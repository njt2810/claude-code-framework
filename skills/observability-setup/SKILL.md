---
name: observability-setup
description: |
  TRIGGER when: the user wants to set up error tracking, structured logging,
  metrics, alerting, or any "what's happening in production" tooling. Also when
  the project has zero visibility into prod issues.
  DO NOT TRIGGER when: the user wants audit logs (use /audit-logging-setup) or
  data analytics (different concern).
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Observability Setup

## When to Use

When a production project needs error tracking, structured logging, metrics,
or alerting. Distinct from audit logging (compliance-driven) — this is
operational visibility.

## Procedure

## Step 1 — Stream Check & Existing State

Read CLAUDE.md to confirm production stream.
Detect what's already installed:
- Sentry, Rollbar, Bugsnag (error tracking)
- Datadog, New Relic, Grafana (metrics)
- Pino, Winston, structlog (structured logging)
- PagerDuty, Opsgenie (alerting)

## Step 2 — Four Pillars

Cover all four pillars of observability:

| Pillar | What | Examples |
|--------|------|----------|
| **Error tracking** | Catches exceptions, ties to user/request | Sentry, Rollbar, Bugsnag |
| **Logs** | Structured event records, queryable | Pino+Better Stack, Logflare, Datadog Logs |
| **Metrics** | Numerical time-series (req/s, latency, errors) | Prometheus+Grafana, Datadog, Vercel Analytics |
| **Alerts** | Page humans when thresholds breach | PagerDuty, Opsgenie, native vendor alerts |

For each pillar, present vendor-neutral options. Don't pick — the user picks.

## Step 3 — Error Tracking Setup

Recommend SENTRY for most projects (generous free tier, broad SDK support).
Alternatives: Rollbar, Bugsnag, Honeybadger.

Walk the user through:
1. Sign up at the chosen vendor
2. Create a project, get DSN
3. Add DSN to `.env.example` placeholder and `.env` actual
4. Install SDK in the stack
5. Initialize at app boot
6. Test by throwing a test exception

Add SDK init code to the project (let user approve):
- Node/Next.js: `sentry.client.config.ts`, `sentry.server.config.ts`
- Python: `sentry-sdk` init in main entry
- Etc.

## Step 4 — Structured Logging Setup

Recommend:
- Node: **Pino** (fast, JSON output) + shipper
- Python: **structlog** (sane defaults, JSON output) + shipper
- Shipper: Better Stack Logs / Logflare / Datadog Logs

Walk through:
1. Install logger library
2. Create `src/lib/logger.ts` or `src/logger.py`
3. Set log levels per environment:
   - dev: debug
   - staging: info
   - production: warn (or info with sampling)
4. Replace any `console.log` / `print()` with logger calls
5. Configure log shipper

Logging conventions to enforce in `wiki/conventions.md`:
- Never log PII fields (use IDs)
- Use levels meaningfully: error / warn / info / debug
- Include correlation IDs for tracing requests
- Never log secrets, tokens, or session IDs

## Step 5 — Metrics Setup

For most projects, host metrics come from the host platform:
- **Vercel** — Vercel Analytics + Web Vitals (built-in)
- **Cloudflare** — Cloudflare Analytics (built-in)
- **AWS** — CloudWatch (built-in)
- **Self-hosted** — Prometheus + Grafana (DIY)

Custom application metrics (counters, histograms):
- Node: `prom-client` (Prometheus client)
- Python: `prometheus_client`
- Or push to vendor: Datadog StatsD, New Relic

Walk through setup based on host. Document in `wiki/operations/metrics.md`.

## Step 6 — Alerting Setup

Define alert rules based on what the project does. Common rules:
- HTTP 5xx rate > 1% over 5min
- p95 latency > 1s over 10min
- Error count from Sentry > 10/min
- Critical health check failing

For solo-founder stage: use vendor email/Slack alerts (free).
For team-of-2+: PagerDuty / Opsgenie with rotation.

Document alert rules in `wiki/operations/alerting.md`:
- Trigger condition
- Severity (P1=page, P2=Slack, P3=ticket)
- Acknowledgment SLA
- Escalation path

## Step 7 — Generate Documentation

Write `wiki/operations/observability.md`:

```markdown
# Observability

## Stack
- Error tracking: {vendor}
- Logs: {logger} + {shipper}
- Metrics: {vendor / built-in}
- Alerts: {vendor / email}

## How to View Production State
- Errors: {URL to Sentry dashboard}
- Logs: {URL to log explorer}
- Metrics: {URL to dashboard}
- Alerts: {URL to alert config}

## Conventions
- Log levels: dev=debug, staging=info, production=warn
- Never log: passwords, tokens, secrets, PII fields (use IDs)
- Always include: request ID, user ID (or "anonymous"), action

## Alert Rules
| Condition | Severity | Channel | SLA |
|-----------|----------|---------|-----|
| 5xx rate > 1% | P1 | Page | 5 min ack |
| ... | ... | ... | ... |

## When Something Breaks
1. Check {Sentry URL} for exception details
2. Search {Logs URL} for context around the timestamp
3. Check {Metrics URL} for system health
4. Follow `wiki/operations/incident-response.md`
```

## Step 8 — Report

```
Observability Setup Complete

  Error tracking:   {vendor} — DSN added to .env.example
  Logger:           {library} — `src/lib/logger.{ts,py}` created
  Log shipper:      {vendor} — wiring TBD on user side
  Metrics:          {built-in / vendor}
  Alerts:           {N} rules drafted in wiki/operations/alerting.md
  Documentation:    wiki/operations/observability.md

Next steps:
  1. Sign up for {chosen vendors} and get API keys
  2. Add keys to secret manager
  3. Deploy and verify error tracking captures a test exception
  4. Verify logs appear in the shipper UI
  5. Test one alert by triggering its condition deliberately
```

## Pitfalls

- Logging PII or secrets — discovered too late, hard to scrub
- Setting log level to debug in production — explosive volume + cost
- No correlation IDs — can't trace a request across services
- Setting up tools but never looking at them — observability without observation
- Alert fatigue from noisy rules — tune aggressively
- Different log formats across services — search becomes impossible

## Verification

- Error tracking SDK installed and DSN in env
- Logger library installed and `logger.ts` / `logger.py` exists
- `wiki/operations/observability.md` documents the full stack
- Alert rules drafted in `wiki/operations/alerting.md`
- User knows the URLs for each tool
