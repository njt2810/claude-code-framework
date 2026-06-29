# Change Management — Always Loaded

These rules enforce the SOC 2 / engineering hygiene baseline for code changes.
They apply to production streams (org1, org2, personal-with-production-flag).
Learning stream is exempt.

## Hard Rules

1. **No direct commits to main on production streams.** Every change goes
   through a feature/fix branch and a Pull Request.

2. **Every PR requires a reviewer.** The Code Reviewer agent counts as the
   reviewer when the user is solo. For team projects, also require a human
   reviewer per branch protection.

3. **CI must pass before merge.** Tests, lint, build, security scan. If any
   are failing on the PR, do NOT merge.

4. **Squash merge to main.** Keeps main history linear and readable.
   Use `gh pr merge {N} --squash --delete-branch`.

5. **Branch names must be descriptive.**
   - `feature/{kebab-case-name}` for features
   - `fix/{kebab-case-name}` for bug fixes
   - `chore/{kebab-case-name}` for housekeeping
   - `docs/{kebab-case-name}` for documentation-only changes

6. **No force-pushing to main, ever.** Force-pushing to a feature branch with
   an open PR is OK during review.

7. **No skipping CI gates.** Do not use `--no-verify`, do not edit CI to make
   it pass — fix the underlying issue.

## Deploy Discipline

8. **Production deploys require all gates.** /deploy enforces this — don't
   bypass via manual deploy commands.

9. **No Friday afternoon deploys to production.** Unless it's a critical fix.
   Reason: nobody around to investigate if it breaks.

10. **Every deploy is logged.** wiki/operations/deploy-log.md must be appended
    on every production deploy.

## When You See a Violation

If you see code being committed directly to main on a production project:
"⚠️ Direct commit to main detected. Production streams require PR workflow.
 Suggest: undo, create feature branch, open PR via /pr."

If you see a PR being merged with failing CI:
"⚠️ CI is failing. Merging would break main. Suggest: fix tests first, push
 to the PR branch, re-run CI."

If you see a deploy without gates:
"⚠️ Deploy without /deploy gates. Suggest: revert if not yet live, or
 retroactively run /compliance-status to assess."
