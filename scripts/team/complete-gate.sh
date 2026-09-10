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
# EVERY CHECK BELOW FAILS CLOSED. A field it reads that is absent, null, of
# the wrong type, negative, fractional or otherwise unparseable REFUSES
# completion, naming the task, the field, the offending value and the check
# that was running. It is never treated as "the condition was not met" and
# never skipped. See "fail-closed reads of the recorded evidence" further down
# for the defect that rule exists to close and why it is enforced per read.
#
# Checks, run in this exact order, stopping at the FIRST failure:
#   1. Task exists and is in "checking" state.
#   2. At least one evidence record exists (see task-state.sh record-evidence),
#      the evidence field really is an array, and its latest entry really is a
#      JSON object.
#   3. Artifact check on the LATEST evidence entry (see above -- this is the
#      most important check in this script). Every path in that entry's
#      artifacts[] AND its output_file must exist on disk AND be non-empty;
#      a zero-byte file is treated as failed evidence, same as a missing
#      file. Every such path is stored already-resolved to absolute by
#      task-state.sh's record-evidence (relative to the evidence's own
#      recorded --cwd), so this check needs no cwd guessing of its own and
#      is correct regardless of which directory this gate is invoked from.
#   4. Latest evidence's exit_code is 0 (validated as a real non-negative
#      integer first, not compared as a rendered string).
#   5. Test requirements (only under --require-tests, the default):
#      tests_total > 0 and tests_skipped == 0. Under --allow-no-tests these
#      two fields are not consulted at all -- the caller has explicitly opted
#      out of the requirement they express.
#   6. Evidence is not stale: the latest evidence's recorded code_snapshot
#      must match the CURRENT actual code snapshot, computed live, right now
#      -- not read from anywhere cached. WITH ONE HONEST EXCEPTION, spelled
#      out below and in check 6 itself: when there is no version control, no
#      code identity exists to compare, and this check reports that it could
#      NOT verify staleness rather than reporting a pass.
#
# Only if every check passes does this script call `task-state.sh complete
# <task-id>` as its own final step -- always with
# `--staleness-verified yes|no`, so check 6's honest verdict is recorded in
# the state file and not merely printed here.
#
# --- Check 6 outside a git repository: THE GATE NEVER CLAIMS A CHECK IT DID
# --- NOT PERFORM ---
# compute_snapshot() cannot compute a code identity when there is no git
# repository (or git is broken/absent). It degrades to the fixed placeholder
# "no-git-repository" -- the same string for every possible state of the code.
# Check 6 then compared that placeholder against itself, matched every time,
# and printed "GATE PASS ... (snapshot: no-git-repository)". Reproduced: record
# evidence in a non-git directory, then overwrite the artifact with completely
# different content, and the gate accepted it and completed the task, reporting
# a snapshot match. Nothing was stale-checked at all. That is this project's
# recurring defect class -- an unavailable input becoming a value that means
# "condition satisfied" -- and here it was worse than a skipped check, because
# the OUTPUT asserted the check had succeeded.
#
# The semantics, decided deliberately rather than defaulted into:
#   - A non-git project is LEGITIMATE and must still be able to complete work,
#     so this does NOT refuse completion.
#   - The gate must never again imply staleness was verified when it was not.
#     So when EITHER snapshot is the placeholder, check 6 emits an explicit
#     warning that staleness COULD NOT BE VERIFIED and that any code drift
#     since the evidence was recorded is therefore UNDETECTED; the final line
#     says "GATE PASS (WITHOUT STALENESS VERIFICATION)" and states plainly what
#     was not checked, instead of naming a snapshot that "matched".
#   - The verdict is RECORDED, not just printed: `task-state.sh complete
#     --staleness-verified no` writes staleness_verified: false onto the
#     checking -> done history entry, so an auditor reading the state file
#     months later can tell a genuinely-verified completion from one that could
#     not be. Only recorded state is ground truth in this subsystem; a warning
#     that exists solely on stdout can be swallowed by a pipe.
# A git-backed run is unaffected: it still fails check 6 as stale on real
# drift, and still records staleness_verified: true on a genuine pass.
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

