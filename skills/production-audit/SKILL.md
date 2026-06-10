---
name: production-audit
description: |
  TRIGGER when: the user asks "production ready?", "ready to deploy?", "audit this",
  "day 2 readiness", "production audit", wants a health check before deploying or
  showing to clients, or requests a quarterly project review.
  DO NOT TRIGGER when: the user wants a code review (/code-review), security-only
  audit (/security-check), project status (/status), or framework health (/framework-check).
effort: high
context: fork
user_locked: true
pinned: true
---

# Production Audit — Enterprise Day-2 Readiness Assessment

## When to Use

Before deploying to production, showing to clients, making a repo public,
or as a quarterly health check. Not for code reviews, security-only audits, or status checks.

## Procedure

Run a strict, evidence-based production-readiness audit across 12 sections.
Check for REAL EVIDENCE — files, configs, CI definitions, test directories.
Do not assume. Do not hallucinate systems. If you cannot verify, mark Missing.

## Step 1 — Gather Evidence

Before scoring anything, collect evidence by reading files and running commands:

```
Gathering evidence for production audit...
```

Check each of these (report what you find, not what you assume):

- `.github/workflows/` or CI config (Circle, GitLab, Jenkins)
- Test directories and test runner config (jest, pytest, vitest, playwright)
- Coverage config (--coverage flag, nyc, c8, pytest-cov)
- `.env.example` and `.gitignore` (secrets handling)
- `package-lock.json`, `yarn.lock`, `requirements.txt` (lockfiles)
- `Dockerfile`, `docker-compose.yml`, `vercel.json`, `railway.json` (deployment)
- Health check endpoints (`/health`, `/healthz`, `/api/health`)
- Logging setup (structured logging, log levels, error tracking like Sentry)
- Monitoring config (Grafana, Datadog, CloudWatch, UptimeRobot)
- Runbooks (`wiki/runbooks/`, `RUNBOOK.md`, `docs/runbook`)
- `CODEOWNERS`, owner references in README or wiki
- Git branch protection (check recent main commits for direct vs PR merges)
- Rate limiting middleware
- Input validation schemas (zod, joi, pydantic)
- Error handling patterns (try/catch, error boundaries, fallbacks)

## Step 2 — Score Each Section

For each of the 12 sections, assign: **Present** / **Partial** / **Missing**

### Section 1: Source Control & Change Safety
- Git initialized with remote
- Branch protection (no direct commits to main)
- PR-based workflow with review requirement
- Meaningful commit messages
- .gitignore covers secrets and build artifacts

### Section 2: Automated Quality Gates
- Unit tests exist and run
- Integration tests exist
- End-to-end tests exist
- Linting configured and enforced
- Tests run in CI (not just locally)
- Coverage reporting configured

### Section 3: Configuration & Secrets Management
- All secrets in environment variables (not in code)
- .env.example exists with placeholders
- .env is gitignored
- No secrets in git history
- Secret rotation strategy exists

### Section 4: Deployment Model
- Deployment config exists and is reproducible
- Staging/preview environment exists
- Rollback mechanism documented
- Deploy process documented step-by-step
- Zero-downtime deployment (if applicable)

### Section 5: Observability & Operability
- Structured logging (not just console.log)
- Error tracking (Sentry, Bugsnag, etc.)
- Request/response logging on APIs
- Log levels properly used (error, warn, info, debug)
- Logs are searchable (not just in terminal)

### Section 6: SLOs & Signal Quality
- SLIs defined (latency, error rate, availability)
- SLO targets set (99.9% uptime, p95 < 500ms, etc.)
- Alerts configured for SLO breaches
- Error budget tracking
- Alert-to-impact mapping (which alert means which user impact?)

### Section 7: Failure Readiness
- Health check endpoint exists
- Auto-restart on crash (PM2, Docker restart, serverless)
- Dependency outage handling (timeouts, retries, circuit breakers)
- Graceful degradation (app works with reduced functionality)
- Data backup strategy

### Section 8: Capacity, Scaling & Cost Controls
- Resource limits configured (memory, CPU, connections)
- Autoscaling configured (if applicable)
- Cost visibility (billing alerts, usage tracking)
- Rate limiting on public endpoints
- Database connection pooling

### Section 9: Operational Ownership & Runbooks
- Clear owner defined (who gets called when it breaks?)
- Runbook exists with common scenarios
- Escalation path documented
- Deploy/rollback runbook
- Debugging guide (common errors, log locations, diagnostic commands)

