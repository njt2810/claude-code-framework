---
name: document-all
description: |
  TRIGGER when: the user wants a full documentation audit, cleanup, or reorganization.
  Also trigger for "update all docs", "clean up the project", "prepare for handoff",
  or before demos and deployments.
  DO NOT TRIGGER when: the user wants to update a single file, write a README,
  or do a security check (/security-check).
disable-model-invocation: true
context: fork
user_locked: true
---

# Full Documentation + Reorganization

## When to Use

When the user wants a full documentation audit, cleanup, or reorganization.
Before demos, deployments, or handoffs. Not for single-file updates or security audits.

## Procedure

### Phase 1 — Documentation Audit

Scan all existing documentation and grade each file:

```
Documentation Audit:
  EXISTS + CURRENT  — {file} (updated within 7 days)
  EXISTS + STALE    — {file} (last updated {N} days ago)
  MISSING           — {file}
```

Check each of these:
- README.md
- CLAUDE.md
- wiki/architecture.md
- wiki/conventions.md
- wiki/memory.md
- wiki/PROJECT_STATUS.md
- wiki/decisions/ (are there ADRs for major decisions?)
- wiki/learnings.md
- .env.example (does it match actual required vars?)
- .gitignore (is it comprehensive?)

Present the audit results. For each STALE or MISSING item, explain what needs to be done.

"I'll fill the gaps and refresh stale docs. Approve?"
GATE — Wait for approval.

## Phase 2 — Fill Documentation Gaps

For each MISSING file, create it with proper content based on the actual codebase.
For each STALE file, update it with current information.

Delegate to the wiki-updater subagent for heavy documentation work.

**wiki/architecture.md** — Update with:
- System overview (what the project does, how it works)
- Component map (which files do what)
- Data flow (how data moves through the system)
- External dependencies and integrations

**wiki/conventions.md** — Update with:
- Code patterns discovered in the codebase
- Naming conventions
- File organization logic

**wiki/PROJECT_STATUS.md** — Update with current state

**README.md** — Create or update with:
- What this project does (one paragraph)
- How to set it up
- How to run it
- How to test it
- How to deploy it

## Phase 3 — Archive + Reorganize (GATE)

Before moving, renaming, or replacing anything:

1. Identify files that should be moved, renamed, or deleted
2. Present the COMPLETE list of proposed changes

GATE — Wait for EXPLICIT approval before making ANY changes.

3. If approved:
   - Create `.archive/` directory if it doesn't exist
   - Copy originals to `.archive/{date}-{filename}` before any changes
   - Execute moves and renames
   - Update all imports/references affected by file moves
   - Run tests to verify nothing broke
   - Add `.archive/` to `.gitignore` if not already there

## Phase 4 — Generate Project Summary

Create or update `wiki/PROJECT_STATUS.md` with full project state.

## Phase 5 — Cross-Reference to Obsidian

Flag learnings that should go to the Obsidian wiki:

"The following learnings from this project may be useful
 across other projects. Consider adding to your Obsidian wiki:
 1. {learning}
 2. {learning}

 Your Obsidian wiki: {path from stream config}"

## Phase 6 — Final Verification

1. Run full test suite → report results
2. Run linter if configured → report results
3. Run graphify → update codebase map
4. Verify .env.example matches required vars
5. Verify .gitignore is comprehensive
6. Commit: "Project fully documented and organized"
7. Push to GitHub if remote configured

## Pitfalls

- Moving or renaming files without backing up to .archive/ first
- Not running tests after file reorganization — moves can break imports
- Generating documentation from assumptions instead of reading actual code
- Overwriting wiki/memory.md content — it's append-only

## Verification

- All documentation files exist and are current (no STALE or MISSING)
- Full test suite passes after any file moves
- .archive/ contains backups of anything that was modified
- Final commit includes all documentation changes
