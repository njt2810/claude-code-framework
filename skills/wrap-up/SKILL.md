---
name: wrap-up
description: |
  TRIGGER when: the user is ending a session, says wrap up, save state, done for now,
  closing, or is about to leave. Also triggered by the session-end hook nudge.
  DO NOT TRIGGER when: the user is in the middle of active work, wants to compact
  (/compact), or wants to clear context (/clear).
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Session Wrap-Up

## When to Use

When the user is ending a session and wants to save state for next time.
Not during active work, compaction, or context clears.

## Procedure

Capture everything important before this session ends.

## Step 1 — Session Summary

Write a session log to `wiki/logs/{YYYY-MM-DD}.md`:

```markdown
# Session Log — {date}

## Accomplished
- {What was completed this session, specific and concrete}

## Decisions Made
- {Any architectural or design decisions}
- {Any tool/library choices}

## Files Changed
- {List of key files modified, created, or deleted}

## Open Items
- {Anything left unfinished}
- {Known issues discovered but not fixed}

## Next Session Should Start With
"{Specific instruction for the next /resume — what to read, what to do first}"
```

## Step 2 — Skill Refinement Check

Check if any skills from `.claude/skills/learned/` were used this session:

For each skill that was used:
- Did the skill's procedure work as documented?
  - YES → Add today's date to the "Verified on" section
  - NO → Show the proposed changes:
    "I'd like to update the {name} skill:
     CURRENT: {what the skill says}
     PROPOSED: {what it should say based on this session}
     Reason: {what happened that shows the change is needed}
     Approve this update? (yes/no)"

- Has this skill been verified 3+ times without changes?
  - YES → "The {name} skill has been verified {N} times. Consider
    promoting it to a permanent skill. Approve? (yes/no)"
  - If approved: move from `.claude/skills/learned/` to `.claude/skills/`
  - After graduation, propose updating TEAM.md:
    "The team now has a permanent '{name}' skill.
     Update TEAM.md to reflect this capability? (yes/no)"

## Step 3 — Learning Routing

For each notable learning from this session, route it to the correct location:

- **Codebase-specific pattern** → Append to `wiki/memory.md`
- **Coding convention or style rule** → Suggest appending to `.claude/rules/`
- **Reusable workflow** → Suggest creating via /learn if not already captured
- **Architectural decision** → Create an ADR in `wiki/decisions/`
- **Cross-project insight** → Note for Obsidian wiki at: {path from stream config}
- **CLAUDE.md candidate** — only if removing it would cause mistakes

## Step 4 — Cost Reminder

If cost tracking is enabled for this stream:

"Session cost check:
 - Claude MAX subscription: already tracked in shared costs
 - Any new services or tools added this session? {list if any}
 - Update your dashboard at: {cost dashboard path}"

## Step 5 — Update Project Status

Update `wiki/PROJECT_STATUS.md` with current state:
- Status: active/paused/complete
- Last updated: today's date
- Current state summary

## Step 6 — Final Commit

If any files were changed during wrap-up (wiki updates, skill refinements):
```
git add wiki/ .claude/skills/
git commit -m "Session wrap-up — {date}"
```

Report:
"Session saved. Run /resume next time to continue."

## Pitfalls

- Forgetting to capture the "Next Session Should Start With" instruction leaves /resume without direction
- Overwriting wiki/memory.md instead of appending — memory.md is append-only
- Promoting a skill that has only been verified once or twice — wait for 3+ verifications

## Verification

- Session log written to wiki/logs/ with today's date
- wiki/PROJECT_STATUS.md updated with current state
- All skill refinements approved by the user before saving
- Final commit includes all wiki and skill updates
