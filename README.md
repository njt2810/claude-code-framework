# Claude Code Development Framework

A self-managing development workflow system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). One install gives every project: automated code review, security auditing, evidence-based bug fixing, session continuity, a learning system that gets better over time, and a self-grooming skill library that maintains itself.

## The Problem

Claude Code is powerful out of the box, but every session starts from scratch. There's no persistent team structure, no enforced quality gates, no memory of what worked last time, and no guardrails against the fix-break death spiral. You end up re-explaining your workflow, re-establishing conventions, and watching Claude silently retry the same failed approach three times.

This framework fixes all of that.

## How It Works

The framework installs globally at `~/.claude/` and activates in every Claude Code session. It works through four interlocking systems:

### 1. The Team System

Claude operates as a **Lead Engineer** with six always-on specialist subagents plus one on-demand:

| Agent | Role | When Active |
|-------|------|-------------|
| **Code Reviewer** | Two-stage review (spec compliance → code quality) | After code changes, before merging |
| **Test Engineer** | QA + failure readiness | After implementation, for test design |
| **Wiki Updater** | Docs + operational docs | After decisions, major changes |
| **Security Auditor** | Security + supply chain | When code touches auth/payments/data |
| **Compliance Officer** | PDPA + SOC 2 — controls, vendor risk, legal docs | Production streams + PII / auth / payment code |
| **Knowledge Agent** | Project second brain | Memory bootstrap, gap detection |
| **UI/UX Engineer** | Design quality (on-demand) | Only when explicitly requested |

The Lead Engineer orchestrates — it builds features, debugs problems, and makes architecture decisions. But it **never reviews its own work**. After building, it always delegates to at least one specialist before shipping. This separation of concerns is the core quality mechanism.

The team identity persists through compactions and long sessions via six reinforcement layers: CLAUDE.md embedding, SessionStart hook injection, InstructionsLoaded reload, compaction preservation rules, session-monitor backup, and TEAM.md reference.

### 2. The Skills System (51 Slash Commands)

Skills are slash commands that encode workflows. They're not just prompts — they're structured procedures with trigger conditions, step-by-step instructions, known failure modes, and verification checks.

Every skill has four required sections:
- **When to Use** — trigger and anti-trigger conditions
- **Procedure** — the actual workflow steps
- **Pitfalls** — known failure modes and how to avoid them
- **Verification** — how to confirm the skill worked

**Core workflows:**

| Command | What It Does |
|---------|-------------|
| `/init-project [stream]` | Bootstrap a project (stream-aware production scope) |
| `/feature [add\|list\|...]` | Lifecycle CRUD — capture features before building |
| `/new-feature` | Spec → plan → branch → build → test → PR (lifecycle-aware) |
| `/bug-fix` | Reproduce → failing test → fix → verify → PR |
| `/pr` | Push branch, pre-PR checks, create PR, delegate review |
| `/resume` | Restore session, surface lifecycle pipeline + safety mode |
| `/wrap-up` | Save state + delegate to Wiki/Knowledge + auto-update lifecycle |
| `/status` | Project snapshot + feature pipeline + compliance summary |
| `/recommend` | Lead Engineer coaches prioritized next actions |

**Engineering hygiene:**

| Command | What It Does |
|---------|-------------|
| `/migration` | Safe DB schema changes — SAFE/RISKY/DESTRUCTIVE classification |
| `/api-contract` | OpenAPI/GraphQL contract — breaking change detection |
| `/add-rule` | Add project-scoped rule with glob frontmatter |

**Safety modes (situational risk control):**

| Command | What It Does |
|---------|-------------|
| `/careful` | Risky work — auto-delegate reviewers, 1-attempt limit |
| `/guard` | Critical systems — explicit yes per step, snapshot first |
| `/freeze` | Read-only on scoped paths — audit/investigate mode |
| `/unfreeze` | Return to normal mode |

**Production setup (production streams):**

| Command | What It Does |
|---------|-------------|
| `/env-setup` | Dev/staging/prod separation + secret manager |
| `/observability-setup` | Error tracking + logs + metrics + alerts |
| `/audit-logging-setup` | SOC 2 evidence collection from day 1 |
| `/auth-setup` | Pick managed auth provider |
| `/billing-setup` | Pick payment provider (MoR for international) |
| `/email-setup` | Transactional + marketing email + DNS |
| `/dr-plan` | Backup strategy + restore drill schedule |

