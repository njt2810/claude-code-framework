# Skill Evolution Protocol — Always Loaded

NEVER modify any skill, rule, agent definition, CLAUDE.md,
hooks, or settings.json without explicit human approval.

For NEW skills:
1. Say: "I'd like to create a new skill: {name}"
2. Show the proposed content in full
3. Wait for "yes" / "approved" / "go ahead"
4. Only then write the file

For UPDATING existing skills:
1. Say: "I'd like to update the {name} skill"
2. Show the specific changes:
   CURRENT: {what it says now}
   PROPOSED: {what it would say}
3. Explain why the change is needed
4. Wait for approval

For DOWNLOADING tools or packages:
1. Say: "This task would benefit from {tool}"
2. Explain: what it does, why needed, install command,
   security implications, adoption level
3. Wait for approval

For GRADUATING learned skills (learned → permanent):

**Concrete promotion criterion: 3 successful uses.**

A "successful use" means:
1. The skill was invoked
2. It completed without the user having to override or correct its procedure
3. The user did not propose changes to the skill afterward
4. The verification section's checks all passed

Track successful uses in the skill's frontmatter:

```yaml
---
name: learned-skill-foo
verified_on:
  - 2026-06-29
  - 2026-07-05
  - 2026-07-12
---
```

When `verified_on` has 3+ entries, the skill is **eligible for graduation**.
Eligible ≠ graduated. The user still approves the promotion explicitly:

1. Say: "The {name} skill has been verified {N} times on {dates}.
   Eligible for promotion to permanent. Promote? (yes/no)"
2. If yes: move it from `learned/` to its parent skills folder **in the same scope** —
   a project skill graduates within the project (`<project>/.claude/skills/learned/` →
   `<project>/.claude/skills/`), a global skill within `~/.claude/skills/`.
   Graduation NEVER changes scope; moving project → global is a separate,
   explicit user decision (see /learn cross-project check).
3. Update TEAM.md to add to "Graduated Skills" section
4. Wait for approval — promotion is not automatic

Skills that FAIL a use (procedure didn't work, user had to override):
- Add the failure date and reason to a `failed_on:` frontmatter array
- Propose a procedure update before next use
- Do not count toward the 3-use graduation criterion
- After 3 failures without graduation, retire the skill via /curate

The human is ALWAYS the gatekeeper for changes to the framework.
