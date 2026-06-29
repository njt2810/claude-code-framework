---
name: unfreeze
description: |
  TRIGGER when: the user wants to exit careful/guard/freeze mode and return
  to normal operation. Also when user says "we're done", "back to normal",
  "exit careful mode".
  DO NOT TRIGGER when: you're entering one of those modes (use that skill directly).
disable-model-invocation: true
effort: low
user_locked: true
pinned: true
---

# Unfreeze — Return to Normal Mode

## When to Use

When you're done with the risky/cautious work and want the project back to
normal speed. Clears `/careful`, `/guard`, or `/freeze` state.

## Lead Engineer Guidance — Why This Matters

If you forget to /unfreeze, the friction from careful/guard/freeze mode
persists into routine work. That trains you to ignore the warnings. So:

- Always /unfreeze when the risky work is complete
- Pair entering a mode with planning to exit it
- Run /unfreeze at the start of every session unless you know why you're in a special mode

## Procedure

## Step 1 — Check Current Mode

Read `.claude/state/mode.json`. Determine current mode.

If file doesn't exist OR mode is already "normal": say so and exit.

## Step 2 — Verify Completion

Ask:
- "You were in {mode} for: {captured reason / what}. Is that work complete?"
- If no: confirm exiting anyway

## Step 3 — Log Exit

Append to mode log:

For careful/guard mode, write summary to `wiki/compliance/evidence/{mode}-mode-log.md`:

```markdown
## {ISO timestamp} — {mode} mode exited

Entered:   {entered_at}
Duration:  {N} minutes
Scope:     {what was protected}
Reason:    {original reason}
Outcome:   {complete | abandoned | mistake-needed-rollback}
Actions:   {summary of what was done}
```

For freeze mode, just log to session log.

## Step 4 — Clear State

Update `.claude/state/mode.json`:

```json
{
  "mode": "normal",
  "exited_at": "{ISO}",
  "previous_mode": "{what we just exited}"
}
```

## Step 5 — Announce

```
✓ Mode cleared — back to normal

Was in:    {previous mode}
Duration:  {time}
Logged:    {evidence file path, if applicable}

Recommended next:
  - Resume routine work
  - If you completed risky work: consider committing the audit-trail entry
  - For production streams: /compliance-status to verify nothing slipped
```

## Pitfalls

- Exiting without completing the work — you'll re-enter and lose context
- Forgetting to log outcome — audit trail incomplete
- Exiting freeze prematurely — could overwrite something you were investigating

## Verification

- `.claude/state/mode.json` set to mode = "normal"
- Log entry written if applicable
- User confirms work was actually complete (or explicitly says abandoned)
