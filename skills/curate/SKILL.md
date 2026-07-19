---
name: curate
description: |
  TRIGGER when: the user runs /curate to review the health of the skill library.
  Also trigger when the user asks to clean up, consolidate, or audit skills.
  DO NOT TRIGGER when: the user wants to create a new skill (/learn) or fix
  the framework itself (/framework-check).
user_locked: true
pinned: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
effort: high
---

## When to Use

Monthly skill library maintenance. Or when the library feels cluttered.
Or when /learn has been adding skills frequently and a review is due.

## Procedure

### Step 1 — Read Telemetry

Read `~/.claude/logs/skill-usage.log` (and rotated logs `.1`, `.2`, `.3` if they exist).
Parse all JSONL lines. Build a usage map: `{ skill_name: [list of timestamps] }`.

If the log is empty or missing, report:
"No telemetry data yet. Run some skills first, then /curate will have data to analyze.
 I can still check structural completeness — proceed? (yes/skip)"

### Step 2 — Scan Skill Library (both scopes)

List every SKILL.md under BOTH:
- `~/.claude/skills/` (global — framework + global learned skills)
- `<project-root>/.claude/skills/` (project-local, including `learned/`) if run inside a project

For each:
- Read frontmatter (user_locked, pinned, description, name)
- Compute days-since-last-use from telemetry (if available)
- Compute invocation count over the last 90 days
- Check which of the 4 required sections exist (When to Use, Procedure, Pitfalls, Verification)
- Note the creation date (from git log or file timestamp)

### Step 3 — Generate Findings

Produce findings in these categories:

**STALE** (no invocation in 90+ days, and skill is older than 30 days):
- Skill name, days-since-last-use, locked/pinned status
- Recommendation: review for retirement
- Skip skills created in the last 30 days (they're new, not stale)

**LOW USAGE** (1-3 invocations in 90 days):
- Skill name, count, last used
- Recommendation: check if the trigger description is too narrow

**POSSIBLE DUPLICATES** (similar "When to Use" sections or 90%+ overlapping procedure):
- Pair of skills, similarity reason
- Recommendation: consolidate (keep the more-used one)

**MISSING STRUCTURE** (skills without all 4 required sections):
- Skill name, which sections are missing
- Recommendation: backfill the missing sections

**MISFILED SCOPE** (learned skills in `~/.claude/skills/learned/` whose content is
project-specific — mentions project paths, a specific stack, service names, or client context):
- Skill name, evidence of project-specificity, best-guess owning project
- Recommendation: relocate to that project's `.claude/skills/learned/`, or retire if the project is done

### Step 4 — Present Report

```
━━━ SKILL LIBRARY CURATION REPORT ━━━
Generated: {date}
Telemetry window: last 90 days
Total skills: {count}
Total invocations: {count}

STALE ({count}):
  1. /{name} — {days} days since last use [{locked/pinned status}]
     Recommendation: review for retirement
     Action? (keep / retire / edit-trigger / skip)

LOW USAGE ({count}):
  1. /{name} — {count} uses in 90 days, last used {date} [{status}]
     Recommendation: check trigger description
     Action? (keep / edit-trigger / skip)

POSSIBLE DUPLICATES ({count}):
  1. /{name1} and /{name2} — {similarity reason}
     Recommendation: consolidate, keep /{more-used} (used {N}x more)
     Action? (consolidate / keep-both / skip)

MISSING STRUCTURE ({count}):
  1. /{name} — missing: {sections}
     Action? (backfill / skip)

MISFILED SCOPE ({count}):
  1. /{name} — global but project-specific ({evidence}); likely belongs to {project}
     Action? (relocate / retire / keep-global / skip)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 5 — Execute Approved Actions

For EACH finding, wait for the user's individual decision. NEVER batch-approve.

- **retire**: move the skill folder to `~/.claude/skills-retired/{name}/`
- **consolidate**: edit the kept skill to fold in unique value, move the other to skills-retired/
- **edit-trigger**: open the SKILL.md and ask the user what to change in the description
- **backfill**: add the missing sections with placeholder content for the user to fill
- **relocate**: move the skill folder to the owning project's `.claude/skills/learned/`
  (confirm the project path with the user first)
- **keep/skip**: no action

### Step 6 — Log Actions

Append every action to `~/.claude/logs/curate-history.log` (JSONL):
`{"timestamp":"...","action":"retire","skill":"...","reason":"stale 120 days"}`

### Step 7 — Final Summary

```
Curation complete:
  Reviewed: {count} skills
  Retired: {count}
  Consolidated: {count}
  Triggers edited: {count}
  Structure backfilled: {count}
  Skipped: {count}

Run /framework-check to verify the library is still healthy.
```

## Pitfalls

- DO NOT auto-execute. Every change requires explicit per-item user approval.
- DO NOT touch skills where `user_locked: true` except to flag them as stale.
- DO NOT delete — always move to `skills-retired/`. Deletion is the user's call.
- DO NOT propose consolidating a pinned skill into another skill.
- DO NOT trust telemetry blindly — exclude skills created in the last 30 days from stale checks.
- If unsure whether a change is good, default to "skip and flag for human review".

## Verification

- All proposed changes were approved by the user before action
- No locked skills were edited
- No pinned skills were retired or consolidated
- Every action was logged to curate-history.log
- The skill library still passes /framework-check after curation
