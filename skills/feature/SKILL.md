---
name: feature
description: |
  TRIGGER when: the user wants to add, list, update status of, or archive a feature,
  bug, or chore in the project backlog. Also triggered to view the feature pipeline.
  DO NOT TRIGGER when: the user wants to start BUILDING a feature (use /new-feature),
  fix a known bug (use /bug-fix), or triage incoming support (use /triage).
argument-hint: "[add|list|show|update|archive|export] [args]"
disable-model-invocation: true
user_locked: true
pinned: true
---

# Feature Lifecycle Management

## When to Use

To capture and track every feature/bug/chore in the project pipeline. Each
item moves through states (proposed → in-progress → review → shipped → archived).
The `/new-feature`, `/bug-fix`, `/pr`, and `/wrap-up` skills automatically
update lifecycle state as work progresses.

**Use this skill when you want to:**
- Add a new item to the backlog before starting to build (`/feature add`)
- See what's in flight across the project (`/feature list`)
- Look at a specific item's history (`/feature show <id>`)
- Manually correct a status (`/feature update <id> <status>`)
- Close out something that won't ship (`/feature archive <id>`)
- Generate a JSON export for an external dashboard (`/feature export`)

## Lead Engineer Guidance — Why This Matters

Without lifecycle tracking, the project ends up with:
- Features in flight that nobody remembers
- "Is this shipped yet?" confusion
- No SOC 2 evidence for change management (auditors want this)
- No clear "what to work on next" view

With it:
- Every commit ties back to a tracked feature
- `/status` shows the real pipeline, not a vibe
- Dashboard export gives clients/team a single source of truth
- Production-stream SOC 2 controls satisfied (CC8: change management)

**Pattern to learn:** Capture features in this system BEFORE building them.
The natural flow is: `/feature add` → discuss/spec → `/new-feature` to build.
The `/new-feature` skill will auto-transition the feature to `in-progress`.

## Procedure

## Step 1 — Determine Operation

Parse `$ARGUMENTS`:
- `add` — create a new feature/bug/chore
- `list` — print all items, optionally filtered by status
- `show <id>` — display one item's full content
- `update <id> <status>` — manually change status
- `archive <id>` — close out (special case of update)
- `export` — write JSON to `wiki/features/_export.json`
- empty — default to `list`

## Step 2 — Verify Setup

Check `wiki/features/` directory exists. If missing, create it.

