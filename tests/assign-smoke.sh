#!/bin/bash
# Assignment-recording smoke tests — real invocations of scripts/team/assign.sh
# (and the task-state.sh record-assignment subcommand it drives), asserted with
# a check() helper, run from an isolated mktemp -d working directory and
# cleaned up on exit. Mirrors tests/task-state-smoke.sh's pattern.
#
# These exist to prove the half of BUILD_PLAN.md Part 1.3's acceptance line
# that is actually this part's own deliverable (the other half —
# "independently caught by the completion-gate script's file-change check" —
# is Part 1.4's deliverable, not built yet; see BUILD_PLAN.md's Part 1.3
# status line):
#   "recorded assignments and loaded skill revisions ... verifier receives
#    the agreed requirements and code snapshot."
# Each clause has a dedicated section below, not just a description of it.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSIGN="$REPO_ROOT/scripts/team/assign.sh"
TASK_STATE="$REPO_ROOT/scripts/team/task-state.sh"
PASS=0; FAIL=0

check() { # check <name> <exit-code-as-string>
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  ok: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH — assign.sh is jq-dependent by design, cannot run these tests"
  exit 0
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "SKIP: sha256sum not on PATH — assign.sh needs it to hash skill files, cannot run these tests"
  exit 0
fi

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR" 2>/dev/null; }
trap cleanup EXIT
cd "$WORKDIR" || exit 1

bash "$TASK_STATE" create part-x "A test part" >/dev/null 2>&1

echo "== builder assignment is durably recorded (agent type, skill hash, timestamp) =="
mkdir -p skills/alpha
echo "alpha skill v1" > skills/alpha/SKILL.md
OUT=$(bash "$ASSIGN" part-x --role builder --agent-type team-builder --skills skills/alpha/SKILL.md 2>&1); RC=$?
check "assign.sh exits 0 for a valid builder assignment" $RC
echo "$OUT" | grep -q "RECORDED-ASSIGNMENT part-x role=builder"; check "assign.sh reports the recorded assignment" $?
echo "$OUT" | grep -q "BRIEFING"; check "assign.sh prints a briefing block" $?

ASSIGNMENT=$(bash "$TASK_STATE" status part-x | jq '.assignments[-1]')
echo "$ASSIGNMENT" | jq -e '.role == "builder"' >/dev/null; check "recorded assignment role is builder" $?
echo "$ASSIGNMENT" | jq -e '.agent_type == "team-builder"' >/dev/null; check "recorded assignment agent_type is team-builder" $?
echo "$ASSIGNMENT" | jq -e '.skills[0].path == "skills/alpha/SKILL.md"' >/dev/null; check "recorded assignment skill path present" $?
EXPECTED_HASH=$(sha256sum skills/alpha/SKILL.md | awk '{print $1}')
RECORDED_HASH=$(echo "$ASSIGNMENT" | jq -r '.skills[0].sha256')
[ "$RECORDED_HASH" = "$EXPECTED_HASH" ]; check "recorded skill hash matches sha256sum of the file (got $RECORDED_HASH)" $?
echo "$ASSIGNMENT" | jq -e '.assigned_at | length > 0' >/dev/null; check "recorded assignment has a non-empty timestamp" $?

echo "== verifier assignment captures acceptance criteria and a code snapshot identity =="
if command -v git >/dev/null 2>&1; then
  GITCHECK="$WORKDIR/gitcheck"
  mkdir -p "$GITCHECK"
  # .claude/state/ must be gitignored here the same way the real repo
  # gitignores it (see .gitignore) -- otherwise task-state.sh's own state
  # file shows up as an untracked change and every snapshot looks "dirty",
  # which would test this script's git plumbing, not its snapshot logic.
  ( cd "$GITCHECK" && git init -q && git config user.email t@t.test && git config user.name t \
      && echo ".claude/state/" > .gitignore && echo x > f \
      && git add f .gitignore && git commit -qm init ) >/dev/null 2>&1
  COMMITTED_SHA=$(cd "$GITCHECK" && git rev-parse --short HEAD)
  ( cd "$GITCHECK" && bash "$TASK_STATE" create part-y "Another test part" ) >/dev/null 2>&1

  OUT=$(cd "$GITCHECK" && bash "$ASSIGN" part-y --role verifier --agent-type team-verifier --acceptance-text "criterion one; criterion two" 2>&1); RC=$?
  check "assign.sh exits 0 for a valid verifier assignment (clean tree)" $RC
  ASSIGNMENT_Y=$(cd "$GITCHECK" && bash "$TASK_STATE" status part-y | jq '.assignments[-1]')
  echo "$ASSIGNMENT_Y" | jq -e '.role == "verifier"' >/dev/null; check "recorded assignment role is verifier" $?
  echo "$ASSIGNMENT_Y" | jq -e --arg t "criterion one; criterion two" '.acceptance_criteria == $t' >/dev/null
  check "recorded acceptance_criteria text matches what was supplied" $?
  CS_Y=$(echo "$ASSIGNMENT_Y" | jq -r '.code_snapshot')
  [ "$CS_Y" = "$COMMITTED_SHA" ]; check "code snapshot on a clean tree is the short commit SHA (got $CS_Y, expected $COMMITTED_SHA)" $?

  echo "-- dirty tree: code snapshot records 'uncommitted, base SHA X, diff Y' --"
  echo "dirty change" >> "$GITCHECK/f"
  OUT=$(cd "$GITCHECK" && bash "$ASSIGN" part-y --role verifier --agent-type team-verifier --acceptance-text "criterion three" 2>&1); RC=$?
  check "assign.sh exits 0 for a valid verifier assignment (dirty tree)" $RC
  ASSIGNMENT_Y2=$(cd "$GITCHECK" && bash "$TASK_STATE" status part-y | jq '.assignments[-1]')
  CS_Y2=$(echo "$ASSIGNMENT_Y2" | jq -r '.code_snapshot')
  case "$CS_Y2" in
    "uncommitted, base SHA $COMMITTED_SHA, diff "*) DIRTY_FORMAT_OK=0 ;;
    *) DIRTY_FORMAT_OK=1 ;;
  esac
  check "dirty-tree code snapshot recorded as 'uncommitted, base SHA <sha>, diff <hash>' (got: $CS_Y2)" $DIRTY_FORMAT_OK
  DIFF_HASH_Y2="${CS_Y2##*, diff }"
  [ -n "$DIFF_HASH_Y2" ] && [ "$DIFF_HASH_Y2" != "$CS_Y2" ]
  check "dirty-tree snapshot's diff-hash suffix is non-empty (got: $DIFF_HASH_Y2)" $?

  echo "-- dirty tree, DIFFERENT content: diff-hash suffix changes even though base SHA and clean/dirty flag do not --"
  echo "different dirty change, not the same content as before" > "$GITCHECK/f"
  OUT=$(cd "$GITCHECK" && bash "$ASSIGN" part-y --role verifier --agent-type team-verifier --acceptance-text "criterion four" 2>&1); RC=$?
  check "assign.sh exits 0 for a valid verifier assignment (differently-dirty tree)" $RC
  ASSIGNMENT_Y3=$(cd "$GITCHECK" && bash "$TASK_STATE" status part-y | jq '.assignments[-1]')
  CS_Y3=$(echo "$ASSIGNMENT_Y3" | jq -r '.code_snapshot')
  DIFF_HASH_Y3="${CS_Y3##*, diff }"
  [ "$DIFF_HASH_Y3" != "$DIFF_HASH_Y2" ]
  check "two materially different dirty trees off the same base commit produce DIFFERENT snapshot strings (got: $CS_Y2 vs $CS_Y3)" $?
