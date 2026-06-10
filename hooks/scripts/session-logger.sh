#!/bin/bash
# Session Logger — records every tool use for observability
# Creates a structured log at .claude/session-log.jsonl
# Runs on PostToolUse (async, non-blocking)

INPUT=$(cat)
LOG_FILE=".claude/session-log.jsonl"

# Ensure directory exists
mkdir -p .claude 2>/dev/null

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

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")

# Write log entry
echo "{\"ts\":\"$TIMESTAMP\",\"tool\":\"$TOOL_NAME\",\"target\":\"$FILE_PATH\"}" >> "$LOG_FILE" 2>/dev/null

exit 0
