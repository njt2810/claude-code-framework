#!/bin/bash
# Task-state helper — deterministic durable task records and transitions for the
# rebuild framework's lead/builder/verifier delivery loop.
# See docs/rebuild/DESIGN.md ("Delivery model", "Verification contract") and
# docs/rebuild/BUILD_PLAN.md Part 1.2.
#
# This is the ONLY thing that may ever mark a task complete. Per DESIGN.md's
# verification contract, an agent's own claim of "done" is never sufficient —
# only this script's own `complete` transition (checking -> done), invoked as a
# real tool call, constitutes completion.
#
# State lives at .claude/state/team-tasks.json, relative to the current working
# directory. That relative path is what makes state project-isolated: each
# project directory gets its own file, nothing here is keyed by an absolute
# path or shared across projects.
#
# Usage:
#   task-state.sh create <id> <title> [--depends id1,id2,...] [--builder name]
#                 [--verifier name] [--skills a,b] [--risk low|medium|high] [--budget N]
#   task-state.sh start <id>
#   task-state.sh check <id>
#   task-state.sh complete <id>
#   task-state.sh block <id> <reason> [--resume-condition text]
#   task-state.sh unblock <id>
#   task-state.sh record-assignment <id> --role builder|verifier --agent-type name
#                 [--skill-hash path:hash,path:hash,...] [--acceptance-text text]
#                 [--code-snapshot text]
#   task-state.sh record-evidence <id> --command "<cmd>" --exit-code N
#                 --tests-total N --tests-skipped N --output-file <path>
#                 [--artifact <path>]... [--cwd <path>]
#   task-state.sh status <id>
#   task-state.sh list
#
# record-assignment (Part 1.3) appends a durable assignment record to the
# task's own "assignments" array -- it does NOT change the task's state.
# It's the mechanism behind scripts/team/assign.sh: durable proof of which
# agent type, which skill file revisions (by content hash, not just path --
# a path alone can't tell you whether the skill changed after assignment),
# and (for verifier assignments) which acceptance criteria and code snapshot
# a given assignment used. Callers should generally go through assign.sh
# rather than calling this subcommand directly, since assign.sh is what
# computes the skill hashes and the code snapshot identity in the first
# place -- this subcommand just records whatever it's given.
#
# record-evidence (Part 1.4) appends a durable evidence record to the task's
# own "evidence" array -- it does NOT change the task's state and it does
# NOT complete the task. See docs/rebuild/DESIGN.md's "Verification
# contract": the runner captures command, cwd, environment identity, time,
# exit status, test totals/skipped, output location, and code snapshot
# identity, and "a commit SHA alone is insufficient when uncommitted changes
# exist." This subcommand is what durably records that evidence; it does not
# itself judge whether the evidence is good enough to complete the task --
# that judgment is scripts/team/complete-gate.sh's job, which reads this
# array and is the ONLY sanctioned path to calling `complete` in the
# intended workflow (see complete-gate.sh's own header for why).
#
# --cwd, --output-file, and every --artifact are resolved to absolute paths
# HERE, at recording time, before being stored: --cwd first (relative to the
# actual invocation directory, same default as when --cwd is omitted), then
# --output-file and each --artifact relative to that now-absolute --cwd. An
# already-absolute path is stored unchanged. This is what makes "verify the
# exact claimed path" well-defined for complete-gate.sh later: without it, a
# relative artifact path's meaning would depend on which directory
# complete-gate.sh happens to be invoked from, which can differ from the
# directory evidence was recorded from.
#
# States: planned -> building -> checking -> done
#         (any of planned/building/checking) -> blocked -> (restored state)
#
# Exit codes: 0 ok
#             1 invalid transition / not found / duplicate id / unmet dependency
#             2 bad usage / missing jq dependency
#
# Every transition is atomic: written to a temp file in the same directory as
# the state file, then mv'd into place — no command can leave the state file
# half-written. Every rejected/invalid attempt exits before any write happens,
# so the state file is left byte-for-byte unchanged. Every mutating command
# records an ISO-8601 timestamp and appends an entry to that task's own
# transition history array.
#
# Every mutating command (create/start/check/complete/block/unblock) also
# holds an exclusive lock across its ENTIRE read-modify-write sequence — not
# just the final atomic_update write — so concurrent invocations (e.g. a lead
# plus several builder/verifier subagents all touching the same project's
# state file at once) are fully serialized instead of racing on stale reads.
# Uses flock when available; falls back to a portable mkdir-based mutex
# otherwise (flock is not reliably present under Git Bash on Windows — verify
# with `command -v flock` rather than assuming). See acquire_lock() below.
#
# No network calls, no model calls. Pure local state management.