### Section 10: Runtime & Supply Chain Security
- Dependencies pinned (exact versions in lockfile)
- No known high/critical CVEs (npm audit / pip-audit)
- Docker images use official bases with pinned tags (not :latest)
- Input validation on all public endpoints
- SBOM available (lockfile counts)

### Section 11: Risk Summary
- Top 5 risks identified with likelihood x impact
- Scaling blockers identified
- Single points of failure mapped
- Data loss scenarios assessed
- Compliance requirements checked (if applicable)

### Section 12: Day-2 Action Plan
- Prioritized backlog of gaps
- Each item labeled: Agent-implementable or Human decision
- 30/60/90-day milestones
- Quick wins identified (fixable in < 1 hour)

## Step 3 — Calculate Score

Score = (Present sections x 8.33) + (Partial sections x 4.17)
Round to nearest integer.

| Score | Rating | Meaning |
|-------|--------|---------|
| 0-30 | Fragile Prototype | Install basic guardrails: CI, tests, rollback, logging |
| 31-60 | Ship-at-your-own-risk | Formalise deploys + observability + secrets hygiene |
| 61-80 | Real Business Ready | SLOs, alert quality, incident playbooks, cost controls |
| 81-100 | Operator-Grade | Optimise speed and reliability, not survival |

## Step 4 — Present Results

```
━━━ PRODUCTION AUDIT ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Project: {name}
  Score: {score}/100 — {rating}
  Date: {today}

  SECTION RESULTS
  ───────────────
  1. Source Control & Change Safety    {Present/Partial/Missing}
  2. Automated Quality Gates           {Present/Partial/Missing}
  3. Configuration & Secrets           {Present/Partial/Missing}
  4. Deployment Model                  {Present/Partial/Missing}
  5. Observability & Operability       {Present/Partial/Missing}
  6. SLOs & Signal Quality             {Present/Partial/Missing}
  7. Failure Readiness                 {Present/Partial/Missing}
  8. Capacity, Scaling & Cost          {Present/Partial/Missing}
  9. Operational Ownership & Runbooks  {Present/Partial/Missing}
  10. Runtime & Supply Chain Security  {Present/Partial/Missing}
  11. Risk Summary                     (narrative below)
  12. Day-2 Action Plan                (narrative below)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Step 5 — Risk Narrative

Present the top 5 risks:

```
  TOP 5 RISKS
  ───────────
  1. {risk} — Likelihood: {H/M/L} x Impact: {H/M/L}
  2. ...
```

## Step 6 — Action Plan

Split into agent-fixable vs human decisions:

```
  AGENT-IMPLEMENTABLE (I can fix these now):
  ──────────────────────────────────────────
  - [ ] {item} — estimated: {time}
  - [ ] {item} — estimated: {time}

  HUMAN DECISIONS REQUIRED (you need to decide):
  ───────────────────────────────────────────────
  - {decision} — why you need to decide: {reason}
  - {decision} — why you need to decide: {reason}

  90-DAY ROADMAP
  ──────────────
  Week 1-2:  {quick wins and critical gaps}
  Week 3-4:  {deployment and observability}
  Week 5-8:  {SLOs, runbooks, failure readiness}
  Week 9-12: {optimisation and hardening}
```

Then ask:
"I found {N} items I can fix right now. Fix these? (yes / pick individually / skip)"

## Step 7 — Delegate to Specialists

After presenting results, delegate verification to the expanded agents:

- Code Reviewer: verify CI/CD and deployment findings
- Test Engineer: verify coverage and failure readiness findings
- Security Auditor: verify supply chain and runtime security findings
- Wiki Updater: verify operational documentation findings

Each agent's expanded scope now covers these production-readiness checks.

## Notes

- Be strict — if you can't verify it exists, mark it Missing
- Don't count plans or intentions — only what's actually built
- A lockfile with floating deps is Partial, not Present
- Console.log is not structured logging
- "We use Vercel" is not a rollback strategy unless documented
- Tests that don't run in CI are Partial, not Present

## Pitfalls

- Assuming systems exist based on framework names in dependencies — verify they're configured
- Counting plans or intentions as Present — only what's actually built counts
- Console.log is not structured logging
- "We use Vercel" is not a rollback strategy unless documented
- A lockfile with floating deps is Partial, not Present

## Verification

- All 12 sections were scored with real evidence
- Score calculation matches the evidence (no inflation)
- Agent-implementable items were correctly distinguished from human decisions
- Specialist agents verified their respective sections
