#!/bin/bash
# StatusLine — live project monitoring at the bottom of Claude Code

# Project info
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
STREAM="unknown"
if [ -f ".claude/stream" ]; then
  STREAM=$(cat .claude/stream 2>/dev/null)
elif [ -f "CLAUDE.md" ]; then
  STREAM=$(grep "Stream:" CLAUDE.md 2>/dev/null | head -1 | awk '{print $NF}')
fi

# Git status
BRANCH=$(git branch --show-current 2>/dev/null || echo "no-git")
CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ' 2>/dev/null || echo "0")
LAST_COMMIT=$(git log -1 --format='%cr' 2>/dev/null || echo "never")

# Session health (from session monitor counter)
COUNTER_FILE="${TEMP:-/tmp}/claude-session-monitor-$$"
TURNS=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")

if [ "$TURNS" -gt 30 ]; then
  CTX="heavy"
elif [ "$TURNS" -gt 15 ]; then
  CTX="moderate"
else
  CTX="fresh"
fi

# Learned skills count — without find (use ls)
LEARNED=0
if [ -d ".claude/skills/learned" ]; then
  LEARNED=$(ls .claude/skills/learned/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ' 2>/dev/null || echo "0")
fi

# Loop incidents (from loop detector log)
EDIT_LOG="${TEMP:-/tmp}/claude-edit-tracker-$$"
LOOP_COUNT=0
if [ -f "$EDIT_LOG" ]; then
  LOOP_COUNT=$(sort "$EDIT_LOG" 2>/dev/null | uniq -c | awk '$1 >= 3 {count++} END {print count+0}' 2>/dev/null || echo "0")
fi

# Build the status line
STATUS="${PROJECT}"

if [ "$STREAM" != "unknown" ]; then
  STATUS="${STATUS} (${STREAM})"
fi

STATUS="${STATUS} | ${BRANCH} +${CHANGES}"
STATUS="${STATUS} | ctx:${CTX}"
STATUS="${STATUS} | ${LEARNED} skills"

if [ "$LOOP_COUNT" -gt 0 ]; then
  STATUS="${STATUS} | ${LOOP_COUNT} loops"
fi

STATUS="${STATUS} | ${LAST_COMMIT}"

echo "$STATUS"
