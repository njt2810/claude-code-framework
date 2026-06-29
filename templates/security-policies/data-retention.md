> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Data Retention Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Annual

## Purpose

Define how long data is retained, and when and how it is deleted.

## Principles

- Retain only what is necessary
- Delete when no longer needed
- Document retention in `wiki/compliance/data-inventory.md`
- Honor user deletion requests within 30 days

## Retention Schedule

| Data Type | Retention Period | Reason | Deletion Mechanism |
|-----------|------------------|--------|-------------------|
| Active user accounts | Until account deletion | Service operation | User-initiated |
| Deleted user data | 30 days after deletion request | Legal hold | Scheduled job |
| Authentication logs | 12 months | SOC 2 evidence + security investigation | S3 lifecycle |
| Audit logs | 12 months hot + 12 months cold | SOC 2 evidence + regulatory | S3 Glacier |
| Application logs | 90 days | Debugging | Log retention policy |
| Backups | 30 days | DR | Rotation policy |
| Email logs | 30 days | Deliverability investigation | Provider auto-delete |
| Payment records | 7 years | Tax/regulatory | Manual review |
| Marketing consent records | Until withdrawn + 3 years | CAN-SPAM / PDPA evidence | Quarterly cleanup |

## User-Initiated Deletion

When a user requests deletion (per PDPA s.16):
1. Acknowledge within 5 business days
2. Mark account for deletion
3. After 30-day legal hold, permanent delete:
   - User record
   - Personal data in all stores
   - Email logs (purge user's email)
   - Audit logs (anonymize user_id to "deleted_user")
   - Backups: retain encrypted, rotate out within standard backup cycle
4. Confirm completion to user

Exceptions (kept beyond user request):
- Financial records (7 years, regulatory)
- Anonymized data for analytics (no longer PII)
- Audit log entries (anonymized)

## Enforcement

`/data-inventory` documents retention per field.
`/compliance-audit` flags fields without retention policy.
Scheduled cleanup jobs document execution in `wiki/compliance/evidence/`.
