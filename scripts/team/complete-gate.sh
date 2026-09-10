#!/bin/bash
# Completion gate for the rebuild framework's lead/builder/verifier delivery
# loop. See docs/rebuild/BUILD_PLAN.md Part 1.4 and docs/rebuild/DESIGN.md
# ("Verification contract", "Definition of implementation completion").
#
# THIS SCRIPT IS THE ONLY SANCTIONED PATH TO COMPLETION in the intended
# workflow. `task-state.sh complete <id>` remains callable directly (it has
# to be -- task-state.sh has no idea this script exists, and nothing at the
# task-state.sh layer enforces this), but nothing in this project's intended
# workflow should call it directly: every completion should go through this
# gate, which independently checks the recorded evidence before ever calling
# `task-state.sh complete` as its own final step.
#
# What "independently" means here, concretely -- this is the whole point of
# this script: a builder's or subagent's report that a file was written, a
# test suite passed, or a check succeeded is NEVER accepted at face value.
# This script re-reads the actual state file, opens and reads the actual
# claimed artifact files on disk, and re-derives the actual current code
# snapshot itself, rather than trusting anything a prior report claimed.
# This is not a hypothetical concern: during Part 1.1 research for this
# project, a subagent's final report claimed a findings file had been
# written; the file did not exist anywhere in the repository, and this was
# only caught because the claim was checked instead of trusted (see
# BUILD_PLAN.md, "Definition of implementation completion"). Check 3 below
# (the artifact check) is this script's direct answer to that incident, and
# per that same section of BUILD_PLAN.md, it is deliberately the FIRST
# evidence-content check this script performs.
#
# Usage:
#   complete-gate.sh <task-id> [--require-tests | --allow-no-tests]
#
# --require-tests is the default (BUILD_PLAN.md Part 1.4's acceptance text
# itself lists "no required tests" as a rejection condition, implying tests
# are required unless a caller explicitly opts out). --allow-no-tests exists
# for parts that genuinely have no test surface (e.g. pure documentation) --
# use it deliberately, not as a way around a real gap in coverage.
#
# Checks, run in this exact order, stopping at the FIRST failure:
#   1. Task exists and is in "checking" state.
#   2. At least one evidence record exists (see task-state.sh record-evidence).
#   3. Artifact check on the LATEST evidence entry (see above -- this is the
#      most important check in this script). Every path in that entry's
#      artifacts[] AND its output_file must exist on disk AND be non-empty;
#      a zero-byte file is treated as failed evidence, same as a missing
#      file. Every such path is stored already-resolved to absolute by
#      task-state.sh's record-evidence (relative to the evidence's own
#      recorded --cwd), so this check needs no cwd guessing of its own and
#      is correct regardless of which directory this gate is invoked from.
#   4. Latest evidence's exit_code is 0.
#   5. Test requirements (only under --require-tests, the default):
#      tests_total > 0 and tests_skipped == 0.
#   6. Evidence is not stale: the latest evidence's recorded code_snapshot
#      must match the CURRENT actual code snapshot, computed live, right now
#      -- not read from anywhere cached.
#
# Only if every check passes does this script call `task-state.sh complete
# <task-id>` as its own final step.
#
# Exit codes: 0 gate passed and task-state.sh complete succeeded
#             1 a check failed, or task-state.sh complete itself failed
#             2 bad usage / missing jq dependency
#
# --- Disclosed residual race ---
# This script reads task state (via `task-state.sh status`), validates it,
# and only THEN calls `task-state.sh complete` as a separate final step.
# Those are two separate invocations of task-state.sh, each independently
# locked and atomic on its own -- but the gap between them is not covered by
# a single lock held across both. Concretely: `task-state.sh complete`
# itself re-validates (under its own lock) that the task is still in
# "checking" state at the moment it runs, so a concurrent `block` or a
# second `complete` landing in that gap cannot corrupt the state file or
# double-complete a task -- task-state.sh's own guards still hold. What is
# NOT re-validated at that final moment is the EVIDENCE itself: if a
# concurrent `task-state.sh record-evidence` call lands in the gap between
# this script's check 6 and its final `complete` call, the task still
# completes, and the evidence that was actually validated is not necessarily
# the evidence array's new latest entry. This is a narrower race than the
# lost-update races fixed in Part 1.2/1.3 (those were about a single
# command's own read-modify-write sequence racing against itself; this is a
# gap between two already-atomic commands run back to back by this script),
# and it is disclosed here rather than silently ignored. Closing it fully
# would need task-state.sh to grow a "complete only if evidence still
# matches snapshot X" compare-and-swap style operation -- out of scope for
# this part; see BUILD_PLAN.md Part 1.4's status line for this project's own
# tracking of the gap.
#
# No network calls, no model calls. Pure local state management, same as
# task-state.sh and assign.sh.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TASK_STATE="$HERE/task-state.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: complete-gate.sh <task-id> [--require-tests | --allow-no-tests]

