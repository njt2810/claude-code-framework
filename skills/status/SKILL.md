---
name: status
description: |
  TRIGGER when: the user asks about the current state of the project, says status,
  what's going on, overview, where are we, or wants a quick snapshot.
  DO NOT TRIGGER when: the user wants to resume work (/resume), start a feature
  (/new-feature), or do a full documentation audit (/document-all).
disable-model-invocation: true
user_locked: true
---

# Project Status

## When to Use

When the user wants a quick snapshot of the project's current state.
Not for resuming work or starting a feature.

## Lead Engineer Guidance

`/status` is a read-only snapshot. For coaching on what to do next, use
`/recommend` instead — that one prioritizes and explains.

`/status` is best at the START of a session before you decide what to work on.
`/recommend` follows naturally if the status raises questions.

## Procedure

### Recent activity
!`git log --oneline -5 2>/dev/null || echo "No git repository"`

## Working tree
!`git status --short 2>/dev/null || echo ""`

## Current branch & PR
!`git rev-parse --abbrev-ref HEAD 2>/dev/null && gh pr list --head $(git rev-parse --abbrev-ref HEAD 2>/dev/null) --json number,url,state 2>/dev/null || echo ""`

## Safety mode
!`cat .claude/state/mode.json 2>/dev/null || echo '{"mode":"normal"}'`

## Steps

1. Read `wiki/PROJECT_STATUS.md` if it exists
2. Read all files in `wiki/features/` and parse frontmatter
3. Check `wiki/logs/` for the latest session log
4. Count files in `.claude/skills/learned/`
5. Read `graphify-out/GRAPH_REPORT.md` for codebase size if available
6. For production streams: read `wiki/compliance/gaps.md` for compliance state
7. Read `.claude/state/mode.json` for safety mode

Display:

```
{Project Name} — Status

  Stream:           {personal/org1/org2/learning}
  Production scope: {ON/OFF}
  Safety mode:      {normal/careful/guard/freeze}
  Stack:            {language, framework}
  Last commit:      {date and message}
  Uncommitted:      {count} changes
  Current branch:   {branch}
  Open PR:          {URL or none}

  Codebase:         {file count} files
  Tests:            {pass/fail count or "not configured"}
  Learned skills:   {count} accumulated

  📋 Feature Pipeline
    Proposed:       {N}
    In progress:    {N}
    Review:         {N}
    Shipped (30d):  {N}
    Active total:   {N}

  Top 3 active (by priority):
    {id} {priority} {title}  ({status})
    {id} {priority} {title}  ({status})
    {id} {priority} {title}  ({status})

  (For production streams)
  🛡 Compliance
    Last audit:     {N days ago}
    Open gaps:      {N} CRITICAL, {N} HIGH
    Evidence stale: {N} items > 90 days

  Last session:     {date — summary}
  Open items:       {from last session log}

  Recent commits:
    {last 5 commits, one-line each}
```

After displaying, if there are notable items, suggest:
"Want a coached recommendation on what to do next? Run `/recommend`."

## Pitfalls

- Don't fabricate data — if wiki/PROJECT_STATUS.md doesn't exist, say so
- Don't skip the feature pipeline section — that's the single most useful add
- Test count should come from actually running tests OR last known good count, with timestamp
- For production streams, omitting compliance state leaves blind spots

## Verification

- All fields filled with real data from the project (no placeholders)
- Feature pipeline counts reflect actual files in wiki/features/
- Safety mode is current (not stale)
- For production streams, compliance summary is present
