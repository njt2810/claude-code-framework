---
name: freeze
description: |
  TRIGGER when: the user wants to freeze certain paths/files from any writes,
  enter read-only investigation mode, or temporarily lock down areas during
  incident analysis.
  DO NOT TRIGGER when: the user just wants extra caution (use /careful).
disable-model-invocation: true
effort: low
user_locked: true
pinned: true
---

# Freeze Mode

## When to Use

When you want to make certain paths/files completely off-limits to writes.
Useful for:
- Reading production data to investigate an issue (don't accidentally modify)
- Doing a deep code audit without changing anything
- Reviewing a PR while preventing accidental edits
- During an active incident — freeze unrelated areas to constrain blast radius
- Onboarding a contractor — freeze sensitive paths to limit their reach

## Lead Engineer Guidance — Why This Matters

Freeze gives you "read-only" by convention. Combined with `/careful` and
`/guard`, you can choose the right level of caution per context:

- **freeze:** can't write at all (audit/investigate mode)
- **guard:** can write only with explicit confirmation (critical changes)
- **careful:** can write but with extra reviews (risky changes)
- **(normal):** routine work, default protections

## Procedure

## Step 1 — Determine Scope

Ask:
- Which paths should be frozen? (glob patterns)
- For how long? (until /unfreeze, or N hours)
- Why are you freezing? (for the log)

Common scope examples:
- `["**/*"]` — freeze entire repo (full read-only)
- `["src/auth/**", "src/billing/**"]` — freeze sensitive areas
- `["wiki/legal/**"]` — freeze legal docs during lawyer review
- `["**/migrations/**"]` — freeze migrations during incident

## Step 2 — Set Mode

Write to `.claude/state/mode.json`:

```json
{
  "mode": "freeze",
  "scope": ["**/*"],
  "reason": "{why}",
  "duration": "{hours or 'until unfreeze'}",
  "entered_at": "{ISO}",
  "entered_by": "{user}"
}
```

## Step 3 — Apply Freeze Rules

While freeze is active:

1. **All Edit/Write/MultiEdit/Bash-write operations on paths in scope are BLOCKED.**
   The Lead Engineer refuses with: "🧊 FREEZE active — cannot write to {path}."

2. **Read operations are unaffected.**

3. **Bash commands that would mutate (rm, mv, sed -i, etc.) on frozen paths
   are refused.**

4. **Git operations are restricted:**
   - No commits while frozen
   - No git push
   - Git read commands (log, status, diff) are fine

5. **If user genuinely needs to write to a frozen path:**
   - They must explicitly run /unfreeze first
   - Or run /careful or /guard with explicit override scope

## Step 4 — Announce

```
🧊 FREEZE ACTIVATED

Scope:    {paths}
Duration: {duration}
Reason:   {why}

While frozen:
  ✓ Read operations: ALLOWED
  ✓ Write operations on frozen paths: BLOCKED
  ✓ Git commits: BLOCKED
  ✓ Bash mutations on frozen paths: BLOCKED

Recommended use:
  - Investigate / audit / review freely
  - When you need to write: /unfreeze first
  - For partial freeze (specific paths only): re-enter /freeze with specific scope
```

## Pitfalls

- Forgetting freeze is active — wonder why edits are blocked
- Freezing the wrong scope — locks out work in unrelated areas
- Freezing during deploy — deploy halts
- Bypassing freeze instead of using /unfreeze — defeats the purpose

## Verification

- `.claude/state/mode.json` shows mode = "freeze" with scope
- Test write attempt on frozen path is refused
- Read attempts work normally
