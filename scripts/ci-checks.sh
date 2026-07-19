#!/bin/bash
# Framework consistency checks — run locally (bash scripts/ci-checks.sh) or in CI.
# Validates the things that rot silently: shell syntax, settings.json, count
# claims across docs, and the personal-identifier scrub.
#
# Scrub patterns are NEVER hardcoded here (that would leak them into the public
# repo). They come from, in order:
#   1. $SCRUB_PATTERNS env var (CI: set as a GitHub Actions repository secret)
#   2. .scrub-patterns file in the repo root (gitignored, local only)
# If neither exists the scrub check is skipped with a warning.

set -u
cd "$(dirname "$0")/.."
PASS=0; FAIL=0

check() {
  if [ "$2" = "0" ]; then PASS=$((PASS+1)); echo "  ok: $1"
  else FAIL=$((FAIL+1)); echo "  FAIL: $1"; fi
}

echo "== Shell syntax (bash -n) =="
SYNTAX_OK=0
for f in hooks/scripts/*.sh tests/*.sh scripts/*.sh; do
  bash -n "$f" 2>/dev/null || { echo "     syntax error: $f"; SYNTAX_OK=1; }
done
check "all shell scripts parse" $SYNTAX_OK

echo "== Shellcheck (if available) =="
if command -v shellcheck >/dev/null 2>&1; then
  # Severity=warning: catches real bugs (SC2086 quoting, SC2016) without style noise
  shellcheck -S warning hooks/scripts/*.sh scripts/*.sh tests/*.sh
  check "shellcheck clean at warning severity" $?
else
  echo "  skip: shellcheck not installed"
fi

echo "== settings.json =="
if command -v jq >/dev/null 2>&1; then
  jq empty settings.json 2>/dev/null; check "settings.json is valid JSON" $?
  # Only documented Claude Code hook events may appear
  BAD_EVENTS=$(jq -r '.hooks | keys[]' settings.json | grep -vxE 'SessionStart|SessionEnd|PreToolUse|PostToolUse|PreCompact|Stop|SubagentStop|Notification|UserPromptSubmit|PermissionRequest' || true)
  [ -z "$BAD_EVENTS" ]; check "no unknown hook events (found: ${BAD_EVENTS:-none})" $?
  # Every referenced hook script exists on disk
  MISSING=0
  while IFS= read -r script; do
    base=$(basename "$script")
    [ -f "hooks/scripts/$base" ] || { echo "     referenced but missing: $base"; MISSING=1; }
  done < <(jq -r '.. | .command? // empty' settings.json | grep -oE '[a-z-]+\.sh' | sort -u)
  check "every wired hook script exists" $MISSING
else
  echo "  skip: jq not installed"
fi

echo "== Count consistency =="
DISK=$(find skills -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
# Note: the line ends in "do (" — cut at the FIRST paren pair, not the last
INSTALL=$(grep 'for %%S in' install.bat | sed 's/[^(]*(//; s/).*//' | tr -d '\r' | tr ' ' '\n' | grep -c .)
README_CLAIM=$(grep -oE 'The Skills System \(([0-9]+)' README.md | grep -oE '[0-9]+' | head -1)
HELP_CLAIM=$(grep -oE '[0-9]+ skills,' skills/help/SKILL.md | grep -oE '[0-9]+' | head -1)
echo "     disk=$DISK install.bat=$INSTALL README=$README_CLAIM help=$HELP_CLAIM"
[ "$DISK" = "$INSTALL" ] && [ "$DISK" = "$README_CLAIM" ] && [ "$DISK" = "$HELP_CLAIM" ]
check "skill counts agree everywhere" $?

AGENTS=$(ls agents/*.md 2>/dev/null | wc -l | tr -d ' ')
RULES=$(ls rules/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$AGENTS" = "7" ] && [ "$RULES" = "10" ]
check "agent/rule counts match documentation (agents=$AGENTS rules=$RULES)" $?

echo "== Personal-identifier scrub =="
PATTERNS="${SCRUB_PATTERNS:-}"
if [ -z "$PATTERNS" ] && [ -f ".scrub-patterns" ]; then
  PATTERNS=$(cat .scrub-patterns)
fi
if [ -n "$PATTERNS" ]; then
  # Word boundaries so e.g. a pattern inside "Extends" doesn't false-positive.
  # Only tracked files matter — untracked local files can't leak via git.
  HITS=$(git grep -iInE "\b($PATTERNS)\b" -- . 2>/dev/null || true)
  if [ -n "$HITS" ]; then
    echo "$HITS" | head -10
  fi
  [ -z "$HITS" ]; check "no personal identifiers in tracked files" $?
else
  echo "  skip: no SCRUB_PATTERNS env var and no .scrub-patterns file"
  echo "        (set the SCRUB_PATTERNS repository secret in GitHub for CI coverage)"
fi

echo ""
echo "=============================="
echo "  PASS: $PASS   FAIL: $FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
