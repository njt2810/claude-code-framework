---
name: data-inventory
description: |
  TRIGGER when: the user wants to map PII flows, build a data inventory,
  asks "what personal data do we collect", needs to document data handling
  for PDPA / SOC 2 / a client questionnaire, or wants to know where user data lives.
  DO NOT TRIGGER when: the user wants a security scan (use /security-check),
  a compliance gap report (use /compliance-audit), or general docs (use /document-all).
disable-model-invocation: true
effort: high
user_locked: true
pinned: true
---

# Data Inventory — Map PII Flows

## When to Use

When the project needs a documented inventory of every piece of personal data
it collects, processes, stores, or transmits. Required for PDPA accountability
and SOC 2 evidence. Should be run on every production project and updated
whenever a new data type is introduced.

## Procedure

## Step 1 — Stream Check

Read project CLAUDE.md to determine stream.
If stream is `learning`: STOP. Data inventory is for production streams.

## Step 2 — Scan Codebase for PII

Delegate to the Compliance Officer subagent (or Security Auditor if Compliance
Officer not installed):

"Scan this codebase and identify every PII field. PII includes but is not
limited to:

Direct identifiers:
  - email, phone, name, address, date of birth, photo, voice, biometric

Quasi-identifiers:
  - IP address, device ID, location data, MAC address, browser fingerprint

Sensitive PII:
  - government ID (NRIC/passport), financial (card, bank), health, religious,
    political, criminal records, sexual orientation

For each PII field found, document:
  - Field name (in code)
  - Where it's collected (which file/endpoint)
  - Where it's stored (which table/file/store)
  - Where it's transmitted (which external services receive it)
  - How long it's retained (if documented)
  - Encryption status (at rest / in transit)
  - Access controls (who can read it)

Return as a structured table."

## Step 3 — Write Data Inventory

Write `wiki/compliance/data-inventory.md`:

```markdown
# Data Inventory

Last updated: {YYYY-MM-DD}
Project: {project name}
Stream: {stream}

## PII Fields

| Field | Type | Collected At | Stored At | Transmitted To | Retention | Encryption | Access |
|-------|------|--------------|-----------|----------------|-----------|-----------|--------|
| email | Direct | /api/signup, /api/login | users table | SendGrid (txn email), Posthog (analytics) | indefinite (TODO: set policy) | TLS + AES-256 at rest | admin, the user |
| ... | ... | ... | ... | ... | ... | ... | ... |

## Data Flows

### Flow 1: User Signup
1. User submits form at `/signup`
2. Frontend POSTs to `/api/signup`
3. Backend validates, hashes password, stores in `users` table
4. Backend sends confirmation email via SendGrid
5. Backend logs signup event to audit log

PII processed: email, name, IP address
External services: SendGrid (sees email + name)
Retention: until account deletion + 30 days

### Flow 2: ...

## Sensitive PII

{List any sensitive PII separately — these require extra scrutiny}

## Cross-Border Transfers

| Destination | Country | Data Sent | Legal Basis | DPA in Place |
|-------------|---------|-----------|-------------|--------------|
| SendGrid    | USA     | email, name | Necessary for service | TODO: verify |

## Gaps and Remediation

- {Gap 1} — {how to fix}
- {Gap 2} — {how to fix}

## Retention Policy

| Data Type | Retention Period | Reason | Deletion Mechanism |
|-----------|-----------------|--------|-------------------|
| User accounts | Indefinite while active | Service operation | User-initiated delete |
| Audit logs | 12 months | SOC 2 evidence | Cron job (TBD) |
| Backups | 30 days | DR | S3 lifecycle policy |
```

## Step 4 — Identify Gaps

After the inventory is written, list gaps:
- Fields with no documented retention policy
- Fields not encrypted at rest
- External services without a DPA
- Cross-border transfers without legal basis
- Fields collected but not actually used (data minimization violation)

## Step 5 — Report

```
Data Inventory Complete

PII fields documented:  {N}
Sensitive PII:          {N} (extra scrutiny needed)
External services:      {N} (verify DPAs)
Cross-border transfers: {N}

Gaps identified:
  - {N} fields without retention policy
  - {N} services without DPA
  - {N} fields not encrypted at rest
  - {N} possible data minimization violations

Full inventory: wiki/compliance/data-inventory.md

Next steps:
  - Set retention policies for fields flagged
  - Request DPAs from vendors flagged
  - Run /vendor-review to formalize vendor assessment
  - Run /compliance-audit to check overall PDPA/SOC 2 status
```

## Pitfalls

- Treating only "obvious" PII as PII — IP addresses, device IDs, location are PII under PDPA/GDPR
- Forgetting external services (analytics, error tracking, email) — they often see PII
- Not capturing cross-border transfers — this is a major PDPA compliance area
- Letting the inventory go stale — re-run after every schema change
- Inferring fields are encrypted at rest — verify with the actual infrastructure config

## Verification

- Every PII field in the codebase is in the inventory
- Each field has all 7 attributes filled (type, collected, stored, transmitted, retention, encryption, access)
- External services that see PII are flagged for DPA verification
- Cross-border transfers are documented with legal basis
- Gaps are listed with concrete remediation actions