else
  echo "  SKIP: git not on PATH, cannot test code-snapshot identity"
fi

echo "== --acceptance-file is read and recorded verbatim =="
printf 'criterion from a file, line 1\ncriterion from a file, line 2\n' > acceptance.txt
bash "$ASSIGN" part-x --role verifier --agent-type team-verifier --acceptance-file acceptance.txt >/dev/null 2>&1
check "assign.sh accepts --acceptance-file" $?
# Compared with \r stripped on both sides: the state file itself stores the
# value correctly as a JSON-escaped \n (verified directly against the raw
# file bytes during development) -- but on this platform's jq build, `jq -r`
# writes its stdout in text mode, which turns embedded LF into CRLF on the
# way OUT of jq. That's a jq-on-Windows stdout quirk in this readback step,
# not a data-integrity bug, and tr -d '\r' is a no-op everywhere else.
RECORDED_TEXT=$(bash "$TASK_STATE" status part-x | jq -r '.assignments[-1].acceptance_criteria' | tr -d '\r')
FILE_TEXT=$(cat acceptance.txt | tr -d '\r')
[ "$RECORDED_TEXT" = "$FILE_TEXT" ]; check "recorded acceptance_criteria matches --acceptance-file content" $?

echo "== verifier assignment without any acceptance criteria fails, and nothing is recorded =="
COUNT_BEFORE=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
OUT=$(bash "$ASSIGN" part-x --role verifier --agent-type team-verifier 2>&1); RC=$?
[ "$RC" != "0" ]; check "verifier assignment with no acceptance criteria fails (exit $RC)" $?
echo "$OUT" | grep -qi "acceptance"; check "error message mentions acceptance criteria" $?
COUNT_AFTER=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
[ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; check "no assignment was recorded on the rejected verifier call ($COUNT_BEFORE -> $COUNT_AFTER)" $?

echo "== --acceptance-file and --acceptance-text together is rejected =="
bash "$ASSIGN" part-x --role verifier --agent-type team-verifier --acceptance-file acceptance.txt --acceptance-text "x" >/dev/null 2>&1; RC=$?
[ "$RC" != "0" ]; check "giving both --acceptance-file and --acceptance-text fails (exit $RC)" $?

echo "== skill-hash correctness: changing a skill file's content changes its recorded hash =="
mkdir -p skills/beta
echo "beta skill v1" > skills/beta/SKILL.md
bash "$ASSIGN" part-x --role builder --agent-type team-builder --skills skills/beta/SKILL.md >/dev/null 2>&1
HASH_V1=$(bash "$TASK_STATE" status part-x | jq -r '.assignments[-1].skills[0].sha256')

echo "beta skill v2 -- content changed" > skills/beta/SKILL.md
bash "$ASSIGN" part-x --role builder --agent-type team-builder --skills skills/beta/SKILL.md >/dev/null 2>&1
HASH_V2=$(bash "$TASK_STATE" status part-x | jq -r '.assignments[-1].skills[0].sha256')

[ -n "$HASH_V1" ] && [ -n "$HASH_V2" ]; check "both hash recordings are non-empty" $?
[ "$HASH_V1" != "$HASH_V2" ]; check "recorded hash changes after the skill file's content changes ($HASH_V1 != $HASH_V2)" $?
EXPECTED_V2=$(sha256sum skills/beta/SKILL.md | awk '{print $1}')
[ "$HASH_V2" = "$EXPECTED_V2" ]; check "post-change recorded hash matches sha256sum of the current file content" $?

echo "== assigning a skill path that doesn't exist fails cleanly, nothing recorded =="
COUNT_BEFORE=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
OUT=$(bash "$ASSIGN" part-x --role builder --agent-type team-builder --skills skills/does-not-exist.md 2>&1); RC=$?
[ "$RC" != "0" ]; check "assigning a missing skill file fails (exit $RC)" $?
echo "$OUT" | grep -q "skills/does-not-exist.md"; check "error names the missing skill file" $?
COUNT_AFTER=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
[ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; check "no assignment recorded when a listed skill file is missing ($COUNT_BEFORE -> $COUNT_AFTER)" $?

echo "== a colon-containing skill path is rejected, not silently mis-parsed (regression) =="
# Windows absolute paths (e.g. "C:/fakepath/skill.md") are realistic input on
# this project's primary platform. task-state.sh record-assignment's
# "path:hash,path:hash,..." format is parsed by splitting on the FIRST
# colon, so a colon-containing path used to silently corrupt into garbage
# (path="C", sha256="/fakepath/skill.md:deadbeef") instead of failing. Skill
# paths in this repo are always relative POSIX-style paths (see
# skills/*/SKILL.md) and must never contain a colon. Exercised at both entry
# points: assign.sh (the normal caller, which now rejects before ever
# computing a hash) and task-state.sh record-assignment directly (defense in
# depth, in case something bypasses assign.sh).
COUNT_BEFORE=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
OUT=$(bash "$ASSIGN" part-x --role builder --agent-type team-builder --skills "C:/fakepath/skill.md" 2>&1); RC=$?
[ "$RC" != "0" ]; check "assign.sh rejects a colon-containing skill path (exit $RC)" $?
echo "$OUT" | grep -qi "colon"; check "assign.sh error mentions a colon" $?
COUNT_AFTER=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
[ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; check "no assignment recorded when assign.sh rejects a colon-containing skill path ($COUNT_BEFORE -> $COUNT_AFTER)" $?

COUNT_BEFORE=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
OUT=$(bash "$TASK_STATE" record-assignment part-x --role builder --agent-type t --skill-hash "C:/fakepath/skill.md:deadbeef" 2>&1); RC=$?
[ "$RC" != "0" ]; check "task-state.sh record-assignment rejects a colon-containing skill path directly (exit $RC)" $?
echo "$OUT" | grep -qi "colon"; check "task-state.sh record-assignment error mentions a colon" $?
COUNT_AFTER=$(bash "$TASK_STATE" status part-x | jq '.assignments | length')
[ "$COUNT_BEFORE" = "$COUNT_AFTER" ]; check "no assignment recorded when task-state.sh rejects a colon-containing skill path directly ($COUNT_BEFORE -> $COUNT_AFTER)" $?

echo "== assigning against a nonexistent part ID fails cleanly (reuses task-state.sh's own not-found behavior) =="
OUT=$(bash "$ASSIGN" no-such-part --role builder --agent-type team-builder 2>&1); RC=$?
[ "$RC" != "0" ]; check "assign.sh on a nonexistent part fails (exit $RC)" $?
echo "$OUT" | grep -qi "not found"; check "error surfaces task-state.sh's own not-found message" $?

echo "== bad usage: missing --role, invalid --role, missing --agent-type =="
bash "$ASSIGN" part-x --agent-type team-builder >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ]; check "missing --role exits 2 (got $RC)" $?
bash "$ASSIGN" part-x --role bogus --agent-type team-builder >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ]; check "invalid --role value exits 2 (got $RC)" $?
bash "$ASSIGN" part-x --role builder >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ]; check "missing --agent-type exits 2 (got $RC)" $?

