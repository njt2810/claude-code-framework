# Asset Inventory

Every system, service, and data store the project depends on.
SOC 2 prerequisite. Updated whenever a new asset is added.

## Production Systems

| Asset | Type | Vendor | Region | Purpose | Owner | Criticality |
|-------|------|--------|--------|---------|-------|-------------|
| {{APP_HOST}} | Compute | {{VENDOR}} | {{REGION}} | App hosting | {{OWNER}} | Tier 1 |
| {{DB}} | Database | {{VENDOR}} | {{REGION}} | Primary data | {{OWNER}} | Tier 1 |
| {{FILE_STORE}} | Storage | {{VENDOR}} | {{REGION}} | User uploads | {{OWNER}} | Tier 1 |
| {{CACHE}} | Cache | {{VENDOR}} | {{REGION}} | Session, rate limit | {{OWNER}} | Tier 2 |
| {{EMAIL}} | Transactional email | {{VENDOR}} | | Auth emails | {{OWNER}} | Tier 1 |
| {{BILLING}} | Payments | {{VENDOR}} | | Subscriptions | {{OWNER}} | Tier 1 |
| {{ERROR_TRACKING}} | Observability | {{VENDOR}} | | Error tracking | {{OWNER}} | Tier 2 |
| {{LOGS}} | Observability | {{VENDOR}} | | Log shipping | {{OWNER}} | Tier 2 |
| {{AUDIT_LOG}} | Audit | {{VENDOR}} | | SOC 2 evidence | {{OWNER}} | Tier 1 |

## Data Stores

| Store | Contains | PII? | Encryption | Backup | Retention |
|-------|----------|------|-----------|--------|-----------|
| {{DB}} | Users, sessions, business data | Yes (Restricted) | At-rest + in-transit | Daily snapshot | Per data-retention.md |
| {{FILE_STORE}} | User uploads | Sometimes | At-rest + in-transit | Versioning | Per data-retention.md |
| Audit logs | Auth events, admin actions | No (IDs only) | At-rest + in-transit | Glacier | 12 months hot + 12 months cold |

## Development Systems

| Asset | Type | Vendor | Purpose |
|-------|------|--------|---------|
| {{REPO}} | Code | GitHub | Source code |
| {{CI}} | CI/CD | GitHub Actions | Test and deploy |
| {{SECRET_MGR}} | Secrets | {{VENDOR}} | Production secrets |

## Tier Definitions

- **Tier 1 (Critical)** — service cannot operate without this
- **Tier 2 (Important)** — service degraded if this fails, but operational
- **Tier 3 (Low)** — failure has minimal user-visible impact

## Review

- Annually: full asset inventory review
- On change: update within 7 days of asset addition or removal
- On vendor change: update register + run `/vendor-review`
