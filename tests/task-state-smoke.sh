#!/bin/bash
# Task-state smoke tests — real invocations of scripts/team/task-state.sh,
# asserted with a check() helper, run from an isolated mktemp -d working
# directory and cleaned up on exit. Mirrors tests/hooks-smoke.sh's pattern.
#
# These exist to prove BUILD_PLAN.md Part 1.2's acceptance line directly:
#   "dependencies block premature dispatch; only the local task-state script
#    accepts completion; invalid transitions fail; project state is isolated."
# Each clause has a dedicated section below, not just a description of it.

set -u
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/team/task-state.sh"
PASS=0; FAIL=0

check() { # check <name> <exit-code-as-string>
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  ok: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH — task-state.sh is jq-dependent by design, cannot run these tests"
  exit 0
fi

STATE_FILE=".claude/state/team-tasks.json"
checksum() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

WORKDIR=$(mktemp -d)
ISO_A=""; ISO_B=""
cleanup() { rm -rf "$WORKDIR" "$ISO_A" "$ISO_B" 2>/dev/null; }
trap cleanup EXIT
cd "$WORKDIR" || exit 1

echo "== missing jq dependency =="
REAL_BASH=$(command -v bash)
NO_JQ_DIR=$(mktemp -d)
OUT=$(PATH="$NO_JQ_DIR" "$REAL_BASH" "$SCRIPT" list 2>&1); RC=$?
[ "$RC" = "2" ]; check "missing jq exits 2 (got $RC)" $?
echo "$OUT" | grep -qi "jq is required"; check "missing jq prints a clear message" $?
rm -rf "$NO_JQ_DIR"

echo "== create =="
bash "$SCRIPT" create task-a "First task" >/dev/null 2>&1
check "create task-a" $?
bash "$SCRIPT" create task-b "Second task" --depends task-a >/dev/null 2>&1
check "create task-b depends on task-a" $?
bash "$SCRIPT" create task-c "Planned-only task" >/dev/null 2>&1
check "create task-c" $?
echo "$(bash "$SCRIPT" status task-b)" | jq -e '.depends_on == ["task-a"]' >/dev/null
check "task-b depends_on recorded as [\"task-a\"]" $?
echo "$(bash "$SCRIPT" status task-c)" | jq -e '.risk == "medium" and .budget == 2' >/dev/null
check "defaults applied: risk=medium budget=2 when unspecified" $?

echo "== dependencies block premature dispatch (core acceptance criterion) =="
OUT=$(bash "$SCRIPT" start task-b 2>&1); RC=$?
[ "$RC" != "0" ]; check "start task-b fails while task-a is still planned (exit $RC)" $?
echo "$OUT" | grep -q "task-a"; check "error names the unmet dependency (task-a)" $?
STATE_B=$(bash "$SCRIPT" status task-b | jq -r '.state')
[ "$STATE_B" = "planned" ]; check "task-b remains in 'planned' after the blocked start attempt" $?

echo "== full lifecycle on task-a: start -> check -> complete =="
bash "$SCRIPT" start task-a >/dev/null 2>&1
check "start task-a" $?
bash "$SCRIPT" check task-a >/dev/null 2>&1
check "check task-a" $?
bash "$SCRIPT" complete task-a >/dev/null 2>&1
check "complete task-a" $?
echo "$(bash "$SCRIPT" status task-a)" | jq -e '.state == "done"' >/dev/null
check "task-a state is done" $?

echo "== history accumulates across transitions =="
HIST_LEN=$(bash "$SCRIPT" status task-a | jq '.history | length')
[ "$HIST_LEN" = "4" ]; check "task-a history has 4 entries (create+start+check+complete), got $HIST_LEN" $?
FROM_TO=$(bash "$SCRIPT" status task-a | jq -r '.history | map("\(.from // "null")>\(.to)") | join(",")')
[ "$FROM_TO" = "null>planned,planned>building,building>checking,checking>done" ]
check "history from/to sequence is correct (got: $FROM_TO)" $?

echo "== dependency satisfied: start task-b now succeeds =="
bash "$SCRIPT" start task-b >/dev/null 2>&1
check "start task-b succeeds once task-a is done" $?

echo "== invalid transition: complete on a 'planned' task =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" complete task-c 2>&1); RC=$?
[ "$RC" != "0" ]; check "complete on planned task fails (exit $RC)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ]; check "state file checksum unchanged after rejected complete" $?

