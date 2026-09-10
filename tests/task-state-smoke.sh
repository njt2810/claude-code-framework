#!/bin/bash
# Task-state smoke tests — real invocations of scripts/team/task-state.sh,
# asserted with a check() helper, run from an isolated mktemp -d working
# directory and cleaned up on exit. Mirrors tests/hooks-smoke.sh's pattern.
#
# These exist to prove BUILD_PLAN.md Part 1.2's acceptance line directly:
#   "dependencies block premature dispatch; only the local task-state script
#    accepts completion; invalid transitions fail; project state is isolated."
# Each clause has a dedicated section below, not just a description of it.

#
# The Part 2.1 sections at the end additionally prove that part's acceptance
# line:
#   "restart restores the exact next action and checks current code;
#    completed external actions are not repeated."
# Both halves of the first clause get their own assertions (the exact
# next-action text AND the code check, in BOTH the drift and no-drift
# directions -- asserting only one direction would prove nothing about
# whether the check actually discriminates).

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/team/task-state.sh"
GATE="$REPO_ROOT/scripts/team/complete-gate.sh"
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
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "missing jq exits 2 (got $RC)" $RC_CHK
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
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "start task-b fails while task-a is still planned (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "task-a"; check "error names the unmet dependency (task-a)" $?
STATE_B=$(bash "$SCRIPT" status task-b | jq -r '.state')
[ "$STATE_B" = "planned" ] && RC_CHK=0 || RC_CHK=1; check "task-b remains in 'planned' after the blocked start attempt" $RC_CHK

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
[ "$HIST_LEN" = "4" ] && RC_CHK=0 || RC_CHK=1; check "task-a history has 4 entries (create+start+check+complete), got $HIST_LEN" $RC_CHK
FROM_TO=$(bash "$SCRIPT" status task-a | jq -r '.history | map("\(.from // "null")>\(.to)") | join(",")')
[ "$FROM_TO" = "null>planned,planned>building,building>checking,checking>done" ] && RC_CHK=0 || RC_CHK=1
check "history from/to sequence is correct (got: $FROM_TO)" $RC_CHK

echo "== dependency satisfied: start task-b now succeeds =="
bash "$SCRIPT" start task-b >/dev/null 2>&1
check "start task-b succeeds once task-a is done" $?

