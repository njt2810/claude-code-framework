---
name: careful
description: |
  TRIGGER when: the user wants to enter "careful mode" for risky work (auth,
  payments, migrations, PII, production deploys), or says "be careful here",
  "this is risky", "extra caution".
  DO NOT TRIGGER when: the user is doing routine work — careful mode adds friction.
disable-model-invocation: true
user_locked: true
pinned: true
---

# Careful Mode

## When to Use

Toggle the project into "careful mode" for high-stakes work. Adds extra
confirmations, slows down destructive operations, and brings in extra
review passes.

## Lead Engineer Guidance — Why This Matters

Most code changes are routine — small risk, fast iteration is fine. But some
changes are NOT routine:
- Database migrations (esp. destructive)
- Authentication code
- Payment processing code
- PII handling
- Production deploys
- Anything affecting paying clients' data

For these, the cost of a mistake is much higher than the cost of friction.
Careful mode adds the friction proportional to the stakes.

**Run `/careful` BEFORE starting risky work.** Run `/unfreeze` to exit.

Sibling skills:
- `/guard` — even higher caution (touches CRITICAL systems)
- `/freeze` — read-only mode (no writes at all to specific paths)
- `/unfreeze` — return to normal mode

## Procedure

## Step 1 — Determine Scope

Ask the user (or accept argument):
- What are you about to do? (one-line)
- Which paths/files does it affect? (optional)

## Step 2 — Set Mode

Write to `.claude/state/mode.json` (create directory if missing):

```json
{
  "mode": "careful",
  "scope": "{user description}",
  "paths": ["..."],
  "entered_at": "{ISO timestamp}",
  "entered_by": "{user}",
  "expected_duration": "{user estimate or 'until /unfreeze'}"
}
```

Add `.claude/state/` to `.gitignore` if not already there.

## Step 3 — Apply Careful Mode Rules

While in careful mode, the following apply:

1. **Confirm before destructive operations:**
   - Before `git push --force`, `git reset --hard`, `rm -rf` → require explicit "yes confirm"
   - Before `DROP TABLE`, `DROP COLUMN`, `TRUNCATE` → require explicit confirmation + verify backup exists
   - Before deploy to production → require triple confirmation

2. **Auto-delegate review:**
   - Every code change touching the scope paths → auto-delegate to Code Reviewer
   - If touching auth/payments/PII → also auto-delegate to Security Auditor + Compliance Officer

3. **Two-attempt limit instead of three:**
   - In normal mode, /bug-fix allows 2 attempts then STOPs
   - In careful mode, ONLY 1 attempt — then stop and reassess

4. **No background commands:**
   - All commands run in foreground with real-time reporting

5. **Pre-commit smoke tests:**
   - Run a fast smoke test before every commit (auth check, schema check, etc.)

6. **Audit log enrichment:**
   - All actions during careful mode logged with "careful-mode" tag

## Step 4 — Announce Mode

```
🟡 CAREFUL MODE ACTIVATED

Scope:              {description}
Paths:              {if specified}
Entered:            {timestamp}

While in careful mode:
  ✓ Destructive ops require explicit confirmation
  ✓ Touched code auto-delegated to reviewers
  ✓ Two-attempt limit reduced to one
  ✓ No background commands (foreground only)
  ✓ Pre-commit smoke tests
  ✓ Actions tagged 'careful-mode' in audit log

Recommended next:
  - Proceed with the risky work
  - Run /unfreeze when done to return to normal mode
  - Run /guard if you need EVEN MORE caution (CRITICAL systems)
```

## Pitfalls

- Forgetting to /unfreeze — careful mode persists into routine work, frustration
- Entering careful mode without naming the scope — vague guards = ignored guards
- Using careful mode for everything — it becomes background noise, loses signal
- Not pairing with /pr — careful mode doesn't replace code review

## Verification

- `.claude/state/mode.json` written with mode = "careful"
- Scope and paths captured
- User informed of what changes in this mode