Independently validates a task's recorded evidence (see task-state.sh
record-evidence) and, only if every check passes, calls
`task-state.sh complete <task-id>` as its own final step. See the header
comment in this file for the exact check order and the disclosed residual
race between this script's checks and its final `complete` call.

Exit codes: 0 gate passed and task completed · 1 a check failed, or
            task-state.sh complete itself failed · 2 bad usage
USAGE
}

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (install: winget install jqlang.jq)" >&2
  exit 2
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum is required (used by compute_snapshot for dirty-tree content hashing)" >&2
  exit 2
fi

TASK_ID="${1:-}"
if [ -z "$TASK_ID" ] || [ "${TASK_ID#-}" != "$TASK_ID" ]; then
  usage
  exit 2
fi
shift

MODE="require-tests"
while [ $# -gt 0 ]; do
  case "$1" in
    --require-tests) MODE="require-tests"; shift ;;
    --allow-no-tests) MODE="allow-no-tests"; shift ;;
    *) echo "ERROR: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

gate_fail() {
  echo "GATE FAIL (check $1): $2" >&2
  exit 1
}

# warn_if_state_not_gitignored -- Part 1.6. Prints ONE advisory warning to
# stderr (never fails the run) if the current directory is a git repository
# AND .claude/state/ is not excluded from `git status` in it. This is purely
# advisory: it must never block a legitimate gate run, so it never affects
# this script's exit code.
#
# The risk it names: compute_snapshot() below (and task-state.sh's identical
# copy) hashes `git status --porcelain` / `git diff HEAD` output to build the
# dirty-tree code_snapshot identity. If .claude/state/ is not gitignored,
# task-state.sh's own bookkeeping writes to .claude/state/team-tasks.json
# (including the very evidence-write that triggered this check) show up as
# tracked/untracked changes and get hashed into that snapshot too -- so the
# snapshot recorded at evidence time and the snapshot recomputed here at gate
# time can differ EVEN THOUGH NO REAL CODE CHANGED, causing check 6 to reject
# genuinely-fresh evidence as stale. See compute_snapshot()'s own comment
# below and task-state.sh's identical copy for the fuller explanation.
#
# "one-time-per-run": guarded by _STATE_GITIGNORE_WARNED so repeated calls in
# one script invocation (this script currently calls it once, but the guard
# keeps that safe if that ever changes) only ever print once. Keep this
# function's detection logic and wording identical to task-state.sh's copy.
_STATE_GITIGNORE_WARNED=""
warn_if_state_not_gitignored() {
  [ -n "$_STATE_GITIGNORE_WARNED" ] && return
  _STATE_GITIGNORE_WARNED=1

  # Not a git repository at all -> nothing to warn about (git rev-parse
  # exits non-zero with a "not a git repository" fatal on stderr in that
  # case; discard it, this is a routine, expected outcome here, not an
  # error).
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

  # `git check-ignore -q PATH` exits 0 if PATH is excluded (ignored), 1 if
  # it is not excluded, and >1 on a real error. Query a path CLEARLY NESTED
  # under .claude/state/ (not the bare directory name) -- a directory-only
  # gitignore pattern like ".claude/state/" only reliably matches through
  # check-ignore once something actually exists at or under that path; a
  # bare, not-yet-existing .claude/state directory can spuriously report
  # exit 1 ("not ignored") even when the pattern would in fact ignore it
  # once created. A nested probe path sidesteps this regardless of whether
  # .claude/state itself exists yet. Only the "not excluded" case (exit
  # exactly 1) should warn -- a real error (e.g. run outside a usable work
  # tree, such as a bare repository) means we can't determine the answer,
  # so stay silent rather than guessing.
  git check-ignore -q .claude/state/.gitcheck-probe 2>/dev/null
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "WARNING: .claude/state/ is not excluded from 'git status' in this repository. task-state.sh's own bookkeeping writes to .claude/state/team-tasks.json will then show up as tracked/untracked changes and get hashed into compute_snapshot()'s dirty-tree code_snapshot identity, which can make genuinely-fresh evidence look stale (spurious 'evidence is stale' failures in complete-gate.sh's check 6) even though no real code changed. Fix: add '.claude/state/' to this repository's .gitignore." >&2
  fi
}

