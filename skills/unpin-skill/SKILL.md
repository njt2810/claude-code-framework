---
name: unpin-skill
description: |
  TRIGGER when: the user wants to remove deletion protection from a skill.
  Says "unpin skill", "unpin-skill", "allow retirement".
  DO NOT TRIGGER when: the user wants to unlock (/unlock-skill) or curate (/curate).
argument-hint: <skill-name>
disable-model-invocation: true
user_locked: true
---

## When to Use

When you want to allow /curate to propose retiring or deleting a skill.
Use after deciding a skill is no longer critical.

## Procedure

1. Read $ARGUMENTS to get the skill name
2. If no argument, ask: "Which skill do you want to unpin?"
3. Read `~/.claude/skills/{name}/SKILL.md`
4. If `pinned: false` or missing: "Already unpinned."
5. If `pinned: true`: set `pinned: false` in frontmatter
6. Report: "Unpinned: /{{name}} — Curator can now propose retirement."

## Pitfalls

- Unpinning only removes deletion protection — if the skill is also locked,
  the Curator still can't propose edits
- Check user_locked status and report both flags to the user

## Verification

- Read the SKILL.md after editing and confirm `pinned: false` is present
