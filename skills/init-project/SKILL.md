---
name: init-project
description: |
  TRIGGER when: the user runs /init-project (legacy command name, kept for muscle
  memory). Immediately defer to /adopt — see below.
  DO NOT TRIGGER when: the user wants to start building a feature (/new-feature), fix a bug (/bug-fix),
  or resume work (/resume). This is for project SETUP only.
argument-hint: [stream-name] (ignored — realm now auto-detects, see /adopt)
disable-model-invocation: true
user_locked: true
pinned: true
---

# Init Project — Deprecated Alias for /adopt

## When to Use

Only when a user or an old doc/muscle-memory habit invokes `/init-project`
directly. This skill does nothing on its own — it's a thin compatibility
shim so `/init-project` keeps working after v2's realm-pack rewrite.

## Procedure

1. If `$ARGUMENTS` was provided (a legacy `[stream-name]` argument like
   `personal`, `org1`, etc.), note it was ignored: "`/init-project` no
   longer takes a stream argument — realm is now auto-detected from
   `~/.claude/realms.json` based on where you are. Continuing as `/adopt`."
2. Run the full `/adopt` procedure (see `skills/adopt/SKILL.md`) as if the
   user had typed `/adopt` directly.

## Pitfalls

- Do not re-implement any of `/adopt`'s logic here — this file's only job is
  to redirect. If `/adopt`'s procedure changes, this alias should never need
  to change with it.
- Do not silently swallow a stream-name argument without telling the user it
  no longer does anything — they may be relying on old habit or an old doc.

## Verification

- Invoking `/init-project` (with or without an argument) produces the exact
  same outcome as invoking `/adopt` directly, plus the one-line note about
  the ignored argument when one was given.
