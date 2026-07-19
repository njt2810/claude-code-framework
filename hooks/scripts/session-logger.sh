#!/bin/bash
# Session Logger — records every tool use for observability
# Creates a structured log at .claude/session-log.jsonl
# Runs on PostToolUse (async, non-blocking)

INPUT=$(cat)
LOG_FILE=".claude/session-log.jsonl"
MAX_SIZE=10485760  # 10MB — same rotation policy as skill-telemetry.sh

# Ensure directory exists
mkdir -p .claude 2>/dev/null

# Log rotation: if file exceeds 10MB, rotate (keep 3 generations)
if [ -f "$LOG_FILE" ]; then
  FILE_SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    [ -f "${LOG_FILE}.2" ] && mv "${LOG_FILE}.2" "${LOG_FILE}.3"
    [ -f "${LOG_FILE}.1" ] && mv "${LOG_FILE}.1" "${LOG_FILE}.2"
    mv "$LOG_FILE" "${LOG_FILE}.1"
  fi
fi

# Extract tool info (portable — no jq, no grep -P)
TOOL_NAME=$(echo "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"//;s/"$//')
if [ -z "$TOOL_NAME" ]; then
  TOOL_NAME="unknown"
fi

# Extract file_path or command from tool_input
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//' | head -c 100)
if [ -z "$FILE_PATH" ]; then
  FILE_PATH=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//' | head -c 100)
fi
if [ -z "$FILE_PATH" ]; then
  FILE_PATH="n/a"
fi

# JSON-escape extracted values so embedded backslashes/quotes can't corrupt the log
TOOL_NAME=${TOOL_NAME//\\/\\\\}; TOOL_NAME=${TOOL_NAME//\"/\\\"}
FILE_PATH=${FILE_PATH//\\/\\\\}; FILE_PATH=${FILE_PATH//\"/\\\"}

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")

# Write log entry
echo "{\"ts\":\"$TIMESTAMP\",\"tool\":\"$TOOL_NAME\",\"target\":\"$FILE_PATH\"}" >> "$LOG_FILE" 2>/dev/null

exit 0
