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
#   task-state.sh status <id>
#   task-state.sh list
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

now_iso() { date -Iseconds; }

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
  create|start|check|complete|block|unblock) acquire_lock ;;
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
        history: [{from: null, to: "planned", at: $now}]
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
  status <id>
  list

Exit codes: 0 ok · 1 invalid transition / not found / duplicate id / unmet dependency
            2 bad usage / missing jq dependency
USAGE
    exit 2
    ;;
esac