# --- fail-closed reads of the recorded evidence ------------------------------
#
# THE DEFECT THIS SECTION EXISTS FOR -- read it before "simplifying" any read
# below back into a bare `jq -r` plus `[ ... -eq ]`.
#
# Every check below pulls fields out of a JSON evidence record and compares
# them. Read with a bare `jq -r` and compared with `[ ... -eq ]` / `-ne`, a
# stored `null` arrives in bash as the literal string "null"; `[` then prints
# "integer expression expected" to stderr and returns 2. An `if` reads ANY
# non-zero return as "condition not met", so the check is SKIPPED rather than
# failed -- the gate FAILS OPEN on precisely the corruption it exists to
# catch. This is not hypothetical: an evidence record claiming a test run but
# recording `tests_total: null` was observed passing check 5 and completing
# the task, with nothing but a bash diagnostic on stderr to show for it.
# `set -u` cannot catch it -- the command RAN; it just returned non-zero from
# a test expression whose failure was being read as a verdict.
#
# THE RULE: no value read out of the evidence record is compared, tested or
# used in arithmetic until it has been through one of the require_evidence_*
# helpers below. They are the single implementation of "is this value usable
# at all", and they FAIL CLOSED -- absent, null, wrong type, negative,
# fractional, or unparseable all REFUSE completion, naming the task, the
# field, the offending value and the check that was running. An unparseable
# value is CORRUPTION and is never quietly re-read as "the condition was not
# met".
#
# Note where this DIFFERS from task-state.sh's read_numeric_field, whose
# philosophy and tone these follow otherwise: there, an absent key is a
# legitimate pre-2.2 legacy record and defaulting is correct. Here it is not.
# Evidence records have no legacy shape -- `record-evidence` has required and
# validated --exit-code / --tests-total / --tests-skipped / --output-file and
# written artifacts[] and code_snapshot in one atomic object since evidence
# existed at all -- so a MISSING field is as much a sign of a hand-edited or
# partially written record as a null one, and is refused the same way.
#
# Why per-read guards and not something global: the obvious global fix does
# not work. `set -e` plus an ERR trap cannot see this class at all, because
# bash deliberately suppresses both inside an `if` condition -- which is
# exactly where every one of these comparisons lives. The other candidate,
# validating the whole latest-evidence record up front in one pass, would
# reorder failures: this script's contract (see the header) is that checks run
# in a fixed order stopping at the FIRST failure, with the artifact check
# deliberately first among the evidence-content checks per BUILD_PLAN.md's own
# hard rule. A record with both a missing artifact and a null tests_total must
# still report the missing artifact. So the guard runs at each read, inside
# the check that owns it, and the structural part is that there is exactly ONE
# implementation of the rule and no raw read left that reaches a comparison.
#
# Why these must never be called inside $( ): their refusal path is gate_fail,
# i.e. `exit 1`. An `exit` inside a command substitution only kills the
# subshell and leaves the caller running on with an empty value -- which is
# the very silent-skip class of bug they exist to make impossible. They
# therefore publish their result in a global rather than printing it. Same
# convention, and the same reason, as task-state.sh's read_numeric_field.
#
# Kept here rather than sourced from task-state.sh for the same reason this
# file keeps its own compute_snapshot and warn_if_state_not_gitignored: these
# are independent CLI entry points, and that duplication is this project's
# existing, deliberate convention.

# evidence_field_fail <check> <field> <what-this-check-needs> <what-was-wrong>
# The single refusal message shared by every helper below, so the wording and
# the "corruption, not 'condition not met'" framing cannot drift between them.
evidence_field_fail() {
  gate_fail "$1" "task '$TASK_ID' has an unusable '$2' field in its recorded evidence (got: $4) — this check needs $3.
  A value that cannot be parsed as that is treated as CORRUPTION and REFUSES completion; it is never re-read as 'the condition was not met', which is how a gate silently fails OPEN. Nothing was changed.
  Only 'task-state.sh record-evidence' should ever write this field, and it validates every value it accepts — so a record failing here was hand-edited, partially written, or produced by something other than task-state.sh."
}

