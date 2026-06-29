> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Data Classification Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Annual

## Purpose

Classify data by sensitivity to apply appropriate controls.

## Classifications

### Public
- Marketing content
- Public blog posts
- Pricing pages
- Open-source code

**Controls:** None beyond integrity (don't get defaced).

### Internal
- Internal documentation, runbooks, architecture diagrams
- Aggregated usage statistics (no PII)
- Non-public roadmap

**Controls:** Access limited to employees/contractors with NDAs.

### Confidential
- Customer data (non-PII): account configurations, plan info
- Source code (proprietary)
- Customer support conversations
- Business financial data

**Controls:** Encrypted in transit and at rest. Access via authenticated systems only. Logged access.

### Restricted (PII)
- Personal Data per PDPA: email, name, IP, etc.
- Authentication credentials (hashed)
- Audit logs
- Payment information (cards handled by Stripe, not us)

**Controls:** Encrypted at rest with key management. Strict access control. MFA required to view. Full audit log of access. Retention policy enforced.

### Highly Restricted (Sensitive PII)
- Government IDs (NRIC, passport)
- Health data
- Financial account details
- Children's data (under 13)

**Controls:** Same as Restricted PLUS:
- Encryption at column level (not just at-rest)
- Access requires explicit business justification logged per-access
- Quarterly access review

## Handling Requirements

- Classify all data stores in `wiki/compliance/data-inventory.md`
- Apply controls per classification
- Never move data to a less-protected store
- When in doubt, classify higher

## Enforcement

`/data-inventory` maintains the classification.
`/compliance-audit` verifies controls match classification.
