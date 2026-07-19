---
name: audit-logging-setup
description: |
  TRIGGER when: the user needs to set up audit logging, asks "what should we be logging",
  needs SOC 2 evidence collection wired in, or is preparing for compliance.
  DO NOT TRIGGER when: the user wants observability/error tracking (use /observability-setup),
  or normal application logs (those are separate from audit logs).
disable-model-invocation: true
user_locked: true
pinned: true
---

# Audit Logging Setup

## When to Use

When a production project needs audit logging — a tamper-evident record of
who did what when, separate from application logs. Required for SOC 2 evidence
and PDPA accountability. Distinct from observability (errors, metrics).

## Procedure

## Step 1 — Stream Check

Read CLAUDE.md to confirm production stream.
If learning: STOP. Audit logging is for production.

## Step 2 — Detect Stack

Detect the project stack:
- `package.json` → Node.js / TypeScript
- `pyproject.toml` or `requirements.txt` → Python
- `Gemfile` → Ruby
- `go.mod` → Go
- Other → ask the user

## Step 3 — Identify Events to Log

Standard audit events (always log these for production projects):

**Authentication events:**
- user.login (success and failure)
- user.logout
- user.password_reset_requested
- user.password_changed
- user.mfa_enabled / mfa_disabled
- user.session_expired

**Account events:**
- user.created
- user.deleted
- user.role_changed
- user.email_changed

**Data events:**
- data.export (user requests their data)
- data.deletion_request (user requests deletion)
- data.viewed (admin views user data)
- data.modified (record changes outside normal user flow)

**Admin events:**
- admin.config_changed
- admin.user_impersonated
- admin.permission_granted / revoked
- admin.feature_flag_toggled

**Payment events (if applicable):**
- payment.attempted
- payment.succeeded
- payment.failed
- payment.refunded
- subscription.created / canceled

**Compliance events:**
- consent.granted / withdrawn
- privacy.policy_accepted

Ask the user: "Any additional events specific to this project? (e.g., {project-specific examples})"

## Step 4 — Choose Storage

Audit logs must be:
- **Append-only** (no updates, no deletions)
- **Tamper-evident** (cryptographic hash chain, or trusted timestamping, or external sink)
- **Retained** for at least 12 months (longer if regulated)
- **Queryable** for incident investigation

