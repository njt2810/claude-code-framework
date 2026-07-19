---
name: triage
description: |
  TRIGGER when: the user has a customer support ticket, bug report from a user,
  feature request from a client, or wants to process a backlog of incoming feedback.
  DO NOT TRIGGER when: the user is fixing a bug they already know about (use /bug-fix),
  or building a new feature (use /new-feature).
argument-hint: "[ticket-source-or-description]"
disable-model-invocation: true
user_locked: true
pinned: true
---

# Customer Support Triage

## When to Use

When converting an incoming customer ticket / bug report / feature request
into a structured backlog item with priority, owner, and next action.
Bridges the gap between customer support and engineering.

## Procedure

## Step 1 — Capture the Ticket

Ask the user (or read from input):
- Source: email / Intercom / Slack / GitHub Issue / personal note?
- Customer: who reported it? (link to account if SaaS)
- Plan tier: free / paid / enterprise (affects SLA)
- What they said: paste verbatim if possible
- When: when did they report?

## Step 2 — Classify

Decide one of:
- **Bug** — something is broken
- **Feature request** — they want something new
- **Question** — they need help, not a code change
- **Complaint** — feedback without a specific action
- **Billing** — payment / subscription issue
- **Security** — possible security report (STOP, treat with care)

## Step 3 — Severity (for Bugs)

| Severity | Criteria | SLA |
|----------|----------|-----|
| **P0** | Production down, data loss, or security breach | 1 hour ack, fix within 4 hours |
| **P1** | Core feature broken for paid customers | 4 hour ack, fix within 24 hours |
| **P2** | Annoying but workaround exists | 1 business day ack, fix within 1 week |
| **P3** | Cosmetic, edge case | 3 business day ack, fix when convenient |

For P0 — STOP, run `/incident` instead.

## Step 4 — Reproduce (Bugs)

Try to reproduce the bug locally:
- What URL / page?
- What inputs?
- What expected vs actual?

If can't reproduce, draft a clarifying response to the customer:
- "Thanks for reporting. To investigate, I need: {question 1}, {question 2}"
- Send via the support channel

If reproducible, follow `/bug-fix` workflow.

## Step 5 — Score Feature Requests

For feature requests, score:
- **Customer impact**: 1 customer / multiple customers / "they all keep asking"
- **Revenue impact**: blocking a sale / would help retention / nice-to-have
- **Effort**: small / medium / large
- **Strategic fit**: core / adjacent / out-of-scope

Score = (impact + revenue) - effort. Prioritize > 0 scores.

For high-score: add to `wiki/backlog.md` (create if missing).
For out-of-scope: respond politely declining with reasoning.

## Step 6 — Respond to Customer

For all categories, send a response within SLA:
- Acknowledge receipt
- State what you understand the issue to be (confirm understanding)
- Set expectation: "I'll look into this and reply by {date/time}"
- For bugs: provide workaround if any

Use template from `wiki/operations/support-templates.md` (create if missing):

```markdown
# Support Response Templates

## Bug Acknowledgment
Hi {name},

Thanks for reporting this. I've reproduced the issue and {assessment}.

Workaround in the meantime: {if any}

I'll have a fix deployed by {date}. I'll email you when it's live.

Best,
{Name}

## Feature Request — Will Build
...

## Feature Request — Declining (politely)
Hi {name},

Thanks for the suggestion. We've thought about this and decided it's
not the right fit for our product because {reason}.

If your need is {underlying need}, here are alternatives: {alternatives}

Best,
{Name}

## Question — Answer
...

## Security Report
Hi {name},

Thank you for reporting this responsibly. I'm investigating and will respond
within 24 hours. Please do not disclose publicly until we've had a chance
to address it.

If material, you'll be credited (with permission) in our security acknowledgments.

Best,
{Name}
```

## Step 7 — Log to Backlog

Append to `wiki/backlog.md`:

```markdown
| Date | Source | Customer | Type | Severity/Score | Summary | Status | Next Action |
|------|--------|----------|------|----------------|---------|--------|-------------|
| {date} | {source} | {customer} | bug | P1 | {summary} | acknowledged | reproduce, fix this week |
```

## Step 8 — Update CRM / Customer Record

If customer-specific:
- Note in their record that they reported this
- Track time-to-resolution per customer
- If a paying customer has multiple open issues → escalate visibility

## Step 9 — Report

```
Triage Complete

  Ticket source:   {source}
  Customer:        {who} ({plan})
  Type:            {bug / feature / question / complaint / billing / security}
  Severity/Score:  {value}
  SLA:             {ack-by} / {resolve-by}

  Response sent:   {yes/draft}
  Logged:          wiki/backlog.md
  Next action:     {concrete next step}

  (For bug)
  Reproducible:    {yes/no}
  Next workflow:   {/bug-fix or /incident}
```

## Pitfalls

- Acknowledging but never following up — worst customer experience
- Promising specific dates without checking calendar — broken promises
- Treating all feature requests as "good ideas" — backlog becomes meaningless
- Ignoring complaints because they're not actionable — patterns hide here
- Handling security reports publicly — disclosure timing matters
- Letting paying customer tickets go to back of queue — churn driver
- Triaging without reproducing — fixes wrong thing

## Verification

- Ticket logged in `wiki/backlog.md`
- Customer received acknowledgment within SLA
- Severity/score assigned
- Concrete next action stated
- If bug: reproduction attempted (success or clarifying question)
- If feature: scored and prioritized
- If security: handled per security disclosure process (don't disclose publicly until fixed)
