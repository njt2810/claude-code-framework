---
name: unlock-skill
description: |
  TRIGGER when: the user wants to allow the Curator to edit a skill.
  Says "unlock skill", "unlock-skill", "allow curator edits".
  DO NOT TRIGGER when: the user wants to unpin (/unpin-skill) or curate (/curate).
argument-hint: <skill-name>
disable-model-invocation: true
user_locked: true
---

## When to Use

When you want to allow /curate to propose edits or retirement for a skill.
Typically used on auto-generated skills from /learn that need curation.

## Procedure

1. Read $ARGUMENTS to get the skill name
2. If no argument, ask: "Which skill do you want to unlock?"
3. Read `~/.claude/skills/{name}/SKILL.md`
4. If `user_locked: false` or missing: "Already unlocked."
5. If `user_locked: true`: set `user_locked: false` in frontmatter
6. Report: "Unlocked: /{{name}} — Curator can now propose edits."

## Pitfalls

- Unlocking a core framework skill means /curate could propose changes to it
- The user always approves changes — unlocking just allows proposals

## Verification

- Read the SKILL.md after editing and confirm `user_locked: false` is present
