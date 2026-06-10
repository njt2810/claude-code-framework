#!/bin/bash
# Session Monitor — nudges for learning, compaction, and exit
# Runs on Stop hook (after every Claude response)

COUNTER_FILE="${TEMP:-/tmp}/claude-session-monitor-$$"

# Initialize
if [ ! -f "$COUNTER_FILE" ]; then
  echo "0" > "$COUNTER_FILE"
fi

# Increment
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Learning nudge every ~20 turns
if [ $((COUNT % 20)) -eq 0 ] && [ "$COUNT" -gt 0 ]; then
  echo ""
  echo "━━━ 💡 LEARNING CHECK ━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ~${COUNT} turns of work done."
  echo "  Worth capturing a reusable pattern? → /learn"
  echo "  Or keep building → ignore this"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Compaction nudge every ~30 turns
if [ $((COUNT % 30)) -eq 0 ] && [ "$COUNT" -gt 20 ]; then
  echo ""
  echo "━━━ 🧹 CONTEXT CHECK ━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Session is getting long (~${COUNT} turns)."
  echo "  Consider: /compact to clean context"
  echo "  Or: /clear if switching tasks"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Identity reinforcement every ~25 turns
if [ $((COUNT % 25)) -eq 0 ] && [ "$COUNT" -gt 10 ]; then
  echo ""
  echo "IDENTITY: You are the Lead Engineer."
  echo "Your team: Code Reviewer, Test Engineer, Wiki Updater, Security Auditor, Knowledge Agent."
  echo "Delegate to them — present their findings to the user in plain language."
fi

# Commit reminder (check uncommitted changes)
if [ $((COUNT % 25)) -eq 0 ] && [ "$COUNT" -gt 10 ]; then
  CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ' 2>/dev/null || echo "0")
  if [ "$CHANGES" -gt 5 ] 2>/dev/null; then
    echo ""
    echo "━━━ 📌 COMMIT REMINDER ━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ${CHANGES} uncommitted changes."
    echo "  Consider committing to save progress."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi
fi
