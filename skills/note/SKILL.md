---
name: note
description: |
  TRIGGER when: the user says /note, "note this down for next session", "leave a note",
  "remind me next time", "remind me when we resume", or wants to leave themselves a
  message for a future session.
  DO NOT TRIGGER when: the user wants to capture a reusable pattern (/learn), update
  documentation (/document-all), or record project knowledge (wiki/memory.md — that's
  the Wiki Updater's job).
argument-hint: "[text]"
user_locked: true
---

# Note to Next Session

## When to Use

The user wants to leave themselves (or Claude) a reminder that surfaces at the
next `/resume` — an idea, a question, a "don't forget." This is the user's inbox,
not project documentation: notes are transient by design and get marked seen
once announced.

## The Inbox File

- In a project with `wiki/`: `wiki/notes/inbox.md` (create the folder on first use)
- Outside a project (no `wiki/`): `~/.claude/notes/inbox.md` (global inbox)

Format — one line per note, checkbox = read state:

```markdown
- [ ] 2026-07-19 23:55 — Ask Claude to check the acme churn numbers before Monday's call
- [x] 2026-07-15 22:10 — Vercel bill looked high (seen 2026-07-17)
```

`[ ]` = unread. `[x]` = announced at a /resume, with the seen date appended.

## Subcommands

### `/note {text}`

1. Resolve the inbox path (project first, global fallback).
2. Append: `- [ ] {YYYY-MM-DD HH:MM} — {text}`
3. Confirm: "Noted. I'll surface this at the next /resume."

### `/note` (no text)

Ask: "What should I note down for the next session?" Then append as above.

### `/note list`

Show the inbox — unread first, then the last 5 seen. If empty:
"No notes. /note {text} to leave one for next session."

## Integration

- **/resume** announces unread notes FIRST — before the session summary — then
  marks each `[x]` with the seen date.
- **Mission Control dashboard** (when built) reads and writes the same file —
  one inbox, two entry points.

## Pitfalls

- Do NOT use the inbox for project knowledge — that belongs in wiki/memory.md.
  A note is a message to a future session, not a fact about the project.
- Do NOT delete notes — mark them seen. The file is an append-only trail.
- Do NOT mark a note seen unless it was actually announced to the user.

## Verification

- Note appended with timestamp and `[ ]` state
- The inbox file is valid markdown (checkbox list)
- /resume announces unread notes and flips them to `[x]` with seen date