**Operations:**

| Command | What It Does |
|---------|-------------|
| `/deploy [env]` | Deploy with all gates (tests/lint/migrations/compliance) |
| `/release [bump]` | Semver + changelog + tag + GitHub Release |
| `/feature-flag` | Gradual rollout / kill switch / A/B testing |
| `/incident` | Production down — structured response |
| `/triage` | Customer ticket → classify → respond → log |
| `/onboard-client` | New client provisioning + kickoff + calendar |
| `/timer [start\|stop\|status\|...]` | Track billable hours per client with auto-captured git evidence |

**Compliance (production streams):**

| Command | What It Does |
|---------|-------------|
| `/compliance-audit` | PDPA + SOC 2 gap analysis |
| `/compliance-status` | Lightweight compliance dashboard |
| `/data-inventory` | Map every PII flow |
| `/legal-docs` | Draft DPA / Privacy Policy / ToS (lawyer review required) |
| `/vendor-review` | Inbound vendor assessments + outbound questionnaire responses |

**Quality & auditing:**

| Command | What It Does |
|---------|-------------|
| `/security-check` | Full security audit via Security Auditor |
| `/production-audit` | 12-section production readiness assessment |
| `/review-ui` | Design quality review via UI/UX Engineer |
| `/review-drift` | Spec vs code alignment audit |
| `/constitution` | Establish project principles and constraints |
| `/evaluate-repo [URL]` | Assess any GitHub repository |
| `/framework-check` | Verify framework installation health |

**Knowledge & documentation:**

| Command | What It Does |
|---------|-------------|
| `/knowledge [mode]` | Build and maintain project second brain |
| `/document-all` | Full documentation sweep |
| `/learn` | Capture reusable patterns as new skills |

**Skill library management:**

| Command | What It Does |
|---------|-------------|
| `/curate` | Monthly skill library health review (propose-only) |
| `/lock-skill <name>` | Protect a skill from Curator edits |
| `/unlock-skill <name>` | Allow Curator to propose edits |
| `/pin-skill <name>` | Protect a skill from deletion |
| `/unpin-skill <name>` | Remove deletion protection |

See `CLAUDE.md` "Skill Workflow Guide" for the full when-to-run-what table.

### 3. The Hooks System (12 Automated Behaviors)

Hooks fire on Claude Code lifecycle events — session start, tool use, compaction, stop. They enforce quality without you having to remember to ask.

| Hook | When | What It Does |
|------|------|-------------|
| **Session Start** | Every session | Injects team identity, suggests `/resume` |
| **Identity Reload** | After compaction | Re-injects Lead Engineer identity and team roster |
| **Bash Guard** | Before bash commands | Warns about chained/long commands |
| **Pre-Compact** | Before compaction | Backs up session state |
| **Verify Before Stop** | When Claude stops | Blocks if tests are failing |
| **Loop Detector** | After file edits | Warns after 3+ edits to same file (death spiral detection) |
| **Session Monitor** | When Claude stops | Learning nudges, compaction nudges, commit reminders |
| **Session Summary** | When Claude stops | Shows tool use metrics |
| **Session Logger** | After every tool | Records tool use for observability |
| **Skill Telemetry** | After skill invocation | Logs usage to JSONL for `/curate` |
| **Post-Compact Check** | After compaction | Verifies critical context survived |
| **Identity Check** | When Claude stops | Semantic check that agent findings are attributed |

### 4. The Rules System (10 Always-Loaded Rules)

Rules are loaded into every session and override default Claude behavior. They enforce invariants that should never be violated.

