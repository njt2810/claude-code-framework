#!/bin/bash
# Pre-Compact — saves session state before compaction
# Runs on PreCompact hook

BACKUP_DIR="${TEMP:-/tmp}/claude-compact-backup"
mkdir -p "$BACKUP_DIR" 2>/dev/null

TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Save current session counter
COUNTER_FILE="${TEMP:-/tmp}/claude-session-monitor-$$"
if [ -f "$COUNTER_FILE" ]; then
  cp "$COUNTER_FILE" "$BACKUP_DIR/session-counter-$TIMESTAMP" 2>/dev/null
fi

# Save edit tracker (for loop detection continuity)
EDIT_LOG="${TEMP:-/tmp}/claude-edit-tracker-$$"
if [ -f "$EDIT_LOG" ]; then
  cp "$EDIT_LOG" "$BACKUP_DIR/edit-tracker-$TIMESTAMP" 2>/dev/null
fi

echo "Session state backed up before compaction."
echo "REMINDER: After compaction, you are the Lead Engineer. Your team: Code Reviewer, Test Engineer, Wiki Updater, Security Auditor, Knowledge Agent."

exit 0