Check `wiki/features/.gitignore` excludes `_export.json` if user wants it
gitignored (default: keep export gitignored — it's regenerated).

## Step 3 — Operation: ADD

Ask the user (if not provided):
1. Title (one-line)
2. Type: `feature` / `bug` / `chore` / `epic`
3. Priority: `P0` / `P1` / `P2` / `P3` (see /triage for definitions)
4. Initial status: `proposed` (default) or `in-progress` if starting now
5. Description (one paragraph — what and why)
6. Acceptance criteria (optional, bulleted)

Generate ID: `{type-prefix}-{NNN}` where prefix is `feat`/`bug`/`chore`/`epic`
and `NNN` is next available number for that type.

Generate slug: `{id}-{kebab-case-title}` (truncate title to 40 chars).

Create file `wiki/features/{slug}.md`:

```markdown
---
id: {id}
title: {title}
type: {type}
status: {status}
priority: {priority}
owner: {user}
created: {YYYY-MM-DD}
updated: {YYYY-MM-DD}
branch: null
pr: null
shipped_at: null
spec: null
---

# {title}

## Description
{description}

## Acceptance Criteria
- [ ] {criterion 1}
- [ ] {criterion 2}

## Notes
(running notes here)

## Activity Log
- {YYYY-MM-DD HH:MM} created (status: {status})
```

After creation, report:
```
Added: {id} — {title}

Type:     {type}
Priority: {priority}
Status:   {status}
File:     wiki/features/{slug}.md

Recommended next:
  - For features: when ready to build, run /new-feature (auto-transitions to in-progress)
  - For bugs: when ready to fix, run /bug-fix (auto-transitions to in-progress)
  - To capture more: run /feature add again
```

## Step 4 — Operation: LIST

Read all files in `wiki/features/`.
Parse frontmatter from each.
Group by status, print as a table:

```
Feature Pipeline — {project name}
Updated: {YYYY-MM-DD HH:MM}

📋 PROPOSED ({N})
  {id}   {priority}  {type}    {title}                          {created}
  ...

🔨 IN PROGRESS ({N})
  {id}   {priority}  {type}    {title}                          {branch}
  ...

👀 REVIEW ({N})
  {id}   {priority}  {type}    {title}                          {pr URL}
  ...

✅ SHIPPED — last 5
  {id}   {priority}  {type}    {title}                          {shipped_at}
  ...

📦 ARCHIVED — last 5
  {id}   {priority}  {type}    {title}                          {updated}
  ...

Total active: {N}  (proposed + in-progress + review)
Total shipped this month: {N}
```

Support filtering: `/feature list status:in-progress` or `/feature list type:bug`.

## Step 5 — Operation: SHOW

Read the file for the given ID. Print full content (frontmatter + body).
Highlight current status with a clear indicator.

```
Feature {id} — {title}

Status:    {status}  [proposed → in-progress → review → shipped]
                                  ↑ current
Priority:  {priority}
Type:      {type}
Owner:     {owner}
Created:   {created}
Updated:   {updated}
Branch:    {branch or "—"}
PR:        {pr or "—"}
Spec:      {spec or "—"}

{body}

Suggested next action:
  {if status=proposed: "/new-feature to start building, or /feature archive to close out"}
  {if status=in-progress: "complete the build, then /pr"}
  {if status=review: "address Code Reviewer findings, merge PR via gh pr merge"}
  {if status=shipped: "no action — feature complete"}
```

## Step 6 — Operation: UPDATE

Validate the requested status transition.
Allowed transitions:

| From          | To                                                                   |
|---------------|----------------------------------------------------------------------|
| proposed      | in-progress, archived                                                |
| in-progress   | review, proposed (rare — pause work), archived                       |
| review        | shipped, in-progress (if changes needed), archived (rare — abandoned)|
| shipped       | (terminal — only archive)                                            |
| archived      | proposed (un-archive)                                                |

If transition is invalid, refuse with explanation.
If valid, update the frontmatter:
- Set `status` to new value
- Set `updated` to today
- If transitioning to `shipped`, set `shipped_at` to today
- Append to Activity Log: `- {timestamp} status: {old} → {new} ({reason if given})`

## Step 7 — Operation: ARCHIVE

Shortcut for `update <id> archived`. Also asks for archive reason:
- `duplicate` — duplicate of {other id}
- `deprioritized` — won't do for now
- `rejected` — decided against
- `superseded` — replaced by {other id}

Append reason to Activity Log.

## Step 8 — Operation: EXPORT

Write `wiki/features/_export.json`:

```json
{
  "generated_at": "{ISO timestamp}",
  "project": "{project name}",
  "stream": "{stream}",
  "features": [
    {
      "id": "feat-001",
      "title": "...",
      "type": "feature",
      "status": "in-progress",
      "priority": "P1",
      "owner": "NT",
      "created": "2026-06-29",
      "updated": "2026-06-29",
      "branch": "feature/foo",
      "pr": null,
      "shipped_at": null
    }
  ],
  "summary": {
    "by_status": {"proposed": 3, "in-progress": 2, "review": 1, "shipped": 12, "archived": 4},
    "by_type": {"feature": 14, "bug": 6, "chore": 2},
    "by_priority": {"P0": 0, "P1": 5, "P2": 12, "P3": 5},
    "shipped_this_month": 5,
    "open_total": 6
  }
}
```

This JSON is consumed by external dashboards.

## Auto-Update Hooks (read-only summary)

These skills auto-update feature lifecycle:
- `/new-feature` — on start, transitions `proposed → in-progress` for the named feature; sets `branch` field
- `/bug-fix` — on start, transitions bug to `in-progress`; sets `branch`
- `/pr` — on PR creation, transitions to `review`; sets `pr` URL
- `/wrap-up` — checks for merged PRs (via `gh pr view --json`), transitions to `shipped`
- `/deploy` — for production deploys, confirms shipped status

If a feature isn't tracked yet (you started building without /feature add),
the `/new-feature` skill will offer to create the feature record retroactively.

## Pitfalls

- Skipping /feature add and just building — lifecycle gets out of sync, dashboard goes stale
- Manually editing wiki/features/*.md without going through /feature update — Activity Log stays incomplete (no audit trail for SOC 2)
- Letting "proposed" items pile up without triage — backlog rots
- Marking things "shipped" without actually deploying — misleads stakeholders
- Skipping archive (just deleting files) — loses historical record
- Not running /feature export when an external dashboard needs fresh data

## Verification

- `wiki/features/{slug}.md` written with all frontmatter fields populated
- Activity Log entry added for every status change
- Status transitions follow the allowed table
- Export JSON written when requested (or auto-triggered by /wrap-up)
- User knows the recommended next action for the current state
