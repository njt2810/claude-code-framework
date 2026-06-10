#!/bin/bash
# Session Summary — generates observability metrics when session ends
# Runs on Stop hook, produces a summary from the session log

LOG_FILE=".claude/session-log.jsonl"

# Only run if session log exists
if [ ! -f "$LOG_FILE" ]; then
  exit 0
fi

# Count total tool uses
TOTAL=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')

# Count edits (most expensive action)
EDITS=$(grep -cE '"tool":"(Edit|Write|MultiEdit)"' "$LOG_FILE" 2>/dev/null || echo "0")

# Count unique files touched (portable — no jq)
FILES=$(grep -oE '"target":"[^"]*"' "$LOG_FILE" 2>/dev/null | sort -u | grep -cv '"target":"n/a"' 2>/dev/null || echo "0")

# Count bash commands
BASH_COUNT=$(grep -c '"tool":"Bash"' "$LOG_FILE" 2>/dev/null || echo "0")

# Detect most-edited files (portable — no jq)
MOST_EDITED=$(grep -oE '"target":"[^"]*"' "$LOG_FILE" 2>/dev/null | sed 's/"target":"//;s/"$//' | grep -v "n/a" | sort | uniq -c | sort -rn | head -3)

# Only show summary if significant work was done
if [ "$TOTAL" -gt 10 ]; then
  echo ""
  echo "SESSION METRICS"
  echo "  Tool uses:     $TOTAL"
  echo "  File edits:    $EDITS"
  echo "  Files touched: $FILES"
  echo "  Commands run:  $BASH_COUNT"
  echo ""
  echo "  Most active files:"
  echo "$MOST_EDITED" | head -3 | while read -r count file; do
    [ -n "$count" ] && echo "    ${count}x  $file"
  done
fi

exit 0
