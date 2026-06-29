---
name: vendor-review
description: |
  TRIGGER when: the user wants to add a vendor to the project, evaluate a third-party
  service's security posture, fill out a vendor security questionnaire, or maintain
  the vendor register. Also triggered when a client sends YOU a vendor questionnaire.
  DO NOT TRIGGER when: the user wants a code-level dependency audit (use /security-check).
argument-hint: "[vendor-name] (optional)"
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Vendor Security Review

## When to Use

When evaluating a third-party service that will process project data, OR
when responding to a client's vendor questionnaire about YOUR project.
Maintains `wiki/compliance/vendor-register.md`.

## Procedure

## Step 1 — Mode

Two modes:
- **Inbound** — assessing a vendor you're considering using
- **Outbound** — responding to a client's questionnaire about YOUR project

Ask: "Are you assessing a vendor (inbound) or responding to a client questionnaire (outbound)?"

## Step 2A — Inbound Vendor Assessment

If inbound, collect:

**Vendor identity:**
- Vendor name
- URL
- Service description (what they do)
- Pricing tier and approximate monthly cost

**Data exposure:**
- What data will they receive? (Pull from `wiki/compliance/data-inventory.md`)
- Will they see PII? (yes/no — if yes, requires DPA)
- Will they see sensitive PII? (yes/no — extra scrutiny)
- Where do they store data? (region/country — affects PDPA cross-border rules)

**Compliance posture:**
- SOC 2 Type 1 or Type 2? (Type 2 preferred)
- ISO 27001?
- GDPR/PDPA-compliant data processing terms?
- Penetration test cadence?
- Breach notification SLA?
- Sub-processors disclosed?

**Contract terms:**
- DPA available? (link)
- Data deletion on termination?
- Data export format?
- Audit rights?
- Liability cap?

**Technical posture:**
- Encryption in transit (TLS 1.2+ required)?
- Encryption at rest?
- Authentication options (SSO/MFA)?
- API rate limits?
- Audit logs from vendor side?

Score the vendor (1-5 scale per category) and produce a recommendation:
- **5 — Adopt**: SOC 2 Type 2, DPA available, all controls in place
- **4 — Adopt with conditions**: Minor gaps, document mitigations
- **3 — Adopt with caution**: Real gaps, set review reminder for 6 months
- **2 — Reject or remediate first**: Significant gaps
- **1 — Reject**: Major security or compliance issues

## Step 2B — Outbound Client Questionnaire

If outbound, the client is asking YOU about your project's security.

Pull answers from these sources:
- `wiki/compliance/policies/` — security policies
- `wiki/compliance/data-inventory.md` — what PII you process
- `wiki/compliance/vendor-register.md` — your sub-processors
- `wiki/compliance/audit-logging.md` — your audit logging
- `wiki/operations/incident-response.md` — your IR plan
- `wiki/operations/disaster-recovery.md` — your DR plan
- `wiki/compliance/evidence-index.md` — SOC 2 evidence

If the client questionnaire is provided (paste it or path to file), parse it
and answer each question with citations to the docs above.

If a question asks about a control you haven't implemented:
- Don't lie. Answer "Not yet — implementing by {date}"
- Add the gap to `wiki/compliance/gaps.md`
- Suggest implementing it via `/compliance-audit`

## Step 3 — Update Vendor Register

For inbound, append a row to `wiki/compliance/vendor-register.md`:

```markdown
| Vendor | Data Processed | DPA Link | SOC 2 | Region | Score | Review Date | Notes |
|--------|---------------|----------|-------|--------|-------|-------------|-------|
| {name} | email, name | {url} | Type 2 (2026) | US-EAST | 4/5 | 2026-06-29 | DPA signed |
```

## Step 4 — Set Review Reminder

Inbound vendors should be reviewed every:
- 12 months for low-risk vendors (no PII access)
- 6 months for medium-risk (PII access, score 3-4)
- 3 months for high-risk (sensitive PII, score 2)

Add to `wiki/operations/calendar.md` (create if missing):

```markdown
| Date | Action | Notes |
|------|--------|-------|
| {YYYY-MM-DD} | Review {vendor} | Score was {N}/5 at last review |
```

## Step 5 — Report

For inbound:

```
Vendor Assessment: {vendor name}

  Service:         {description}
  Data Exposure:   {PII? yes/no, fields}
  Region:          {country}
  SOC 2:           {status}
  DPA:             {available/missing}
  Score:           {N}/5
  Recommendation:  {Adopt / Adopt with conditions / Caution / Reject}

  Gaps:
    {bullet list}

  Next steps:
    {bullet list}

  Updated: wiki/compliance/vendor-register.md
  Review reminder: {date} in wiki/operations/calendar.md
```

For outbound:

```
Client Questionnaire Response

  Questions answered: {N}
  Gaps revealed:      {N} (added to wiki/compliance/gaps.md)
  Documents cited:    {list}

  Draft response: wiki/compliance/questionnaire-{client}-{date}.md

  ⚠ Review before sending — verify accuracy of every answer
```

## Pitfalls

- Adopting a vendor with no DPA when they'll see PII — PDPA violation
- Not tracking sub-processors (vendors-of-vendors) — they need disclosure too
- Forgetting cross-border transfer implications for PDPA (Singapore data → US vendor)
- Letting the register go stale — vendors lose certifications, add new sub-processors
- Lying on a client questionnaire — you'll be discovered during audit
- Score-shopping to justify adoption — score honestly, then decide

## Verification

- Vendor added to `wiki/compliance/vendor-register.md` with all columns filled
- DPA link captured if available, "MISSING" if not
- Review reminder added to `wiki/operations/calendar.md`
- For outbound: draft response written, gaps logged in `wiki/compliance/gaps.md`
- User has clear next action (sign DPA, mitigate gap, etc.)
