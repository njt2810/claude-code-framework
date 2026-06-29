# Safety Modes — Always Loaded

The project may be in a heightened-caution mode at any time, set via
`/careful`, `/guard`, or `/freeze`. Always check `.claude/state/mode.json`
at the start of every session and before any risky operation.

## Mode Levels

| Mode | What Changes | When |
|------|--------------|------|
| **normal** | Default protections | Routine work |
| **careful** | Auto-delegate reviewers, 1-attempt limit, no background, pre-commit smoke | Risky changes |
| **guard** | All careful + explicit "yes" per step + snapshot first + 1-hour expiry | Critical systems |
| **freeze** | Read-only on scoped paths — block writes, commits, mutations | Investigation / audit |

## Reading Current Mode

At session start and before risky ops:

```bash
cat .claude/state/mode.json 2>/dev/null
```

If the file exists and mode is not "normal", honor the constraints described
in the respective skill (`/careful`, `/guard`, `/freeze`).

## When to Suggest Entering a Mode

The Lead Engineer should proactively suggest:

**Suggest /careful when about to:**
- Modify authentication code
- Modify payment / billing code
- Touch PII columns
- Run a database migration
- Deploy to production
- Change CI/CD config

**Suggest /guard when about to:**
- Rotate production signing keys
- Modify cloud IAM roles
- Change auth provider trust relationships
- Modify Stripe webhook endpoints
- Change anything in the secret manager

**Suggest /freeze when:**
- Investigating an incident (freeze unrelated code)
- Doing a security audit
- Reviewing a PR without authority to merge
- Onboarding a contractor with limited scope

## Bypassing Safety Modes

If the user attempts to bypass (e.g., uses raw bash to write to a frozen
path), refuse and explain:

"🧊 You're in {mode} mode, scope includes {path}. Either:
  1. Run /unfreeze first if the work is genuinely safe
  2. Run /careful or /guard with an explicit override scope"

Never silently bypass.

## Mode Persistence Across Sessions

`.claude/state/mode.json` persists across sessions (it's not in .gitignore by default).
A session starting in a non-normal mode should warn the user:

"⚠️ This project is in {mode} mode (entered {when} by {who}, reason: {reason}).
  Run /unfreeze to return to normal, or continue with caution."
