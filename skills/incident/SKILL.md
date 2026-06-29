---
name: incident
description: |
  TRIGGER when: production is down, users report a critical issue, the user
  says "incident", "outage", "production broken", or there's an active P1 problem.
  DO NOT TRIGGER when: the user has a normal bug (use /bug-fix), or wants
  to plan DR (use /dr-plan).
disable-model-invocation: true
effort: high
user_locked: true
pinned: true
---

# Incident Response

## When to Use

When production is broken or degraded and customers are or could be affected.
This skill structures the response so nothing critical is missed under pressure.

## Procedure

## Step 1 — Declare Incident

Ask: "Brief description of the incident? (one sentence)"

Create incident file at `wiki/operations/incidents/{YYYY-MM-DD}-{slug}.md`:

```markdown
# Incident: {title}

## Status: ACTIVE
- Declared: {YYYY-MM-DD HH:MM}
- Severity: {P1 / P2 / P3} (assess below)
- Impact: {what's broken, who's affected}
- Lead: {Lead Engineer}

## Severity Assessment
- P1: Production down or major data loss or active security breach
- P2: Significant feature broken, paid customers affected, no data loss
- P3: Minor degradation, workaround exists, not customer-blocking

## Timeline
- {HH:MM} — Declared

## Status Updates
{Add here as situation evolves}

## Root Cause
{Filled in during/after}

## Resolution
{Filled in after}

## Action Items (post-incident)
{Filled in after}

## Postmortem
{Filled in after}
```

## Step 2 — Stabilize First, Investigate Second

Order of operations:
1. **Stop the bleeding** — rollback the last deploy if recent
2. **Communicate** — update status page, notify affected customers
3. **Investigate** — find root cause
4. **Fix** — implement permanent fix
5. **Verify** — confirm resolution
6. **Document** — postmortem

## Step 3 — Immediate Stabilization

If a recent deploy is the suspected cause:
- Trigger rollback per `wiki/operations/rollback-runbook.md`
- This is the fastest path to "the bleeding stops"
- After rollback, you have time to investigate properly

If not deploy-related:
- Identify the immediate symptom (high error rate, slow response, hard down)
- Apply circuit breaker if available (rate limit, feature flag off, traffic re-route)
- Scale up if capacity issue
- Restart if memory leak / state issue

Document each action in the incident file timeline.

## Step 4 — External Communication

Update the status page (if you have one) with:
- Initial status: "Investigating — we're aware of {issue} affecting {scope}"
- Updates every 30 minutes minimum
- Resolution: "Issue resolved at {time}. Postmortem to follow."

For P1 affecting paid customers, send email/Slack to affected accounts.
For SaaS clients: many contracts require notification within N hours.

Use template at `wiki/operations/incident-comms-template.md`:

```
Subject: Service Incident — {short description}

Hi {customer},

We're investigating an issue affecting {scope}.

Impact: {what's affected, what's not}
Start time: {when}
Status: Investigating / Identified / Monitoring / Resolved

We will update you every 30 minutes until resolved.
Status page: {URL}

Best,
{Name}
```

## Step 5 — Investigate

Use observability tools (read URLs from wiki/operations/observability.md):
- Error tracking: find the exception stack traces
- Logs: trace the request flow
- Metrics: identify what changed (deploy, traffic spike, etc.)
- Audit logs: did someone change config?

State your hypothesis before fixing:
"I believe the cause is {X} because {evidence}."

## Step 6 — Fix

For P1 incidents, the fix can be:
- A hotfix on main (with PR, but expedited review) — see `/bug-fix` workflow
- A config change (feature flag, rate limit adjustment)
- A vendor fix (if root cause is vendor-side)

NEVER skip the failing-test-first step from /bug-fix, even under pressure.
You need proof the fix actually addresses the issue.

After fix is verified working:
- Re-enable any circuit breakers that were tripped
- Monitor for 30 minutes for regression

## Step 7 — Resolve

Mark the incident resolved when:
- Symptom is gone
- Root cause is identified (or strongly hypothesized)
- Fix is deployed and stable for 30+ minutes
- Customers have been notified

Update incident file:
```markdown
## Status: RESOLVED
- Resolved: {YYYY-MM-DD HH:MM}
- Duration: {N} minutes/hours
- Resolution: {what fixed it}
```

## Step 8 — Postmortem (Within 5 Days)

Write the postmortem section of the incident file:

```markdown
## Postmortem

### What happened
{Plain-language explanation}

### Timeline
- {HH:MM} — {event}
- ...

### Root cause
{Why it happened, including contributing factors}

### Impact
- Customers affected: {count or "all" or scope}
- Duration: {N} minutes
- Data loss: {none / scope}
- Financial impact: {if measurable}

### What went well
- {What helped detection/resolution}

### What went wrong
- {What slowed detection/resolution}

### Action items
| Action | Owner | Due | Status |
|--------|-------|-----|--------|
| {add monitoring for X} | {name} | {date} | open |
| {add test for Y} | {name} | {date} | open |
| {update runbook} | {name} | {date} | open |

### Lessons learned
{For the team / future}
```

Postmortems are **blameless** — focus on system gaps, not individual errors.

## Step 9 — Update Compliance Records

For SOC 2:
- Add the incident to `wiki/compliance/evidence/incidents-log.md`
- If PII was exposed: this is a notifiable breach under PDPA
  - PDPA notification: within 72 hours of becoming aware
  - File a notification with the PDPC if criteria met
  - Notify affected individuals if criteria met
- Update `wiki/compliance/risk-register.md` with any new risks revealed

## Step 10 — Report

```
Incident Resolved

  Title:         {title}
  Severity:      {P1/P2/P3}
  Duration:      {N} min
  Customers:     {affected count}
  Root cause:    {one-line}
  Resolution:    {one-line}

  Incident file: wiki/operations/incidents/{filename}
  Postmortem:    {scheduled / completed}

Required next steps:
  1. Postmortem within 5 days
  2. {N} action items to track
  3. (If PII exposed) PDPA notification — verify with lawyer
  4. (If client SLA affected) Send incident report to affected clients
  5. Update `wiki/operations/incident-response.md` if process gaps found
```

## Pitfalls

- Investigating before stabilizing — bleeding continues while you debug
- No external communication — customers feel ignored, trust erodes
- Skipping the failing test even under pressure — fix may not address root cause
- Blameful postmortem — destroys team trust, hides truth in future
- Forgetting compliance reporting — PDPA breach notification has hard deadlines
- Treating the incident as "done" after fix — postmortem and action items matter more for prevention

## Verification

- Incident file created with all required sections
- Customers notified (status page, email, or in-app)
- Stabilization actions documented in timeline
- Root cause identified and documented
- Fix verified and stable for 30+ minutes
- Postmortem scheduled within 5 days
- Compliance records updated (incidents log, risk register)
- Action items have owners and due dates
