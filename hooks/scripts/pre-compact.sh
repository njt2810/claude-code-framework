#!/bin/bash
# Pre-Compact — saves session state before compaction
# Runs on PreCompact hook

BACKUP_DIR="${TEMP:-/tmp}/claude-compact-backup"
mkdir -p "$BACKUP_DIR" 2>/dev/null

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Payload arrives as JSON on stdin — same session-id keying as the other hooks
INPUT=$(cat 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//;s/"$//')

BACKED_UP=0

# Save current session counter
COUNTER_FILE="${TEMP:-/tmp}/claude-session-monitor-${SESSION_ID:-default}"
if [ -f "$COUNTER_FILE" ]; then
  cp "$COUNTER_FILE" "$BACKUP_DIR/session-counter-$TIMESTAMP" 2>/dev/null && BACKED_UP=1
fi

# Save edit tracker (for loop detection continuity)
EDIT_LOG="${TEMP:-/tmp}/claude-edit-tracker-${SESSION_ID:-default}"
if [ -f "$EDIT_LOG" ]; then
  cp "$EDIT_LOG" "$BACKUP_DIR/edit-tracker-$TIMESTAMP" 2>/dev/null && BACKED_UP=1
fi

if [ "$BACKED_UP" = "1" ]; then
  echo "Session state backed up before compaction."
fi
# Identity reload is handled by the SessionStart "compact" hook in settings.json —
# no duplicate reminder here.

exit 0