echo "== concurrent record-assignment calls on the same task: no lost updates =="
# This exercises a different jq operation (appending to the per-task
# 'assignments' array under lock) than task-state-smoke.sh's own concurrency
# test (creating distinct top-level task keys) -- not fully redundant with
# it, so it earns its place here rather than just padding the suite.
if command -v timeout >/dev/null 2>&1; then
  bash "$TASK_STATE" create part-conc "Concurrent assignment target" >/dev/null 2>&1
  timeout 60 bash -c '
    ASSIGN="$1"; N="$2"
    PIDS=()
    for i in $(seq 1 "$N"); do
      ( bash "$ASSIGN" part-conc --role builder --agent-type "builder-$i" >/dev/null 2>&1 ) &
      PIDS+=("$!")
    done
    for pid in "${PIDS[@]}"; do wait "$pid"; done
  ' _ "$ASSIGN" 20
  RC=$?
  [ "$RC" != "124" ]; check "20 concurrent record-assignment calls complete without deadlocking (exit $RC, 124=timeout)" $?
  CONC_COUNT=$(bash "$TASK_STATE" status part-conc | jq '.assignments | length')
  [ "$CONC_COUNT" = "20" ]
  check "20 concurrent assignments on the same task yield exactly 20 recorded entries, not fewer (got ${CONC_COUNT:-0})" $?
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely bound the concurrency regression test"
fi

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
