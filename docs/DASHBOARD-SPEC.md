# Mission Control — Build Specification

_Status: SPEC — approved design, not yet built. Written 2026-07-19 after two
mockup iterations. The notes pipeline (/note + /resume integration) shipped
separately and is NOT part of this spec._

## What this is

A local, single-user operations dashboard for all framework-managed projects:
portfolio overview, Clockify-style live time tracker, kanban board, personal
notes, costs, docs browser, and graphify embed — plus a printable client
"Statement of Work Performed."

Design reference (approved mockups, sample data): `docs/mockups/dashboard-mockup.html`
and `docs/mockups/timer-report-mockup.html`. The build must match these unless a
finding during implementation forces a change — record any deviation in this file.

## Architecture

**One small local companion server + generated static assets. No cloud, no auth,
localhost only.**

```
/dashboard (skill)
   └─ starts companion server (single-file Node, zero npm dependencies)
        ├─ serves the dashboard UI (the mockup, made data-driven)
        ├─ GET  /api/state            → aggregated read model (see Collectors)
        ├─ POST /api/timer/start|stop|pause|resume
        │        └─ shells out to ~/.claude/hooks/scripts/timer.sh  ← SINGLE WRITER
        ├─ POST /api/notes            → append to wiki/notes/inbox.md (same format as /note)
        └─ GET  /api/doc?path=…       → raw markdown of a whitelisted wiki file
```

### Non-negotiable rules

1. **timer.sh is the only writer of timer.json.** The server never writes timer
   state itself — it shells to the script. The /timer skill, the statusline, and
   the dashboard therefore can never disagree.
2. **Files are the source of truth.** The server holds no state of its own; every
   GET re-reads from disk. No database, no cache files.
3. **Localhost binding only** (`127.0.0.1`), random-ish port printed by /dashboard.
   Never expose; no auth is the tradeoff and it is only acceptable local-only.
4. **Doc endpoint is whitelisted** to `wiki/**` and refuses path traversal
   (resolve + prefix check).
5. **Node stdlib only** (http, fs, path, child_process). No npm install step.

## Project registry (prerequisite)

`~/.claude/projects.json` — the list of framework projects; nothing else in the
framework records "all my projects."

```json
{ "projects": [
  { "path": "C:/…/client-analytics", "stream": "org1", "registered": "2026-07-20" }
] }
```

- `/init-project` appends on init (dedupe by path)
- `/upgrade-project` appends if missing (backfills old projects)
- Collector skips entries whose path no longer exists (report, don't crash)

## Collectors — what each panel reads

| Panel | Reads |
|---|---|
| Portfolio card | `.claude/framework-version`, `.claude/state/mode.json`, `.claude/state/timer.json`, git (branch, dirty count, last commit date), `wiki/compliance/gaps.md` (unchecked count) |
| Briefing (Overview) | Derived from portfolio + attention data — worst items rendered as plain-English sentences with severity underlines (see mockup) |
| Tracker | `.claude/state/timer.json` (live), `wiki/clients/*/time-log.md` (entries, day/week rollups) |
| Board | `wiki/features/*.md` frontmatter (status, dates, branch); aging = in-progress > 7 days |
| Notes | `wiki/notes/inbox.md` (+ global `~/.claude/notes/inbox.md`) |
| Costs | `wiki/logs/cost-time-log.md`, `project-costs.json` |
| Docs | `wiki/**` tree + file content via /api/doc |
| Graph | `graphify-out/GRAPH_REPORT.html` if present (iframe); else show build command |

## Tracker behavior (Clockify-parity requirements)

- Clock ticks client-side from `started_at` + `accumulated_seconds` (already the
  timer.sh model); server polled every ~15s to catch out-of-band changes (e.g.
  /timer stop in a Claude session while the dashboard is open)
- Start requires description + client + type — same fields /timer asks for;
  POST /api/timer/start passes them straight through to `timer.sh start`
- Stop appends the time-log entry **with git evidence**: the server runs
  `git diff --stat` / `git log --oneline` from `starting_commit` (mirrors
  /timer stop step 3) and writes the same entry format as the skill
- Rail shows a pulsing indicator while running (mockup behavior)
- Pause/resume map 1:1 to timer.sh subcommands

## Statement generator

`/timer report --client X` gains `--html`: renders the statement template
(mockup 2) with real data to `wiki/clients/{client}/reports/{YYYY-MM}.html`
alongside the existing markdown. Fixed rules from the design review:

- Period label derives from generation date ("1–19 July (month to date)"), never
  a hardcoded full month
- No hardcoded page counts
- Per-entry client notes come from the entry's "Final note" field
- Footer keeps the git-verifiability sentence — it is the trust pitch

## Build phases

| Phase | Scope | Est. |
|---|---|---|
| 1 | Project registry (init/upgrade-project edits) + collector module + GET /api/state | 1 session |
| 2 | Server + data-driven UI (port the mockup) + /dashboard skill (start/stop/open) | 1 session |
| 3 | Tracker writes (timer.sh bridge + evidence capture) + notes POST | 0.5 session |
| 4 | Statement generator (--html) | 0.5 session |
| 5 | /wrap-up hook: regenerate-on-wrap-up or stop server; polish | small |

Each phase ends with: smoke test additions (tests/), CI green, Code Reviewer pass
(server code especially — path traversal, shell-arg injection via note/description
text going into timer.sh args: always pass as argv array, never string-interpolate).

## Open decisions (decide at build time)

- Port: fixed (e.g. 4747) vs ephemeral — fixed is bookmarkable, ephemeral avoids collisions
- Multi-project tracker: v1 tracks only the project the server was started in, or
  any registered project? (Mockup implies current-project; registry makes any-project cheap)
- Auto-start: should /resume offer to start the dashboard? (Lean no — keep it on demand)

## Design decisions already locked (do not relitigate)

- One identity across dashboard + statement: Cambria/Georgia display, Segoe UI
  body, Consolas evidence lines; system fonts only
- Overview opens with the plain-English briefing, not widgets
- Statement is a trust document: ledger + evidence + notes + sign-off, grayscale-safe
- Read-only everywhere except tracker + notes (the two approved writers)
- Dashboard never duplicates state — regenerate from files, always