Present options to the user (don't pick — they choose):

| Option | Pros | Cons | Approx. cost |
|--------|------|------|--------------|
| **Better Stack (Logtail)** | Easy setup, search UI, SOC 2 compliant | Subscription cost | ~$25/mo to start |
| **AWS CloudWatch + S3 (Glacier for old)** | Cheap at low volume, native to AWS | Setup complexity | <$10/mo small scale |
| **Logflare** | Postgres backend, GraphQL queries | Less polished UI | ~$10/mo |
| **Datadog Logs** | Best UX, integrates with metrics | Expensive | $1.27/GB ingested |
| **Self-hosted (Loki, Vector)** | No vendor lock-in | You operate it | infrastructure cost |
| **PostgreSQL append-only table + cron-to-S3** | Cheapest, simple | DIY tamper-evidence | infrastructure cost |

Ask: "Which storage do you want? (or 'recommend' for cheapest/safest path)"

## Step 5 — Generate Helper Code

Based on stack, generate `src/lib/audit-log.ts` (Node) or `src/audit_log.py`
(Python) or equivalent.

**Node/TypeScript template:**

```typescript
// src/lib/audit-log.ts
// Audit log helper — append-only event recorder for SOC 2 evidence
// Storage: {chosen vendor}

import { randomUUID } from "crypto";

export type AuditEvent = {
  id?: string;              // auto-generated if omitted
  actor: string;            // user_id, "system", or "anonymous"
  action: string;           // e.g., "user.login.success"
  resource: string;         // e.g., "user:abc123", "config:feature.x"
  outcome: "success" | "failure";
  metadata?: Record<string, unknown>;
  ip?: string;              // request IP if available
  user_agent?: string;
  timestamp?: string;       // auto-set if omitted, ISO 8601
};

const REDACT_KEYS = ["password", "token", "secret", "api_key", "ssn", "credit_card"];

function redact(metadata: Record<string, unknown> | undefined): Record<string, unknown> | undefined {
  if (!metadata) return metadata;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(metadata)) {
    if (REDACT_KEYS.some(r => k.toLowerCase().includes(r))) {
      out[k] = "[REDACTED]";
    } else {
      out[k] = v;
    }
  }
  return out;
}

export async function audit(event: AuditEvent): Promise<void> {
  const enriched: AuditEvent = {
    id: event.id ?? randomUUID(),
    timestamp: event.timestamp ?? new Date().toISOString(),
    ...event,
    metadata: redact(event.metadata),
  };

  // TODO: wire to {chosen vendor}
  // For now, JSON to stdout — replace with vendor SDK call
  console.log("[AUDIT]", JSON.stringify(enriched));
}
```

**Python template:**

```python
# src/audit_log.py
# Audit log helper — append-only event recorder for SOC 2 evidence
# Storage: {chosen vendor}

import json
import uuid
from datetime import datetime
from typing import Any, Literal

REDACT_KEYS = ["password", "token", "secret", "api_key", "ssn", "credit_card"]


def _redact(metadata: dict[str, Any] | None) -> dict[str, Any] | None:
    if not metadata:
        return metadata
    out = {}
    for k, v in metadata.items():
        if any(r in k.lower() for r in REDACT_KEYS):
            out[k] = "[REDACTED]"
        else:
            out[k] = v
    return out


def audit(
    actor: str,
    action: str,
    resource: str,
    outcome: Literal["success", "failure"],
    metadata: dict[str, Any] | None = None,
    ip: str | None = None,
    user_agent: str | None = None,
) -> None:
    event = {
        "id": str(uuid.uuid4()),
        "actor": actor,
        "action": action,
        "resource": resource,
        "outcome": outcome,
        "metadata": _redact(metadata),
        "ip": ip,
        "user_agent": user_agent,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }
    # TODO: wire to {chosen vendor}
    print("[AUDIT]", json.dumps(event))
```

## Step 6 — Document

Create or update `wiki/compliance/audit-logging.md`:

```markdown
# Audit Logging

## Storage
{Chosen vendor}, {retention period}

## Helper Location
- {language}: `src/lib/audit-log.ts` (or `src/audit_log.py`)

## Events Logged
{Table of all events with description}

## Redaction
The helper auto-redacts these field names: password, token, secret, api_key, ssn, credit_card.

## How to Add a New Event
1. Identify the event name (`{domain}.{action}.{outcome}`)
2. Call `audit({...})` at the point where the action completes
3. Include actor, resource, and minimal metadata (no PII unless necessary)
4. Update the Events Logged table here

## Retention
{N} months in hot storage, then {N} months in cold storage (Glacier / S3 IA).
Total retention: at least 12 months for SOC 2 evidence.

## Tamper Evidence
{If using append-only log with hash chain: describe}
{If using vendor SOC 2 sink: vendor enforces append-only}

## Querying for Investigations
{How to query for incident response — example commands}
```

## Step 7 — Report

```
Audit Logging Setup Complete

  Helper file:    {path}
  Storage:        {vendor — TBD on user's side}
  Events covered: {N} standard events + {N} project-specific

Required next steps:
  1. Sign up for {chosen vendor} and obtain API credentials
  2. Wire the helper to the vendor SDK (TODO comments in the file)
  3. Test by triggering a known event (e.g., login) — verify it shows up in vendor UI
  4. Add audit() calls at critical points in your codebase
  5. Document any project-specific events in wiki/compliance/audit-logging.md

Update: wiki/compliance/evidence-index.md — add audit log location
```

## Pitfalls

- Logging PII in audit metadata defeats the purpose — use IDs not values
- Forgetting redaction lets secrets leak into audit logs
- Treating application logs (errors, info, debug) as audit logs — they aren't tamper-evident
- Not setting retention long enough — SOC 2 typically wants 12+ months
- Audit logs in the same DB as application data — easier to lose / corrupt together

## Verification

- Helper file created at the right path for the stack
- Helper redacts sensitive fields by default
- `wiki/compliance/audit-logging.md` documents events, storage, retention
- User knows the next concrete step (wire helper to vendor)
- Evidence index updated
