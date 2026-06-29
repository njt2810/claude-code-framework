---
name: timer
description: |
  TRIGGER when: the user says "start a timer", "stop the timer", "track time",
  "log hours", or anything about billable client work. Subcommands: start, stop,
  pause, resume, status, list, report.
  DO NOT TRIGGER when: the user wants session duration (/wrap-up handles that)
  or asks about internal product work (use /feature, not /timer).
effort: low
user_locked: true
---

# Client Time Tracking

## When to Use

When working on something for a paying client and you need billable hours
logged with evidence. NOT for internal product work — internal work tracks
via /feature lifecycle.

## State Files

- Active timer: `.claude/state/timer.json` (per-project)
- Client log:   `wiki/clients/{client}/time-log.md` (append-only)
- Reports:      `wiki/clients/{client}/reports/{YYYY-MM}.md`

## Subcommands

### `/timer start [note] [--client X] [--type Y]`

1. Read `.claude/state/timer.json`. If active=true → error:
   "Timer already running for {client}: {note}. /timer stop or /timer pause first."
2. Resolve client:
   - If `--client` passed → validate it exists in `wiki/clients/`
   - Else list `wiki/clients/*/`. If exactly 1, use it. If multiple, ask
     "Which client?". If 0, error: "No clients onboarded. Run /onboard-client first."
3. Resolve type. If not passed, ask:
   "What kind of work? bug-fix / feature / dashboard / data / support / research / meeting / other"
4. If no note passed, ask: "One-line note describing what you're working on?"
5. Capture: ISO start time, current branch (`git branch --show-current`),
   starting commit (`git rev-parse HEAD`)
6. Ensure `.claude/state/` exists. Write `.claude/state/timer.json`:
   ```json
   {
     "active": true,
     "mode": "running",
     "client": "acme",
     "type": "bug-fix",
     "note": "fixing dashboard layout",
     "started_at": "2026-06-29T14:14:00+08:00",
     "branch": "fix/dashboard-mobile",
     "starting_commit": "a1b2c3d",
     "accumulated_seconds": 0
   }
   ```
7. Confirm: "⏱ Timer started — acme · bug-fix · 'fixing dashboard layout' · 2:14 PM"

### `/timer stop [--note "updated note"]`

1. Read state. If not active → error: "No timer running."
2. Compute duration:
   - If mode=running: `(now - started_at) + accumulated_seconds`
   - If mode=paused:  `accumulated_seconds`
3. If `--note` passed, replace stored note. Else ask:
   "Anything to add to the note before logging?"
4. Evidence capture:
   - `git diff --stat {starting_commit}..HEAD` → file count + line counts
   - `git log --oneline {starting_commit}..HEAD` → commit list
   - Current branch
5. Append entry to `wiki/clients/{client}/time-log.md` using the format below.
6. Delete `.claude/state/timer.json`.
7. Show: "Logged 1h 32m to acme. 5 files, 2 commits. See wiki/clients/acme/time-log.md"

### `/timer pause`

1. Read state. If not active or already paused → error.
2. Add `(now - started_at)` to `accumulated_seconds`. Clear `started_at`. Set `mode=paused`.
3. Show: "⏸ Paused at 47m. /timer resume to continue."

### `/timer resume`

1. Read state. If mode != paused → error.
2. Set `mode=running`, `started_at=now`.
3. Show: "▶ Resumed. Accumulated so far: 47m."

### `/timer status`

- No timer:     "No timer running."
- Running:      "⏱ acme · bug-fix · 'fixing dashboard layout' · started 2:14 PM · 1h 14m elapsed"
- Paused:       "⏸ acme · bug-fix · paused at 47m"

### `/timer list [--client X] [--month YYYY-MM]`

1. Read `wiki/clients/{client}/time-log.md` (all clients if `--client` omitted).
2. Parse entries (each is a `## YYYY-MM-DD · {note}` heading with structured bullets).
3. Filter by month if `--month` given.
4. Show table:
   ```
   Date       Client   Type       Duration   Topic
   2026-06-12 acme     feature    2h 04m     Initial dashboard build
   2026-06-15 acme     bug-fix    1h 30m     Data import bug
   ```

### `/timer report --client X [--month YYYY-MM]`

1. Read `wiki/clients/{client}/time-log.md`, filter by month.
2. Generate markdown report (format below).
3. Save to `wiki/clients/{client}/reports/{YYYY-MM}.md`.
4. Print: "Report saved (8h 24m across 4 sessions). Send to client."

## Log Entry Format (appended to time-log.md)

```markdown
## 2026-06-29 · fixing dashboard layout

- Client: acme
- Type: bug-fix
- Started: 2:14 PM SGT
- Stopped: 3:46 PM SGT
- Duration: 1h 32m
- Branch: fix/dashboard-mobile
- Commits: 2 (a1b2c3d, e4f5g6h)
- Files touched: src/components/Dashboard.tsx, src/styles/dashboard.css (+3 more)
- Final note: "Fixed misaligned columns on mobile breakpoint, tested on iOS Safari"
```

## Report Format

```markdown
# Time Report — acme — June 2026

**Total: 8h 24m across 4 sessions**

Breakdown by type:
- bug-fix:   4h 10m
- dashboard: 2h 30m
- data:      1h 44m

| Date  | Duration | Type      | Topic                    |
|-------|----------|-----------|--------------------------|
| 06-12 | 2h 04m   | feature   | Initial dashboard build  |
| 06-15 | 1h 30m   | bug-fix   | Data import bug          |
| 06-22 | 3h 18m   | data      | Churn analysis review    |
| 06-29 | 1h 32m   | bug-fix   | Dashboard layout bug     |

---

## Session detail

{Full entries from time-log.md filtered to this month}
```

## Integration

- **/wrap-up:** If timer active → prompts: stop / pause / leave running
- **/resume:** If a paused timer exists → announces it
- **/onboard-client:** Creates `wiki/clients/{slug}/time-log.md` placeholder
- **statusline.sh:** Shows live ⏱ line when timer is active

## Pitfalls

- Don't start a timer for internal product work — that's not billable. Use /feature.
- If you forget /timer stop before /clear or shutdown, the timer keeps running.
  Next /timer status will show inflated time — manually edit time-log.md to correct.
- If you switch branches mid-timer, the evidence capture spans both. Consider
  /timer stop + /timer start when context changes meaningfully.
- Always confirm the auto-captured file list looks right before sending a report
  to a client — git diff may include incidental files (config tweaks, etc.).

## Verification

- `/timer status` reflects correct elapsed time across pause/resume
- `/timer stop` writes a complete entry with git evidence
- `/wrap-up` detects active timer and prompts
- `/resume` announces paused timer if present
- statusline shows ⏱ line when timer is running
