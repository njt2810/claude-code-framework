---
name: pin-skill
description: |
  TRIGGER when: the user wants to protect a skill from deletion/retirement.
  Says "pin skill", "pin-skill", "protect from deletion".
  DO NOT TRIGGER when: the user wants to lock a skill (/lock-skill) or curate (/curate).
argument-hint: <skill-name>
disable-model-invocation: true
user_locked: true
---

## When to Use

When you want to protect a skill from being retired or deleted by /curate.
Pinned skills can still receive edit proposals, unlike locked skills.

## Procedure

1. Read $ARGUMENTS to get the skill name
2. If no argument, ask: "Which skill do you want to pin?"
3. Read `~/.claude/skills/{name}/SKILL.md`
4. If `pinned: true` already exists: "Already pinned."
5. If `pinned: false` or missing: set `pinned: true` in frontmatter
6. Report: "Pinned: /{{name}} — Curator cannot retire or delete this skill."

## Pitfalls

- Pinning does NOT prevent edits — use /lock-skill for full protection
- Both pinned + locked = equivalent to locked (most restrictive wins)

## Verification

- Read the SKILL.md after editing and confirm `pinned: true` is present