| Rule | What It Enforces |
|------|-----------------|
| **Security** | Never write secrets in code, never commit .env files, always validate input |
| **Capability Gaps** | Stop and ask before improvising when a tool is missing |
| **Skill Evolution** | Never modify framework files without explicit human approval (3-use graduation criterion for learned skills) |
| **Config Protection** | Never weaken linter/formatter config to make checks pass |
| **Fact-Forcing** | Investigate before editing unfamiliar files — no assumption-based edits |
| **PII Handling** | Never log PII; encrypt at rest; honor retention; never URL-param PII |
| **Change Management** | Production streams: no direct commits to main, PR workflow required |
| **Secrets Management** | Secret manager for production, rotation discipline, no shared secrets cross-env |
| **Audit Everything** | Production streams: state changes must be auditable |
| **Safety Modes** | Honor `/careful`, `/guard`, `/freeze` state in `.claude/state/mode.json` |

## The Learning System

The framework learns from your work:

1. You build things normally
2. Every ~20 turns, a hook nudges: "Worth capturing a pattern? `/learn`"
3. `/learn` extracts the reusable pattern into a new skill
4. Next time a similar task comes up, Claude uses the learned skill
5. Skills get refined each time they're used
6. After 3+ successful uses, `/wrap-up` can promote them to permanent

Learned skills start unlocked (the Curator can refine them). Hand-authored skills are locked by default. This lets the library evolve while protecting the core.

## The Self-Grooming System

