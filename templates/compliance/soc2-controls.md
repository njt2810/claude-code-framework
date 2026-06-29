# SOC 2 Control Matrix

This document maps SOC 2 Common Criteria (CC1–CC9) to this project's
implementation and evidence. Update as controls are implemented.

| Criterion | Description | Implementation | Evidence Location | Last Verified | Owner |
|-----------|-------------|----------------|-------------------|---------------|-------|
| **CC1.1** | Demonstrates commitment to integrity and ethical values | Acceptable Use Policy signed by all personnel | wiki/compliance/policies/acceptable-use.md + acknowledgment records | | |
| **CC1.2** | Exercises oversight responsibility | Founder reviews quarterly compliance status | wiki/compliance/evidence/quarterly-reviews/ | | |
| **CC1.3** | Establishes structure, authority, responsibilities | TEAM.md defines roles | TEAM.md | | |
| **CC1.4** | Demonstrates commitment to competence | Annual security training | wiki/compliance/evidence/training-log.md | | |
| **CC1.5** | Enforces accountability | Acknowledgment of policies, incident learnings | wiki/compliance/evidence/ | | |
| **CC2.1** | Obtains and uses relevant quality info | Observability stack (logs, metrics, errors) | wiki/operations/observability.md | | |
| **CC2.2** | Internally communicates info needed for control | wiki/ is single source of truth, accessible to all team | wiki/ | | |
| **CC2.3** | Communicates with external parties | Status page, breach notification process | wiki/operations/incident-response.md | | |
| **CC3.1** | Specifies objectives | Project objectives in CLAUDE.md / constitution.md | CLAUDE.md / constitution.md | | |
| **CC3.2** | Identifies and assesses risk | Risk register maintained | wiki/compliance/risk-register.md | | |
| **CC3.3** | Considers fraud potential | Audit logging, anomaly detection | wiki/compliance/audit-logging.md | | |
| **CC3.4** | Identifies/assesses change | Change management policy + PR workflow | wiki/operations/change-management.md | | |
| **CC4.1** | Selects and develops control activities | Documented in security policies | wiki/compliance/policies/ | | |
| **CC4.2** | Performs ongoing/separate evaluations | /compliance-audit run quarterly | wiki/compliance/gaps.md (dated entries) | | |
| **CC5.1** | Selects and develops general controls | Security policies pack adopted | wiki/compliance/policies/ | | |
| **CC5.2** | Deploys via policies and procedures | Policies acknowledged, enforced via tooling | wiki/compliance/evidence/policy-acknowledgments.md | | |
| **CC5.3** | Selects and develops technology controls | Encryption, access control, audit logging | wiki/operations/architecture.md | | |
| **CC6.1** | Implements logical access controls | Auth provider, MFA, RBAC | wiki/conventions.md (auth section) | | |
| **CC6.2** | Restricts physical access | N/A for cloud-native (vendor handles) | Vendor SOC 2 reports | | |
| **CC6.3** | Manages access (provision/deprovision) | Access control policy | wiki/compliance/policies/access-control.md + quarterly review | | |
| **CC6.6** | Implements logical access security measures | TLS, encryption, MFA, audit logs | wiki/compliance/policies/encryption-policy.md | | |
| **CC6.7** | Restricts unauthorized access | Auth + RBAC + audit | wiki/conventions.md | | |
| **CC6.8** | Implements controls for boundary protection | WAF, rate limiting, firewall | wiki/operations/architecture.md | | |
| **CC7.1** | Detects and responds to incidents | Observability + /incident workflow | wiki/operations/observability.md + incidents/ | | |
| **CC7.2** | Monitors components for anomalies | Alerts + error tracking | wiki/operations/alerting.md | | |
| **CC7.3** | Evaluates security events to identify incidents | Triage in /incident | wiki/operations/incidents/ | | |
| **CC7.4** | Responds to and communicates incidents | /incident workflow + breach notification | wiki/operations/incident-response.md | | |
| **CC7.5** | Implements recovery activities | DR plan + restore drills | wiki/operations/disaster-recovery.md | | |
| **CC8.1** | Authorizes/designs changes | PR + branch protection | wiki/operations/change-management.md | | |
| **CC8.2** | Documents and tracks changes | Git history + deploy log | wiki/operations/deploy-log.md | | |
| **CC8.3** | Tests changes | CI test suite + manual smoke tests | CI run logs | | |
| **CC8.4** | Authorizes implementation | PR review approval | GitHub PR history | | |
| **CC9.1** | Identifies risks from business relationships | Vendor risk assessment | wiki/compliance/vendor-register.md | | |
| **CC9.2** | Assesses and manages risks | Risk register reviewed quarterly | wiki/compliance/risk-register.md | | |

## Coverage Summary

- Total controls: 32
- Implemented (PASS): _ / 32
- Partial: _ / 32
- Not implemented: _ / 32

Run `/compliance-audit SOC2` to update status.
