#!/bin/bash
# Bash Guard — intercepts long-running and chained commands
# Runs on PreToolUse (matcher: Bash)
# Warns but does NOT block (exit 0)

INPUT=$(cat)

# Extract command from tool input JSON (portable — no jq, no grep -P)
COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Check for known long-running commands chained with && or ;
LONG_CMDS="npm install|npm ci|pip install|pytest|npm test|npm run build|pip-audit|npm audit|yarn install|pnpm install"
if echo "$COMMAND" | grep -qiE "($LONG_CMDS)" 2>/dev/null; then
  if echo "$COMMAND" | grep -qE '&&|;' 2>/dev/null; then
    echo "Break this into separate commands for progress reporting. Run each command individually and report status between them."
  fi
  if echo "$COMMAND" | grep -qiE "(npm (install|ci)|pip install|yarn install|pnpm install)" 2>/dev/null; then
    echo "This command may take several minutes. Consider using run_in_background."
  fi
fi

# Check for network commands without timeout
NETWORK_CMDS="curl|wget|fetch|ssh|scp|rsync"
if echo "$COMMAND" | grep -qiE "($NETWORK_CMDS)" 2>/dev/null; then
  if ! echo "$COMMAND" | grep -qiE "(timeout|--connect-timeout|--max-time|-m )" 2>/dev/null; then
    echo "Network command without timeout. Set a timeout to prevent hanging on unreachable servers."
  fi
fi

# Check for commands that commonly hang waiting for input
STDIN_CMDS="read |less |more |vi |vim |nano |emacs "
if echo "$COMMAND" | grep -qiE "($STDIN_CMDS)" 2>/dev/null; then
  echo "This command may wait for interactive input, which will hang. Use a non-interactive alternative."
fi

exit 0