# require_evidence_number <check> <json> <field> -> EVIDENCE_NUMBER
# Resolves ONE field of the given JSON object to a plain non-negative integer,
# or refuses. Must not be called in a command substitution (see above).
EVIDENCE_NUMBER=""
require_evidence_number() {
  local check="$1" json="$2" field="$3" verdict
  verdict=$(printf '%s\n' "$json" | jq -r --arg f "$field" '
    if type != "object" then "shape"
    elif (has($f) | not) then "absent"
    else .[$f] as $v
      | if ($v | type) == "number" and $v >= 0 and $v == ($v | floor)
        then "ok:" + ($v | tostring)
        else "bad:" + ($v | tojson)
        end
    end
  ' 2>/dev/null)
  verdict="${verdict%$'\r'}"

  case "$verdict" in
    ok:*)
      EVIDENCE_NUMBER="${verdict#ok:}"
      # Belt and braces, same as task-state.sh's: a value can satisfy jq's
      # numeric tests above and still not reach bash as a plain run of digits
      # -- exponent form ("1E+30"), or a decimal spelling of a whole number
      # ("0.0"), depending on the jq build. Bash arithmetic would mangle
      # either, so anything that is not plain digits is refused here too.
      case "$EVIDENCE_NUMBER" in
        ''|*[!0-9]*)
          evidence_field_fail "$check" "$field" "a plain non-negative integer" \
            "$EVIDENCE_NUMBER — numeric in the state file, but it does not render as a plain run of digits"
          ;;
      esac
      return 0
      ;;
    absent) evidence_field_fail "$check" "$field" "a plain non-negative integer" "the field is absent entirely" ;;
    shape)  evidence_field_fail "$check" "$field" "a plain non-negative integer" "the evidence entry is not a JSON object" ;;
    bad:*)  evidence_field_fail "$check" "$field" "a plain non-negative integer" "${verdict#bad:}" ;;
    *)      evidence_field_fail "$check" "$field" "a plain non-negative integer" "unreadable — the evidence entry could not be parsed as JSON" ;;
  esac
}

# require_evidence_string <check> <json> <field> -> EVIDENCE_STRING
# Same contract for the non-numeric fields the checks below actually act on
# (output_file, code_snapshot): a JSON string, non-empty. `null`, a number, an
# absent key or a bare "" all refuse rather than being skipped. The old
# `[ "$X" != "null" ]` spelling could not tell JSON null from the literal
# string "null" at all, and treated both as "nothing to check here".
EVIDENCE_STRING=""
require_evidence_string() {
  local check="$1" json="$2" field="$3" verdict
  verdict=$(printf '%s\n' "$json" | jq -r --arg f "$field" '
    if type != "object" then "shape"
    elif (has($f) | not) then "absent"
    else .[$f] as $v
      | if ($v | type) == "string" and ($v | length) > 0
        then "ok:" + $v
        else "bad:" + ($v | tojson)
        end
    end
  ' 2>/dev/null)
  verdict="${verdict%$'\r'}"

  case "$verdict" in
    ok:*)
      EVIDENCE_STRING="${verdict#ok:}"
      EVIDENCE_STRING="${EVIDENCE_STRING%$'\r'}"
      return 0
      ;;
    absent) evidence_field_fail "$check" "$field" "a non-empty string" "the field is absent entirely" ;;
    shape)  evidence_field_fail "$check" "$field" "a non-empty string" "the evidence entry is not a JSON object" ;;
    bad:*)  evidence_field_fail "$check" "$field" "a non-empty string" "${verdict#bad:}" ;;
    *)      evidence_field_fail "$check" "$field" "a non-empty string" "unreadable — the evidence entry could not be parsed as JSON" ;;
  esac
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
#
# *** THE "no-git-repository" RETURN IS NOT A CODE IDENTITY. READ THIS BEFORE
# *** COMPARING TWO SNAPSHOTS ANYWHERE.
# When there is no git repository (or git is broken/absent), this function
# CANNOT compute a code identity, and it returns the fixed string
# "no-git-repository" -- the same string every time, for every possible state of
# the code. Two such values comparing EQUAL therefore proves NOTHING about the
# code: rewrite every file in the directory and the two snapshots still match.
# Any comparison that treats that match as "the evidence is fresh" is claiming a
# check it did not perform. This is a DELIBERATE degradation, not an oversight
# -- a non-git project is legitimate and must still be able to complete work --
# but every caller that compares snapshots must detect this value FIRST and say
# plainly that nothing was verified. Compare against $NO_GIT_SNAPSHOT below
# rather than retyping the literal.
# The caller in this file: CHECK 6 (search "Check 6", near the end), which warns,
# passes WITHOUT staleness verification instead of reporting a match, and
# records staleness_verified: false via `complete --staleness-verified no`.
# task-state.sh's `resume` does the same thing in its CODE CHECK; see the
# matching note above its own copy of this function.
# This note lives ABOVE the function rather than inside it on purpose: the three
# copies of compute_snapshot's BODY (here, assign.sh, task-state.sh) must stay
# byte-for-byte identical, while these preamble comments are already per-file.
# Do not move it into the body.
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

