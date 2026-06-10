---
name: framework-check
description: |
  TRIGGER when: the user wants to verify the framework is working, says "check framework",
  "is everything installed", "framework health", or something seems broken with hooks,
  skills, agents, or rules. Also useful after updates or install.bat runs.
  DO NOT TRIGGER when: the user wants project status (/status), a security audit
  (/security-check), or to evaluate an external repo (/evaluate-repo).
disable-model-invocation: true
effort: low
user_locked: true
pinned: true
---

# Framework Health Check

## When to Use

When the user wants to verify the framework is installed correctly, after running
install.bat, or when something seems broken with hooks, skills, or agents.
Not for project status, security audits, or repo evaluation.

## Procedure

Validate that the entire framework is installed and working correctly.

## Step 1 — Check Global Files

Verify each file exists at the expected location (~/.claude/ or %USERPROFILE%\.claude\):

```
Checking global framework files...

  CLAUDE.md:           {EXISTS / MISSING}
  TEAM.md:             {EXISTS / MISSING}
  settings.json:       {EXISTS / MISSING}
```

## Step 2 — Check Skills

Verify each skill folder has a SKILL.md:

```
  Skills:
    init-project:      {EXISTS / MISSING}
    new-feature:       {EXISTS / MISSING}
    bug-fix:           {EXISTS / MISSING}
    wrap-up:           {EXISTS / MISSING}
    resume:            {EXISTS / MISSING}
    learn:             {EXISTS / MISSING}
    help:              {EXISTS / MISSING}
    document-all:      {EXISTS / MISSING}
    evaluate-repo:     {EXISTS / MISSING}
    security-check:    {EXISTS / MISSING}
    status:            {EXISTS / MISSING}
    framework-check:   {EXISTS / MISSING}
    constitution:      {EXISTS / MISSING}
    review-drift:      {EXISTS / MISSING}
    knowledge:         {EXISTS / MISSING}
    production-audit:  {EXISTS / MISSING}
    review-ui:         {EXISTS / MISSING}
    curate:            {EXISTS / MISSING}
    lock-skill:        {EXISTS / MISSING}
    unlock-skill:      {EXISTS / MISSING}
    pin-skill:         {EXISTS / MISSING}
    unpin-skill:       {EXISTS / MISSING}
```

## Step 3 — Check Agents

```
  Agents:
    code-reviewer:     {EXISTS / MISSING}
    test-engineer:     {EXISTS / MISSING}
    wiki-updater:      {EXISTS / MISSING}
    security-auditor:  {EXISTS / MISSING}
    knowledge-agent:   {EXISTS / MISSING}
    ui-ux-engineer:    {EXISTS / MISSING}
```

## Step 4 — Check Rules

```
  Rules:
    security.md:         {EXISTS / MISSING}
    capability-gaps.md:  {EXISTS / MISSING}
    skill-evolution.md:  {EXISTS / MISSING}
    config-protection.md:{EXISTS / MISSING}
    fact-forcing.md:     {EXISTS / MISSING}
```

## Step 5 — Check Hook Scripts

```
  Hooks:
    verify-before-stop.sh:  {EXISTS / MISSING}
    session-monitor.sh:     {EXISTS / MISSING}
    session-summary.sh:     {EXISTS / MISSING}
    session-start.sh:       {EXISTS / MISSING}
    loop-detector.sh:       {EXISTS / MISSING}
    bash-guard.sh:          {EXISTS / MISSING}
    bash-watchdog.sh:       {EXISTS / MISSING}
    session-logger.sh:      {EXISTS / MISSING}
    statusline.sh:          {EXISTS / MISSING}
    progress-monitor.sh:    {EXISTS / MISSING}
    pre-compact.sh:         {EXISTS / MISSING}
    timed-run.sh:           {EXISTS / MISSING}
    skill-telemetry.sh:     {EXISTS / MISSING}
```

## Step 5b — Check Telemetry

```
  Telemetry:
    logs/ directory:       {EXISTS / MISSING}
    skill-usage.log:       {EXISTS / MISSING}
```

## Step 6 — Check Project-Level Files (if in a project)

If the current directory has been initialized with /init-project:

```
  Project files:
    CLAUDE.md:                {EXISTS / MISSING}
    .claude/rules/debugging.md:  {EXISTS / MISSING}
    .claude/rules/testing.md:    {EXISTS / MISSING}
    .claude/skills/learned/:     {EXISTS / MISSING}
    wiki/:                       {EXISTS / MISSING}
    wiki/memory.md:              {EXISTS / MISSING}
    wiki/architecture.md:        {EXISTS / MISSING}
    wiki/logs/:                  {EXISTS / MISSING}
    .gitignore:                  {EXISTS / MISSING}
```

## Step 7 — Check Tool Dependencies

```
  Tools:
    git:       {AVAILABLE / MISSING — required}
    gh:        {AVAILABLE / MISSING — optional, for GitHub integration}
    jq:        {AVAILABLE / MISSING — required by hook scripts}
    graphify:  {AVAILABLE / MISSING — optional, for codebase mapping}
```

If jq is missing:
  "⚠️ jq is required by several hook scripts (bash-watchdog, session-logger).
   Install it: https://stedolan.github.io/jq/download/
   Without jq, some hooks will fail silently (they have error handling
   so they won't break Claude, but they won't work either)."

## Step 8 — Report

```
━━━ 🔧 FRAMEWORK HEALTH CHECK ━━━━━━━━━━━━━━━━━━━
  Framework version: {from settings.json}
  
  Global files:  {count OK} / {total} ✅
  Skills:        {count OK} / {total} ✅
  Agents:        {count OK} / {total} ✅
  Rules:         {count OK} / {total} ✅
  Hooks:         {count OK} / {total} ✅
  Project files: {count OK} / {total} ✅ (or "not in a project")
  Tools:         {count OK} / {total}
  
  {If everything passes}:
  ✅ Framework is healthy.
  
  {If anything is missing}:
  ⚠️ {count} issues found:
    - {file}: MISSING — reinstall with install.bat or create manually
    - {tool}: MISSING — {install instructions}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Pitfalls

- Checking file existence without verifying content — a file can exist but be empty or corrupted
- Not testing on Windows CMD — hooks use bash, which requires Git Bash on Windows
- Forgetting to check project-level files when inside a project directory

## Verification

- All global files checked and reported
- All skills, agents, rules, hooks validated
- Tool dependencies checked (git, bash, jq, graphify)
- Clear report with pass/fail for each component
