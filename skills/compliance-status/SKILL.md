---
name: compliance-status
description: |
  TRIGGER when: the user wants a quick compliance health dashboard, asks "where are we
  on compliance", or needs to check what evidence has been collected and what's stale.
  DO NOT TRIGGER when: the user wants a full audit (use /compliance-audit) or
  data inventory (use /data-inventory).
disable-model-invocation: true
user_locked: true
pinned: true
---

# Compliance Status Dashboard

## When to Use

Lightweight read-only check on the project's compliance state. Designed to be
fast — runs daily or weekly without modifying anything. For deep gap analysis,
use `/compliance-audit`.

## Procedure

## Step 1 — Stream Check

Read CLAUDE.md to confirm production stream.
If learning: STOP. Compliance is for production streams.

## Step 2 — Read Compliance Files

Read these in parallel (if they exist):
- `wiki/compliance/gaps.md` — latest audit results
- `wiki/compliance/evidence-index.md` — collected evidence
- `wiki/compliance/data-inventory.md` — PII inventory
- `wiki/compliance/vendor-register.md` — vendor list
- `wiki/compliance/soc2-controls.md` — SOC 2 control matrix
- `wiki/compliance/audit-logging.md` — audit log config
- `wiki/operations/calendar.md` — upcoming review dates
- `wiki/legal/privacy-policy.md` — verify exists and not stale
- `wiki/legal/dpa.md` — verify exists and not stale

If any file is missing, note it as a gap.

## Step 3 — Calculate Health Metrics

| Metric | Calculation |
|--------|-------------|
| **Days since last audit** | Today - latest audit date in gaps.md |
| **Open gaps** | Count FAIL + PARTIAL in latest audit |
| **Evidence freshness** | Count evidence items last verified > 90 days ago |
| **Vendor reviews due** | Vendors with review_date < today |
| **Documents needing review** | Files in `wiki/legal/` with "DRAFT" header still present |
| **PII fields without retention** | Rows in data-inventory.md with "TODO" in retention column |

## Step 4 — Check Audit Logging Activity

If audit log helper exists (`src/lib/audit-log.ts` or `src/audit_log.py`):
- Check the helper file is still wired (not stubbed)
- If a `audit-logs/` directory exists locally, check the latest file timestamp
- Report whether logging appears active

## Step 5 — Print Dashboard

```
Compliance Status — {project name}
Stream: {stream}    Updated: {YYYY-MM-DD HH:MM}

📊 Overview
  Days since last audit:        {N}  ({status: 🟢 < 90  🟡 90-180  🔴 > 180})
  Open gaps:                    {N}  ({severity breakdown})
  Evidence items collected:     {N}
  Evidence > 90 days stale:     {N}
  Vendor reviews due:           {N}
  Documents pending lawyer:     {N}
  PII fields w/o retention:     {N}

📁 Coverage
  Data inventory:               {exists / MISSING}
  Vendor register:              {N} vendors tracked
  Security policies:            {N/10} in wiki/compliance/policies/
  Legal docs:                   {N/4} in wiki/legal/ (privacy/tos/dpa/cookie)
  Audit logging:                {ACTIVE / SCAFFOLD / MISSING}

📅 Upcoming
  {Date}: Review {vendor X}
  {Date}: Re-audit ({90 days from last})
  {Date}: Annual privacy policy review

🔥 Top 3 actions
  1. {action} — {why}
  2. {action} — {why}
  3. {action} — {why}
```

## Step 6 — No Writes

This skill ONLY reads. It writes nothing.

For modifications, suggest the right skill:
- "Run `/compliance-audit` to update gap analysis"
- "Run `/data-inventory` to refresh PII map"
- "Run `/vendor-review {name}` for stale vendors"
- "Run `/legal-docs {type}` for missing legal docs"

## Pitfalls

- Treating this as a replacement for `/compliance-audit` — it's a dashboard, not an audit
- Forgetting to refresh evidence after collecting it — the dashboard will show false staleness
- Running on a learning stream — meaningless, returns nothing useful
- Not running it often enough — quarterly is too slow for production. Weekly or per-session is right.

## Verification

- All compliance files read (or noted as missing)
- Dashboard printed with all metrics
- Top 3 actions clearly stated
- No files were modified by this skill
- Stale items have a recommended skill to address them
