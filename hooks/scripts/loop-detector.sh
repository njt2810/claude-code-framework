#!/bin/bash
# Loop Detector — warns after 3+ edits to the same file
# Runs on PostToolUse hook (matcher: Edit|Write)

FILE_PATH="$CLAUDE_FILE_PATH"
EDIT_LOG="${TEMP:-/tmp}/claude-edit-tracker-$$"

if [ -n "$FILE_PATH" ]; then
  echo "$FILE_PATH" >> "$EDIT_LOG"

  if [ -f "$EDIT_LOG" ]; then
    EDIT_COUNT=$(grep -c "$FILE_PATH" "$EDIT_LOG" 2>/dev/null || echo "0")

    if [ "$EDIT_COUNT" -ge 3 ]; then
      echo ""
      echo "━━━ ⚠️ LOOP WARNING ━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  $FILE_PATH edited $EDIT_COUNT times this session."
      echo ""
      echo "  Before editing again, explain:"
      echo "  1. What was wrong with your previous approach?"
      echo "  2. Why will this attempt be different?"
      echo "  3. Would /rewind give a cleaner starting point?"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
  fi
fi
