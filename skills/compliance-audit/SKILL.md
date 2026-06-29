---
name: compliance-audit
description: |
  TRIGGER when: the user wants to audit the project against PDPA or SOC 2 controls,
  asks about compliance status, wants a gap analysis, says "are we compliant",
  or is preparing for a client security questionnaire.
  DO NOT TRIGGER when: the user wants a security audit (use /security-check),
  data inventory only (use /data-inventory), or legal docs (use /legal-docs).
argument-hint: "[PDPA|SOC2|both]"
disable-model-invocation: true
effort: high
user_locked: true
pinned: true
---

# Compliance Audit

## When to Use

When you need a gap analysis of the current project against PDPA (Singapore)
or SOC 2 Common Criteria, or both. Produces a structured report — does not
auto-remediate. The user fixes gaps in subsequent sessions.

## Procedure

## Step 1 — Determine Scope

Read `$ARGUMENTS` to determine which framework(s) to audit:
- `PDPA` — Singapore Personal Data Protection Act only
- `SOC2` — SOC 2 Common Criteria only
- `both` — audit against both (recommended)
- If empty: ask "Audit against PDPA, SOC 2, or both?"

Also detect the project stream from CLAUDE.md:
- If stream is `learning`: STOP. Say "Learning stream projects are not in
  compliance scope. /compliance-audit is for production streams only."

## Step 2 — Delegate to Compliance Officer

Delegate to the Compliance Officer subagent:

"Perform a {PDPA|SOC2|both} gap audit on this project.

For PDPA, check these obligations (Singapore PDPA Part IV-VI):
  1. Consent — is consent collected for PII processing?
  2. Purpose limitation — is purpose stated and respected?
  3. Notification — are users told what's collected and why?
  4. Access & correction — can users request their data?
  5. Accuracy — are mechanisms in place to keep data accurate?
  6. Protection — encryption, access controls, retention
  7. Retention — is there a retention policy and enforcement?
  8. Transfer limitation — are cross-border transfers compliant?
  9. Openness — is privacy policy published?
  10. Data Protection Officer — is a DPO designated?

For SOC 2, check Common Criteria (CC1-CC9):
  CC1 — Control environment (governance, accountability)
  CC2 — Communication and information
  CC3 — Risk assessment
  CC4 — Monitoring activities
  CC5 — Control activities
  CC6 — Logical and physical access
  CC7 — System operations (change management, monitoring)
  CC8 — Change management
  CC9 — Risk mitigation

For each control, classify the project as:
  PASS — control fully implemented with evidence
  PARTIAL — control implemented but missing evidence or has gaps
  FAIL — control not implemented
  N/A — control does not apply to this project

Report findings as a structured table. For each FAIL or PARTIAL, include
a remediation suggestion."

Wait for the Compliance Officer's report.

## Step 3 — Write Gap Report

Write `wiki/compliance/gaps.md` (append a new dated section if file exists):

```markdown
## Audit — {YYYY-MM-DD}

Scope: {PDPA|SOC2|both}
Auditor: Compliance Officer agent
Stream: {project stream}

### Summary

| Framework | PASS | PARTIAL | FAIL | N/A | Total |
|-----------|------|---------|------|-----|-------|
| PDPA      | {n}  | {n}     | {n}  | {n} | {n}   |
| SOC 2     | {n}  | {n}     | {n}  | {n} | {n}   |

### PDPA Findings

| Obligation | Status | Evidence / Gap | Remediation |
|-----------|--------|----------------|-------------|
| Consent | ... | ... | ... |
| ... | ... | ... | ... |

### SOC 2 Findings

| Criterion | Status | Evidence / Gap | Remediation |
|-----------|--------|----------------|-------------|
| CC1 | ... | ... | ... |
| ... | ... | ... | ... |

### Top 5 Gaps to Address

1. {Gap} — {why critical} — {effort: S/M/L}
2. ...

### Next Audit Recommended

{Date — typically 90 days for active projects, 30 days if many FAILs}
```

## Step 4 — Update Evidence Index

For each PASS finding, append to `wiki/compliance/evidence-index.md`:

```markdown
| Control | Evidence Location | Last Verified | Verifier |
|---------|------------------|---------------|----------|
| {control id} | {file path} | {YYYY-MM-DD} | Compliance Officer |
```

## Step 5 — Report Summary

Print to user:

```
Compliance Audit Complete

Scope:     {PDPA|SOC2|both}
PASS:      {N} controls
PARTIAL:   {N} controls
FAIL:      {N} controls
N/A:       {N} controls

Top 5 gaps to address:
  1. {gap}
  2. {gap}
  ...

Full report: wiki/compliance/gaps.md
Evidence index: wiki/compliance/evidence-index.md

Next steps:
  - Review the FAIL gaps and decide which to address first
  - Run /data-inventory if PII flow mapping was flagged as a gap
  - Run /legal-docs if missing privacy policy / DPA was flagged
  - Run /audit-logging-setup if audit logging was flagged
```

## Pitfalls

- Running this without a Compliance Officer agent installed — fails silently.
  Confirm agent exists at .claude/agents/compliance-officer.md first.
- Running on `learning` stream — meaningless and noisy. Block early.
- Overwriting `wiki/compliance/gaps.md` instead of appending — historical
  audits matter for SOC 2 evidence.
- Auditing without specifying scope — defaults are dangerous; ask the user.

## Verification

- `wiki/compliance/gaps.md` was written with today's date
- All controls in scope have a status (PASS/PARTIAL/FAIL/N/A)
- Top 5 gaps are clearly identified
- Evidence index updated with PASS findings
- User has a clear next action
