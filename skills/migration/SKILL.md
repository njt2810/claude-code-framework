---
name: migration
description: |
  TRIGGER when: the user wants to change the database schema, generate a
  migration file, test a migration, plan a rollback, or check migration safety.
  Also when /deploy flags migration concerns.
  DO NOT TRIGGER when: the user wants to write a one-off SQL query (just write it),
  or to do general DB ops (different scope).
argument-hint: "[create|plan|verify|rollback|history] [name]"
disable-model-invocation: true
user_locked: true
pinned: true
---

# Database Migration Management

## When to Use

When the project's database schema needs to change — adding/dropping columns,
new tables, indexes, constraints, data backfills. Enforces the discipline
that prevents migrations from breaking production.

## Lead Engineer Guidance — Why This Matters

Migrations are the #1 cause of production outages in growing SaaS projects.
Common failure modes:
- Locking a large table during a deploy → users see timeouts
- Backward-incompatible change → old app version on rolling deploy crashes
- Drop column without grace period → forgotten code references break
- No rollback plan → recovery requires improvisation under pressure
- Untested migration → "it ran in dev" but corrupts prod

**Use this skill EVERY time the schema changes.** The cost of running it
(5 min) is far less than the cost of one bad migration (hours of recovery).

**Pattern to learn — expand/contract:**
For risky changes, split into two deploys:
- **Expand:** add the new shape alongside the old (forward-compatible)
- **Migrate code:** new code uses new shape; old shape still works
- **Contract:** drop the old shape (only after old code is fully retired)

This makes migrations safe under rolling deploys.

## Procedure

## Step 1 — Detect ORM / Migration Tool

Detect from project:
- `prisma/schema.prisma` → Prisma
- `drizzle.config.ts` → Drizzle
- `alembic.ini` → Alembic (SQLAlchemy)
- `migrations/` (Django) → Django migrations
- `db/migrate/` (Rails) → Active Record migrations
- `node-pg-migrate` in package.json → node-pg-migrate
- `knexfile.js` → Knex
- Raw SQL files in `migrations/` → DIY

If unclear, ask the user.

## Step 2 — Operation: CREATE

Walk the user through creating a safe migration:

1. **Describe the change** — what schema change? Why?
2. **Classify safety:**
   - SAFE (forward-compatible, no locks):
     - Add nullable column with no default
     - Add table (no FK from existing)
     - Add index CONCURRENTLY (Postgres)
     - Add constraint NOT VALID then VALIDATE
   - RISKY (locks, breaks rolling deploy):
     - Add column with default (Postgres locks rewrites table)
     - Drop column (old code still reads it)
     - Rename column (old code uses old name)
     - Add FK constraint without NOT VALID
     - Add NOT NULL on existing column
   - DESTRUCTIVE (data loss possible):
     - Drop table
     - Drop column with data
     - Change column type with possible data truncation
     - Bulk DELETE / UPDATE without batching

3. **For RISKY changes, propose expand/contract split.** Example:
   - Bad: `ALTER TABLE users RENAME COLUMN email TO email_address`
   - Good (3 deploys):
     - Deploy 1: `ALTER TABLE users ADD COLUMN email_address TEXT` + dual-write code
     - Deploy 2: backfill data, switch reads to new column
     - Deploy 3: `ALTER TABLE users DROP COLUMN email`

4. **Generate migration file** using detected tool:
   - Prisma: `pnpm prisma migrate dev --name {name}`
   - Drizzle: `pnpm drizzle-kit generate`
   - Alembic: `alembic revision -m "{name}"`
   - Django: `python manage.py makemigrations`
   - Else: create the SQL file manually

5. **Add rollback** in the down migration. NEVER leave this empty.
   For destructive operations (drop column), the rollback may need to be
   "restore from backup at {timestamp}" — document explicitly.

## Step 3 — Operation: PLAN (for risky changes)

Generate a deployment plan in `wiki/operations/migrations/{date}-{name}.md`:

