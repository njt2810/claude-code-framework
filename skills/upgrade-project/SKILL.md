---
name: upgrade-project
description: |
  TRIGGER when: the user runs /upgrade-project, asks to bring an existing project
  up to date with the latest framework, or /init-project detects the project was
  initialized with an older framework version.
  DO NOT TRIGGER when: the project has never been initialized (/init-project),
  the user wants to resume work (/resume), or wants framework health (/framework-check).
disable-model-invocation: true
user_locked: true
pinned: true
argument-hint: "[--dry-run]"
---

# Framework Upgrade for an Existing Project

## When to Use

A project was initialized with an older version of the framework and needs to
catch up with improvements — new skills, updated templates, fixed hooks —
WITHOUT losing any project state or history.

Core promise: **assess → report → archive (never delete) → apply → resume**.

## Never-Touch List (protected project state)

These are the project's memory — the upgrade must NEVER modify, move, or archive them:

- `wiki/` content written by the project (features, decisions, logs, clients, time-logs)
- `.claude/state/` (timer, safety mode, feature state)
- `.claude/skills/learned/` (project learned skills)
- `.claude/session-log.jsonl` and any session history
- Project source code, `.env`, secrets, data — obviously
- Project-specific sections the user wrote into CLAUDE.md

## Step 1 — Detect Versions

1. Read `framework_version:` from the project's CLAUDE.md frontmatter or
   `.claude/framework-version` (whichever exists)
2. Read the installed framework version from `~/.claude/VERSION`
3. Report:

```
Project initialized with: {old version / "unknown (pre-versioning)"}
Installed framework:      {current version}
```

If the project has NO version stamp, treat it as pre-versioning: the assessment
in Step 2 becomes the source of truth, and the upgrade adds the stamp at the end.

If versions match: "Project is already on the current framework. Nothing to do."
→ stop.

## Step 2 — Takeover Assessment (read-only)

Scan the project and classify every framework-owned file:

- **CURRENT** — matches the installed framework's template/expectation
- **OUTDATED** — exists but the framework's version has since changed
  (compare against `~/.claude/templates/` and the installed skill/rule set)
- **MISSING** — the framework now provides this but the project lacks it
- **ORPHANED** — framework-shaped file that no current framework version produces
  (leftover from a removed feature or an old experiment)
- **PROTECTED** — on the never-touch list (report count only)

Also detect the stream (`.claude/stream` or CLAUDE.md) — production streams
(org1/org2) get the full template set; personal/learning stay minimal, same
rules as /init-project.

## Step 3 — Present the Upgrade Plan (wait for approval)

```
━━━ UPGRADE PLAN: {project} ({old} → {new}) ━━━
CURRENT   ({n}): no action
PROTECTED ({n}): untouched (project state)

MISSING ({n}) — will be created:
  1. {path} — {why the framework provides it}

OUTDATED ({n}) — will be updated (old copy archived first):
  1. {path} — {what changed}

ORPHANED ({n}) — will be moved to .archive/:
  1. {path} — {why it is orphaned}

Nothing is deleted. Everything replaced or removed goes to
.archive/{YYYY-MM-DD}/ with a manifest.

Apply? (all / pick items / dry-run only)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

With `--dry-run`, stop here.
Per-item approval is available ("pick items") — never force all-or-nothing.

## Step 4 — Archive, Then Apply

For each approved item:

1. If replacing or removing a file: move the current copy to
   `.archive/{YYYY-MM-DD}/{original-relative-path}` first
2. Append one line to `.archive/{YYYY-MM-DD}/MANIFEST.md`:
   `- {path} — {OUTDATED replaced / ORPHANED removed} — {one-line reason}`
3. Then create/update the file from the installed framework

Ensure `.archive/` is in `.gitignore` (init-project already adds it).
CLAUDE.md updates are SURGICAL: only framework-owned sections change;
user-written sections are preserved byte-for-byte.

## Step 5 — Stamp and Verify

1. Write the new version to the project (`framework_version:` in CLAUDE.md
   frontmatter AND `.claude/framework-version`)
2. Re-run the Step 2 scan — everything should now be CURRENT or PROTECTED
3. Append to `wiki/logs/` (or session log): upgrade date, from → to,
   counts of created/updated/archived

## Step 6 — Hand Off to Resume

```
━━━ UPGRADE COMPLETE ━━━
{project}: {old} → {new}
Created: {n}   Updated: {n}   Archived: {n} (in .archive/{date}/)
Protected state untouched: wiki, timers, learned skills, session history.

Type /resume to pick up where you left off.
━━━━━━━━━━━━━━━━━━━━━━━━
```

## Pitfalls

- NEVER delete — everything goes to `.archive/{date}/` with a manifest entry
- NEVER touch the never-touch list, even if a file there looks outdated
- NEVER overwrite user-written CLAUDE.md content — surgical section updates only
- Do not "upgrade" a project that was never initialized — send to /init-project
- Do not run tests/builds as part of upgrade — this is a framework operation,
  not a code change
- If unsure whether a file is framework-owned or project-owned: ask, default to skip

## Verification

- Step 2 re-scan after apply shows zero MISSING/OUTDATED/ORPHANED (or only user-skipped items)
- `.archive/{date}/MANIFEST.md` lists every moved file with a reason
- Version stamp present and matches installed framework
- Protected paths byte-identical before/after (spot-check wiki/ and .claude/state/)
- User approved the plan (and any per-item choices) before any file was touched
