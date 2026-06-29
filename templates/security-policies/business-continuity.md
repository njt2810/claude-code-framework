> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Business Continuity Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Annual

## Purpose

Ensure continued service delivery during and after disruptive events.

## Scope

All systems, services, and personnel required to operate the Service.

## Recovery Objectives

- **RTO (Recovery Time Objective):** {{RTO_HOURS}} hours
- **RPO (Recovery Point Objective):** {{RPO_HOURS}} hours

(See `wiki/operations/disaster-recovery.md` for detailed procedures.)

## Critical Functions

| Function | Owner | Recovery Priority |
|----------|-------|-------------------|
| Customer-facing Service | {{OWNER}} | Highest |
| Customer support | {{OWNER}} | High |
| Billing | {{OWNER}} | High |
| Internal tooling | {{OWNER}} | Medium |

## Backup Strategy

Per `wiki/operations/disaster-recovery.md`:
- Primary database: continuous replication + daily snapshot
- Backups stored in different region from primary
- Backup encryption with separate key from production
- Quarterly restore drills

## Vendor Continuity

For critical vendors:
- Identify replacement vendors (documented in vendor-register.md)
- Maintain understanding of switching cost and time
- For Tier 1 vendors: have offline procedures for critical functions

## Personnel Continuity (bus-factor)

For solo founder stage:
- Cross-train trusted partner (spouse, co-founder, agency)
- Document runbooks comprehensively (anyone could follow them)
- Maintain "emergency access" procedure documented separately

## Incident Activation

This plan activates when:
- Production is unavailable for > 1 hour
- Critical vendor experiences outage > 4 hours
- Key personnel becomes unavailable (illness, etc.)
- Office/equipment becomes unusable

Activation triggers `/incident` workflow.

## Testing

- Quarterly: DR drill (restore test, see disaster-recovery.md)
- Annually: full BCP tabletop exercise

## Review

Annual review of this policy, RTO/RPO targets, and recovery procedures.
