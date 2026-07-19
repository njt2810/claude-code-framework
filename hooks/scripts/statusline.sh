#!/bin/bash
# StatusLine v2 — plain English status for operators
# Receives Claude Code JSON on stdin (model, cost, session duration).
# Multi-line output; only shows what's actionable. Empty lines are suppressed.

INPUT=$(cat 2>/dev/null)

# === Dependency guard: without jq, degrade to a minimal statusline ===
if ! command -v jq >/dev/null 2>&1; then
  PROJECT="${PWD##*/}"
  BRANCH=$(git branch --show-current 2>/dev/null)
  echo "${PROJECT}${BRANCH:+  ·  ${BRANCH}}  ·  (install jq for full status)"
  exit 0
fi

# === Stdin: cost + session duration ===
SESSION_COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null || echo "0")
SESSION_DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0' 2>/dev/null || echo "0")
COST_FMT=$(printf "\$%.2f" "$SESSION_COST" 2>/dev/null || echo "\$0.00")

SESSION_MIN=$((SESSION_DURATION_MS / 60000))
if [ "$SESSION_MIN" -ge 60 ]; then
  SESSION_FMT="$((SESSION_MIN/60))h $((SESSION_MIN%60))m"
elif [ "$SESSION_MIN" -gt 0 ]; then
  SESSION_FMT="${SESSION_MIN}m"
else
  SESSION_FMT=""
fi

# === Project + stream ===
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
STREAM=""
if [ -f ".claude/stream" ]; then
  STREAM=$(cat .claude/stream 2>/dev/null | tr -d '[:space:]')
elif [ -f "CLAUDE.md" ]; then
  STREAM=$(grep -i "^stream:" CLAUDE.md 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d '[:space:]')
fi

case "$STREAM" in
  org1|org2)   STREAM_LABEL="production project ($STREAM)"; IS_PRODUCTION=1 ;;
  personal)    STREAM_LABEL="personal project"; IS_PRODUCTION=0 ;;
  learning)    STREAM_LABEL="learning project"; IS_PRODUCTION=0 ;;
  *)           STREAM_LABEL=""; IS_PRODUCTION=0 ;;
esac

# === Safety mode ===
MODE=""
if [ -f ".claude/state/mode.json" ]; then
  MODE_VAL=$(jq -r '.mode // "normal"' .claude/state/mode.json 2>/dev/null)
  if [ -n "$MODE_VAL" ] && [ "$MODE_VAL" != "normal" ]; then
    MODE=$(echo "$MODE_VAL" | tr '[:lower:]' '[:upper:]')
  fi
fi

# === Active timer ===
TIMER_LINE=""
if [ -f ".claude/state/timer.json" ]; then
  # One jq call for all six fields (statusline runs on every render)
  IFS=$'\t' read -r T_ACTIVE T_CLIENT T_NOTE T_MODE T_STARTED T_ACC < <(
    jq -r '[(.active // false), (.client // "?"), (.note // ""), (.mode // "running"), (.started_at // ""), (.accumulated_seconds // 0)] | @tsv' \
      .claude/state/timer.json 2>/dev/null
  )
  if [ "$T_ACTIVE" = "true" ]; then
    if [ "$T_MODE" = "running" ] && [ -n "$T_STARTED" ]; then
      T_START_EPOCH=$(date -d "$T_STARTED" +%s 2>/dev/null || echo "")
      if [ -n "$T_START_EPOCH" ]; then
        T_ELAPSED=$(( $(date +%s) - T_START_EPOCH + T_ACC ))
      else
        # Malformed timestamp — show accumulated time only, never epoch-0 garbage
        T_ELAPSED=$T_ACC
      fi
    else
      T_ELAPSED=$T_ACC
    fi

    T_MIN=$((T_ELAPSED / 60))
    if [ "$T_MIN" -ge 60 ]; then
      T_FMT="$((T_MIN/60))h $((T_MIN%60))m"
    else
      T_FMT="${T_MIN}m"
    fi

    T_PREFIX="⏱"
    [ "$T_MODE" = "paused" ] && T_PREFIX="⏸"
    TIMER_LINE="${T_PREFIX} ${T_CLIENT} · \"${T_NOTE}\" · ${T_FMT}"
  fi
fi