```markdown
# Migration Plan: {name}

## Change
{What's changing}

## Safety Classification
{SAFE / RISKY / DESTRUCTIVE} — {reason}

## Expand-Contract Phases
{If applicable}

### Phase 1 — Expand (Deploy {N})
- Migration: {file}
- Code change: {description}
- Backward-compatible: YES
- Risk: low

### Phase 2 — Backfill (Deploy {N+1})
- Backfill script: {path}
- Validation: {how to verify data integrity}
- Estimated time: {duration}
- Lockable: NO (or YES — schedule maintenance window)

### Phase 3 — Contract (Deploy {N+2})
- Migration: {file}
- Old code retired: YES (confirm)

## Locking Assessment

For each migration, run an analysis:
- Estimated lock duration: {N} seconds
- Tables locked: {list}
- Acceptable for production traffic: YES / NO (schedule maintenance window)

For Postgres, use `pg_locks` query in staging to measure actual lock time.

## Rollback Plan

If Phase {N} fails:
1. {Concrete rollback step}
2. {Concrete rollback step}

Data recovery (if destructive):
- Backup taken at: {ISO timestamp before phase}
- Restore command: {exact command}
- RPO: {N} hours of data loss possible

## Testing Plan
- [ ] Apply migration in dev
- [ ] Run app smoke tests
- [ ] Apply migration in staging (production-like dataset)
- [ ] Measure actual lock duration
- [ ] Test rollback in staging
- [ ] Run /api-contract verify (if API affected)

## Comms Plan
{If maintenance window required, schedule and notify users}

## Sign-off
- Code Reviewer: {pending}
- Security Auditor: {pending if PII columns affected}
- Compliance Officer: {pending if PII columns affected}
```

## Step 4 — Operation: VERIFY

Before deploying a migration:

1. **Dry-run on staging:**
   - Restore latest production snapshot to staging
   - Apply migration
   - Measure lock duration: `SELECT * FROM pg_stat_activity WHERE wait_event LIKE '%Lock%'`
   - Run smoke tests against the migrated DB

2. **Check backward compatibility:**
   - Old app version code paths: do they still work against new schema?
   - If using rolling deploy: old + new app versions will both run against new schema simultaneously

3. **Verify rollback path:**
   - Actually run the down migration in staging
   - Confirm it reverses cleanly

4. **Check data integrity:**
   - Row counts before/after match
   - NULL counts in changed columns make sense
   - Sample queries return expected results

5. **Report:**
```
Migration verification: {name}

  Schema change:       APPLIED in staging
  Lock duration:       {N} seconds
  Smoke tests:         {pass/fail}
  Rollback test:       {pass/fail}
  Data integrity:      {pass/fail}
  Old code compat:     {pass/fail}

  Safe to deploy?      {YES / NO — reason}
```

## Step 5 — Operation: ROLLBACK

For an in-progress production issue:

1. **Stabilize first** — see /incident workflow
2. **Decide:** code rollback only (if migration is forward-compatible)?
   Or migration rollback too?
3. **If migration rollback:**
   - Execute down migration: tool-specific (`alembic downgrade -1`, `prisma migrate resolve --rolled-back`, etc.)
   - For destructive migrations: this may not work — restore from backup
4. **Document in incident file**

## Step 6 — Operation: HISTORY

Read migration files and tool's migration history.
Print a timeline:

```
Migration History — {project}

Last 10 migrations:
  {timestamp}  {name}                       {applied to prod}
  ...

Pending (not in prod yet):
  {name}  (added: {date}, status: dev only / staging only)

Stuck or failed:
  {name}  (failed: {error})

Total migrations: {N}
First migration: {date}
```

## Step 7 — Compliance & Audit

Log every production migration in `wiki/compliance/evidence/migration-log.md`:

```markdown
| Date       | Migration | Applied By | Tested in Staging | Rollback Tested | Result |
|------------|-----------|------------|-------------------|-----------------|--------|
| {date}     | {name}    | {user}     | YES               | YES             | OK     |
```

This is SOC 2 evidence for CC8 (change management).

## Pitfalls

- "It's a small change" — even one-column changes can lock big tables
- Skipping the staging dry-run — first time you see lock duration is in prod
- No rollback path — fix becomes guessing
- Letting old code reference dropped columns — instant crash
- Adding NOT NULL on existing column without backfill — fails for existing rows
- Running migrations and app deploy as one atomic step — if migration fails mid-deploy, you have a half-migrated state
- Forgetting to log to migration-log.md — auditors will ask

## Verification

- Migration file created with both up AND down
- Plan written for risky/destructive changes
- Staging dry-run completed before production
- Rollback tested in staging
- Logged in `wiki/compliance/evidence/migration-log.md`
- User knows the safety classification of the migration
