---
name: context
description: |
  TRIGGER when: the user runs /context, asks what identity/rules are active, wants
  to debug conflicting instructions, asks "why did you respond as X", "what realm
  am I in", or "am I in the right realm/project".
  DO NOT TRIGGER when: the user wants project status (/status) or a command
  reference (/help) — this is specifically about resolved CLAUDE.md identity.
disable-model-invocation: true
user_locked: true
pinned: true
allowed-tools:
  - Read
  - Glob
  - Bash
---

## When to Use

Any time it's unclear which identity/rules are actually governing the current
session — after a realm boundary might have been crossed, when two documents
seem to disagree about persona or delegation, or as a routine sanity check
before starting work in an unfamiliar directory. This is a transparency
command, not a config command — it never writes anything.

## Procedure

### Step 1 — Walk the CLAUDE.md ancestor chain

Starting from the filesystem root, walk down to the current working directory,
collecting every `CLAUDE.md` found at each directory level. Always include the
global `~/.claude/CLAUDE.md` first, regardless of cwd.

### Step 2 — Resolve imports

For each `CLAUDE.md` found, check for an `@path` import line (e.g. `@AGENTS.md`).
If present, read the imported file too and note it alongside the importing file
in the output — it's part of that file's effective content even though it lives
in a separate file on disk.

### Step 3 — Extract signal per file

For each file in the chain (in root-to-leaf load order), extract:
- File path
- First non-blank heading or line (usually the title)
- Any line containing "identity", "persona", "NON-NEGOTIABLE", or "override"
  — a cheap heuristic for conflict-relevant content, not a full parse

### Step 4 — Flag conflicts

If more than one file in the chain contains identity/persona language, print an
explicit warning: "⚠ N files claim identity content — check for conflicts."
List which files, then state which one wins and why: **most-specific wins** —
a project-level CLAUDE.md beats a realm-root CLAUDE.md, which beats the global
CLAUDE.md. If two files at the SAME level both claim identity (shouldn't happen
under normal use, but flag it if it does), say so explicitly rather than picking
one silently.

### Step 5 — Resolve the realm

Read `~/.claude/realms.json` if it exists. Prefix-match the current working
directory against every registered realm root, longest match wins. Report:
- Which realm was resolved (or "unregistered location" if no match)
- The realm root path that matched
- Whether `realms.json` itself exists at all (if missing, say so — the realm
  system isn't configured on this machine yet, not just "no match")

### Step 6 — Print the summary

```
Resolved CLAUDE.md chain for: {cwd}

1. {path} — "{title}" — contains: {signals, or "—" if none}
2. {path} — {imports @X if any} — contains: {signals}
...

{⚠ N files claim identity content — resolved: {file} wins ({reason}).}
{or: No identity conflicts — {N} file(s) in chain, none claim identity/persona content.}

Realm: {realm-key} (matched via realms.json prefix: {realm-root})
{or: Realm: unregistered — this location isn't part of any realm in realms.json}
{or: Realm: none configured — ~/.claude/realms.json doesn't exist yet}
```

## Example output

Run from inside a realm-root project that overrides identity:

```
Resolved CLAUDE.md chain for: C:\Users\you\Documents\Work\Acme\billing-service\

1. ~/.claude/CLAUDE.md — "Global Rules" — contains: NON-NEGOTIABLE, identity
2. Documents\Work\CLAUDE.md — imports @AGENTS.md — contains: override, identity
3. Documents\Work\Acme\billing-service\CLAUDE.md — "Billing Service" — contains: —

⚠ 2 files claim identity content — resolved: Documents\Work\CLAUDE.md wins
  (most specific realm-level override; project CLAUDE.md doesn't redeclare).

Realm: work (matched via realms.json prefix: Documents\Work\)
```

## Edge cases

- **No `CLAUDE.md` found anywhere but global**: report "No project/realm context
  — running on global defaults only." Don't fabricate a realm resolution.
- **cwd not under any registered realm**: report "Unregistered location — not
  part of any realm in realms.json" rather than silently guessing which realm
  is "closest."
- **`realms.json` doesn't exist**: report this distinctly from "no match" — it
  means the realm system was never set up on this install, not that this one
  location happens to fall outside it.
- **A `CLAUDE.md`'s `@import` target is missing**: note the broken import rather
  than silently skipping it — this is exactly the kind of drift the realm
  system exists to prevent, so surface it.

## Pitfalls

- Don't just print file paths — the whole point is showing which one actually
  *wins*, and why. A list without a resolved verdict doesn't answer "why did you
  respond as X."
- Don't guess a realm when cwd doesn't match any `realms.json` entry — say so
  plainly instead of picking the nearest-looking one.
- This command never writes files or modifies state — it's read-only diagnostics.

## Verification

- The full ancestor chain is printed in root-to-leaf load order, not just the
  nearest file
- Any `@import` is resolved and attributed to its importing file
- If 2+ files claim identity, a conflict warning and explicit resolution are
  both printed — not just a list
- The realm resolution line always appears, even when there's no match