# The exact string compute_snapshot returns when it could not compute a code
# identity at all. Declared OUTSIDE the function (which must stay byte-identical
# to assign.sh's and task-state.sh's copies -- so the literal stays inline
# there) purely so check 6 cannot drift from it by a typo. A snapshot equal to
# this is an ABSENCE of information, never a code identity; see the note above
# compute_snapshot. task-state.sh declares the same constant, with the same
# value, for the same reason.
NO_GIT_SNAPSHOT="no-git-repository"

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
# THE ONE BARE `jq -r` LEFT IN THIS SCRIPT THAT FEEDS A DECISION, and why it is
# not routed through the require_evidence_* family like every other one.
# The comparison below is a POSITIVE MATCH: completion proceeds only if this
# value is exactly "checking". Every failure mode of the read lands on "not
# checking" and therefore REFUSES -- a stored null renders as "null", an absent
# key as "null", an array as a multi-line blob, and a jq that fails outright
# leaves the value empty. There is no input, corrupt or otherwise, that this
# read can turn into permission. That is structurally the opposite of the defect
# class the helpers exist for, where an unreadable value became "the condition
# was not met" and a check was SKIPPED; skipping is impossible here, because the
# check IS the requirement to match. The cost of leaving it is a less specific
# message for a corrupt record (it reports the offending state rather than
# naming corruption), never a false pass. Do NOT change this to a negative test
# (e.g. `= "done"` -> refuse): that inverts the safe direction and re-opens the
# class here.
CUR_STATE=$(echo "$STATUS_OUT" | jq -r '.state')
if [ "$CUR_STATE" != "checking" ]; then
  gate_fail 1 "task '$TASK_ID' is in state '$CUR_STATE', must be 'checking' to gate completion."
fi

