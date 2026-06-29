# Risk Register

A living document of identified risks, their assessment, and mitigation status.

Updated continuously by the Compliance Officer and reviewed quarterly.

## Risk Categories

- **Security** — confidentiality, integrity, availability
- **Compliance** — PDPA, SOC 2, contractual obligations
- **Operational** — service availability, dependencies
- **Financial** — payment processing, cost overruns
- **Reputational** — customer trust, public perception
- **Vendor** — third-party service failures

## Scoring

**Likelihood:** 1 (rare) — 5 (almost certain)
**Impact:** 1 (negligible) — 5 (catastrophic)
**Risk score:** likelihood × impact

| Score | Treatment |
|-------|-----------|
| 1-4 | Accept (document) |
| 5-9 | Mitigate (plan) |
| 10-14 | Mitigate urgently |
| 15-25 | Mitigate immediately or transfer |

## Active Risks

| ID | Category | Risk | Likelihood | Impact | Score | Mitigation | Status | Owner | Review Date |
|----|----------|------|------------|--------|-------|------------|--------|-------|-------------|
| R-001 | Security | Hardcoded secrets in code history | | | | Run /security-check, rotate any found | open | {{DPO}} | |
| R-002 | Compliance | No DPA signed with sub-processors | | | | Run /vendor-review for each | open | {{DPO}} | |
| R-003 | Operational | No backup restoration test performed | | | | Schedule via /dr-plan | open | {{DPO}} | |
| R-004 | Vendor | Single-vendor dependency for hosting | | | | Document switching plan | open | {{DPO}} | |
| R-005 | Compliance | No documented retention policy | | | | Define in data-retention.md | open | {{DPO}} | |

## Retired Risks

(Risks that were mitigated and closed)

| ID | Risk | Mitigation Applied | Retired Date |
|----|------|--------------------|--------------|

## Review Schedule

- Quarterly: full review of all active risks
- Triggered by: new incident, vendor change, regulatory update, major feature
