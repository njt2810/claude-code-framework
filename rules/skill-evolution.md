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
1. Say: "The {name} skill has been verified {N} times.
   Promote to permanent skill?"
2. Wait for approval

The human is ALWAYS the gatekeeper for changes to the framework.