# ---- Check 2: at least one evidence record exists, and the evidence array
#      and its latest entry are structurally usable at all. ----
#
# The count is resolved in jq, which knows the difference between "no evidence
# key / null / empty array" (a genuine no-evidence task, the original message
# below, unchanged) and "evidence is present but is not an array" (corruption).
# The old `(.evidence // []) | length` could not tell those apart and, worse,
# errored out entirely on some shapes (`evidence: true`), leaving
# EVIDENCE_COUNT empty so that `[ "" -eq 0 ]` errored and the check was
# skipped -- the same fail-open shape as the tests_total defect above.
EVIDENCE_SHAPE=$(echo "$STATUS_OUT" | jq -r '
  if type != "object" then "shape"
  elif (has("evidence") | not) or (.evidence == null) then "empty"
  elif (.evidence | type) != "array" then "bad:" + (.evidence | tojson)
  elif (.evidence | length) == 0 then "empty"
  else "ok:" + (.evidence | length | tostring)
  end
' 2>/dev/null)
EVIDENCE_SHAPE="${EVIDENCE_SHAPE%$'\r'}"
case "$EVIDENCE_SHAPE" in
  empty)
    gate_fail 2 "no evidence recorded for task '$TASK_ID' — run task-state.sh record-evidence first."
    ;;
  ok:*)
    EVIDENCE_COUNT="${EVIDENCE_SHAPE#ok:}"
    case "$EVIDENCE_COUNT" in
      ''|*[!0-9]*)
        evidence_field_fail 2 "evidence" "a countable array" "a length that does not render as a plain integer ($EVIDENCE_COUNT)"
        ;;
    esac
    ;;
  bad:*)
    evidence_field_fail 2 "evidence" "an array of evidence records" "${EVIDENCE_SHAPE#bad:}"
    ;;
  *)
    evidence_field_fail 2 "evidence" "an array of evidence records" "unreadable — the task record could not be parsed as JSON"
    ;;
esac

LATEST=$(echo "$STATUS_OUT" | jq -c '.evidence[-1]')
# Every check from here on reads fields out of $LATEST, so it has to actually
# be an object before any of them run -- otherwise each field read below
# degrades to an empty value and the checks that consume it get skipped one by
# one instead of failing. Refuse once, here, with a message that says what is
# actually wrong.
LATEST_SHAPE=$(printf '%s\n' "$LATEST" | jq -r 'type' 2>/dev/null)
LATEST_SHAPE="${LATEST_SHAPE%$'\r'}"
if [ "$LATEST_SHAPE" != "object" ]; then
  evidence_field_fail 2 "evidence[-1]" "a JSON object" "a JSON ${LATEST_SHAPE:-value that could not be parsed}"
fi

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
#
# The artifacts[] read below is `jq -r '.artifacts[]?'`, and the `?` there
# swallows an error if `.artifacts` is not iterable at all -- so a corrupted
# `artifacts: "docs/x.md"` (a bare string rather than an array) would yield NO
# paths and this check, the most important one in the script, would pass
# having verified nothing. Same fail-open shape, different spelling. So the
# array's shape is settled first, and only then iterated.
ARTIFACTS_SHAPE=$(echo "$LATEST" | jq -r '
  if (has("artifacts") | not) then "bad:the field is absent entirely"
  elif (.artifacts | type) != "array" then "bad:not a JSON array — " + (.artifacts | tojson)
  elif ([.artifacts[] | select(type != "string")] | length) > 0
    then "bad:the array contains non-string entries — " + ([.artifacts[] | select(type != "string")] | tojson)
  elif ([.artifacts[] | select(length == 0)] | length) > 0
    then "bad:the array contains an empty-string path, which claims an artifact while naming no file"
  else "ok"
  end
' 2>/dev/null)
ARTIFACTS_SHAPE="${ARTIFACTS_SHAPE%$'\r'}"
if [ "$ARTIFACTS_SHAPE" != "ok" ]; then
  case "$ARTIFACTS_SHAPE" in
    bad:*) evidence_field_fail 3 "artifacts" "an array of non-empty path strings" "${ARTIFACTS_SHAPE#bad:}" ;;
    *)     evidence_field_fail 3 "artifacts" "an array of non-empty path strings" "unreadable — the evidence entry could not be parsed as JSON" ;;
  esac
