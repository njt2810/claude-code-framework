---
name: onboard-client
description: |
  TRIGGER when: the user is onboarding a new client to the project, provisioning
  a new tenant, sending welcome/kickoff comms, or completing the post-sale setup.
  DO NOT TRIGGER when: the user is signing up a regular self-serve user (different scope),
  or doing pre-sale work (use /triage or general session).
argument-hint: "[client-name]"
disable-model-invocation: true
user_locked: true
pinned: true
---

# Client Onboarding

## When to Use

When a paying client is being onboarded onto the platform. Walks through
the structured checklist so nothing falls through the cracks between sales
sign and client first-value.

This is a **generic** skill — it walks through the steps that apply to most
SaaS client onboarding. Project-specific details (which tenant DB, which
SSO config) are filled in per invocation.

## Lead Engineer Guidance — Why This Matters

Client onboarding is where most early-stage SaaS quietly loses customers.
The contract is signed, but the client hits friction in the first 14 days
and never gets to "value." Then they churn.

A structured onboarding skill:
- Catches the legal/compliance items BEFORE they become blockers
- Surfaces tech tasks in dependency order (env before SSO before data import)
- Captures notes and decisions for the client's record
- Makes the second onboarding 10x faster than the first

**Run this skill:**
- When a new client signs (the day of)
- Whenever you add a new "tenant" to a multi-tenant system
- Before the kickoff call (so you have answers ready)

**Each invocation produces:**
- `wiki/clients/{client-slug}/` with a structured record
- Updates to `wiki/compliance/vendor-register.md` if client onboarding triggers new sub-processors
- Calendar entries for client check-ins

## Procedure

## Step 1 — Capture Client Identity

Ask (if not provided):
- Client legal name
- Client industry / use case
- Plan / pricing tier
- Contract effective date and term
- Client primary contact (name, email, role)
- Their end-user jurisdiction (affects compliance scope)
- Has DPA been signed?
- Other signed agreements: MSA, SLA, NDA?

Generate slug: kebab-case of client name.

## Step 2 — Create Client Record

Also create `wiki/clients/{slug}/time-log.md` (empty placeholder, used by /timer):

```markdown
# Time Log — {client legal name}

This is an append-only log of billable client work for this client.
Entries are written by `/timer stop`. Do not edit by hand unless correcting
an error — keep the audit trail intact.

(no entries yet)
```

Create `wiki/clients/{slug}/profile.md`:

```markdown
---
client: {legal name}
slug: {slug}
contract_start: {date}
contract_end: {date}
plan: {tier}
primary_contact: {name, email}
status: onboarding | active | paused | churned
---

# Client: {legal name}

## Profile
- Industry: {industry}
- Use case: {description}
- End-user jurisdiction: {country}
- Plan: {tier}
- MRR / ARR: {amount}

## Contacts

| Name | Role | Email | Phone |
|------|------|-------|-------|
| ... | ... | ... | ... |

## Agreements

| Doc | Status | Date Signed | Counter-party Signer |
|-----|--------|-------------|---------------------|
| MSA | signed | {date} | {name} |
| DPA | signed | {date} | {name} |
| SLA | pending | | |

## Onboarding Checklist
(populated by Step 3)

## Notes & Decisions
(running log)

## Communications Log
(running log of major comms)
```

## Step 3 — Walk the Onboarding Checklist

Present a project-aware checklist (the framework can adapt based on what
skills are installed). Common items:

### Legal & Compliance
- [ ] DPA signed (if not, route to /legal-docs for draft)
- [ ] MSA / order form signed
- [ ] If client needs SOC 2 report, share status / report under NDA
- [ ] Update `wiki/compliance/vendor-register.md` if client adds any sub-processors
- [ ] Schedule annual data review (calendar entry)

### Provisioning
- [ ] Create production tenant (DB row, account, etc.)
- [ ] Generate credentials / API keys
- [ ] Provision storage / quota per plan
- [ ] Add to billing system (if applicable)
- [ ] Configure feature flags for plan tier (use /feature-flag)