# === Git state ===
GIT_STATE=""
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ]; then
  DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$DIRTY" = "0" ]; then
    GIT_STATE="${BRANCH} · clean"
  elif [ "$DIRTY" = "1" ]; then
    GIT_STATE="${BRANCH} · 1 unsaved change"
  else
    GIT_STATE="${BRANCH} · ${DIRTY} unsaved changes"
  fi
fi

# === PR state (cached 60s, only if gh installed and not on default branch) ===
PR_STATE=""
if command -v gh >/dev/null 2>&1 && [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  PR_CACHE="${TEMP:-/tmp}/claude-pr-${BRANCH//\//_}"
  CACHE_AGE=999
  if [ -f "$PR_CACHE" ]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$PR_CACHE" 2>/dev/null || echo 0) ))
  fi
  if [ "$CACHE_AGE" -lt 60 ]; then
    PR_STATE=$(cat "$PR_CACHE" 2>/dev/null)
  else
    PR_JSON=$(timeout 3 gh pr view --json number,state,statusCheckRollup 2>/dev/null)
    if [ -n "$PR_JSON" ]; then
      PR_NUM=$(echo "$PR_JSON" | jq -r '.number' 2>/dev/null)
      PR_CHECKS=$(echo "$PR_JSON" | jq -r '[.statusCheckRollup[]?.conclusion] | if any(. == "FAILURE") then "failing CI" elif any(. == "PENDING") then "CI running" else "passing" end' 2>/dev/null || echo "open")
      PR_STATE="PR #${PR_NUM} ${PR_CHECKS}"
    fi
    echo "$PR_STATE" > "$PR_CACHE" 2>/dev/null
  fi
fi

# === Lifecycle pipeline (production only) ===
PIPELINE=""
if [ "$IS_PRODUCTION" = "1" ] && [ -d "wiki/features" ]; then
  IN_PROGRESS=$(grep -l "^status: in-progress" wiki/features/*.md 2>/dev/null | wc -l | tr -d ' ')
  IN_REVIEW=$(grep -l "^status: review" wiki/features/*.md 2>/dev/null | wc -l | tr -d ' ')
  [ "$IN_PROGRESS" -gt 0 ] && PIPELINE="${IN_PROGRESS} in progress"
  if [ "$IN_REVIEW" -gt 0 ]; then
    [ -n "$PIPELINE" ] && PIPELINE="${PIPELINE}, "
    PIPELINE="${PIPELINE}${IN_REVIEW} waiting for review"
  fi
fi

# === Compliance gaps (production only) ===
GAPS=""
if [ "$IS_PRODUCTION" = "1" ] && [ -f "wiki/compliance/gaps.md" ]; then
  GAP_COUNT=$(grep -c "^- \[ \]" wiki/compliance/gaps.md 2>/dev/null || echo "0")
  if [ "$GAP_COUNT" = "1" ]; then
    GAPS="⚠ 1 compliance item to fix"
  elif [ "$GAP_COUNT" -gt 0 ]; then
    GAPS="⚠ ${GAP_COUNT} compliance items to fix"
  fi
fi

# === Compose output ===
LINE1="$PROJECT"
[ -n "$STREAM_LABEL" ] && LINE1="${LINE1}  ·  ${STREAM_LABEL}"
[ -n "$MODE" ] && LINE1="${LINE1}  ·  ⚠ ${MODE} MODE ON"
[ -n "$GAPS" ] && LINE1="${LINE1}  ·  ${GAPS}"

LINE2=""
[ -n "$GIT_STATE" ] && LINE2="$GIT_STATE"
[ -n "$PR_STATE" ] && LINE2="${LINE2:+${LINE2}  ·  }${PR_STATE}"
[ -n "$TIMER_LINE" ] && LINE2="${LINE2:+${LINE2}  ·  }${TIMER_LINE}"

LINE3=""
[ -n "$PIPELINE" ] && LINE3="$PIPELINE"
[ -n "$SESSION_FMT" ] && LINE3="${LINE3:+${LINE3}  ·  }Session: ${SESSION_FMT}"
if [ -n "$COST_FMT" ] && [ "$COST_FMT" != "\$0.00" ]; then
  LINE3="${LINE3:+${LINE3}  ·  }${COST_FMT}"
fi

echo "$LINE1"
[ -n "$LINE2" ] && echo "$LINE2"
[ -n "$LINE3" ] && echo "$LINE3"
exit 0
