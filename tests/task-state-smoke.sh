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

echo "== complete --staleness-verified: the completion records whether staleness was actually checked =="
# complete-gate.sh's check 6 cannot verify staleness when there is no version
# control (both snapshots degrade to the same placeholder and match no matter
# what the code did). It must not report a pass it did not perform, and -- since
# only recorded state is ground truth here -- that verdict has to reach the
# state file, not just stdout. This flag is how it gets there.
echo "-- omitted: no key at all, which reads as 'whoever completed this did not say' --"
bash "$SCRIPT" status task-a | jq -e '.history[-1] | has("staleness_verified") | not' >/dev/null
check "a complete with no flag writes NO staleness_verified key (legacy/direct-call records stay readable)" $?
echo "-- --staleness-verified yes / no are recorded as real booleans --"
bash "$SCRIPT" create task-sv-yes "Verified completion" >/dev/null 2>&1
bash "$SCRIPT" start task-sv-yes >/dev/null 2>&1; bash "$SCRIPT" check task-sv-yes >/dev/null 2>&1
SV_OUT=$(bash "$SCRIPT" complete task-sv-yes --staleness-verified yes 2>&1); RC=$?
check "complete --staleness-verified yes succeeds" $RC
echo "$SV_OUT" | grep -q "COMPLETED task-sv-yes state=done"; check "its output still leads with the usual COMPLETED line" $?
echo "$SV_OUT" | grep -q "staleness_verified=true"; check "its output also states the verdict" $?
bash "$SCRIPT" status task-sv-yes | jq -e '.history[-1].staleness_verified == true' >/dev/null
check "yes is recorded as the JSON boolean true (not the string \"yes\")" $?
bash "$SCRIPT" create task-sv-no "Unverified completion" >/dev/null 2>&1
bash "$SCRIPT" start task-sv-no >/dev/null 2>&1; bash "$SCRIPT" check task-sv-no >/dev/null 2>&1
bash "$SCRIPT" complete task-sv-no --staleness-verified no >/dev/null 2>&1
check "complete --staleness-verified no succeeds" $?
bash "$SCRIPT" status task-sv-no | jq -e '.history[-1].staleness_verified == false' >/dev/null
check "no is recorded as the JSON boolean false" $?
bash "$SCRIPT" status task-sv-no | jq -e '.state == "done"' >/dev/null
check "an UNVERIFIED completion still reaches done (it is a disclosure, not a refusal)" $?
echo "-- the flag is validated, and a bad value changes nothing --"
bash "$SCRIPT" create task-sv-bad "Bad flag value" >/dev/null 2>&1
bash "$SCRIPT" start task-sv-bad >/dev/null 2>&1; bash "$SCRIPT" check task-sv-bad >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" complete task-sv-bad --staleness-verified maybe 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1
check "complete --staleness-verified with a value other than yes/no exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--staleness-verified"; check "the refusal names the offending flag" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1
check "state file byte-for-byte unchanged after the rejected complete" $RC_CHK
OUT=$(bash "$SCRIPT" complete task-sv-bad --staleness-verified 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1
check "complete --staleness-verified with no trailing value exits 2 (got $RC)" $RC_CHK
SV_BAD_STATE=$(bash "$SCRIPT" status task-sv-bad | jq -r '.state')
[ "$SV_BAD_STATE" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "the task is still 'checking' after both rejected completes (got: $SV_BAD_STATE)" $RC_CHK
bash "$SCRIPT" complete task-sv-bad --staleness-verified yes >/dev/null 2>&1
check "CONTROL: the same task completes once the flag value is valid — the refusals above are not vacuous" $?

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

echo "== resume OUTSIDE a git repository: the CODE CHECK must not claim the code is unchanged =="
# THE DEFECT: compute_snapshot cannot compute a code identity without git, so it
# returns the constant "no-git-repository". resume compared that constant
# against itself, matched every time, and printed
#     CODE CHECK: OK — code is unchanged since the pause
# having verified NOTHING -- rewrite every file in the directory while paused
# and it said the same thing. This WORKDIR is deliberately not a git repository,
# so the resume just above ran on exactly that path; these assertions are about
# what it SAID. (The genuine unchanged/changed discrimination is asserted in the
# git-backed section further below, which is what keeps these non-vacuous.)
NOGIT_SNAP=$(echo "$STATE_P" | jq -r '.history[-1].resume_snapshot')
[ "$NOGIT_SNAP" = "no-git-repository" ] && RC_CHK=0 || RC_CHK=1
check "precondition: this resume really ran on the no-git placeholder (got: $NOGIT_SNAP)" $RC_CHK
# Re-run one more pause/resume cycle so the printed output is in hand.
bash "$SCRIPT" pause task-p --next-action "check the honesty of the CODE CHECK line" >/dev/null 2>&1
echo "the code moved while the task was paused" > code-moved-while-paused.txt
NG_OUT=$(bash "$SCRIPT" resume task-p 2>&1); RC=$?
check "resume still succeeds outside a git repository (not refused)" $RC
echo "$NG_OUT" | grep -q "CODE CHECK: OK" && RC_CHK=1 || RC_CHK=0
check "resume does NOT print 'CODE CHECK: OK' when it could not check anything" $RC_CHK
echo "$NG_OUT" | grep -qi "unchanged since the pause" && RC_CHK=1 || RC_CHK=0
check "resume does NOT claim the code is unchanged since the pause" $RC_CHK
echo "$NG_OUT" | grep -q "CODE CHECK: \*\*\* NOT VERIFIED"; check "resume says the code check was NOT VERIFIED" $?
echo "$NG_OUT" | grep -qi "not under version control"; check "resume names the reason (no version control)" $?
echo "$NG_OUT" | grep -qi "UNDETECTED"; check "resume says any change made while paused is UNDETECTED" $?
echo "$NG_OUT" | grep -qF "check the honesty of the CODE CHECK line"
check "resume still prints the EXACT recorded next action in the unverified case" $?
NG_HIST=$(bash "$SCRIPT" status task-p | jq -c '.history[-1]')
echo "$NG_HIST" | jq -e '.staleness_verified == false' >/dev/null
check "the unverifiable verdict is DURABLY recorded as staleness_verified=false (got: $NG_HIST)" $?
echo "$NG_HIST" | jq -e '.drift_detected == false' >/dev/null
check "drift_detected is still false alongside it — the pair is what makes the record readable" $?
rm -f code-moved-while-paused.txt

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
  # THE CONTROL FOR THE NON-GIT HONESTY TEST ABOVE. Here the comparison really
  # was possible, so "OK — unchanged" is a claim the code is entitled to make,
  # and it must be recorded as verified. Without this side, the assertions above
  # would only prove the message can be suppressed, not that it discriminates.
  echo "$ND_HIST" | jq -e '.staleness_verified == true' >/dev/null
  check "no-drift: history entry records staleness_verified=true (the check genuinely ran)" $?
  ! echo "$ND_OUT" | grep -qi "NOT VERIFIED"
  check "no-drift: a real git repo never prints the could-not-verify message" $?

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
  # ...and staleness_verified must be true in BOTH git-backed directions: it
  # answers "was the comparison possible", not "did it find drift". A field that
  # tracked drift_detected would be redundant, not a check on it.
  echo "$D_HIST" | jq -e '.staleness_verified == true' >/dev/null
  check "drift: history entry also records staleness_verified=true (the check ran and FOUND drift)" $?
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

echo "== Part 2.2: fresh tasks start with a zero attempt counter and empty repair arrays =="
bash "$SCRIPT" create task-schema "Schema task" >/dev/null 2>&1
STATE_SCH=$(bash "$SCRIPT" status task-schema)
echo "$STATE_SCH" | jq -e '.attempts_used == 0' >/dev/null; check "attempts_used starts at 0" $?
echo "$STATE_SCH" | jq -e '.attempts == []' >/dev/null; check "attempts array starts empty" $?
echo "$STATE_SCH" | jq -e '.reassessments == []' >/dev/null; check "reassessments array starts empty" $?

echo "== Part 2.2: a task created BEFORE this schema existed still works (no attempts_used field at all) =="
# Not hypothetical: this repo's own task '2.2' was created by the pre-2.2
# `create` and its stored record has attempts_used: null and no attempts /
# reassessments arrays. `fail` and `reassess` must treat that as 0 / [] via
# their `// 0` and `// []` defaults rather than crashing or mis-counting.
# The hand-edit below is the only way to manufacture a legacy-shaped record,
# and it is done to a throwaway state file in an isolated mktemp dir, never
# to a real project's state.
LEGACY_DIR=$(mktemp -d)
( cd "$LEGACY_DIR" && bash "$SCRIPT" create legacy "Pre-2.2 schema task" && bash "$SCRIPT" start legacy ) >/dev/null 2>&1
jq 'del(.tasks.legacy.attempts_used, .tasks.legacy.attempts, .tasks.legacy.reassessments)' \
  "$LEGACY_DIR/$STATE_FILE" > "$LEGACY_DIR/legacy.tmp" && mv "$LEGACY_DIR/legacy.tmp" "$LEGACY_DIR/$STATE_FILE"
jq -e '.tasks.legacy | has("attempts_used") | not' "$LEGACY_DIR/$STATE_FILE" >/dev/null
check "legacy record genuinely has no attempts_used field before the test runs" $?
( cd "$LEGACY_DIR" && bash "$SCRIPT" fail legacy --reason "first" --hypothesis "legacy theory one" ) >/dev/null 2>&1
check "fail succeeds on a record with no attempts_used field" $?
( cd "$LEGACY_DIR" && bash "$SCRIPT" status legacy ) | jq -e '.attempts_used == 1 and (.attempts | length) == 1' >/dev/null
check "a missing attempts_used counts as 0, so the first failure becomes attempt 1" $?
( cd "$LEGACY_DIR" && bash "$SCRIPT" fail legacy --reason "second" --hypothesis "legacy theory two" ) >/dev/null 2>&1
( cd "$LEGACY_DIR" && bash "$SCRIPT" status legacy ) | jq -e '.state == "needs-reassessment" and .attempts_used == 2' >/dev/null
check "a legacy-schema task still trips needs-reassessment at the default budget of 2" $?
( cd "$LEGACY_DIR" && bash "$SCRIPT" reassess legacy --specialist sp --finding "legacy path works" --additional-budget 1 ) >/dev/null 2>&1
check "reassess succeeds on a record that had no reassessments array" $?
( cd "$LEGACY_DIR" && bash "$SCRIPT" status legacy ) | jq -e '.state == "building" and .budget == 3 and (.reassessments | length) == 1' >/dev/null
check "the legacy record now carries a proper reassessments array and a raised budget" $?
rm -rf "$LEGACY_DIR"

echo "== Part 2.2: a numeric field that is PRESENT but invalid FAILS CLOSED (regression: jq's // collapsed a stored null to 0) =="
# The section ABOVE covers one half of the absent-vs-invalid distinction: a
# key that is genuinely missing on a task with no attempt history is a
# pre-2.2 record and must keep defaulting. This section covers the half that
# let the real bug through, which that test could not have caught because it
# only ever stripped fields from a FRESH task before any attempt existed:
#
#   a task genuinely at attempts_used=2 with two recorded attempts, whose
#   attempts_used is then set to null, used to read back as 0. `reassess`
#   printed "attempts_used=0 (unchanged)" -- asserting the field was
#   untouched while displaying a number that was never in the file -- and the
#   next `fail` wrote 1, walking the monotonic counter BACKWARDS and putting
#   a duplicate attempt_number into the durable audit trail.
#
# Every case below therefore starts from a task with REAL prior history.
# corrupt_task_dir <budget> <field> <json-value> -> prints an isolated dir
# holding task 'c' driven to attempts_used=2 with two recorded attempts, with
# <field> then set to <json-value>. Budget 5 leaves it in 'building' (so
# `fail` is reachable); budget 2 leaves it in 'needs-reassessment' (so
# `reassess` is reachable). The hand-edit is the only way to manufacture a
# corrupt record and it only ever touches a throwaway mktemp state file.
corrupt_task_dir() {
  local budget="$1" field="$2" value="$3" dir
  dir=$(mktemp -d)
  ( cd "$dir" && bash "$SCRIPT" create c "Corruptible task" --budget "$budget" \
    && bash "$SCRIPT" start c \
    && bash "$SCRIPT" fail c --reason "first" --hypothesis "theory one" \
    && bash "$SCRIPT" fail c --reason "second" --hypothesis "theory two" ) >/dev/null 2>&1
  jq --arg f "$field" --argjson v "$value" '.tasks.c[$f] = $v' \
    "$dir/$STATE_FILE" > "$dir/corrupt.tmp" && mv "$dir/corrupt.tmp" "$dir/$STATE_FILE"
  printf '%s' "$dir"
}

echo "-- THE REPORTED BUG: null attempts_used on a task with two recorded attempts --"
CDIR=$(corrupt_task_dir 5 attempts_used null)
jq -e '.tasks.c.attempts_used == null and (.tasks.c.attempts | length) == 2' "$CDIR/$STATE_FILE" >/dev/null
check "precondition: attempts_used is stored as null and two attempts are genuinely recorded" $?
CS1=$(checksum "$CDIR/$STATE_FILE")
OUT=$(cd "$CDIR" && bash "$SCRIPT" fail c --reason "third" --hypothesis "theory three" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "fail is REFUSED when attempts_used is present-but-null (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "attempts_used"; check "the refusal names the offending field (attempts_used)" $?
echo "$OUT" | grep -qF -- "task 'c'"; check "the refusal names the task" $?
echo "$OUT" | grep -q "null"; check "the refusal shows the offending value (null)" $?
CS2=$(checksum "$CDIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the refused fail (null attempts_used)" $RC_CHK
jq -e '(.tasks.c.attempts | length) == 2 and .tasks.c.state == "building"' "$CDIR/$STATE_FILE" >/dev/null
check "no third attempt record was appended and the state did not move" $?
rm -rf "$CDIR"

CDIR=$(corrupt_task_dir 2 attempts_used null)
jq -e '.tasks.c.state == "needs-reassessment"' "$CDIR/$STATE_FILE" >/dev/null
check "precondition: the budget-2 variant really is stopped in needs-reassessment" $?
CS1=$(checksum "$CDIR/$STATE_FILE")
OUT=$(cd "$CDIR" && bash "$SCRIPT" reassess c --specialist s --finding f 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "reassess is REFUSED when attempts_used is present-but-null (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "attempts_used"; check "the reassess refusal names attempts_used" $?
echo "$OUT" | grep -qi "attempts_used=0"; RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "reassess no longer prints the fabricated 'attempts_used=0 (unchanged)' line" $RC_CHK
CS2=$(checksum "$CDIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the refused reassess" $RC_CHK
jq -e '.tasks.c.state == "needs-reassessment" and .tasks.c.budget == 2' "$CDIR/$STATE_FILE" >/dev/null
check "the task is still stopped and its budget was not raised by the refused reassess" $?
rm -rf "$CDIR"

echo "-- the same defect on 'budget' (F2): it fails safe, but it is the same bug and gets the same fix --"
CDIR=$(corrupt_task_dir 5 budget null)
CS1=$(checksum "$CDIR/$STATE_FILE")
OUT=$(cd "$CDIR" && bash "$SCRIPT" fail c --reason "third" --hypothesis "theory three" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "fail is REFUSED when budget is present-but-null (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "budget"; check "the refusal names the offending field (budget)" $?
CS2=$(checksum "$CDIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the refused fail (null budget)" $RC_CHK
rm -rf "$CDIR"
CDIR=$(corrupt_task_dir 2 budget null)
CS1=$(checksum "$CDIR/$STATE_FILE")
OUT=$(cd "$CDIR" && bash "$SCRIPT" reassess c --specialist s --finding f --additional-budget 1 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "reassess is REFUSED when budget is present-but-null (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "budget"; check "the reassess refusal names budget" $?
CS2=$(checksum "$CDIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the refused reassess (null budget)" $RC_CHK
rm -rf "$CDIR"

echo "-- non-integer values in either field are refused too (string, negative, fractional) --"
# check_corrupt_fail_refused <budget> <field> <json-value> <human label>
# Same three assertions for each corruption shape: refused, names the field,
# and left the state file byte-for-byte unchanged.
check_corrupt_fail_refused() {
  local budget="$1" field="$2" value="$3" label="$4"
  local dir cs_before cs_after out rc verdict
  dir=$(corrupt_task_dir "$budget" "$field" "$value")
  cs_before=$(checksum "$dir/$STATE_FILE")
  out=$(cd "$dir" && bash "$SCRIPT" fail c --reason "third" --hypothesis "theory three" 2>&1); rc=$?
  [ "$rc" != "0" ] && verdict=0 || verdict=1
  check "fail is refused when $field is $label (exit $rc)" "$verdict"
  echo "$out" | grep -q "$field"; check "the refusal for $field=$label names the field" $?
  cs_after=$(checksum "$dir/$STATE_FILE")
  [ "$cs_before" = "$cs_after" ] && verdict=0 || verdict=1
  check "state file checksum unchanged after the refused fail ($field=$label)" "$verdict"
  rm -rf "$dir"
}
check_corrupt_fail_refused 5 attempts_used '"two"' 'the string "two"'
check_corrupt_fail_refused 5 budget '"lots"' 'the string "lots"'
check_corrupt_fail_refused 5 attempts_used '-1' 'the negative number -1'
check_corrupt_fail_refused 5 budget '1.5' 'the fractional number 1.5'

echo "-- DELETING attempts_used from a task that HAS attempts is corruption too, not a legacy record --"
# has() alone cannot tell these apart -- both have no key. What separates them
# is the attempt history: a genuine pre-2.2 record has none, a stripped record
# does. Without this check, `del(.attempts_used)` would be an exact substitute
# for `= null` and reopen the very same counter reset.
CDIR=$(corrupt_task_dir 5 attempts_used null)
jq 'del(.tasks.c.attempts_used)' "$CDIR/$STATE_FILE" > "$CDIR/t.json" && mv "$CDIR/t.json" "$CDIR/$STATE_FILE"
jq -e '(.tasks.c | has("attempts_used") | not) and (.tasks.c.attempts | length) == 2' "$CDIR/$STATE_FILE" >/dev/null
check "precondition: the key is genuinely absent AND two attempts are genuinely recorded" $?
CS1=$(checksum "$CDIR/$STATE_FILE")
OUT=$(cd "$CDIR" && bash "$SCRIPT" fail c --reason "third" --hypothesis "theory three" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "fail is refused when attempts_used is absent but the task has real attempt history (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "behind its own recorded attempt history"
check "the refusal says the counter is behind its own recorded attempt history" $?
CS2=$(checksum "$CDIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the stripped-counter refusal" $RC_CHK
rm -rf "$CDIR"

echo "-- ...while the genuinely-legacy shape (both keys absent AND no attempt history) still defaults --"
LEG2_DIR=$(mktemp -d)
( cd "$LEG2_DIR" && bash "$SCRIPT" create c "Legacy-shaped task" && bash "$SCRIPT" start c ) >/dev/null 2>&1
jq 'del(.tasks.c.attempts_used, .tasks.c.budget, .tasks.c.attempts, .tasks.c.reassessments)' \
  "$LEG2_DIR/$STATE_FILE" > "$LEG2_DIR/t.json" && mv "$LEG2_DIR/t.json" "$LEG2_DIR/$STATE_FILE"
jq -e '(.tasks.c | has("attempts_used") | not) and (.tasks.c | has("budget") | not)' "$LEG2_DIR/$STATE_FILE" >/dev/null
check "precondition: both numeric keys are absent and the task has no attempt history" $?
( cd "$LEG2_DIR" && bash "$SCRIPT" fail c --reason "first" --hypothesis "theory one" ) >/dev/null 2>&1
check "fail still SUCCEEDS on a genuinely legacy-shaped record" $?
jq -e '.tasks.c.attempts_used == 1 and .tasks.c.state == "building"' "$LEG2_DIR/$STATE_FILE" >/dev/null
check "absent budget defaulted to 2 and absent attempts_used to 0, so the first failure is attempt 1 of 2" $?
rm -rf "$LEG2_DIR"

echo "-- corrupt -> refuse -> repair: the counter never decreased and attempt_numbers stayed unique and ascending --"
CDIR=$(corrupt_task_dir 5 attempts_used null)
USED_BEFORE=$(jq -r '[.tasks.c.attempts[].attempt_number] | max' "$CDIR/$STATE_FILE")
( cd "$CDIR" && bash "$SCRIPT" fail c --reason "during corruption" --hypothesis "theory three" ) >/dev/null 2>&1
jq -e '[.tasks.c.attempts[].attempt_number] == [1,2]' "$CDIR/$STATE_FILE" >/dev/null
check "while corrupt, the refused fail added no attempt_number at all (still [1,2])" $?
# Repair the field to the value the audit trail says it must be, then carry on.
jq '.tasks.c.attempts_used = 2' "$CDIR/$STATE_FILE" > "$CDIR/t.json" && mv "$CDIR/t.json" "$CDIR/$STATE_FILE"
( cd "$CDIR" && bash "$SCRIPT" fail c --reason "after repair" --hypothesis "theory three" ) >/dev/null 2>&1
check "fail succeeds again once the counter is restored to a valid value" $?
NUMS=$(jq -c '[.tasks.c.attempts[].attempt_number]' "$CDIR/$STATE_FILE")
[ "$NUMS" = "[1,2,3]" ] && RC_CHK=0 || RC_CHK=1
check "the next attempt is 3, not a re-issued 1 — the counter never went backwards (got $NUMS)" $RC_CHK
jq -e '[.tasks.c.attempts[].attempt_number] as $n
       | ($n | unique | length) == ($n | length) and $n == ($n | sort)' "$CDIR/$STATE_FILE" >/dev/null
check "every attempt_number across the corrupt-then-recover sequence is unique and ascending" $?
USED_AFTER=$(jq -r '.tasks.c.attempts_used' "$CDIR/$STATE_FILE")
[ "$USED_AFTER" -ge "$USED_BEFORE" ] && RC_CHK=0 || RC_CHK=1
check "attempts_used never decreased across the whole sequence ($USED_BEFORE -> $USED_AFTER)" $RC_CHK
rm -rf "$CDIR"

echo "== Part 2.2: the default budget-2 arc — fail once (repair proceeds), fail twice (reassessment required) =="
bash "$SCRIPT" create task-r1 "Bounded repair task" >/dev/null 2>&1
bash "$SCRIPT" start task-r1 >/dev/null 2>&1
F1=$(bash "$SCRIPT" fail task-r1 --reason "assertion 7 fails on CRLF fixtures" \
  --hypothesis "the fixture loader strips \\r too late" 2>&1); RC=$?
check "fail #1 from 'building' succeeds" $RC
echo "$F1" | grep -q "FAILED task-r1"; check "fail #1 output leads with FAILED" $?
STATE_R1=$(bash "$SCRIPT" status task-r1)
echo "$STATE_R1" | jq -e '.state == "building"' >/dev/null
check "under budget, failure returns the task to 'building' so repair proceeds" $?
echo "$STATE_R1" | jq -e '.attempts_used == 1' >/dev/null; check "attempts_used incremented to 1" $?
echo "$F1" | grep -q "1 repair attempt(s) remain"; check "fail #1 output says plainly how many attempts remain (1)" $?
echo "$STATE_R1" | jq -e '.attempts | length == 1' >/dev/null; check "one attempt record appended" $?
echo "$STATE_R1" | jq -e '.attempts[0].attempt_number == 1' >/dev/null; check "attempt record carries attempt_number 1" $?
echo "$STATE_R1" | jq -e '.attempts[0].reason == "assertion 7 fails on CRLF fixtures"' >/dev/null
check "attempt record carries the exact reason text" $?
echo "$STATE_R1" | jq -e '.attempts[0].hypothesis == "the fixture loader strips \\r too late"' >/dev/null
check "attempt record carries the exact hypothesis text" $?
echo "$STATE_R1" | jq -e '(.attempts[0].failed_at | type == "string" and length > 0)' >/dev/null
check "attempt record carries a failed_at timestamp" $?
echo "$STATE_R1" | jq -e '(.attempts[0].code_snapshot | type == "string" and length > 0)' >/dev/null
check "attempt record carries a code snapshot" $?

F2=$(bash "$SCRIPT" fail task-r1 --reason "still failing after the loader fix" \
  --hypothesis "the regex itself is anchored wrong" 2>&1); RC=$?
check "fail #2 succeeds" $RC
STATE_R1=$(bash "$SCRIPT" status task-r1)
echo "$STATE_R1" | jq -e '.state == "needs-reassessment"' >/dev/null
check "two failed attempts at the default budget trigger 'needs-reassessment'" $?
echo "$STATE_R1" | jq -e '.attempts_used == 2' >/dev/null; check "attempts_used incremented to 2" $?
echo "$F2" | grep -qi "budget exhausted"; check "fail #2 output says the budget is exhausted" $?
echo "$F2" | grep -q "reassess"; check "fail #2 output says only reassess can clear it" $?
echo "$STATE_R1" | jq -e '.attempts | length == 2' >/dev/null; check "two attempt records now recorded" $?

echo "== Part 2.2: a task can also fail during verification ('checking'), not only implementation =="
bash "$SCRIPT" create task-rc "Fails during checking" >/dev/null 2>&1
bash "$SCRIPT" start task-rc >/dev/null 2>&1
bash "$SCRIPT" check task-rc >/dev/null 2>&1
OUT=$(bash "$SCRIPT" fail task-rc --reason "verifier could not reproduce the claimed artifact" \
  --hypothesis "the artifact path was never written at all" 2>&1); RC=$?
check "fail from 'checking' succeeds" $RC
bash "$SCRIPT" status task-rc | jq -e '.state == "building" and .attempts_used == 1' >/dev/null
check "failing from 'checking' also returns the task to 'building' while budget remains" $?
bash "$SCRIPT" status task-rc | jq -e '.history[-1].from == "checking"' >/dev/null
check "history records that this attempt failed from 'checking', not 'building'" $?

echo "-- fail is refused from every state that has no attempt in flight --"
# task-c is 'planned', task-a is 'done', task-pb is 'blocked' (all set up
# earlier in this file). None of them has an attempt in flight to fail.
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" fail task-c --reason r --hypothesis h 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "fail on a 'planned' task is refused (exit $RC)" $RC_CHK
echo "$OUT" | grep -qF -- "state 'planned'"; check "refusal names the offending state (planned)" $?
OUT=$(bash "$SCRIPT" fail task-a --reason r --hypothesis h 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "fail on a 'done' task is refused (exit $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" fail task-pb --reason r --hypothesis h 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "fail on a 'blocked' task is refused (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the three rejected fails" $RC_CHK

echo "== Part 2.2: CONTROL — 'needs-reassessment' is a real stop; every other door is refused =="
# task-r1 is sitting in needs-reassessment from the arc above. Each attempt
# below must be refused AND must leave the state file byte-for-byte unchanged.
CS1=$(checksum "$STATE_FILE")
NR_FAIL=$(bash "$SCRIPT" fail task-r1 --reason "one more go" --hypothesis "a genuinely new theory" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "fail is refused from needs-reassessment (exit $RC)" $RC_CHK
echo "$NR_FAIL" | grep -q "reassess"; check "the refused fail points the caller at reassess" $?
NR_START=$(bash "$SCRIPT" start task-r1 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "start is refused from needs-reassessment (exit $RC)" $RC_CHK
echo "$NR_START" | grep -q "reassess"; check "the refused start points the caller at reassess" $?
NR_CHECK=$(bash "$SCRIPT" check task-r1 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "check is refused from needs-reassessment (exit $RC)" $RC_CHK
echo "$NR_CHECK" | grep -q "reassess"; check "the refused check points the caller at reassess" $?
NR_COMPLETE=$(bash "$SCRIPT" complete task-r1 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete is refused from needs-reassessment (exit $RC)" $RC_CHK
echo "$NR_COMPLETE" | grep -q "reassess"; check "the refused complete points the caller at reassess" $?
# ...and the two indirect doors: if block or pause were accepted, unblock or
# resume would become a second exit from this state.
NR_BLOCK=$(bash "$SCRIPT" block task-r1 "pretend an external obstacle" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "block is refused from needs-reassessment, so unblock cannot become a second exit (exit $RC)" $RC_CHK
echo "$NR_BLOCK" | grep -q "reassess"; check "the refused block points the caller at reassess" $?
NR_PAUSE=$(bash "$SCRIPT" pause task-r1 --next-action "sneak out via resume" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "pause is refused from needs-reassessment, so resume cannot become a second exit (exit $RC)" $RC_CHK
echo "$NR_PAUSE" | grep -q "reassess"; check "the refused pause points the caller at reassess" $?
bash "$SCRIPT" unblock task-r1 >/dev/null 2>&1; RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "unblock is refused (the task is not blocked and cannot be made blocked) (exit $RC)" $RC_CHK
bash "$SCRIPT" resume task-r1 >/dev/null 2>&1; RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "resume is refused (the task is not paused and cannot be made paused) (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1
check "state file checksum unchanged after ALL eight refused escape attempts" $RC_CHK
NR_STATE=$(bash "$SCRIPT" status task-r1 | jq -r '.state')
[ "$NR_STATE" = "needs-reassessment" ] && RC_CHK=0 || RC_CHK=1
check "task-r1 is still in needs-reassessment after every escape attempt (got $NR_STATE)" $RC_CHK

echo "== Part 2.2: reassess is the ONLY exit — and it demands a specialist and a finding =="
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" reassess task-r1 --finding "no specialist named" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess without --specialist exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--specialist"; check "error names the missing --specialist flag" $?
OUT=$(bash "$SCRIPT" reassess task-r1 --specialist "Test Engineer" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess without --finding exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--finding"; check "error names the missing --finding flag" $?
OUT=$(bash "$SCRIPT" reassess task-r1 --specialist s --finding f --resume-state "done" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess with an invalid --resume-state exits 2 (got $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" reassess task-c --specialist s --finding f 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "reassess on a task that is NOT in needs-reassessment is refused (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the rejected reassess calls" $RC_CHK

echo "-- reassess with NO --additional-budget: back to work, but still at the cap --"
RA=$(bash "$SCRIPT" reassess task-r1 --specialist "Test Engineer (independent fixture re-read)" \
  --finding "both attempts assumed CRLF; the fixtures are LF and the fault is elsewhere" 2>&1); RC=$?
check "reassess without --additional-budget succeeds" $RC
STATE_R1=$(bash "$SCRIPT" status task-r1)
echo "$STATE_R1" | jq -e '.state == "building"' >/dev/null; check "reassess restores 'building' by default" $?
echo "$STATE_R1" | jq -e '.budget == 2' >/dev/null; check "budget is unchanged when no additional budget is granted" $?
echo "$STATE_R1" | jq -e '.attempts_used == 2' >/dev/null; check "attempts_used is NOT reset by reassess (still 2)" $?
echo "$RA" | grep -qi "no additional budget granted"; check "output says plainly that nothing was granted" $?
echo "$RA" | grep -qi "next 'fail' will put it straight back"; check "output warns the next fail re-trips reassessment" $?
echo "$STATE_R1" | jq -e '.reassessments | length == 1' >/dev/null; check "one reassessment record appended" $?
echo "$STATE_R1" | jq -e '.reassessments[0].specialist == "Test Engineer (independent fixture re-read)"' >/dev/null
check "reassessment record holds the exact specialist text" $?
echo "$STATE_R1" | jq -e '.reassessments[0].finding == "both attempts assumed CRLF; the fixtures are LF and the fault is elsewhere"' >/dev/null
check "reassessment record holds the exact finding text" $?
echo "$STATE_R1" | jq -e '.reassessments[0].additional_budget_granted == 0' >/dev/null
check "reassessment record shows 0 additional budget granted" $?
echo "$STATE_R1" | jq -e '.reassessments[0].attempts_at_reassessment == 2' >/dev/null
check "reassessment record captures attempts_used at reassessment time" $?
echo "$STATE_R1" | jq -e '(.reassessments[0].reassessed_at | type == "string" and length > 0)' >/dev/null
check "reassessment record holds a reassessed_at timestamp" $?

echo "-- ...and the very next failure re-trips reassessment, exactly as the output warned --"
OUT=$(bash "$SCRIPT" fail task-r1 --reason "third attempt also failed" \
  --hypothesis "the LF assumption was wrong too" 2>&1); RC=$?
check "the next fail after an empty-handed reassess is accepted" $RC
STATE_R1=$(bash "$SCRIPT" status task-r1)
echo "$STATE_R1" | jq -e '.state == "needs-reassessment"' >/dev/null
check "one fail past the cap returns the task straight to needs-reassessment" $?
echo "$STATE_R1" | jq -e '.attempts_used == 3' >/dev/null; check "attempts_used is now 3 — it kept counting past the budget" $?

echo "== Part 2.2: --additional-budget N buys exactly N more attempts, and no more =="
bash "$SCRIPT" create task-r2 "Budgeted repair task" --budget 1 >/dev/null 2>&1
bash "$SCRIPT" start task-r2 >/dev/null 2>&1
bash "$SCRIPT" fail task-r2 --reason "first" --hypothesis "theory one" >/dev/null 2>&1
bash "$SCRIPT" status task-r2 | jq -e '.state == "needs-reassessment"' >/dev/null
check "budget=1 means a single failure exhausts the budget immediately" $?
RA=$(bash "$SCRIPT" reassess task-r2 --specialist "Security Auditor" --finding "root cause is in the token parser" --additional-budget 2 2>&1); RC=$?
check "reassess with --additional-budget 2 succeeds" $RC
bash "$SCRIPT" status task-r2 | jq -e '.budget == 3' >/dev/null
check "budget RAISED from 1 to 3 (1 + 2), not reset to 2" $?
bash "$SCRIPT" status task-r2 | jq -e '.attempts_used == 1' >/dev/null
check "attempts_used still 1 after the grant — history is not erased" $?
echo "$RA" | grep -q "2 further repair attempt(s)"; check "output states exactly how many attempts the grant bought (2)" $?
bash "$SCRIPT" fail task-r2 --reason "second" --hypothesis "theory two" >/dev/null 2>&1
bash "$SCRIPT" status task-r2 | jq -e '.state == "building" and .attempts_used == 2' >/dev/null
check "granted attempt 1 of 2: still building" $?
bash "$SCRIPT" fail task-r2 --reason "third" --hypothesis "theory three" >/dev/null 2>&1
bash "$SCRIPT" status task-r2 | jq -e '.state == "needs-reassessment" and .attempts_used == 3' >/dev/null
check "granted attempt 2 of 2 exhausts the raised budget — no third free attempt" $?

echo "-- --resume-state checking is REFUSED for a task that has never been in 'checking' --"
# CONTROL, both directions -- asserting only the success direction would prove
# nothing about whether the check discriminates. task-r2 went
# planned -> building -> fail -> ... and has never once reached 'checking', so
# "restoring" it there would record a needs-reassessment -> checking promotion
# with no building -> checking transition anywhere behind it.
bash "$SCRIPT" status task-r2 | jq -e '[.history[] | select(.to == "checking")] | length == 0' >/dev/null
check "precondition: task-r2 has genuinely never been in 'checking'" $?
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" reassess task-r2 --specialist "Code Reviewer" --finding "the verification method was wrong" \
  --additional-budget 1 --resume-state checking 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "reassess --resume-state checking on a never-checked task is refused (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "never been in state 'checking'"; check "the refusal says the task has never been in 'checking'" $?
echo "$OUT" | grep -qF -- "task-state.sh check task-r2"; check "the refusal names the honest route (reassess, then check)" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the refused --resume-state checking" $RC_CHK
bash "$SCRIPT" status task-r2 | jq -e '.state == "needs-reassessment" and .budget == 3' >/dev/null
check "task-r2 is still stopped at budget 3 — the refused call granted nothing" $?

echo "-- ...and it DOES restore 'checking' for a task that genuinely failed during verification --"
bash "$SCRIPT" create task-rs "Reassess back to checking" --budget 1 >/dev/null 2>&1
bash "$SCRIPT" start task-rs >/dev/null 2>&1
bash "$SCRIPT" check task-rs >/dev/null 2>&1
bash "$SCRIPT" fail task-rs --reason "verifier could not reproduce the claimed artifact" \
  --hypothesis "the artifact path was never written" >/dev/null 2>&1
bash "$SCRIPT" status task-rs | jq -e '.state == "needs-reassessment"' >/dev/null
check "task-rs failed out of budget from 'checking'" $?
RA=$(bash "$SCRIPT" reassess task-rs --specialist "Code Reviewer" --finding "the implementation is fine; the verification method was wrong" \
  --additional-budget 1 --resume-state checking 2>&1); RC=$?
check "reassess --resume-state checking succeeds for a task that WAS actually in checking" $RC
bash "$SCRIPT" status task-rs | jq -e '.state == "checking"' >/dev/null
check "reassess --resume-state checking restores 'checking', not 'building'" $?
bash "$SCRIPT" fail task-rs --reason "still not reproducible" --hypothesis "the verifier and the builder ran different suites" >/dev/null 2>&1
bash "$SCRIPT" reassess task-rs --specialist "Test Engineer" --finding "the suites really did differ" --additional-budget 1 >/dev/null 2>&1
bash "$SCRIPT" status task-rs | jq -e '.reassessments | length == 2' >/dev/null
check "a second reassessment record appended (arrays accumulate, nothing overwritten)" $?

echo "== Part 2.2: CONTROL 1 — attempts_used is strictly monotonic across a full fail->reassess->fail cycle =="
bash "$SCRIPT" create task-mono "Monotonic counter task" --budget 1 >/dev/null 2>&1
bash "$SCRIPT" start task-mono >/dev/null 2>&1
MONO_0=$(bash "$SCRIPT" status task-mono | jq -r '.attempts_used')
bash "$SCRIPT" fail task-mono --reason a --hypothesis "hypothesis alpha" >/dev/null 2>&1
MONO_1=$(bash "$SCRIPT" status task-mono | jq -r '.attempts_used')
bash "$SCRIPT" reassess task-mono --specialist sp --finding "keep going" --additional-budget 1 >/dev/null 2>&1
MONO_2=$(bash "$SCRIPT" status task-mono | jq -r '.attempts_used')
bash "$SCRIPT" fail task-mono --reason b --hypothesis "hypothesis beta" >/dev/null 2>&1
MONO_3=$(bash "$SCRIPT" status task-mono | jq -r '.attempts_used')
bash "$SCRIPT" reassess task-mono --specialist sp --finding "one more" --additional-budget 1 >/dev/null 2>&1
MONO_4=$(bash "$SCRIPT" status task-mono | jq -r '.attempts_used')
[ "$MONO_0" = "0" ] && [ "$MONO_1" = "1" ] && [ "$MONO_2" = "1" ] && [ "$MONO_3" = "2" ] && [ "$MONO_4" = "2" ] && RC_CHK=0 || RC_CHK=1
check "attempts_used never decreases across create->fail->reassess->fail->reassess (0,1,1,2,2; got $MONO_0,$MONO_1,$MONO_2,$MONO_3,$MONO_4)" $RC_CHK
[ "$MONO_2" -ge "$MONO_1" ] && [ "$MONO_4" -ge "$MONO_3" ] && RC_CHK=0 || RC_CHK=1
check "specifically: reassess never lowers the counter it was called to relieve" $RC_CHK

echo "-- ATTACK: no subcommand accepts a flag that would reset the counter --"
CS1=$(checksum "$STATE_FILE")
bash "$SCRIPT" reassess task-mono --specialist sp --finding f --attempts-used 0 >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess --attempts-used is rejected as an unknown option (got $RC)" $RC_CHK
bash "$SCRIPT" fail task-mono --reason r --hypothesis "yet another theory" --attempts-used 0 >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "fail --attempts-used is rejected as an unknown option (got $RC)" $RC_CHK
bash "$SCRIPT" fail task-mono --reason r --hypothesis "another" --attempts 0 >/dev/null 2>&1; RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "fail --attempts is rejected as an unknown option (got $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the counter-reset attempts" $RC_CHK
MONO_5=$(bash "$SCRIPT" status task-mono | jq -r '.attempts_used')
[ "$MONO_5" = "2" ] && RC_CHK=0 || RC_CHK=1; check "attempts_used survived every reset attempt (still $MONO_5)" $RC_CHK

echo "== Part 2.2: CONTROL 2 — budget can only ever be RAISED, and only by reassess =="
BUDGET_BEFORE=$(bash "$SCRIPT" status task-r2 | jq -r '.budget')
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" fail task-r2 --reason r --hypothesis "a brand new theory" --budget 0 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "fail --budget is rejected as an unknown option (got $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" reassess task-r2 --specialist s --finding f --budget 0 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess --budget is rejected as an unknown option (got $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" start task-r2 --budget 0 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "start does not accept a budget flag either (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the budget-lowering attempts" $RC_CHK
BUDGET_AFTER=$(bash "$SCRIPT" status task-r2 | jq -r '.budget')
[ "$BUDGET_BEFORE" = "$BUDGET_AFTER" ] && RC_CHK=0 || RC_CHK=1
check "budget unchanged by every non-reassess path (before=$BUDGET_BEFORE after=$BUDGET_AFTER)" $RC_CHK

echo "-- ...and reassess itself will not grant a zero or negative amount --"
bash "$SCRIPT" create task-neg "Negative-grant task" --budget 1 >/dev/null 2>&1
bash "$SCRIPT" start task-neg >/dev/null 2>&1
bash "$SCRIPT" fail task-neg --reason r --hypothesis "the only theory" >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" reassess task-neg --specialist s --finding f --additional-budget 0 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "--additional-budget 0 is refused as not positive (got $RC)" $RC_CHK
echo "$OUT" | grep -qi "positive integer"; check "the refusal says a positive integer is required" $?
OUT=$(bash "$SCRIPT" reassess task-neg --specialist s --finding f --additional-budget -3 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "--additional-budget -3 is refused (got $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" reassess task-neg --specialist s --finding f --additional-budget abc 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "--additional-budget abc is refused (got $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the three rejected grants" $RC_CHK
bash "$SCRIPT" status task-neg | jq -e '.budget == 1 and .state == "needs-reassessment"' >/dev/null
check "task-neg still capped at budget 1 and still stopped" $?

echo "-- reassess is refused on a HEALTHY task, so budget cannot be inflated pre-emptively --"
bash "$SCRIPT" create task-healthy "Healthy task" >/dev/null 2>&1
bash "$SCRIPT" start task-healthy >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" reassess task-healthy --specialist s --finding f --additional-budget 50 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "reassess on a 'building' task is refused (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "not a general-purpose budget grant"; check "the refusal says reassess is not a general-purpose budget grant" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the pre-emptive inflation attempt" $RC_CHK
bash "$SCRIPT" status task-healthy | jq -e '.budget == 2' >/dev/null; check "task-healthy still at the default budget of 2" $?

echo "== Part 2.2: CONTROL 3 — repeating the previous hypothesis is refused, by name =="
bash "$SCRIPT" create task-hyp "Hypothesis control task" --budget 10 >/dev/null 2>&1
bash "$SCRIPT" start task-hyp >/dev/null 2>&1
HYP_1="The Parser Mishandles Nested Quotes"
bash "$SCRIPT" fail task-hyp --reason "first attempt" --hypothesis "$HYP_1" >/dev/null 2>&1
check "first fail with the original hypothesis succeeds" $?
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" fail task-hyp --reason "second attempt" --hypothesis "$HYP_1" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "repeating the previous hypothesis verbatim is refused (exit $RC)" $RC_CHK
echo "$OUT" | grep -qF -- "$HYP_1"; check "the refusal names the prior hypothesis verbatim" $?
echo "$OUT" | grep -qi "previous hypothesis"; check "the refusal labels it as the previous hypothesis" $?
echo "$OUT" | grep -qi "changed hypothesis"; check "the refusal cites the changed-hypothesis requirement" $?
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the refused repeat" $RC_CHK
bash "$SCRIPT" status task-hyp | jq -e '.attempts_used == 1 and (.attempts | length) == 1' >/dev/null
check "the refused repeat consumed no attempt and recorded nothing" $?

echo "-- ...and the cheapest evasions (case, padding, internal whitespace) do not slip past --"
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" fail task-hyp --reason "sneaky" --hypothesis "  the   parser MISHANDLES nested quotes  " 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "a case-folded, re-spaced restatement of the same hypothesis is still refused (exit $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the re-spaced repeat" $RC_CHK

echo "-- a genuinely different hypothesis is accepted, and only the IMMEDIATELY preceding one is compared --"
bash "$SCRIPT" fail task-hyp --reason "third attempt" --hypothesis "the tokenizer, not the parser, drops the escape" >/dev/null 2>&1
check "a genuinely different hypothesis is accepted" $?
bash "$SCRIPT" fail task-hyp --reason "fourth attempt" --hypothesis "$HYP_1" >/dev/null 2>&1
check "an OLDER hypothesis may be revisited once another attempt has intervened" $?
bash "$SCRIPT" status task-hyp | jq -e '.attempts_used == 3' >/dev/null
check "three attempts recorded on task-hyp" $?

echo "== Part 2.2: missing required flags exit 2 and change nothing =="
bash "$SCRIPT" create task-flags "Flag guard task" >/dev/null 2>&1
bash "$SCRIPT" start task-flags >/dev/null 2>&1
CS1=$(checksum "$STATE_FILE")
OUT=$(bash "$SCRIPT" fail task-flags --hypothesis "h with no reason" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "fail without --reason exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--reason"; check "error names the missing --reason flag" $?
OUT=$(bash "$SCRIPT" fail task-flags --reason "r with no hypothesis" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "fail without --hypothesis exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--hypothesis"; check "error names the missing --hypothesis flag" $?
OUT=$(bash "$SCRIPT" fail 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "fail with no task id exits 2 (got $RC)" $RC_CHK
OUT=$(bash "$SCRIPT" reassess 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess with no task id exits 2 (got $RC)" $RC_CHK
CS2=$(checksum "$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after every missing-flag rejection" $RC_CHK
FLAGS_STATE=$(bash "$SCRIPT" status task-flags | jq -r '.state')
[ "$FLAGS_STATE" = "building" ] && RC_CHK=0 || RC_CHK=1; check "task-flags still 'building' with 0 attempts used (got $FLAGS_STATE)" $RC_CHK
bash "$SCRIPT" status task-flags | jq -e '.attempts_used == 0' >/dev/null
check "task-flags attempts_used still 0 after the rejections" $?

echo "-- a flag given with no trailing value must error, not hang (the regression this file already carries for create/block/pause) --"
if command -v timeout >/dev/null 2>&1; then
  CS1=$(checksum "$STATE_FILE")
  for flagcase in "fail task-flags --reason" "fail task-flags --hypothesis" \
                  "reassess task-flags --specialist" "reassess task-flags --finding" \
                  "reassess task-flags --additional-budget" "reassess task-flags --resume-state"; do
    # shellcheck disable=SC2086
    OUT=$(timeout 5 bash "$SCRIPT" $flagcase 2>&1); RC=$?
    [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "'$flagcase' with no trailing value does not hang (exit $RC, 124=timeout)" $RC_CHK
    [ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "'$flagcase' with no trailing value exits 2 (got $RC)" $RC_CHK
  done
  CS2=$(checksum "$STATE_FILE")
  [ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after every missing-flag-value rejection" $RC_CHK
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely test the fail/reassess missing-flag-value hang regression"
fi

echo "== Part 2.2: the attempts and reassessments arrays accumulate in order =="
bash "$SCRIPT" create task-ord "Ordering task" --budget 1 >/dev/null 2>&1
bash "$SCRIPT" start task-ord >/dev/null 2>&1
bash "$SCRIPT" fail task-ord --reason "reason one" --hypothesis "hypothesis one" >/dev/null 2>&1
bash "$SCRIPT" reassess task-ord --specialist "specialist one" --finding "finding one" --additional-budget 1 >/dev/null 2>&1
bash "$SCRIPT" fail task-ord --reason "reason two" --hypothesis "hypothesis two" >/dev/null 2>&1
bash "$SCRIPT" reassess task-ord --specialist "specialist two" --finding "finding two" --additional-budget 1 >/dev/null 2>&1
bash "$SCRIPT" fail task-ord --reason "reason three" --hypothesis "hypothesis three" >/dev/null 2>&1
STATE_ORD=$(bash "$SCRIPT" status task-ord)
echo "$STATE_ORD" | jq -e '.attempts | length == 3' >/dev/null; check "three attempt records accumulated" $?
echo "$STATE_ORD" | jq -e '.reassessments | length == 2' >/dev/null; check "two reassessment records accumulated" $?
echo "$STATE_ORD" | jq -e '[.attempts[].attempt_number] == [1,2,3]' >/dev/null
check "attempt_number runs 1,2,3 in order, none skipped or reused" $?
echo "$STATE_ORD" | jq -e '[.attempts[].reason] == ["reason one","reason two","reason three"]' >/dev/null
check "attempts are stored oldest-first, in fail order" $?
echo "$STATE_ORD" | jq -e '[.reassessments[].specialist] == ["specialist one","specialist two"]' >/dev/null
check "reassessments are stored oldest-first, in reassess order" $?
echo "$STATE_ORD" | jq -e '[.reassessments[].attempts_at_reassessment] == [1,2]' >/dev/null
check "each reassessment captured the attempts_used it was called at (1 then 2)" $?
echo "$STATE_ORD" | jq -e '.budget == 3 and .attempts_used == 3' >/dev/null
check "budget ended at 1+1+1=3 and attempts_used at 3" $?

echo "== Part 2.2: a needs-reassessment task cannot be completed via complete-gate.sh =="
if ! command -v git >/dev/null 2>&1; then
  echo "  SKIP: git not on PATH — complete-gate.sh's staleness check needs it"
else
  RGATE_DIR=$(mktemp -d)
  ( cd "$RGATE_DIR" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
  echo ".claude/state/" > "$RGATE_DIR/.gitignore"
  echo "base content" > "$RGATE_DIR/tracked.txt"
  ( cd "$RGATE_DIR" && git add .gitignore tracked.txt && git commit -qm init ) >/dev/null 2>&1

  # Same design as the paused-task gate test above: drive BOTH tasks
  # identically to genuinely gate-passing evidence, and change only ONE thing
  # about one of them (here: fail it out of budget). Without the control, a
  # gate refusal would prove nothing — it could just as easily mean the
  # evidence setup was broken. Create every evidence file BEFORE recording any
  # evidence, since each untracked file moves compute_snapshot()'s hash.
  for t in rgate-ctrl rgate-stopped; do
    ( cd "$RGATE_DIR" && bash "$SCRIPT" create "$t" "Gate task $t" --budget 1 \
      && bash "$SCRIPT" start "$t" && bash "$SCRIPT" check "$t" ) >/dev/null 2>&1
    echo "real evidence output for $t" > "$RGATE_DIR/$t-output.txt"
    echo "real artifact for $t" > "$RGATE_DIR/$t-artifact.txt"
  done
  for t in rgate-ctrl rgate-stopped; do
    ( cd "$RGATE_DIR" && bash "$SCRIPT" record-evidence "$t" --command "bash tests/task-state-smoke.sh" \
      --exit-code 0 --tests-total 9 --tests-skipped 0 \
      --output-file "$t-output.txt" --artifact "$t-artifact.txt" ) >/dev/null 2>&1
  done

  echo "-- control: an identically-prepared task that was never failed passes the gate --"
  RCTRL_OUT=$(cd "$RGATE_DIR" && bash "$GATE" rgate-ctrl 2>&1); RC=$?
  check "control task's evidence is genuinely gate-passing (exit $RC)" $RC
  echo "$RCTRL_OUT" | grep -q "GATE PASS"; check "control task prints GATE PASS" $?
  RCTRL_STATE=$(cd "$RGATE_DIR" && bash "$SCRIPT" status rgate-ctrl | jq -r '.state')
  [ "$RCTRL_STATE" = "done" ] && RC_CHK=0 || RC_CHK=1; check "control task reached 'done' (got $RCTRL_STATE)" $RC_CHK

  echo "-- the out-of-budget task, same evidence, is refused --"
  ( cd "$RGATE_DIR" && bash "$SCRIPT" fail rgate-stopped --reason "verifier found the artifact does not match the claim" \
    --hypothesis "the builder tested a different file than the one it shipped" ) >/dev/null 2>&1
  RSTOP_STATE=$(cd "$RGATE_DIR" && bash "$SCRIPT" status rgate-stopped | jq -r '.state')
  [ "$RSTOP_STATE" = "needs-reassessment" ] && RC_CHK=0 || RC_CHK=1
  check "rgate-stopped really is in needs-reassessment before the gate runs (got $RSTOP_STATE)" $RC_CHK
  RGATE_OUT=$(cd "$RGATE_DIR" && bash "$GATE" rgate-stopped 2>&1); RC=$?
  [ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh refuses a needs-reassessment task (exit $RC)" $RC_CHK
  echo "$RGATE_OUT" | grep -q "GATE FAIL"; check "gate output says GATE FAIL" $?
  echo "$RGATE_OUT" | grep -q "needs-reassessment"; check "gate failure names the offending state (needs-reassessment)" $?
  RAFTER_STATE=$(cd "$RGATE_DIR" && bash "$SCRIPT" status rgate-stopped | jq -r '.state')
  [ "$RAFTER_STATE" = "needs-reassessment" ] && RC_CHK=0 || RC_CHK=1
  check "the refused task is still 'needs-reassessment', not 'done' (got $RAFTER_STATE)" $RC_CHK

  echo "-- and it becomes completable again only after a reassessment back to 'checking' --"
  ( cd "$RGATE_DIR" && bash "$SCRIPT" reassess rgate-stopped --specialist "Test Engineer" \
    --finding "the artifact claim was a path typo; the shipped file is correct" --resume-state checking ) >/dev/null 2>&1
  RREOPEN_STATE=$(cd "$RGATE_DIR" && bash "$SCRIPT" status rgate-stopped | jq -r '.state')
  [ "$RREOPEN_STATE" = "checking" ] && RC_CHK=0 || RC_CHK=1; check "reassess restored 'checking' (got $RREOPEN_STATE)" $RC_CHK
  RGATE_OUT2=$(cd "$RGATE_DIR" && bash "$GATE" rgate-stopped 2>&1); RC=$?
  check "the same evidence now passes the gate once the task is back in 'checking' (exit $RC)" $RC
  echo "$RGATE_OUT2" | grep -q "GATE PASS"; check "the reopened task prints GATE PASS on the same evidence" $?
  RFINAL_STATE=$(cd "$RGATE_DIR" && bash "$SCRIPT" status rgate-stopped | jq -r '.state')
  [ "$RFINAL_STATE" = "done" ] && RC_CHK=0 || RC_CHK=1; check "task independently re-reads as 'done' after the gate passed (got $RFINAL_STATE)" $RC_CHK
  rm -rf "$RGATE_DIR"
fi

echo "== Part 2.2: the record-* subcommands are refused from 'needs-reassessment' (a frozen task's RECORD is frozen too) =="
# These three do not change state, so allowing them was never a completion
# bypass -- complete-gate.sh independently requires 'checking'. What they did
# allow was an audit trail that kept accreting on a task that is supposed to
# be stopped, contradicting the contract that this state accepts nothing
# further.
F3_DIR=$(mktemp -d)
( cd "$F3_DIR" && bash "$SCRIPT" create f3 "Frozen record task" --budget 1 \
  && bash "$SCRIPT" start f3 \
  && bash "$SCRIPT" fail f3 --reason "r" --hypothesis "the only theory" ) >/dev/null 2>&1
echo "evidence output" > "$F3_DIR/f3-output.txt"
jq -e '.tasks.f3.state == "needs-reassessment"' "$F3_DIR/$STATE_FILE" >/dev/null
check "precondition: f3 really is in needs-reassessment" $?
CS1=$(checksum "$F3_DIR/$STATE_FILE")
OUT=$(cd "$F3_DIR" && bash "$SCRIPT" record-assignment f3 --role builder --agent-type team-builder 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "record-assignment is refused from needs-reassessment (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "reassess"; check "the refused record-assignment points the caller at reassess" $?
OUT=$(cd "$F3_DIR" && bash "$SCRIPT" record-evidence f3 --command "bash tests/x.sh" --exit-code 0 \
  --tests-total 1 --tests-skipped 0 --output-file f3-output.txt 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "record-evidence is refused from needs-reassessment (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "reassess"; check "the refused record-evidence points the caller at reassess" $?
OUT=$(cd "$F3_DIR" && bash "$SCRIPT" record-external-action f3 --key pr-1 --description "open the PR" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "record-external-action is refused from needs-reassessment (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "reassess"; check "the refused record-external-action points the caller at reassess" $?
echo "$OUT" | grep -q "RECORDED-EXTERNAL-ACTION"; RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "the refusal is NOT the record-first 'go ahead' word, so a record-first caller will not act" $RC_CHK
CS2=$(checksum "$F3_DIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after all three refused record-* calls" $RC_CHK
jq -e '(.tasks.f3.assignments | length) == 0 and (.tasks.f3.evidence | length) == 0
       and (.tasks.f3.external_actions | length) == 0' "$F3_DIR/$STATE_FILE" >/dev/null
check "not one entry was appended to assignments, evidence or external_actions" $?
rm -rf "$F3_DIR"

echo "-- CONTROL: the same three ARE accepted from 'paused' and 'blocked' — those are suspensions, not stops --"
# Deliberate, not an oversight. `pause` and `block` are designed to be resumed
# into the exact state they came from, and the record-first external-action
# idiom is part of the very wrap-up sequence `pause` exists to support.
# Without this control, the refusals above would prove nothing about whether
# the check discriminates between a stop and a suspension.
for susp in paused blocked; do
  SUSP_DIR=$(mktemp -d)
  ( cd "$SUSP_DIR" && bash "$SCRIPT" create s "Suspended task" && bash "$SCRIPT" start s ) >/dev/null 2>&1
  if [ "$susp" = "paused" ]; then
    ( cd "$SUSP_DIR" && bash "$SCRIPT" pause s --next-action "open the PR, then resume" ) >/dev/null 2>&1
  else
    ( cd "$SUSP_DIR" && bash "$SCRIPT" block s "waiting on review" ) >/dev/null 2>&1
  fi
  echo "evidence output" > "$SUSP_DIR/s-output.txt"
  jq -e --arg s "$susp" '.tasks.s.state == $s' "$SUSP_DIR/$STATE_FILE" >/dev/null
  check "precondition: s really is '$susp'" $?
  ( cd "$SUSP_DIR" && bash "$SCRIPT" record-assignment s --role builder --agent-type team-builder ) >/dev/null 2>&1
  check "record-assignment is accepted from '$susp'" $?
  ( cd "$SUSP_DIR" && bash "$SCRIPT" record-evidence s --command "bash tests/x.sh" --exit-code 0 \
    --tests-total 1 --tests-skipped 0 --output-file s-output.txt ) >/dev/null 2>&1
  check "record-evidence is accepted from '$susp'" $?
  EA_OUT=$(cd "$SUSP_DIR" && bash "$SCRIPT" record-external-action s --key pr-1 --description "open the PR" 2>&1); RC=$?
  check "record-external-action is accepted from '$susp'" $RC
  echo "$EA_OUT" | grep -q "RECORDED-EXTERNAL-ACTION"
  check "the record-first idiom still returns its 'go ahead' word from '$susp'" $?
  jq -e --arg s "$susp" '.tasks.s.state == $s and (.tasks.s.assignments | length) == 1
         and (.tasks.s.evidence | length) == 1 and (.tasks.s.external_actions | length) == 1' \
    "$SUSP_DIR/$STATE_FILE" >/dev/null
  check "all three records landed and the '$susp' state itself is untouched" $?
  rm -rf "$SUSP_DIR"
done

echo "== Part 2.2: whitespace-only flag values are refused exactly as empty ones are =="
# A durably-recorded "   " carries no more accountability than "" does, but it
# stores as a field that LOOKS answered -- which is worse than an outright
# refusal, because it survives review.
WS_DIR=$(mktemp -d)
( cd "$WS_DIR" && bash "$SCRIPT" create ws "Whitespace guard task" --budget 1 \
  && bash "$SCRIPT" start ws ) >/dev/null 2>&1
CS1=$(checksum "$WS_DIR/$STATE_FILE")
OUT=$(cd "$WS_DIR" && bash "$SCRIPT" fail ws --reason "   " --hypothesis "a real theory" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "fail with a whitespace-only --reason exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--reason"; check "the refusal names the offending --reason flag" $?
OUT=$(cd "$WS_DIR" && bash "$SCRIPT" fail ws --reason "a real reason" --hypothesis "$(printf ' \t\n ')" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1
check "fail with a tab/newline-only --hypothesis exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--hypothesis"; check "the refusal names the offending --hypothesis flag" $?
CS2=$(checksum "$WS_DIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the blank fail rejections" $RC_CHK
jq -e '.tasks.ws.attempts_used == 0 and (.tasks.ws.attempts | length) == 0' "$WS_DIR/$STATE_FILE" >/dev/null
check "no attempt was consumed and nothing was recorded" $?

( cd "$WS_DIR" && bash "$SCRIPT" fail ws --reason "a real reason" --hypothesis "a real theory" ) >/dev/null 2>&1
jq -e '.tasks.ws.state == "needs-reassessment"' "$WS_DIR/$STATE_FILE" >/dev/null
check "ws is now stopped, so reassess's own flags can be exercised" $?
CS1=$(checksum "$WS_DIR/$STATE_FILE")
OUT=$(cd "$WS_DIR" && bash "$SCRIPT" reassess ws --specialist "  " --finding "a real finding" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess with a whitespace-only --specialist exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--specialist"; check "the refusal names the offending --specialist flag" $?
OUT=$(cd "$WS_DIR" && bash "$SCRIPT" reassess ws --specialist "a real specialist" --finding "$(printf '\t')" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "reassess with a tab-only --finding exits 2 (got $RC)" $RC_CHK
echo "$OUT" | grep -qi -- "--finding"; check "the refusal names the offending --finding flag" $?
CS2=$(checksum "$WS_DIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1; check "state file checksum unchanged after the blank reassess rejections" $RC_CHK
jq -e '.tasks.ws.state == "needs-reassessment" and (.tasks.ws.reassessments | length) == 0' "$WS_DIR/$STATE_FILE" >/dev/null
check "the task is still stopped and no blank reassessment was recorded" $?
rm -rf "$WS_DIR"

echo "== Part 2.2: 20 concurrent fails on one task lose no attempt increments =="
# The attempt counter is a read-modify-write, exactly the shape that raced
# before Part 1.2's lock existed. A lost update here would silently hand a
# task free repair attempts it never earned — the endless loop this part is
# supposed to bound. Budget 30 so none of the 20 trips the cap; every
# hypothesis is distinct so none is refused by the changed-hypothesis control.
if command -v timeout >/dev/null 2>&1; then
  CONC_F_DIR=$(mktemp -d)
  ( cd "$CONC_F_DIR" && bash "$SCRIPT" create f-conc "Concurrent fail task" --budget 30 \
    && bash "$SCRIPT" start f-conc ) >/dev/null 2>&1
  timeout 60 bash -c '
    SCRIPT="$1"; DIR="$2"; N="$3"
    PIDS=()
    for i in $(seq 1 "$N"); do
      ( cd "$DIR" && bash "$SCRIPT" fail f-conc --reason "concurrent failure $i" \
          --hypothesis "distinct hypothesis number $i" >/dev/null 2>&1 ) &
      PIDS+=("$!")
    done
    for pid in "${PIDS[@]}"; do wait "$pid"; done
  ' _ "$SCRIPT" "$CONC_F_DIR" 20
  RC=$?
  [ "$RC" != "124" ] && RC_CHK=0 || RC_CHK=1; check "20 concurrent fails complete without deadlocking on the lock (exit $RC, 124=timeout)" $RC_CHK
  CONC_F_USED=$(jq -r '.tasks["f-conc"].attempts_used' "$CONC_F_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$CONC_F_USED" = "20" ] && RC_CHK=0 || RC_CHK=1
  check "attempts_used is exactly 20 after 20 concurrent fails — no increment lost (got ${CONC_F_USED:-0})" $RC_CHK
  CONC_F_LEN=$(jq -r '.tasks["f-conc"].attempts | length' "$CONC_F_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$CONC_F_LEN" = "20" ] && RC_CHK=0 || RC_CHK=1
  check "exactly 20 attempt records were appended, none clobbered (got ${CONC_F_LEN:-0})" $RC_CHK
  CONC_F_UNIQ=$(jq -r '[.tasks["f-conc"].attempts[].attempt_number] | unique | length' "$CONC_F_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$CONC_F_UNIQ" = "20" ] && RC_CHK=0 || RC_CHK=1
  check "all 20 attempt_numbers are distinct — the counter never handed out the same number twice (got ${CONC_F_UNIQ:-0})" $RC_CHK
  CONC_F_MAX=$(jq -r '[.tasks["f-conc"].attempts[].attempt_number] | max' "$CONC_F_DIR/.claude/state/team-tasks.json" 2>/dev/null)
  [ "$CONC_F_MAX" = "20" ] && RC_CHK=0 || RC_CHK=1
  check "the highest attempt_number is exactly 20, matching attempts_used (got ${CONC_F_MAX:-0})" $RC_CHK
  rm -rf "$CONC_F_DIR"
else
  echo "  SKIP: 'timeout' not on PATH, cannot safely bound the concurrent-fail test"
fi

echo "== FAIL-CLOSED READS: a state field that is PRESENT but wrong-typed REFUSES, it never degrades a guard =="
# ONE DEFECT, NOT MANY. Three consecutive reviews found the same shape in a
# different field each time (attempts_used/budget, then the gate's
# tests_total/exit_code/artifacts/output_file, then hypothesis/
# external_actions/checkpoints). The shape: A VALUE THAT CANNOT BE PARSED IS
# SILENTLY CONVERTED INTO A VALUE THAT MEANS "THE CONDITION WAS NOT MET", SO A
# SAFETY CHECK BECOMES A NO-OP INSTEAD OF AN ERROR. In jq/bash it spells itself
# `// ""`, `// 0`, `// []`, `[]?`, a bare `?`, a `2>/dev/null` on a jq whose
# output is then compared, or a `[ ... ]` whose operand can arrive as the
# literal string "null".
#
# This section therefore tests the CLASS across every read in task-state.sh
# that gates something, not the three instances that happened to be reported.
# Each case asserts all four of:
#   1. the operation is REFUSED with the expected nonzero exit,
#   2. the message NAMES the offending field,
#   3. NO bash or jq diagnostic leaks into the output -- a guard that "works"
#      by making `[` print "integer expression expected" is the bug, not the
#      fix, so a refusal accompanied by one would not count as a pass,
#   4. the state file is BYTE-FOR-BYTE unchanged.
# A PASSING CONTROL for every one of these commands runs at the end of the
# section, so none of these refusals can be vacuous.

# hs_* : fixture builders. Each runs inside an already-cd'd isolated dir.
hs_failed()   { bash "$SCRIPT" create c "Hardening fixture" --budget 9; bash "$SCRIPT" start c; bash "$SCRIPT" fail c --reason "r1" --hypothesis "theory one"; }
hs_paused()   { bash "$SCRIPT" create c "Hardening fixture"; bash "$SCRIPT" start c; bash "$SCRIPT" pause c --next-action "rerun the migration by hand"; }
hs_blocked()  { bash "$SCRIPT" create c "Hardening fixture"; bash "$SCRIPT" start c; bash "$SCRIPT" block c "waiting on review"; }
hs_ea()       { bash "$SCRIPT" create c "Hardening fixture"; bash "$SCRIPT" start c; bash "$SCRIPT" record-external-action c --key K1 --description "opened PR #7"; }
hs_dep()      { bash "$SCRIPT" create d1 "Dependency"; bash "$SCRIPT" create c "Hardening fixture" --depends d1; }
hs_stopped()  { bash "$SCRIPT" create c "Hardening fixture"; bash "$SCRIPT" start c; bash "$SCRIPT" fail c --reason "r1" --hypothesis "theory one"; bash "$SCRIPT" fail c --reason "r2" --hypothesis "theory two"; }
hs_building() { bash "$SCRIPT" create c "Hardening fixture"; bash "$SCRIPT" start c; }
# Reached 'checking' for real, then failed out of budget -- the ONLY shape for
# which `reassess --resume-state checking` is legitimate, so it is the fixture
# that can tell "the guard refused because the history is unreadable" apart from
# "the guard refused because this task never reached checking".
hs_checked_stopped() { bash "$SCRIPT" create c "Hardening fixture" --budget 1; bash "$SCRIPT" start c; bash "$SCRIPT" check c; bash "$SCRIPT" fail c --reason "r1" --hypothesis "theory one"; }

# harden_dir <setup-fn> <jq-corruption-program> -> prints an isolated dir whose
# state file has been hand-corrupted. Hand-editing is the only way to
# manufacture a corrupt record, and it only ever touches a throwaway mktemp
# state file, never a real project's.
harden_dir() {
  local fn="$1" corrupt="$2" dir
  dir=$(mktemp -d)
  ( cd "$dir" && "$fn" ) >/dev/null 2>&1
  jq "$corrupt" "$dir/$STATE_FILE" > "$dir/h.tmp" && mv "$dir/h.tmp" "$dir/$STATE_FILE"
  printf '%s' "$dir"
}

# harden_case <label> <setup-fn> <jq-corruption> <field-named-in-message>
#             <expected-exit> <subcommand and args...>
harden_case() {
  local label="$1" fn="$2" corrupt="$3" field="$4" want="$5"
  shift 5
  local dir cs1 cs2 out rc noise verdict
  dir=$(harden_dir "$fn" "$corrupt")
  cs1=$(checksum "$dir/$STATE_FILE")
  out=$(cd "$dir" && bash "$SCRIPT" "$@" 2>&1); rc=$?
  [ "$rc" = "$want" ] && verdict=0 || verdict=1
  check "$label: refused with exit $want (got $rc)" "$verdict"
  # QUOTED field name, not a bare substring. A bare grep for "state" also
  # matches "state file" and "is in state ''", and a bare grep for "tasks"
  # matches "team-tasks.json" -- so the loose form would have counted the OLD,
  # accidental refusals as "named the field" and quietly weakened this whole
  # section. The refusals name a record field as 'field' and an entry key as
  # "key", so accept either quoting and nothing else.
  echo "$out" | grep -qE "'$field'|\"$field\""; check "$label: the refusal names '$field'" $?
  echo "$out" | grep -qE "integer expression expected|unary operator expected|Cannot iterate|Cannot index|has no length|jq: error|not a valid number|cannot be added"; noise=$?
  [ "$noise" != "0" ] && verdict=0 || verdict=1
  check "$label: no bash or jq diagnostic leaked into the output" "$verdict"
  cs2=$(checksum "$dir/$STATE_FILE")
  [ "$cs1" = "$cs2" ] && verdict=0 || verdict=1
  check "$label: state file byte-for-byte unchanged" "$verdict"
  rm -rf "$dir"
}

echo "-- the reported CRITICAL: fail's changed-hypothesis control (a null prior hypothesis switched it OFF permanently) --"
# `def norm: (. // "") | ...` turned a stored null into "", and the INCOMING
# hypothesis is already validated non-blank, so `"" == it` could never be true
# and the identical theory could be resubmitted forever.
harden_case "hypothesis=null" hs_failed '.tasks.c.attempts[-1].hypothesis = null' \
  hypothesis 1 fail c --reason "r2" --hypothesis "theory one"
harden_case "hypothesis=42" hs_failed '.tasks.c.attempts[-1].hypothesis = 42' \
  hypothesis 1 fail c --reason "r2" --hypothesis "theory one"
harden_case "hypothesis=\"\"" hs_failed '.tasks.c.attempts[-1].hypothesis = ""' \
  hypothesis 1 fail c --reason "r2" --hypothesis "theory one"
harden_case "attempts[-1] is not an object" hs_failed '.tasks.c.attempts[-1] = "an attempt"' \
  attempts 1 fail c --reason "r2" --hypothesis "theory two"
# And the same control seen from the other side: with the prior hypothesis
# restored to a usable value, a REPEAT is still refused (proving the fix did
# not simply delete the control it was meant to protect).
HREP_DIR=$(harden_dir hs_failed '.tasks.c.title = "Hardening fixture"')
OUT=$(cd "$HREP_DIR" && bash "$SCRIPT" fail c --reason "r2" --hypothesis "  THEORY   ONE  " 2>&1); RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1
check "the changed-hypothesis control still refuses a normalised repeat on an intact record (exit $RC)" $RC_CHK
echo "$OUT" | grep -qF "theory one"; check "that refusal still quotes the previous hypothesis verbatim" $?
rm -rf "$HREP_DIR"

echo "-- attempts array shape: the monotonic-counter guard cannot be blinded by corrupting its own audit trail --"
# The old `[ (.attempts // []) | .[]? | .attempt_number? | numbers ]` plus a
# degrade-to-0 turned an unreadable attempts array into "no recorded
# attempts", which is the exact answer that switches the guard off: corrupt
# the entries and delete attempts_used, and the counter reset to 0 and
# re-issued attempt_number 1.
harden_case "attempts entries are strings + attempts_used deleted" hs_failed \
  '.tasks.c.attempts = ["a","b"] | del(.tasks.c.attempts_used)' \
  attempts 1 fail c --reason "r2" --hypothesis "theory two"
harden_case "attempts=true" hs_failed '.tasks.c.attempts = true' \
  attempts 1 fail c --reason "r2" --hypothesis "theory two"
harden_case "attempt_number is a string" hs_failed '.tasks.c.attempts[-1].attempt_number = "1"' \
  attempts 1 fail c --reason "r2" --hypothesis "theory two"
harden_case "attempt_number is fractional" hs_failed '.tasks.c.attempts[-1].attempt_number = 1.5' \
  attempts 1 fail c --reason "r2" --hypothesis "theory two"

echo "-- start's dependency guard: the identical [] ? hole that was just fixed in complete-gate.sh's artifacts[] --"
# `.depends_on[]?` yields NOTHING when depends_on is not iterable, and "no
# dependencies" is the answer that lets a task dispatch while its dependency
# is still planned.
harden_case "depends_on is a bare string" hs_dep '.tasks.c.depends_on = "d1"' \
  depends_on 1 start c
harden_case "depends_on=true" hs_dep '.tasks.c.depends_on = true' \
  depends_on 1 start c
harden_case "depends_on holds a number" hs_dep '.tasks.c.depends_on = [123]' \
  depends_on 1 start c
harden_case "depends_on holds an empty string" hs_dep '.tasks.c.depends_on = [""]' \
  depends_on 1 start c
# The dependency's OWN record being corrupt must refuse too, not silently drop
# that dependency out of the unmet list.
harden_case "a dependency's record is not an object" hs_dep '.tasks.d1 = "planned"' \
  state 1 start c

echo "-- resume's no-checkpoint guard and the checkpoint it restores --"
# `(.checkpoints // []) | length` errored on a boolean, leaving CP_COUNT empty,
# and `[ "" -eq 0 ]` returned 2, which the `if` read as "condition not met" --
# so the guard was SKIPPED and resume printed an empty next action.
harden_case "checkpoints=true" hs_paused '.tasks.c.checkpoints = true' \
  checkpoints 1 resume c
harden_case "checkpoints is a string" hs_paused '.tasks.c.checkpoints = "x"' \
  checkpoints 1 resume c
harden_case "checkpoints holds a non-object entry" hs_paused '.tasks.c.checkpoints = [["not an object"]]' \
  checkpoints 1 resume c
harden_case "next_action=null" hs_paused '.tasks.c.checkpoints[-1].next_action = null' \
  next_action 1 resume c
harden_case "next_action is missing" hs_paused 'del(.tasks.c.checkpoints[-1].next_action)' \
  next_action 1 resume c
harden_case "code_snapshot=null" hs_paused '.tasks.c.checkpoints[-1].code_snapshot = null' \
  code_snapshot 1 resume c
# pause refuses at the point of WRITING to a corrupt checkpoints array too, not
# only when resume later reads the damage back.
harden_case "pause onto a corrupt checkpoints array" hs_building '.tasks.c.checkpoints = true' \
  checkpoints 1 pause c --next-action "do the thing"

echo "-- external-action idempotency: a false PROCEED here IS the duplicate-PR bug --"
# `map(select(.key == $key))` aborts the whole jq program on a single
# non-object entry, and both call sites read the empty result as "not
# recorded": record-external-action appended a DUPLICATE, and
# check-external-action answered NOT-RECORDED / PROCEED for a recorded key.
harden_case "external_actions holds a non-object entry (record)" hs_ea \
  '.tasks.c.external_actions = ["junk"] + .tasks.c.external_actions' \
  external_actions 1 record-external-action c --key K1 --description "opened PR #7"
harden_case "external_actions=true (record)" hs_ea '.tasks.c.external_actions = true' \
  external_actions 1 record-external-action c --key K1 --description "opened PR #7"
harden_case "an entry's key is null (record)" hs_ea '.tasks.c.external_actions[0].key = null' \
  external_actions 1 record-external-action c --key K1 --description "opened PR #7"
# check-external-action's refusals MUST be exit 3, never 1: exit 1 is its
# documented "CONFIRMED NOT RECORDED -> PROCEED" answer, so a corruption
# refusal that exited 1 would tell the caller to go and open the PR again.
harden_case "external_actions holds a non-object entry (check)" hs_ea \
  '.tasks.c.external_actions = ["junk"] + .tasks.c.external_actions' \
  external_actions 3 check-external-action c --key K1
harden_case "external_actions=true (check)" hs_ea '.tasks.c.external_actions = true' \
  external_actions 3 check-external-action c --key K1
harden_case "an entry's key is null (check)" hs_ea '.tasks.c.external_actions[0].key = null' \
  external_actions 3 check-external-action c --key K1
# Explicitly: NOT exit 1, and the word PROCEED must not appear.
XC_DIR=$(harden_dir hs_ea '.tasks.c.external_actions = ["junk"] + .tasks.c.external_actions')
XC_OUT=$(cd "$XC_DIR" && bash "$SCRIPT" check-external-action c --key K1 2>&1); XC_RC=$?
[ "$XC_RC" != "1" ] && RC_CHK=0 || RC_CHK=1
check "a corrupt external_actions NEVER exits 1 from check-external-action (exit $XC_RC — 1 would mean PROCEED)" $RC_CHK
echo "$XC_OUT" | grep -q "PROCEED"; RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "and it never prints PROCEED for a record it could not read" $RC_CHK
rm -rf "$XC_DIR"

echo "-- blocked_from / paused_from: an unvalidated restore target was a COMPLETION BYPASS --"
# unblock restored whatever string it found, so a blocked_from hand-set to
# "done" moved the task straight to done — past checking, past
# complete-gate.sh, past the entire verification contract, printing success.
harden_case "blocked_from=\"done\" (completion bypass)" hs_blocked '.tasks.c.blocked_from = "done"' \
  blocked_from 1 unblock c
harden_case "blocked_from=true" hs_blocked '.tasks.c.blocked_from = true' \
  blocked_from 1 unblock c
harden_case "paused_from=\"done\" (completion bypass)" hs_paused '.tasks.c.paused_from = "done"' \
  paused_from 1 resume c
harden_case "paused_from=[\"building\"]" hs_paused '.tasks.c.paused_from = ["building"]' \
  paused_from 1 resume c
# And the state really did not move.
UB_DIR=$(harden_dir hs_blocked '.tasks.c.blocked_from = "done"')
( cd "$UB_DIR" && bash "$SCRIPT" unblock c ) >/dev/null 2>&1
jq -e '.tasks.c.state == "blocked"' "$UB_DIR/$STATE_FILE" >/dev/null
check "the task is still blocked after the refused unblock — it did not reach 'done'" $?
rm -rf "$UB_DIR"

echo "-- the state field itself: the read EVERY subcommand branches on --"
# `.tasks[$id].state // "missing"` could not tell a task that does not exist
# from one whose state is an array, and a state that matched no state name read
# as "this task is not in needs-reassessment" — walking straight through the
# frozen-record stop.
harden_case "state=[\"needs-reassessment\"] (freeze bypass)" hs_stopped '.tasks.c.state = ["needs-reassessment"]' \
  state 1 record-external-action c --key K --description "posted a note"
harden_case "state=null" hs_building '.tasks.c.state = null' state 1 check c
harden_case "state=42" hs_building '.tasks.c.state = 42' state 1 check c
harden_case "the task record is not an object" hs_building '.tasks.c = "building"' \
  state 1 check c
harden_case ".tasks is an array" hs_building '.tasks = []' tasks 1 create newtask "New task"
# A record corrupted to null must not read as "no such task" and let create
# silently REPLACE it (the duplicate-id guard degrading into permission).
NULLNODE_DIR=$(harden_dir hs_building '.tasks.c = null')
CS1=$(checksum "$NULLNODE_DIR/$STATE_FILE")
OUT=$(cd "$NULLNODE_DIR" && bash "$SCRIPT" create c "Replacement" 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "create over a task record corrupted to null is refused, not silently replaced (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "already exists"; check "the refusal says the task already exists" $?
CS2=$(checksum "$NULLNODE_DIR/$STATE_FILE")
[ "$CS1" = "$CS2" ] && RC_CHK=0 || RC_CHK=1
check "state file byte-for-byte unchanged after the refused create" $RC_CHK
rm -rf "$NULLNODE_DIR"

echo "-- the append-only arrays: refused BY NAME rather than as an anonymous jq blow-up --"
harden_case "history=true" hs_building '.tasks.c.history = true' history 1 check c
harden_case "assignments=true" hs_building '.tasks.c.assignments = true' \
  assignments 1 record-assignment c --role builder --agent-type team-builder
harden_case "evidence=true" hs_building '.tasks.c.evidence = true' \
  evidence 1 record-evidence c --command "true" --exit-code 0 --tests-total 1 --tests-skipped 0 --output-file out.txt
harden_case "reassessments=true" hs_stopped '.tasks.c.reassessments = true' \
  reassessments 1 reassess c --specialist sp --finding "the finding"
harden_case "history=true blocks --resume-state checking" hs_stopped '.tasks.c.history = true' \
  history 1 reassess c --specialist sp --finding "the finding" --resume-state checking

echo "-- the 'has this task EVER reached checking?' guard, now routed through the shared family --"
# This was the last decision-bearing read in the file still hand-rolled at its
# call site, with its own inline jq and its own `case`. Two of its behaviours
# are what a one-off gets you, and both are asserted here against a fixture that
# GENUINELY reached 'checking' (so a refusal cannot be explained away as "this
# task never got there"):
#   1. `select(type == "object")` SKIPPED non-object history entries, so a
#      history holding garbage was quietly counted rather than refused.
#   2. `.to` was read with no type check at all, so an entry whose destination
#      had been nulled or deleted still counted as a valid transition record --
#      the guard answering from a record it could not actually read.
# Under the old inline read both of these ALLOWED the promotion (exit 0). They
# now refuse, by name.
harden_case "history holds a non-object entry (ever-checked guard)" hs_checked_stopped \
  '.tasks.c.history += [["not an object"]]' \
  history 1 reassess c --specialist sp --finding "the finding" --resume-state checking
harden_case "a history entry's 'to' is null (ever-checked guard)" hs_checked_stopped \
  '.tasks.c.history[-1].to = null' \
  history 1 reassess c --specialist sp --finding "the finding" --resume-state checking
harden_case "a history entry has no 'to' at all (ever-checked guard)" hs_checked_stopped \
  'del(.tasks.c.history[-1].to)' \
  history 1 reassess c --specialist sp --finding "the finding" --resume-state checking
harden_case "a history entry's 'to' is a number (ever-checked guard)" hs_checked_stopped \
  '.tasks.c.history[-1].to = 42' \
  history 1 reassess c --specialist sp --finding "the finding" --resume-state checking
# CONTROL, same fixture, uncorrupted: the promotion this guard protects must
# still SUCCEED for a task that really did reach 'checking', or the four
# refusals above would prove only that the command is broken.
EVC_DIR=$(harden_dir hs_checked_stopped '.tasks.c.title = "Hardening fixture"')
jq -e '[.tasks.c.history[] | select(.to == "checking")] | length == 1' "$EVC_DIR/$STATE_FILE" >/dev/null
check "CONTROL: the fixture genuinely holds one 'checking' transition" $?
EVC_OUT=$(cd "$EVC_DIR" && bash "$SCRIPT" reassess c --specialist sp --finding "the finding" --resume-state checking 2>&1); RC=$?
check "CONTROL: --resume-state checking still succeeds on an intact history (exit $RC)" $RC
echo "$EVC_OUT" | grep -q "REASSESSED c .*state=checking"
check "CONTROL: its output reports the restored state (got: $EVC_OUT)" $?
jq -e '.tasks.c.state == "checking"' "$EVC_DIR/$STATE_FILE" >/dev/null
check "CONTROL: and the task really is back in 'checking'" $?
rm -rf "$EVC_DIR"

echo "-- PASSING CONTROLS: every command above SUCCEEDS on an intact record, so none of the refusals is vacuous --"
CTRL_DIR=$(mktemp -d)
(
  cd "$CTRL_DIR" || exit 1
  bash "$SCRIPT" create d1 "Dependency"
  bash "$SCRIPT" start d1; bash "$SCRIPT" check d1; bash "$SCRIPT" complete d1
  bash "$SCRIPT" create c "Control task" --depends d1 --budget 9
) >/dev/null 2>&1
( cd "$CTRL_DIR" && bash "$SCRIPT" start c ) >/dev/null 2>&1
check "CONTROL: start succeeds with a well-formed depends_on whose dependency is done" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" record-assignment c --role builder --agent-type team-builder ) >/dev/null 2>&1
check "CONTROL: record-assignment succeeds" $?
( cd "$CTRL_DIR" && echo "real output" > out.txt && bash "$SCRIPT" record-evidence c --command "true" --exit-code 0 --tests-total 1 --tests-skipped 0 --output-file out.txt ) >/dev/null 2>&1
check "CONTROL: record-evidence succeeds" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" record-external-action c --key K1 --description "opened PR #7" ) >/dev/null 2>&1
check "CONTROL: record-external-action succeeds" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" check-external-action c --key K1 ) >/dev/null 2>&1
check "CONTROL: check-external-action reports ALREADY-RECORDED (exit 0) for a key that is recorded" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" check-external-action c --key K2 ) >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1
check "CONTROL: check-external-action still answers PROCEED (exit 1) for an unrecorded key on an intact record" $RC_CHK
( cd "$CTRL_DIR" && bash "$SCRIPT" pause c --next-action "rerun the migration by hand" ) >/dev/null 2>&1
check "CONTROL: pause succeeds" $?
CTRL_RESUME=$(cd "$CTRL_DIR" && bash "$SCRIPT" resume c 2>&1); RC=$?
[ "$RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "CONTROL: resume succeeds" $RC_CHK
echo "$CTRL_RESUME" | grep -qF "NEXT ACTION: rerun the migration by hand"
check "CONTROL: resume still restores the EXACT next action text" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" block c "waiting on review" ) >/dev/null 2>&1
check "CONTROL: block succeeds" $?
CTRL_UNBLOCK=$(cd "$CTRL_DIR" && bash "$SCRIPT" unblock c 2>&1); RC=$?
[ "$RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "CONTROL: unblock succeeds" $RC_CHK
echo "$CTRL_UNBLOCK" | grep -qF "state=building"; check "CONTROL: unblock restores the exact pre-block state" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" fail c --reason "r1" --hypothesis "theory one" ) >/dev/null 2>&1
check "CONTROL: fail succeeds" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" fail c --reason "r2" --hypothesis "theory two" ) >/dev/null 2>&1
check "CONTROL: a second fail with a CHANGED hypothesis succeeds" $?
( cd "$CTRL_DIR" && bash "$SCRIPT" check c ) >/dev/null 2>&1
check "CONTROL: check succeeds" $?
rm -rf "$CTRL_DIR"

echo "-- LEGACY RECORDS STILL WORK: an ABSENT key keeps its safe default; only PRESENT-but-wrong refuses --"
# This is the half of the absent-vs-invalid distinction that makes the
# hardening safe to apply everywhere. A record written before a field existed
# has no such key at all, and every one of these fields has a genuine
# absent-case: no dependencies, no checkpoints, nothing recorded yet.
HLEG_DIR=$(mktemp -d)
( cd "$HLEG_DIR" && bash "$SCRIPT" create d1 "Dependency" && bash "$SCRIPT" start d1 \
  && bash "$SCRIPT" check d1 && bash "$SCRIPT" complete d1 \
  && bash "$SCRIPT" create c "Legacy-shaped task" --depends d1 ) >/dev/null 2>&1
jq 'del(.tasks.c.checkpoints, .tasks.c.external_actions, .tasks.c.assignments,
        .tasks.c.evidence, .tasks.c.attempts, .tasks.c.reassessments)' \
  "$HLEG_DIR/$STATE_FILE" > "$HLEG_DIR/l.tmp" && mv "$HLEG_DIR/l.tmp" "$HLEG_DIR/$STATE_FILE"
jq -e '(.tasks.c | has("checkpoints") | not) and (.tasks.c | has("external_actions") | not)' \
  "$HLEG_DIR/$STATE_FILE" >/dev/null
check "precondition: the legacy-shaped record genuinely has none of those keys" $?
( cd "$HLEG_DIR" && bash "$SCRIPT" start c ) >/dev/null 2>&1
check "LEGACY: start still succeeds (absent-but-satisfied depends_on is untouched)" $?
( cd "$HLEG_DIR" && bash "$SCRIPT" check-external-action c --key K1 ) >/dev/null 2>&1; RC=$?
[ "$RC" = "1" ] && RC_CHK=0 || RC_CHK=1
check "LEGACY: an absent external_actions array still answers PROCEED (exit 1), not a refusal" $RC_CHK
( cd "$HLEG_DIR" && bash "$SCRIPT" record-external-action c --key K1 --description "opened PR" ) >/dev/null 2>&1
check "LEGACY: record-external-action still creates the array from nothing" $?
( cd "$HLEG_DIR" && bash "$SCRIPT" record-assignment c --role builder --agent-type team-builder ) >/dev/null 2>&1
check "LEGACY: record-assignment still creates the assignments array from nothing" $?
( cd "$HLEG_DIR" && bash "$SCRIPT" fail c --reason "r1" --hypothesis "theory one" ) >/dev/null 2>&1
check "LEGACY: fail still succeeds with no attempts array at all" $?
jq -e '.tasks.c.attempts_used == 1 and (.tasks.c.attempts | length) == 1' "$HLEG_DIR/$STATE_FILE" >/dev/null
check "LEGACY: the absent attempts array defaulted to empty, so this is attempt 1" $?
( cd "$HLEG_DIR" && bash "$SCRIPT" pause c --next-action "pick this back up" ) >/dev/null 2>&1
check "LEGACY: pause still creates the checkpoints array from nothing" $?
HLEG_RESUME=$(cd "$HLEG_DIR" && bash "$SCRIPT" resume c 2>&1); RC=$?
[ "$RC" = "0" ] && RC_CHK=0 || RC_CHK=1; check "LEGACY: resume still succeeds" $RC_CHK
echo "$HLEG_RESUME" | grep -qF "NEXT ACTION: pick this back up"
check "LEGACY: and still restores the exact next action" $?
rm -rf "$HLEG_DIR"

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