echo "== invalid transition: check on a 'done' task =="
bash "$SCRIPT" create task-e "Full-lifecycle task" >/dev/null 2>&1
bash "$SCRIPT" start task-e >/dev/null 2>&1
bash "$SCRIPT" check task-e >/dev/null 2>&1
bash "$SCRIPT" complete task-e >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" check task-e 2>&1); RC=$?
[ "$RC" != "0" ]; check "check on a done task fails (exit $RC)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ]; check "state file checksum unchanged after rejected check" $?

echo "== invalid transition: unblock on a task that isn't blocked =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" unblock task-c 2>&1); RC=$?
[ "$RC" != "0" ]; check "unblock on a non-blocked task fails (exit $RC)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ]; check "state file checksum unchanged after rejected unblock" $?

echo "== invalid transition: start on a nonexistent id =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" start does-not-exist 2>&1); RC=$?
[ "$RC" != "0" ]; check "start on nonexistent id fails (exit $RC)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ]; check "state file checksum unchanged after rejected start on missing id" $?

echo "== create fails if a listed dependency doesn't exist =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" create task-g "Depends on ghost" --depends does-not-exist 2>&1); RC=$?
[ "$RC" != "0" ]; check "create with a missing dependency fails (exit $RC)" $?
echo "$OUT" | grep -q "does-not-exist"; check "error names the missing dependency" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ]; check "state file checksum unchanged after rejected create (missing dep)" $?

echo "== duplicate create fails, original task untouched =="
BEFORE_TITLE=$(bash "$SCRIPT" status task-a | jq -r '.title')
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" create task-a "Different title" 2>&1); RC=$?
[ "$RC" != "0" ]; check "creating an already-existing id fails (exit $RC)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ]; check "state file checksum unchanged after rejected duplicate create" $?
AFTER_TITLE=$(bash "$SCRIPT" status task-a | jq -r '.title')
[ "$BEFORE_TITLE" = "$AFTER_TITLE" ]; check "original task-a title untouched (still: $AFTER_TITLE)" $?

echo "== block then unblock restores the pre-block state =="
bash "$SCRIPT" create task-f "Blockable task" >/dev/null 2>&1
bash "$SCRIPT" start task-f >/dev/null 2>&1   # now 'building'
OUT=$(bash "$SCRIPT" block task-f "waiting on external API key" --resume-condition "key provisioned" 2>&1); RC=$?
check "block task-f from 'building'" $RC
STATE_F=$(bash "$SCRIPT" status task-f)
echo "$STATE_F" | jq -e '.state == "blocked"' >/dev/null; check "task-f state is blocked" $?
echo "$STATE_F" | jq -e '.blocked_from == "building"' >/dev/null; check "blocked_from recorded as building" $?
echo "$STATE_F" | jq -e '.blocked_reason == "waiting on external API key"' >/dev/null; check "blocked_reason recorded" $?
echo "$STATE_F" | jq -e '.resume_condition == "key provisioned"' >/dev/null; check "resume_condition recorded" $?

OUT=$(bash "$SCRIPT" unblock task-f 2>&1); RC=$?
check "unblock task-f" $RC
STATE_F=$(bash "$SCRIPT" status task-f)
echo "$STATE_F" | jq -e '.state == "building"' >/dev/null; check "unblock restores 'building' (the pre-block state)" $?

echo "== list output =="
LIST_OUT=$(bash "$SCRIPT" list)
echo "$LIST_OUT" | grep -q "task-a"; check "list includes task-a" $?
echo "$LIST_OUT" | grep -q "depends_on"; check "list shows depends_on" $?

echo "== status on unknown id =="
bash "$SCRIPT" status no-such-task >/dev/null 2>&1; RC=$?
[ "$RC" != "0" ]; check "status on unknown id fails (exit $RC)" $?

echo "== project isolation =="
ISO_A=$(mktemp -d)
ISO_B=$(mktemp -d)

( cd "$ISO_A" && bash "$SCRIPT" create iso-only-in-a "A's task" >/dev/null 2>&1 )
check "create task in isolated dir A" $?

OUT_B_LIST=$(cd "$ISO_B" && bash "$SCRIPT" list 2>&1)
! echo "$OUT_B_LIST" | grep -q "iso-only-in-a"
check "task created in dir A is invisible via 'list' in dir B" $?

