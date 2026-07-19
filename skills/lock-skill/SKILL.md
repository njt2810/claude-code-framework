---
name: lock-skill
description: |
  TRIGGER when: the user wants to mark a skill as user-authored and protect it
  from Curator edits. Says "lock skill", "lock-skill", "protect skill".
  DO NOT TRIGGER when: the user wants to pin a skill (/pin-skill) or curate
  the library (/curate).
argument-hint: <skill-name>
disable-model-invocation: true
user_locked: true
---

## When to Use

When you want to protect a skill from being edited or deleted by /curate.
Locked skills can still be flagged as stale but the Curator cannot modify them.

## Procedure

1. Read $ARGUMENTS to get the skill name
2. If no argument, ask: "Which skill do you want to lock?"
3. Read `~/.claude/skills/{name}/SKILL.md`
4. If `user_locked: true` already exists: "Already locked."
5. If `user_locked: false` or missing: set `user_locked: true` in frontmatter
6. Report: "Locked: /{{name}} — Curator cannot edit or delete this skill."

## Pitfalls

- Make sure the skill name matches an actual skill directory
- Don't modify anything outside the frontmatter

## Verification

- Read the SKILL.md after editing and confirm `user_locked: true` is present
