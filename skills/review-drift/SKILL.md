---
name: review-drift
description: |
  TRIGGER when: the user wants to check if the codebase matches the original spec,
  or says "check drift", "review drift", "does the code match the spec", "what diverged",
  "what changed from the plan", or wants to audit spec compliance after multiple features.
  DO NOT TRIGGER when: the user wants a code review (/code-review), security check
  (/security-check), or documentation audit (/document-all).
disable-model-invocation: true
context: fork
user_locked: true
---

# Review Drift — Spec vs Code Alignment Check

## When to Use

After building multiple features, before demos, before handoffs, or when
something feels "off" from the original vision. Not for code reviews,
security audits, or documentation cleanup.

## Procedure

Detect where the codebase has diverged from its specifications, plans, and
constitution. Useful after building multiple features, before demos, before
handoffs, or when something feels "off" from the original vision.

Inspired by spec-driven development drift detection.

## Step 1 — Gather Source of Truth Documents

Read ALL of these (skip any that don't exist):

1. `constitution.md` — project principles and constraints
2. `wiki/decisions/` — all ADRs (architectural decisions)
3. `wiki/architecture.md` — system design
4. `wiki/conventions.md` — code patterns and standards
5. `wiki/PROJECT_STATUS.md` — declared current state
6. `CLAUDE.md` — project rules and context
7. `wiki/memory.md` — accumulated knowledge

Also read:
8. `wiki/logs/` — recent session logs (last 3-5 sessions)
9. `graphify-out/GRAPH_REPORT.md` if it exists

Summarize what the project SHOULD look like according to these documents.

## Step 2 — Scan the Actual Codebase

Examine what actually exists:

1. Read the file structure and key source files
2. Run `git log --oneline -20` to see recent changes
3. Check test coverage: are specified features tested?
4. Check for code that doesn't match documented patterns
5. Check for features that exist in code but aren't in any spec or decision

## Step 3 — Identify Drift

Compare source-of-truth documents against the actual codebase.
Categorize findings:

### Specified but not built
Features, requirements, or decisions documented in specs/ADRs that
don't appear to be implemented in the codebase.

### Built but not specified
Code, features, or behaviors that exist in the codebase but aren't
documented in any spec, ADR, or architecture doc. This is "stealth scope."

### Diverged from plan
Features that were built differently from how they were specified or planned.
The code works, but it doesn't match what was decided.

### Constitution violations
Code or patterns that violate principles stated in constitution.md or
non-negotiable rules.

### Stale documentation
Documentation that describes something that no longer matches the code.
Includes outdated architecture docs, obsolete conventions, and wrong
status information.

## Step 4 — Present the Drift Report

```
DRIFT REPORT — {Project Name}
Date: {today}

Documents checked: {count}
Files scanned: {count}

SPECIFIED BUT NOT BUILT ({count}):
  {requirement from spec/ADR} — Expected in: {where} — Status: not found
  ...

BUILT BUT NOT SPECIFIED ({count}):
  {file/feature} — What it does: {description} — Not in any spec/ADR
  ...

DIVERGED FROM PLAN ({count}):
  {feature} — Spec says: {what was planned} — Code does: {what exists}
  ...

CONSTITUTION VIOLATIONS ({count}):
  {violation} — Rule: {which rule} — Where: {file/line}
  ...

STALE DOCUMENTATION ({count}):
  {doc file} — Says: {what it says} — Reality: {what's true now}
  ...

ALIGNMENT SCORE: {percentage of spec that matches code}
```

## Step 5 — Recommend Actions

For each finding, recommend one of:

- **Update the spec** — if the code is correct and the spec is outdated
- **Update the code** — if the spec is correct and the code diverged
- **Create an ADR** — if the divergence was an intentional decision that wasn't documented
- **Update documentation** — if the docs are stale but code and spec agree
- **Discuss with user** — if it's unclear which is correct

```
RECOMMENDED ACTIONS:

  Priority 1 (constitution violations — fix now):
    {action}

  Priority 2 (specified but not built — decide if still needed):
    {action}

  Priority 3 (built but not specified — document or remove):
    {action}

  Priority 4 (stale docs — update when convenient):
    {action}
```

GATE — Wait for the user to decide which actions to take.

## Step 6 — Execute Approved Actions

For each approved action:
1. Make the change (update doc, create ADR, or flag for code changes)
2. Report what was done
3. If code changes are needed, recommend /new-feature or /bug-fix

After all actions:
```
Drift review complete.
  {count} findings addressed
  {count} deferred
  Alignment score: {before} -> {after}

  Next recommended drift review: after {N} more features or in {timeframe}
```

Update `wiki/memory.md` with the drift review date and results.

## Pitfalls

- Treating "built but not specified" as always bad — it may be intentional; ask first
- Not checking git log for context on why something diverged
- Updating specs to match code without asking (the code might be wrong)
- Running this without constitution.md reduces the value significantly

## Verification

- All source-of-truth documents were checked
- Findings are categorized correctly (5 drift types)
- Each finding has a recommended action
- User approved actions before execution
- wiki/memory.md was updated with the drift review date
