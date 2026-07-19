---
name: deploy
description: |
  TRIGGER when: the user wants to deploy to dev/staging/production, ship to an
  environment, or set up a deployment workflow.
  DO NOT TRIGGER when: the user wants to merge a PR (they handle that via gh),
  or run a build locally (use the build command directly).
argument-hint: "[dev|staging|production]"
disable-model-invocation: true
user_locked: true
pinned: true
---

# Deploy

## When to Use

When deploying to a non-local environment. Enforces pre-deploy gates,
runs the deploy, and verifies post-deploy health.

## Procedure

## Step 1 — Determine Target

From `$ARGUMENTS`:
- `dev` — deploy to dev environment
- `staging` — deploy to staging
- `production` — deploy to production (highest gate)
- If empty: ask the user

## Step 2 — Pre-Deploy Gates

Run ALL of these. ANY failure blocks the deploy.

### Gate 1: Branch & PR State (production only)
- Current branch must be `main`
- Working tree must be clean (no uncommitted)
- HEAD commit must be the merged PR commit
- Last PR was approved + merged via squash

### Gate 2: Tests Pass
- Run full test suite
- Block deploy if any tests fail

### Gate 3: Linting Passes
- Run linter
- Block if errors

### Gate 4: Build Succeeds
- Run build command
- Block if build fails

### Gate 5: Migration Safety (if migrations changed)
- Detect new migrations in this deploy
- For production: ALL of these must be true:
  - Migrations are backward-compatible with the current production schema
  - Migrations include rollback plans (down migrations or documented manual rollback)
  - Migrations don't lock large tables (no naive ALTER TABLE on multi-million-row tables)
- If any are uncertain: STOP and delegate to Code Reviewer for migration safety check

### Gate 6: Compliance (production, if applicable)
- Read `wiki/compliance/gaps.md` — block if CRITICAL gaps are open
- Read `wiki/compliance/audit-logging.md` — confirm audit logging is wired
- Read `wiki/operations/disaster-recovery.md` — confirm backups are scheduled

### Gate 7: Secret Manager Configured (production)
- Confirm production secrets are in the secret manager
- Confirm no `.env.production` file is being deployed

### Gate 8: User Confirmation (production)
For production deploys, require explicit confirmation:

```
PRODUCTION DEPLOY CONFIRMATION

Branch:          {name} (HEAD: {sha})
PR:              {URL of last merged PR}
Tests:           ✅ {N} passing
Build:           ✅ succeeded
Migrations:      {N} new ({safety status})
Compliance:      {PASS / N gaps}
Last deploy:     {timestamp}
Deploy duration: estimated {N} min

Continue with PRODUCTION deploy? (yes/no)
```

Do NOT auto-confirm. Wait for explicit "yes."

## Step 3 — Execute Deploy

Detect deployment mechanism from project config:
- `vercel.json` → `vercel deploy --prod` (production) or `vercel deploy` (preview)
- `netlify.toml` → `netlify deploy --prod` or `netlify deploy`
- `.github/workflows/deploy.yml` → trigger GitHub Actions deploy
- `fly.toml` → `fly deploy`
- Docker + cloud run → custom script (read from wiki/operations/deploy-runbook.md)
- Else: ask user for the deploy command

Run the deploy command with `run_in_background: true` and timeout `300000` (5 min).
Stream progress to user.

## Step 4 — Wait for Deploy Completion

Poll the deploy status until complete or failed.
Report every 30 seconds: "Deploy in progress: {stage}..."

## Step 5 — Post-Deploy Health Check

After deploy reports success:

1. **Smoke test endpoints**
   - GET the health check URL (read from wiki/operations/deploy-runbook.md)
   - Expect 200 within 30s
   - If fails: trigger rollback (Step 6)

2. **Check error tracking**
   - Wait 2 minutes
   - Query error tracking for new errors since deploy timestamp
   - If error rate > baseline: warn user

3. **Check key metrics**
   - p95 latency vs baseline
   - 5xx rate vs baseline
   - If degraded: warn user

4. **Verify audit logging is producing events**
   - Trigger a known event (synthetic if possible)
   - Verify it appears in audit logs

## Step 6 — Rollback (if needed)

If post-deploy health check fails:

1. Alert user immediately: "Deploy succeeded but health check failed. ROLLING BACK."
2. Execute rollback per `wiki/operations/rollback-runbook.md`:
   - Vercel: `vercel rollback`
   - Netlify: redeploy previous deploy ID
   - Cloud Run: `gcloud run services update --image={previous-image}`
   - Else: per-project rollback command
3. Verify rollback succeeded (re-run smoke tests)
4. Create an incident entry via `/incident`
5. Report to user with full timeline

## Step 7 — Record Deploy

Append to `wiki/operations/deploy-log.md`:

```markdown
## {YYYY-MM-DD HH:MM} — {env}

- Commit: {sha} ({message})
- PR:     {URL}
- Author: {user}
- Result: SUCCESS / ROLLED BACK
- Duration: {N} min
- Notes:  {anything notable}
```

If production: also update `wiki/PROJECT_STATUS.md` with the new prod version.

## Step 8 — Report

```
Deploy Complete — {env}

  Result:        ✅ SUCCESS (or ❌ ROLLED BACK)
  Commit:        {sha} ({message})
  Duration:      {N} min
  Health check:  PASS / FAIL
  Error rate:    {N} errors (delta vs baseline)
  P95 latency:   {N}ms (delta vs baseline)

  Logs:          {URL}
  Errors:        {URL}
  Metrics:       {URL}
  Live URL:      {URL}

  Recorded:      wiki/operations/deploy-log.md

  (Production only)
  PROJECT_STATUS.md updated with new prod version.
```

## Pitfalls

- Skipping gates "just this once" — that's when things break
- Deploying without a rollback plan — recovery becomes panic
- Deploying with uncommitted changes — what's actually live is unknown
- Deploying without checking compliance gaps — auditors will catch this
- Deploying migrations without backward-compat — breaks rolling deploys
- Not verifying post-deploy health — silent failures until users complain

## Verification

- All gates passed before deploy ran
- Deploy command exited successfully
- Health check passed within SLA
- Deploy logged in wiki/operations/deploy-log.md
- For production: PROJECT_STATUS.md updated
- If failed: rollback executed AND incident created