set -u

STATE_DIR=".claude/state"
STATE="$STATE_DIR/team-tasks.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (install: winget install jqlang.jq)" >&2
  exit 2
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum is required (used by compute_snapshot for dirty-tree content hashing)" >&2
  exit 2
fi

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

# task_state_of <id> -> state string, or "missing" if the task doesn't exist.
# Assumes $STATE already exists.
task_state_of() {
  jq -r --arg id "$1" '.tasks[$id].state // "missing"' "$STATE"
}

# require_task <id> -> prints the task's current state and returns 0, or
# prints an error to stderr and exits 1 if the state file or task is missing.
require_task() {
  if [ ! -f "$STATE" ]; then
    echo "ERROR: task '$1' not found (no tasks recorded yet)" >&2
    exit 1
  fi
  local s
  s=$(task_state_of "$1")
  if [ "$s" = "missing" ]; then
    echo "ERROR: task '$1' not found" >&2
    exit 1
  fi
  echo "$s"
}

CMD="${1:-}"

# Every mutating command is serialized against every other mutating command
# via a single project-wide lock, held for the command's entire
# read-modify-write sequence (see acquire_lock() above).
case "$CMD" in
  create|start|check|complete|block|unblock|record-assignment|record-evidence) acquire_lock ;;
esac

