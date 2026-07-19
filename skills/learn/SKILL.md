---
name: learn
description: |
  TRIGGER when: the user says /learn, wants to capture a reusable pattern, or the session
  monitor nudges about learning. Also trigger when the user says "save this pattern",
  "remember how we did this", or "we should capture this".
  DO NOT TRIGGER when: the user wants documentation (/document-all), project setup
  (/init-project), or session wrap-up (/wrap-up — which has its own skill refinement step).
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Learning Capture

## When to Use

When a reusable pattern emerges from the current session — a debugging technique,
a workflow that worked well, a configuration trick. Also triggered by the session
monitor nudge after ~20 turns.

## Procedure

Extract what worked and preserve it for future sessions.

## Step 1 — Analyze the Session

Review what just happened and answer:

1. **What was the task?** (one sentence)
2. **What approach worked?** (step-by-step, be specific)
3. **What pitfalls were encountered?** (what went wrong or almost went wrong)
4. **What would you do differently next time?** (improvements)
5. **Is this task likely to recur?** (yes/no and why)

## Step 2 — Decide the Scope (project vs global)

**Default scope is PROJECT-LOCAL**: `<project-root>/.claude/skills/learned/` —
the `.claude` folder INSIDE the current project, NEVER `~/.claude/skills/`.

A skill goes GLOBAL (`~/.claude/skills/learned/`) only if BOTH are true:
1. The procedure has nothing project-specific in it (no project paths, stack
   details, service names, or client context)
2. The user explicitly confirms it is useful across all their projects

When in doubt, project-local. A project skill leaking global clutters every
other project; a global-worthy skill stuck in one project costs nothing.

## Step 3 — Check for Existing Skill

Search the PROJECT's `.claude/skills/learned/` first, then `~/.claude/skills/learned/`:
- If a related skill exists → propose UPDATING it with new learnings (in its current location)
- If nothing similar exists → propose CREATING a new skill

## Step 4 — Propose the Skill (wait for approval)

Present the proposed skill to the user:

```
I'd like to {create / update} a learned skill:

Name: {descriptive-name}
Description: {what this skill does, when to use it}
Scope: {PROJECT (this project only) / GLOBAL (all projects)} — {one-line reason}

Procedure:
  1. {step from what worked}
  2. {step}
  3. {step}

Pitfalls:
  - {what went wrong or could go wrong}

Verified on:
  - {today's date}: {brief outcome description}

Save to {project-root}/.claude/skills/learned/{name}/SKILL.md?
(or ~/.claude/skills/learned/{name}/SKILL.md if scope is GLOBAL)
```

Wait for approval. Do NOT create or modify files without explicit "yes."
The user may override the proposed scope — their choice wins.

## Step 5 — Write the Skill (after approval)

Create the SKILL.md at the approved scope's path:

```yaml
---
name: {descriptive-name}
description: {What this skill does and when to use it. Be specific about trigger conditions.}
---
```

Then the skill body with: When to Use, Procedure, Pitfalls, Verified On sections.

## Step 6 — Log the Learning

Append to `wiki/learnings.md`:

```
- {Date} | {Task} | {Skill created/updated} | {Key insight in one sentence}
```

## Step 7 — Update Team Knowledge

After creating or updating a skill, check if TEAM.md should be updated:
- Does this skill relate to an existing agent's capabilities?
- Does this skill introduce a new capability?

All TEAM.md modifications follow the skill-evolution protocol — approval required.

## Step 8 — Cross-Project Check

If a PROJECT-scoped skill later seems broadly useful:
"This learning could be useful across other projects.
 Want me to promote it to the global learned folder (~/.claude/skills/learned/)?"
Moving scope is an explicit user decision — never silent.

## For Skill Updates (existing skill)

When updating an existing skill, show the diff:
```
Updating: {skill name}

ADDING to procedure:
  + {new step or modification}

ADDING to pitfalls:
  + {new pitfall discovered}

ADDING to verified:
  + {today's date}: {outcome}

Approve this update? (yes/no)
```

## Pitfalls

- Saving a project-specific skill to the GLOBAL folder — this clutters every other
  project over time. Default is always the project's own .claude/skills/learned/
- Creating a skill that's too specific to one project — check if it's broadly useful
- Not populating Pitfalls and Verification sections — every new skill needs all 4 sections
- Modifying TEAM.md without approval — always follow skill-evolution protocol
- Auto-generated skills should NOT have user_locked: true — the Curator may improve them

## Verification

- New skill has all 4 required sections (When to Use, Procedure, Pitfalls, Verification)
- Skill was approved by the user before creation
- wiki/learnings.md was updated
- Learned skills do NOT have user_locked set (unlocked by default for curation)
