---
name: guard
description: |
  TRIGGER when: the user is about to touch CRITICAL systems (production DB,
  auth provider config, payment processor settings, signing keys, IAM roles),
  or says "guard mode", "this is critical", "highest caution".
  DO NOT TRIGGER when: medium-risk work (use /careful instead) or routine work.
disable-model-invocation: true
effort: low
user_locked: true
pinned: true
---

# Guard Mode

## When to Use

The most cautious mode. Reserved for changes that, if wrong, can:
- Cause data loss
- Lock out users
- Expose secrets
- Trigger compliance incidents
- Cost real money (e.g., misconfigured Stripe webhook)

Examples:
- Rotating production signing keys
- Changing IAM roles in cloud console
- Modifying production DB constraints
- Editing auth provider trust relationships
- Changing payment processor webhook endpoints

## Lead Engineer Guidance — Why This Matters

Guard mode is `/careful` plus a human-in-the-loop confirmation discipline.
The Lead Engineer will NOT proceed without you actively saying "yes, do X."
No defaults, no inferences.

If you ever wonder "should I be in guard mode?" — yes, you should be.

## Procedure

## Step 1 — Capture Intent

Ask (and require answers):
- WHAT change are you making? (specific, not vague)
- WHY now? (justification)
- WHAT could go wrong? (you list the failure modes)
- WHO else has approved? (for team: name an approver; for solo: write "self-approved with reasoning")
- WHAT's the rollback? (how do you reverse this)

If any answer is missing, refuse to enter guard mode.

## Step 2 — Set Mode

Write to `.claude/state/mode.json`:

```json
{
  "mode": "guard",
  "what": "{specific change}",
  "why": "{justification}",
  "failure_modes": ["..."],
  "approver": "{name or 'self-approved'}",
  "rollback_plan": "{how to reverse}",
  "entered_at": "{ISO}",
  "entered_by": "{user}"
}
```

## Step 3 — Apply Guard Mode Rules

Everything in /careful, PLUS:

1. **No actions without explicit "yes" per step.** The Lead Engineer
   describes what it's about to do and stops.

2. **Snapshot before action:**
   - Database: take a snapshot or confirm one exists from < 1 hour ago
   - Config: capture current state (export, screenshot)
   - Cloud resources: terraform plan / cloud console export

3. **Time-boxed window:**
   - Guard mode auto-expires after 1 hour
   - Re-enter to extend

4. **Audit log enrichment:**
   - Every action logged with "guard-mode" tag + the captured "what/why"
   - Logged to `wiki/compliance/evidence/guard-mode-log.md`

5. **Postmortem on mistakes:**
   - If something goes wrong while in guard mode → /incident automatically

## Step 4 — Announce

```
🔴 GUARD MODE ACTIVATED — highest caution

What:           {change}
Why:            {justification}
Failure modes:  {list}
Rollback:       {plan}
Approver:       {name}
Expires:        {entered + 1 hour}

While in guard mode:
  ✓ Everything in /careful mode
  ✓ Explicit "yes" required for every action
  ✓ Snapshot taken before action
  ✓ Auto-expires in 1 hour
  ✓ Actions logged to wiki/compliance/evidence/guard-mode-log.md
  ✓ If anything breaks → /incident automatically

Recommended next:
  - Walk through the change step by step
  - Confirm each step before execution
  - Run /unfreeze when done (or wait for 1-hour auto-expire)
```

## Pitfalls

- Entering guard mode without a rollback plan — defeats the purpose
- Spending too long in guard mode → fatigue → typo → disaster
- Bypassing the explicit "yes" requirements — strip the safety
- Not capturing the snapshot — can't compare or restore

## Verification

- `.claude/state/mode.json` written with mode = "guard" and all required fields
- All "what/why/rollback" fields filled
- Snapshot taken or confirmed
- Time-bound expiry set
