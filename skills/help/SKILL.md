---
name: help
description: |
  TRIGGER when: the user says help, needs a command reference, is unsure what to do next,
  or asks what commands are available.
  DO NOT TRIGGER when: the user wants status (/status), to resume (/resume), or
  coached recommendations (/recommend — better for "what should I do next").
disable-model-invocation: true
user_locked: true
---

# Framework Command Reference

## When to Use

When the user needs a command reference, is unsure what's available, or wants
a quick lookup. For coached "what should I do next" guidance, use `/recommend`
instead — it scans project state and prioritizes.

## Procedure

Display this reference to the user:

```
YOUR COMMAND REFERENCE — 53 skills, 6 always-on + 1 on-demand agents

STARTING & RESUMING
  /init-project [stream]  Bootstrap a new or existing project
  /upgrade-project        Bring an initialized project up to the installed
                          framework (assess, archive old files, never delete)
  /note [text]            Leave yourself a note — /resume announces unread
                          notes first, then marks them seen
                          Streams: personal, org1, org2, learning
                          Production scope auto-applied to org1/org2
  /resume                 Pick up where you left off (lifecycle-aware)
  /status                 Snapshot of project state + feature pipeline
  /recommend              Lead Engineer coaches you on next actions

BUILDING — features and bugs
  /feature [add|list|...] Lifecycle CRUD (capture before building)
  /new-feature            Spec > plan > branch > build > test > PR
                          (auto-updates feature lifecycle)
  /bug-fix                Reproduce > prove > fix > verify > PR
                          (auto-updates lifecycle)
  /pr                     Push branch, pre-PR checks, create PR,
                          delegate to Code Reviewer
  /migration              Safe DB schema changes (SAFE/RISKY/DESTRUCTIVE
                          classification + expand-contract pattern)
  /api-contract           OpenAPI/GraphQL contract management
                          (breaking change detection, SDK gen)
  /add-rule               Add a project-scoped rule with glob pattern

SAFETY MODES — situational risk control
  /careful                Risky work (auth/payments/migrations)
                          adds reviews + 1-attempt limit + smoke tests
  /guard                  Critical systems (keys/IAM/webhooks)
                          explicit yes per step + snapshot first
  /freeze                 Read-only on scoped paths (audit mode)
  /unfreeze               Return to normal mode

PRODUCTION SETUP (production streams)
  /env-setup              Dev/staging/prod separation + secret manager
  /observability-setup    Error tracking + logs + metrics + alerts
  /audit-logging-setup    SOC 2 evidence collection from day 1
  /auth-setup             Pick managed auth provider (don't DIY)
  /billing-setup          Pick payment provider (MoR for international)
  /email-setup            Transactional + marketing email + DNS
  /dr-plan                Backup strategy + restore drill schedule

OPERATIONS
  /deploy [env]           Deploy with all gates (tests/lint/migrations/
                          compliance/secrets)
  /release [bump]         Semver + changelog + tag + GitHub Release
  /feature-flag           Gradual rollout / kill switch / A/B testing
  /incident               Production down — structured response
  /triage                 Customer ticket > classify > respond > log
  /onboard-client         New client provisioning + kickoff + calendar
  /timer [start|stop|...] Track billable hours per client with auto-captured
                          git evidence — for client work only, not internal

COMPLIANCE (production streams)
  /compliance-audit       PDPA + SOC 2 gap analysis
  /compliance-status      Lightweight compliance dashboard
  /data-inventory         Map every PII flow in the codebase
  /legal-docs             Draft DPA / Privacy Policy / ToS / Cookie
  /vendor-review          Inbound + outbound vendor questionnaires

KNOWLEDGE & DOCUMENTATION
  /knowledge [mode]       Build the project's second brain
                          Modes: bootstrap, update, gaps, search
  /constitution           Project principles and constraints
  /review-drift           Spec vs code alignment audit
  /document-all           Full documentation sweep
  /evaluate-repo [URL]    Assess if a GitHub repo is useful
  /learn                  Capture reusable patterns from this session

AUDITS & REVIEWS
  /security-check         Full security audit (Security Auditor)
  /production-audit       12-section production readiness (all agents)
  /review-ui              Design quality review (UI/UX Engineer)
  /framework-check        Verify framework installation health

SKILL LIBRARY MANAGEMENT
  /curate                 Monthly skill library health review
  /lock-skill <name>      Protect a skill from Curator edits
  /unlock-skill <name>    Allow Curator to propose edits
  /pin-skill <name>       Protect a skill from deletion
  /unpin-skill <name>     Remove deletion protection

SESSION MANAGEMENT
  /wrap-up                Save state, delegate to Wiki + Knowledge agents,
                          auto-update lifecycle, top 3 recommendations
  /clear                  Full context reset (between unrelated tasks)
  /compact                Compress context (preserves key info)
  /rewind                 Undo to a previous checkpoint
  /help                   This reference

WHAT HAPPENS AUTOMATICALLY (hooks + 10 rules)
  Hooks:
  - SessionStart      Injects team identity, suggests /resume
  - Identity reload   Re-injects identity + context check after compaction
  - Bash guard        Warns about chained/long commands
  - Pre-compact       Backs up session state
  - Verify before stop  Blocks if tests are failing
  - Loop detector     Warns after 3+ edits to same file
  - Session monitor   Learning + commit + compaction nudges
  - Session summary   Tool use metrics at session end
  - Session logger    Records every tool use
  - Skill telemetry   Logs skill invocations for /curate
  - Identity check    Blocks stop if agent findings unattributed
  - Statusline        Plain-English status bar (project, timer, git, PRs)
  - Idle + session-end reminders (inline in settings.json)

  Always-loaded rules:
  - security          No secrets, .env, PII in logs
  - capability-gaps   Stop before installing unfamiliar tools
  - skill-evolution   Never modify framework without approval
  - config-protection No weakening linter to make CI pass
  - fact-forcing      Read file before first edit
  - pii-handling      PII handling discipline (production)
  - change-management PR-based workflow on main (production)
  - secrets-management Secret rotation and storage rules
  - audit-everything  State-change audit logging (production)
  - safety-modes      Honor /careful, /guard, /freeze state

GRAPHIFY (codebase knowledge graph, if installed)
  /graphify .                Build or rebuild the knowledge graph
  /graphify . --update       Re-process only changed files
  /graphify query "..."      Query the graph directly
  /graphify path "A" "B"     Find path between two components
  /graphify explain "Node"   Explain a specific component

QUICK DECISION TREE
  Starting a session?            → /resume then /recommend
  Remember something next time?  → /note "text" (surfaces at next /resume)
  Framework updated since init?  → /upgrade-project (archives, never deletes)
  What's next?                   → /recommend
  What's the project state?      → /status
  Want to build X?               → /feature add then /new-feature
  Something broken (small)?      → /bug-fix
  Production down?               → /incident
  Customer asked for X?          → /triage
  About to touch risky code?     → /careful first
  About to rotate keys / IAM?    → /guard first
  Need to onboard a client?      → /onboard-client
  Client sent us a questionnaire?→ /vendor-review (outbound)
  Starting client billable work? → /timer start (then work normally)
  Finished client billable work? → /timer stop (logs evidence + duration)

See CLAUDE.md "Skill Workflow Guide" for the full when-to-run-what table
organized by project phase.
```

## Pitfalls

- This is a reference display — don't try to run commands from here
- Keep the list up to date when skills are added or removed
- For "what should I do" questions, prefer /recommend (it's coached + prioritized)

## Verification

- All 53 installed skills are listed
- Each section grouping is logical
- Quick decision tree at the bottom resolves common questions
- Skills the user might not know about are surfaced
