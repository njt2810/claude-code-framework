---
name: new-feature
description: |
  TRIGGER when: the user wants to build something new — a feature, enhancement, user story,
  or says build, create, add, implement, start working on.
  DO NOT TRIGGER when: the user is fixing a bug (/bug-fix), setting up a project (/init-project),
  evaluating a repo (/evaluate-repo), or doing documentation (/document-all).
disable-model-invocation: true
effort: high
user_locked: true
pinned: true
---

# New Feature Workflow

## When to Use

When the user wants to build something new — a feature, enhancement, or user story.
Not for bug fixes, project setup, documentation, or security audits.

## Procedure

Follow these steps in order. Do not skip steps.
Wait for human approval at gates marked with GATE.

## Step 1 — Research (use a subagent to keep main context clean)

Before writing any code:

1. Read graphify-out/GRAPH_REPORT.md to understand the current codebase structure
2. Read wiki/architecture.md and wiki/conventions.md
3. Read wiki/memory.md for accumulated project knowledge
4. Check wiki/decisions/ for past decisions that may be relevant
5. Check .claude/skills/learned/ for any skills relevant to this task

Summarize what you found:
"Current codebase: {summary}
 Relevant patterns: {any learned skills or conventions}
 Potential conflicts: {anything this feature might affect}"

Then ask: "What feature are you building?"

## Step 2 — Spec (GATE)

Based on the user's description and your research:

1. Write a clear spec covering:
   - **Feature:** what it is (one sentence)
   - **Goal:** what problem it solves
   - **Inputs:** what it needs
   - **Outputs:** what it produces
   - **Constraints:** technical limitations, dependencies, edge cases
   - **Success criteria:** how we know it's done and working

2. Present the spec to the user
3. Save to wiki/decisions/{feature-name}.md when approved

GATE — Wait for approval before proceeding. Accept modifications.

## Step 3 — Clarify

Before planning, surface assumptions and unknowns:

1. Review the approved spec and list every assumption you're making
2. Identify open questions — things the spec doesn't answer:
   - Edge cases: what happens when input is empty, huge, malformed?
   - Error handling: what fails gracefully vs hard-fails?
   - Scope boundaries: what's explicitly NOT included?
   - Integration points: what existing code does this touch?
3. If constitution.md exists, check the spec against project principles.
   Flag any tensions: "The spec calls for {X} but the constitution says {Y}."

Present your findings:
```
ASSUMPTIONS (things I'll treat as true unless you say otherwise):
  1. {assumption}
  2. {assumption}

OPEN QUESTIONS (need your input before I plan):
  1. {question} — affects: {what changes depending on the answer}
  2. {question} — affects: {what changes depending on the answer}

SCOPE BOUNDARY (explicitly NOT doing):
  - {exclusion}
```

GATE — Wait for answers before proceeding. If there are no open questions,
state "No open questions — ready to plan" and move to the next step.

## Step 4 — Checklist

Build a verification checklist from the spec and clarifications:

1. Turn each success criterion into a testable check
2. Add edge cases from the Clarify step
3. Add constitution checks if constitution.md exists
4. Add integration checks for any existing code this touches

```
DONE-WHEN CHECKLIST:
  [ ] {criterion from spec — how to verify}
  [ ] {edge case — how to verify}
  [ ] {constitution alignment — how to verify}
  [ ] {integration — how to verify}
```

This checklist will be used in Step 7 (Review) to verify the feature.
No gate — proceed to planning.

## Step 5 — Plan (GATE)

Break the spec into implementation tasks:

1. Number each task (Task 1/N, Task 2/N, etc.)
2. Each task should be a single, testable slice of work
3. Include a test task after every 2-3 implementation tasks
4. Keep tasks small — if a task description is more than 2 sentences, split it
5. Order tasks so each builds on the previous (no jumping ahead)

Present the plan. GATE — Wait for approval.

## Step 6 — Build

For each task in the plan:

1. Announce: "Starting Task {X}/{N}: {description}..."
2. Implement the task
3. If the task involves new logic, write a test for it
4. Run tests after completion: announce "Tests: {pass count} passing, {fail count} failing"
5. Commit with a descriptive message: `feat: {what was done}`
6. Announce: "Task {X}/{N} complete"

During building:
- Follow any scoped rules that apply (debugging.md, testing.md)
- If you hit a problem, follow the evidence-based debugging approach
- If you need a tool or library not installed, stop and explain what you need (capability-gaps protocol)
- Never make changes outside the scope of the current task
- For long-running commands (npm install, builds, etc.), use run_in_background and report progress

## Step 7 — Review

After all tasks complete:

1. Run through the DONE-WHEN CHECKLIST from Step 4.
   Mark each item pass/fail. If any fail, fix before proceeding.

2. Delegate to the code-reviewer subagent:
   "Review all changes made in this session. Check for:
   security vulnerabilities, error handling gaps, complexity
   that could be simplified, and test coverage for new code paths."

3. If the feature touches auth, payments, user data, or external APIs:
   Delegate to the security-auditor subagent.

4. Address all findings before proceeding.
   If a finding requires code changes, follow the same build pattern
   (implement, test, commit).

## Step 8 — Document

Delegate to the wiki-updater subagent:

"Update project documentation for the new feature:
 - wiki/architecture.md if system design changed
 - wiki/conventions.md if new patterns were introduced
 - wiki/memory.md with any knowledge gained
 Keep updates concise — facts, not essays."

## Step 9 — Ship

1. Ensure all tests pass (full suite, not just new tests)
2. Ensure linting passes (if configured)
3. Create a final commit if any documentation was updated
4. If CI/CD is configured, push and verify the pipeline passes
5. Summarize what was built:

```
Feature complete: {feature name}
   Tasks completed: {N}
   Tests: {pass count} passing
   Files changed: {count}
   New files: {count}
```

## Pitfalls

- Skipping the Clarify step leads to mid-build surprises and rework
- Skipping the Checklist means no clear "done" criteria — scope creep follows
- Building before the plan is approved wastes time if the user wants a different approach
- Not running the full test suite after each slice lets regressions accumulate
- Forgetting to delegate to Security Auditor when the feature handles user input or auth

## Verification

- All DONE-WHEN checklist items from Step 4 pass
- Code Reviewer found no CRITICAL or HIGH issues
- Security Auditor approved (if feature touches auth/payments/user data/APIs)
- Wiki updated with architecture and convention changes
- Full test suite passes with no new failures
- All tasks committed with descriptive messages
