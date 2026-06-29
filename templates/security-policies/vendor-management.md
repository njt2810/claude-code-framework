> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Vendor Management Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Annual

## Purpose

Manage third-party vendor risk through structured assessment, contracting, and ongoing review.

## Scope

All third-party services that:
- Process customer Personal Data
- Have access to production systems
- Are critical to service delivery
- Cost more than {{COST_THRESHOLD}}/month

## Vendor Onboarding

Before engaging a new vendor:
1. Run `/vendor-review {vendor-name}` (inbound mode)
2. Verify SOC 2 / ISO 27001 status (or equivalent)
3. Sign DPA if PII will be processed
4. Document in `wiki/compliance/vendor-register.md`
5. Approve based on score (5/5: adopt, 1-2: reject, 3-4: adopt with conditions)

## Vendor Categories

| Category | Examples | Required Controls |
|----------|----------|-------------------|
| Tier 1 (critical) | Hosting, DB, payment | SOC 2 Type 2, DPA, quarterly review |
| Tier 2 (important) | Email, monitoring | SOC 2 Type 1 minimum, DPA, semi-annual review |
| Tier 3 (low risk) | Marketing tools without PII | Annual review |

## Ongoing Review

- Tier 1: every 3 months
- Tier 2: every 6 months
- Tier 3: every 12 months
- Trigger reviews on: vendor incident, certification change, contract renewal

## Sub-processors

Vendors that engage their own sub-processors (sub-processors of our processors)
must:
- Disclose all sub-processors
- Notify us before adding new sub-processors
- Allow us to object to sub-processors on data protection grounds

## Termination

On vendor termination:
- Confirm data deletion or return (per DPA)
- Revoke access credentials
- Remove vendor from active register, move to archived
- Document in vendor register

## Enforcement

`/vendor-review` skill manages assessments.
`/compliance-status` flags overdue reviews.