case "$CMD" in

  create)
    ID="${2:-}"; TITLE="${3:-}"
    if [ -z "$ID" ] || [ -z "$TITLE" ]; then
      echo "Usage: task-state.sh create <id> <title> [--depends id1,id2,...] [--builder name] [--verifier name] [--skills a,b] [--risk low|medium|high] [--budget N]" >&2
      exit 2
    fi
    if [ $# -ge 3 ]; then shift 3; else shift $#; fi

    DEPENDS=""; BUILDER=""; VERIFIER=""; SKILLS=""; RISK="medium"; BUDGET=2
    while [ $# -gt 0 ]; do
      case "$1" in
        --depends) [ $# -ge 2 ] || { echo "ERROR: --depends requires a value" >&2; exit 2; }; DEPENDS="$2"; shift 2 ;;
        --builder) [ $# -ge 2 ] || { echo "ERROR: --builder requires a value" >&2; exit 2; }; BUILDER="$2"; shift 2 ;;
        --verifier) [ $# -ge 2 ] || { echo "ERROR: --verifier requires a value" >&2; exit 2; }; VERIFIER="$2"; shift 2 ;;
        --skills) [ $# -ge 2 ] || { echo "ERROR: --skills requires a value" >&2; exit 2; }; SKILLS="$2"; shift 2 ;;
        --risk) [ $# -ge 2 ] || { echo "ERROR: --risk requires a value" >&2; exit 2; }; RISK="$2"; shift 2 ;;
        --budget) [ $# -ge 2 ] || { echo "ERROR: --budget requires a value" >&2; exit 2; }; BUDGET="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    case "$RISK" in
      low|medium|high) ;;
      *) echo "ERROR: --risk must be one of low, medium, high (got: $RISK)" >&2; exit 2 ;;
    esac
    case "$BUDGET" in
      ''|*[!0-9]*) echo "ERROR: --budget must be a non-negative integer (got: $BUDGET)" >&2; exit 2 ;;
    esac

    ensure_state_file

    EXISTS=$(jq -r --arg id "$ID" '.tasks[$id] // empty' "$STATE")
    if [ -n "$EXISTS" ]; then
      echo "ERROR: task '$ID' already exists" >&2
      exit 1
    fi

    if [ -n "$DEPENDS" ]; then
      IFS=',' read -ra DEP_ARR <<< "$DEPENDS"
      for dep in "${DEP_ARR[@]}"; do
        [ -n "$dep" ] || continue
        DEP_EXISTS=$(jq -r --arg id "$dep" '.tasks[$id] // empty' "$STATE")
        if [ -z "$DEP_EXISTS" ]; then
          echo "ERROR: dependency '$dep' does not exist; create it before task '$ID'" >&2
          exit 1
        fi
      done
    fi

    DEPENDS_JSON=$(csv_to_json_array "$DEPENDS")
    SKILLS_JSON=$(csv_to_json_array "$SKILLS")
    NOW=$(now_iso)

    atomic_update --arg id "$ID" --arg title "$TITLE" --arg builder "$BUILDER" \
      --arg verifier "$VERIFIER" --arg risk "$RISK" --argjson budget "$BUDGET" \
      --argjson depends "$DEPENDS_JSON" --argjson skills "$SKILLS_JSON" --arg now "$NOW" '
      (if $builder == "" then null else $builder end) as $builder_val
      | (if $verifier == "" then null else $verifier end) as $verifier_val
      | .tasks[$id] = {
        id: $id, title: $title, state: "planned",
        depends_on: $depends, builder: $builder_val, verifier: $verifier_val,
        skills: $skills, risk: $risk, budget: $budget,
        blocked_from: null, blocked_reason: null, resume_condition: null,
        created_at: $now, updated_at: $now,
        history: [{from: null, to: "planned", at: $now}],
        assignments: [],
        evidence: []
      }
    '
    echo "CREATED $ID \"$TITLE\" state=planned"
    ;;

  start)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh start <id>" >&2; exit 2; }
    CUR_STATE=$(require_task "$ID")
    if [ "$CUR_STATE" != "planned" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot start (must be 'planned')" >&2
      exit 1
    fi

    UNMET=$(jq -r --arg id "$ID" '
      .tasks[$id].depends_on[]? as $d
      | (.tasks[$d].state // "missing") as $s
      | select($s != "done")
      | "\($d) (state: \($s))"
    ' "$STATE")
    if [ -n "$UNMET" ]; then
      echo "ERROR: task '$ID' cannot start — unmet dependencies:" >&2
      while IFS= read -r line; do echo "  - $line" >&2; done <<< "$UNMET"
      exit 1
    fi

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" '
      .tasks[$id].state = "building"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{from: "planned", to: "building", at: $now}]
    '
    echo "STARTED $ID state=building"
    ;;

  check)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh check <id>" >&2; exit 2; }
    CUR_STATE=$(require_task "$ID")
    if [ "$CUR_STATE" != "building" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot move to checking (must be 'building')" >&2
      exit 1
    fi
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" '
      .tasks[$id].state = "checking"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{from: "building", to: "checking", at: $now}]
    '
    echo "CHECKING $ID state=checking"
    ;;

  complete)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh complete <id>" >&2; exit 2; }
    CUR_STATE=$(require_task "$ID")
    if [ "$CUR_STATE" != "checking" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot complete (must be 'checking')" >&2
      exit 1
    fi
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" '
      .tasks[$id].state = "done"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{from: "checking", to: "done", at: $now}]
    '
    echo "COMPLETED $ID state=done"
    ;;

  block)
    ID="${2:-}"; REASON="${3:-}"
    if [ -z "$ID" ] || [ -z "$REASON" ]; then
      echo "Usage: task-state.sh block <id> <reason> [--resume-condition text]" >&2
      exit 2
    fi
    if [ $# -ge 3 ]; then shift 3; else shift $#; fi

    RESUME_COND=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --resume-condition) [ $# -ge 2 ] || { echo "ERROR: --resume-condition requires a value" >&2; exit 2; }; RESUME_COND="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    CUR_STATE=$(require_task "$ID")
    case "$CUR_STATE" in
      planned|building|checking) ;;
      *) echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot block from this state" >&2; exit 1 ;;
    esac

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg reason "$REASON" \
      --arg resume "$RESUME_COND" --arg from "$CUR_STATE" '
      (if $resume == "" then null else $resume end) as $resume_val
      | .tasks[$id].blocked_from = $from
      | .tasks[$id].blocked_reason = $reason
      | .tasks[$id].resume_condition = $resume_val
      | .tasks[$id].state = "blocked"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{from: $from, to: "blocked", at: $now, reason: $reason, resume_condition: $resume_val}]
    '
    echo "BLOCKED $ID from=$CUR_STATE reason=\"$REASON\""
    ;;

  unblock)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh unblock <id>" >&2; exit 2; }
    CUR_STATE=$(require_task "$ID")
    if [ "$CUR_STATE" != "blocked" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', not blocked" >&2
      exit 1
    fi

    RESTORE=$(jq -r --arg id "$ID" '.tasks[$id].blocked_from // "missing"' "$STATE")
    if [ "$RESTORE" = "missing" ] || [ -z "$RESTORE" ]; then
      echo "ERROR: task '$ID' has no recorded prior state to restore to" >&2
      exit 1
    fi

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg restore "$RESTORE" '
      .tasks[$id].state = $restore
      | .tasks[$id].updated_at = $now
      | .tasks[$id].blocked_from = null
      | .tasks[$id].blocked_reason = null
      | .tasks[$id].resume_condition = null
      | .tasks[$id].history += [{from: "blocked", to: $restore, at: $now}]
    '
    echo "UNBLOCKED $ID state=$RESTORE"
    ;;

  record-assignment)
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-assignment <id> --role builder|verifier --agent-type name [--skill-hash path:hash,path:hash,...] [--acceptance-text text] [--code-snapshot text]" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    ROLE=""; AGENT_TYPE=""; SKILL_HASH=""; ACCEPTANCE=""; SNAPSHOT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --role) [ $# -ge 2 ] || { echo "ERROR: --role requires a value" >&2; exit 2; }; ROLE="$2"; shift 2 ;;
        --agent-type) [ $# -ge 2 ] || { echo "ERROR: --agent-type requires a value" >&2; exit 2; }; AGENT_TYPE="$2"; shift 2 ;;
        --skill-hash) [ $# -ge 2 ] || { echo "ERROR: --skill-hash requires a value" >&2; exit 2; }; SKILL_HASH="$2"; shift 2 ;;
        --acceptance-text) [ $# -ge 2 ] || { echo "ERROR: --acceptance-text requires a value" >&2; exit 2; }; ACCEPTANCE="$2"; shift 2 ;;
        --code-snapshot) [ $# -ge 2 ] || { echo "ERROR: --code-snapshot requires a value" >&2; exit 2; }; SNAPSHOT="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    case "$ROLE" in
      builder|verifier) ;;
      *) echo "ERROR: --role must be 'builder' or 'verifier' (got: '$ROLE')" >&2; exit 2 ;;
    esac
    [ -n "$AGENT_TYPE" ] || { echo "ERROR: --agent-type is required" >&2; exit 2; }

    # Defense in depth: validate --skill-hash BEFORE ever touching the state
    # file, even though scripts/team/assign.sh (the normal caller) already
    # rejects colon-containing skill paths itself. Something could call this
    # subcommand directly, bypassing assign.sh's check, so this subcommand
    # must not trust its caller.
    #
    # "path:hash,path:hash,..." is parsed below by splitting each entry on
    # its FIRST colon: skill paths in this repo are POSIX-relative (see
    # skills/*/SKILL.md and how they're referenced elsewhere in this repo --
    # never absolute, never Windows-style, so never containing a colon), so
    # the first colon always separates path from the hex sha256 that follows.
    # A colon-containing path (e.g. a Windows absolute path like
    # "C:/fakepath/skill.md", realistic input on this project's primary
    # platform) would otherwise silently split into garbage instead of
    # failing -- exactly the silent-corruption bug this validation closes.
    # An entry with zero colons is still valid (path only, no hash) and
    # records (path, sha256: null); an entry with exactly one colon is valid
    # only if the text after it actually looks like a sha256 hex hash --
    # otherwise that colon is almost certainly part of the path itself, not
    # a path/hash separator, so it's rejected too. Two or more colons is
    # always rejected outright.
    if [ -n "$SKILL_HASH" ]; then
      IFS=',' read -ra _SKILL_HASH_ENTRIES <<< "$SKILL_HASH"
      for _entry in "${_SKILL_HASH_ENTRIES[@]}"; do
        [ -n "$_entry" ] || continue
        _colon_count=$(awk -F: '{print NF-1}' <<< "$_entry")
        case "$_colon_count" in
          0) ;; # path only, no colon -- fine
          1)
            _hash_part="${_entry#*:}"
            if ! [[ "$_hash_part" =~ ^[0-9a-fA-F]+$ ]]; then
              echo "ERROR: invalid --skill-hash entry '$_entry': skill paths must not contain a colon and must be relative POSIX-style paths (e.g. skills/foo/SKILL.md) -- the text after the colon does not look like a sha256 hash, which usually means the colon is part of the path itself" >&2
              exit 2
            fi
            ;;
          *)
            echo "ERROR: invalid --skill-hash entry '$_entry': skill paths must not contain a colon and must be relative POSIX-style paths (e.g. skills/foo/SKILL.md)" >&2
            exit 2
            ;;
        esac
      done
    fi

    # require_task exits (before any write) if the state file or task is missing.
    require_task "$ID" >/dev/null

    # "path:hash,path:hash,..." -> [{path, sha256}, ...]. Split each entry on
    # its FIRST colon: skill paths in this repo are POSIX-relative (no colons),
    # so the first colon always separates path from the hex sha256 that follows.
    # An entry with no colon still records (path, sha256: null) rather than
    # silently dropping it.
    SKILLS_JSON=$(jq -R -c '
      split(",") | map(select(length > 0)) | map(
        (index(":")) as $i
        | if $i == null then {path: ., sha256: null}
          else {path: .[0:$i], sha256: .[($i + 1):]} end
      )
    ' <<< "$SKILL_HASH")

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg role "$ROLE" --arg agent_type "$AGENT_TYPE" \
      --argjson skills "$SKILLS_JSON" --arg now "$NOW" \
      --arg acceptance "$ACCEPTANCE" --arg snapshot "$SNAPSHOT" '
      (if $acceptance == "" then null else $acceptance end) as $acceptance_val
      | (if $snapshot == "" then null else $snapshot end) as $snapshot_val
      | .tasks[$id].assignments = ((.tasks[$id].assignments // []) + [{
          role: $role, agent_type: $agent_type, skills: $skills,
          assigned_at: $now, acceptance_criteria: $acceptance_val,
          code_snapshot: $snapshot_val
        }])
      | .tasks[$id].updated_at = $now
    '
    SKILL_COUNT=$(echo "$SKILLS_JSON" | jq 'length')
    echo "RECORDED-ASSIGNMENT $ID role=$ROLE agent_type=$AGENT_TYPE skills=$SKILL_COUNT"
    ;;

  record-evidence)
    # Part 1.6 advisory check, run before any of this subcommand's normal
    # work below.
    warn_if_state_not_gitignored

    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-evidence <id> --command \"<cmd>\" --exit-code N --tests-total N --tests-skipped N --output-file <path> [--artifact <path>]... [--cwd <path>]" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    EV_COMMAND=""; EXIT_CODE=""; TESTS_TOTAL=""; TESTS_SKIPPED=""; OUTPUT_FILE=""; CWD_ARG=""
    ARTIFACTS=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --command) [ $# -ge 2 ] || { echo "ERROR: --command requires a value" >&2; exit 2; }; EV_COMMAND="$2"; shift 2 ;;
        --exit-code) [ $# -ge 2 ] || { echo "ERROR: --exit-code requires a value" >&2; exit 2; }; EXIT_CODE="$2"; shift 2 ;;
        --tests-total) [ $# -ge 2 ] || { echo "ERROR: --tests-total requires a value" >&2; exit 2; }; TESTS_TOTAL="$2"; shift 2 ;;
        --tests-skipped) [ $# -ge 2 ] || { echo "ERROR: --tests-skipped requires a value" >&2; exit 2; }; TESTS_SKIPPED="$2"; shift 2 ;;
        --output-file) [ $# -ge 2 ] || { echo "ERROR: --output-file requires a value" >&2; exit 2; }; OUTPUT_FILE="$2"; shift 2 ;;
        --artifact) [ $# -ge 2 ] || { echo "ERROR: --artifact requires a value" >&2; exit 2; }; ARTIFACTS+=("$2"); shift 2 ;;
        --cwd) [ $# -ge 2 ] || { echo "ERROR: --cwd requires a value" >&2; exit 2; }; CWD_ARG="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    [ -n "$EV_COMMAND" ] || { echo "ERROR: --command is required" >&2; exit 2; }
    [ -n "$OUTPUT_FILE" ] || { echo "ERROR: --output-file is required" >&2; exit 2; }

    # Same validation style as `create`'s --budget check: non-negative
    # integers only, reject non-numeric input cleanly rather than silently
    # coercing it.
    [ -n "$EXIT_CODE" ] || { echo "ERROR: --exit-code is required" >&2; exit 2; }
    case "$EXIT_CODE" in
      ''|*[!0-9]*) echo "ERROR: --exit-code must be a non-negative integer (got: $EXIT_CODE)" >&2; exit 2 ;;
    esac
    [ -n "$TESTS_TOTAL" ] || { echo "ERROR: --tests-total is required" >&2; exit 2; }
    case "$TESTS_TOTAL" in
      ''|*[!0-9]*) echo "ERROR: --tests-total must be a non-negative integer (got: $TESTS_TOTAL)" >&2; exit 2 ;;
    esac
    [ -n "$TESTS_SKIPPED" ] || { echo "ERROR: --tests-skipped is required" >&2; exit 2; }
    case "$TESTS_SKIPPED" in
      ''|*[!0-9]*) echo "ERROR: --tests-skipped must be a non-negative integer (got: $TESTS_SKIPPED)" >&2; exit 2 ;;
    esac

    # Resolve --cwd itself to an absolute path FIRST, relative to the actual
    # invocation directory ($(pwd), the same default used when --cwd is
    # omitted) -- otherwise a caller-supplied relative --cwd (e.g. "subdir")
    # would leave every artifact/output_file path resolved below still
    # relative to some other, ambiguous base. This is the fix for the
    # artifact/output_file path-resolution ambiguity between recording time
    # and gate time (see complete-gate.sh's check 3): every path this
    # subcommand records from here on is stored fully absolute, so a later
    # `complete-gate.sh` run from any directory resolves it identically,
    # without ever needing to guess at or reconstruct a cwd.
    [ -n "$CWD_ARG" ] || CWD_ARG="$(pwd)"
    CWD_ARG=$(resolve_path "$CWD_ARG" "$(pwd)")

    # require_task exits (before any write) if the state file or task is
    # missing -- same defense-in-depth as record-assignment.
    require_task "$ID" >/dev/null

    # --output-file: same ambiguity as --artifact below -- resolve to
    # absolute against the (now-absolute) recorded cwd before storing, so
    # complete-gate.sh's Bug-3 output_file check needs no cwd guessing either.
    OUTPUT_FILE=$(resolve_path "$OUTPUT_FILE" "$CWD_ARG")

    # Artifacts: resolve each to an absolute path against the (now-absolute)
    # recorded cwd BEFORE building the JSON array below -- an artifact
    # recorded as a relative path from one directory must resolve to the
    # same file regardless of which directory complete-gate.sh is later
    # invoked from; storing it pre-resolved is what makes that unambiguous,
    # rather than leaving complete-gate.sh to guess a cwd at check time.
    if [ "${#ARTIFACTS[@]}" -gt 0 ]; then
      RESOLVED_ARTIFACTS=()
      for _art in "${ARTIFACTS[@]}"; do
        RESOLVED_ARTIFACTS+=("$(resolve_path "$_art" "$CWD_ARG")")
      done
      ARTIFACTS=("${RESOLVED_ARTIFACTS[@]}")
    fi

    # Artifacts: bash array -> JSON array of strings, via jq --args so paths
    # containing spaces or special characters survive intact (each array
    # element reaches jq as its own argv entry). ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}
    # is the portable idiom for "expand this array, or nothing, under set -u"
    # that also behaves under older bash where expanding a truly empty array
    # directly can error.
    ARTIFACTS_JSON=$(jq -c -n --args '$ARGS.positional' ${ARTIFACTS[@]+"${ARTIFACTS[@]}"})

    # Environment identity: OS + bash version is enough per BUILD_PLAN.md
    # Part 1.4's own instruction -- not overengineered further.
    ENV_ID="$(uname -s 2>/dev/null || echo unknown) / $(bash --version 2>/dev/null | head -1)"

    SNAPSHOT=$(compute_snapshot)
    NOW=$(now_iso)

    atomic_update --arg id "$ID" --arg command "$EV_COMMAND" --arg cwd "$CWD_ARG" \
      --arg env "$ENV_ID" --arg now "$NOW" --argjson exit_code "$EXIT_CODE" \
      --argjson tests_total "$TESTS_TOTAL" --argjson tests_skipped "$TESTS_SKIPPED" \
      --arg output_file "$OUTPUT_FILE" --argjson artifacts "$ARTIFACTS_JSON" \
      --arg snapshot "$SNAPSHOT" '
      .tasks[$id].evidence = ((.tasks[$id].evidence // []) + [{
          command: $command, cwd: $cwd, environment: $env, recorded_at: $now,
          exit_code: $exit_code, tests_total: $tests_total,
          tests_skipped: $tests_skipped, output_file: $output_file,
          artifacts: $artifacts, code_snapshot: $snapshot
        }])
      | .tasks[$id].updated_at = $now
    '
    ARTIFACT_COUNT=$(echo "$ARTIFACTS_JSON" | jq 'length')
    echo "RECORDED-EVIDENCE $ID exit_code=$EXIT_CODE tests_total=$TESTS_TOTAL tests_skipped=$TESTS_SKIPPED artifacts=$ARTIFACT_COUNT snapshot=\"$SNAPSHOT\""
    ;;

  status)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh status <id>" >&2; exit 2; }
    if [ ! -f "$STATE" ]; then
      echo "ERROR: task '$ID' not found (no tasks recorded yet)" >&2
      exit 1
    fi
    TASK=$(jq --arg id "$ID" '.tasks[$id] // empty' "$STATE")
    if [ -z "$TASK" ]; then
      echo "ERROR: task '$ID' not found" >&2
      exit 1
    fi
    echo "$TASK"
    ;;

  list)
    if [ ! -f "$STATE" ] || [ "$(jq '.tasks | length' "$STATE")" = "0" ]; then
      echo "No tasks recorded."
      exit 0
    fi
    jq -r '
      .tasks[] |
      "\(.id)  [\(.state)]  \(.title)  (depends_on: \(
        (.depends_on // []) | if length == 0 then "none" else join(",") end
      ))"
    ' "$STATE"
    ;;

  *)
    cat >&2 <<'USAGE'
Usage: task-state.sh <command> [args]

Commands:
  create <id> <title> [--depends id1,id2,...] [--builder name] [--verifier name]
                       [--skills a,b] [--risk low|medium|high] [--budget N]
  start <id>
  check <id>
  complete <id>
  block <id> <reason> [--resume-condition text]
  unblock <id>
  record-assignment <id> --role builder|verifier --agent-type name
                     [--skill-hash path:hash,path:hash,...]
                     [--acceptance-text text] [--code-snapshot text]
  record-evidence <id> --command "<cmd>" --exit-code N --tests-total N
                   --tests-skipped N --output-file <path>
                   [--artifact <path>]... [--cwd <path>]
  status <id>
  list

Exit codes: 0 ok · 1 invalid transition / not found / duplicate id / unmet dependency
            2 bad usage / missing jq dependency
USAGE
    exit 2
    ;;
esac
