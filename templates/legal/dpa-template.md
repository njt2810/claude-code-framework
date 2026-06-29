> ⚠️ **DRAFT — LAWYER REVIEW REQUIRED**
>
> This Data Processing Agreement is a starting template. Every term must be
> reviewed by a qualified lawyer (ideally one with PDPA / commercial contracts
> background) before signing with any client.

# Data Processing Agreement

This Data Processing Agreement ("DPA") forms part of the agreement between:

**Controller:** {{CLIENT_LEGAL_ENTITY}} ("Client")
Address: {{CLIENT_ADDRESS}}

**Processor:** {{LEGAL_ENTITY}} ("Service Provider")
Address: {{ADDRESS}}

Effective Date: {{EFFECTIVE_DATE}}

## 1. Definitions

- "**Personal Data**" has the meaning under the Singapore Personal Data
  Protection Act 2012 (PDPA).
- "**Processing**" means any operation performed on Personal Data.
- "**Sub-processor**" means any third party engaged by Service Provider to
  process Personal Data on Client's behalf.
- "**Notifiable Data Breach**" has the meaning under PDPA Part VIA.

## 2. Scope and Purpose of Processing

Service Provider processes Personal Data on behalf of Client solely for the
purpose of providing {{PRODUCT_NAME}} per the underlying service agreement.

**Categories of data subjects:** {{DATA_SUBJECTS}} (e.g., Client's end users)
**Categories of Personal Data:** {{PII_CATEGORIES}}
**Duration of processing:** for the term of the underlying service agreement
plus the retention period defined in Section 7.

## 3. Service Provider's Obligations

Service Provider will:

a. Process Personal Data only on documented instructions from Client
b. Ensure persons authorized to process Personal Data are bound by confidentiality
c. Implement appropriate technical and organizational measures (see Section 5)
d. Assist Client in responding to data subject requests (access, correction, deletion)
e. Notify Client of any Notifiable Data Breach without undue delay and in any
   event within 72 hours of becoming aware
f. On termination, delete or return Personal Data per Client's instructions
g. Make available information necessary to demonstrate compliance with this DPA

## 4. Sub-processors

Service Provider may engage sub-processors listed in Schedule A.

Service Provider will:
- Notify Client at least 30 days before adding or replacing a sub-processor
- Allow Client to object to a new sub-processor on reasonable data protection grounds
- Impose data protection obligations on sub-processors no less protective than this DPA
- Remain liable for sub-processor performance

## 5. Security Measures

Service Provider implements:

- Encryption of Personal Data in transit (TLS 1.2 or higher)
- Encryption of Personal Data at rest
- Access controls based on least privilege
- Audit logging of access to Personal Data
- Regular vulnerability assessments
- Incident response procedures
- Personnel security training

Detailed security controls are in Schedule B.

## 6. Cross-Border Data Transfers

Personal Data may be transferred to and processed in {{COUNTRIES}}.

Service Provider ensures cross-border transfers comply with PDPA s.26 through:
- Contractual safeguards with recipients
- Recipient certifications (e.g., SOC 2, ISO 27001)
- Standard contractual clauses where applicable

## 7. Data Retention and Deletion

Service Provider retains Personal Data for the duration of the service plus:
- {{RETENTION_PERIOD_DAYS}} days legal hold after account deletion
- Audit logs: 12 months minimum (regulatory)
- Backups: per backup rotation policy (typically 30 days)

On Client's request after termination, Service Provider will delete or return
Personal Data within 30 days, subject to legal hold obligations.

## 8. Data Subject Rights

Service Provider will assist Client in responding to data subject requests by:
- Providing data export functionality
- Implementing deletion on request
- Correcting inaccurate data on request

Service Provider will respond to Client's requests within 5 business days.

## 9. Audits

Once per year, Client may audit Service Provider's compliance with this DPA,
either by:
- Reviewing Service Provider's SOC 2 / ISO 27001 / other independent audit reports
- Conducting an on-site audit at Client's expense, with 30 days' notice

## 10. Liability and Indemnification

Each party's liability under this DPA is governed by the underlying service
agreement, except where limitations are prohibited by PDPA.

## 11. Term and Termination

This DPA is effective for the duration of the underlying service agreement.
Sections 3(f), 7, 8 survive termination.

## 12. Governing Law

This DPA is governed by the laws of Singapore.

---

## Schedule A — Sub-processors

| Sub-processor | Purpose | Location | DPA in Place |
|---------------|---------|----------|--------------|
| {{SUBPROCESSOR_1}} | {{PURPOSE}} | {{COUNTRY}} | Yes |
| {{SUBPROCESSOR_2}} | {{PURPOSE}} | {{COUNTRY}} | Yes |

## Schedule B — Technical and Organizational Measures

### Access Control
- Multi-factor authentication required for all administrative access
- Role-based access control (RBAC) for application access
- Quarterly access reviews

### Encryption
- TLS 1.2+ for all data in transit
- AES-256 for data at rest
- Key management via {{KEY_MANAGEMENT_SERVICE}}

### Logging and Monitoring
- All access to Personal Data is audit-logged
- Logs retained for 12 months
- Alerting on anomalous access patterns

### Incident Response
- Documented incident response runbook
- 72-hour breach notification SLA per PDPA

### Personnel
- Background checks for personnel with access to Personal Data
- Annual security awareness training
- Confidentiality agreements

### Vendor Management
- Sub-processors reviewed annually
- DPAs with all sub-processors handling Personal Data

---

**Signed for Service Provider:** _______________________ Date: __________
**Signed for Client:** _______________________ Date: __________

---

**Last reviewed by counsel:** {{LAWYER_REVIEW_DATE}}
**Next review due:** {{NEXT_REVIEW_DATE}}
