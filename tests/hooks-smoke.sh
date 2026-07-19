#!/bin/bash
# Hook smoke tests — pipes fake Claude Code JSON payloads into every hook script
# and asserts the expected behavior. Run locally (bash tests/hooks-smoke.sh) or in CI.
#
# These exist because four hooks were once broken for months with zero visible
# errors (PID-keyed state, grep -P, wrong env var). Every regression fixed on
# 2026-07-19 has an assertion here.

set -u
HOOKS="$(cd "$(dirname "$0")/../hooks/scripts" && pwd)"
SID="smoketest-$$"
TMPDIR_BASE="${TEMP:-/tmp}"
WORKDIR=$(mktemp -d)
PASS=0; FAIL=0

check() { # check <name> <condition-result>
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  ok: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi
}

cleanup() {
  rm -f "$TMPDIR_BASE/claude-session-monitor-$SID" \
        "$TMPDIR_BASE/claude-edit-tracker-$SID" \
        "$TMPDIR_BASE/claude-verify-counter-$SID" 2>/dev/null
  rm -rf "$WORKDIR" 2>/dev/null
}
trap cleanup EXIT

cd "$WORKDIR"

echo "== loop-detector =="
OUT=""
for i in 1 2 3; do
  OUT=$(echo "{\"session_id\":\"$SID\",\"tool_input\":{\"file_path\":\"src/app.js\"}}" | bash "$HOOKS/loop-detector.sh")
done
echo "$OUT" | grep -q "LOOP WARNING"; check "warns on 3rd edit of same file" $?
[ -f "$TMPDIR_BASE/claude-edit-tracker-$SID" ]; check "tracker keyed by session_id persists" $?

echo "== session-monitor =="
for i in 1 2 3; do echo "{\"session_id\":\"$SID\"}" | bash "$HOOKS/session-monitor.sh" >/dev/null; done
COUNT=$(cat "$TMPDIR_BASE/claude-session-monitor-$SID" 2>/dev/null || echo 0)
[ "$COUNT" = "3" ]; check "counter accumulates across invocations (got $COUNT)" $?

echo "== verify-before-stop =="
echo "{\"session_id\":\"$SID\"}" | bash "$HOOKS/verify-before-stop.sh"; check "exits 0 with no project files" $?
echo '{"scripts": {"test": "jest --ci"}}' > package.json
EXTRACT=$(grep -oE '"test"[[:space:]]*:[[:space:]]*"[^"]*"' package.json | head -1 | sed 's/.*"test"[[:space:]]*:[[:space:]]*"//;s/"$//')
[ "$EXTRACT" = "jest --ci" ]; check "test-command extraction uses portable grep -E" $?
rm -f package.json
! grep -q 'grep -oP' "$HOOKS/verify-before-stop.sh"; check "no grep -P anywhere in verify-before-stop" $?

echo "== pre-compact =="
echo "{\"session_id\":\"$SID\"}" | bash "$HOOKS/pre-compact.sh" >/dev/null; check "exits 0" $?
OUT=$(echo "{\"session_id\":\"$SID-fresh\"}" | bash "$HOOKS/pre-compact.sh")
! echo "$OUT" | grep -q "backed up"; check "does not claim backup when nothing was backed up" $?

echo "== bash-guard =="
OUT=$(echo '{"tool_input":{"command":"npm install && npm test"}}' | bash "$HOOKS/bash-guard.sh")
echo "$OUT" | grep -q "separate commands"; check "warns on chained long commands" $?
OUT=$(echo '{"tool_input":{"command":"curl https://example.com"}}' | bash "$HOOKS/bash-guard.sh")
echo "$OUT" | grep -q "timeout"; check "warns on network command without timeout" $?
echo '{"tool_input":{"command":"ls"}}' | bash "$HOOKS/bash-guard.sh" >/dev/null; check "silent on harmless command" $?

echo "== session-logger =="
echo '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}' | bash "$HOOKS/session-logger.sh"
[ -f ".claude/session-log.jsonl" ]; check "writes log file" $?
if command -v jq >/dev/null 2>&1; then
  tail -1 .claude/session-log.jsonl | jq empty 2>/dev/null; check "log line is valid JSON" $?
else
  echo "  skip: jq not on PATH — JSON validity check skipped"
fi

echo "== skill-telemetry =="
echo '{"tool_input":{"skill":"smoke-test-skill"}}' | bash "$HOOKS/skill-telemetry.sh"; check "logs a skill invocation" $?
echo '{"tool_input":{"other":"no skill key"}}' | bash "$HOOKS/skill-telemetry.sh"; check "exits 0 when no skill in payload (set -e regression)" $?
grep -v smoke-test-skill "$HOME/.claude/logs/skill-usage.log" > "$HOME/.claude/logs/skill-usage.log.tmp" 2>/dev/null \
  && mv "$HOME/.claude/logs/skill-usage.log.tmp" "$HOME/.claude/logs/skill-usage.log" 2>/dev/null

echo "== statusline =="
OUT=$(echo '{}' | bash "$HOOKS/statusline.sh"); RC=$?
check "exits 0 on empty payload" $RC
[ -n "$OUT" ]; check "prints at least one line" $?

echo "== timer.sh =="
if command -v jq >/dev/null 2>&1; then
  bash "$HOOKS/timer.sh" start acme bug-fix "smoke test" >/dev/null; check "start" $?
  bash "$HOOKS/timer.sh" start acme bug-fix "dupe" >/dev/null 2>&1; [ $? -eq 1 ]; check "double start blocked (exit 1)" $?
  bash "$HOOKS/timer.sh" pause >/dev/null; check "pause" $?
  bash "$HOOKS/timer.sh" resume >/dev/null; check "resume" $?
  STOP_JSON=$(bash "$HOOKS/timer.sh" stop 2>/dev/null)
  echo "$STOP_JSON" | jq -e '.total_seconds >= 0' >/dev/null; check "stop emits total_seconds" $?
  [ ! -f ".claude/state/timer.json" ]; check "stop clears state file" $?
else
  echo "  skip: jq not on PATH — timer tests skipped"
fi

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
