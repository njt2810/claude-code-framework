> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Incident Response Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Annual + after every P1 incident

## Purpose

Detect, respond to, contain, and recover from security and operational incidents.

## Scope

Any event that:
- Affects customer-facing service
- Compromises confidentiality, integrity, or availability of data
- Triggers regulatory notification obligations (e.g., PDPA Notifiable Data Breach)

## Severity Classification

| Severity | Criteria | Response SLA |
|----------|----------|--------------|
| **P0 / Critical** | Production down, data loss, security breach, PII exposure | Immediate (within 1 hour) |
| **P1 / High** | Major feature broken for paid customers, partial outage | Within 4 hours |
| **P2 / Medium** | Annoying but workaround exists | Within 1 business day |
| **P3 / Low** | Minor degradation, cosmetic | Within 1 week |

## Activation

`/incident` skill activates the workflow.

For Notifiable Data Breaches under PDPA Part VIA:
- 72-hour notification deadline to PDPC
- Notification to affected individuals if criteria met
- See `wiki/operations/breach-notification-template.md`

## Roles

For solo founder stage:
- **Incident Commander:** Founder (you)
- **Communications:** Founder
- **Technical Lead:** Founder

As team grows, separate these roles. Document in `wiki/operations/on-call-rotation.md`.

## Phases

1. **Detect** — Alerts, customer reports, observability
2. **Triage** — Severity assessed, incident declared via /incident
3. **Stabilize** — Stop the bleeding (rollback, feature flag off, etc.)
4. **Communicate** — Update status page, notify affected customers within SLA
5. **Investigate** — Identify root cause
6. **Resolve** — Deploy fix, verify stable
7. **Postmortem** — Document within 5 days
8. **Action items** — Track remediations to closure

## Documentation Requirements

Every P0/P1 incident produces:
- Incident file at `wiki/operations/incidents/{date}-{slug}.md`
- Postmortem section within 5 days
- Action items tracked to closure
- Entry in `wiki/compliance/evidence/incidents-log.md`

## Regulatory Notification

PDPA Notifiable Data Breach criteria (PDPA Part VIA):
- Significant harm to individuals (e.g., financial loss, identity theft risk)
- Affects ≥ 500 individuals

If criteria met:
- Notify PDPC within 72 hours of becoming aware
- Notify affected individuals (unless exempted)
- Use template at `wiki/operations/breach-notification-template.md`

## Tests

Annual tabletop exercise (simulated incident) to verify the team can execute this policy.
Documented in `wiki/compliance/evidence/`.

## Review

After every P0/P1: review what went well, what didn't, update this policy if process gaps revealed.
