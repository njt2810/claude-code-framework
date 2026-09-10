# Claude Code Development Framework

A self-managing development workflow system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). One install gives every project: automated code review, security auditing, evidence-based bug fixing, session continuity, a learning system that gets better over time, and a self-grooming skill library that maintains itself.

## The Problem

Claude Code is powerful out of the box, but every session starts from scratch. There's no persistent team structure, no enforced quality gates, no memory of what worked last time, and no guardrails against the fix-break death spiral. You end up re-explaining your workflow, re-establishing conventions, and watching Claude silently retry the same failed approach three times.

This framework fixes all of that.

## How It Works

The framework installs globally at `~/.claude/` and activates in every Claude Code session. It works through five interlocking systems:

### 1. The Realm System (new in v2)

Claude Code loads `CLAUDE.md` by walking up the directory tree from wherever it's
opened — global, then every ancestor directory's `CLAUDE.md`, then the project's
own, merged root to leaf. v2 uses this to give you fully automatic, zero-config
context switching between separate areas of your work — "realms" — with **hard
segregation**: content from one realm never bleeds into another, and nothing needs
manual pointing to a hub folder.

Define a realm by creating two files at a folder that will act as its root:

```
<realm-root>/
├── AGENTS.md     ← portable content: what this realm is, its boundary.
│                   Cross-tool readable (Gemini CLI, Codex, etc. read this
│                   natively — Claude Code does not read AGENTS.md directly,
│                   see below).
└── CLAUDE.md     ← @AGENTS.md, then anything Claude-Code-specific: identity
                    overrides, delegation style, realm-specific rules.
```

Every project nested under that root inherits it automatically — open Claude Code
anywhere inside, and the realm's identity and rules are already active. Nothing to
remember, nothing to point at.

Register your realm roots in `~/.claude/realms.json` (gitignored — this is your
private map, ship only `realms.json.example`):

```json
{
  "personal": "C:\\Users\\you\\Documents\\Personal",
  "work": "C:\\Users\\you\\Documents\\Work",
  "client-acme": "C:\\Users\\you\\Documents\\Clients\\Acme"
}
```

Run `/adopt` in any project folder — it prefix-matches your cwd against
`realms.json`, applies the right realm with zero questions if it matches, and asks
once if it doesn't. `/adopt` replaces `/init-project`; it stamps a project without
copying agent or rule files, because the realm layer already covers them
automatically — everything else `/init-project` used to do (GitHub repo creation,
security audit, CI/CD setup, and for production-tier realms: branch protection,
compliance/legal doc scaffolding, audit-logging stubs, environment separation)
still happens, just resolved from the realm instead of a typed-in stream name.

Run `/context` any time to see exactly which `CLAUDE.md` files are active and in
what order — a transparency command for debugging conflicting instructions,
borrowed from a pattern in Google's Gemini CLI (`/memory show`).

**Why `AGENTS.md` + `CLAUDE.md`, not just `CLAUDE.md`:** Claude Code reads
`CLAUDE.md` only — `AGENTS.md` is invisible to it unless imported. But other
agentic tools (Gemini CLI, Codex, and 20+ others) read `AGENTS.md` natively. Putting
portable realm-boundary content in `AGENTS.md` and importing it via `@AGENTS.md`
from `CLAUDE.md` means your realm definition is readable by whatever tool you're
using that day, with nothing Claude-Code-specific lost.

**No realms.json yet?** `/adopt` still works — it just treats the project as a
one-off, not part of any realm, and asks a couple of the questions realm
resolution would otherwise answer automatically (GitHub destination,
production-tier status). You don't need to migrate everything to the realm
system at once.

**Caution — `--add-dir` can defeat realm segregation.** Claude Code's `--add-dir`
flag, combined with `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`, loads a
second directory's `CLAUDE.md` into the same session. Using it to add a folder
from a *different* realm than the one you opened Claude Code in loads both
realms' identity/rules simultaneously — exactly the mixing this system exists to
prevent. Worth knowing before you reach for it.

