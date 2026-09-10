#!/bin/bash
# Assignment-recording wrapper for the rebuild framework's lead/builder/verifier
# delivery loop. See docs/rebuild/BUILD_PLAN.md Part 1.3 and docs/rebuild/DESIGN.md
# ("Packaging and architecture", "Delivery model").
#
# This script does two things:
#   1. Durably records an assignment (agent type, skill paths + their sha256
#      content hashes at assignment time, timestamp, and for a verifier: the
#      supplied acceptance criteria and a code snapshot identity) onto the
#      task's own record in .claude/state/team-tasks.json, by shelling out to
#      `task-state.sh record-assignment` -- it does NOT reimplement
#      task-state.sh's locking/atomic-write logic; it reuses it as a
#      subprocess so there is exactly one implementation of the locked
#      read-modify-write sequence in this repo.
#   2. Prints the briefing/prompt text a real Task-tool dispatch would use.
#
# What this script does NOT do: it does not itself invoke the Agent/Task
# tool. Dispatching a native Claude Code subagent is not scriptable from
# bash -- that dispatch is done by whatever is driving the lead session (a
# human operator, or the Lead's own tool use in a real Claude Code session).
# This script's job stops at preparing and durably recording the assignment;
# the caller is responsible for actually starting the subagent with the
# printed briefing.
#
# The sha256 hash recorded for each skill path is the "loaded skill
# revision" BUILD_PLAN.md Part 1.3's acceptance criteria asks for: durable
# proof of exactly which version of a skill's instructions a given
# assignment used, so that if the skill file is edited later, a past
# assignment's hash can be compared against the file's current hash to tell
# whether the assignment used the old or the new version.
#
# Usage:
#   assign.sh <part-id> --role builder|verifier --agent-type <name>
#             [--skills path1,path2,...]
#             [--acceptance-file <path> | --acceptance-text <text>]
#
# Role-specific requirements:
#   builder  : --skills is optional but recommended.
#   verifier : requires --acceptance-file or --acceptance-text.
#              docs/rebuild/BUILD_PLAN.md's acceptance criteria for a part
#              are prose inside BUILD_PLAN.md, not (yet) stored in
#              task-state.sh's own schema -- that's a disclosed gap, not
#              invented storage -- so the caller must supply the acceptance
#              text explicitly here.
#
# Exit codes: 0 ok
#             1 part not found, missing skill file, or task-state.sh rejected
#               the assignment
#             2 bad usage
#
# No network calls, no model calls. Pure local state management, same as
# task-state.sh.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TASK_STATE="$HERE/task-state.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: assign.sh <part-id> --role builder|verifier --agent-type <name>
                  [--skills path1,path2,...]
                  [--acceptance-file <path> | --acceptance-text <text>]

Records a durable assignment for an existing task (BUILD_PLAN.md part) into
.claude/state/team-tasks.json via task-state.sh record-assignment, then
prints the briefing/prompt text a real Task-tool dispatch would use. See the
header comment in this file for what this script does and does not do.

Exit codes: 0 ok · 1 part not found / missing skill file / rejected by
            task-state.sh · 2 bad usage
USAGE
}

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (install: winget install jqlang.jq)" >&2
  exit 2
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum is required to compute skill content hashes" >&2
  exit 2
fi

PART_ID="${1:-}"
if [ -z "$PART_ID" ] || [ "${PART_ID#-}" != "$PART_ID" ]; then
  usage
  exit 2
fi
shift

ROLE=""; AGENT_TYPE=""; SKILLS=""; ACCEPTANCE_FILE=""; ACCEPTANCE_TEXT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --role) [ $# -ge 2 ] || { echo "ERROR: --role requires a value" >&2; exit 2; }; ROLE="$2"; shift 2 ;;
    --agent-type) [ $# -ge 2 ] || { echo "ERROR: --agent-type requires a value" >&2; exit 2; }; AGENT_TYPE="$2"; shift 2 ;;
    --skills) [ $# -ge 2 ] || { echo "ERROR: --skills requires a value" >&2; exit 2; }; SKILLS="$2"; shift 2 ;;
    --acceptance-file) [ $# -ge 2 ] || { echo "ERROR: --acceptance-file requires a value" >&2; exit 2; }; ACCEPTANCE_FILE="$2"; shift 2 ;;
    --acceptance-text) [ $# -ge 2 ] || { echo "ERROR: --acceptance-text requires a value" >&2; exit 2; }; ACCEPTANCE_TEXT="$2"; shift 2 ;;
    *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$ROLE" in
  builder|verifier) ;;
  *) echo "ERROR: --role must be 'builder' or 'verifier' (got: '${ROLE:-<empty>}')" >&2; exit 2 ;;
