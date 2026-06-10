---
name: help
description: |
  TRIGGER when: the user says help, needs a command reference, is unsure what to do next,
  or asks what commands are available.
  DO NOT TRIGGER when: the user wants status (/status) or to resume (/resume).
disable-model-invocation: true
effort: low
user_locked: true
---

# Framework Command Reference

## When to Use

When the user needs a command reference, is unsure what to do, or asks what's available.

## Procedure

Display this reference to the user:

```
YOUR COMMAND REFERENCE

  STARTING & RESUMING
  /init-project [stream]  Bootstrap a new or existing project
                          Streams: personal, org1, org2, learning
  /resume                 Pick up where you left off
  /status                 Show project status summary

  BUILDING
  /new-feature            Start a new feature
                          (spec > plan > build > test > review)
  /bug-fix                Fix a bug with proof-first methodology
                          (reproduce > prove > fix > verify)

  LEARNING & DOCUMENTATION
  /learn                  Capture reusable patterns from this session
  /document-all           Full documentation + folder reorganization
  /evaluate-repo [URL]    Assess if a GitHub repo is useful
  /security-check         Run a full security audit right now

  KNOWLEDGE & GOVERNANCE
  /knowledge [mode]       Build and maintain the project's second brain
                          Modes: bootstrap, update, gaps, search <term>
  /constitution           Establish project principles and constraints
                          (runs once per project, or update existing)
  /review-drift           Check if code matches specs and decisions
                          (spec vs code alignment audit)

  AUDITS & REVIEWS
  /production-audit       Full 12-section production readiness assessment
                          (score 0-100, gap table, 90-day roadmap)
  /review-ui              Design quality review via UI/UX Engineer
                          (design system, accessibility, responsiveness)
  /framework-check        Verify the framework is installed correctly
                          (skills, agents, hooks, rules, tools)

  SKILL LIBRARY MANAGEMENT
  /curate                 Review skill library health (monthly)
                          (stale, low-usage, duplicates, missing structure)
  /lock-skill <name>      Mark a skill as user-authored (Curator can't edit)
  /unlock-skill <name>    Allow Curator to propose edits
  /pin-skill <name>       Protect a skill from deletion/retirement
  /unpin-skill <name>     Remove deletion protection

  SESSION MANAGEMENT
  /wrap-up                Save session state before closing
  /clear                  Full context reset (between unrelated tasks)
  /compact                Compress context (preserves key info)
  /rewind                 Undo to a previous checkpoint

  WHAT HAPPENS AUTOMATICALLY
  - Test verification    blocks "done" if tests fail (Stop hook)
  - Loop detection       warns after 3+ edits to same file (PostToolUse hook)
  - Session logging      records every tool use for metrics (PostToolUse hook)
  - Session metrics      shows tool count, edits, files at session end (Stop hook)
  - Bash guard           warns about long/chained commands (PreToolUse hook)
  - Config protection    blocks weakening linter/formatter configs (rule)
  - Fact-forcing         requires reading files before first edit (rule)
  - Identity reload      restores team identity after compaction (SessionStart hook)
  - Context monitoring   nudges when context gets heavy (~30 turns)
  - Learning nudge       suggests /learn after ~20 turns
  - Commit reminders     flags uncommitted changes piling up
  - Progress reporting   stage-by-stage updates for long tasks (rule)
  - Security checks      alerts on secrets in code (rule)
  - Capability gaps      stops and asks before installing tools (rule)
  - Skill telemetry     logs every skill invocation for /curate (PostToolUse hook)

  GRAPHIFY (codebase knowledge graph, if installed)
  /graphify .                Build or rebuild the knowledge graph
  /graphify . --update       Re-process only changed files
  /graphify query "..."      Query the graph directly
  /graphify path "A" "B"     Find path between two components
  /graphify explain "Node"   Explain a specific component
```

## Pitfalls

- This is a reference display — don't try to run commands from here
- Keep the list up to date when skills are added or removed

## Verification

- All installed skills are listed in the output
- Descriptions match what each skill actually does
