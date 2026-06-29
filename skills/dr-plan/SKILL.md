---
name: dr-plan
description: |
  TRIGGER when: the user wants to plan disaster recovery, set up backups,
  define RTO/RPO targets, or test backup restoration.
  DO NOT TRIGGER when: the user wants incident response (use /incident),
  or to deploy (use /deploy).
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Disaster Recovery Plan

## When to Use

When a production project needs a backup and disaster recovery plan, or when
testing whether existing backups actually restore. SOC 2 requires both
documented DR plan AND evidence of restore tests.

## Procedure

## Step 1 — Stream Check

Read CLAUDE.md to confirm production stream. If learning: STOP.

## Step 2 — Identify Recovery Targets

For each data store or service, define:

**RTO (Recovery Time Objective)** — how long to recover after a failure
**RPO (Recovery Point Objective)** — how much data loss is acceptable

Typical SaaS targets at early stage:
- RTO: 4 hours for paid customer-facing systems
- RPO: 24 hours (daily backups), or 1 hour with continuous replication

Ask the user to confirm or adjust these targets.

## Step 3 — Inventory Data Stores

For each store, document:
- What it holds (use data-inventory.md)
- Where it lives (vendor, region)
- Existing backup mechanism
- Backup frequency
- Backup retention
- Backup destination (and is it in a different region/account?)
- Restoration tested? Last test date?

Example:
| Store | Holds | Backup | Frequency | Retention | Tested |
|-------|-------|--------|-----------|-----------|--------|
| Postgres (Neon) | users, orders | Neon native | continuous | 7 days hot, 30 cold | No |
| S3 bucket "uploads" | user files | S3 versioning + cross-region replication | continuous | 90 days | No |
| Redis (cache) | sessions, rate limits | None (ephemeral) | n/a | n/a | n/a |

## Step 4 — Identify Gaps

For each gap, propose a fix:

- No backup → enable native backup or schedule export
- Backup not in different region/account → enable cross-region replication
- Retention too short → extend
- Never tested → schedule a restore drill

## Step 5 — Write DR Plan

Write `wiki/operations/disaster-recovery.md`:

```markdown
# Disaster Recovery Plan

## Recovery Targets
- RTO: {N} hours
- RPO: {N} hours

## Data Stores

### {Store name}
- Holds: {what}
- Vendor: {vendor}, {region}
- Backup: {mechanism, frequency, retention, destination}
- Restoration procedure: see runbook below
- Last restore test: {date or "NEVER — schedule"}

## Failure Scenarios

### Scenario 1: Primary DB region failure
- Detection: {how}
- Impact: {what's affected}
- Recovery steps:
  1. {step}
  2. ...
- Estimated time: {N} hours
- Comms: notify affected users via {channel}

### Scenario 2: Accidental data deletion
- ...

### Scenario 3: Ransomware / data corruption
- ...

### Scenario 4: Vendor outage (e.g., hosting provider down)
- ...

## Restore Procedures

### Postgres Restore from Backup
```bash
# {commands here}
```

### S3 Restore from Versioning
```bash
# {commands here}
```

## Test Schedule
- Quarterly: full restore drill from latest backup to a scratch environment
- Monthly: spot-check that backup files are valid

## Contact List
- Primary on-call: {name, phone}
- Vendor support: {names, URLs}
- Status page admin: {link to update}

## Communications Template
- See `wiki/operations/incident-comms-template.md`
```

## Step 6 — Schedule Restore Drill

Append to `wiki/operations/calendar.md`:

```markdown
| Date | Action | Notes |
|------|--------|-------|
| {today + 14 days} | DR drill: Postgres restore | First drill — measure actual RTO |
| {today + 90 days} | DR drill: full | Quarterly |
```

## Step 7 — Report

```
Disaster Recovery Plan Complete

  RTO target:    {N} hours
  RPO target:    {N} hours
  Data stores:   {N} inventoried
  Backups:       {N} configured, {N} need setup
  Restores:      {N} never tested

  Top gaps:
    - {gap} — {fix}
    - ...

  DR plan:       wiki/operations/disaster-recovery.md
  Calendar:      First drill scheduled for {date}

Next steps:
  1. Enable backups for the {N} stores without
  2. Run a restore drill within 14 days — that's how you find broken backups
  3. Verify backup destination is in a different region/account
```

## Pitfalls

- Backups that have never been tested — they often don't work
- Backup destination in same region/account as primary — single point of failure
- Setting unrealistic RTO/RPO — promises you can't keep
- DR plan that mentions "the team will" — solo founder = you are the team
- Forgetting non-DB state (uploaded files, cache, configs) — incomplete recovery

## Verification

- `wiki/operations/disaster-recovery.md` written with all sections
- Every data store has a backup mechanism documented (or flagged as gap)
- RTO and RPO are explicit numbers, not "as soon as possible"
- First restore drill is scheduled in `wiki/operations/calendar.md`
- Recovery procedures are concrete enough to follow under pressure
