---
name: pr
description: |
  TRIGGER when: the user wants to open a pull request, ship a feature branch,
  create a PR, push to GitHub for review, or finalize work on a branch.
  DO NOT TRIGGER when: the user is on the main/master branch (no PR possible),
  the user hasn't committed their changes yet (push has nothing to publish),
  or the user just wants to push without a PR (use plain git push).
argument-hint: "[reviewer-username] (optional)"
disable-model-invocation: true
user_locked: true
pinned: true
---

# Open Pull Request

## When to Use

When the user is on a feature or fix branch and wants to push it and open a PR
on GitHub. Standard outcome of `/new-feature` and `/bug-fix` workflows.

## Procedure

## Step 1 — Pre-PR Checks

Before pushing, verify the branch is ready:

1. **Check current branch**
   - Run: `git rev-parse --abbrev-ref HEAD`
   - If on `main` or `master`: STOP. Say "You're on the main branch — no PR can be opened. Did you forget to create a feature branch?"

2. **Check for uncommitted changes**
   - Run: `git status --porcelain`
   - If output is non-empty: ask "You have uncommitted changes. Commit them before opening the PR? (yes/no)"

3. **Check there are commits ahead of main**
   - Run: `git log main..HEAD --oneline` (or `master..HEAD`)
   - If empty: STOP. Say "No commits on this branch beyond main — nothing to PR."

4. **Run the full test suite**
   - Detect test command from package.json / pyproject.toml / etc.
   - Run with timeout 600000ms
   - If tests fail: report the failures and ask "Tests are failing. Fix before PR, or open as draft? (fix/draft/cancel)"

5. **Run the linter** (if configured)
   - If errors: report and ask "Linter has errors. Fix before PR? (yes/no)"

6. **Scan for debug code and secrets**
   - Grep for: `console.log`, `print(`, `debugger`, `TODO HACK`, `FIXME URGENT`
   - Grep for likely secrets: API keys, tokens, passwords
   - If found: list them and ask "Found potential debug/secret code. Review before PR? (yes/no)"

## Step 2 — Push Branch

1. Push the current branch with upstream tracking:
   - `git push -u origin {current_branch}`
2. Report: "Branch pushed: {branch_name}"

## Step 3 — Build PR Description

Build the PR body from these sources (in order of priority):

1. **Feature spec** if it exists at `wiki/decisions/{branch_name}.md` or `wiki/decisions/{feature-name}.md`
2. **Bug description** if this is a fix branch — pull from the first commit message
3. **Commits on the branch** — `git log main..HEAD --format='- %s'`

Format the PR body as:

```markdown
## Summary
{One-paragraph summary derived from spec or commits}

## Changes
{Bulleted list of commits since main}

## Test Plan
- [ ] Tests pass locally
- [ ] Linter passes
- [ ] {Each DONE-WHEN checklist item from the spec, if available}
- [ ] Manual smoke test in the local dev environment

## Spec
{Link to wiki/decisions/{name}.md if it exists}

## Notes for Reviewer
{Anything specific the reviewer should pay attention to}

🤖 Generated with Claude Code Framework
```

## Step 4 — Create PR

1. Detect base branch (usually `main`, fall back to `master`):
   - `git remote show origin | grep 'HEAD branch'` → that's the base

2. Build PR title from the most descriptive commit or the feature spec name:
   - For features: `feat: {feature name}`
   - For bug fixes: `fix: {bug description}`
   - Keep under 70 characters

3. Create the PR using `gh pr create`:
   ```
   gh pr create \
     --base {base_branch} \
     --head {current_branch} \
     --title "{title}" \
     --body "$(cat <<'EOF'
   {body from Step 3}
   EOF
   )"
   ```

4. If a reviewer username was passed as argument:
   - Add: `--reviewer {username}`

5. Capture the PR URL from output

## Step 5 — Delegate to Code Reviewer

Delegate to the Code Reviewer subagent:

"A new PR has been opened: {PR_URL}.
Review the changes in branch {branch_name} (diff against {base_branch}).
Check for: security vulnerabilities, error handling gaps, complexity that
could be simplified, test coverage for new code paths, and any code that
doesn't match project conventions in wiki/conventions.md.

Post your findings as a structured report. Do NOT comment on the PR directly —
the Lead Engineer will translate your findings for the user."

## Step 6 — Report

Output:

```
PR opened: {PR_URL}
Branch:    {branch_name}
Base:      {base_branch}
Commits:   {N} commits ahead of {base_branch}
Files:     {file_count} changed
Reviewer:  {Code Reviewer findings being prepared}

Next steps:
  1. Wait for Code Reviewer findings (delegating now)
  2. Address findings → push fixes to the same branch
  3. When ready: merge via `gh pr merge --squash --delete-branch`
```

## Pitfalls

- Pushing to main directly bypasses this entire workflow — main should have branch protection
- Forgetting to run tests before PR means broken PRs that waste reviewer time
- Auto-creating PRs without a spec means the PR description is just "added thing" — useless for reviewers
- Not delegating to Code Reviewer after PR creation skips the quality gate
- Force-pushing to a PR branch is OK during review, but never force-push to main

## Verification

- PR URL is returned and accessible
- All tests passed before push
- Linter passed before push
- PR description includes spec link or generated summary from commits
- Code Reviewer has been delegated to and is preparing findings