Inspired by [Hermes Agent](https://github.com/NousResearch/Hermes-Function-Calling) (Nous Research), the framework maintains itself:

1. **Telemetry** — every skill invocation is logged to `logs/skill-usage.log` (JSONL). The `/curate` command reads this to know which skills are actually used vs. gathering dust.

2. **Locking & Pinning** — two independent protection levels. `user_locked: true` prevents the Curator from editing a skill. `pinned: true` prevents it from being retired. Core skills have both; learned skills start with neither.

3. **Structured Sections** — every skill must have When to Use, Procedure, Pitfalls, and Verification. This forces skills to think about failure modes, not just the happy path.

4. **The Curator** (`/curate`) — reads telemetry, scans the library, and produces a health report: stale skills, low-usage candidates, possible duplicates, missing structure. **Propose-only** — never auto-executes. Every change requires explicit per-item approval.

## The Bug Fix Methodology

The `/bug-fix` skill enforces an evidence-based workflow that prevents the fix-break death spiral:

```
UNDERSTAND → REPRODUCE → PROVE (failing test) → FIX (minimal) → VERIFY → DOCUMENT
```

Key constraints:
- Cannot proceed to fixing without a failing test that proves the bug
- Fix must be the smallest possible change — one thing only
- Full test suite must pass after the fix (no new regressions)
- After 2 failed attempts: stop, report what was tried, and ask for direction
- After 3+ edits to the same file: automatic red flag and reassessment
- Never say "I've fixed it" without showing passing test output

## Architecture

```
~/.claude/
├── CLAUDE.md              ← Global rules + Skill Workflow Guide
├── TEAM.md                ← Team structure, delegation rules, identity
├── settings.json          ← Hook configuration (12 hooks)
├── skills/                ← 51 slash commands
│   ├── init-project/         Each skill is a SKILL.md with frontmatter
│   ├── new-feature/          (trigger conditions, locking, hooks)
│   ├── bug-fix/              and four required sections
│   ├── pr/                   (When to Use, Procedure, Pitfalls, Verification)
│   ├── feature/              Lifecycle CRUD
│   ├── recommend/            Lead Engineer coaching
│   ├── careful/  guard/  freeze/  unfreeze/   Safety modes
│   ├── compliance-audit/  data-inventory/  legal-docs/   Compliance pack
│   ├── deploy/  release/  incident/  dr-plan/            Operations
│   ├── auth-setup/  billing-setup/  email-setup/         Business
│   └── ... (51 total)
├── agents/                ← 7 specialist subagent definitions
│   ├── code-reviewer.md      (two-stage review)
│   ├── test-engineer.md
│   ├── wiki-updater.md
│   ├── security-auditor.md
│   ├── compliance-officer.md (production streams)
│   ├── knowledge-agent.md
│   └── ui-ux-engineer.md     (on-demand)
├── rules/                 ← 10 always-loaded behavioral rules
│   ├── security.md
│   ├── capability-gaps.md
│   ├── skill-evolution.md
│   ├── config-protection.md
│   ├── fact-forcing.md
│   ├── pii-handling.md
│   ├── change-management.md
│   ├── secrets-management.md
│   ├── audit-everything.md
│   └── safety-modes.md
├── hooks/scripts/         ← 12 hook scripts (bash)
│   ├── session-start.sh
│   ├── bash-guard.sh
│   ├── verify-before-stop.sh
│   ├── loop-detector.sh
│   ├── skill-telemetry.sh
│   └── ... (12 total)
├── logs/                  ← Telemetry data
│   └── skill-usage.log      JSONL skill invocation log
├── templates/             ← Used by /init-project
│   ├── SKILL-template.md    Standard 4-section skill template
│   ├── wiki/                Wiki page templates
│   ├── rules/               Scoped rule templates
│   ├── ci/                  CI/CD pipeline templates
│   ├── legal/               DPA, Privacy, ToS, Cookie (lawyer review)
│   ├── security-policies/   10 SOC 2 security policies
│   ├── compliance/          SOC 2 controls matrix, risk register, assets
│   ├── operations/          Deploy + rollback runbooks
│   └── vendor/              Security questionnaire template
└── scripts/               ← Utility scripts
    └── timed-run.sh

When a project is initialized with /init-project, it ALSO creates:
{project}/
├── .claude/
│   ├── agents/             ← Project-local copies of agents
│   ├── rules/              ← Project-scoped rules (with glob frontmatter)
│   ├── skills/learned/     ← Skills captured via /learn
│   └── state/mode.json     ← Safety mode state (careful/guard/freeze)
├── wiki/
│   ├── features/           ← Lifecycle tracking (BMAD-style)
│   │   ├── feat-001-*.md
│   │   └── _export.json    ← Dashboard export
│   ├── decisions/          ← ADRs
│   ├── logs/               ← Session logs
│   ├── compliance/         ← (production) gaps, data inventory, evidence
│   ├── legal/              ← (production) DPA, Privacy, ToS drafts
│   ├── operations/         ← (production) deploy runbook, calendar
│   ├── clients/            ← (production) per-client profiles
│   └── ...
└── ...
```

**How data flows:**

```
Session Start
    │
    ├── CLAUDE.md loads (identity, rules, team structure)
    ├── SessionStart hook fires (reinforces identity, suggests /resume)
    ├── Rules load (security, fact-forcing, config protection, etc.)
    │
    ▼
Normal Work (you type, Claude builds)
    │
    ├── Every tool call → session-logger.sh records it
    ├── Every bash command → bash-guard.sh checks for risks
    ├── Every file edit → loop-detector.sh watches for death spirals
    ├── Every skill invocation → skill-telemetry.sh logs usage
    │
    ▼
Quality Gates (automatic)
    │
    ├── /new-feature → delegates to Test Engineer, Code Reviewer, etc.
    ├── /bug-fix → enforces reproduce → prove → fix → verify cycle
    ├── verify-before-stop.sh → blocks if tests are failing
    ├── session-monitor.sh → learning nudges, commit reminders
    │
    ▼
Session End
    │
    ├── /wrap-up saves state, graduates skills, reminds to commit
    ├── session-summary.sh shows tool use metrics
    └── session-end reminder if you forget /wrap-up
```

## Requirements

- **Windows** with [Git for Windows](https://git-scm.com/download/win) installed (provides bash for hooks)
- **Claude Code** CLI, desktop app, or web app
- Git must be available on PATH

## Installation

```batch
git clone https://github.com/<your-username>/claude-code-framework.git
cd claude-code-framework
install.bat
```

The installer copies all framework files to `%USERPROFILE%\.claude\`, creates the directory structure, initializes telemetry logs, and verifies that everything installed correctly.

## Quick Start

Open any project folder in Claude Code and type:

```
/init-project personal     ← your own projects
/init-project learning     ← experiments (minimal setup)
```

Then type `/help` to see all available commands.

## Design Philosophy

- **You focus on building.** The framework manages itself.
- **Nothing happens without your approval.** Tools, skills, and changes need a "yes."
- **Evidence over speculation.** No guessing at bug fixes. Prove it first.
- **Learn from everything.** Every session is an opportunity to get better.
- **Always know what's happening.** Progress updates, not silence.
- **The human is always the gatekeeper.** The framework proposes, you decide.
