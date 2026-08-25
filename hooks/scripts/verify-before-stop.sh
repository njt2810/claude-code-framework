#!/bin/bash
# Verify Before Stop — blocks Claude from finishing if tests fail
# Exit code 2 = force Claude to keep working
# Exit code 0 = let Claude stop

# Payload arrives as JSON on stdin — key the counter by session id so it persists
INPUT=$(cat 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//;s/"$//')

# Explicit handoff: a skill can request an unconditional stop — e.g. /bug-fix
# Step 6, handing control to the user after 2 failed attempts — by dropping
# this marker before ending its turn. That stop is intentional, not a bug
# being left unverified by accident, so it bypasses the test check entirely.
# TTL-bounded (2 min): the marker has no session/project scoping — SESSION_ID
# isn't available to the skill's touch call, only to this hook — so an
# unbounded marker could be consumed by an unrelated Stop event in a different
# session/project if the hook never ran for the turn that created it. A
# legitimate handoff is touched and consumed within the same turn transition
# (seconds), so a short window closes that gap without needing skill-side
# changes. Past the window, treat it as stale garbage and remove it rather
# than honoring it.
VERIFY_COUNTER="${TEMP:-/tmp}/claude-verify-counter-${SESSION_ID:-default}"
HOLD_MARKER="${TEMP:-/tmp}/claude-bugfix-allow-stop"
if [ -f "$HOLD_MARKER" ]; then
  if [ -n "$(find "$HOLD_MARKER" -mmin -2 2>/dev/null)" ]; then
    rm -f "$HOLD_MARKER"
    echo "0" > "$VERIFY_COUNTER"
    exit 0
  fi
  rm -f "$HOLD_MARKER"
fi

# Prevent infinite verification loops using a counter file
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
  # Check if test script exists (portable — no jq, no grep -P; -P fails on Git Bash grep)
  HAS_TEST=$(grep -oE '"test"[[:space:]]*:[[:space:]]*"[^"]*"' package.json 2>/dev/null | head -1 | sed 's/.*"test"[[:space:]]*:[[:space:]]*"//;s/"$//')
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
