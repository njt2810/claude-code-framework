---
name: resume
description: |
  TRIGGER when: the user starts a new session and wants to pick up where they left off,
  or says resume, continue, where was I, what was I doing, pick up.
  DO NOT TRIGGER when: the user is starting a brand new task with no prior context,
  or wants to initialize a project (/init-project).
disable-model-invocation: true
effort: medium
shell: bash
user_locked: true
pinned: true
---

# Session Resume

## When to Use

When starting a new session and the user wants to continue where they left off.
Not for brand new tasks with no prior context, or project setup.

## Procedure

Pick up exactly where the last session left off.

## Current git state
!`git log --oneline -5 2>/dev/null || echo "No git repository"`
!`git status --short 2>/dev/null || echo ""`

## Step 1 — Load Last Session

1. Find the most recent file in `wiki/logs/`
2. Read it completely
3. Read `wiki/memory.md` for accumulated project knowledge
4. Read `wiki/PROJECT_STATUS.md` for current state
5. Read `CLAUDE.md` for project context

## Step 2 — Check Codebase State

1. If graphify-out/GRAPH_REPORT.md exists, read it for codebase structure
2. Review the git log and status shown above
3. Note any uncommitted changes

## Step 3 — Check Knowledge Base

1. If `memory/` exists, read `memory/glossary.md` for known terms
2. Read CLAUDE.md for hot cache entries (Memory section if it exists)
3. Scan the last session log for names, acronyms, or project references
   that aren't in the glossary or hot cache
4. If gaps found, note them for the resume summary

## Step 4 — Check Available Skills

1. Scan `.claude/skills/learned/` for any learned skills
2. Note how many are available and their names

## Step 5 — Present Resume Summary

Before presenting, re-read TEAM.md to reinforce the team structure.

```
Lead Engineer reporting in.

Resuming: {project name}

Last session ({date}):
  {2-3 sentence summary of what was accomplished}

Current state:
  {What works, what's pending, any open items}

{If uncommitted changes exist}:
  {N} uncommitted changes detected from last session.

Learned skills available: {count}
  {List skill names if any}

{If knowledge gaps found}:
  Knowledge gaps: {count} unknown terms from last session.
  Run /knowledge gaps to fill them in, or I'll ask as they come up.

Suggested next step:
  "{The specific instruction from the session log's 'Next Session Should Start With' field}"

Ready to continue. What would you like to work on?
```

## If No Session Logs Exist

```
No previous session logs found for this project.

Project: {name from CLAUDE.md}
Stack: {from CLAUDE.md}
Files: {count from directory scan}
{If graphify exists}: Codebase: {node count} files mapped

This appears to be a fresh start. Options:
  /new-feature  start building something new
  /status       see project overview
  /help         see all available commands
```

## Pitfalls

- Not re-reading TEAM.md before presenting leads to identity drift
- Assuming the last session log is accurate — check git log for the real state
- Presenting resume without checking uncommitted changes can miss work-in-progress

## Verification

- Lead Engineer identity stated in the summary
- Last session's state accurately reflected
- Uncommitted changes noted if present
- Suggested next step comes from the session log's "Next Session Should Start With" field
