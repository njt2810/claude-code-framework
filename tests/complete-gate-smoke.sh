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

echo "-- not inside a git repository at all: no warning, no crash --"
NOGIT_DIR=$(mktemp -d)
gated_task_in "$NOGIT_DIR" nogit-gate
ERR_OUT=$(cd "$NOGIT_DIR" && bash "$GATE" nogit-gate 2>&1 1>/dev/null)
RC_OUT=$(cd "$NOGIT_DIR" && bash "$TASK_STATE" status nogit-gate | jq -r '.state')
[ -z "$ERR_OUT" ]; check "no warning printed outside a git repository (got: $ERR_OUT)" $?
[ "$RC_OUT" = "done" ]; check "task reaches done normally outside a git repository (both snapshots are no-git-repository, so staleness check trivially matches)" $?
rm -rf "$NOGIT_DIR"

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
