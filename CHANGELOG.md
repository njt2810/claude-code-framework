# Changelog

All notable framework changes, newest first. The version is the `VERSION` file
(date-based). `/upgrade-project` uses this to explain what an older project
gains by upgrading.

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
