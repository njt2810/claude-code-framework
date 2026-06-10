#!/bin/bash
# Timed Run — wraps a command with periodic progress output
# Usage: bash timed-run.sh <command> [args...]
# Reports elapsed time every 2 minutes while the command runs

if [ $# -eq 0 ]; then
  echo "Usage: bash timed-run.sh <command> [args...]"
  exit 1
fi

START_TIME=$(date +%s)
echo "Starting: $*"

# Run command in background
"$@" &
PID=$!

# Monitor progress
while kill -0 "$PID" 2>/dev/null; do
  sleep 120
  if kill -0 "$PID" 2>/dev/null; then
    ELAPSED=$(( $(date +%s) - START_TIME ))
    MINS=$((ELAPSED / 60))
    echo "Still running (${MINS}m elapsed)..."
  fi
done

# Capture exit code
wait "$PID"
EXIT_CODE=$?

DURATION=$(( $(date +%s) - START_TIME ))
MINS=$((DURATION / 60))
SECS=$((DURATION % 60))

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "Done (${MINS}m ${SECS}s)"
else
  echo "Failed with exit code $EXIT_CODE (${MINS}m ${SECS}s)"
fi

exit $EXIT_CODE
