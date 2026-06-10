#!/usr/bin/env bash
# Skill invocation telemetry — logs skill usage to JSONL file.
# Wired as a PostToolUse hook on Skill tool calls.
# Reads tool_input from stdin to extract the skill name.

set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/skill-usage.log"
MAX_SIZE=10485760  # 10MB

mkdir -p "$LOG_DIR"

# Read hook input from stdin
INPUT=$(cat)

# Extract skill name from the hook input
SKILL_NAME=$(echo "$INPUT" | grep -oE '"skill"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"skill"\s*:\s*"//;s/".*//')

if [ -z "$SKILL_NAME" ]; then
  exit 0
fi

# Detect project name from current directory
PROJECT_NAME=$(basename "$(pwd)" 2>/dev/null || echo "unknown")

# Log rotation: if file exceeds 10MB, rotate
if [ -f "$LOG_FILE" ]; then
  FILE_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    [ -f "${LOG_FILE}.2" ] && mv "${LOG_FILE}.2" "${LOG_FILE}.3"
    [ -f "${LOG_FILE}.1" ] && mv "${LOG_FILE}.1" "${LOG_FILE}.2"
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
fi

# Write JSONL line
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")
echo "{\"timestamp\":\"$TIMESTAMP\",\"skill\":\"$SKILL_NAME\",\"project\":\"$PROJECT_NAME\"}" >> "$LOG_FILE"