esac
[ -n "$AGENT_TYPE" ] || { echo "ERROR: --agent-type is required" >&2; exit 2; }
if [ -n "$ACCEPTANCE_FILE" ] && [ -n "$ACCEPTANCE_TEXT" ]; then
  echo "ERROR: give at most one of --acceptance-file or --acceptance-text, not both" >&2
  exit 2
fi

# 1. Validate the part exists. Reuse task-state.sh's own not-found behavior
#    rather than re-reading/duplicating its jq logic here.
STATUS_OUT=$(bash "$TASK_STATE" status "$PART_ID" 2>&1)
STATUS_RC=$?
if [ "$STATUS_RC" -ne 0 ]; then
  echo "$STATUS_OUT" >&2
  exit 1
fi
PART_TITLE=$(echo "$STATUS_OUT" | jq -r '.title')

# 2. Resolve acceptance criteria text (verifier only).
ACCEPTANCE=""
if [ -n "$ACCEPTANCE_FILE" ]; then
  if [ ! -f "$ACCEPTANCE_FILE" ]; then
    echo "ERROR: --acceptance-file not found: $ACCEPTANCE_FILE" >&2
    exit 1
  fi
  ACCEPTANCE=$(cat "$ACCEPTANCE_FILE")
elif [ -n "$ACCEPTANCE_TEXT" ]; then
  ACCEPTANCE="$ACCEPTANCE_TEXT"
fi
if [ "$ROLE" = "verifier" ] && [ -z "$ACCEPTANCE" ]; then
  echo "ERROR: --role verifier requires --acceptance-file or --acceptance-text" >&2
  echo "       (docs/rebuild/BUILD_PLAN.md's acceptance criteria for a part are not" >&2
  echo "       stored in task-state.sh's schema yet -- supply them explicitly)" >&2
  exit 2
fi

# 3. Compute sha256 content hashes for each recorded skill path -- this IS
#    the "loaded skill revision" evidence. Fails loudly if a listed skill
#    file doesn't exist, rather than silently recording a hash for nothing.
#
#    Validated FIRST, before any hash is computed or task-state.sh is ever
#    invoked: a skill path must not contain a colon. The recorded format is
#    "path:hash,path:hash,..." (see task-state.sh record-assignment), parsed
#    by splitting each entry on its FIRST colon -- so a colon-containing path
#    (e.g. a Windows absolute path like "C:/fakepath/skill.md", realistic
#    input on this project's primary platform) would silently split into
#    garbage (path="C", hash="/fakepath/skill.md:<realhash>") instead of
#    failing. Skill paths in this repo are always relative POSIX-style paths
#    (see skills/*/SKILL.md and how they're referenced elsewhere in this
#    repo) -- never absolute, never Windows-style, so this is a real
#    constraint, not just a parser convenience. Rejecting here, before
#    SKILL_HASH_CSV is built, protects every downstream consumer of that
#    string in one place: both the recording call to task-state.sh below and
#    this script's own briefing/display printout at the bottom, since both
#    are derived from SKILL_HASH_CSV.
SKILL_HASH_CSV=""
if [ -n "$SKILLS" ]; then
  IFS=',' read -ra SKILL_PATHS <<< "$SKILLS"
  for p in "${SKILL_PATHS[@]}"; do
    [ -n "$p" ] || continue
    case "$p" in
      *:*)
        echo "ERROR: invalid skill path '$p': skill paths must not contain a colon and must be relative POSIX-style paths (e.g. skills/foo/SKILL.md), not an absolute/Windows-style path" >&2
        exit 1
        ;;
    esac
    if [ ! -f "$p" ]; then
      echo "ERROR: skill file not found: $p" >&2
      exit 1
    fi
    HASH=$(sha256sum "$p" | awk '{print $1}')
    if [ -n "$SKILL_HASH_CSV" ]; then SKILL_HASH_CSV+=","; fi
    SKILL_HASH_CSV+="$p:$HASH"
  done
