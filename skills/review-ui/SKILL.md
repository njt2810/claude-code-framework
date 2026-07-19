---
name: review-ui
description: |
  TRIGGER when: the user asks to review UI, check design quality, review
  frontend implementation, "make it look good", "design review", or
  "check the design". Also triggered by Lead Engineer during /new-feature
  for frontend features.
  DO NOT TRIGGER when: backend-only code review (/code-review), security
  audit (/security-check), general project status (/status), or non-visual work.
user_locked: true
---

# UI/UX Review

## When to Use

When the user asks to review UI quality, check design, or wants a frontend
implementation reviewed against the design system. Not for backend code reviews
or non-visual work.

## Procedure

Delegate to the UI/UX Engineer subagent for a design quality review.

## Step 1 — Check Design System

Check if `design-system/MASTER.md` exists in the project root.

**If MASTER.md exists:**
- Read it — this is the source of truth
- Check for page-specific overrides in `design-system/pages/`
- Proceed to Step 2

**If MASTER.md does NOT exist:**
- Check if the ui-ux-pro-max-skill is installed:
  - Look for `.claude/skills/ui-ux-pro-max/` or check if the plugin is available
- If installed: "No design system found. Generate MASTER.md first? (yes/skip review)"
  - If yes: run the design system generator for this project
  - If skip: proceed with general best practices instead of a project-specific spec
- If NOT installed: "The ui-ux-pro-max design skill provides design intelligence
  for beautiful UIs. 87k+ stars, 247k+ installs. Install it? (yes/skip)"
  - Follow the capability-gaps protocol for installation

## Step 2 — Identify Files to Review

Determine what to review:
- If the user specified files/routes: review those
- If not: find recently changed frontend files:
  ```
  git diff --name-only HEAD~5 -- "*.tsx" "*.jsx" "*.css" "*.html" "*.vue" "*.svelte"
  ```
- If no recent changes: review the main UI entry points (layout, pages, components)

## Step 3 — Delegate to UI/UX Engineer

Delegate the review to the ui-ux-engineer subagent with this context:

"Review these frontend files for design quality:
 Files: {list of files}
 Design system: {MASTER.md path or 'none — use general best practices'}
 
 Check all categories: Design System Compliance, Accessibility,
 Responsiveness, Components, User Flow, Performance.
 
 Apply the anti-AI-slop rules strictly."

## Step 4 — Present Findings

Present the UI/UX Engineer's findings grouped by category:

```
━━━ UI/UX REVIEW ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Design System: {MASTER.md found / not found}
  Files reviewed: {count}

  DESIGN SYSTEM COMPLIANCE
  ────────────────────────
  {findings}

  ACCESSIBILITY
  ─────────────
  {findings}

  RESPONSIVENESS
  ──────────────
  {findings}

  COMPONENTS
  ──────────
  {findings}

  PERFORMANCE
  ───────────
  {findings}

  Summary: {count} issues found
    🔴 Broken: {count}
    🟠 Poor UX: {count}
    🟡 Improvement: {count}
    ℹ️  Suggestion: {count}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Step 5 — Offer Fixes

If issues were found:
"I can fix {N} of these issues directly. Fix them? (yes / pick individually / skip)"

For fixes, the Lead Engineer (main session) implements — the UI/UX Engineer
only reports findings. After fixes, re-run the review to verify.

## Pitfalls

- Reviewing without MASTER.md reduces findings to generic best practices
- Not checking accessibility (ARIA, contrast, keyboard nav) — this is mandatory
- Installing ui-ux-pro-max-skill without following capability-gaps protocol
- The Lead Engineer implements fixes, not the UI/UX Engineer

## Verification

- Findings are grouped by category (Design System, Accessibility, Responsiveness, etc.)
- Each finding has a severity level
- MASTER.md was consulted if it exists
- Anti-AI-slop rules were checked