# Code snapshot identity: short commit SHA when the tree is clean, or
# "uncommitted, base SHA X, diff Y" when it is dirty, where Y is a short
# prefix of a sha256 hash over the ACTUAL dirty content -- tracked changes
# (via `git diff HEAD`) plus the content of every untracked file -- not just
# a bare clean/dirty flag. A bare flag plus the base SHA is NOT enough: two
# materially different dirty trees off the same base commit would otherwise
# produce the identical snapshot string, so evidence recorded against one
# dirty state would be wrongly accepted as still-fresh after the tree
# changed again without a commit. Same compute_snapshot logic as assign.sh
# and task-state.sh -- kept as a third copy for the same reason
# task-state.sh's own copy is a copy rather than a source: these are
# independent CLI entry points. If you change this, change assign.sh's and
# task-state.sh's compute_snapshot to match.
#
# REQUIRES .claude/state/ to be excluded from `git status` in the target
# repo (this repo's own .gitignore already does this, as of Phase 1.2). If
# it is not gitignored, task-state.sh's own bookkeeping writes (including
# the evidence write that triggered this very check) become visible as tree
# changes and get hashed into the snapshot, causing spurious "evidence is
# stale" failures on genuinely-fresh evidence. This has no path to a false
# PASS -- only a confusing false FAIL -- but it's easy to hit blind if
# adopting this tooling in a repo where .claude/state/ isn't gitignored.
compute_snapshot() {
  local sha
  sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  if [ -z "$sha" ]; then
    echo "no-git-repository"
    return
  fi
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    local diff_hash
    diff_hash=$(
      {
        # Tracked changes (staged and unstaged) against the base commit.
        git diff HEAD 2>/dev/null
        # Untracked files: `git diff HEAD` says nothing about these, so list
        # them (the porcelain line itself, which captures the path) and hash
        # their actual content too -- a new/renamed untracked file with
        # different content must produce a different hash, not just "some
        # untracked file changed".
        git status --porcelain --untracked-files=all 2>/dev/null | while IFS= read -r line; do
          echo "$line"
          case "$line" in
            '??'*) f="${line#???}"; [ -f "$f" ] && cat "$f" ;;
          esac
        done
      } | sha256sum | awk '{print $1}' | cut -c1-12
    )
    echo "uncommitted, base SHA $sha, diff $diff_hash"
  else
    echo "$sha"
  fi
}

# Part 1.6 advisory check, run before any of the gate's normal work below.
warn_if_state_not_gitignored

# ---- Check 1: task exists and is in "checking" state. ----
STATUS_OUT=$(bash "$TASK_STATE" status "$TASK_ID" 2>&1)
STATUS_RC=$?
if [ "$STATUS_RC" -ne 0 ]; then
  # Forward task-state.sh's own not-found message rather than inventing a
  # different one.
  echo "GATE FAIL (check 1): $STATUS_OUT" >&2
  exit 1
fi
CUR_STATE=$(echo "$STATUS_OUT" | jq -r '.state')
if [ "$CUR_STATE" != "checking" ]; then
  gate_fail 1 "task '$TASK_ID' is in state '$CUR_STATE', must be 'checking' to gate completion."
fi

# ---- Check 2: at least one evidence record exists. ----
EVIDENCE_COUNT=$(echo "$STATUS_OUT" | jq '(.evidence // []) | length')
if [ "$EVIDENCE_COUNT" -eq 0 ]; then
  gate_fail 2 "no evidence recorded for task '$TASK_ID' — run task-state.sh record-evidence first."
fi

LATEST=$(echo "$STATUS_OUT" | jq -c '.evidence[-1]')

# ---- Check 3 (FIRST among evidence-content checks, per BUILD_PLAN.md's own
#      hard rule): artifact check on the LATEST evidence entry, PLUS the
#      recorded output_file -- both are "claimed artifact must actually
#      exist" checks, so they run together as one conceptual step, though
#      with distinct error labels below so a failure always says clearly
#      which kind of path was missing/empty. Every claimed path (declared
#      artifacts[] entries AND output_file) is independently opened/stat'd on
#      disk here -- never trusted because it's present in the evidence
#      record. As of the record-evidence fix, every such path is stored
#      already-resolved to absolute by task-state.sh, so this check needs no
#      cwd guessing of its own and works correctly regardless of which
#      directory this gate is invoked from. ----
MISSING=()
EMPTY=()
while IFS= read -r art; do
  # Strip a trailing \r: on this project's primary platform (Windows Git
  # Bash / MSYS), `jq -r` emits CRLF line endings for multi-line output fed
  # through a pipe, unlike a single-scalar command substitution (which this
  # script's other jq -r reads use, and which are unaffected -- verified
  # empirically during development). Without this strip, every claimed
  # artifact path would carry an invisible trailing \r and every `[ -f ]`
  # check below would falsely report a real, existing file as missing.
  art="${art%$'\r'}"
  [ -n "$art" ] || continue
  if [ ! -f "$art" ]; then
    MISSING+=("$art")
  elif [ ! -s "$art" ]; then
    EMPTY+=("$art")
  fi