### 2. The Team System

Claude operates as a **Lead Engineer** with six always-on specialist subagents plus
one on-demand:

| Agent | Role | When Active |
|-------|------|-------------|
| **Code Reviewer** | Two-stage review (spec compliance → code quality) | After code changes, before merging |
| **Test Engineer** | QA + failure readiness | After implementation, for test design |
| **Wiki Updater** | Docs + operational docs | After decisions, major changes |
| **Security Auditor** | Security + supply chain | When code touches auth/payments/data |
| **Compliance Officer** | PDPA + SOC 2 — controls, vendor risk, legal docs | Production-tier projects + PII / auth / payment code |
| **Knowledge Agent** | Project second brain | Memory bootstrap, gap detection |
| **UI/UX Engineer** | Design quality (on-demand) | Only when explicitly requested |

The Lead Engineer orchestrates — it builds features, debugs problems, and makes
architecture decisions. But it **never reviews its own work**. After building, it
delegates to at least one specialist before shipping **by default** — skippable for
small, low-risk changes (typo fixes, single-line tweaks, comment-only edits); any
non-trivial change still delegates by default. (v2: softened from an unconditional
mandate, in line with Anthropic's own published guidance against unconditional
agentic overhead on every task, regardless of size — see "Design Philosophy.")

**"Lead Engineer" is the default persona, not a fixed one.** A realm's `CLAUDE.md`
can override the outward-facing identity/voice for everything under that realm
root — the team roster and delegation model stay the same either way, only how
Claude presents itself changes. Run `/context` any time to see which persona is
actually active and why.

The team identity persists through compactions and long sessions via reinforcement
layers: CLAUDE.md embedding, SessionStart hook injection (on startup and after
compaction, pointing at `/context` rather than hardcoding a persona — see the Hooks
System below), compaction preservation rules, session-monitor reinforcement, and
TEAM.md reference.

### 3. The Skills System (55 Slash Commands)

Skills are slash commands that encode workflows. They're not just prompts — they're structured procedures with trigger conditions, step-by-step instructions, known failure modes, and verification checks.

Every skill has four required sections:
- **When to Use** — trigger and anti-trigger conditions
- **Procedure** — the actual workflow steps
- **Pitfalls** — known failure modes and how to avoid them
- **Verification** — how to confirm the skill worked

**Realm system:**

| Command | What It Does |
|---------|-------------|
| `/adopt [realm-key]` | **v2** — realm-aware project onboarding: auto-detects realm from cwd via `realms.json`, stamps the project, never copies what the realm layer already covers. Full parity with what `/init-project` used to do (GitHub creation, security audit, CI/CD, production scaffolding) — just realm-aware instead of stream-hardcoded. Replaces `/init-project`. |
| `/context` | **v2** — show the fully resolved CLAUDE.md ancestor chain for the current directory; flags conflicting identity claims |

**Core workflows:**

| Command | What It Does |
|---------|-------------|
| `/init-project [stream]` | Legacy alias for `/adopt` — the `[stream]` argument is ignored, kept for muscle memory |
| `/upgrade-project` | Bring an existing project up to the installed framework (assess → archive → apply, never deletes) |
| `/feature [add\|list\|...]` | Lifecycle CRUD — capture features before building |
| `/new-feature` | Spec → plan → branch → build → test → PR (lifecycle-aware) |
| `/bug-fix` | Reproduce → failing test → fix → verify → PR |
| `/pr` | Push branch, pre-PR checks, create PR, delegate review |
| `/resume` | Restore session, surface unread notes + lifecycle pipeline + safety mode |
| `/note [text]` | Leave yourself a note — /resume announces unread notes first |
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

**Production setup (production-tier projects):**

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

**Compliance (production-tier projects):**

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
| `/learn` | Capture reusable patterns as new skills (v2: PROJECT / REALM / GLOBAL scope) |