OUT_B_STATUS=$(cd "$ISO_B" && bash "$SCRIPT" status iso-only-in-a 2>&1); RC=$?
[ "$RC" != "0" ]; check "'status' for A's task from dir B returns not-found (exit $RC)" $?

( cd "$ISO_B" && bash "$SCRIPT" create iso-only-in-a "B's own version" >/dev/null 2>&1 )
check "dir B can independently create a task with the same id (no cross-contamination)" $?

TITLE_A=$(cd "$ISO_A" && bash "$SCRIPT" status iso-only-in-a | jq -r '.title')
TITLE_B=$(cd "$ISO_B" && bash "$SCRIPT" status iso-only-in-a | jq -r '.title')
[ "$TITLE_A" = "A's task" ] && [ "$TITLE_B" = "B's own version" ]
check "each dir keeps its own independent record for the same id (A=$TITLE_A, B=$TITLE_B)" $?

! bash "$SCRIPT" list 2>&1 | grep -q "iso-only-in-a"
check "main WORKDIR project state unaffected by isolated-dir tasks" $?

echo "== flag given without its value must error, not hang (regression: create --depends used to spin forever) =="
if command -v timeout >/dev/null 2>&1; then
  OUT=$(timeout 5 bash "$SCRIPT" create no-val-task "No value task" --depends 2>&1); RC=$?
  [ "$RC" != "124" ]; check "create --depends with no trailing value does not hang (exit $RC, 124=timeout)" $?
  [ "$RC" = "2" ]; check "create --depends with no trailing value exits 2 (got $RC)" $?
  echo "$OUT" | grep -qi -- "--depends"; check "error names the missing --depends value" $?
  bash "$SCRIPT" status no-val-task >/dev/null 2>&1; RC2=$?
  [ "$RC2" != "0" ]; check "task was not created when its flag value was missing (bad usage exits before any write)" $?

  bash "$SCRIPT" create blockable-novalue "Blockable task" >/dev/null 2>&1
  OUT=$(timeout 5 bash "$SCRIPT" block blockable-novalue "some reason" --resume-condition 2>&1); RC=$?
  [ "$RC" != "124" ]; check "block --resume-condition with no trailing value does not hang (exit $RC, 124=timeout)" $?
  [ "$RC" = "2" ]; check "block --resume-condition with no trailing value exits 2 (got $RC)" $?
  echo "$OUT" | grep -qi -- "--resume-condition"; check "error names the missing --resume-condition value" $?
  STATE_BN=$(bash "$SCRIPT" status blockable-novalue | jq -r '.state')
  [ "$STATE_BN" = "planned" ]; check "task state unchanged after rejected block with missing flag value (got $STATE_BN)" $?
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely test the missing-flag-value hang regression"
fi

echo "== builder/verifier default to JSON null, not empty string, when unspecified =="
bash "$SCRIPT" create task-h "No builder/verifier" >/dev/null 2>&1
STATE_H=$(bash "$SCRIPT" status task-h)
echo "$STATE_H" | jq -e '.builder == null' >/dev/null; check "builder defaults to null when unspecified" $?
echo "$STATE_H" | jq -e '.verifier == null' >/dev/null; check "verifier defaults to null when unspecified" $?
bash "$SCRIPT" create task-i "With builder/verifier" --builder alice --verifier bob >/dev/null 2>&1
STATE_I=$(bash "$SCRIPT" status task-i)
echo "$STATE_I" | jq -e '.builder == "alice" and .verifier == "bob"' >/dev/null; check "builder/verifier recorded when given" $?

echo "== concurrent creates: no lost updates (regression: atomic_update's read-modify-write raced without a lock) =="
if command -v timeout >/dev/null 2>&1; then
  CONC_DIR=$(mktemp -d)
  timeout 60 bash -c '
    SCRIPT="$1"; DIR="$2"; N="$3"
    PIDS=()
    for i in $(seq 1 "$N"); do
      ( cd "$DIR" && bash "$SCRIPT" create "conc-task-$i" "Concurrent task $i" >/dev/null 2>&1 ) &
      PIDS+=("$!")
    done
    for pid in "${PIDS[@]}"; do wait "$pid"; done
  ' _ "$SCRIPT" "$CONC_DIR" 20
  RC=$?
  [ "$RC" != "124" ]; check "20 concurrent creates complete without deadlocking on the lock (exit $RC, 124=timeout)" $?
  CONC_COUNT=$(jq '.tasks | length' "$CONC_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$CONC_COUNT" = "20" ]; check "20 concurrent creates against the same state file yield exactly 20 tasks, not fewer (got ${CONC_COUNT:-0})" $?
  rm -rf "$CONC_DIR"
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely bound the concurrency regression test"
fi

