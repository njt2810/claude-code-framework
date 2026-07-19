#!/bin/bash
# Timer helper — deterministic state operations for /timer (client billable time)
# The /timer skill calls this for ALL timer.json reads/writes so billing state
# is never hand-written by the model. Requires jq (a framework dependency).
#
# Usage:
#   timer.sh start <client> <type> <note>   Create timer.json (fails if active)
#   timer.sh pause                          Accumulate elapsed, set paused
#   timer.sh resume                         Set running again
#   timer.sh stop                           Print final summary JSON, delete state
#   timer.sh status                         Human-readable one-liner
#
# Exit codes: 0 ok · 1 invalid state (no timer / already running) · 2 bad usage / missing dep

STATE_DIR=".claude/state"
STATE="$STATE_DIR/timer.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (install: winget install jqlang.jq)" >&2
  exit 2
fi

now_iso()   { date -Iseconds; }
now_epoch() { date +%s; }

# Elapsed seconds for a running timer segment; 0 if unparseable
segment_seconds() {
  local started="$1" start_epoch
  start_epoch=$(date -d "$started" +%s 2>/dev/null) || return 1
  echo $(( $(now_epoch) - start_epoch ))
}

fmt_duration() {
  local s=$1 m=$(( $1 / 60 ))
  if [ "$m" -ge 60 ]; then echo "$((m/60))h $((m%60))m"; else echo "${m}m"; fi
}

case "${1:-}" in

  start)
    CLIENT="${2:-}"; TYPE="${3:-other}"; NOTE="${4:-}"
    if [ -z "$CLIENT" ] || [ -z "$NOTE" ]; then
      echo "Usage: timer.sh start <client> <type> <note>" >&2; exit 2
    fi
    if [ -f "$STATE" ] && [ "$(jq -r '.active // false' "$STATE" 2>/dev/null)" = "true" ]; then
      echo "ERROR: timer already running for $(jq -r '.client' "$STATE"): $(jq -r '.note' "$STATE")" >&2
      exit 1
    fi
    mkdir -p "$STATE_DIR"
    BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
    jq -n \
      --arg client "$CLIENT" --arg type "$TYPE" --arg note "$NOTE" \
      --arg started "$(now_iso)" --arg branch "$BRANCH" --arg commit "$COMMIT" \
      '{active: true, mode: "running", client: $client, type: $type, note: $note,
        started_at: $started, branch: $branch, starting_commit: $commit,
        accumulated_seconds: 0}' > "$STATE"
    echo "STARTED client=$CLIENT type=$TYPE note=\"$NOTE\" at=$(now_iso)"
    ;;

  pause)
    [ -f "$STATE" ] || { echo "ERROR: no timer running" >&2; exit 1; }
    MODE=$(jq -r '.mode // "running"' "$STATE")
    [ "$MODE" = "running" ] || { echo "ERROR: timer is not running (mode=$MODE)" >&2; exit 1; }
    STARTED=$(jq -r '.started_at' "$STATE")
    SEG=$(segment_seconds "$STARTED") || SEG=0
    TMP=$(mktemp) && jq --argjson seg "$SEG" \
      '.accumulated_seconds += $seg | .mode = "paused" | .started_at = ""' \
      "$STATE" > "$TMP" && mv "$TMP" "$STATE"
    ACC=$(jq -r '.accumulated_seconds' "$STATE")
    echo "PAUSED at $(fmt_duration "$ACC")"
    ;;

  resume)
    [ -f "$STATE" ] || { echo "ERROR: no timer to resume" >&2; exit 1; }
    MODE=$(jq -r '.mode // ""' "$STATE")
    [ "$MODE" = "paused" ] || { echo "ERROR: timer is not paused (mode=$MODE)" >&2; exit 1; }
    TMP=$(mktemp) && jq --arg started "$(now_iso)" \
      '.mode = "running" | .started_at = $started' \
      "$STATE" > "$TMP" && mv "$TMP" "$STATE"
    ACC=$(jq -r '.accumulated_seconds' "$STATE")
    echo "RESUMED accumulated=$(fmt_duration "$ACC")"
    ;;

  stop)
    [ -f "$STATE" ] || { echo "ERROR: no timer running" >&2; exit 1; }
    MODE=$(jq -r '.mode // "running"' "$STATE")
    ACC=$(jq -r '.accumulated_seconds // 0' "$STATE")
    TOTAL=$ACC
    if [ "$MODE" = "running" ]; then
      STARTED=$(jq -r '.started_at' "$STATE")
      SEG=$(segment_seconds "$STARTED") || SEG=0
      TOTAL=$(( ACC + SEG ))
    fi
    # Final summary JSON for the skill to build the time-log entry from
    jq --argjson total "$TOTAL" --arg stopped "$(now_iso)" \
      '. + {total_seconds: $total, stopped_at: $stopped}' "$STATE"
    rm -f "$STATE"
    echo "STOPPED total=$(fmt_duration "$TOTAL")" >&2
    ;;

  status)
    if [ ! -f "$STATE" ] || [ "$(jq -r '.active // false' "$STATE" 2>/dev/null)" != "true" ]; then
      echo "No timer running."
      exit 0
    fi
    MODE=$(jq -r '.mode' "$STATE"); ACC=$(jq -r '.accumulated_seconds // 0' "$STATE")
    CLIENT=$(jq -r '.client' "$STATE"); TYPE=$(jq -r '.type' "$STATE"); NOTE=$(jq -r '.note' "$STATE")
    TOTAL=$ACC
    if [ "$MODE" = "running" ]; then
      SEG=$(segment_seconds "$(jq -r '.started_at' "$STATE")") || SEG=0
      TOTAL=$(( ACC + SEG ))
      echo "RUNNING $CLIENT · $TYPE · \"$NOTE\" · $(fmt_duration "$TOTAL")"
    else
      echo "PAUSED $CLIENT · $TYPE · \"$NOTE\" · $(fmt_duration "$TOTAL")"
    fi
    ;;

  *)
    echo "Usage: timer.sh {start|pause|resume|stop|status}" >&2
    exit 2
    ;;
esac