**Skill library management:**

| Command | What It Does |
|---------|-------------|
| `/curate` | Skill library health review + wiki/log/decision staleness lint (v2), propose-only |
| `/lock-skill <name>` | Protect a skill from Curator edits |
| `/unlock-skill <name>` | Allow Curator to propose edits |
| `/pin-skill <name>` | Protect a skill from deletion |
| `/unpin-skill <name>` | Remove deletion protection |

See `CLAUDE.md` "Skill Workflow Guide" for the full when-to-run-what table.

### 4. The Hooks System (12 Automated Behaviors)

Hooks fire on Claude Code lifecycle events — session start, tool use, compaction, stop. They enforce quality without you having to remember to ask.

| Hook | When | What It Does |
|------|------|-------------|
| **Session Start** | Every session | Injects team roster, points to `/context` for resolved identity, suggests `/resume` |
| **Identity Reload** | After compaction | Re-injects team roster + context check, points to `/context` |
| **Bash Guard** | Before bash commands | Warns about chained/long commands |
| **Pre-Compact** | Before compaction | Backs up session state |
| **Verify Before Stop** | When Claude stops | Blocks if tests are failing — honors an explicit handoff marker so a skill's own deliberate stop (e.g. `/bug-fix` Step 6, handing control back to the user) isn't misread as a bug left unverified |
| **Loop Detector** | After file edits | Warns after 3+ edits to same file (death spiral detection) |
| **Session Monitor** | When Claude stops | Learning nudges, compaction nudges, commit reminders |
| **Session Summary** | When Claude stops | Shows tool use metrics |
| **Session Logger** | After every tool | Records tool use for observability |
| **Skill Telemetry** | After skill invocation | Logs usage to JSONL for `/curate` |
| **Post-Compact Check** | After compaction | Verifies critical context survived |
| **Identity Check** | When Claude stops | Checks subagent findings were attributed to the right agent — persona-agnostic, doesn't require a specific identity name |

**Neither hook that touches identity hardcodes a persona name.** Session Start and
Identity Reload both point at `/context` instead — a realm's `CLAUDE.md` can
override the default persona, and a hook has no way to know which realm (if any)
governs the directory it fires in. Hardcoding one persona name into a hook that
fires everywhere, regardless of realm, would silently fight any override.

### 5. The Rules System (10 Always-Loaded Rules)

Rules are loaded into every session and override default Claude behavior. They enforce invariants that should never be violated.

| Rule | What It Enforces |
|------|-----------------|
| **Security** | Never write secrets in code, never commit .env files, always validate input |
| **Capability Gaps** | Stop and ask before improvising when a tool is missing |
| **Skill Evolution** | Never modify framework files without explicit human approval (3-use graduation criterion for learned skills; v2 adds a REALM promotion tier alongside PROJECT/GLOBAL) |
| **Config Protection** | Never weaken linter/formatter config to make checks pass |
| **Fact-Forcing** | Investigate before editing unfamiliar files — no assumption-based edits |
| **PII Handling** | Never log PII; encrypt at rest; honor retention; never URL-param PII |
| **Change Management** | Production-tier projects (declared in your own `realms.json`/realm `CLAUDE.md`, not hardcoded by the framework): no direct commits to main, PR workflow required |
| **Secrets Management** | Secret manager for production, rotation discipline, no shared secrets cross-env |
| **Audit Everything** | Production-tier projects: state changes must be auditable |
| **Safety Modes** | Honor `/careful`, `/guard`, `/freeze` state in `.claude/state/mode.json` |

## Migrating from v1

1. `git pull` / reinstall via `install.bat` to get v2's files into `~/.claude/`.
2. Copy `realms.json.example` to `realms.json` and fill in your own realm roots —
   this file is gitignored and never overwritten by future updates.
