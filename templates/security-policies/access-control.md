> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Access Control Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Quarterly

## Purpose

To control access to systems and data based on the principle of least privilege.

## Scope

All systems containing PII, source code, or production infrastructure.

## Policy

### Provisioning
- Access granted only with documented business justification
- Manager (or founder for solo) approves all access requests
- Default deny — explicit grant required for each system
- Provisioning logged in `wiki/compliance/evidence/access-log.md`

### Least Privilege
- Users granted only the minimum access required for their role
- Administrative access limited to those who need it
- Production access separate from development access
- Read-only access used where write access not required

### Multi-Factor Authentication (MFA)
- MFA required for all production systems
- MFA required for all systems containing PII
- MFA required for all administrative accounts
- TOTP or hardware key (FIDO2) preferred over SMS

### Quarterly Access Review
- Every quarter, review all access grants
- Remove access for departed personnel within 24 hours of departure
- Remove access for role changes within 7 days
- Document review in `wiki/compliance/evidence/access-review-{quarter}.md`

### Deprovisioning
- On personnel departure: revoke all access within 24 hours
- On role change: review and adjust access within 7 days
- On contract end (for contractors): revoke same day

### Privileged Access
- Production database access requires MFA + audit logging
- Production server access requires SSH key + bastion host (where applicable)
- Privileged actions are logged

### Service Accounts
- Service accounts have scoped permissions (no admin unless required)
- Service account credentials rotated quarterly
- Service accounts documented in `wiki/operations/environments.md`

## Audit Logging

Every access grant, revocation, and privileged action is logged.
Logs retained 12 months minimum.

## Enforcement

Violations reported per incident response policy.

## Review

This policy is reviewed quarterly.
