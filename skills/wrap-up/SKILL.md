---
name: wrap-up
description: |
  TRIGGER when: the user is ending a session, says wrap up, save state, done for now,
  closing, or is about to leave. Also triggered by the session-end hook nudge.
  DO NOT TRIGGER when: the user is in the middle of active work, wants to compact
  (/compact), or wants to clear context (/clear).
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Session Wrap-Up

## When to Use

When the user is ending a session and wants to save state for next time.
Not during active work, compaction, or context clears.

## Procedure

Run every step. Each step is an ACTION the framework performs — not a reminder.
Report progress as you go. If a step has nothing to do, say so explicitly.

## Step 1 — Pre-Wrap Diagnostics

Run these checks IN PARALLEL and report a single summary:

1. **Branch & PR status**
   - Current branch: `git rev-parse --abbrev-ref HEAD`
   - Uncommitted changes: `git status --porcelain | wc -l`
   - Unpushed commits: `git log @{upstream}..HEAD --oneline 2>/dev/null`
   - Open PRs from this branch: `gh pr list --head $(git rev-parse --abbrev-ref HEAD)`

2. **Test suite status**
   - Detect test command from package.json/pyproject.toml/etc.
   - Run with timeout 600000ms
   - Report pass/fail counts

3. **Stream detection**
   - Read project CLAUDE.md to determine stream (personal/org1/org2/learning)
   - Production streams (org1/org2, or personal-with-production-flag) get additional checks in Step 7

4. **Safety mode check**
   - Read `.claude/state/mode.json`
   - If mode != "normal": flag and suggest /unfreeze before ending session

5. **Active timer check**
   - Read `.claude/state/timer.json`
   - If active=true: flag for Step 1b handling (do not silently end the session)

6. **Feature lifecycle reconciliation**
   - Read all files in `wiki/features/`
   - For each feature in `in-progress`: check if a branch named `feature/{slug}` or `fix/{slug}` exists
   - For each feature in `review`: check PR state via `gh pr view {pr_number} --json state`
     - If state = MERGED: auto-transition to `shipped`, set `shipped_at`
     - If state = CLOSED (not merged): flag for user decision
   - Report any auto-transitions made

Report:
```
DIAGNOSTICS:
  Branch:        {name}
  Uncommitted:   {N} files (or "clean")
  Unpushed:      {N} commits (or "in sync")
  Open PR:       {URL or "none"}
  Tests:         {pass}/{total} passing
  Stream:        {name}
  Safety mode:   {mode}
  Active timer:  {client · note · duration, or "none"}
  Lifecycle:     {N} auto-transitions ({list})
```

## Step 1b — Active Timer Check

If `.claude/state/timer.json` is active (from Step 1):

