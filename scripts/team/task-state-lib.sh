# shellcheck shell=bash
# Task-state guard/helper library — sourced by scripts/team/task-state.sh.
#
# This file holds the shared machinery that used to sit above the CLI
# dispatch in task-state.sh: the timestamp/snapshot helpers, the state-file
# bootstrap, the project-wide lock, the atomic write, and the require_*/
# read_* guard family every subcommand dispatches through. It is a LIBRARY:
# it defines functions plus two path variables and does nothing else at
# source time. In particular it must never `exit` while being sourced, which
# is why the two `command -v` dependency checks that DO exit deliberately
# stayed behind in task-state.sh's entry point -- there an exit means "this
# invocation cannot run"; here it would mean "the shell that sourced us dies".
#
# STATE_DIR/STATE live here rather than in the entry point so the library is
# self-contained: nearly every function below reads $STATE, and this code
# runs under `set -u`, where a caller that forgot to define them would fail
# with an unbound-variable error instead of anything diagnosable. Both are
# plain assignments with no side effect. The path stays RELATIVE on purpose:
# that relative path is what keeps state project-isolated (see the header of
# task-state.sh).
#
# Split out of task-state.sh with no behaviour change. Every function below
# is byte-identical to its previous definition there.
#
# SC2034 ("appears unused") is disabled file-wide, and only SC2034. The guard
# family below deliberately publishes its results in globals rather than on
# stdout -- NO_GIT_SNAPSHOT, ENTRY_STRING, RESTORE_STATE, TASK_PRESENCE,
# EA_RECORDED_AT, BUDGET_VALUE, OPEN_DECISION_ID, APPROVAL_VERDICT and
# APPROVAL_DETAIL -- precisely so the guards can be called
# DIRECTLY instead of inside `$( )`, where their `exit` would only ever kill a
# subshell (see the note above require_task_state, and the fail-open defects
# that note records). Every one of those globals IS read: by the CLI dispatch
# in task-state.sh. scripts/ci-checks.sh passes this file to shellcheck as a
# command-line argument of its own, so shellcheck analyses it standalone, with
# no way to see the readers -- the finding is structurally unresolvable here
# rather than a real defect. Disclosed cost, not hidden: a genuinely unused
# variable added to this file later would also go unreported by SC2034. The
# alternative, six per-line disables, would have meant editing six of the
# safety-critical guard functions during a refactor whose whole claim is that
# it edited none of them.
# shellcheck disable=SC2034

STATE_DIR=".claude/state"
STATE="$STATE_DIR/team-tasks.json"

now_iso() { date -Iseconds; }

# Code snapshot identity: short commit SHA when the tree is clean, or
# "uncommitted, base SHA X, diff Y" when it is dirty, where Y is a short
# prefix of a sha256 hash over the ACTUAL dirty content -- tracked changes
# (via `git diff HEAD`) plus the content of every untracked file -- not just
# a bare clean/dirty flag. A bare flag plus the base SHA is NOT enough: two
# materially different dirty trees off the same base commit would otherwise
# produce the identical snapshot string, so evidence recorded against one
# dirty state would be wrongly accepted as still-fresh after the tree
# changed again without a commit. This is an exact mirror of
# scripts/team/assign.sh's own compute_snapshot() -- kept as a second copy
# rather than sourced, since these are independent CLI entry points, but the
# logic must stay identical to assign.sh's (see docs/rebuild/DESIGN.md,
# "Verification contract": "A commit SHA alone is insufficient when
# uncommitted changes exist."). If you change this, change assign.sh's and
# complete-gate.sh's compute_snapshot to match.
#
# REQUIRES .claude/state/ to be excluded from `git status` in the target
# repo (this repo's own .gitignore already does this, as of Phase 1.2) --
# otherwise this script's own state writes get hashed into the snapshot and
# cause spurious "evidence is stale" failures in complete-gate.sh. See that
# script's compute_snapshot comment for the full explanation.
#
# *** THE "no-git-repository" RETURN IS NOT A CODE IDENTITY. READ THIS BEFORE
# *** COMPARING TWO SNAPSHOTS ANYWHERE.
# When there is no git repository (or git is broken/absent), this function
# CANNOT compute a code identity, and it returns the fixed string
# "no-git-repository" -- the same string every time, for every possible state of
# the code. Two such values comparing EQUAL therefore proves NOTHING about the
# code: rewrite every file in the directory and the two snapshots still match.
# Any comparison that treats that match as "the code is unchanged" is claiming a
# check it did not perform, which is this project's whole defect class (an
# unavailable input becoming a value that means "condition satisfied") wearing a
# different hat. This is a DELIBERATE degradation, not an oversight -- a
# non-git project is legitimate and must still be able to pause, resume and
# complete work -- but every caller that compares snapshots must detect this
# value FIRST and say plainly that nothing was verified. Compare against
# $NO_GIT_SNAPSHOT below rather than retyping the literal.
# The two callers in this file that compare snapshots, both handled:
#   - `resume`'s CODE CHECK          (search "CODE CHECK", ~line 2160)
#   - complete-gate.sh's check 6     (its own copy of this note is above its
#                                     compute_snapshot, and its check 6 says so
#                                     in the GATE PASS line and records
#                                     staleness_verified in the state file)
# This note lives ABOVE the function rather than inside it on purpose: the three
# copies of compute_snapshot's BODY (here, assign.sh, complete-gate.sh) must
# stay byte-for-byte identical, while these preamble comments are already
# per-file. Do not move it into the body.
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
# to assign.sh's and complete-gate.sh's copies -- so the literal stays inline
# there) purely so the comparison sites below cannot drift from it by a typo. A
# snapshot equal to this is an ABSENCE of information, never a code identity;
# see the note above compute_snapshot. complete-gate.sh declares the same
# constant, with the same value, for the same reason.
NO_GIT_SNAPSHOT="no-git-repository"

# warn_if_state_not_gitignored -- Part 1.6. Prints ONE advisory warning to
# stderr (never fails the run) if the current directory is a git repository
# AND .claude/state/ is not excluded from `git status` in it. This is purely
# advisory: it must never block a legitimate record-evidence run, so it never
# affects this script's exit code.
#
# The risk it names: compute_snapshot() above (and complete-gate.sh's
# identical copy) hashes `git status --porcelain` / `git diff HEAD` output to
# build the dirty-tree code_snapshot identity. If .claude/state/ is not
# gitignored, this script's own bookkeeping writes to
# .claude/state/team-tasks.json (including the very evidence-write this call
# is about to make) show up as tracked/untracked changes and get hashed into
# that snapshot too -- so the snapshot recorded here at evidence time and the
# snapshot recomputed later at gate time can differ EVEN THOUGH NO REAL CODE
# CHANGED, causing complete-gate.sh's check 6 to reject genuinely-fresh
# evidence as stale. See compute_snapshot()'s own comment above and
# complete-gate.sh's identical copy for the fuller explanation.
#
# "one-time-per-run": guarded by _STATE_GITIGNORE_WARNED so repeated calls in
# one script invocation only ever print once (record-evidence, the only
# caller today, calls this once, but the guard keeps that safe if that ever
# changes). Keep this function's detection logic and wording identical to
# complete-gate.sh's copy.
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

