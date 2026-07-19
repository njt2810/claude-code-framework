#!/bin/bash
# Loop Detector — warns after 3+ edits to the same file
# Runs on PostToolUse hook (matcher: Edit|Write)
# Payload arrives as JSON on stdin — portable parsing, no jq, no grep -P

INPUT=$(cat 2>/dev/null)

FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
SESSION_ID=$(echo "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//;s/"$//')

# Key the tracker by session id so it persists across hook invocations
EDIT_LOG="${TEMP:-/tmp}/claude-edit-tracker-${SESSION_ID:-default}"

if [ -n "$FILE_PATH" ]; then
  echo "$FILE_PATH" >> "$EDIT_LOG"

  EDIT_COUNT=$(grep -cF "$FILE_PATH" "$EDIT_LOG" 2>/dev/null || echo "0")

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

exit 0
