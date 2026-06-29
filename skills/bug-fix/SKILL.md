---
name: bug-fix
description: |
  TRIGGER when: the user reports a bug, error, crash, defect, unexpected behavior,
  or says something is broken, not working, failing, or wrong.
  DO NOT TRIGGER when: the user wants to add new functionality (/new-feature),
  refactor existing code, improve performance, or do cleanup. Those are /new-feature tasks.
disable-model-invocation: true
effort: high
user_locked: true
pinned: true
hooks:
  PostToolUse:
    - matcher: "Edit|Write|MultiEdit"
      hooks:
        - type: command
          command: "bash ~/.claude/hooks/scripts/loop-detector.sh"
---

# Evidence-Based Bug Fix Workflow

## When to Use

When the user reports a bug, error, crash, or unexpected behavior.
Not for new features, refactoring, performance improvements, or cleanup.

## Procedure

This workflow prevents the fix-break death spiral.
Follow every step. Do not skip steps. Do not shortcut.

## Step 0 — Create Fix Branch

Before any investigation or code changes:

1. Check current branch: `git rev-parse --abbrev-ref HEAD`
2. If on `main`/`master`: branch from here
3. If on another branch: ask "You're on branch {X}. Branch from main instead? (yes/no)"
4. Generate a short, descriptive branch name from the bug:
   - Format: `fix/{kebab-case-bug-description}`
   - Example: `fix/login-timeout-on-slow-network`
5. Create and switch: `git checkout -b fix/{name}`
6. Announce: "Fix branch created: fix/{name}. All work happens here, including the failing test."

For trunk-based projects (single main branch, no PR workflow), skip branch creation
and work on main. Detect from wiki/conventions.md or ask the user.

## Step 1 — UNDERSTAND (do not write any code yet)

1. Read the error message, log output, or bug description
2. Read graphify-out/GRAPH_REPORT.md to understand which files are connected
3. Identify the SPECIFIC file and line where the error occurs
4. Read that file and understand the relevant code path
5. Check wiki/memory.md — has this type of bug been seen before?
6. Check .claude/skills/learned/ — is there a skill for this type of issue?

State your hypothesis clearly:
"I believe the bug is caused by {X} because {evidence from code/logs/errors}"

## Step 2 — REPRODUCE

Run the failing test, command, or action that shows the bug.
Show the ACTUAL output — not a description, the real output.

If you CANNOT reproduce the bug:
```
STOP. Say:
"I cannot reproduce this bug with the information available.
 To investigate further, I need:
 - {specific question 1}
 - {specific question 2}
 Can you provide more details?"
```
Do NOT proceed to fixing without reproduction.

## Step 3 — PROVE (write a failing test FIRST)

1. Write a test that captures the exact bug behavior
2. Run the test
3. Confirm it FAILS
4. Show the failing output

If the test PASSES:
```
STOP. Your understanding of the bug is wrong.
Say: "My test passed, which means my hypothesis about the cause
is incorrect. Let me re-examine the code."
Go back to Step 1 with a different hypothesis.
```

Do NOT proceed to fixing until you have a failing test.

## Step 4 — FIX (minimal change only)

1. Make the SMALLEST possible change to fix the bug
2. Change ONE thing only
3. Do NOT refactor surrounding code
4. Do NOT fix other issues you noticed (note them for later)
5. Do NOT make multiple changes at once

## Step 5 — VERIFY

1. Run the specific test from Step 3
   - It MUST PASS now
   - If it still fails: go to Step 6 (attempt tracking)

2. Run the FULL test suite
   - No new failures allowed
   - If new failures appear: REVERT your change immediately
     `git checkout -- {file}` and go to Step 6

3. Only after both checks pass, announce:
   "Bug fixed and verified.
    - Failing test now passes
    - Full test suite: {count} passing, 0 new failures
    - Change: {one-sentence description of what was changed}"

## Step 6 — ATTEMPT TRACKING

Track your fix attempts:

After attempt 1 fails:
"Attempt 1 failed: tried {what}, result was {what happened}.
 Trying a different approach."
 Go back to Step 4 with a DIFFERENT strategy.

After attempt 2 fails:
```
STOP EVERYTHING. Do not make a third attempt.

Say:
"I've tried two approaches and neither worked.

 Attempt 1: {what I tried} → {why it failed}
 Attempt 2: {what I tried} → {why it failed}

 I recommend:
   Option A: {fundamentally different strategy}
   Option B: {fundamentally different strategy}
   Option C: /rewind to before my first attempt and start fresh

 Which approach would you like me to try?"
```

Wait for the user to choose. Do NOT continue fixing on your own.

## Step 7 — REWIND RECOVERY

If the user says /rewind or asks to start fresh:
1. Use /rewind to restore to before the failed fix attempts
2. This removes failed approaches from context (prevents pollution)
3. Start over at Step 1 with fresh context and a new hypothesis

## Step 8 — DOCUMENT & OPEN PR

After the fix is verified:
1. Commit on the fix branch: `fix: {description of the bug and fix}`
2. Invoke the `/pr` skill to:
   - Push the fix branch
   - Create a PR with the bug description and the test that proves the fix
   - Delegate to Code Reviewer
3. If this was a non-obvious bug, consider capturing the pattern:
   "This was a non-obvious bug. Worth capturing the debugging pattern? (/learn)"
4. If the bug reveals a design flaw, note it:
   "This bug suggests {design issue}. Consider an ADR in wiki/decisions/."

For trunk-based projects, push directly to main and skip the PR step.

## Step 9 — MERGE & CLEANUP

After PR is approved and CI green:

1. Squash merge: `gh pr merge {PR_number} --squash --delete-branch`
2. Switch back to main: `git checkout main && git pull`
3. Announce: "Fix merged to main. Bug closed."

## Red Flags — STOP immediately if any of these occur:

- You're editing the same file for the 3rd time for the same bug
- You're fixing something your previous fix just broke
- You can't explain WHY your fix works, only that it "should" work
- The test suite has more failures after your fix than before
- You find yourself saying "this should work" without evidence

When a red flag occurs:
```
"Red flag: {which one}
 Stopping to reassess. Current state:
 - What I've tried: {list}
 - What's broken: {current symptoms}
 - My best theory: {hypothesis}

 Recommend: /rewind and try {alternative approach}
 Or: explain what you'd like me to do differently."
```

## NEVER:
- Say "I've fixed it" without showing PASSING test output
- Edit code that isn't related to the bug
- Theorize about the cause without reading the actual error first
- Make multiple changes at once — one change, one test, one verification
- Silently retry a failed approach — always report what happened

## Pitfalls

- Editing the same file 3+ times for one bug is the loop pattern — stop and reassess
- Skipping the failing test (Step 3) means you can't prove the fix works
- Making multiple changes at once makes it impossible to know which one fixed it
- Fixing something your previous fix just broke is the death spiral — /rewind immediately
- Saying "this should work" without evidence — that's a guess, not a fix

## Verification

- The failing test from Step 3 now passes
- The full test suite has no new failures
- Only one thing was changed (minimal fix)
- The fix was committed on the fix branch (not main)
- PR opened with the failing-test-now-passes as the proof
- Code Reviewer approved the fix on the PR
- After merge: branch deleted, main pulled, working tree clean
