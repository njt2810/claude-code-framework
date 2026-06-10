#!/bin/bash
# Verify Before Stop — blocks Claude from finishing if tests fail
# Exit code 2 = force Claude to keep working
# Exit code 0 = let Claude stop

# Prevent infinite verification loops using a counter file
VERIFY_COUNTER="${TEMP:-/tmp}/claude-verify-counter-$$"
if [ ! -f "$VERIFY_COUNTER" ]; then
  echo "0" > "$VERIFY_COUNTER"
fi

COUNT=$(cat "$VERIFY_COUNTER" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$VERIFY_COUNTER"

# After 3 blocks, stop forcing — prevent infinite loop
if [ "$COUNT" -gt 3 ]; then
  echo "0" > "$VERIFY_COUNTER"
  exit 0
fi

# Detect test command from common project configurations
TEST_CMD=""

if [ -f "package.json" ]; then
  # Check if test script exists (without jq — use grep)
  HAS_TEST=$(grep -oP '"test"\s*:\s*"[^"]*"' package.json 2>/dev/null | head -1 | sed 's/.*"test"\s*:\s*"//;s/"$//')
  if [ -n "$HAS_TEST" ] && ! echo "$HAS_TEST" | grep -q "no test specified"; then
    TEST_CMD="npm test -- --watchAll=false 2>&1"
  fi
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  if command -v pytest &>/dev/null; then
    TEST_CMD="pytest --tb=short -q 2>&1"
  fi
fi

# If no test command found, let Claude stop
if [ -z "$TEST_CMD" ]; then
  echo "0" > "$VERIFY_COUNTER"
  exit 0
fi

# Check if any source files were modified (not just docs/config)
CHANGES=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(py|js|ts|jsx|tsx|mjs|cjs)$' | head -1)
if [ -z "$CHANGES" ]; then
  echo "0" > "$VERIFY_COUNTER"
  exit 0
fi

# Run tests
TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
TEST_EXIT=$?

if [ $TEST_EXIT -ne 0 ]; then
  echo "Tests are failing. Fix them before finishing:" >&2
  echo "$TEST_OUTPUT" | tail -20 >&2
  exit 2
fi

# Tests passed — reset counter and let Claude stop
echo "0" > "$VERIFY_COUNTER"
exit 0