echo "== invalid transition: complete on a 'planned' task =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" complete task-c 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete on planned task fails (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected complete" $RC_CHK

echo "== invalid transition: check on a 'done' task =="
bash "$SCRIPT" create task-e "Full-lifecycle task" >/dev/null 2>&1
bash "$SCRIPT" start task-e >/dev/null 2>&1
bash "$SCRIPT" check task-e >/dev/null 2>&1
bash "$SCRIPT" complete task-e >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" check task-e 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "check on a done task fails (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected check" $RC_CHK

echo "== invalid transition: unblock on a task that isn't blocked =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" unblock task-c 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "unblock on a non-blocked task fails (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected unblock" $RC_CHK

echo "== invalid transition: start on a nonexistent id =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" start does-not-exist 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "start on nonexistent id fails (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected start on missing id" $RC_CHK

echo "== create fails if a listed dependency doesn't exist =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" create task-g "Depends on ghost" --depends does-not-exist 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "create with a missing dependency fails (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "does-not-exist"; check "error names the missing dependency" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected create (missing dep)" $RC_CHK

echo "== duplicate create fails, original task untouched =="
BEFORE_TITLE=$(bash "$SCRIPT" status task-a | jq -r '.title')
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" create task-a "Different title" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "creating an already-existing id fails (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected duplicate create" $RC_CHK
AFTER_TITLE=$(bash "$SCRIPT" status task-a | jq -r '.title')
[ "$BEFORE_TITLE" = "$AFTER_TITLE" ] && RC_CHK=0 || RC_CHK=1; check "original task-a title untouched (still: $AFTER_TITLE)" $RC_CHK

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
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "status on unknown id fails (exit $RC)" $RC_CHK

echo "== project isolation =="
ISO_A=$(mktemp -d)
ISO_B=$(mktemp -d)

( cd "$ISO_A" && bash "$SCRIPT" create iso-only-in-a "A's task" >/dev/null 2>&1 )
check "create task in isolated dir A" $?

OUT_B_LIST=$(cd "$ISO_B" && bash "$SCRIPT" list 2>&1)
! echo "$OUT_B_LIST" | grep -q "iso-only-in-a"
check "task created in dir A is invisible via 'list' in dir B" $?

( cd "$ISO_B" && bash "$SCRIPT" status iso-only-in-a >/dev/null 2>&1 ); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "'status' for A's task from dir B returns not-found (exit $RC)" $RC_CHK

( cd "$ISO_B" && bash "$SCRIPT" create iso-only-in-a "B's own version" >/dev/null 2>&1 )
check "dir B can independently create a task with the same id (no cross-contamination)" $?

TITLE_A=$(cd "$ISO_A" && bash "$SCRIPT" status iso-only-in-a | jq -r '.title')
TITLE_B=$(cd "$ISO_B" && bash "$SCRIPT" status iso-only-in-a | jq -r '.title')
[ "$TITLE_A" = "A's task" ] && [ "$TITLE_B" = "B's own version" ] && RC_CHK=0 || RC_CHK=1
check "each dir keeps its own independent record for the same id (A=$TITLE_A, B=$TITLE_B)" $RC_CHK

! bash "$SCRIPT" list 2>&1 | grep -q "iso-only-in-a"
check "main WORKDIR project state unaffected by isolated-dir tasks" $?

echo "== flag given without its value must error, not hang (regression: create --depends used to spin forever) =="
if command -v timeout >/dev/null 2>&1; then
  OUT=$(timeout 5 bash "$SCRIPT" create no-val-task "No value task" --depends 2>&1); RC=$?
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "create --depends with no trailing value does not hang (exit $RC, 124=timeout)" $RC_CHK
  [ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "create --depends with no trailing value exits 2 (got $RC)" $RC_CHK
  echo "$OUT" | grep -qi -- "--depends"; check "error names the missing --depends value" $?
  bash "$SCRIPT" status no-val-task >/dev/null 2>&1; RC2=$?
  [ "$RC2" != "0" ] && RC_CHK=0 || RC_CHK=1; check "task was not created when its flag value was missing (bad usage exits before any write)" $RC_CHK

  bash "$SCRIPT" create blockable-novalue "Blockable task" >/dev/null 2>&1
  OUT=$(timeout 5 bash "$SCRIPT" block blockable-novalue "some reason" --resume-condition 2>&1); RC=$?
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "block --resume-condition with no trailing value does not hang (exit $RC, 124=timeout)" $RC_CHK
  [ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "block --resume-condition with no trailing value exits 2 (got $RC)" $RC_CHK
  echo "$OUT" | grep -qi -- "--resume-condition"; check "error names the missing --resume-condition value" $?
  STATE_BN=$(bash "$SCRIPT" status blockable-novalue | jq -r '.state')
  [ "$STATE_BN" = "planned" ] && RC_CHK=0 || RC_CHK=1; check "task state unchanged after rejected block with missing flag value (got $STATE_BN)" $RC_CHK
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
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "20 concurrent creates complete without deadlocking on the lock (exit $RC, 124=timeout)" $RC_CHK
  CONC_COUNT=$(jq '.tasks | length' "$CONC_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$CONC_COUNT" = "20" ] && RC_CHK=0 || RC_CHK=1
  check "20 concurrent creates against the same state file yield exactly 20 tasks, not fewer (got ${CONC_COUNT:-0})" $RC_CHK
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
  [ -z "$ERR_OUT" ] && RC_CHK=0 || RC_CHK=1; check "no warning printed to stderr when .claude/state/ is already gitignored (got: $ERR_OUT)" $RC_CHK
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
  [ -z "$ERR_OUT" ] && RC_CHK=0 || RC_CHK=1; check "no warning printed to stderr outside a git repository (got: $ERR_OUT)" $RC_CHK
  SNAP=$(cd "$NOGIT_DIR" && bash "$SCRIPT" status nogit-task | jq -r '.evidence[-1].code_snapshot')
  [ "$SNAP" = "no-git-repository" ] && RC_CHK=0 || RC_CHK=1
  check "code_snapshot correctly records no-git-repository outside a git repo (got: $SNAP)" $RC_CHK
  rm -rf "$NOGIT_DIR"
fi

echo "== Part 2.1: pause records a checkpoint; resume restores the exact prior state =="
NEXT_1="finish resume)'s drift branch, then run tests/task-state-smoke.sh"
bash "$SCRIPT" create task-p "Pausable task" >/dev/null 2>&1
bash "$SCRIPT" start task-p >/dev/null 2>&1   # now 'building'
OUT=$(bash "$SCRIPT" pause task-p --next-action "$NEXT_1" 2>&1); RC=$?
check "pause task-p from 'building'" $RC
STATE_P=$(bash "$SCRIPT" status task-p)
echo "$STATE_P" | jq -e '.state == "paused"' >/dev/null; check "task-p state is paused" $?
echo "$STATE_P" | jq -e '.paused_from == "building"' >/dev/null; check "paused_from recorded as building" $?
echo "$STATE_P" | jq -e '.checkpoints | length == 1' >/dev/null; check "exactly one checkpoint appended by pause" $?
echo "$STATE_P" | jq -e --arg n "$NEXT_1" '.checkpoints[-1].next_action == $n' >/dev/null
check "checkpoint holds the EXACT next-action text" $?
echo "$STATE_P" | jq -e '.checkpoints[-1].paused_from == "building"' >/dev/null; check "checkpoint records paused_from" $?
echo "$STATE_P" | jq -e '(.checkpoints[-1].code_snapshot | type == "string" and length > 0)' >/dev/null
check "checkpoint holds a non-empty code snapshot" $?
echo "$STATE_P" | jq -e '(.checkpoints[-1].paused_at | type == "string" and length > 0)' >/dev/null
check "checkpoint holds a paused_at timestamp" $?

OUT=$(bash "$SCRIPT" resume task-p 2>&1); RC=$?
check "resume task-p" $RC
STATE_P=$(bash "$SCRIPT" status task-p)
echo "$STATE_P" | jq -e '.state == "building"' >/dev/null; check "resume restores exactly 'building' (the pre-pause state)" $?
echo "$STATE_P" | jq -e '.paused_from == null' >/dev/null; check "paused_from cleared after resume" $?
grep -qF -- "$NEXT_1" <<< "$OUT"; check "resume output contains the EXACT recorded next-action string" $?
echo "$STATE_P" | jq -e '.checkpoints | length == 1' >/dev/null; check "resume does not destroy the checkpoint it read" $?
# The drift verdict must be DURABLE, not just printed -- see task-state.sh's
# resume contract, point 3. (This WORKDIR is not a git repo, so both
# snapshots are "no-git-repository" and the verdict is deterministically
# no-drift; the genuine drift/no-drift discrimination is asserted in the
# git-backed section further below.)
echo "$STATE_P" | jq -e '.history[-1].drift_detected == false' >/dev/null
check "resume durably records its drift verdict in the history entry (drift_detected=false)" $?
echo "$STATE_P" | jq -e '(.history[-1].pause_snapshot | type == "string" and length > 0)
  and (.history[-1].resume_snapshot | type == "string" and length > 0)' >/dev/null
check "resume's history entry carries both pause_snapshot and resume_snapshot" $?

echo "== Part 2.1: rejected pause/resume attempts leave the state file byte-for-byte unchanged =="
echo "-- pause with no --next-action at all --"
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" pause task-p 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "pause without --next-action exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--next-action"; check "error names the required --next-action flag" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after pause with no --next-action" $RC_CHK
STATE_PP=$(bash "$SCRIPT" status task-p | jq -r '.state')
[ "$STATE_PP" = "building" ] && RC_CHK=0 || RC_CHK=1; check "task-p still 'building' after the rejected pause (got $STATE_PP)" $RC_CHK

echo "-- pause on a 'done' task --"
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" pause task-a --next-action "should never be recorded" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "pause on a done task fails (exit $RC)" $RC_CHK
echo "$OUT" | grep -qF -- "state 'done'"; check "error names the offending state (done)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected pause on done task" $RC_CHK

echo "-- pause on an already-paused task --"
bash "$SCRIPT" pause task-p --next-action "temporary pause for the double-pause test" >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" pause task-p --next-action "second pause, must be refused" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "pause on an already-paused task fails (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "already paused"; check "error says the task is already paused" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected double pause" $RC_CHK
bash "$SCRIPT" resume task-p >/dev/null 2>&1   # back to 'building'

echo "-- pause on a 'blocked' task --"
bash "$SCRIPT" create task-pb "Blocked-then-pause task" >/dev/null 2>&1
bash "$SCRIPT" start task-pb >/dev/null 2>&1
bash "$SCRIPT" block task-pb "waiting on something" >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" pause task-pb --next-action "must be refused" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "pause on a blocked task fails (exit $RC)" $RC_CHK
echo "$OUT" | grep -qF -- "state 'blocked'"; check "error names the offending state (blocked)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected pause on blocked task" $RC_CHK

echo "-- resume on a task that isn't paused --"
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" resume task-c 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "resume on a non-paused task fails (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "not paused"; check "error says the task is not paused" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after rejected resume" $RC_CHK

echo "-- resume on a nonexistent id --"
CS1=$(checksum "$STATE_FILE")
bash "$SCRIPT" resume no-such-task-at-all >/dev/null 2>&1; RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "resume on a nonexistent id fails (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after resume on missing id" $RC_CHK

echo "-- pause --next-action given with no trailing value must error, not hang --"
if command -v timeout >/dev/null 2>&1; then
  CS1=$(checksum "$STATE_FILE")
  OUT=$(timeout 5 bash "$SCRIPT" pause task-p --next-action 2>&1); RC=$?
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "pause --next-action with no trailing value does not hang (exit $RC, 124=timeout)" $RC_CHK
  [ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "pause --next-action with no trailing value exits 2 (got $RC)" $RC_CHK
  echo "$OUT" | grep -qi -- "--next-action"; check "error names the missing --next-action value" $?
  CS2=$(checksum "$STATE_FILE")
  [ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after pause with missing flag value" $RC_CHK
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely test the missing-flag-value hang regression for pause"
fi

echo "== Part 2.1: checkpoints accumulate across two pause/resume cycles =="
NEXT_A="cycle one: implement record-external-action"
NEXT_B="cycle two: implement check-external-action"
bash "$SCRIPT" create task-cp "Two-cycle task" >/dev/null 2>&1
bash "$SCRIPT" start task-cp >/dev/null 2>&1
bash "$SCRIPT" pause task-cp --next-action "$NEXT_A" >/dev/null 2>&1
check "cycle 1: pause task-cp" $?
bash "$SCRIPT" resume task-cp >/dev/null 2>&1
check "cycle 1: resume task-cp" $?
bash "$SCRIPT" pause task-cp --next-action "$NEXT_B" >/dev/null 2>&1
check "cycle 2: pause task-cp" $?
bash "$SCRIPT" resume task-cp >/dev/null 2>&1
check "cycle 2: resume task-cp" $?
CP_LEN=$(bash "$SCRIPT" status task-cp | jq '.checkpoints | length')
[ "$CP_LEN" = "2" ] && RC_CHK=0 || RC_CHK=1; check "two pause/resume cycles leave exactly 2 checkpoints (got $CP_LEN)" $RC_CHK
bash "$SCRIPT" status task-cp | jq -e --arg a "$NEXT_A" --arg b "$NEXT_B" \
  '(.checkpoints[0].next_action == $a) and (.checkpoints[1].next_action == $b)' >/dev/null
check "both next-action texts are present, in pause order (oldest first)" $?
STATE_CP=$(bash "$SCRIPT" status task-cp | jq -r '.state')
[ "$STATE_CP" = "building" ] && RC_CHK=0 || RC_CHK=1; check "task-cp back in 'building' after the second resume (got $STATE_CP)" $RC_CHK

echo "== Part 2.1: resume CHECKS CURRENT CODE — both directions (no-drift and drift) =="
if ! command -v git >/dev/null 2>&1; then
  echo "  SKIP: git not on PATH — compute_snapshot needs it, cannot exercise the code-drift check"
else
  DRIFT_DIR=$(mktemp -d)
  ( cd "$DRIFT_DIR" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
  # .claude/state/ MUST be gitignored here, or task-state.sh's own writes
  # would themselves move the snapshot and manufacture fake "drift".
  echo ".claude/state/" > "$DRIFT_DIR/.gitignore"
  echo "original content" > "$DRIFT_DIR/tracked.txt"
  ( cd "$DRIFT_DIR" && git add .gitignore tracked.txt && git commit -qm init ) >/dev/null 2>&1

  echo "-- direction 1: code UNCHANGED while paused --"
  ( cd "$DRIFT_DIR" && bash "$SCRIPT" create nodrift "No-drift task" && bash "$SCRIPT" start nodrift ) >/dev/null 2>&1
  ( cd "$DRIFT_DIR" && bash "$SCRIPT" pause nodrift --next-action "resume with the code untouched" ) >/dev/null 2>&1
  ND_PAUSE_SNAP=$(cd "$DRIFT_DIR" && bash "$SCRIPT" status nodrift | jq -r '.checkpoints[-1].code_snapshot')
  ND_OUT=$(cd "$DRIFT_DIR" && bash "$SCRIPT" resume nodrift 2>&1); RC=$?
  check "resume succeeds when the code is unchanged" $RC
  echo "$ND_OUT" | grep -q "CODE CHECK: OK"; check "no-drift resume states explicitly that the code is unchanged" $?
  echo "$ND_OUT" | grep -qi "unchanged since the pause"; check "no-drift message says 'unchanged since the pause' in plain words" $?
  echo "$ND_OUT" | grep -qF -- "$ND_PAUSE_SNAP"; check "no-drift message names the snapshot ($ND_PAUSE_SNAP)" $?
  ! echo "$ND_OUT" | grep -qi "WARNING"; check "no drift warning is printed when the code really did not change" $?
  # ...and the verdict is durably recorded, not only printed: stdout can be
  # swallowed by a pipe, and only durably-recorded state counts here.
  ND_HIST=$(cd "$DRIFT_DIR" && bash "$SCRIPT" status nodrift | jq -c '.history[-1]')
  echo "$ND_HIST" | jq -e '.from == "paused" and .to == "building"' >/dev/null
  check "no-drift: the last history entry is the resume transition (got: $ND_HIST)" $?
  echo "$ND_HIST" | jq -e '.drift_detected == false' >/dev/null
  check "no-drift: history entry records drift_detected=false" $?
  echo "$ND_HIST" | jq -e --arg s "$ND_PAUSE_SNAP" '.pause_snapshot == $s' >/dev/null
  check "no-drift: history entry records the pause-time snapshot ($ND_PAUSE_SNAP)" $?
  echo "$ND_HIST" | jq -e --arg s "$ND_PAUSE_SNAP" '.resume_snapshot == $s' >/dev/null
  check "no-drift: history entry records a resume_snapshot equal to the pause one" $?
  echo "$ND_HIST" | jq -e '.pause_snapshot == .resume_snapshot' >/dev/null
  check "no-drift: the false verdict is re-derivable from the two persisted snapshots alone" $?

  echo "-- direction 2: tracked file GENUINELY MODIFIED while paused --"
  ( cd "$DRIFT_DIR" && bash "$SCRIPT" pause nodrift --next-action "re-check the parser before editing it" ) >/dev/null 2>&1
  D_PAUSE_SNAP=$(cd "$DRIFT_DIR" && bash "$SCRIPT" status nodrift | jq -r '.checkpoints[-1].code_snapshot')
  # A real, uncommitted edit to a tracked file — exactly the situation the
  # code check exists for.
  echo "someone edited this while the task was paused" >> "$DRIFT_DIR/tracked.txt"
  D_OUT=$(cd "$DRIFT_DIR" && bash "$SCRIPT" resume nodrift 2>&1); RC=$?
  check "resume still SUCCEEDS on drift (drift is surfaced, not a refusal to resume)" $RC
  D_STATE=$(cd "$DRIFT_DIR" && bash "$SCRIPT" status nodrift | jq -r '.state')
  [ "$D_STATE" = "building" ] && RC_CHK=0 || RC_CHK=1; check "drifted resume still restores 'building' (got $D_STATE)" $RC_CHK
  echo "$D_OUT" | grep -qi "CODE CHANGED WHILE THIS TASK WAS PAUSED"; check "drift resume warns prominently that the code changed" $?
  echo "$D_OUT" | grep -qi "may no longer be valid"; check "drift warning says the recorded next action may no longer be valid" $?
  echo "$D_OUT" | grep -qF -- "$D_PAUSE_SNAP"; check "drift warning names the snapshot recorded at pause ($D_PAUSE_SNAP)" $?
  echo "$D_OUT" | grep -q "snapshot now:"; check "drift warning also names the current snapshot" $?
  # Pull the current-snapshot value back out of the printed line and compare
  # it to the pause-time one, so this asserts two genuinely different values
  # were named rather than just that two labels were printed.
  D_NOW_SNAP=$(echo "$D_OUT" | sed -n 's/^ *snapshot now: *//p' | tr -d '\r')
  echo "$D_NOW_SNAP" | grep -qi "uncommitted"; check "current snapshot reflects the uncommitted edit (got: $D_NOW_SNAP)" $?
  [ -n "$D_NOW_SNAP" ] && [ "$D_PAUSE_SNAP" != "$D_NOW_SNAP" ] && RC_CHK=0 || RC_CHK=1
  check "the two named snapshots genuinely differ ('$D_PAUSE_SNAP' vs '$D_NOW_SNAP')" $RC_CHK
  echo "$D_OUT" | grep -qF -- "re-check the parser before editing it"; check "drift resume still prints the exact recorded next action" $?
  # ...and, again, the verdict is durably recorded. Cross-check the persisted
  # resume_snapshot against the value scraped out of the PRINTED warning, so
  # this asserts the record matches what the caller was actually told rather
  # than merely that some string was stored.
  D_HIST=$(cd "$DRIFT_DIR" && bash "$SCRIPT" status nodrift | jq -c '.history[-1]')
  echo "$D_HIST" | jq -e '.from == "paused" and .to == "building"' >/dev/null
  check "drift: the last history entry is the resume transition" $?
  echo "$D_HIST" | jq -e '.drift_detected == true' >/dev/null
  check "drift: history entry records drift_detected=true" $?
  echo "$D_HIST" | jq -e --arg s "$D_PAUSE_SNAP" '.pause_snapshot == $s' >/dev/null
  check "drift: history entry records the pause-time snapshot ($D_PAUSE_SNAP)" $?
  echo "$D_HIST" | jq -e --arg s "$D_NOW_SNAP" '.resume_snapshot == $s' >/dev/null
  check "drift: persisted resume_snapshot matches the one printed in the warning ($D_NOW_SNAP)" $?
  echo "$D_HIST" | jq -e '.pause_snapshot != .resume_snapshot' >/dev/null
  check "drift: the true verdict is re-derivable from the two persisted snapshots alone" $?
  # The two directions must write DIFFERENT booleans -- asserting only one
  # would prove nothing about whether the persisted field discriminates.
  ND_FLAG=$(echo "$ND_HIST" | jq -r '.drift_detected' | tr -d '\r')
  D_FLAG=$(echo "$D_HIST" | jq -r '.drift_detected' | tr -d '\r')
  [ "$ND_FLAG" = "false" ] && [ "$D_FLAG" = "true" ] && RC_CHK=0 || RC_CHK=1
  check "the persisted drift_detected field genuinely discriminates (no-drift=$ND_FLAG, drift=$D_FLAG)" $RC_CHK
  rm -rf "$DRIFT_DIR"
fi

echo "== Part 2.1: external-action idempotency — completed external actions are not repeated =="
bash "$SCRIPT" create task-ea "External-action task" >/dev/null 2>&1

echo "-- before recording: check says PROCEED --"
OUT=$(bash "$SCRIPT" check-external-action task-ea --key open-pr 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "check-external-action exits nonzero for an unrecorded key (exit $RC)" $RC_CHK
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1; check "check-external-action uses exit 1 for 'not recorded' (got $RC)" $RC_CHK
echo "$OUT" | grep -q "NOT-RECORDED"; check "output says NOT-RECORDED for an unrecorded key" $?
echo "$OUT" | grep -q "PROCEED"; check "output tells the caller in plain words to PROCEED" $?

echo "-- recording --"
OUT=$(bash "$SCRIPT" record-external-action task-ea --key open-pr --description "opened PR #17 against main" 2>&1); RC=$?
check "record-external-action succeeds" $RC
echo "$OUT" | grep -q "RECORDED-EXTERNAL-ACTION"; check "record-external-action confirms the record in its output" $?
STATE_EA=$(bash "$SCRIPT" status task-ea)
echo "$STATE_EA" | jq -e '.external_actions | length == 1' >/dev/null; check "exactly one external action recorded" $?
echo "$STATE_EA" | jq -e '.external_actions[0].key == "open-pr"' >/dev/null; check "recorded entry holds the key" $?
echo "$STATE_EA" | jq -e '.external_actions[0].description == "opened PR #17 against main"' >/dev/null
check "recorded entry holds the description" $?
echo "$STATE_EA" | jq -e '(.external_actions[0].recorded_at | type == "string" and length > 0)' >/dev/null
check "recorded entry holds a recorded_at timestamp" $?

echo "-- after recording: check says SKIP --"
OUT=$(bash "$SCRIPT" check-external-action task-ea --key open-pr 2>&1); RC=$?
[ "$RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "check-external-action exits 0 once the key is recorded (got $RC)" $RC_CHK
echo "$OUT" | grep -q "ALREADY-RECORDED"; check "output says ALREADY-RECORDED once the key is recorded" $?
echo "$OUT" | grep -q "SKIP"; check "output tells the caller in plain words to SKIP" $?

echo "-- recording the same key twice does not duplicate the entry --"
OUT=$(bash "$SCRIPT" record-external-action task-ea --key open-pr --description "opened PR #17 AGAIN" 2>&1); RC=$?
[ "$RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "re-recording an already-recorded key exits 0 (documented no-op success; got $RC)" $RC_CHK
echo "$OUT" | grep -q "ALREADY-RECORDED"; check "re-record output says ALREADY-RECORDED" $?
EA_LEN=$(bash "$SCRIPT" status task-ea | jq '.external_actions | length')
[ "$EA_LEN" = "1" ] && RC_CHK=0 || RC_CHK=1; check "external_actions still has exactly 1 entry, not 2 (got $EA_LEN)" $RC_CHK
bash "$SCRIPT" status task-ea | jq -e '.external_actions[0].description == "opened PR #17 against main"' >/dev/null
check "the ORIGINAL description survives; the duplicate attempt did not overwrite it" $?

echo "-- two different keys are independent of each other --"
OUT=$(bash "$SCRIPT" check-external-action task-ea --key post-note 2>&1); RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1; check "a DIFFERENT, unrecorded key still says PROCEED (exit $RC), unaffected by the first key" $RC_CHK
bash "$SCRIPT" record-external-action task-ea --key post-note --description "posted the wrap-up note" >/dev/null 2>&1
check "recording the second key succeeds" $?
EA_LEN=$(bash "$SCRIPT" status task-ea | jq '.external_actions | length')
[ "$EA_LEN" = "2" ] && RC_CHK=0 || RC_CHK=1; check "two distinct keys yield exactly 2 entries (got $EA_LEN)" $RC_CHK
bash "$SCRIPT" check-external-action task-ea --key open-pr >/dev/null 2>&1; RC=$?
[ "$RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "the first key still reads as recorded after the second was added (exit $RC)" $RC_CHK
bash "$SCRIPT" check-external-action task-ea --key post-note >/dev/null 2>&1; RC=$?
[ "$RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "the second key reads as recorded (exit $RC)" $RC_CHK
bash "$SCRIPT" check-external-action task-ea --key never-done >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1; check "a third, never-recorded key still says PROCEED (exit $RC)" $RC_CHK

echo "-- check-external-action is read-only: it must not touch the state file --"
CS1=$(checksum "$STATE_FILE")
bash "$SCRIPT" check-external-action task-ea --key open-pr >/dev/null 2>&1
bash "$SCRIPT" check-external-action task-ea --key never-done >/dev/null 2>&1
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after read-only check-external-action calls" $RC_CHK

echo "-- required flags and missing-value guards --"
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" record-external-action task-ea --description "no key given" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "record-external-action without --key exits 2 (got $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" record-external-action task-ea --key lonely-key 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "record-external-action without --description exits 2 (got $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" check-external-action task-ea 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "check-external-action without --key exits 2 (got $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the rejected external-action calls" $RC_CHK
if command -v timeout >/dev/null 2>&1; then
  OUT=$(timeout 5 bash "$SCRIPT" record-external-action task-ea --key 2>&1); RC=$?
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "record-external-action --key with no trailing value does not hang (exit $RC, 124=timeout)" $RC_CHK
  [ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "record-external-action --key with no trailing value exits 2 (got $RC)" $RC_CHK
  OUT=$(timeout 5 bash "$SCRIPT" check-external-action task-ea --key 2>&1); RC=$?
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "check-external-action --key with no trailing value does not hang (exit $RC, 124=timeout)" $RC_CHK
  [ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "check-external-action --key with no trailing value exits 2 (got $RC)" $RC_CHK
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely test the external-action missing-flag-value hang regression"
fi

echo "== Part 2.1: check-external-action's FULL exit-code contract — all four codes, distinctly =="
# This subcommand exists to stop a duplicate external side effect, and
# branching on its exit status is the idiom its own docs teach. So every
# answer it can give must carry a DIFFERENT code -- in particular a
# nonexistent task id must NOT land on 1, which is the "not recorded, go
# ahead and do it" answer. Regression: it used to reach require_task and exit
# 1, which made a typo'd task id indistinguishable from a green light to open
# a second PR.
bash "$SCRIPT" create task-xc "Exit-code contract task" >/dev/null 2>&1
bash "$SCRIPT" record-external-action task-xc --key done-key --description "already performed" >/dev/null 2>&1

XC0_OUT=$(bash "$SCRIPT" check-external-action task-xc --key done-key 2>&1); XC0=$?
[ "$XC0" = "0" ] && RC_CHK=0 || RC_CHK=1; check "exit-code contract: a RECORDED key exits 0 (got $XC0)" $RC_CHK
echo "$XC0_OUT" | grep -q "ALREADY-RECORDED"; check "exit-0 output says ALREADY-RECORDED" $?
echo "$XC0_OUT" | grep -q "SKIP"; check "exit-0 output tells the caller to SKIP" $?

XC1_OUT=$(bash "$SCRIPT" check-external-action task-xc --key never-recorded-key 2>&1); XC1=$?
[ "$XC1" = "1" ] && RC_CHK=0 || RC_CHK=1; check "exit-code contract: an UNRECORDED key exits 1 (got $XC1)" $RC_CHK
echo "$XC1_OUT" | grep -q "NOT-RECORDED"; check "exit-1 output says NOT-RECORDED" $?
echo "$XC1_OUT" | grep -q "PROCEED"; check "exit-1 output tells the caller to PROCEED" $?

XC3_OUT=$(bash "$SCRIPT" check-external-action task-xc-typo --key done-key 2>&1); XC3=$?
[ "$XC3" = "3" ] && RC_CHK=0 || RC_CHK=1; check "exit-code contract: a NONEXISTENT task exits 3, not 1 (got $XC3)" $RC_CHK
[ "$XC3" != "$XC1" ] && RC_CHK=0 || RC_CHK=1
check "a typo'd task id is distinguishable from 'not recorded, PROCEED' by exit code alone ($XC3 vs $XC1)" $RC_CHK
echo "$XC3_OUT" | grep -qi "not found"; check "exit-3 output says the task was not found" $?
echo "$XC3_OUT" | grep -qF -- "task-xc-typo"; check "exit-3 output names the offending task id" $?
echo "$XC3_OUT" | grep -qi "do not proceed"; check "exit-3 output tells the caller NOT to proceed" $?
! echo "$XC3_OUT" | grep -q "NOT-RECORDED"; check "exit-3 output never claims NOT-RECORDED (it is not a PROCEED answer)" $?

XC2_OUT=$(bash "$SCRIPT" check-external-action task-xc 2>&1); XC2=$?
[ "$XC2" = "2" ] && RC_CHK=0 || RC_CHK=1; check "exit-code contract: missing --key is bad usage, exits 2 (got $XC2)" $RC_CHK
echo "$XC2_OUT" | grep -qi -- "--key"; check "exit-2 output names the missing --key flag" $?

XC_UNIQ=$(printf '%s\n' "$XC0" "$XC1" "$XC2" "$XC3" | sort -u | wc -l | tr -d ' ')
[ "$XC_UNIQ" = "4" ] && RC_CHK=0 || RC_CHK=1
check "all four outcomes have DISTINCT exit codes — 0/1/2/3, got $XC_UNIQ distinct ($XC0/$XC1/$XC2/$XC3)" $RC_CHK

echo "-- the exit-3 path stays read-only, like the rest of this subcommand --"
CS1=$(checksum "$STATE_FILE")
bash "$SCRIPT" check-external-action definitely-not-a-task --key done-key >/dev/null 2>&1
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the exit-3 missing-task check" $RC_CHK

echo "-- exit 3 is LOCAL to check-external-action: require_task was not changed --"
bash "$SCRIPT" start no-such-task-for-exit3 >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1; check "start on a missing task still exits 1, not 3 (got $RC)" $RC_CHK
bash "$SCRIPT" record-external-action no-such-task-for-exit3 --key k --description d >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1; check "record-external-action on a missing task still exits 1, not 3 (got $RC)" $RC_CHK
bash "$SCRIPT" status no-such-task-for-exit3 >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1; check "status on a missing task still exits 1, not 3 (got $RC)" $RC_CHK
bash "$SCRIPT" resume no-such-task-for-exit3 >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1; check "resume on a missing task still exits 1, not 3 (got $RC)" $RC_CHK

echo "-- exit 3 also applies when there is no state file at all --"
NOSTATE_DIR=$(mktemp -d)
XC3B_OUT=$(cd "$NOSTATE_DIR" && bash "$SCRIPT" check-external-action any-task --key any-key 2>&1); XC3B=$?
[ "$XC3B" = "3" ] && RC_CHK=0 || RC_CHK=1; check "check-external-action exits 3 in a project with no state file yet (got $XC3B)" $RC_CHK
echo "$XC3B_OUT" | grep -qi "do not proceed"; check "the no-state-file case also tells the caller NOT to proceed" $?
rm -rf "$NOSTATE_DIR"

echo "== Part 2.1: record-first idiom — record-external-action's two outcomes are distinguishable from OUTPUT =="
# The documented safe idiom (see task-state.sh's header) branches on these
# two words rather than on exit status, since both outcomes exit 0 by design.
# If they ever stopped being distinct, record-first would become unwritable.
RF_DIR=$(mktemp -d)
( cd "$RF_DIR" && bash "$SCRIPT" create rf-task "Record-first task" ) >/dev/null 2>&1
RF1=$(cd "$RF_DIR" && bash "$SCRIPT" record-external-action rf-task --key rf-key --description "first" 2>&1); RF1_RC=$?
[ "$RF1_RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "record-first: the newly-recording call exits 0 (got $RF1_RC)" $RC_CHK
echo "$RF1" | grep -q "RECORDED-EXTERNAL-ACTION"; check "record-first: newly-recorded prints RECORDED-EXTERNAL-ACTION (the 'you own it, DO the action' signal)" $?
! echo "$RF1" | grep -q "ALREADY-RECORDED"; check "record-first: the newly-recorded output does NOT also say ALREADY-RECORDED" $?
RF2=$(cd "$RF_DIR" && bash "$SCRIPT" record-external-action rf-task --key rf-key --description "second" 2>&1); RF2_RC=$?
[ "$RF2_RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "record-first: the losing call also exits 0, so output is the only signal (got $RF2_RC)" $RC_CHK
echo "$RF2" | grep -q "ALREADY-RECORDED"; check "record-first: already-recorded prints ALREADY-RECORDED (the 'SKIP the action' signal)" $?
! echo "$RF2" | grep -q "RECORDED-EXTERNAL-ACTION"; check "record-first: the already-recorded output does NOT claim it newly recorded" $?
[ "$RF1" != "$RF2" ] && RC_CHK=0 || RC_CHK=1
check "record-first: the two outcomes are genuinely distinguishable from output alone" $RC_CHK
rm -rf "$RF_DIR"

echo "== Part 2.1: a paused task cannot be completed via complete-gate.sh =="
if ! command -v git >/dev/null 2>&1; then
  echo "  SKIP: git not on PATH — complete-gate.sh's staleness check needs it"
else
  GATE_DIR=$(mktemp -d)
  ( cd "$GATE_DIR" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
  echo ".claude/state/" > "$GATE_DIR/.gitignore"
  echo "base content" > "$GATE_DIR/tracked.txt"
  ( cd "$GATE_DIR" && git add .gitignore tracked.txt && git commit -qm init ) >/dev/null 2>&1

  # Drive BOTH tasks identically and far enough to have genuinely valid,
  # gate-passing evidence. The only difference between them is that one gets
  # paused. Without the control task below, a gate refusal would prove
  # nothing -- it could just as easily mean the evidence setup was broken.
  #
  # Create EVERY evidence file BEFORE recording ANY evidence. These files are
  # untracked, so each one created changes compute_snapshot()'s dirty-tree
  # hash; creating the second task's files after recording the first task's
  # evidence would make that first evidence legitimately stale and fail the
  # gate's check 6 for a reason that has nothing to do with pausing. (.claude/
  # state/ is gitignored above, so the state writes themselves do not move
  # the snapshot -- only these artifact files do.)
  for t in gate-ctrl gate-paused; do
    ( cd "$GATE_DIR" && bash "$SCRIPT" create "$t" "Gate task $t" && bash "$SCRIPT" start "$t" && bash "$SCRIPT" check "$t" ) >/dev/null 2>&1
    echo "real evidence output for $t" > "$GATE_DIR/$t-output.txt"
    echo "real artifact for $t" > "$GATE_DIR/$t-artifact.txt"
  done
  for t in gate-ctrl gate-paused; do
    ( cd "$GATE_DIR" && bash "$SCRIPT" record-evidence "$t" --command "bash tests/task-state-smoke.sh" \
      --exit-code 0 --tests-total 7 --tests-skipped 0 \
      --output-file "$t-output.txt" --artifact "$t-artifact.txt" ) >/dev/null 2>&1
  done

  echo "-- control: an identically-prepared, NOT-paused task passes the gate --"
  CTRL_OUT=$(cd "$GATE_DIR" && bash "$GATE" gate-ctrl 2>&1); RC=$?
  check "control task's evidence is genuinely gate-passing (exit $RC)" $RC
  echo "$CTRL_OUT" | grep -q "GATE PASS"; check "control task prints GATE PASS" $?
  CTRL_STATE=$(cd "$GATE_DIR" && bash "$SCRIPT" status gate-ctrl | jq -r '.state')
  [ "$CTRL_STATE" = "done" ] && RC_CHK=0 || RC_CHK=1; check "control task reached 'done' (got $CTRL_STATE)" $RC_CHK

  echo "-- the paused task, same evidence, is refused --"
  ( cd "$GATE_DIR" && bash "$SCRIPT" pause gate-paused --next-action "get the verifier to re-read the evidence" ) >/dev/null 2>&1
  PAUSED_STATE=$(cd "$GATE_DIR" && bash "$SCRIPT" status gate-paused | jq -r '.state')
  [ "$PAUSED_STATE" = "paused" ] && RC_CHK=0 || RC_CHK=1; check "gate-paused really is paused before the gate runs (got $PAUSED_STATE)" $RC_CHK
  GATE_OUT=$(cd "$GATE_DIR" && bash "$GATE" gate-paused 2>&1); RC=$?
  [ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh refuses a paused task (exit $RC)" $RC_CHK
  echo "$GATE_OUT" | grep -q "GATE FAIL"; check "gate output says GATE FAIL" $?
  echo "$GATE_OUT" | grep -q "paused"; check "gate failure names the offending state (paused)" $?
  AFTER_STATE=$(cd "$GATE_DIR" && bash "$SCRIPT" status gate-paused | jq -r '.state')
  [ "$AFTER_STATE" = "paused" ] && RC_CHK=0 || RC_CHK=1; check "the refused task is still 'paused', not 'done' (got $AFTER_STATE)" $RC_CHK
  rm -rf "$GATE_DIR"
fi

echo "== Part 2.1: concurrent record-external-action with N distinct keys yields exactly N entries =="
if command -v timeout >/dev/null 2>&1; then
  CONC_EA_DIR=$(mktemp -d)
  ( cd "$CONC_EA_DIR" && bash "$SCRIPT" create ea-conc "Concurrent external-action task" ) >/dev/null 2>&1
  timeout 60 bash -c '
    SCRIPT="$1"; DIR="$2"; N="$3"
    PIDS=()
    for i in $(seq 1 "$N"); do
      ( cd "$DIR" && bash "$SCRIPT" record-external-action ea-conc --key "ea-key-$i" --description "external action $i" >/dev/null 2>&1 ) &
      PIDS+=("$!")
    done
    for pid in "${PIDS[@]}"; do wait "$pid"; done
  ' _ "$SCRIPT" "$CONC_EA_DIR" 20
  RC=$?
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "20 concurrent record-external-action calls complete without deadlocking (exit $RC, 124=timeout)" $RC_CHK
  EA_CONC_COUNT=$(jq '.tasks["ea-conc"].external_actions | length' "$CONC_EA_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$EA_CONC_COUNT" = "20" ] && RC_CHK=0 || RC_CHK=1
  check "20 concurrent distinct keys yield exactly 20 entries, not fewer (got ${EA_CONC_COUNT:-0})" $RC_CHK
  EA_CONC_UNIQ=$(jq '[.tasks["ea-conc"].external_actions[].key] | unique | length' "$CONC_EA_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$EA_CONC_UNIQ" = "20" ] && RC_CHK=0 || RC_CHK=1
  check "all 20 recorded keys are distinct, none lost or duplicated (got ${EA_CONC_UNIQ:-0})" $RC_CHK
  rm -rf "$CONC_EA_DIR"
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely bound the external-action concurrency test"
fi

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