### Authentication / SSO (if applicable)
- [ ] Configure SSO with client's IdP (Okta, Azure AD, Google)
- [ ] Set up SAML/OIDC metadata exchange
- [ ] Test SSO login end-to-end
- [ ] Document IdP details in profile.md

### Data Import / Migration (if applicable)
- [ ] Receive client data dump (in agreed format)
- [ ] Validate data: schema, completeness, encoding
- [ ] Import to client tenant
- [ ] Spot-check 5+ records
- [ ] Confirm import with client

### Custom Configuration
- [ ] Plan-specific config (rate limits, integrations enabled)
- [ ] Brand customization (logo, colors, custom domain)
- [ ] Custom email sender domain (if applicable, see /email-setup DNS)

### Comms
- [ ] Welcome email sent with login credentials and getting-started guide
- [ ] Kickoff call scheduled (within 7 days of contract start)
- [ ] Shared support channel created (Slack Connect / shared email alias)
- [ ] Client added to "Customers" mailing list (with their consent)

### Knowledge Transfer
- [ ] Send links to: docs, status page, support process
- [ ] Show video walkthrough of core flows
- [ ] Provide test/sandbox account if applicable
- [ ] Set up first 30-day check-in calendar invite

### Internal
- [ ] Log onboarding date in client profile
- [ ] Create #client-{slug} channel (or equivalent)
- [ ] Add to active client roster
- [ ] Set up monitoring alert for this client's usage (if applicable)

For each item, mark in `wiki/clients/{slug}/profile.md` as done.

## Step 4 — Schedule Follow-ups

Add to `wiki/operations/calendar.md`:

```markdown
| Date | Action | Notes |
|------|--------|-------|
| {start + 7 days} | Kickoff call: {client} | First touchpoint after onboarding |
| {start + 30 days} | 30-day check-in: {client} | Health check, expand discussion |
| {start + 90 days} | Quarterly review: {client} | Renewal conversation |
| {contract_end - 60 days} | Renewal conversation: {client} | Begin renewal process |
```

## Step 5 — Update Dashboard / Tracking

Update `wiki/clients/_index.md` (create if missing):

```markdown
# Client Roster

## Active

| Client | Plan | Started | Primary Contact | MRR | Status |
|--------|------|---------|-----------------|-----|--------|
| {name} | {tier} | {date} | {contact} | {amount} | active |
| ... | ... | ... | ... | ... | ... |

## Onboarding

| Client | Plan | Signed | Days in Onboarding | Blocker |
|--------|------|--------|--------------------|---------|
| ... | ... | ... | ... | ... |

## Churned (archive)

| Client | Plan | Started | Ended | Reason |
|--------|------|---------|-------|--------|
| ... | ... | ... | ... | ... |
```

## Step 6 — Report

```
Client Onboarding — {client name}

  Profile created: wiki/clients/{slug}/profile.md
  Time log:        wiki/clients/{slug}/time-log.md (ready for /timer)
  Roster updated:  wiki/clients/_index.md
  Calendar items:  {N} scheduled

  Checklist progress: {done}/{total}

  Pending blockers:
    - {item}: {what's blocking, who needs to act}

Recommended next:
  1. Resolve blockers above
  2. Run kickoff call within 7 days
  3. Add client to relevant feature flags if multi-tenant
  4. If client added new sub-processor relationships, run /vendor-review
  5. For SOC 2 evidence: this onboarding's checklist itself is evidence (CC1.5, CC9.1)
```

## Pitfalls

- Skipping the kickoff call — clients silently disengage
- Forgetting to provision before kickoff — embarrassing call
- No SSO config when client needs it — onboarding stalls 2 weeks
- DPA not signed by day 1 — legal exposure if client data flows
- No support channel set up — client emails go to noreply, you miss them
- No 30/60/90 calendar items — first time you remember the client is at renewal
- Checklist that's never project-specific — turns generic, gets ignored

## Verification

- `wiki/clients/{slug}/profile.md` written with frontmatter
- Onboarding checklist captured (even if not all done)
- Calendar items scheduled
- Roster updated
- User knows the top blocker to unblock
