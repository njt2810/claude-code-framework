---
name: recommend
description: |
  TRIGGER when: the user asks "what should I do next", "what should I run",
  "what's next", or wants Lead Engineer coaching on next actions. Also useful
  when returning to a project after time away.
  DO NOT TRIGGER when: the user asks for project status only (use /status),
  or wants to resume from session log (use /resume).
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Recommend — Lead Engineer Coaching

## When to Use

When you (the user) want the Lead Engineer to look at the project's current
state and recommend the highest-value next actions, with reasoning.

This is **coaching**, not just status. The Lead Engineer scans:
- Feature pipeline (wiki/features/)
- Compliance gaps (wiki/compliance/gaps.md)
- Open PRs (gh pr list)
- Test failures
- Stale items (PRs > 7 days, audits > 90 days, vendor reviews due)
- Production stream readiness (if applicable)

And produces a prioritized list with WHY for each.

## Lead Engineer Guidance — Why This Matters

Solo founders often suffer from "context fog" — too many things in flight,
unclear what's most important right now. This skill cuts through that.

Run `/recommend`:
- At the start of each session (alongside /resume)
- When you feel stuck or unsure
- After completing a big task (clear the next thing)
- Weekly as a health check
- Before client demos / milestones

## Procedure

## Step 1 — Gather State (parallel reads)

Read in parallel:
- `wiki/features/` — all feature files
- `wiki/compliance/gaps.md` (production streams)
- `wiki/compliance/evidence-index.md` (production streams)
- `wiki/compliance/vendor-register.md` (production streams)
- `wiki/operations/calendar.md` (production streams)
- `wiki/PROJECT_STATUS.md`
- `wiki/backlog.md` (if exists, from /triage)
- Last 5 entries from `wiki/logs/`

Run:
- `git status --porcelain` (uncommitted changes)
- `git log --since="7 days ago" --oneline` (recent commits)
- `gh pr list --state open --json number,title,url,createdAt` (open PRs)
- Test suite quick check (only run if user requests deep mode)

## Step 2 — Detect Patterns

Classify findings into categories:

**Blockers (do FIRST):**
- P0 bugs not yet fixed
- Failing tests on main
- CRITICAL compliance gaps (production streams)
- Stale PR ready to merge (in review > 24h, CI green, approved)
- Active incident open

**High-value next (do next):**
- P1 features in `in-progress` state — push to review
- Features in `review` with Code Reviewer findings unaddressed
- Vendor reviews overdue (production streams)
- Compliance audit overdue (>90 days for production)

**Maintenance (when capacity):**
- P2/P3 backlog items at top of priority
- Documentation stale (no wiki updates in 7+ days)
- Stale flag retirement (per feature-flag registry)
- Backup restore drill overdue

**Discovery (proactive):**
- Recently merged features that haven't been documented
- New PII fields detected without retention policy
- Code touching auth/payments not yet seen by Compliance Officer

## Step 3 — Detect Stage-Specific Recommendations

Check what skills haven't been run yet (for production projects):

| Skill | Should have run? | Reason if missing |
|-------|------------------|-------------------|
| /constitution | Once at project start | Defines guardrails |
| /knowledge bootstrap | After /init-project | Builds second brain |
| /compliance-audit | Within 90 days | SOC 2 baseline |
| /data-inventory | After PII fields added | Required for SOC 2 + PDPA |
| /audit-logging-setup | Before first deploy | SOC 2 evidence collection |
| /observability-setup | Before first deploy | Operational visibility |
| /dr-plan | Before first paying customer | Business continuity |
| /env-setup | Before staging/prod | Multi-environment safety |
| /vendor-review (per vendor) | When adopting any vendor | Risk assessment |

If any of these haven't run but should have, surface as a recommendation.

## Step 4 — Generate Recommendation Report

Present as a coached report (not just a list):

```
🎯 Lead Engineer Recommendations — {project name}
   {YYYY-MM-DD HH:MM}     Stream: {stream}     Production: {ON/OFF}

═══════════════════════════════════════════════════════════════
🔴 DO FIRST (blockers)
───────────────────────────────────────────────────────────────

  1. {Action}
     Why: {one-sentence reasoning}
     How: {exact skill or command to run}
     Cost: {S/M/L effort}

  2. ...

═══════════════════════════════════════════════════════════════
🟠 HIGH VALUE (do next)
───────────────────────────────────────────────────────────────

  1. {Action}
     Why: {reasoning}
     How: {skill or command}
     Cost: {effort}

═══════════════════════════════════════════════════════════════
🟡 MAINTENANCE (when capacity)
───────────────────────────────────────────────────────────────

  1. {Action}
     Why: {reasoning}
     How: {skill or command}

═══════════════════════════════════════════════════════════════
💡 MISSING SETUP (you skipped these)
───────────────────────────────────────────────────────────────

  - {Skill}: {why it should run, given project state}

═══════════════════════════════════════════════════════════════

📊 Snapshot
  Open features:   {N}  (in-progress: {N}, review: {N})
  Open PRs:        {N}  (oldest: {days} days)
  Open bugs:       {N}  ({N} P0/P1)
  Compliance gaps: {N} CRITICAL, {N} HIGH (production only)
  Last shipped:    {date}

📅 Coming up
  {date}: {scheduled item from calendar.md}
  {date}: {scheduled item}

If you only do ONE thing today: {the single most important action}.
```

## Step 5 — Offer to Run a Recommendation

After presenting, ask:
"Want me to start on any of these? Reply with the number or describe what
you want to tackle. Or 'cancel' if you just wanted the overview."

If the user picks one, invoke the relevant skill/workflow.

## Patterns The Lead Engineer Looks For

**Pattern: "PR rotting in review"**
- Open PR > 7 days with no recent activity → recommend reviewing or closing

**Pattern: "Features stuck in proposed"**
- Items in proposed > 30 days → recommend triage decision (build/archive)

**Pattern: "Shipping without compliance"**
- Production stream, deploy happened, but no compliance audit in 90 days
  → recommend /compliance-audit before next deploy

**Pattern: "Vendor risk drift"**
- Vendor added but no /vendor-review entry → recommend review now

**Pattern: "Skill never run when it should be"**
- Production stream, no /audit-logging-setup output → recommend immediately

**Pattern: "Friday afternoon"**
- Suggesting non-trivial deploys on Friday afternoon → discourage

**Pattern: "Pre-demo / pre-client-call"**
- If user mentions an upcoming demo / client call → recommend
  /production-audit before the event

## Pitfalls

- Surfacing 20 recommendations dilutes signal — keep to top 5-7
- Recommending tasks without reasoning — user can't learn the pattern
- Not differentiating blockers from nice-to-haves — leads to decision paralysis
- Ignoring stream context (recommending production skills for learning stream) — noise

## Verification

- Report includes blockers, high-value, maintenance, missing-setup sections
- Every recommendation has a Why and How
- Snapshot numbers match actual state (not stale)
- The "if you only do ONE thing" is explicit
- User has a clear path to start on any recommendation