fi

# 4. Code snapshot identity: short commit SHA, or "uncommitted, base SHA X"
#    if the tree is dirty. Same idea as hooks/scripts/timer.sh's
#    starting_commit (git rev-parse --short HEAD), extended with an explicit
#    dirty check since a dirty tree makes the SHA alone insufficient
#    (see docs/rebuild/DESIGN.md, "Verification contract": "A commit SHA
#    alone is insufficient when uncommitted changes exist.").
compute_snapshot() {
  local sha
  sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  if [ -z "$sha" ]; then
    echo "no-git-repository"
    return
  fi
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "uncommitted, base SHA $sha"
  else
    echo "$sha"
  fi
}
SNAPSHOT=$(compute_snapshot)

# 5. Record the assignment via task-state.sh -- the ONLY writer of
#    .claude/state/team-tasks.json, reusing its lock/atomic_update.
RECORD_ARGS=(record-assignment "$PART_ID" --role "$ROLE" --agent-type "$AGENT_TYPE" --code-snapshot "$SNAPSHOT")
[ -n "$SKILL_HASH_CSV" ] && RECORD_ARGS+=(--skill-hash "$SKILL_HASH_CSV")
[ -n "$ACCEPTANCE" ] && RECORD_ARGS+=(--acceptance-text "$ACCEPTANCE")

RECORD_OUT=$(bash "$TASK_STATE" "${RECORD_ARGS[@]}" 2>&1)
RECORD_RC=$?
if [ "$RECORD_RC" -ne 0 ]; then
  echo "$RECORD_OUT" >&2
  exit 1
fi
echo "$RECORD_OUT"

# 6. Print the briefing/prompt text a real Task-tool dispatch would use.
echo ""
echo "===================== BRIEFING ====================="
echo "Part:        $PART_ID -- $PART_TITLE"
echo "Role:        $ROLE"
echo "Agent type:  $AGENT_TYPE"
echo "Code snapshot: $SNAPSHOT"
if [ -n "$SKILL_HASH_CSV" ]; then
  echo "Skills (path:sha256):"
  IFS=',' read -ra SKILL_PAIRS <<< "$SKILL_HASH_CSV"
  for pair in "${SKILL_PAIRS[@]}"; do
    echo "  - $pair"
  done
else
  echo "Skills: (none recorded for this assignment)"
fi

if [ "$ROLE" = "builder" ]; then
  cat <<EOF

Instructions to the builder subagent (dispatch with agent type
"$AGENT_TYPE", part ID "$PART_ID"):
  Implement docs/rebuild/BUILD_PLAN.md part $PART_ID ("$PART_TITLE") using
  exactly the skill revisions listed above. Confirm each skill file's
  current sha256 still matches the recorded hash before starting. Stay
  inside your assigned scope: do not hand-edit .claude/state/*, do not edit
  docs/rebuild/* beyond this part's own status line, and do not modify
  evidence/verification-runner code -- see agents/team-builder.md for the
  full scope-boundary instruction. Move the task to "checking"
  (task-state.sh check $PART_ID) when implementation and tests are ready;
  do not mark it done yourself.
EOF
else
  cat <<EOF

Instructions to the verifier subagent (dispatch with agent type
"$AGENT_TYPE", part ID "$PART_ID"):
  Independently verify docs/rebuild/BUILD_PLAN.md part $PART_ID
  ("$PART_TITLE") against the acceptance criteria below and the recorded
  code snapshot ($SNAPSHOT). Independently open and read every file the
  builder's report claims to have produced or changed -- a claimed path is
  never evidence on its own. Report PASS/FAIL per criterion. See
  agents/team-verifier.md for the full verification procedure.

  Acceptance criteria:
$(echo "$ACCEPTANCE" | sed 's/^/    /')
EOF
fi
echo "======================================================"