# is_absolute_path <path> -- true if <path> is already absolute. Covers both
# POSIX/MSYS-style ("/..." ) and Windows drive-letter style ("C:/..." or
# "C:\...", realistic input on this project's primary platform, Git Bash on
# Windows -- see assign.sh's own comment on colon-containing skill paths for
# the same platform reality).
is_absolute_path() {
  case "$1" in
    /*) return 0 ;;
    [A-Za-z]:[/\\]*) return 0 ;;
    *) return 1 ;;
  esac
}

# resolve_path <path> <base-dir> -- returns an absolute path. If <path> is
# already absolute, returns it unchanged; otherwise joins it onto <base-dir>
# (which must itself already be absolute -- callers resolve base-dir first).
# Deliberately does NOT use `realpath`: that's a GNU coreutils extension not
# guaranteed present in every environment this needs to run in (this repo's
# other path handling, e.g. assign.sh's and complete-gate.sh's `HERE="$(cd
# "$(dirname "$0")" && pwd)"`, resolves absolute paths via `cd ... && pwd`
# rather than `realpath` for the same portability reason). Also deliberately
# does NOT require <path> to exist on disk and does NOT collapse "." or ".."
# segments -- a claimed artifact may not exist yet (recording is not
# judging; see the ghost-artifact regression test), and any "." / ".."
# segments left in a joined path are resolved correctly by the OS the same
# way for `[ -f ]` / `[ -s ]` as for any other path, so textual collapsing
# would only be cosmetic, not load-bearing, and skipping it keeps this
# dependency-free.
resolve_path() {
  local path="$1" base="$2"
  if is_absolute_path "$path"; then
    echo "$path"
  else
    echo "${base%/}/$path"
  fi
}

# Comma-separated string -> compact JSON array. Empty string -> [].
csv_to_json_array() {
  local csv="$1"
  if [ -z "$csv" ]; then
    echo '[]'
    return
  fi
  jq -R -c 'split(",") | map(select(length > 0))' <<< "$csv"
}

# Create .claude/state/ and an empty team-tasks.json skeleton if neither exists
# yet. Only ever called from `create`, and only actually writes when the file
# is truly absent — it never fires against an already-populated state file, so
# it never counts as a mutation on an otherwise-rejected create.
ensure_state_file() {
  mkdir -p "$STATE_DIR"
  [ -f "$STATE" ] || echo '{"tasks":{}}' > "$STATE"
}

# Acquire an exclusive lock covering the whole duration of the current
# mutating command, released automatically when this process exits (normal
# exit, error exit, or signal). Two locking strategies:
#
#   1. flock, when present: opens $STATE_DIR/.team-tasks.lock on fd 9 and
#      blocks (up to LOCK_WAIT_SECS) until an exclusive lock is granted. The
#      lock is released the moment fd 9 closes, which happens automatically
#      when this script process exits — no explicit unlock needed.
#
#   2. Portable mkdir-based mutex, when flock is unavailable: `mkdir` is
#      atomic even on network/shared filesystems and works identically on
#      Linux CI runners and Windows Git Bash (unlike flock, which is not
#      reliably present under Git Bash). Only one concurrent caller can
#      successfully mkdir the lock directory; everyone else retries with a
#      short sleep until they succeed or LOCK_WAIT_SECS is exhausted. An EXIT
#      trap rmdir's the lock directory so it's released whenever this process
#      ends, including on Ctrl-C.
#
# Either way, the lock is held for the FULL read-modify-write sequence of the
# calling command (duplicate/dependency checks through atomic_update), not
# just the final write — that's what prevents the lost-update race where two
# concurrent invocations both read the same pre-update state and the second
# write silently clobbers the first.
LOCK_WAIT_SECS=30

acquire_lock() {
  mkdir -p "$STATE_DIR"
  if command -v flock >/dev/null 2>&1; then
    local lock_file="$STATE_DIR/.team-tasks.lock"
    exec 9>"$lock_file"
    if ! flock -w "$LOCK_WAIT_SECS" 9; then
      echo "ERROR: could not acquire task-state lock within ${LOCK_WAIT_SECS}s (another invocation may be stuck on: $lock_file)" >&2
      exit 1
    fi
  else
    local lock_dir="$STATE_DIR/.team-tasks.lockdir"
    local tries=0
    local max_tries=$((LOCK_WAIT_SECS * 5)) # 0.2s per try
    while ! mkdir "$lock_dir" 2>/dev/null; do
      tries=$((tries + 1))
      if [ "$tries" -ge "$max_tries" ]; then
        echo "ERROR: could not acquire task-state lock within ${LOCK_WAIT_SECS}s (another invocation may be stuck on: $lock_dir)" >&2
        exit 1
      fi
      sleep 0.2
    done
    trap 'rmdir "'"$lock_dir"'" 2>/dev/null' EXIT INT TERM
  fi
}

# Atomically replace $STATE with the result of running `jq "$@"` over it.
# The temp file is created inside $STATE_DIR so `mv` is a same-filesystem
# rename (not a copy), which is what makes the replacement atomic.
atomic_update() {
  local tmp
  tmp=$(mktemp "$STATE_DIR/.team-tasks.XXXXXX") || {
    echo "ERROR: failed to create temp file for atomic write" >&2
    exit 1
  }
  if ! jq "$@" "$STATE" > "$tmp"; then
    rm -f "$tmp"
    echo "ERROR: internal jq failure while updating state; state file left unchanged" >&2
    exit 1
  fi
  mv "$tmp" "$STATE"
}

# NOTE: the old `task_state_of` lived here. It has been replaced by
# read_task_state / require_task_state further down, in the "fail-closed reads
# of the stored task record" section -- see that section's comment for what its
# `.tasks[$id].state // "missing"` did to the needs-reassessment freeze.

# reassessment_required_error <id> <what-was-attempted> -- the single refusal
# message every subcommand uses when it is asked to act on a task whose
# repair-attempt budget is exhausted (state `needs-reassessment`). Shared
# rather than copy-pasted per subcommand for one reason: `needs-reassessment`
# is meant to be a real stop, and a real stop has to name its ONE exit
# consistently no matter which door the caller tried. Prints only -- the
# caller exits 1 itself, keeping the "rejected operations exit before any
# write" rule visible at each call site rather than hidden in here.
reassessment_required_error() {
  echo "ERROR: task '$1' is in state 'needs-reassessment', cannot $2 — its repair-attempt budget is exhausted. The ONLY way out of this state is: task-state.sh reassess $1 --specialist \"<who/what reassessed>\" --finding \"<what the reassessment concluded>\" [--additional-budget N]" >&2
}

# decision_required_error <id> <what-was-attempted> -- Part 2.3. The exact
# counterpart of reassessment_required_error above, for the OTHER real stop:
# state `awaiting-decision`, entered by `record-decision` when a material
# deviation needs a human answer. Same shape and same reason: a real stop must
# name its exits consistently no matter which door the caller tried. It has
# TWO exits rather than one (a decision can be answered yes or no), and both
# are named here -- an answer of "no" is still an answer, and a rejected
# decision must be recordable rather than left looking unanswered. Prints
# only; the caller exits 1 itself, keeping "rejected operations exit before
# any write" visible at each call site.
decision_required_error() {
  echo "ERROR: task '$1' is in state 'awaiting-decision', cannot $2 — a decision card is open and is waiting for a human answer. The ONLY ways out of this state are: task-state.sh record-approval $1 --decision <decision-id> --scope \"<what is approved>\" --approved-by \"<who/what approved>\" --deployment-impact yes|no [--conditions \"<text>\"], or task-state.sh record-rejection $1 --decision <decision-id> --rejected-by \"<who/what rejected>\" --reason \"<why>\"" >&2
}

# require_nonblank <flag-label> <value> <why-it-matters> -- guard for the free-
# text flags whose values are DURABLY RECORDED and later read by a human
# deciding whether an attempt or a reassessment was legitimate (`--reason`,
# `--hypothesis`, `--specialist`, `--finding`). A bare `[ -n ]` check is not
# enough: " " is non-empty but records exactly as much accountability as ""
# does, i.e. none, while looking like a supplied value in the stored record.
# Whitespace-only is therefore refused the same way empty is (exit 2, bad
# usage, before any write). "Whitespace" here is the shell's own [:space:]
# class, so tabs and newlines are caught too, not just spaces.
require_nonblank() {
  case "$2" in
    *[![:space:]]*) return 0 ;;
  esac
  echo "ERROR: $1 is required and must not be empty or whitespace-only ($3)" >&2
  exit 2
}

# --- fail-closed reads of the stored task record -----------------------------
#
# THE DEFECT CLASS THIS SECTION EXISTS FOR. Read this before "simplifying" any
# read below back into a `//` chain, a `[]?`, a bare `?`, a `2>/dev/null` on a
# jq whose output is then compared, or a `[ ... ]` test on a raw `jq -r`.
#
# The shape, precisely: A VALUE THAT CANNOT BE PARSED IS SILENTLY CONVERTED
# INTO A VALUE THAT MEANS "THE CONDITION WAS NOT MET", SO A SAFETY CHECK
# BECOMES A NO-OP INSTEAD OF AN ERROR. Three spellings of the same bug, all
# three of which were live in this file:
#
#   1. `//` swallows a stored null.  `.[-1].hypothesis // ""` turned a corrupt
#      previous hypothesis into "", and since an incoming hypothesis is already
#      validated non-blank, `"" == it` could never be true -- so the
#      changed-hypothesis control (this file's control #3, "cannot be
#      weakened") passed unconditionally, forever, and the same theory could be
#      retried without limit.
#   2. `[]?` / `?` swallow a type error.  `.depends_on[]?` on a `depends_on`
#      corrupted to a bare string yielded NO dependencies, so `start` reported
#      no unmet dependencies and dispatched a task whose dependency was still
#      `planned`. Same spelling, same silence, as `.artifacts[]?` in
#      complete-gate.sh. `map(select(.key == $key))` over an
#      `external_actions` array holding one non-object entry errored out
#      entirely, leaving an empty result: `check-external-action` then answered
#      NOT-RECORDED/PROCEED for a key that WAS recorded, and
#      `record-external-action` appended a duplicate. A false PROCEED there is
#      the duplicate-PR bug the whole mechanism exists to prevent.
#   3. an unvalidated value reaching `[ ... ]`.  `checkpoints | length` on a
#      `checkpoints` corrupted to `true` made jq error, leaving CP_COUNT empty;
#      `[ "" -eq 0 ]` then printed "integer expression expected" and returned
#      2, and an `if` reads ANY non-zero return as "condition not met", so
#      `resume`'s no-checkpoint guard was SKIPPED rather than failed.
#
# THE RULE: no value read out of the stored task record is compared, iterated,
# tested or used in arithmetic until it has been through one of the helpers in
# this section (or read_numeric_field / require_repair_counters below, which
# are the same discipline applied to the two numeric counters and predate it).
# They are the single implementation of "is this value usable at all", and they
# FAIL CLOSED.
#
# ABSENT vs PRESENT-BUT-WRONG is the distinction that makes this safe to apply
# everywhere, and it is inherited from read_numeric_field:
#
#   Key ABSENT entirely (or null where the schema has always written a value
#   only when it had one) -> may be a legitimate legacy record, from before the
#   field existed. Defaulting is correct WHERE A SAFE ABSENT-CASE GENUINELY
#   EXISTS, and each site below says in a comment which case it is in.
#   Key PRESENT but of the wrong type / null / empty where the schema always
#   writes content -> corruption or a partial or hand write. REFUSE: name the
#   task, the field and the offending value, and change nothing.
#
# WHY A SHARED FAMILY AND NOT PER-SITE CHECKS. This class has now been found
# three separate times, in a different field each time (the numeric counters,
# then the gate's evidence fields, then the three fields below), because the
# hardening lived in ONE helper that only covered NUMBERS. Strings and arrays
# had no equivalent, so every string and array read stayed ad-hoc and each new
# one re-introduced the defect. Extending the family is what stops the fourth.
#
# WHY THESE MUST NEVER BE CALLED INSIDE $( ). Their refusal path is `exit`. An
# `exit` inside a command substitution kills only the subshell and leaves the
# caller running on with an empty value -- which IS the silent-degradation
# class they exist to make impossible. They therefore publish their result in a
# global rather than printing it. Same convention, same reason, as
# read_numeric_field below and complete-gate.sh's require_evidence_* helpers.
#
# WHAT THIS SECTION COVERS, AND THE ONE INSTANCE THAT LIVES OUTSIDE IT.
# This section covers reads of the STATE FILE. The same defect class had one
# further instance in a read of the ENVIRONMENT, and it is now fixed -- but
# fixed elsewhere, so look for it there rather than here:
# compute_snapshot()'s `git rev-parse ... 2>/dev/null || echo ""` degrades a
# missing or broken git into the constant "no-git-repository". `resume` and
# complete-gate.sh's check 6 then compared that constant against itself, matched
# every time, and reported the code as unchanged / the evidence as fresh having
# verified nothing -- the same shape (an unavailable value becoming an answer
# that means "the condition is satisfied"), and worse than a skipped check
# because the OUTPUT asserted a check that could not run.
# THE FIX IS AT THE COMPARISON SITES, NOT IN compute_snapshot. The function
# still returns the placeholder (a non-git project is legitimate and must still
# be able to work), and its three copies here, in assign.sh and in
# complete-gate.sh stay byte-for-byte identical. What changed is that every
# caller comparing two snapshots now detects the placeholder FIRST, refuses to
# claim a verification it could not perform, and records that verdict durably:
#   - `resume`'s CODE CHECK -- third "NOT VERIFIED" outcome, and
#     `staleness_verified` on the resume history entry.
#   - complete-gate.sh check 6 -- warns, passes WITHOUT staleness verification
#     rather than reporting a snapshot match, and records staleness_verified
#     via `complete --staleness-verified no`.
# See the note above compute_snapshot for the rule, and $NO_GIT_SNAPSHOT for the
# constant every such comparison must test against.
#
# Two further reads are deliberately NOT hardened because they gate nothing:
# `status` and `list`. Both say so in a comment at their own site.
#
# WHY EVERY case STATEMENT BELOW HAS A CATCH-ALL. The verdict reads pass
# `2>/dev/null` so jq's own raw error text does not reach the user in place of
# a real message. That is only safe because an EMPTY verdict (jq failed
# outright) falls through to a `*)` branch that REFUSES. Never add a verdict
# read here without one.

# STATE_FAIL_EXIT -- the exit code every refusal in this section uses.
#
# It is 1 everywhere EXCEPT check-external-action, which sets it to 3 before
# its first read. There, exit 1 is the documented "CONFIRMED NOT RECORDED ->
# PROCEED WITH THE EXTERNAL ACTION" answer (see this file's header), so a
# corrupt record refusing with 1 would tell the caller to go ahead and open the
# PR -- turning a corruption refusal into the very duplicate this subcommand
# exists to prevent. 3 is that subcommand's UNDETERMINED / do-NOT-proceed code.
STATE_FAIL_EXIT=1

# state_field_fail <id> <field> <what-this-read-needs> <what-was-wrong>
# The single refusal message every helper below shares, so the wording and the
# "corruption, not 'condition not met'" framing cannot drift between them.
state_field_fail() {
  echo "ERROR: task '$1' has an unusable '$2' field in the state file (got: $4) — this read needs $3. Refusing this operation — nothing was changed." >&2
  echo "  A value that is PRESENT but cannot be parsed as that is treated as CORRUPTION, never as 'the condition was not met'. Silently degrading it is exactly how a guard becomes a no-op and fails OPEN, which is why this read is checked rather than defaulted." >&2
  echo "  The state file may have been hand-edited or partially written — only task-state.sh should write it." >&2
  exit "$STATE_FAIL_EXIT"
}

# read_task_state <id> -> TASK_STATE_VALUE ("missing" when the task genuinely
# does not exist), plus STATE_FILE_PRESENT for the caller's error wording.
#
# This replaces the old `task_state_of`, whose `.tasks[$id].state // "missing"`
# was the single most load-bearing unguarded read in the file: EVERY subcommand
# branches on its result. A `state` corrupted to an ARRAY rendered through
# `jq -r` as a multi-line JSON blob that matched none of the state names, which
# read as "this task is not in needs-reassessment" and let the record-*
# subcommands write to a task that is supposed to be frozen. The old
# `// "missing"` also could not tell a task that does not exist from a task
# whose record is a string, a number or null -- and for a non-object record jq
# errored out entirely, leaving the caller with an empty state that the
# follow-on comparison reported as `state ''`.
#
# ABSENT-CASE: a task id with no entry under .tasks (or no .tasks at all) is
# genuinely "missing" -- the normal not-found path, not corruption. Everything
# else that is not a non-empty JSON string is corruption.
TASK_STATE_VALUE=""
STATE_FILE_PRESENT=""
read_task_state() {
  local id="$1" verdict
  if [ ! -f "$STATE" ]; then
    STATE_FILE_PRESENT=""
    TASK_STATE_VALUE="missing"
    return 0
  fi
  STATE_FILE_PRESENT=1
  verdict=$(jq -r --arg id "$id" '
    if type != "object" then "bad:the state file root is not a JSON object — it is " + (type)
    elif (has("tasks") | not) or (.tasks == null) then "missing"
    elif (.tasks | type) != "object" then "bad:.tasks is not a JSON object — " + (.tasks | tojson | .[0:200])
    elif (.tasks | has($id) | not) then "missing"
    elif (.tasks[$id] | type) != "object" then "bad:the task record itself is not a JSON object — " + (.tasks[$id] | tojson | .[0:200])
    elif (.tasks[$id] | has("state") | not) then "bad:the task record carries no state field at all"
    elif (.tasks[$id].state | type) != "string" then "bad:" + (.tasks[$id].state | tojson | .[0:200])
    elif (.tasks[$id].state | length) == 0 then "bad:an empty string"
    else "ok:" + .tasks[$id].state
    end
  ' "$STATE" 2>/dev/null)

  case "$verdict" in
    missing) TASK_STATE_VALUE="missing"; return 0 ;;
    ok:*)    TASK_STATE_VALUE="${verdict#ok:}"; return 0 ;;
    bad:*)   state_field_fail "$id" "state" "a non-empty JSON string naming the task's current state" "${verdict#bad:}" ;;
    *)       state_field_fail "$id" "state" "a non-empty JSON string naming the task's current state" "unreadable — the state file could not be parsed as JSON" ;;
  esac
}

# require_task_state <id> -> TASK_STATE_VALUE. Refuses if the state file or the
# task is missing, or if the record is corrupt. MUST NOT be called in $( ).
#
# This replaces `CUR_STATE=$(require_task "$ID")`, which was a latent instance
# of the same class in a different disguise: require_task's not-found path is
# an `exit`, and inside a command substitution that killed only the subshell,
# so CUR_STATE became "" and the script carried on. Every caller happened to
# refuse anyway on the follow-on state comparison, but it refused with the
# nonsense message "task 'x' is in state ''" -- i.e. the not-found guard was
# already degrading into "the condition was not met" and only the next check
# saved it. Called directly (not in $( )), the exit propagates properly.
#
# It also validates `history` here, centrally: every mutating subcommand
# appends to that array, and this is the one place they all pass through.
# (read_task_state deliberately does NOT, so `start`'s per-dependency probe
# below does not refuse because some OTHER task's history is malformed.)
require_task_state() {
  read_task_state "$1"
  if [ "$TASK_STATE_VALUE" = "missing" ]; then
    if [ -z "$STATE_FILE_PRESENT" ]; then
      echo "ERROR: task '$1' not found (no tasks recorded yet)" >&2
    else
      echo "ERROR: task '$1' not found" >&2
    fi
    exit "$STATE_FAIL_EXIT"
  fi
  require_appendable_array "$1" "history"
}

# require_appendable_array <id> <field> -- the weakest of the array guards, for
# an array this script only ever APPENDS to and never reads a decision out of
# (history, and the record-* arrays). Absent or null is a legitimate legacy
# record and is accepted (the `// []` in the write itself starts one); a
# PRESENT non-array is refused here, by name, rather than being left to blow up
# inside atomic_update's jq as an anonymous "internal jq failure".
require_appendable_array() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "ok"
      elif ($t[$f] | type) != "array" then "bad:not a JSON array — " + ($t[$f] | tojson | .[0:200])
      else "ok"
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok)    return 0 ;;
    bad:*) state_field_fail "$id" "$field" "a JSON array (or no such key at all, on a legacy record)" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "a JSON array (or no such key at all, on a legacy record)" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_object_array <id> <field> -> ARRAY_LENGTH
#
# For every array this script reads a DECISION out of: attempts (the
# changed-hypothesis control and the monotonic-counter control),
# checkpoints (resume's next action), external_actions (idempotency).
#
# ABSENT-CASE: no such key, or null, is a legitimate legacy/never-written
# record and yields length 0 -- which is exactly what "no previous attempt" /
# "no checkpoint" / "nothing recorded yet" already mean, so the existing
# behaviour for those records is unchanged. PRESENT but not an array, or an
# array holding an entry that is not a JSON object, is corruption and refuses:
# `map(select(.key == ...))`, `.[-1].hypothesis` and friends all silently
# produce nothing on such an array, and "nothing" is precisely the answer that
# turns each of those guards off.
ARRAY_LENGTH=""
require_object_array() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "ok:0"
      elif ($t[$f] | type) != "array" then "bad:not a JSON array — " + ($t[$f] | tojson | .[0:200])
      else ([$t[$f][] | select(type != "object")]) as $bad
        | if ($bad | length) > 0
          then "bad:the array holds entries that are not JSON objects — " + ($bad | tojson | .[0:200])
          else "ok:" + ($t[$f] | length | tostring)
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      ARRAY_LENGTH="${verdict#ok:}"
      # Belt and braces, the same reason read_numeric_field does it: a length
      # that does not reach bash as a plain run of digits would be mangled by
      # the arithmetic comparisons the callers do on it.
      case "$ARRAY_LENGTH" in
        ''|*[!0-9]*)
          state_field_fail "$id" "$field" "an array whose length renders as a plain integer" "a length of '$ARRAY_LENGTH'" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "$field" "an array of JSON objects (or no such key at all, on a legacy record)" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an array of JSON objects (or no such key at all, on a legacy record)" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_string_array <id> <field> -> ARRAY_LENGTH
# Same contract for an array of plain strings. Used for depends_on, whose
# `[]?` iteration silently yielded nothing when the field was not iterable at
# all -- and "no dependencies" is the answer that lets `start` dispatch.
# ABSENT-CASE: no key / null means no dependencies, which is what a task
# created without --depends legitimately has.
require_string_array() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "ok:0"
      elif ($t[$f] | type) != "array" then "bad:not a JSON array — " + ($t[$f] | tojson | .[0:200])
      else ([$t[$f][] | select((type != "string") or (length == 0))]) as $bad
        | if ($bad | length) > 0
          then "bad:the array holds entries that are not non-empty strings — " + ($bad | tojson | .[0:200])
          else "ok:" + ($t[$f] | length | tostring)
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      ARRAY_LENGTH="${verdict#ok:}"
      case "$ARRAY_LENGTH" in
        ''|*[!0-9]*)
          state_field_fail "$id" "$field" "an array whose length renders as a plain integer" "a length of '$ARRAY_LENGTH'" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "$field" "an array of non-empty strings (or no such key at all, on a legacy record)" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an array of non-empty strings (or no such key at all, on a legacy record)" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_entry_string <id> <field> <index> <key> -> ENTRY_STRING
#
# The entry at <index> of <field> must be a JSON object carrying a NON-EMPTY
# STRING at <key>. There is deliberately no absent-case here: these are fields
# the writing subcommand has always written with content in the same atomic
# object as the entry itself (`fail` always writes hypothesis, `pause` always
# writes next_action and code_snapshot), so a missing or null one is as much a
# sign of a hand-edited record as a wrong-typed one. Call require_object_array
# on <field> first -- this assumes the array shape is settled and <index> is in
# range.
ENTRY_STRING=""
require_entry_string() {
  local id="$1" field="$2" index="$3" key="$4" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" --argjson i "$index" --arg k "$key" '
    (.tasks[$id][$f][$i]) as $e
    | if ($e | type) != "object" then "bad:entry \($i) is not a JSON object — " + ($e | tojson | .[0:200])
      elif ($e | has($k) | not) then "bad:entry \($i) carries no \"\($k)\" field at all"
      elif ($e[$k] | type) != "string" then "bad:entry \($i)'"'"'s \"\($k)\" is " + ($e[$k] | tojson | .[0:200])
      elif ($e[$k] | length) == 0 then "bad:entry \($i)'"'"'s \"\($k)\" is an empty string"
      else "ok:" + $e[$k]
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)  ENTRY_STRING="${verdict#ok:}"; return 0 ;;
    bad:*) state_field_fail "$id" "$field" "an entry carrying a non-empty string '$key'" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an entry carrying a non-empty string '$key'" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_entry_number <id> <field> <index> <key> -> ENTRY_NUMBER
# The same contract for a non-negative integer entry field (attempt_number).
ENTRY_NUMBER=""
require_entry_number() {
  local id="$1" field="$2" index="$3" key="$4" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" --argjson i "$index" --arg k "$key" '
    (.tasks[$id][$f][$i]) as $e
    | if ($e | type) != "object" then "bad:entry \($i) is not a JSON object — " + ($e | tojson | .[0:200])
      elif ($e | has($k) | not) then "bad:entry \($i) carries no \"\($k)\" field at all"
      else $e[$k] as $v
        | if ($v | type) == "number" and $v >= 0 and $v == ($v | floor)
          then "ok:" + ($v | tostring)
          else "bad:entry \($i)'"'"'s \"\($k)\" is " + ($v | tojson | .[0:200])
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      ENTRY_NUMBER="${verdict#ok:}"
      case "$ENTRY_NUMBER" in
        ''|*[!0-9]*)
          state_field_fail "$id" "$field" "an entry whose '$key' renders as a plain non-negative integer" "$ENTRY_NUMBER" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "$field" "an entry carrying a non-negative integer '$key'" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an entry carrying a non-negative integer '$key'" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_restorable_state <id> <field> -> RESTORE_STATE ("missing" when the
# field is absent or null, which is the caller's own "nothing to restore to"
# refusal, unchanged).
#
# For blocked_from and paused_from. This one is NOT merely a type check, and it
# is the most permissive read that was in this file: `unblock` restored
# whatever string it found, so a `blocked_from` hand-set to "done" moved the
# task straight to `done` -- past `checking`, past complete-gate.sh, past the
# entire verification contract, with `unblock` reporting success. `block` and
# `pause` only ever record planned/building/checking (they refuse every other
# source state), so restricting the restore target to exactly those three is
# behaviour-preserving for every honestly-written record and closes the
# completion bypass for every other one. A non-string, or a string naming any
# other state, is refused.
RESTORE_STATE=""
require_restorable_state() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "missing"
      elif ($t[$f] | type) != "string" then "bad:" + ($t[$f] | tojson | .[0:200])
      elif ($t[$f] | length) == 0 then "bad:an empty string"
      elif ((["planned", "building", "checking"] | index($t[$f])) == null)
        then "bad:the string \"\($t[$f])\", which is not a state \($f) is ever written with (only planned, building or checking are)"
      else "ok:" + $t[$f]
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    missing) RESTORE_STATE="missing"; return 0 ;;
    ok:*)    RESTORE_STATE="${verdict#ok:}"; return 0 ;;
    bad:*)   state_field_fail "$id" "$field" "one of the states it is ever recorded with: planned, building or checking" "${verdict#bad:}" ;;
    *)       state_field_fail "$id" "$field" "one of the states it is ever recorded with: planned, building or checking" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# --- numeric state-field reads on the mutation paths -------------------------
#
# read_numeric_field <id> <field-name> <default-when-absent>
#   Resolves ONE numeric field of a task and leaves the result in the global
#   NUMERIC_FIELD_VALUE. It does NOT print the value and MUST NOT be called in
#   a command substitution: its refusal path is `exit 1`, and an `exit` inside
#   `$( )` only kills the subshell, leaving the caller running on with an
#   empty value -- which for these fields is precisely the silent-reset class
#   of bug this function exists to make impossible.
#
#   THE DISTINCTION THIS FUNCTION EXISTS FOR -- "absent" and "present but
#   invalid" are genuinely different and must behave differently:
#
#     Key ABSENT entirely  -> a legitimate pre-2.2 legacy record (tasks
#                             created before `attempts_used` / `budget`
#                             existed genuinely have no such key). Defaulting
#                             is correct, and stays correct.
#     Key PRESENT but null, non-numeric, fractional or negative
#                          -> corruption or a partial/hand write. FAIL CLOSED:
#                             refuse, name the task, the field and the
#                             offending value, and change nothing.
#
#   Why this is not done with jq's `//` default operator: `//` treats `null`
#   (and `false`) as ABSENT, so `.attempts_used // 0` collapses a *stored*
#   null to 0 before any guard can see it. A validator downstream of `//`
#   then only ever validates the already-defaulted value and structurally
#   cannot catch the corruption -- it reports a healthy "0" for a task that
#   really is at attempt 2, the counter goes BACKWARDS on the next write, and
#   the attempts array ends up with a duplicate attempt_number. The
#   presence test therefore has to be `has(...)`, and the validation has to
#   run against the RAW value, before any defaulting. Do not "simplify" this
#   back into a `//` chain.
NUMERIC_FIELD_VALUE=""
read_numeric_field() {
  local id="$1" field="$2" default="$3" verdict invalid_desc
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | type) != "object" then "shape:" + ($t | tojson | .[0:200])
      elif ($t | has($f) | not) then "absent"
      else ($t[$f]) as $v
        | if ($v | type) == "number" and $v >= 0 and $v == ($v | floor)
          then "ok:" + ($v | tostring)
          else "bad:" + ($v | tojson) end
      end
  ' "$STATE" 2>/dev/null)

  case "$verdict" in
    shape:*)
      # The task record is not a JSON object at all, so there is no field here
      # to be absent OR invalid. Refuse via the shared message rather than
      # falling through to the field-specific one below, which would blame the
      # field for a record-level problem. (read_task_state normally catches
      # this first; this is the belt to its braces, and it is what stops an
      # empty verdict from a jq that errored out being read as "not absent,
      # not ok" and landing on a message with an empty offending value.)
      state_field_fail "$id" "$field" "a task record that is a JSON object" "${verdict#shape:}"
      ;;
    absent)
      NUMERIC_FIELD_VALUE="$default"
      return 0
      ;;
    ok:*)
      NUMERIC_FIELD_VALUE="${verdict#ok:}"
      # Belt and braces: a value can satisfy jq's numeric checks above and
      # still not render as a plain run of digits by the time it reaches bash
      # -- exponent form ("1E+30"), or a decimal spelling of a whole number
      # ("0.0"), depending on the jq version. Bash arithmetic would mangle
      # either, so anything that is not plain digits here is refused too.
      case "$NUMERIC_FIELD_VALUE" in
        ''|*[!0-9]*)
          echo "ERROR: task '$id' has a '$field' field that is numeric in the state file but does not render as a plain non-negative integer (got: $NUMERIC_FIELD_VALUE); it cannot be used as an attempt counter or budget. Refusing this operation — nothing was changed." >&2
          exit 1
          ;;
      esac
      return 0
      ;;
    bad:*)
      invalid_desc="${verdict#bad:}"
      ;;
    *)
      # EXPLICIT CATCH-ALL, per this section's own rule ("why every case
      # statement below has a catch-all"). This branch is reached when the
      # verdict is EMPTY or is none of the four words this read can produce --
      # i.e. jq itself failed, and `2>/dev/null` swallowed its error text. It
      # already exited 1 (safe) before this branch existed, because an
      # unmatched `bad:*` prefix strip left the message intact -- but it
      # reported the offending value as a BLANK "(got: )", which reads like a
      # field that is present and empty rather than a state file that could not
      # be parsed at all. Same refusal, honest description.
      invalid_desc="unreadable — the state file could not be parsed as JSON, so no verdict was produced for this field"
      ;;
  esac

  echo "ERROR: task '$id' has an invalid '$field' field in the state file (got: $invalid_desc); it is PRESENT but is not a non-negative integer, so it cannot be a trustworthy attempt counter or budget. Refusing this operation — nothing was changed." >&2
  echo "  A field that is present-but-invalid is treated as CORRUPTION, not as 'unset': defaulting it to 0 here would silently reset a real attempt counter and let the same attempt_number be issued twice. (A genuinely legacy record, created before this field existed, has no '$field' key at all and is still accepted.)" >&2
  echo "  The state file may have been hand-edited or partially written — only task-state.sh should write it." >&2
  exit 1
}

# require_task_presence <id> -> TASK_PRESENCE (yes|no). Answers ONLY "does an
# entry exist under this id", which is what `create`'s duplicate-id guard and
# its dependency-exists guard each need -- neither of them can use
# read_task_state, because a record that exists but is corrupt must still count
# as EXISTING for the duplicate guard (refusing to overwrite it is the safe
# answer) rather than being reported as usable.
#
# The read it replaces was `.tasks[$id] // empty`, and `//` treats a stored
# `null` (and `false`) as absent: a task whose record had been corrupted to
# null read as "does not exist", so `create` silently REPLACED it. has() cannot
# be fooled that way. A `.tasks` that is not an object at all used to make jq
# error out and yield an empty answer, which read as "no such task" too; it is
# refused here instead.
TASK_PRESENCE=""
require_task_presence() {
  local id="$1" probe
  probe=$(jq -r --arg id "$id" '
    if type != "object" then "bad:the state file root is not a JSON object"
    elif (has("tasks") | not) or (.tasks == null) then "no"
    elif (.tasks | type) != "object" then "bad:.tasks is not a JSON object — " + (.tasks | tojson | .[0:200])
    elif (.tasks | has($id)) then "yes"
    else "no"
    end
  ' "$STATE" 2>/dev/null)
  case "$probe" in
    yes|no) TASK_PRESENCE="$probe"; return 0 ;;
    bad:*)  state_field_fail "$id" "tasks" "a JSON object mapping task ids to task records" "${probe#bad:}" ;;
    *)      state_field_fail "$id" "tasks" "a JSON object mapping task ids to task records" "unreadable — the state file could not be parsed as JSON" ;;
  esac
}

# require_external_action <id> <key> -> EA_RECORDED_AT ("" when the key is NOT
# recorded for this task).
#
# THE ONE implementation of the already-recorded lookup, shared by
# record-external-action and check-external-action. It was previously the same
# jq expression copy-pasted into both, and both copies had the same hole:
# `map(select(.key == $key))` over an external_actions array containing a
# single non-object entry makes jq abort the whole program ("Cannot index
# string with string"), leaving an EMPTY result -- which both call sites read
# as "this key is not recorded". record-external-action then appended a
# DUPLICATE entry, and check-external-action answered NOT-RECORDED / PROCEED
# for a key that was in fact already recorded. A false PROCEED there is
# precisely the duplicate-PR failure the external-action mechanism exists to
# prevent, so both directions of this read now refuse instead.
#
# Note the two DELIBERATE defaults here, so a later reader can tell them from
# an unhardened read: an absent/null external_actions array legitimately means
# "nothing recorded yet" (require_object_array's absent-case), and a matched
# entry whose recorded_at is unusable still counts as RECORDED, falling back to
# the literal "unknown time" purely for the message. That fallback is
# display-only -- it can never turn a recorded key into an unrecorded one,
# which is the only direction that could cause a duplicate.
EA_RECORDED_AT=""
require_external_action() {
  local id="$1" key="$2" verdict
  require_object_array "$id" "external_actions"
  verdict=$(jq -r --arg id "$id" --arg key "$key" '
    ((.tasks[$id].external_actions) // []) as $a
    | [ $a[] | select((has("key") | not)
                      or ((.key | type) != "string")
                      or ((.key | length) == 0)) ] as $bad
    | if ($bad | length) > 0
      then "bad:entries carrying no usable \"key\" — " + ($bad | tojson | .[0:200])
      else [ $a[] | select(.key == $key) ] as $hit
        | if ($hit | length) == 0 then "no"
          else ($hit[0].recorded_at) as $t
            | if ($t | type) == "string" and ($t | length) > 0
              then "yes:" + $t
              else "yes:unknown time"
              end
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    no)     EA_RECORDED_AT=""; return 0 ;;
    yes:*)  EA_RECORDED_AT="${verdict#yes:}"; return 0 ;;
    bad:*)  state_field_fail "$id" "external_actions" "every entry to carry a non-empty string idempotency key" "${verdict#bad:}" ;;
    *)      state_field_fail "$id" "external_actions" "every entry to carry a non-empty string idempotency key" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_max_attempt_number <id> -> MAX_ATTEMPT_NUMBER (0 when the task has no
# recorded attempts at all). Call require_object_array "$id" "attempts" first:
# this assumes the array is already known to be absent, empty, or made of
# objects, and it settles the remaining question -- that EVERY entry carries a
# usable attempt_number, so the maximum it returns really is the high-water
# mark of the audit trail and not just the maximum of the entries that happened
# to be readable.
MAX_ATTEMPT_NUMBER=""
require_max_attempt_number() {
  local id="$1" verdict
  verdict=$(jq -r --arg id "$id" '
    (.tasks[$id].attempts) as $a
    | (if ($a == null) then []
       else [ $a[] | select((has("attempt_number") | not)
                            or (.attempt_number | type) != "number"
                            or (.attempt_number < 0)
                            or (.attempt_number != (.attempt_number | floor))) ]
       end) as $bad
    | if ($bad | length) > 0
      then "bad:entries with no usable attempt_number — " + ($bad | tojson | .[0:200])
      elif ($a == null) or ($a | length) == 0 then "ok:0"
      else "ok:" + ([$a[].attempt_number] | max | tostring)
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      MAX_ATTEMPT_NUMBER="${verdict#ok:}"
      case "$MAX_ATTEMPT_NUMBER" in
        ''|*[!0-9]*)
          state_field_fail "$id" "attempts" "a highest attempt_number that renders as a plain integer" "$MAX_ATTEMPT_NUMBER" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "attempts" "every entry to carry a non-negative integer attempt_number" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "attempts" "every entry to carry a non-negative integer attempt_number" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_transition_count <id> <to-state> -> TRANSITION_COUNT
#
# "How many times has this task transitioned INTO <to-state>?", answered off the
# task's own history array. Used by `reassess --resume-state checking`, whose
# audit-integrity rule needs "has this task ever actually reached checking?".
#
# WHY THIS EXISTS AS A FAMILY MEMBER RATHER THAN A ONE-OFF jq AT THE CALL SITE.
# It was a one-off, and that was the whole problem: it was the last
# decision-bearing read in this file still spelled out inline, with its own
# hand-written `case`, its own `2>/dev/null`, and its own idea of what a
# malformed history means. It happened to fail closed -- but "happened to" is
# exactly the property this family exists to replace with "by construction",
# and a lone hand-rolled guard is where the next instance of the defect class
# gets introduced by someone copying the nearest example. There is now no
# decision-bearing state read in this file outside the family.
#
# Two things the inline version did that this deliberately does NOT do:
#   1. `select(type == "object")` SKIPPED non-object history entries, so a
#      history holding garbage counted as "no checking transition" -- an
#      unreadable value quietly becoming an answer, the exact shape of the
#      defect class. require_object_array settles that first and REFUSES.
#   2. It read `to` with no type check at all. Every history entry this script
#      has ever written carries a non-empty string `to` (`create` writes
#      to:"planned", every transition writes its destination), so an entry
#      without one is a hand-edit, not a legacy record, and is refused by name.
# ABSENT-CASE: no history key at all, or null, is require_object_array's
# legitimate legacy case and yields 0 -- which is what "this task has never
# reached that state" already means, so the caller's behaviour is unchanged for
# every honestly-written record.
TRANSITION_COUNT=""
require_transition_count() {
  local id="$1" to_state="$2" verdict
  require_object_array "$id" "history"
  verdict=$(jq -r --arg id "$id" --arg to "$to_state" '
    ((.tasks[$id].history) // []) as $h
    | [ $h[] | select((has("to") | not)
                      or ((.to | type) != "string")
                      or ((.to | length) == 0)) ] as $bad
    | if ($bad | length) > 0
      then "bad:entries carrying no usable \"to\" state — " + ($bad | tojson | .[0:200])
      else "ok:" + ([ $h[] | select(.to == $to) ] | length | tostring)
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      TRANSITION_COUNT="${verdict#ok:}"
      case "$TRANSITION_COUNT" in
        ''|*[!0-9]*)
          state_field_fail "$id" "history" "a count of transitions into '$to_state' that renders as a plain integer" "a count of '$TRANSITION_COUNT'" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "history" "every entry to record the state it transitioned TO, so 'has this task ever reached $to_state?' can be answered" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "history" "every entry to record the state it transitioned TO, so 'has this task ever reached $to_state?' can be answered" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_repair_counters <id> -- resolve BOTH numeric fields the bounded-repair
# paths do arithmetic on, into the globals BUDGET_VALUE and
# ATTEMPTS_USED_VALUE. `fail` and `reassess` both need exactly this, identically;
# it lives here as ONE implementation rather than two copies because the
# duplicated version is what let the guard drift out of step with the read it
# was supposed to be guarding in the first place.
#
# Beyond the per-field validation, this also enforces the cross-field
# invariant that makes `attempts_used` an audit counter rather than a hint:
# attempts_used must be at least the highest attempt_number already recorded
# in the task's own `attempts` array. A counter that has fallen BEHIND its own
# audit trail would re-issue an attempt_number that is already in use, so it
# is refused here rather than written. This is what closes the "delete the key
# on a task that has real history" door, which `has()` alone cannot tell apart
# from a genuine legacy record: a legacy record has no attempts either, so it
# passes; a stripped record with recorded attempts does not.
BUDGET_VALUE=""
ATTEMPTS_USED_VALUE=""
require_repair_counters() {
  local id="$1" max_recorded

  read_numeric_field "$id" "budget" 2
  BUDGET_VALUE="$NUMERIC_FIELD_VALUE"
  read_numeric_field "$id" "attempts_used" 0
  ATTEMPTS_USED_VALUE="$NUMERIC_FIELD_VALUE"

  # THE ATTEMPTS ARRAY IS SETTLED BEFORE IT IS SUMMARISED. The read this
  # replaces was `[ (.attempts // []) | .[]? | .attempt_number? | numbers ]`,
  # with a `case` that degraded anything unreadable to 0 -- and it carried a
  # comment calling that "defense in depth". It was the opposite. Every one of
  # `// []`, `.[]?`, `.attempt_number?`, `numbers` and the degrade-to-0 turns
  # an unreadable attempts array into "no recorded attempts", and "no recorded
  # attempts" is the exact answer that switches this guard OFF. Corrupting the
  # entries to strings and deleting attempts_used therefore reset the counter
  # to 0 and re-issued attempt_number 1 -- reopening, by another door, the very
  # monotonic-counter hole (control #1) this function was added to close.
  # Now: absent/null -> genuinely no history (a legacy record, still accepted);
  # present but not an array of objects each carrying a non-negative integer
  # attempt_number -> corruption, refused by name.
  require_object_array "$id" "attempts"
  require_max_attempt_number "$id"
  max_recorded="$MAX_ATTEMPT_NUMBER"

  if [ "$ATTEMPTS_USED_VALUE" -lt "$max_recorded" ]; then
    echo "ERROR: task '$id' has an 'attempts_used' counter ($ATTEMPTS_USED_VALUE) that is BEHIND its own recorded attempt history (highest recorded attempt_number: $max_recorded). Refusing this operation — nothing was changed." >&2
    echo "  attempts_used is strictly monotonic by design; a counter below the audit trail would re-issue attempt_number $ATTEMPTS_USED_VALUE and durably corrupt the attempts array with a duplicate. The state file may have been hand-edited or partially written — only task-state.sh should write it." >&2
    exit 1
  fi
}

# --- Part 2.3: decision cards and scoped approval records --------------------

# require_open_decision <id> -> OPEN_DECISION_ID
#
# Resolves "which decision card is this task currently waiting on?" -- the
# read `record-approval` and `record-rejection` both branch on. Call it only
# after the caller has confirmed the task is in state `awaiting-decision`.
#
# A task in `awaiting-decision` was put there by `record-decision`, which
# ALWAYS appends a decision entry carrying a non-empty `decision_id` and a
# `status` of exactly "open", in the same atomic object as the state change.
# So there is no legitimate absent-case here at all: an empty `decisions`
# array, a last entry with no usable `decision_id`, or a last entry whose
# `status` is anything other than "open" on a task that IS in
# `awaiting-decision` is an inconsistent record, not a legacy one. Each is
# refused by name rather than defaulted -- defaulting any of them would let a
# resolution be written against a card that is not open, which is the same
# "unreadable value becomes permission" shape the whole family exists for.
#
# Only the LAST entry is consulted because only one decision can ever be open
# at a time: `record-decision` is refused from `awaiting-decision`, so a second
# card cannot be raised while the first is unanswered.
OPEN_DECISION_ID=""
require_open_decision() {
  local id="$1"
  require_object_array "$id" "decisions"
  if [ "$ARRAY_LENGTH" -eq 0 ]; then
    echo "ERROR: task '$id' is in state 'awaiting-decision' but its 'decisions' array is empty, so there is no decision card to answer. Refusing this operation — nothing was changed." >&2
    echo "  Only 'record-decision' puts a task into this state, and it always appends the card in the same atomic write as the state change, so this combination cannot have been produced by task-state.sh. The state file may have been hand-edited or partially written." >&2
    exit "$STATE_FAIL_EXIT"
  fi
  require_entry_string "$id" "decisions" -1 "decision_id"
  OPEN_DECISION_ID="$ENTRY_STRING"
  require_entry_string "$id" "decisions" -1 "status"
  if [ "$ENTRY_STRING" != "open" ]; then
    echo "ERROR: task '$id' is in state 'awaiting-decision' but its latest decision card '$OPEN_DECISION_ID' has a 'status' of '$ENTRY_STRING' rather than 'open'. Refusing this operation — nothing was changed." >&2
    echo "  A card that is already answered cannot be answered again, and a task frozen on an answered card is an inconsistent record. The state file may have been hand-edited or partially written — only task-state.sh should write it." >&2
    exit "$STATE_FAIL_EXIT"
  fi
}

# require_approval_verdict <id> <action-scope> <action-deployment: yes|no>
#                          <current-revision> -> APPROVAL_VERDICT + APPROVAL_DETAIL
#
# THE SAFETY-CRITICAL READ OF PART 2.3. It answers, for `check-approval`,
# "does a recorded approval cover the action the caller is about to take?" --
# and the ONLY verdict that may ever mean "yes" is the literal word `ok`.
# Every other outcome, including every failure of the read itself, lands on a
# verdict the caller turns into a NONZERO exit. NONZERO NEVER MEANS APPROVED.
#
# APPROVAL_VERDICT is the decision and is one of exactly six words:
#   ok            -- an approval covers this action's scope, revision and
#                    deployment impact.
#   none          -- this task has no approval records at all.
#   scope         -- approvals exist, none of their scopes matches the action.
#   deployment    -- an approval matches the scope, but the action carries
#                    deployment impact and that approval did not.
#   revision      -- an approval matches the scope, but the code has moved
#                    since it was granted.
#   unverifiable  -- an approval matches the scope, but the revision could not
#                    be established on one side or the other (see below).
# APPROVAL_DETAIL is everything after the first newline of the jq output and is
# DISPLAY ONLY -- pre-formatted human-readable lines the caller prints. Nothing
# branches on it. That split is the point: the decision is one word, validated
# against a closed set with a catch-all that REFUSES, and all the free text that
# could contain anything at all is structurally unable to influence it.
#
# WHICH APPROVAL WINS. Approvals are scanned most-recent-first. If ANY of them
# fully covers the action the verdict is `ok` (an older approval that still
# holds is still an approval). If none does, the verdict reported is the one
# from the MOST RECENT approval whose SCOPE matched -- the nearest miss, which
# is the one whose failure a human actually needs to hear about. Per-approval
# the order is scope, then deployment, then revision: DESIGN.md's "a merge
# approval is not permission for an unexpected deployment" is a statement about
# what was approved, which is more fundamental than whether it has since gone
# stale, so it is reported first when both are true.
#
# SCOPE MATCHING IS A NORMALISED EXACT MATCH -- DISCLOSED LIMIT, NOT AN
# OVERSIGHT. Normalisation is the same one `fail`'s changed-hypothesis control
# uses (case-folded, trimmed, internal whitespace collapsed), so re-typing an
# approved action in different case or spacing still matches. Anything else
# does NOT match. In particular this is deliberately NOT a substring or prefix
# test: under a prefix test an approval scoped "merge PR 12" would cover
# "merge PR 12 and deploy to production", which is precisely the escalation
# DESIGN.md forbids. The cost is that a caller who paraphrases the action gets
# told it is not covered and has to ask again; that is the safe direction, and
# it is the direction this whole subcommand is built to fail in.
#
# THE NON-GIT CASE, DECIDED DELIBERATELY. compute_snapshot() returns the fixed
# string $NO_GIT_SNAPSHOT when it cannot identify the code at all, and two such
# values compare EQUAL for every possible state of the code (see the note above
# compute_snapshot). Treating that match as "the revision is unchanged" would be
# this project's entire defect class -- an unavailable input becoming a value
# that means "the condition is satisfied" -- in the one place where the
# condition being satisfied authorises an action. So a placeholder on EITHER
# side yields `unverifiable`, which the caller reports as its own nonzero exit.
# It is deliberately NOT folded into `revision`: "the code moved" and "we could
# not tell whether the code moved" are different claims and a human answering
# the question needs to know which one they are looking at. This does mean that
# in a project with no version control check-approval can never answer `ok`.
# That is the intended degradation: it degrades to "ask a human every time",
# i.e. to the behaviour before this mechanism existed, never to "proceed".
# `resume` handles the same placeholder by warning rather than refusing, and the
# difference is not an inconsistency: `resume` is reporting on work that is
# resuming either way, while `check-approval` exists solely to answer "may I?",
# and the honest answer to "may I?" when you cannot tell is no.
#
# WHAT A VALID APPROVAL RECORD MUST CARRY. decision_id, scope, target_revision
# and approved_by as non-empty strings, deployment_impact as a real JSON
# boolean, and conditions as either absent/null or a string. `record-approval`
# writes all of them, validated, in one atomic object, so a record missing or
# mistyping any of them is corruption and is refused by name. Note in
# particular that deployment_impact is checked for the BOOLEAN type rather than
# for truthiness: a deployment_impact of the string "no", or of null, must not
# be read as `false` and quietly authorise a deployment.
# ABSENT-CASE: no `approvals` key at all, or null, is require_object_array's
# legitimate legacy/never-approved record and yields the `none` verdict, which
# is a refusal -- so the absent case is safe here as well as legitimate.
#
# ONE CORRUPT ENTRY REFUSES EVERY SCOPE ON THAT TASK -- DISCLOSED LIMIT, NOT AN
# OVERSIGHT. The `$bad` selector below runs over the WHOLE approvals array
# before any scope matching, so a single malformed record makes check-approval
# refuse every action on that task, including scopes that a perfectly good
# approval sitting beside it does cover; that is the same fail-closed
# whole-array validation `attempts`, `checkpoints` and `external_actions`
# already use, and narrowing it to "only the entry whose scope you asked about"
# would leave the untrusted remainder unexamined in the one read whose answer is
# permission. The cost is availability -- one bad entry blocks every approval
# check on that task until the record is repaired -- and that is the cost being
# chosen here, not one being overlooked.
APPROVAL_VERDICT=""
APPROVAL_DETAIL=""
require_approval_verdict() {
  local id="$1" scope="$2" deployment="$3" current_rev="$4" raw
  require_object_array "$id" "approvals"
  raw=$(jq -r --arg id "$id" --arg scope "$scope" --arg dep "$deployment" \
    --arg cur "$current_rev" --arg nogit "$NO_GIT_SNAPSHOT" '
    def norm: ascii_downcase | gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; "");
    ((.tasks[$id].approvals) // []) as $a
    | [ $a[] | select(
          ((has("decision_id") | not) or ((.decision_id | type) != "string") or ((.decision_id | length) == 0))
          or ((has("scope") | not) or ((.scope | type) != "string") or ((.scope | length) == 0))
          or ((has("target_revision") | not) or ((.target_revision | type) != "string") or ((.target_revision | length) == 0))
          or ((has("approved_by") | not) or ((.approved_by | type) != "string") or ((.approved_by | length) == 0))
          or ((has("deployment_impact") | not) or ((.deployment_impact | type) != "boolean"))
          or (has("conditions") and (.conditions != null) and ((.conditions | type) != "string"))
      ) ] as $bad
    | if ($bad | length) > 0
      then "bad:entries that do not carry a usable decision_id / scope / target_revision / approved_by / deployment_impact / conditions — " + ($bad | tojson | .[0:200])
      elif ($a | length) == 0 then "none"
      else ([ $a[] | select((.scope | norm) == ($scope | norm)) ] | reverse) as $cov
        | if ($cov | length) == 0
          then "scope\n  recorded approval scopes for this task, none of which matches that action:\n"
               + ([ $a[] | "    - \"" + .scope + "\" (decision " + .decision_id + ", deployment_impact: " + (.deployment_impact | tostring) + ")" ] | join("\n"))
          else ([ $cov[] |
                 if ($dep == "yes" and .deployment_impact == false)
                 then "deployment\n  matching approval: \"" + .scope + "\" (decision " + .decision_id + ", approved by " + .approved_by + ")\n  that approval was recorded with deployment_impact: false, and the action you described HAS deployment impact."
                 elif (.target_revision == $nogit) or ($cur == $nogit)
                 then "unverifiable\n  matching approval: \"" + .scope + "\" (decision " + .decision_id + ")\n  revision when approved: " + .target_revision + "\n  revision now:          " + $cur
                 elif (.target_revision != $cur)
                 then "revision\n  matching approval: \"" + .scope + "\" (decision " + .decision_id + ", approved by " + .approved_by + ")\n  revision when approved: " + .target_revision + "\n  revision now:          " + $cur
                 else "ok\n  decision:    " + .decision_id
                      + "\n  approved by: " + .approved_by
                      + "\n  scope:       \"" + .scope + "\""
                      + "\n  revision:    " + .target_revision
                      + "\n  conditions:  " + (if (.conditions | type) == "string" and ((.conditions | length) > 0) then .conditions else "(none recorded)" end)
                 end ]) as $outcomes
            | ([ $outcomes[] | select(startswith("ok\n")) ]) as $good
            | if ($good | length) > 0 then $good[0] else $outcomes[0] end
          end
      end
  ' "$STATE" 2>/dev/null)

  # CRLF NORMALISATION, AND WHY IT IS NOT OPTIONAL HERE. This is the only read
  # in this file whose jq output is deliberately MULTI-LINE, and multi-line is
  # where this project's platform bites: the jq build on the primary platform
  # (Windows, run under Git Bash) writes stdout in TEXT MODE, so every `\n` the
  # program emits arrives as CR LF. The existing single-line reads never had to
  # care -- MSYS bash strips a trailing CRLF from a command substitution -- but
  # an INTERNAL newline keeps its CR, which would leave the verdict word as
  # "ok\r" and send a perfectly good approval down the catch-all into a
  # corruption refusal. (Verified, not assumed: `jq -r '"ok\n x"'` through
  # `$( )` and `od -c` shows `o k \r \n`.) Only CRLF PAIRS are collapsed, so a
  # CR a caller genuinely typed into a scope or approver string survives; that
  # text is display-only anyway and nothing branches on it. This is the same
  # hazard `start`'s dependency loop documents for PIPED jq, in its text-mode
  # form, which reaches `$( )` too.
  raw="${raw//$'\r'$'\n'/$'\n'}"

  # Split the decision word off the display text. `${raw%%$'\n'*}` is the whole
  # string when there is no newline at all, which is exactly what the one-word
  # verdicts ("none") and a jq that produced nothing both look like -- and both
  # are handled correctly by the case below (accepted, and refused,
  # respectively).
  APPROVAL_VERDICT="${raw%%$'\n'*}"
  if [ "$APPROVAL_VERDICT" = "$raw" ]; then
    APPROVAL_DETAIL=""
  else
    APPROVAL_DETAIL="${raw#*$'\n'}"
  fi

  case "$APPROVAL_VERDICT" in
    ok|none|scope|deployment|revision|unverifiable) return 0 ;;
    bad:*) state_field_fail "$id" "approvals" "every entry to carry a non-empty string decision_id, scope, target_revision and approved_by, a boolean deployment_impact, and conditions that are absent, null or a string" "${APPROVAL_VERDICT#bad:}" ;;
    # EXPLICIT CATCH-ALL, per this section's rule. An empty verdict means jq
    # itself failed and `2>/dev/null` swallowed its message; any other word
    # means this program was edited without extending the case above. Both
    # REFUSE -- there is no route from an unreadable state file to `ok`.
    *)     state_field_fail "$id" "approvals" "every entry to carry a non-empty string decision_id, scope, target_revision and approved_by, a boolean deployment_impact, and conditions that are absent, null or a string" "unreadable — the task record could not be parsed as JSON, so no approval verdict was produced" ;;
  esac
}

# NOTE: the old `require_task` lived here. Every call site now uses
# require_task_state (above), which publishes the state in TASK_STATE_VALUE
# instead of printing it -- so it can be called DIRECTLY rather than inside
# `$( )`, where its `exit` only ever killed the subshell. Its two not-found
# messages are preserved verbatim there.