done < <(echo "$LATEST" | jq -r '.artifacts[]?')

# output_file: same existence/non-empty check as declared artifacts, but
# tracked separately (a single path, not an array) so the failure message
# below can name it as the output_file specifically rather than folding it
# anonymously into the artifacts[] list.
OUTPUT_FILE_MISSING=""
OUTPUT_FILE_EMPTY=""
OUTPUT_FILE=$(echo "$LATEST" | jq -r '.output_file')
OUTPUT_FILE="${OUTPUT_FILE%$'\r'}"
if [ -n "$OUTPUT_FILE" ] && [ "$OUTPUT_FILE" != "null" ]; then
  if [ ! -f "$OUTPUT_FILE" ]; then
    OUTPUT_FILE_MISSING="$OUTPUT_FILE"
  elif [ ! -s "$OUTPUT_FILE" ]; then
    OUTPUT_FILE_EMPTY="$OUTPUT_FILE"
  fi
fi

if [ "${#MISSING[@]}" -gt 0 ] || [ "${#EMPTY[@]}" -gt 0 ] || [ -n "$OUTPUT_FILE_MISSING" ] || [ -n "$OUTPUT_FILE_EMPTY" ]; then
  MSG="claimed artifact(s) failed independent verification for task '$TASK_ID':"
  if [ "${#MISSING[@]}" -gt 0 ]; then
    MSG="$MSG
  declared artifact(s) missing (do not exist on disk): $(printf '%s, ' "${MISSING[@]}" | sed 's/, $//')"
  fi
  if [ "${#EMPTY[@]}" -gt 0 ]; then
    MSG="$MSG
  declared artifact(s) empty (zero-byte, as suspicious as missing): $(printf '%s, ' "${EMPTY[@]}" | sed 's/, $//')"
  fi
  if [ -n "$OUTPUT_FILE_MISSING" ]; then
    MSG="$MSG
  output_file missing (does not exist on disk): $OUTPUT_FILE_MISSING"
  fi
  if [ -n "$OUTPUT_FILE_EMPTY" ]; then
    MSG="$MSG
  output_file empty (zero-byte, as suspicious as missing): $OUTPUT_FILE_EMPTY"
  fi
  gate_fail 3 "$MSG"
fi

# ---- Check 4: latest evidence's exit_code is 0. ----
EXIT_CODE=$(echo "$LATEST" | jq -r '.exit_code')
EV_COMMAND=$(echo "$LATEST" | jq -r '.command')
if [ "$EXIT_CODE" != "0" ]; then
  gate_fail 4 "latest evidence shows exit code $EXIT_CODE (not 0) for command: $EV_COMMAND"
fi

# ---- Check 5: test requirements (only under --require-tests, the default). ----
if [ "$MODE" = "require-tests" ]; then
  TESTS_TOTAL=$(echo "$LATEST" | jq -r '.tests_total')
  TESTS_SKIPPED=$(echo "$LATEST" | jq -r '.tests_skipped')
  if [ "$TESTS_TOTAL" -eq 0 ]; then
    gate_fail 5 "no tests were run — tests_total is 0 (pass --allow-no-tests if this part genuinely has no test surface)."
  fi
  if [ "$TESTS_SKIPPED" -ne 0 ]; then
    gate_fail 5 "$TESTS_SKIPPED required tests were skipped."
  fi
fi

# ---- Check 6: evidence not stale. ----
RECORDED_SNAPSHOT=$(echo "$LATEST" | jq -r '.code_snapshot')
CURRENT_SNAPSHOT=$(compute_snapshot)
if [ "$RECORDED_SNAPSHOT" != "$CURRENT_SNAPSHOT" ]; then
  gate_fail 6 "evidence is stale — recorded against snapshot $RECORDED_SNAPSHOT, current snapshot is $CURRENT_SNAPSHOT; code changed since verification, re-run checks."
fi

# ---- All checks passed. This is the only place in this script that calls
#      `task-state.sh complete`. See the header's "Disclosed residual race"
#      section for the gap between the checks above and this call. ----
RECORDED_AT=$(echo "$LATEST" | jq -r '.recorded_at')
echo "GATE PASS: task '$TASK_ID' — evidence recorded at $RECORDED_AT accepted (snapshot: $CURRENT_SNAPSHOT)"

COMPLETE_OUT=$(bash "$TASK_STATE" complete "$TASK_ID" 2>&1)
COMPLETE_RC=$?
echo "$COMPLETE_OUT"
if [ "$COMPLETE_RC" -ne 0 ]; then
  echo "GATE FAIL: all evidence checks passed, but task-state.sh complete itself rejected the transition (see message above) -- most likely the disclosed residual race: task state changed between this gate's checks and its final complete call." >&2
  exit 1
fi

exit 0