1. Show the running timer: client, note, elapsed time.
2. Ask: "Timer is still running. What do you want to do?
   1. **Stop it** — log the time to {client}'s log (you're done with this work)
   2. **Pause it** — save state and resume next session
   3. **Leave it running** — keep counting across the gap (risky: you might bill for time you didn't work)"
3. Execute the chosen option by invoking the matching `/timer` subcommand:
   - Stop → `/timer stop` (will prompt for final note)
   - Pause → `/timer pause`
   - Leave → no-op, but warn: "Timer will keep counting until you /timer stop next session."
4. Continue with Step 2.

If no timer is active, skip this step.

## Step 2 — Handle Uncommitted Work

If there are uncommitted changes:

1. Show: `git status --short`
2. Ask: "You have uncommitted changes. Commit before wrap-up? (yes/no/show-diff)"
3. If yes:
   - Determine commit type from the files changed (feat/fix/docs/chore)
   - Suggest a commit message based on the diff
   - Commit on the current branch
4. If no:
   - Warn: "Uncommitted changes will be left in your working tree. They will NOT be in the session log."
   - Continue

## Step 3 — Push Current Branch

If on a feature/fix branch with unpushed commits:

1. Push: `git push -u origin {current_branch}` (or `git push` if upstream exists)
2. If there's an open PR: report its URL and review status
3. If there's no PR yet AND we're on a feature/fix branch with multiple commits:
   - Ask: "Branch has {N} commits with no PR. Open PR now? (yes/no)"
   - If yes: invoke `/pr`

If on main/master with unpushed commits:
- This SHOULD NOT happen with production streams (branch protection blocks it)
- For non-production: push directly with `git push`

## Step 4 — Write Session Log

Write `wiki/logs/{YYYY-MM-DD}.md` (append if file exists, create if not).

If wiki/logs/ doesn't exist, create it.

Content:

```markdown
## Session — {HH:MM start} to {HH:MM end}

### Accomplished
- {Specific, concrete things completed this session}

### Decisions Made
- {Architectural / tool / library choices}

### Files Changed
- {Key files modified/created/deleted, grouped by area}

### Branch Activity
- {New branches created}
- {PRs opened with URLs}
- {PRs merged}

### Open Items
- {Unfinished work}
- {Known issues discovered but not fixed}
- {Stale PRs that need attention}

### Next Session Should Start With
{Specific instruction for /resume — what to read, what to do first}
```

Calculate session duration from the start of the session log to now.

## Step 5 — Delegate to Wiki Updater

Delegate to the Wiki Updater subagent:

"Review the changes in this session and update project documentation:
- wiki/architecture.md if system design changed
- wiki/conventions.md if new patterns were introduced
- wiki/memory.md (APPEND ONLY) for any knowledge gained worth preserving
- wiki/decisions/ for any architectural decisions made

Be concise — facts, not essays. Report what you updated."

Wait for the Wiki Updater's report. Include it in the final wrap-up summary.

## Step 6 — Delegate to Knowledge Agent

Delegate to the Knowledge Agent:

"Review this session for new terms, people, projects, or context that should
enter the second brain:
- Were any new terms or jargon introduced?
- Were any new people or stakeholders mentioned?
- Did the project context shift in any way?
- Are there gaps in CLAUDE.md hot cache that this session revealed?

Update memory/ deep store with new entries. Update CLAUDE.md hot cache if
something belongs in the top ~30 entries. Report what you updated."

Wait for the Knowledge Agent's report.

## Step 7 — Production Stream Checks

If stream is org1, org2, or personal-with-production-flag:

1. **Compliance status**: invoke `/compliance-status` if available — report any new gaps
2. **Secrets scan**: grep recent commits for likely secrets
   - `git log --since="1 day ago" -p | grep -iE "api[_-]?key|secret|password|token" || echo "clean"`
3. **PII audit**: if data-inventory.md exists, check if any new PII fields were added without documentation
4. **PR staleness**: list any open PRs older than 7 days — they need attention
5. **Audit log volume**: report if audit logging is active and producing events
6. **Backup verification**: if backup config exists, report last backup timestamp

For non-production streams, skip Step 7.

## Step 8 — Skill Refinement Check

Check learned skills (`.claude/skills/learned/` or skills with `learned: true` frontmatter):

For each skill used this session:
- Did the skill's procedure work as documented?
  - YES → Add today's date to a "Verified on" list in the skill's frontmatter
  - NO → Show proposed changes and wait for approval

For skills verified 3+ times:
- Propose promotion to permanent: "The {name} skill has been verified {N} times.
  Promote to permanent? (yes/no)"
- If approved: move from `.claude/skills/learned/` to `.claude/skills/`
- Propose TEAM.md update

## Step 9 — Cost & Time Log

If stream has cost tracking enabled (org1, org2, or personal-with-cost-flag):

1. Calculate session duration (from session start to now)
2. Append to `wiki/logs/cost-time-log.md`:

```markdown
| Date       | Duration | Stream | Project | Notes |
|------------|----------|--------|---------|-------|
| {date}     | {Xh Ym}  | {name} | {proj}  | {one-liner} |
```

3. If new third-party services were added this session (detected from package.json/requirements/etc. changes):
   - List them and their estimated monthly cost
   - Append to `wiki/operations/vendor-costs.md`

For streams without cost tracking, skip this step.

## Step 10 — Update Project Status

Update `wiki/PROJECT_STATUS.md`:
- Status: active/paused/complete
- Last session: today's date
- Open PRs: count and URLs
- Failing tests: count (should be 0)
- Next milestone: derived from PROJECT_STATUS.md current goals
- Feature pipeline summary: counts by status (from /feature list)

## Step 10b — Export Feature Pipeline

Run `/feature export` to regenerate `wiki/features/_export.json` for any
external dashboards consuming the feature lifecycle data.

## Step 11 — Graphify Update

If `graphify` is installed in the project:

1. Check when graphify was last run: `stat graphify-out/GRAPH_REPORT.md`
2. If older than 3 days OR if 10+ files changed this session:
   - Ask: "Run /graphify to refresh the codebase graph? (yes/no)"
   - If yes: run graphify in background and report when complete

If graphify isn't installed, skip.

## Step 12 — Final Commit

If any files were changed during Steps 4-10 (wiki updates, status updates, skill refinements):

```
git add wiki/ .claude/skills/
git commit -m "Session wrap-up — {date}"
```

If on a feature/fix branch: push the wrap-up commit to the branch.
If on main with production stream: STOP — this should have been on a branch.

## Step 13 — Final Report + Recommendations

```
✓ Wrap-up complete

  Session duration:  {Xh Ym}
  Tests:             {N} passing, 0 failing
  Branch:            {name}
  Commits this session: {N}
  PR status:         {open/merged/none}
  Wiki updates:      {N} files (from Wiki Updater)
  Knowledge updates: {N} entries (from Knowledge Agent)
  Cost log:          updated (or "n/a for this stream")
  Production checks: {pass/N gaps found} (or "n/a")
  Timer:             {stopped/paused/left running/n/a} (client + duration if applicable)
  Lifecycle:         {N} auto-transitions ({list})
  Feature export:    wiki/features/_export.json refreshed

  Next session: /resume to continue where you left off.

  ⚠ Open items needing attention:
    {bullets if any — stale PRs, failing tests, compliance gaps}

🎯 Lead Engineer Recommendations for Next Session
  (run /recommend for full coached overview)

  Top 3:
    1. {highest priority action with one-line why}
    2. {next priority}
    3. {next priority}

  If you only do ONE thing next session: {the single most important action}
```

Generate the top 3 by running the same logic /recommend uses but
condensed: scan blockers first, then high-value items, pick top 3.

## Pitfalls

- Skipping Steps 5-6 (delegate to Wiki Updater and Knowledge Agent) means
  documentation drifts session by session
- Treating Step 7 as a reminder instead of running the checks defeats the
  purpose of production streams
- Promoting a learned skill that has only been verified once or twice —
  wait for 3+ verifications
- Not pushing the branch leaves work locked on your machine — next session
  cannot pick up where you left off if you switch devices
- Committing wrap-up changes to main on a production stream — should always
  be on a branch with a PR

## Verification

- All 13 steps executed (or explicitly marked n/a)
- Wiki Updater and Knowledge Agent have reported back
- Session log written with today's date
- Branch pushed (or noted why not)
- Final summary printed with all metrics
- No silent skips — every step either ran or reported "n/a because {reason}"
