#!/bin/bash
# Progress Monitor — wraps long-running commands with logging and error detection
# Usage: bash progress-monitor.sh "command to run"

COMMAND="$*"
LOG_FILE="${TEMP:-/tmp}/claude-progress-log-$$"
START_TIME=$(date +%s)

echo "━━━ ⏳ PROCESS STARTED ━━━━━━━━━━━━━━━━━━━━━━━" | tee "$LOG_FILE"
echo "  Command: $COMMAND" | tee -a "$LOG_FILE"
echo "  Started: $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"

# Run command, capture output line by line
eval "$COMMAND" 2>&1 | while IFS= read -r line; do
  ELAPSED=$(( $(date +%s) - START_TIME ))
  echo "[${ELAPSED}s] $line" | tee -a "$LOG_FILE"

  # Error detection
  if echo "$line" | grep -qiE "error|exception|failed|traceback|ENOENT|permission denied|fatal"; then
    echo "" | tee -a "$LOG_FILE"
    echo "━━━ ❌ ERROR DETECTED at ${ELAPSED}s ━━━━━━━━━━━" | tee -a "$LOG_FILE"
    echo "  $line" | tee -a "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
  fi

  # Progress update every 60 seconds
  if [ $((ELAPSED % 60)) -eq 0 ] && [ "$ELAPSED" -gt 0 ]; then
    echo "[${ELAPSED}s] ⏳ Still running..." | tee -a "$LOG_FILE"
  fi
done

EXIT_CODE=${PIPESTATUS[0]}
DURATION=$(( $(date +%s) - START_TIME ))

echo "" | tee -a "$LOG_FILE"
if [ "$EXIT_CODE" -ne 0 ]; then
  echo "━━━ ❌ PROCESS FAILED ━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
  echo "  Exit code: $EXIT_CODE" | tee -a "$LOG_FILE"
  echo "  Duration: ${DURATION}s" | tee -a "$LOG_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
else
  echo "━━━ ✅ PROCESS COMPLETE ━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
  echo "  Duration: ${DURATION}s" | tee -a "$LOG_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOG_FILE"
fi

exit $EXIT_CODE
