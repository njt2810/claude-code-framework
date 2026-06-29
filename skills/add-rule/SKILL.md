---
name: add-rule
description: |
  TRIGGER when: the user wants to add a project-scoped rule, capture a coding
  convention, document a pattern to enforce, or formalize a "we always do X" decision.
  DO NOT TRIGGER when: the user wants to add a GLOBAL rule (those go in
  ~/.claude/rules/ and require the skill-evolution protocol), or wants to
  change settings.json (different concern).
argument-hint: "[rule-name] (optional)"
disable-model-invocation: true
effort: low
user_locked: true
pinned: true
---

# Add Project Rule

## When to Use

When the project has a convention or guardrail that should be applied to
specific files (e.g., "all React components use Tailwind", "all Python tests
use pytest fixtures, never module-level state"). The rule lives at
`.claude/rules/{name}.md` and is auto-loaded by Claude when editing files
matching the glob.

## Lead Engineer Guidance — Why This Matters

The framework's GLOBAL rules (security, PII handling, etc.) apply everywhere.
Project rules apply only to this project. This keeps global rules clean while
allowing project-specific discipline.

**When to add a project rule:**
- You've corrected Claude twice for the same convention — formalize it
- A new pattern is introduced and you want it consistently applied
- Architectural decision (ADR) should also be enforced as a rule
- New team member onboarding — encode patterns so the framework teaches them

**When NOT to add a project rule:**
- One-off preference that doesn't generalize
- Something that should be in linter config instead (use the linter)
- Something that should be a comment on the code (use a comment)

## Procedure

## Step 1 — Determine Rule Name

If `$ARGUMENTS` given, use as rule name. Otherwise ask:
"What's the rule about? (one-line)"

Generate a kebab-case slug from the description.

## Step 2 — Determine Scope

Ask: "Where does this rule apply?"

Common scope patterns:
- All TypeScript files: `["**/*.ts", "**/*.tsx"]`
- React components only: `["**/components/**/*.tsx"]`
- Python tests: `["**/test_*.py", "**/*_test.py", "**/tests/**/*.py"]`
- API routes: `["**/api/**/*.ts", "**/routes/**/*.ts"]`
- Database migrations: `["**/migrations/*.sql", "**/db/migrations/**"]`
- All files: `["**/*"]` (rare — usually global is better)

Validate globs are well-formed.

## Step 3 — Capture the Rule

Ask for:
1. **Rule statement** — one or two sentences, declarative ("X must Y", "Never do Z")
2. **Reason** — why this rule exists (1-2 sentences)
3. **Example of compliance** — code snippet showing the right way
4. **Example of violation** — code snippet showing what to avoid
5. **Exception** — if any (otherwise "None")

## Step 4 — Write the Rule

Create `.claude/rules/{slug}.md`:

```markdown
---
name: {slug}
globs: {globs_array}
description: {one-line description}
---

# {Title}

## Rule

{Rule statement}

## Why

{Reason}

## Compliance Example

```{language}
{example}
```

## Violation Example

```{language}
{anti-example}
```

## Exceptions

{Exceptions or "None"}

## Related

- {Related ADR in wiki/decisions/, if any}
- {Related global rule in ~/.claude/rules/, if any}

---

Added: {YYYY-MM-DD}
Author: {user}
```

## Step 5 — Update Conventions Doc

Append to `wiki/conventions.md`:

```markdown
## Project Rules
- **{rule name}** (`.claude/rules/{slug}.md`) — {one-line description}
```

If `wiki/conventions.md` doesn't have a "Project Rules" section, create it.

## Step 6 — Report

```
Project rule added

  Name:        {slug}
  File:        .claude/rules/{slug}.md
  Scope:       {globs}
  Auto-loads:  when editing files matching the globs

Recommended next:
  - Skim existing code in scope — does it already comply?
  - If non-compliance found: file as a /feature add (chore type) for cleanup
  - When you edit a file in scope, this rule will be auto-loaded
  - To remove: delete .claude/rules/{slug}.md

Related skills:
  - /constitution — document architectural principles (broader than rules)
  - /document-all — sweep documentation including new rules
```

## Pitfalls

- Adding rules that contradict global rules — confusion. Check global rules first.
- Globs that match too broadly (`**/*`) — equivalent to global, defeats the point
- Skipping the "Why" section — future-you won't know why the rule exists
- Adding too many rules — every rule eats context every time it loads. Be selective.
- Adding a rule for something the linter already catches — duplicate enforcement

## Verification

- File written to `.claude/rules/{slug}.md` with valid frontmatter
- Globs are well-formed (no syntax errors)
- `wiki/conventions.md` updated with reference
- All four sections present (Rule, Why, Compliance, Violation)
