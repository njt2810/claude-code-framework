# Changelog

All notable framework changes, newest first. The version is the `VERSION` file.
Releases before 2.0.0 used a date-stamp convention; from 2.0.0 onward the
project uses semver — this release is a real architecture break (the v2 Realm
System), not a routine update, and semver signals that unambiguously.
`/upgrade-project` uses this file to explain what an older project gains by
upgrading.

## 2.0.0 — The Realm System

**Breaking changes**

- **New: the Realm System.** Define a `<realm-root>/AGENTS.md` +
  `<realm-root>/CLAUDE.md` pair anywhere in your folder tree, register it in
  `~/.claude/realms.json` (gitignored, ships as `realms.json.example`), and
  every project nested under that root automatically inherits its identity
  and rules via Claude Code's native `CLAUDE.md` ancestor-walk — no manual
  pointing, no per-project copies. See the README's "The Realm System"
  section and "Migrating from v1" for the upgrade path.
- **`/adopt` replaces `/init-project`.** Same functional coverage (GitHub repo
  creation, security audit, CI/CD setup, and — for production-tier realms —
  branch protection, compliance/legal doc scaffolding, audit-logging stubs,
  environment separation), but realm-aware instead of stream-hardcoded, and
  it no longer copies agent definitions or `TEAM.md` into the project — the
  global `~/.claude/agents/` and the realm-root `CLAUDE.md` already cover
  every project automatically, and copying them was the exact mechanism that
  let files silently drift from their source in v1. `/init-project` still
  works as a thin alias; the `[stream]` argument is now ignored.
- **New: `/context`.** Shows the fully resolved `CLAUDE.md` ancestor chain for
  the current directory and flags conflicting identity claims — modeled on
  Gemini CLI's `/memory show`. Two hooks now depend on it: Session Start and
  Identity Reload no longer hardcode a persona name (previously always
  "Lead Engineer," which would have silently fought any realm-level identity
  override) — they point at `/context` instead. The Identity Check stop-hook
  now checks that subagent findings are attributed to an agent, without
  requiring a specific persona name.
- **`/curate` extended with a wiki/log/decision staleness lint.** Reuses the
  `review_date` frontmatter pattern; flags past-due `review_date` fields and
  stale wiki/decision files with no recent activity. Same propose-only,
  no-batch-approval discipline as the rest of `/curate`.
- **`/learn` and skill graduation gain a REALM tier.** Learned skills can now
  live at `<realm-root>\.realm-skills\` — between project-local and global —
  synced into a project's `.claude/skills/` by `/adopt`, never silently.
- **Removed: the Mission Control dashboard spec** (`docs/DASHBOARD-SPEC.md`,
  `docs/mockups/`). It was never built, and sat in tension with the
  framework's own native-first design principle (a bespoke registry +
  collector server + API + UI, where existing tools would do). Deleted, not
  archived — the git history still has it if it's ever needed again. The
  underlying idea isn't dead — it's being pursued as a project-specific
  initiative outside the framework's scope.
- **Delegation softened.** "Always delegate to at least one specialist before
  shipping" is now a default, skippable for small/low-risk changes (typo
  fixes, single-line tweaks, comment-only edits). Non-trivial changes still
  delegate by default. In line with Anthropic's own published guidance
  against unconditional agentic overhead on every task regardless of size.
- **Genericized:** `change-management.md`, `audit-everything.md`, and
  `compliance-officer.md` no longer hardcode example stream names
  (`org1`, `org2`, `personal-with-production-flag`). Production-tier status
  now comes from a realm's own `CLAUDE.md` declaration, or a per-project
  self-declaration via `/adopt` — never baked into the framework itself.
  Several other skills (`status`, `upgrade-project`, `wrap-up`,
  `compliance-status`, `recommend`, `release`, and the `PROJECT_STATUS.md`
  template) had the same hardcoded stream-name pattern and were updated for
  consistency. Cost/time tracking (previously gated on stream name) is now a
  simple per-project opt-in, asked once on first `/wrap-up`.

**Migration:** see the README's "Migrating from v1" section. Existing
projects keep working unchanged; realm adoption is opt-in and incremental —
`/adopt` still works as a one-off project bootstrap with no `realms.json` at
all.

## 2026.07.19

**Reliability: the framework now tests itself**
- CI pipeline (`.github/workflows/ci.yml` + `scripts/ci-checks.sh`): shell syntax,
  shellcheck, settings.json validation, hook-event whitelist, count consistency,
  and a personal-identifier scrub gate (patterns via `SCRUB_PATTERNS` secret /
  gitignored `.scrub-patterns` — never committed)
- Hook smoke tests (`tests/hooks-smoke.sh`, 23 assertions) — every hook is piped
  fake payloads and asserted; covers all regressions fixed in this release

**Fixed (silent no-ops, some broken since introduction)**
- loop-detector: read file_path from stdin JSON (was reading a nonexistent env var)
- session-monitor / verify-before-stop / pre-compact: state keyed by session_id,
  not PID — counters and nudges actually persist now
- verify-before-stop: `grep -P` → POSIX `grep -E` (`-P` fails on Git Bash)
- statusline: jq-missing fallback, 3s timeout on `gh pr view`, single jq call for
  timer fields, no epoch-0 duration garbage, explicit exit 0
- settings.json: removed nonexistent hook events (InstructionsLoaded, PostCompact,
  StopFailure); removed unverified model pin; bug-fix's duplicate loop-detector
  hook dropped
- skill-telemetry: set -e no longer kills the script on missing skill key
- session-logger: 10MB log rotation + JSON escaping (embedded quotes can't corrupt
  the log); same escaping in skill-telemetry

**Learned skills: project-local by default**
- /learn asks project-vs-global at save time; default is the project's
  `.claude/skills/learned/`
- /curate scans both scopes; new MISFILED SCOPE finding with relocate action
- Graduation (skill-evolution, wrap-up) never crosses scope

**New**
- /upgrade-project (52nd skill): assess → report → archive to `.archive/{date}/`
  (never delete) → apply → /resume; VERSION file + `.claude/framework-version`
  stamping via /init-project
- timer.sh helper: /timer state math is now deterministic code, not model-written
  JSON — billing records can't be miscalculated
- /note (53rd skill): leave yourself a note in `wiki/notes/inbox.md`; /resume
  announces unread notes FIRST, then marks them seen
- Mission Control dashboard: approved design mockups in `docs/mockups/` and full
  build spec in `docs/DASHBOARD-SPEC.md` (companion server, Clockify-style
  tracker driving timer.sh, printable client statement) — spec'd, not yet built

**Hygiene**
- Dead `effort:`/`shell:` frontmatter keys removed from all skills
- /graphify clearly marked as an optional external add-on
- Rule dedup: secrets-management no longer restates security.md;
  skill-evolution points to capability-gaps for tool installs
- Identity injection trimmed (pre-compact no longer duplicates the SessionStart
  compact reload); team roster unified to 6 always-on + 1 on-demand everywhere

## 2026.06.29

- /timer skill for client billable time tracking (git evidence + notes,
  hours-only reports)
- Statusline rewritten in plain English for operators (stream-aware, only shows
  problems)
- Lifecycle tracking (/feature), coaching (/recommend), safety modes
  (/careful /guard /freeze /unfreeze), Lead Engineer workflow guide
- Major rework to production-grade SaaS framework: compliance pack, operations
  pack, SaaS business pack, onboarding, 51 skills total

## 2026.06.10

- Initial public release (v3): 50 skills, 7 agents, 10 rules, 12 hooks,
  templates, install.bat; personal details scrubbed to org1/org2 placeholders
