#!/bin/bash
# Session Start — fires on startup, resume, and clear
# Injects team roster and suggests /resume. Does NOT hardcode a persona name —
# realm-root CLAUDE.md files can override identity (v2 Realm System), and this
# hook has no way to know which realm (if any) governs the cwd it fires in.
# Point at /context instead, which resolves it live every time.

echo ""
echo "Framework active. Run /context to see the resolved identity and rules for this location."
echo ""
echo "Your team: Code Reviewer, Test Engineer, Wiki Updater, Security Auditor, Knowledge Agent, Compliance Officer + UI/UX Engineer (on-demand)."
echo "Delegate to them for reviews, audits, docs, testing, compliance, and knowledge management."
echo ""

# Check for TEAM.md (project-local first, then global)
if [ -f "TEAM.md" ]; then
  echo "TEAM.md found (project-local). Read it for full delegation rules."
elif [ -f "$HOME/.claude/TEAM.md" ]; then
  echo "TEAM.md found (global). Read it for full delegation rules."
fi

# Check for session logs (suggest /resume if they exist)
if [ -d "wiki/logs" ]; then
  LATEST=$(ls -t wiki/logs/*.md 2>/dev/null | head -1)
  if [ -n "$LATEST" ]; then
    echo ""
    echo "Previous session log found. Type /resume to continue where you left off."
  fi
fi

exit 0