3. For each realm root, create its `AGENTS.md` + `CLAUDE.md` pair (see "The Realm
   System" above). If you were relying on the old flat global identity for
   everything, you can start with one realm covering everything you have today, and
   split further later — nothing forces an immediate full migration.
4. Run `/adopt` once in each existing project — it detects realm membership and
   stamps the project without touching anything the realm layer now covers. Existing
   `.claude/agents/*.md` copies in your projects (a v1 pattern) are now redundant —
   delete them once you've confirmed `/context` resolves correctly without them.
5. Old `/init-project [stream]` invocations still work (alias), but prefer `/adopt`
   going forward.
6. No `realms.json` yet, or not ready to set one up? `/adopt` still works as a
   one-off project bootstrap — you don't have to adopt the realm system to keep
   using the rest of the framework.

## The Learning System

The framework learns from your work:

1. You build things normally
2. Every ~20 turns, a hook nudges: "Worth capturing a pattern? `/learn`"
3. `/learn` extracts the reusable pattern into a new skill — scoped to the
   project, its realm, or global, per how broadly it actually applies (v2)
4. Next time a similar task comes up, Claude uses the learned skill
5. Skills get refined each time they're used
6. After 3+ successful uses, `/wrap-up` can promote them to permanent

Learned skills start unlocked (the Curator can refine them). Hand-authored skills are locked by default. This lets the library evolve while protecting the core.

## The Self-Grooming System

Inspired by [Hermes Agent](https://github.com/NousResearch/Hermes-Function-Calling) (Nous Research), the framework maintains itself:

1. **Telemetry** — every skill invocation is logged to `logs/skill-usage.log` (JSONL). The `/curate` command reads this to know which skills are actually used vs. gathering dust.

2. **Locking & Pinning** — two independent protection levels. `user_locked: true` prevents the Curator from editing a skill. `pinned: true` prevents it from being retired. Core skills have both; learned skills start with neither.

3. **Structured Sections** — every skill must have When to Use, Procedure, Pitfalls, and Verification. This forces skills to think about failure modes, not just the happy path.

4. **The Curator** (`/curate`) — reads telemetry, scans the library, and produces a health report: stale skills, low-usage candidates, possible duplicates, missing structure — and (v2) stale wiki/log/decision content past its `review_date`, or aged with no recent activity. **Propose-only** — never auto-executes. Every change requires explicit per-item approval.

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
├── realms.json             ← Your private realm-root map (v2, gitignored)
├── realms.json.example     ← Template — copy to realms.json and fill in
├── skills/                ← 55 slash commands
│   ├── adopt/                 Realm-aware project onboarding (v2)
│   ├── context/               Resolved-identity transparency command (v2)
│   ├── init-project/          Legacy alias for adopt
│   ├── new-feature/          Each skill is a SKILL.md with frontmatter
│   ├── bug-fix/              (trigger conditions, locking, hooks)
│   ├── pr/                   and four required sections
│   ├── feature/              (When to Use, Procedure, Pitfalls, Verification)
│   ├── recommend/            Lead Engineer coaching
│   ├── careful/  guard/  freeze/  unfreeze/   Safety modes
│   ├── compliance-audit/  data-inventory/  legal-docs/   Compliance pack
│   ├── deploy/  release/  incident/  dr-plan/            Operations
│   ├── auth-setup/  billing-setup/  email-setup/         Business
│   └── ... (55 total)
├── agents/                ← 7 specialist subagent definitions
│   ├── code-reviewer.md      (two-stage review)
│   ├── test-engineer.md
│   ├── wiki-updater.md
│   ├── security-auditor.md
│   ├── compliance-officer.md (production-tier projects)
│   ├── knowledge-agent.md
│   ├── ui-ux-engineer.md     (on-demand)
│   └── team-builder.md / team-verifier.md
│                             2 more role definitions, not part of the
│                             general delegation team above — they're the
│                             framework-rebuild's own lead/builder/verifier
│                             delivery loop (see docs/rebuild/)
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
├── templates/             ← Used by /adopt
│   ├── SKILL-template.md    Standard 4-section skill template
│   ├── wiki/                Wiki page templates
│   ├── rules/               Scoped rule templates
│   ├── ci/                  CI/CD pipeline templates
│   ├── legal/                DPA, Privacy, ToS, Cookie (lawyer review)
│   ├── security-policies/   10 SOC 2 security policies
│   ├── compliance/          SOC 2 controls matrix, risk register, assets
│   ├── operations/           Deploy + rollback runbooks
│   └── vendor/               Security questionnaire template
└── scripts/               ← Utility scripts
    └── timed-run.sh

Each realm root you define (outside ~/.claude/, wherever your projects live):
<realm-root>/
├── AGENTS.md               ← Portable realm-boundary description
├── CLAUDE.md               ← @AGENTS.md + identity/rule overrides for this realm
└── .realm-skills/          ← (optional, v2) skills shared across this realm's
                               projects — synced into a project's .claude/skills/
                               by /adopt, never silently

When a project is adopted with /adopt, it ALSO creates:
{project}/
├── .claude/
│   ├── rules/              ← Project-scoped rules (with glob frontmatter)
│   ├── skills/learned/     ← Skills captured via /learn
│   └── state/mode.json     ← Safety mode state (careful/guard/freeze)
├── wiki/
│   ├── features/           ← Lifecycle tracking (BMAD-style)
│   │   ├── feat-001-*.md
│   │   └── _export.json    ← Dashboard export
│   ├── decisions/          ← ADRs
│   ├── logs/               ← Session logs
│   ├── compliance/         ← (production-tier) gaps, data inventory, evidence
│   ├── legal/               ← (production-tier) DPA, Privacy, ToS drafts
│   ├── operations/          ← (production-tier) deploy runbook, calendar
│   ├── clients/              ← (production-tier) per-client profiles
│   └── ...
└── ...

Note what's NOT copied into the project (v2, deliberate): .claude/agents/ and
TEAM.md. Global ~/.claude/agents/ and the realm-root's CLAUDE.md already cover
every project underneath them automatically — copying them in was the v1
mechanism that caused files to silently drift from their source over time.
```

**How data flows:**

```
Session Start
    │
    ├── CLAUDE.md loads (ancestor-walk: global → realm root → project)
    ├── SessionStart hook fires (team roster, points to /context, suggests /resume)
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

The installer copies all framework files to `%USERPROFILE%\.claude\`, creates the directory structure, drops in `realms.json.example` (never overwrites a real `realms.json`), initializes telemetry logs, and verifies that everything installed correctly.

## Quick Start

Optional but recommended — set up the realm system once:

```batch
copy %USERPROFILE%\.claude\realms.json.example %USERPROFILE%\.claude\realms.json
:: edit realms.json to point at your own folders
```

Then, for each realm root, create its `AGENTS.md` + `CLAUDE.md` pair (see "The
Realm System" above) — or skip this step entirely and just start adopting projects
as one-offs.

Open any project folder in Claude Code and type:

```
/adopt
```

Realm is auto-detected from `realms.json` — no argument needed. No `realms.json`
yet? `/adopt` still works, just asks a couple of questions realm resolution would
otherwise answer automatically.

Then type `/help` to see all available commands.

## Design Philosophy

- **You focus on building.** The framework manages itself.
- **Nothing happens without your approval.** Tools, skills, and changes need a "yes."
- **Evidence over speculation.** No guessing at bug fixes. Prove it first.
- **Learn from everything.** Every session is an opportunity to get better.
- **Always know what's happening.** Progress updates, not silence.
- **The human is always the gatekeeper.** The framework proposes, you decide.
- **Load only what's relevant.** (v2) Identity and rules are scoped to global,
  realm, and project layers rather than one flat always-on file — in line with
  Anthropic's own guidance that unconditional context is a cost, not a default
  virtue.