fi

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
#
# output_file is REQUIRED, not optional. The old guard here was
# `[ -n "$X" ] && [ "$X" != "null" ]`, which quietly skipped the whole check
# when the field was absent, JSON null, or an empty string -- an evidence
# record that names no output file at all sailed past the very check that is
# supposed to prove the run produced output. (It also could not tell JSON null
# from a file literally named "null", because both render identically through
# `jq -r`.) require_evidence_string settles the type in jq instead, and
# refuses rather than skips. `record-evidence` has always required
# --output-file, so no honest record is affected.
OUTPUT_FILE_MISSING=""
OUTPUT_FILE_EMPTY=""
require_evidence_string 3 "$LATEST" output_file
OUTPUT_FILE="$EVIDENCE_STRING"
if [ ! -f "$OUTPUT_FILE" ]; then
  OUTPUT_FILE_MISSING="$OUTPUT_FILE"
elif [ ! -s "$OUTPUT_FILE" ]; then
  OUTPUT_FILE_EMPTY="$OUTPUT_FILE"
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
#
# This one used to compare as a STRING (`[ "$EXIT_CODE" != "0" ]`), which
# happened to fail closed for `null` -- "null" != "0", so it rejected -- but
# only by accident, and it was wrong in the other direction: a corrupted
# `exit_code: "0"` (the JSON *string* "0") rendered identically through
# `jq -r` and passed. It is now validated as a real non-negative integer
# first, and only then compared arithmetically, so the check states its own
# requirement instead of depending on a coincidence of string rendering -- and
# cannot silently regress into a bare `-ne` on an unvalidated value later.
require_evidence_number 4 "$LATEST" exit_code
EXIT_CODE="$EVIDENCE_NUMBER"
EV_COMMAND=$(echo "$LATEST" | jq -r '.command')
if [ "$EXIT_CODE" -ne 0 ]; then
  gate_fail 4 "latest evidence shows exit code $EXIT_CODE (not 0) for command: $EV_COMMAND"
fi

# ---- Check 5: test requirements (only under --require-tests, the default). ----
#
# THE ORIGINAL FAIL-OPEN. `tests_total`/`tests_skipped` were read with a bare
# `jq -r` and compared with `-eq`/`-ne`; a stored `null` made `[` error, the
# `if` read that error as "condition not met", and an evidence record claiming
# a test run while recording no tests COMPLETED the task. Both are validated
# before either comparison now. Deliberately still read only in
# --require-tests mode: under --allow-no-tests the caller has explicitly
# opted out of the test requirement and these fields are not consulted at all,
# so there is nothing here to fail open.
if [ "$MODE" = "require-tests" ]; then
  require_evidence_number 5 "$LATEST" tests_total
  TESTS_TOTAL="$EVIDENCE_NUMBER"
  require_evidence_number 5 "$LATEST" tests_skipped
  TESTS_SKIPPED="$EVIDENCE_NUMBER"
  if [ "$TESTS_TOTAL" -eq 0 ]; then
    gate_fail 5 "no tests were run — tests_total is 0 (pass --allow-no-tests if this part genuinely has no test surface)."
  fi
  if [ "$TESTS_SKIPPED" -ne 0 ]; then
    gate_fail 5 "$TESTS_SKIPPED required tests were skipped."
  fi
fi

# ---- Check 6: evidence not stale. ----
#
# code_snapshot is the entire basis of this check, so an unusable one must
# refuse rather than be compared as the literal string "null" against a real
# snapshot -- that would reject, but with a message blaming changed code for
# what is actually a corrupt record.
require_evidence_string 6 "$LATEST" code_snapshot
RECORDED_SNAPSHOT="$EVIDENCE_STRING"
CURRENT_SNAPSHOT=$(compute_snapshot)

