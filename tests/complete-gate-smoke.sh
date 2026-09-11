#!/bin/bash
# Completion-gate smoke tests — real invocations of scripts/team/complete-gate.sh
# (and the task-state.sh record-evidence subcommand it depends on), asserted
# with a check() helper, run from an isolated mktemp -d git repository and
# cleaned up on exit. Mirrors tests/task-state-smoke.sh and
# tests/assign-smoke.sh's pattern.
#
# These exist to prove BUILD_PLAN.md Part 1.4's acceptance line:
#   "actual output retained; false reports, no required tests, skipped
#    required checks, and changed code reject completion; acceptance
#    requirements map to evidence."
# and, above all, the "Definition of implementation completion" hard rule:
# the gate's first evidence-content check must independently open and read
# every claimed artifact path rather than trust the claim. The regression
# test named after that incident is the single most important test in this
# file -- see "THE CORE REGRESSION TEST" below.

set -u
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_STATE="$REPO_ROOT/scripts/team/task-state.sh"
GATE="$REPO_ROOT/scripts/team/complete-gate.sh"
PASS=0; FAIL=0

check() { # check <name> <exit-code-as-string>
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  ok: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH — complete-gate.sh is jq-dependent by design, cannot run these tests"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not on PATH — complete-gate.sh's staleness check needs it, cannot run these tests"
  exit 0
fi

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR" 2>/dev/null; }
trap cleanup EXIT
cd "$WORKDIR" || exit 1

git init -q >/dev/null 2>&1
git config user.email t@t.test
git config user.name t
echo ".claude/state/" > .gitignore
echo "base content" > tracked.txt
git add tracked.txt .gitignore
git commit -qm init >/dev/null 2>&1
BASE_SHA=$(git rev-parse --short HEAD)

# task_state <id> — current state string, via task-state.sh status (not by
# re-reading team-tasks.json's raw JSON ourselves -- exercise the real CLI
# the same way a caller would).
task_state() {
  bash "$TASK_STATE" status "$1" 2>/dev/null | jq -r '.state'
}

# new_task <id> [state] — creates a task and drives it to the given state
# (default: checking, since that's the only state the gate accepts).
new_task() {
  local id="$1" target="${2:-checking}"
  bash "$TASK_STATE" create "$id" "Task $id" >/dev/null 2>&1
  [ "$target" = "planned" ] && return
  bash "$TASK_STATE" start "$id" >/dev/null 2>&1
  [ "$target" = "building" ] && return
  bash "$TASK_STATE" check "$id" >/dev/null 2>&1
}

echo "== happy path: create -> start -> check -> record-evidence (real existing artifact) -> gate -> done =="
new_task happy checking
echo "findings, really written" > happy-artifact.txt
echo "raw test output" > happy-output.txt
bash "$TASK_STATE" record-evidence happy --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 5 --tests-skipped 0 --output-file happy-output.txt --artifact happy-artifact.txt >/dev/null 2>&1
check "record-evidence for happy path exits 0" $?
OUT=$(bash "$GATE" happy 2>&1); RC=$?
check "complete-gate.sh exits 0 on the happy path" $RC
echo "$OUT" | grep -q "GATE PASS"; check "happy path output shows GATE PASS" $?
echo "$OUT" | grep -q "COMPLETED happy state=done"; check "happy path output shows task-state.sh's own COMPLETED line (gate really called complete)" $?
[ "$(task_state happy)" = "done" ] && RC_CHK=0 || RC_CHK=1
check "independently re-checking task-state.sh status afterward shows state=done (not just trusting the gate's own message)" $RC_CHK

echo ""
echo "== THE CORE REGRESSION TEST: claimed artifact that does not exist on disk =="
echo "   (this is the Part 1.1 incident: a subagent claimed a findings file"
echo "   existed; it did not; only caught because the claim was checked)"
new_task ghost-artifact checking
bash "$TASK_STATE" record-evidence ghost-artifact --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 5 --tests-skipped 0 --output-file ghost-output.txt --artifact docs/rebuild/DOES_NOT_EXIST.md >/dev/null 2>&1
check "record-evidence accepts a claimed artifact path without checking it exists (recording is not judging)" $?
OUT=$(bash "$GATE" ghost-artifact 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS a claimed artifact that does not exist (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "docs/rebuild/DOES_NOT_EXIST.md"; check "rejection names the exact missing path" $?
echo "$OUT" | grep -qi "missing"; check "rejection message says the artifact is missing" $?
[ "$(task_state ghost-artifact)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "task does NOT transition to done — independently re-checked via task-state.sh status (still checking)" $RC_CHK

echo ""
echo "== zero-byte claimed artifact is also rejected (as suspicious as missing) =="
new_task empty-artifact checking
touch empty-artifact.txt
[ -f empty-artifact.txt ] && [ ! -s empty-artifact.txt ] && RC_CHK=0 || RC_CHK=1
check "test setup: empty-artifact.txt exists on disk and is genuinely zero bytes" $RC_CHK
bash "$TASK_STATE" record-evidence empty-artifact --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 5 --tests-skipped 0 --output-file empty-output.txt --artifact empty-artifact.txt >/dev/null 2>&1
OUT=$(bash "$GATE" empty-artifact 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS a zero-byte claimed artifact (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "empty-artifact.txt"; check "rejection names the exact empty path" $?
echo "$OUT" | grep -qi "empty"; check "rejection message says the artifact is empty" $?
[ "$(task_state empty-artifact)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "zero-byte-artifact task does NOT transition to done" $RC_CHK

echo ""
echo "== no evidence recorded at all =="
new_task no-evidence checking
OUT=$(bash "$GATE" no-evidence 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS a task with no evidence recorded (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "no evidence"; check "rejection message mentions no evidence" $?
[ "$(task_state no-evidence)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "no-evidence task does NOT transition to done" $RC_CHK

echo ""
echo "== nonzero exit code in latest evidence =="
new_task bad-exit checking
echo "real artifact" > bad-exit-artifact.txt
echo "raw output" > bad-exit-output.txt
bash "$TASK_STATE" record-evidence bad-exit --command "bash tests/some-suite.sh" --exit-code 1 \
  --tests-total 5 --tests-skipped 0 --output-file bad-exit-output.txt --artifact bad-exit-artifact.txt >/dev/null 2>&1
OUT=$(bash "$GATE" bad-exit 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS evidence with a nonzero exit code (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "exit code 1"; check "rejection names the actual nonzero exit code" $?
[ "$(task_state bad-exit)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "bad-exit task does NOT transition to done" $RC_CHK

echo ""
echo "== tests_total=0 rejected by default (--require-tests); passes under --allow-no-tests =="
new_task no-tests checking
echo "real artifact" > no-tests-artifact.txt
echo "raw output" > no-tests-output.txt
bash "$TASK_STATE" record-evidence no-tests --command "echo nothing to test" --exit-code 0 \
  --tests-total 0 --tests-skipped 0 --output-file no-tests-output.txt --artifact no-tests-artifact.txt >/dev/null 2>&1
OUT=$(bash "$GATE" no-tests 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS tests_total=0 under default --require-tests (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "tests_total is 0"; check "rejection message says tests_total is 0" $?
[ "$(task_state no-tests)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "no-tests task does NOT transition to done under default mode" $RC_CHK

OUT=$(bash "$GATE" no-tests --allow-no-tests 2>&1); RC=$?
check "complete-gate.sh PASSES the same evidence under --allow-no-tests" $RC
[ "$(task_state no-tests)" = "done" ] && RC_CHK=0 || RC_CHK=1
check "--allow-no-tests task transitions to done" $RC_CHK

echo ""
echo "== tests_skipped>0 rejected under default --require-tests =="
new_task skipped-tests checking
echo "real artifact" > skipped-artifact.txt
echo "raw output" > skipped-output.txt
bash "$TASK_STATE" record-evidence skipped-tests --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 8 --tests-skipped 2 --output-file skipped-output.txt --artifact skipped-artifact.txt >/dev/null 2>&1
OUT=$(bash "$GATE" skipped-tests 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS tests_skipped>0 under default --require-tests (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "2 required tests were skipped"; check "rejection names the actual skipped count" $?
[ "$(task_state skipped-tests)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "skipped-tests task does NOT transition to done" $RC_CHK

echo ""
echo "== stale evidence (dirty-content variant): tree stays dirty the whole time, but the"
echo "   tracked content actually changes again after evidence was recorded, without any"
echo "   commit in between -- this is the reviewer's exact CRITICAL-finding repro: a bare"
echo "   clean/dirty flag plus the base SHA cannot tell two different dirty trees off the"
echo "   same base commit apart, so evidence recorded against one would be wrongly accepted"
echo "   as still-fresh after the tracked file changed again without a commit. =="
new_task dirty-stale checking
echo "real artifact" > dirty-stale-artifact.txt
echo "raw output" > dirty-stale-output.txt
echo "v1 - the version that was tested" > tracked.txt
bash "$TASK_STATE" record-evidence dirty-stale --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 4 --tests-skipped 0 --output-file dirty-stale-output.txt --artifact dirty-stale-artifact.txt >/dev/null 2>&1
RECORDED_DIRTY_SNAPSHOT=$(bash "$TASK_STATE" status dirty-stale | jq -r '.evidence[-1].code_snapshot')
echo "  (evidence recorded against: $RECORDED_DIRTY_SNAPSHOT)"
echo "v2 - DIFFERENT, UNTESTED logic, changed after evidence was recorded" > tracked.txt
[ -n "$(git status --porcelain 2>/dev/null)" ] && RC_CHK=0 || RC_CHK=1
check "test setup: tree is still dirty (no commit happened) after the second tracked.txt change" $RC_CHK
OUT=$(bash "$GATE" dirty-stale 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS stale evidence when the tree stays dirty but tracked content changed again without a commit (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "stale"; check "dirty-content-stale rejection message says evidence is stale" $?
[ "$(task_state dirty-stale)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "dirty-content-stale task does NOT transition to done" $RC_CHK

echo ""
echo "== stale evidence (commit-based variant): recorded snapshot no longer matches current code =="
new_task stale checking
echo "real artifact" > stale-artifact.txt
echo "raw output" > stale-output.txt
bash "$TASK_STATE" record-evidence stale --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 4 --tests-skipped 0 --output-file stale-output.txt --artifact stale-artifact.txt >/dev/null 2>&1
RECORDED_SNAPSHOT=$(bash "$TASK_STATE" status stale | jq -r '.evidence[-1].code_snapshot')
echo "  (evidence recorded against: $RECORDED_SNAPSHOT)"
# A genuinely different, valid staleness scenario alongside the dirty-content
# one above: here the base SHA itself moves via a real new commit, rather
# than the dirty-content diff hash changing while the base SHA stays put.
# Both are real staleness cases complete-gate.sh must reject, so both are
# kept as separate tests.
git add -A >/dev/null 2>&1
git commit -qm "advance the snapshot for the staleness test" >/dev/null 2>&1
NEW_SHA=$(git rev-parse --short HEAD)
[ "$NEW_SHA" != "$BASE_SHA" ] && RC_CHK=0 || RC_CHK=1
check "test setup: a real new commit was made, advancing the base SHA ($BASE_SHA -> $NEW_SHA)" $RC_CHK
OUT=$(bash "$GATE" stale 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS stale evidence after a real new commit (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "stale"; check "rejection message says evidence is stale" $?
echo "$OUT" | grep -q "$NEW_SHA"; check "rejection message names the current snapshot ($NEW_SHA)" $?
[ "$(task_state stale)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "stale task does NOT transition to done" $RC_CHK

echo ""
echo "== task not in 'checking' state is rejected =="
new_task still-building building
echo "artifact" > still-building-artifact.txt
bash "$TASK_STATE" record-evidence still-building --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 3 --tests-skipped 0 --output-file sb-output.txt --artifact still-building-artifact.txt >/dev/null 2>&1
OUT=$(bash "$GATE" still-building 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS a task still in 'building' state (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "building"; check "rejection names the actual current state (building)" $?

new_task already-done checking
echo "artifact" > already-done-artifact.txt
echo "raw output" > ad-output.txt
bash "$TASK_STATE" record-evidence already-done --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 3 --tests-skipped 0 --output-file ad-output.txt --artifact already-done-artifact.txt >/dev/null 2>&1
bash "$GATE" already-done >/dev/null 2>&1
[ "$(task_state already-done)" = "done" ] && RC_CHK=0 || RC_CHK=1
check "setup: already-done task really reached done via the gate once" $RC_CHK
OUT=$(bash "$GATE" already-done 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS re-gating an already-done task (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "done"; check "rejection names the actual current state (done)" $?

echo ""
echo "== path resolution (CRITICAL Bug 2 regression): evidence recorded with an explicit"
echo "   --cwd pointing at a subdirectory and relative artifact/output_file paths -- the OLD"
echo "   bug resolved those relative to wherever complete-gate.sh itself was invoked from"
echo "   (this test's \$WORKDIR, since that's where .claude/state/ lives and task-state.sh"
echo "   resolves state relative to its own invocation dir -- see task-state.sh's own header),"
echo "   which would falsely report a real, existing file as missing. The FIX stores every"
echo "   artifact/output_file path pre-resolved to absolute (joined onto --cwd) at record time,"
echo "   so the gate needs no cwd guessing of its own at all. =="
mkdir -p subdir
echo "artifact actually living in subdir" > subdir/cwd-artifact.txt
echo "output actually living in subdir" > subdir/cwd-output.txt
new_task cwd-resolve checking
bash "$TASK_STATE" record-evidence cwd-resolve --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 2 --tests-skipped 0 --output-file cwd-output.txt --artifact cwd-artifact.txt --cwd subdir >/dev/null 2>&1
check "record-evidence with --cwd subdir and relative artifact/output_file exits 0" $?

RECORDED_ARTIFACT=$(bash "$TASK_STATE" status cwd-resolve | jq -r '.evidence[-1].artifacts[0]')
RECORDED_OUTPUT=$(bash "$TASK_STATE" status cwd-resolve | jq -r '.evidence[-1].output_file')
RECORDED_CWD=$(bash "$TASK_STATE" status cwd-resolve | jq -r '.evidence[-1].cwd')
case "$RECORDED_ARTIFACT" in
  /*|[A-Za-z]:[/\\]*) ARTIFACT_ABS_OK=0 ;;
  *) ARTIFACT_ABS_OK=1 ;;
esac
check "recorded artifact path was resolved to absolute (joined onto --cwd) at record time (got: $RECORDED_ARTIFACT)" $ARTIFACT_ABS_OK
case "$RECORDED_OUTPUT" in
  /*|[A-Za-z]:[/\\]*) OUTPUT_ABS_OK=0 ;;
  *) OUTPUT_ABS_OK=1 ;;
esac
check "recorded output_file path was resolved to absolute (joined onto --cwd) at record time (got: $RECORDED_OUTPUT)" $OUTPUT_ABS_OK
case "$RECORDED_CWD" in
  /*|[A-Za-z]:[/\\]*) CWD_ABS_OK=0 ;;
  *) CWD_ABS_OK=1 ;;
esac
check "recorded cwd field itself was resolved to absolute (got: $RECORDED_CWD)" $CWD_ABS_OK

# The old bug: complete-gate.sh resolved each raw stored artifact path
# relative to ITS OWN invocation directory ($WORKDIR here), so a bare
# "cwd-artifact.txt" would have been checked at $WORKDIR/cwd-artifact.txt --
# which does NOT exist (the real file is $WORKDIR/subdir/cwd-artifact.txt)
# -- falsely rejecting a real, existing file. The gate is invoked from
# $WORKDIR below, same as every other test in this file (task-state.sh
# resolves .claude/state/ relative to its own invocation dir, so $WORKDIR is
# the only directory any command in this suite can be run from) -- proving
# the fix does not depend on the gate's own invocation directory matching
# the evidence's recorded --cwd at all.
[ ! -f "$WORKDIR/cwd-artifact.txt" ] && RC_CHK=0 || RC_CHK=1
check "test sanity: no file exists at the OLD buggy resolution location ($WORKDIR/cwd-artifact.txt)" $RC_CHK
OUT=$(bash "$GATE" cwd-resolve 2>&1); RC=$?
check "complete-gate.sh finds the real artifact/output_file via their resolved absolute paths, not the gate's own invocation dir (exit $RC)" $RC
[ "$(task_state cwd-resolve)" = "done" ] && RC_CHK=0 || RC_CHK=1
check "cwd-resolve task reaches done" $RC_CHK

echo ""
echo "== path resolution (CRITICAL Bug 2 regression), negative case: a genuinely missing"
echo "   artifact (relative to its recorded --cwd) is still correctly rejected by its real"
echo "   resolved path =="
mkdir -p subdir2
new_task cwd-resolve-missing checking
echo "output actually living in subdir2" > subdir2/cwd2-output.txt
bash "$TASK_STATE" record-evidence cwd-resolve-missing --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 2 --tests-skipped 0 --output-file cwd2-output.txt --artifact does-not-exist-in-subdir2.txt --cwd subdir2 >/dev/null 2>&1
OUT=$(bash "$GATE" cwd-resolve-missing 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS a missing artifact resolved against its recorded --cwd (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "does-not-exist-in-subdir2.txt"; check "rejection names the missing artifact (resolved path correctly points into subdir2)" $?
[ "$(task_state cwd-resolve-missing)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "cwd-resolve-missing task does NOT transition to done" $RC_CHK

echo ""
echo "== output_file existence check (HIGH Bug 3 regression): recorded output_file that was"
echo "   never actually created on disk =="
new_task ghost-output checking
echo "real artifact" > ghost-output-artifact.txt
bash "$TASK_STATE" record-evidence ghost-output --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 3 --tests-skipped 0 --output-file DOES_NOT_EXIST_OUTPUT.txt --artifact ghost-output-artifact.txt >/dev/null 2>&1
check "record-evidence accepts a claimed output_file path without checking it exists (recording is not judging)" $?
OUT=$(bash "$GATE" ghost-output 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS a claimed output_file that does not exist (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "DOES_NOT_EXIST_OUTPUT.txt"; check "rejection names the exact missing output_file path" $?
echo "$OUT" | grep -qi "output_file"; check "rejection message specifically calls out output_file (distinct from a declared artifact)" $?
[ "$(task_state ghost-output)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "ghost-output task does NOT transition to done" $RC_CHK

echo ""
echo "== output_file existence check (Bug 3), zero-byte variant =="
new_task empty-output checking
touch empty-output-file.txt
echo "real artifact" > empty-output-artifact.txt
bash "$TASK_STATE" record-evidence empty-output --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 3 --tests-skipped 0 --output-file empty-output-file.txt --artifact empty-output-artifact.txt >/dev/null 2>&1
OUT=$(bash "$GATE" empty-output 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh REJECTS a zero-byte output_file (exit $RC)" $RC_CHK
echo "$OUT" | grep -q "empty-output-file.txt"; check "zero-byte rejection names the exact output_file path" $?
echo "$OUT" | grep -qi "output_file"; check "zero-byte rejection message specifically calls out output_file" $?
[ "$(task_state empty-output)" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "empty-output task does NOT transition to done" $RC_CHK

echo ""
echo "== output_file present and non-empty: gate proceeds (positive control alongside the"
echo "   Bug 3 negative cases above) =="
new_task good-output checking
echo "real artifact" > good-output-artifact.txt
echo "real output content" > good-output-file.txt
bash "$TASK_STATE" record-evidence good-output --command "bash tests/some-suite.sh" --exit-code 0 \
  --tests-total 3 --tests-skipped 0 --output-file good-output-file.txt --artifact good-output-artifact.txt >/dev/null 2>&1
OUT=$(bash "$GATE" good-output 2>&1); RC=$?
check "complete-gate.sh PASSES when output_file exists and is non-empty (exit $RC)" $RC
[ "$(task_state good-output)" = "done" ] && RC_CHK=0 || RC_CHK=1
check "good-output task transitions to done when output_file is present and non-empty" $RC_CHK

echo ""
echo "== nonexistent task ID fails cleanly =="
OUT=$(bash "$GATE" no-such-task 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1; check "complete-gate.sh on a nonexistent task fails (exit $RC)" $RC_CHK
echo "$OUT" | grep -qi "not found"; check "error surfaces task-state.sh's own not-found message" $?

echo ""
echo "== bad usage =="
OUT=$(bash "$GATE" 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "missing task ID exits 2 (got $RC)" $RC_CHK
OUT=$(bash "$GATE" happy --bogus-flag 2>&1); RC=$?
[ "$RC" = "2" ] && RC_CHK=0 || RC_CHK=1; check "unknown flag exits 2 (got $RC)" $RC_CHK

echo ""
echo "== Part 1.6: .claude/state/ gitignore warning on complete-gate.sh =="

# gated_task_in <dir> <id> -- creates a task in <dir> and drives it through
# create -> start -> check -> record-evidence (real artifact/output) so the
# gate can run against it. Independent of the main WORKDIR/task-state()
# helpers above since these run in their own isolated directories.
gated_task_in() {
  local dir="$1" id="$2"
  ( cd "$dir" && bash "$TASK_STATE" create "$id" "Task $id" ) >/dev/null 2>&1
  ( cd "$dir" && bash "$TASK_STATE" start "$id" ) >/dev/null 2>&1
  ( cd "$dir" && bash "$TASK_STATE" check "$id" ) >/dev/null 2>&1
  echo "real artifact" > "$dir/$id-artifact.txt"
  echo "real output" > "$dir/$id-output.txt"
  ( cd "$dir" && bash "$TASK_STATE" record-evidence "$id" --command "echo hi" --exit-code 0 \
      --tests-total 1 --tests-skipped 0 --output-file "$id-output.txt" --artifact "$id-artifact.txt" ) >/dev/null 2>&1
}

echo "-- happy path above already ran with .claude/state/ gitignored (this repo's own .gitignore, WORKDIR) --"
HAPPY_ERR=$(bash "$GATE" already-done 2>&1 1>/dev/null)
echo "$HAPPY_ERR" | grep -qi "not excluded from 'git status'"
[ "$?" != "0" ] && RC_CHK=0 || RC_CHK=1; check "no gitignore warning in an already-gitignored repo (re-checked against an already-done task, no false positive)" $RC_CHK

echo "-- .claude/state/ NOT gitignored: warning printed, gate still completes the task normally --"
WARN_DIR=$(mktemp -d)
( cd "$WARN_DIR" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
gated_task_in "$WARN_DIR" warn-gate
ERR_OUT=$(cd "$WARN_DIR" && bash "$GATE" warn-gate 2>&1 1>/dev/null)
RC_OUT=$(cd "$WARN_DIR" && bash "$TASK_STATE" status warn-gate | jq -r '.state')
echo "$ERR_OUT" | grep -qi "not excluded from 'git status'"; check "complete-gate.sh warns on stderr when .claude/state/ is not gitignored" $?
echo "$ERR_OUT" | grep -qi "stale"; check "warning names the spurious-staleness risk" $?
[ "$RC_OUT" = "done" ] && RC_CHK=0 || RC_CHK=1; check "task still reaches done despite the warning (advisory only, not a hard failure)" $RC_CHK
rm -rf "$WARN_DIR"

echo "-- .claude/state/ IS gitignored: no warning, no regression --"
OK_DIR=$(mktemp -d)
( cd "$OK_DIR" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
echo ".claude/state/" > "$OK_DIR/.gitignore"
( cd "$OK_DIR" && git add .gitignore && git commit -qm init ) >/dev/null 2>&1
gated_task_in "$OK_DIR" ok-gate
ERR_OUT=$(cd "$OK_DIR" && bash "$GATE" ok-gate 2>&1 1>/dev/null)
RC_OUT=$(cd "$OK_DIR" && bash "$TASK_STATE" status ok-gate | jq -r '.state')
[ -z "$ERR_OUT" ] && RC_CHK=0 || RC_CHK=1; check "no warning printed when .claude/state/ is already gitignored (got: $ERR_OUT)" $RC_CHK
[ "$RC_OUT" = "done" ] && RC_CHK=0 || RC_CHK=1; check "task reaches done normally when .claude/state/ is gitignored" $RC_CHK
rm -rf "$OK_DIR"

echo "-- not inside a git repository at all: no gitignore warning on stderr, no crash --"
NOGIT_DIR=$(mktemp -d)
gated_task_in "$NOGIT_DIR" nogit-gate
ERR_OUT=$(cd "$NOGIT_DIR" && bash "$GATE" nogit-gate 2>&1 1>/dev/null)
RC_OUT=$(cd "$NOGIT_DIR" && bash "$TASK_STATE" status nogit-gate | jq -r '.state')
[ -z "$ERR_OUT" ] && RC_CHK=0 || RC_CHK=1; check "no gitignore warning printed to stderr outside a git repository (got: $ERR_OUT)" $RC_CHK
# NOTE: this used to read "...so staleness check trivially matches", which was
# the defect stated as if it were a feature. It does not trivially match; it
# cannot run at all. What is asserted here is only that completion still
# HAPPENS outside git -- the honesty of what the gate SAYS about check 6 is
# asserted in its own section immediately below.
[ "$RC_OUT" = "done" ] && RC_CHK=0 || RC_CHK=1; check "task still reaches done outside a git repository (a project without version control is legitimate and must still be able to complete work)" $RC_CHK
rm -rf "$NOGIT_DIR"

echo ""
echo "== CHECK 6 OUTSIDE A GIT REPOSITORY: the gate must never claim a staleness"
echo "   check it could not perform =="
# THE DEFECT, reproduced here exactly as it was reported:
#   record-evidence ... --artifact art.txt   -> snapshot="no-git-repository"
#   echo "COMPLETELY DIFFERENT CODE" > art.txt   (rewrite the code afterwards)
#   complete-gate.sh n
#   GATE PASS: task 'n' — evidence recorded at ... accepted (snapshot: no-git-repository)
#   COMPLETED n state=done
# compute_snapshot degrades a missing git into the constant "no-git-repository",
# so check 6 compared that constant against itself, matched every time, and
# reported acceptance. The same sequence inside a git repo correctly fails check
# 6 as stale (asserted in the staleness sections far above, and again as this
# section's own control below). The defect is not that completion happened -- a
# non-git project is legitimate -- it is that the OUTPUT asserted a snapshot
# check had succeeded when none was possible.
NOGIT_STALE=$(mktemp -d)
( cd "$NOGIT_STALE" && bash "$TASK_STATE" create ngs "Non-git staleness task" ) >/dev/null 2>&1
( cd "$NOGIT_STALE" && bash "$TASK_STATE" start ngs ) >/dev/null 2>&1
( cd "$NOGIT_STALE" && bash "$TASK_STATE" check ngs ) >/dev/null 2>&1
echo "ORIGINAL CODE" > "$NOGIT_STALE/art.txt"
echo "raw test output" > "$NOGIT_STALE/out.txt"
( cd "$NOGIT_STALE" && bash "$TASK_STATE" record-evidence ngs --command "bash tests/some-suite.sh" \
    --exit-code 0 --tests-total 3 --tests-skipped 0 --output-file out.txt --artifact art.txt ) >/dev/null 2>&1
NGS_SNAP=$(cd "$NOGIT_STALE" && bash "$TASK_STATE" status ngs | jq -r '.evidence[-1].code_snapshot')
[ "$NGS_SNAP" = "no-git-repository" ] && RC_CHK=0 || RC_CHK=1
check "test setup: evidence really was recorded against the no-git placeholder (got: $NGS_SNAP)" $RC_CHK
# The rewrite that makes this a real staleness scenario: the artifact's content
# is now completely different from what the recorded command ran against.
echo "COMPLETELY DIFFERENT CODE" > "$NOGIT_STALE/art.txt"
NGS_OUT=$(cd "$NOGIT_STALE" && bash "$GATE" ngs 2>&1); RC=$?
check "gate still exits 0 in a non-git project (completion is NOT refused — that is the deliberate semantics)" $RC
echo "$NGS_OUT" | grep -q "COULD NOT VERIFY STALENESS"
check "gate states explicitly that check 6 could NOT verify staleness" $?
echo "$NGS_OUT" | grep -qi "not under version control"
check "gate names the reason in plain words (no version control)" $?
echo "$NGS_OUT" | grep -qi "UNDETECTED"
check "gate says any code drift since the evidence was recorded is UNDETECTED" $?
echo "$NGS_OUT" | grep -q "GATE PASS (WITHOUT STALENESS VERIFICATION)"
check "the final pass line says plainly that it passed WITHOUT staleness verification" $?
# The exact old wording must be GONE: "accepted (snapshot: no-git-repository)"
# is the sentence that asserted a snapshot had matched.
echo "$NGS_OUT" | grep -q "accepted (snapshot: no-git-repository)" && RC_CHK=1 || RC_CHK=0
check "the old false wording 'accepted (snapshot: no-git-repository)' is gone" $RC_CHK
# ...and no bare "GATE PASS:" line either (that spelling is the verified one).
echo "$NGS_OUT" | grep -q "^GATE PASS:" && RC_CHK=1 || RC_CHK=0
check "the unverified run does not print the verified 'GATE PASS:' line" $RC_CHK
NGS_STATE=$(cd "$NOGIT_STALE" && bash "$TASK_STATE" status ngs | jq -r '.state')
[ "$NGS_STATE" = "done" ] && RC_CHK=0 || RC_CHK=1
check "task does reach done (got: $NGS_STATE)" $RC_CHK
# DURABLE, not merely printed: only recorded state is ground truth here, so an
# auditor reading the state file months later must be able to tell this
# completion from a genuinely-verified one.
NGS_HIST=$(cd "$NOGIT_STALE" && bash "$TASK_STATE" status ngs | jq -c '.history[-1]')
echo "$NGS_HIST" | jq -e '.from == "checking" and .to == "done"' >/dev/null
check "the last history entry is the completion transition (got: $NGS_HIST)" $?
echo "$NGS_HIST" | jq -e '.staleness_verified == false' >/dev/null
check "the completion is durably recorded with staleness_verified=false" $?
rm -rf "$NOGIT_STALE"

echo "-- THE CONTROL: the same sequence inside a git repository still REJECTS as stale, and a"
echo "   genuinely-verified completion records staleness_verified=true (or the above proves nothing) --"
GIT_CTRL=$(mktemp -d)
( cd "$GIT_CTRL" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
echo ".claude/state/" > "$GIT_CTRL/.gitignore"
echo "ORIGINAL CODE" > "$GIT_CTRL/art.txt"
echo "raw test output" > "$GIT_CTRL/out.txt"
( cd "$GIT_CTRL" && git add .gitignore art.txt out.txt && git commit -qm init ) >/dev/null 2>&1
( cd "$GIT_CTRL" && bash "$TASK_STATE" create gc "Git control task" ) >/dev/null 2>&1
( cd "$GIT_CTRL" && bash "$TASK_STATE" start gc ) >/dev/null 2>&1
( cd "$GIT_CTRL" && bash "$TASK_STATE" check gc ) >/dev/null 2>&1
( cd "$GIT_CTRL" && bash "$TASK_STATE" record-evidence gc --command "bash tests/some-suite.sh" \
    --exit-code 0 --tests-total 3 --tests-skipped 0 --output-file out.txt --artifact art.txt ) >/dev/null 2>&1
GC_SNAP=$(cd "$GIT_CTRL" && bash "$TASK_STATE" status gc | jq -r '.evidence[-1].code_snapshot')
[ "$GC_SNAP" != "no-git-repository" ] && [ -n "$GC_SNAP" ] && RC_CHK=0 || RC_CHK=1
check "control setup: evidence recorded against a REAL snapshot, not the placeholder (got: $GC_SNAP)" $RC_CHK
echo "COMPLETELY DIFFERENT CODE" > "$GIT_CTRL/art.txt"
GC_OUT=$(cd "$GIT_CTRL" && bash "$GATE" gc 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "control: the IDENTICAL rewrite-after-recording sequence is REJECTED as stale inside a git repo (exit $RC)" $RC_CHK
echo "$GC_OUT" | grep -qi "stale"; check "control: the rejection says the evidence is stale" $?
GC_STATE=$(cd "$GIT_CTRL" && bash "$TASK_STATE" status gc | jq -r '.state')
[ "$GC_STATE" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "control: the rejected task does NOT reach done (got: $GC_STATE)" $RC_CHK
# Now let it pass honestly: restore the recorded content so the snapshot matches
# again, and assert the verified verdict is recorded as such.
echo "ORIGINAL CODE" > "$GIT_CTRL/art.txt"
GC_OUT2=$(cd "$GIT_CTRL" && bash "$GATE" gc 2>&1); RC=$?
check "control: with the code restored, the same task passes the gate (exit $RC)" $RC
echo "$GC_OUT2" | grep -q "^GATE PASS:"; check "control: a genuinely-verified pass prints the plain 'GATE PASS:' line" $?
echo "$GC_OUT2" | grep -q "WITHOUT STALENESS VERIFICATION" && RC_CHK=1 || RC_CHK=0
check "control: a verified pass does NOT claim to be unverified" $RC_CHK
echo "$GC_OUT2" | grep -q "COULD NOT VERIFY STALENESS" && RC_CHK=1 || RC_CHK=0
check "control: no could-not-verify warning is printed when the check really ran" $RC_CHK
GC_HIST=$(cd "$GIT_CTRL" && bash "$TASK_STATE" status gc | jq -c '.history[-1]')
echo "$GC_HIST" | jq -e '.staleness_verified == true' >/dev/null
check "control: the verified completion records staleness_verified=true (got: $GC_HIST)" $?
rm -rf "$GIT_CTRL"

echo ""
echo "== relocated install: the four team files run from ~/.claude/scripts/team/ against a foreign project =="
# This is the packaging contract, tested end to end rather than assumed.
# install.bat copies scripts/team/*.sh to %USERPROFILE%\.claude\scripts\team\,
# and skills/team-start + skills/team-status invoke them from there by
# absolute path. So the full lifecycle must work when (a) the scripts live in
# a directory that is not this repo, and (b) the cwd is a project that is not
# this repo either -- with state landing in THAT project, never near the repo
# or the install directory. Two independent temp trees, so a path bug in
# either direction shows up as a failure instead of accidentally working.
#
# There are FOUR files, not three: task-state.sh is an entry point that
# sources its guard/helper library, task-state-lib.sh, from its own directory.
# That makes this section the direct test of that resolution too -- the
# foreign project below has no scripts/team/ directory of its own, so a
# task-state.sh that looked for its library relative to the CWD instead of
# relative to itself would fail on the very first invocation here rather
# than anywhere subtle.
INSTALL_ROOT=$(mktemp -d)
FOREIGN_PROJ=$(mktemp -d)
mkdir -p "$INSTALL_ROOT/scripts/team"
cp "$REPO_ROOT"/scripts/team/*.sh "$INSTALL_ROOT/scripts/team/"
chmod +x "$INSTALL_ROOT"/scripts/team/*.sh 2>/dev/null
R_TASK_STATE="$INSTALL_ROOT/scripts/team/task-state.sh"
R_TASK_STATE_LIB="$INSTALL_ROOT/scripts/team/task-state-lib.sh"
R_ASSIGN="$INSTALL_ROOT/scripts/team/assign.sh"
R_GATE="$INSTALL_ROOT/scripts/team/complete-gate.sh"

[ -f "$R_TASK_STATE" ] && [ -f "$R_TASK_STATE_LIB" ] && [ -f "$R_ASSIGN" ] && [ -f "$R_GATE" ] && RC_CHK=0 || RC_CHK=1
check "test setup: all 4 team files (3 entry-point scripts + task-state-lib.sh) copied to a non-repo install directory" $RC_CHK
case "$INSTALL_ROOT/" in "$REPO_ROOT"/*) RC_CHK=1 ;; *) RC_CHK=0 ;; esac
check "test setup: install directory is genuinely outside the repo" $RC_CHK
case "$FOREIGN_PROJ/" in "$REPO_ROOT"/*) RC_CHK=1 ;; *) RC_CHK=0 ;; esac
check "test setup: foreign project directory is genuinely outside the repo" $RC_CHK

( cd "$FOREIGN_PROJ" && git init -q && git config user.email t@t.test && git config user.name t ) >/dev/null 2>&1
echo ".claude/state/" > "$FOREIGN_PROJ/.gitignore"
echo "some app code" > "$FOREIGN_PROJ/app.txt"
( cd "$FOREIGN_PROJ" && git add .gitignore app.txt && git commit -qm init ) >/dev/null 2>&1

# The gap this test exists to close: from a foreign cwd, the OLD cwd-relative
# invocation the skills used to document cannot work at all.
( cd "$FOREIGN_PROJ" && bash scripts/team/task-state.sh list ) >/dev/null 2>&1
[ "$?" != "0" ] && RC_CHK=0 || RC_CHK=1
check "the old cwd-relative 'bash scripts/team/task-state.sh' form genuinely fails outside the repo (this is the bug being fixed)" $RC_CHK

echo "-- full lifecycle by absolute path: create -> start -> check -> record-evidence -> complete-gate -> done --"
( cd "$FOREIGN_PROJ" && bash "$R_TASK_STATE" create relocated-1 "Relocated lifecycle task" ) >/dev/null 2>&1
check "create works from a foreign cwd with an absolute script path (so task-state.sh found task-state-lib.sh by its own location, not by cwd)" $?
( cd "$FOREIGN_PROJ" && bash "$R_TASK_STATE" start relocated-1 ) >/dev/null 2>&1
check "start works from a foreign cwd" $?
RELOC_STATE=$(cd "$FOREIGN_PROJ" && bash "$R_TASK_STATE" status relocated-1 2>/dev/null | jq -r '.state')
[ "$RELOC_STATE" = "building" ] && RC_CHK=0 || RC_CHK=1
check "status read back from a foreign cwd shows state=building (got: $RELOC_STATE)" $RC_CHK

# assign.sh is the script that must find its sibling task-state.sh purely from
# its own location -- the whole reason all three can be relocated together.
ASSIGN_OUT=$(cd "$FOREIGN_PROJ" && bash "$R_ASSIGN" relocated-1 --role builder --agent-type team-builder 2>&1); RC=$?
check "assign.sh --role builder works from the relocated install (it resolves its sibling task-state.sh by its own location, not by cwd)" $RC
echo "$ASSIGN_OUT" | grep -q "BRIEFING"; check "relocated assign.sh still prints its BRIEFING block" $?

( cd "$FOREIGN_PROJ" && bash "$R_TASK_STATE" check relocated-1 ) >/dev/null 2>&1
check "check (building -> checking) works from a foreign cwd" $?
( cd "$FOREIGN_PROJ" && bash "$R_ASSIGN" relocated-1 --role verifier --agent-type team-verifier \
    --acceptance-text "Lifecycle completes from a relocated install" ) >/dev/null 2>&1
check "assign.sh --role verifier works from the relocated install" $?

echo "real findings, written into the foreign project" > "$FOREIGN_PROJ/relocated-artifact.txt"
echo "raw test output" > "$FOREIGN_PROJ/relocated-output.txt"
( cd "$FOREIGN_PROJ" && bash "$R_TASK_STATE" record-evidence relocated-1 --command "bash tests/some-suite.sh" \
    --exit-code 0 --tests-total 3 --tests-skipped 0 \
    --output-file relocated-output.txt --artifact relocated-artifact.txt ) >/dev/null 2>&1
check "record-evidence works from a foreign cwd (artifact paths resolve against that project, not the repo)" $?

RELOC_OUT=$(cd "$FOREIGN_PROJ" && bash "$R_GATE" relocated-1 2>&1); RC=$?
check "complete-gate.sh exits 0 from the relocated install against the foreign project" $RC
echo "$RELOC_OUT" | grep -q "GATE PASS"; check "relocated gate output shows GATE PASS" $?
RELOC_STATE=$(cd "$FOREIGN_PROJ" && bash "$R_TASK_STATE" status relocated-1 2>/dev/null | jq -r '.state')
[ "$RELOC_STATE" = "done" ] && RC_CHK=0 || RC_CHK=1
check "independently re-read status shows state=done — full lifecycle works from a relocated install (got: $RELOC_STATE)" $RC_CHK

echo "-- state landed in the foreign project only, not in the repo or the install directory --"
[ -f "$FOREIGN_PROJ/.claude/state/team-tasks.json" ] && RC_CHK=0 || RC_CHK=1
check "state file exists at the FOREIGN PROJECT's own .claude/state/team-tasks.json" $RC_CHK
grep -q "relocated-1" "$FOREIGN_PROJ/.claude/state/team-tasks.json" 2>/dev/null
check "that file is the one holding the task record" $?
[ ! -e "$INSTALL_ROOT/.claude" ] && [ ! -e "$INSTALL_ROOT/scripts/team/.claude" ] && RC_CHK=0 || RC_CHK=1
check "no .claude/state was created anywhere under the install directory (scripts are global tooling, state is not)" $RC_CHK
if [ -f "$REPO_ROOT/.claude/state/team-tasks.json" ]; then
  grep -q "relocated-1" "$REPO_ROOT/.claude/state/team-tasks.json" 2>/dev/null
  [ "$?" != "0" ] && RC_CHK=0 || RC_CHK=1
else
  RC_CHK=0
fi
check "the repo's own task state was not touched by the foreign-project run" $RC_CHK

rm -rf "$INSTALL_ROOT" "$FOREIGN_PROJ"

echo ""
echo "== FAIL-CLOSED evidence reads: a field the gate compares that is null, non-numeric or"
echo "   the wrong shape must REFUSE completion, not be silently skipped =="
# The defect these exist for, reproduced live before the fix: a task in
# 'checking' with genuine evidence (artifact present, output_file present,
# exit_code 0) whose tests_total was then set to null -- claiming a test run
# while recording none -- printed
#     complete-gate.sh: line 348: [: null: integer expression expected
#     GATE PASS ... COMPLETED g state=done
# and exited 0. `jq -r` renders a stored null as the string "null", `[ null
# -eq 0 ]` errors and returns 2, and the surrounding `if` reads that error as
# "condition not met" -- so check 5 was SKIPPED, not failed. The gate failed
# OPEN on exactly the corruption it exists to catch.
#
# Every case below therefore asserts four things, because three of them alone
# would not have caught the bug: the gate exits nonzero, its message names the
# offending field, the task is still 'checking' when task-state.sh status is
# re-read independently afterwards (never trusting the gate's own output), and
# -- the one that separates a clean refusal from an error that merely happens
# to precede one -- NO bash diagnostic appears anywhere in the output.
#
# A passing control with honest evidence runs from the SAME fixture builder at
# the end of this section, so the refusals cannot be vacuous.

STATE_FILE=".claude/state/team-tasks.json"
checksum() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# honest_evidence_dir -> prints a fresh isolated git repo holding task 'c' in
# 'checking' with completely genuine evidence: a real non-empty artifact, a
# real non-empty output_file, exit_code 0, tests_total 5, tests_skipped 0, and
# a code_snapshot recorded against this very tree. Gating it untouched passes.
honest_evidence_dir() {
  local dir
  dir=$(mktemp -d)
  ( cd "$dir" \
    && git init -q && git config user.email t@t.test && git config user.name t \
    && echo ".claude/state/" > .gitignore \
    && echo "base content" > tracked.txt \
    && git add tracked.txt .gitignore && git commit -qm init \
    && echo "findings, really written" > c-artifact.txt \
    && echo "raw test output" > c-output.txt \
    && bash "$TASK_STATE" create c "Corruptible task" \
    && bash "$TASK_STATE" start c \
    && bash "$TASK_STATE" check c \
    && bash "$TASK_STATE" record-evidence c --command "bash tests/some-suite.sh" \
         --exit-code 0 --tests-total 5 --tests-skipped 0 \
         --output-file c-output.txt --artifact c-artifact.txt ) >/dev/null 2>&1
  printf '%s' "$dir"
}

# corrupt_evidence_dir <jq-path> <json-value> -> the same fixture with one
# field overwritten. Writing the state file directly is the only way to
# manufacture a corrupt evidence record (task-state.sh validates every numeric
# flag it accepts, so it cannot produce one), and it only ever touches a
# throwaway mktemp state file -- never a real project's state. The jq temp
# file is written INSIDE .claude/state/, which this fixture gitignores, so it
# cannot perturb the code snapshot the gate recomputes and turn these into
# accidental staleness failures instead of the corruption failures they test.
corrupt_evidence_dir() {
  local expr="$1" value="$2" dir
  dir=$(honest_evidence_dir)
  jq --argjson v "$value" "$expr = \$v" "$dir/$STATE_FILE" \
    > "$dir/.claude/state/corrupt.tmp" && mv "$dir/.claude/state/corrupt.tmp" "$dir/$STATE_FILE"
  printf '%s' "$dir"
}

# check_gate_refuses <label> <jq-path> <json-value> <field-named-in-message>
check_gate_refuses() {
  local label="$1" expr="$2" value="$3" field="$4"
  local dir out rc cs1 cs2 verdict state
  dir=$(corrupt_evidence_dir "$expr" "$value")
  cs1=$(checksum "$dir/$STATE_FILE")
  out=$(cd "$dir" && bash "$GATE" c 2>&1); rc=$?
  [ "$rc" != "0" ] && verdict=0 || verdict=1
  check "gate REFUSES $label (exit $rc)" "$verdict"
  echo "$out" | grep -q -- "$field"; check "  refusal for $label names the field ($field)" $?
  echo "$out" | grep -qF -- "task 'c'"; check "  refusal for $label names the task" $?
  echo "$out" | grep -q "GATE PASS" && verdict=1 || verdict=0
  check "  refusal for $label never prints GATE PASS" "$verdict"
  # The clean-refusal assertion: any bash diagnostic ("[: null: integer
  # expression expected", "unary operator expected", or anything else carrying
  # a "script: line N:" prefix) means a test expression errored and its error
  # was being consumed as a verdict -- which is the bug, even when the run
  # happens to reject afterwards.
  echo "$out" | grep -Eqi "integer expression expected|unary operator expected|: line [0-9]+:" && verdict=1 || verdict=0
  check "  refusal for $label is CLEAN — no bash diagnostic anywhere in the gate's output" "$verdict"
  state=$(cd "$dir" && bash "$TASK_STATE" status c 2>/dev/null | jq -r '.state')
  [ "$state" = "checking" ] && verdict=0 || verdict=1
  check "  $label task does NOT reach done — re-read independently via task-state.sh status (got: $state)" "$verdict"
  cs2=$(checksum "$dir/$STATE_FILE")
  [ "$cs1" = "$cs2" ] && verdict=0 || verdict=1
  check "  state file byte-for-byte unchanged after the refused gate ($label)" "$verdict"
  rm -rf "$dir"
}

echo "-- THE REPRODUCED BUG: tests_total / tests_skipped, the two fields check 5 compares --"
check_gate_refuses "tests_total = null (claims a test run, records none)" \
  '.tasks.c.evidence[-1].tests_total' 'null' 'tests_total'
check_gate_refuses 'tests_total = the string "five"' \
  '.tasks.c.evidence[-1].tests_total' '"five"' 'tests_total'
check_gate_refuses "tests_total = the fractional number 2.5" \
  '.tasks.c.evidence[-1].tests_total' '2.5' 'tests_total'
check_gate_refuses "tests_skipped = null" \
  '.tasks.c.evidence[-1].tests_skipped' 'null' 'tests_skipped'
check_gate_refuses 'tests_skipped = the string "none"' \
  '.tasks.c.evidence[-1].tests_skipped' '"none"' 'tests_skipped'
check_gate_refuses "tests_skipped = the negative number -1" \
  '.tasks.c.evidence[-1].tests_skipped' '-1' 'tests_skipped'
check_gate_refuses "tests_total absent entirely (evidence records have no legacy shape)" \
  '.tasks.c.evidence[-1] |= del(.tests_total) | .tasks.c.evidence[-1].command' \
  '"bash tests/some-suite.sh"' 'tests_total'

echo "-- exit_code, which check 4 compares: it happened to fail closed on null via a STRING"
echo "   comparison, but that was a coincidence of rendering, not a check --"
check_gate_refuses "exit_code = null" \
  '.tasks.c.evidence[-1].exit_code' 'null' 'exit_code'
check_gate_refuses 'exit_code = the string "zero"' \
  '.tasks.c.evidence[-1].exit_code' '"zero"' 'exit_code'
check_gate_refuses "exit_code = the negative number -1" \
  '.tasks.c.evidence[-1].exit_code' '-1' 'exit_code'
# The other direction, which the old string comparison got WRONG: the JSON
# *string* "0" renders through `jq -r` as exactly "0", so `[ "$X" != "0" ]`
# accepted it and the task completed on an evidence record whose exit_code was
# never a number at all.
check_gate_refuses 'exit_code = the string "0" (renders identically to the number 0)' \
  '.tasks.c.evidence[-1].exit_code' '"0"' 'exit_code'

echo "-- the count-like read in check 2: 'evidence' present but not an array --"
# `(.evidence // []) | length` could not tell "no evidence" from "evidence is
# the wrong type", and on a boolean jq itself errored, leaving the count empty
# so that `[ "" -eq 0 ]` errored and check 2 was skipped outright.
check_gate_refuses 'evidence = the string "five records"' \
  '.tasks.c.evidence' '"five records"' 'evidence'
check_gate_refuses "evidence = the boolean true (the shape that made jq itself error)" \
  '.tasks.c.evidence' 'true' 'evidence'
check_gate_refuses "evidence = the number 3" \
  '.tasks.c.evidence' '3' 'evidence'
check_gate_refuses "latest evidence entry is not a JSON object" \
  '.tasks.c.evidence[-1]' '"just a string"' 'evidence'

echo "-- the same class in the artifact/output_file reads of check 3 --"
# artifacts[] was iterated with `jq -r '.artifacts[]?'`, and that `?` swallows
# the error when .artifacts is not iterable -- so a bare string yielded NO
# paths and the most important check in the script passed having verified
# nothing at all.
check_gate_refuses "artifacts = a bare string instead of an array (the '?' used to swallow this)" \
  '.tasks.c.evidence[-1].artifacts' '"docs/rebuild/FINDINGS.md"' 'artifacts'
check_gate_refuses "artifacts = null" \
  '.tasks.c.evidence[-1].artifacts' 'null' 'artifacts'
check_gate_refuses "artifacts = an array containing a non-string entry" \
  '.tasks.c.evidence[-1].artifacts' '[5]' 'artifacts'
check_gate_refuses "artifacts = an array containing an empty-string path" \
  '.tasks.c.evidence[-1].artifacts' '[""]' 'artifacts'
# output_file's old guard was `[ -n "$X" ] && [ "$X" != "null" ]`, which
# skipped the whole check for a null/absent/empty value -- a record naming no
# output file at all sailed past the check meant to prove the run produced one.
check_gate_refuses "output_file = null (used to skip the check entirely)" \
  '.tasks.c.evidence[-1].output_file' 'null' 'output_file'
check_gate_refuses "output_file = the empty string" \
  '.tasks.c.evidence[-1].output_file' '""' 'output_file'
check_gate_refuses "output_file = a number" \
  '.tasks.c.evidence[-1].output_file' '5' 'output_file'

echo "-- code_snapshot, the entire basis of check 6 --"
check_gate_refuses "code_snapshot = null" \
  '.tasks.c.evidence[-1].code_snapshot' 'null' 'code_snapshot'
check_gate_refuses "code_snapshot = the empty string" \
  '.tasks.c.evidence[-1].code_snapshot' '""' 'code_snapshot'

echo "-- --allow-no-tests does not become a way around the OTHER checks --"
# Under --allow-no-tests the caller has explicitly opted out of the test
# requirement and tests_total/tests_skipped are not consulted at all, so a
# corrupt value there is not read. Everything else still is: a corrupt
# exit_code must still be refused in that mode.
ANT_DIR=$(corrupt_evidence_dir '.tasks.c.evidence[-1].exit_code' 'null')
ANT_OUT=$(cd "$ANT_DIR" && bash "$GATE" c --allow-no-tests 2>&1); RC=$?
[ "$RC" != "0" ] && RC_CHK=0 || RC_CHK=1
check "gate REFUSES a null exit_code even under --allow-no-tests (exit $RC)" $RC_CHK
echo "$ANT_OUT" | grep -q "exit_code"; check "  that refusal still names exit_code" $?
echo "$ANT_OUT" | grep -Eqi "integer expression expected|: line [0-9]+:" && RC_CHK=1 || RC_CHK=0
check "  that refusal is clean — no bash diagnostic" $RC_CHK
ANT_STATE=$(cd "$ANT_DIR" && bash "$TASK_STATE" status c 2>/dev/null | jq -r '.state')
[ "$ANT_STATE" = "checking" ] && RC_CHK=0 || RC_CHK=1
check "  --allow-no-tests task with a corrupt exit_code does NOT reach done (got: $ANT_STATE)" $RC_CHK
rm -rf "$ANT_DIR"

echo "-- THE CONTROL: the same fixture, uncorrupted, must still pass (or the refusals above prove nothing) --"
CTRL_DIR=$(honest_evidence_dir)
CTRL_OUT=$(cd "$CTRL_DIR" && bash "$GATE" c 2>&1); RC=$?
check "control: the SAME fixture with honest evidence still exits 0 (exit $RC)" $RC
echo "$CTRL_OUT" | grep -q "GATE PASS"; check "control: output shows GATE PASS" $?
echo "$CTRL_OUT" | grep -Eqi "integer expression expected|: line [0-9]+:" && RC_CHK=1 || RC_CHK=0
check "control: the passing run emits no bash diagnostic either" $RC_CHK
CTRL_STATE=$(cd "$CTRL_DIR" && bash "$TASK_STATE" status c 2>/dev/null | jq -r '.state')
[ "$CTRL_STATE" = "done" ] && RC_CHK=0 || RC_CHK=1
check "control: honest-evidence task reaches done (got: $CTRL_STATE) — the refusals above are not vacuous" $RC_CHK
rm -rf "$CTRL_DIR"

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
