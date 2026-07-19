---
name: env-setup
description: |
  TRIGGER when: the user wants to set up environment separation (dev/staging/prod),
  asks about env vars management, needs to onboard a new env, or wants to fix
  inconsistent env handling.
  DO NOT TRIGGER when: the user wants secrets rotation only (that's an ops task),
  or just wants to add a single env var (just edit .env.example directly).
disable-model-invocation: true
user_locked: true
pinned: true
---

# Environment Setup

## When to Use

When a project needs proper dev/staging/production separation, or has drifted
into inconsistent env handling and needs cleanup. Required for production streams.

## Procedure

## Step 1 — Stream Check

Read project CLAUDE.md to confirm stream.
If learning: STOP. Env separation is overkill for learning projects.

## Step 2 — Audit Current State

Detect what currently exists:
- `.env.example`
- `.env.development.example`
- `.env.staging.example`
- `.env.production.example`
- `.env.development`
- `.env.staging`
- `.env.production`
- `.env`
- Process.env / os.environ usage in code
- Any secrets in code (delegate quick scan to Security Auditor if needed)

Report what's present and what's missing.

## Step 3 — Define Required Env Vars

Read project code to identify referenced env vars:
- Node: grep for `process.env.*`
- Python: grep for `os.environ`, `os.getenv`, `getenv`
- Other: ask user

Categorize each var:
- **Public** (safe in client bundles, OK to commit non-prod values)
- **Secret** (must never be in client bundles or committed)
- **URL/host** (different per environment but not sensitive)
- **Feature flag** (boolean toggles for behavior)

## Step 4 — Generate Per-Environment Examples

Create or update:

**`.env.example`** (shared baseline, all vars with placeholder values):
```
# Public
APP_NAME=My App
PUBLIC_URL=http://localhost:3000

# URL/host
DATABASE_URL=postgres://user:pass@localhost:5432/mydb_dev
REDIS_URL=redis://localhost:6379

# Secret (NEVER commit real values)
JWT_SECRET=replace-with-strong-random-string
STRIPE_SECRET_KEY=sk_test_...
SENDGRID_API_KEY=SG.replace-me

# Feature flags
FEATURE_NEW_ONBOARDING=false
```

**`.env.development.example`** (overrides for dev):
```
NODE_ENV=development
LOG_LEVEL=debug
DATABASE_URL=postgres://user:pass@localhost:5432/mydb_dev
```

**`.env.staging.example`** (overrides for staging):
```
NODE_ENV=staging
LOG_LEVEL=info
PUBLIC_URL=https://staging.myapp.com
DATABASE_URL=<staging-db-url-here>
```

**`.env.production.example`** (overrides for prod):
```
NODE_ENV=production
LOG_LEVEL=warn
PUBLIC_URL=https://myapp.com
DATABASE_URL=<production-db-url-here>
# All secrets in production come from the secret manager, not the file
```

## Step 5 — Update .gitignore

Ensure these are ignored (NOT the `.example` files):
```
.env
.env.local
.env.development
.env.staging
.env.production
.env.*.local
```

## Step 6 — Choose Secret Manager (Production)

For production stream, the user needs a secret manager. Present options
(vendor-neutral):

| Option | Pros | Cons | Use when |
|--------|------|------|----------|
| **Vercel/Netlify env vars** | Free if hosting there, easy | Vendor-locked | Hosting on those platforms |
| **AWS Secrets Manager** | Robust, audit logs, rotation | Setup complexity | Already on AWS |
| **GCP Secret Manager** | Same as AWS for GCP | Same as AWS | Already on GCP |
| **Doppler** | Platform-agnostic, free tier | Subscription at scale | Multi-cloud |
| **Infisical** | Open-source option | Self-host or paid | Cost-conscious |
| **1Password Secrets Automation** | If already using 1Password | Subscription | Already using 1Password |

Ask the user: "Which secret manager? (or 'recommend' for cheapest/easiest)"
Don't pick for them.

## Step 7 — Generate Documentation

Write `wiki/operations/environments.md`:

```markdown
# Environment Setup

## Environments
- **development** — local dev on developer machine
- **staging** — pre-production env mirroring production config
- **production** — live customer-facing env

## Env Files
| File | Committed? | Purpose |
|------|-----------|---------|
| .env.example | YES | Baseline shared vars (placeholder values) |
| .env.development.example | YES | Dev-specific overrides |
| .env.staging.example | YES | Staging-specific overrides |
| .env.production.example | YES | Production placeholders (no real values) |
| .env (dev) | NO | Actual dev values, gitignored |
| .env.staging | NO | Actual staging values, gitignored |
| .env.production | NO | NEVER stored locally — comes from secret manager |

## Secret Manager
{Chosen vendor — TBD}

## Adding a New Env Var
1. Add to `.env.example` with placeholder
2. Add to env-specific example files if values differ
3. Document the var in this file (table below)
4. Add to secret manager if it's secret

## Variables

| Name | Type | Description | Example | Required? |
|------|------|-------------|---------|-----------|
| DATABASE_URL | URL | Postgres connection | postgres://... | yes |
| JWT_SECRET | Secret | JWT signing key (32+ char random) | (generate) | yes |
| ... | ... | ... | ... | ... |

## Local Dev Setup
1. Copy `.env.example` to `.env`
2. Copy `.env.development.example` to `.env.development`
3. Fill in real values
4. Run `npm run dev` (or equivalent)

## Production Deployment
- Production env vars are pushed from the secret manager to the host
- Do NOT manually edit production env files
- Rotate secrets quarterly (see incident-response.md)
```

## Step 8 — Report

```
Environment Setup Complete

  Examples created/updated:
    .env.example
    .env.development.example
    .env.staging.example
    .env.production.example

  .gitignore updated:    {yes/already had it}
  Secret manager:        {chosen / TBD}
  Documentation:         wiki/operations/environments.md

Next steps:
  1. Sign up for {secret manager}
  2. Push current production secrets to the secret manager
  3. Wire deployment to pull from secret manager on deploy
  4. Rotate any secrets that were ever in git history
```

## Pitfalls

- Committing `.env` (not `.env.example`) — exposes secrets
- Different env var names across environments — silent failures in prod
- Treating staging env as identical to prod when it should be — bugs slip past
- Storing prod secrets in .env.production file locally — defeats secret manager
- Forgetting to update `.env.example` when adding a new var — onboarding breaks

## Verification

- `.env.example` and per-env `.example` files exist
- `.gitignore` excludes all real env files
- Documentation in `wiki/operations/environments.md` lists every var
- Secret manager choice is documented
- No real secrets exist in any committed file