# WAS A STALENESS CHECK EVEN POSSIBLE? Settled BEFORE the comparison, because
# the comparison's result is meaningless without it.
#
# THE DEFECT THIS CLOSES -- see this file's header ("Check 6 outside a git
# repository") for the full statement and the reproduction. Short version: with
# no version control, compute_snapshot returns the constant $NO_GIT_SNAPSHOT on
# BOTH sides, the equality below matched no matter what the code did, and this
# gate printed a PASS naming a snapshot as though something had been verified.
# An unavailable input became a value meaning "condition satisfied", and the
# output asserted a check that could not run.
#
# What happens now, in each direction:
#   - Both sides real          -> compare as before; a mismatch is STALE and
#                                 REFUSES completion, exactly as it always did.
#   - Either side the placeholder -> NO comparison is possible. Do not report a
#                                 pass on this check, do not refuse completion
#                                 (a non-git project is legitimate); warn
#                                 explicitly, and carry STALENESS_VERIFIED=no
#                                 into both the final line and the durable
#                                 record. "Either", not "both", on purpose: a
#                                 real SHA on one side and the placeholder on
#                                 the other is still two things that cannot be
#                                 compared as code identities.
STALENESS_VERIFIED=yes
if [ "$RECORDED_SNAPSHOT" = "$NO_GIT_SNAPSHOT" ] || [ "$CURRENT_SNAPSHOT" = "$NO_GIT_SNAPSHOT" ]; then
  STALENESS_VERIFIED=no
  echo "*** CHECK 6 COULD NOT VERIFY STALENESS — THIS PROJECT IS NOT UNDER VERSION CONTROL ***"
  echo "  evidence recorded against snapshot: $RECORDED_SNAPSHOT"
  echo "  current snapshot:                   $CURRENT_SNAPSHOT"
  echo "  At least one of those is the placeholder '$NO_GIT_SNAPSHOT' — what compute_snapshot returns when it cannot identify the code at all — so the two cannot be compared as code identities, and when both are the placeholder they match for every possible state of the code. This check therefore did NOT pass; it could not run. ANY code drift since this evidence was recorded is UNDETECTED: the artifacts checked above were opened and read just now, but nothing here proves they are the same code the recorded command actually ran against."
  echo "  Completion is NOT refused for this — a project without version control is legitimate. The verdict is recorded durably as staleness_verified: false on this task's checking -> done history entry, so this completion can be told apart from a verified one later."
elif [ "$RECORDED_SNAPSHOT" != "$CURRENT_SNAPSHOT" ]; then
  gate_fail 6 "evidence is stale — recorded against snapshot $RECORDED_SNAPSHOT, current snapshot is $CURRENT_SNAPSHOT; code changed since verification, re-run checks."
fi

# ---- All checks passed. This is the only place in this script that calls
#      `task-state.sh complete`. See the header's "Disclosed residual race"
#      section for the gap between the checks above and this call. ----
#
# TWO DIFFERENT PASS LINES, because they are two different claims. The verified
# one names the snapshot that genuinely matched. The unverified one must not:
# printing "(snapshot: no-git-repository)" next to the word PASS is precisely
# how this read as "a snapshot check succeeded" when none was possible.
RECORDED_AT=$(echo "$LATEST" | jq -r '.recorded_at')
if [ "$STALENESS_VERIFIED" = "yes" ]; then
  echo "GATE PASS: task '$TASK_ID' — evidence recorded at $RECORDED_AT accepted (snapshot: $CURRENT_SNAPSHOT)"
else
  echo "GATE PASS (WITHOUT STALENESS VERIFICATION): task '$TASK_ID' — evidence recorded at $RECORDED_AT accepted on checks 1-5, but check 6 could NOT verify that the code is unchanged since then, because this project is not under version control. No snapshot comparison happened. Recording staleness_verified: false."
fi

# The verdict travels to the state file, not just to stdout -- see this file's
# header. `--staleness-verified` is always passed, in both directions: a gate
# run that stayed silent about it would be indistinguishable from a completion
# that never went through this gate at all.
COMPLETE_OUT=$(bash "$TASK_STATE" complete "$TASK_ID" --staleness-verified "$STALENESS_VERIFIED" 2>&1)
COMPLETE_RC=$?
echo "$COMPLETE_OUT"
if [ "$COMPLETE_RC" -ne 0 ]; then
  echo "GATE FAIL: all evidence checks passed, but task-state.sh complete itself rejected the transition (see message above) -- most likely the disclosed residual race: task state changed between this gate's checks and its final complete call." >&2
  exit 1
fi

exit 0
