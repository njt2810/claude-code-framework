---
name: release
description: |
  TRIGGER when: the user wants to cut a release, bump version, generate a changelog,
  or tag a release. Often runs after multiple PRs have merged to main.
  DO NOT TRIGGER when: the user just wants to deploy (use /deploy), or has a
  bug fix to ship urgently (use /bug-fix then /deploy).
argument-hint: "[major|minor|patch] (default: auto from commits)"
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Release Management

## When to Use

When ready to cut a versioned release with changelog. For projects with
external consumers (clients, API users, internal teams) where version
visibility matters. Optional for personal/learning streams.

## Procedure

## Step 1 — Determine Bump Type

From `$ARGUMENTS`:
- `major` — breaking changes (X.0.0)
- `minor` — new features (0.X.0)
- `patch` — bug fixes only (0.0.X)
- empty — auto-detect from commits since last tag

Auto-detect rules (conventional commits):
- Any commit with `BREAKING CHANGE:` or `!:` → major
- Any commit starting with `feat:` → minor
- Otherwise → patch

## Step 2 — Determine Current Version

Find the current version from (in order):
- `package.json` → `version` field
- `pyproject.toml` → `[project].version`
- Latest git tag matching `v*`
- Default `0.0.0` if none

Compute next version per bump type.

## Step 3 — Generate Changelog

Find commits since last tag:
- `git log {last_tag}..HEAD --no-merges --format='%H|%s|%b' --reverse`

Group by conventional commit type:

```markdown
## {next_version} — {YYYY-MM-DD}

### Breaking Changes
- {description from BREAKING CHANGE: footer or !: subject}

### Features
- {feat: ... commits}

### Bug Fixes
- {fix: ... commits}

### Documentation
- {docs: ... commits}

### Internal
- {chore:, refactor:, test: ... commits}
```

Skip groups with no commits.

For each entry, link the PR if discoverable: `(#{PR_number})`.

## Step 4 — Update Files

1. **Version files**
   - `package.json` → bump version
   - `pyproject.toml` → bump version
   - `Cargo.toml` → bump version
   - Any other version source

2. **CHANGELOG.md**
   - Prepend the new section above any existing content
   - Keep the existing content intact

3. **Optional: git tag annotation**
   - Use the changelog section as the tag annotation

## Step 5 — Verify Tests & Build Pass

Before tagging, ensure:
- Tests pass
- Linter passes
- Build succeeds

If any fail: STOP. Don't release a broken commit.

## Step 6 — Commit, Tag, Push

```bash
git add CHANGELOG.md package.json {other-version-files}
git commit -m "chore(release): v{next_version}"
git tag -a "v{next_version}" -m "Release v{next_version}

{changelog-section}"
git push origin main
git push origin "v{next_version}"
```

## Step 7 — Create GitHub Release

```bash
gh release create "v{next_version}" \
  --title "v{next_version}" \
  --notes "{changelog-section}"
```

For pre-releases (e.g., `v1.2.0-beta.1`), add `--prerelease`.

## Step 8 — Report

```
Release Cut: v{next_version}

  Previous version: v{previous}
  Bump type:        {major|minor|patch} ({auto-detected | user-specified})
  Commits since:    {N}
  PRs included:     {N}

  Changelog:        CHANGELOG.md (top entry)
  Git tag:          v{next_version}
  GitHub release:   {URL}

Next steps:
  1. Run /deploy production to ship this version
  2. Notify affected stakeholders (clients, internal teams)
  3. Update documentation referencing the version
```

## Pitfalls

- Cutting a release without running tests — broken release in the wild
- Bumping major version casually — signals breaking changes that aren't
- Forgetting to push the tag — release exists locally only
- Auto-detecting bump from poorly-written commits — review the auto-detection
- Skipping CHANGELOG — consumers can't tell what changed
- Cutting releases too frequently — noise; batch related changes

## Verification

- Version bumped in all version source files
- CHANGELOG.md prepended with new section
- Git tag created and pushed
- GitHub Release created (if remote is GitHub)
- Tests passed before tag was created
- User knows next step (deploy)