echo "== Part 1.6: .claude/state/ gitignore warning on record-evidence =="
if ! command -v git >/dev/null 2>&1; then
  echo "  SKIP: git not on PATH — cannot exercise the gitignore-warning check"
else
  echo "-- .claude/state/ NOT gitignored: warning printed, command still succeeds --"
  WARN_DIR=$(mktemp -d)
  ( cd "$WARN_DIR" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
  ( cd "$WARN_DIR" && bash "$SCRIPT" create warn-task "Warn task" ) >/dev/null 2>&1
  echo "real artifact" > "$WARN_DIR/warn-artifact.txt"
  echo "real output" > "$WARN_DIR/warn-output.txt"
  ERR_OUT=$(cd "$WARN_DIR" && bash "$SCRIPT" record-evidence warn-task --command "echo hi" --exit-code 0 \
    --tests-total 1 --tests-skipped 0 --output-file warn-output.txt --artifact warn-artifact.txt 2>&1 1>/dev/null)
  RC=$?
  check "record-evidence still exits 0 when .claude/state/ is not gitignored (no hard failure from the warning)" $RC
  echo "$ERR_OUT" | grep -qi "not excluded from 'git status'"; check "warning printed to stderr when .claude/state/ is not gitignored" $?
  echo "$ERR_OUT" | grep -qi "stale"; check "warning names the spurious-staleness risk" $?
  rm -rf "$WARN_DIR"

  echo "-- .claude/state/ IS gitignored: no warning (no regression) --"
  OK_DIR=$(mktemp -d)
  ( cd "$OK_DIR" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
  echo ".claude/state/" > "$OK_DIR/.gitignore"
  ( cd "$OK_DIR" && git add .gitignore && git commit -qm init ) >/dev/null 2>&1
  ( cd "$OK_DIR" && bash "$SCRIPT" create ok-task "OK task" ) >/dev/null 2>&1
  echo "real artifact" > "$OK_DIR/ok-artifact.txt"
  echo "real output" > "$OK_DIR/ok-output.txt"
  ERR_OUT=$(cd "$OK_DIR" && bash "$SCRIPT" record-evidence ok-task --command "echo hi" --exit-code 0 \
    --tests-total 1 --tests-skipped 0 --output-file ok-output.txt --artifact ok-artifact.txt 2>&1 1>/dev/null)
  RC=$?
  check "record-evidence exits 0 when .claude/state/ is gitignored" $RC
  [ -z "$ERR_OUT" ]; check "no warning printed to stderr when .claude/state/ is already gitignored (got: $ERR_OUT)" $?
  rm -rf "$OK_DIR"

  echo "-- not inside a git repository at all: no warning, no crash --"
  NOGIT_DIR=$(mktemp -d)
  ( cd "$NOGIT_DIR" && bash "$SCRIPT" create nogit-task "No-git task" ) >/dev/null 2>&1
  echo "real artifact" > "$NOGIT_DIR/nogit-artifact.txt"
  echo "real output" > "$NOGIT_DIR/nogit-output.txt"
  ERR_OUT=$(cd "$NOGIT_DIR" && bash "$SCRIPT" record-evidence nogit-task --command "echo hi" --exit-code 0 \
    --tests-total 1 --tests-skipped 0 --output-file nogit-output.txt --artifact nogit-artifact.txt 2>&1 1>/dev/null)
  RC=$?
  check "record-evidence exits 0 outside a git repository (no crash)" $RC
  [ -z "$ERR_OUT" ]; check "no warning printed to stderr outside a git repository (got: $ERR_OUT)" $?
  SNAP=$(cd "$NOGIT_DIR" && bash "$SCRIPT" status nogit-task | jq -r '.evidence[-1].code_snapshot')
  [ "$SNAP" = "no-git-repository" ]; check "code_snapshot correctly records no-git-repository outside a git repo (got: $SNAP)" $?
  rm -rf "$NOGIT_DIR"
fi

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
