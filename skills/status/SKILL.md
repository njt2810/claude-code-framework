---
name: status
description: |
  TRIGGER when: the user asks about the current state of the project, says status,
  what's going on, overview, where are we, or wants a quick snapshot.
  DO NOT TRIGGER when: the user wants to resume work (/resume), start a feature
  (/new-feature), or do a full documentation audit (/document-all).
disable-model-invocation: true
effort: low
shell: bash
user_locked: true
---

# Project Status

## When to Use

When the user wants a quick snapshot of the project's current state.
Not for resuming work or starting a feature.

## Procedure

### Recent activity
!`git log --oneline -5 2>/dev/null || echo "No git repository"`

## Working tree
!`git status --short 2>/dev/null || echo ""`

## Steps

1. Read `wiki/PROJECT_STATUS.md` if it exists
2. Check `wiki/logs/` for the latest session log
3. Count files in `.claude/skills/learned/`
4. Read `graphify-out/GRAPH_REPORT.md` for codebase size if available

Display:

```
{Project Name} — Status

  Stream:       {personal/omasu/xtend}
  Status:       {active/paused/complete}
  Stack:        {language, framework}
  Last commit:  {date and message}
  Uncommitted:  {count} changes

  Codebase:     {file count} files
  Tests:        {pass/fail count or "not configured"}
  Learned:      {count} skills accumulated

  Last session: {date — summary}
  Open items:   {from last session log}

  Recent commits:
    {last 5 commits, one-line each}
```

## Pitfalls

- Don't fabricate data — if wiki/PROJECT_STATUS.md doesn't exist, say so
- Test count should come from actually running tests, not guessing

## Verification

- All fields are filled with real data from the project
- No placeholder values left in the output
