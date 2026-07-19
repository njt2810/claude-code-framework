---
name: framework-check
description: |
  TRIGGER when: the user wants to verify the framework is working, says "check framework",
  "is everything installed", "framework health", or something seems broken with hooks,
  skills, agents, or rules. Also useful after updates or install.bat runs.
  DO NOT TRIGGER when: the user wants project status (/status), a security audit
  (/security-check), or to evaluate an external repo (/evaluate-repo).
disable-model-invocation: true
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

Check that all 53 skill folders contain a SKILL.md. Use a glob over
`~/.claude/skills/*/SKILL.md` and verify the expected set:

Core:
  init-project, upgrade-project, note, new-feature, bug-fix, pr, wrap-up, resume,
  learn, help, document-all, evaluate-repo, status, framework-check,
  constitution, review-drift, knowledge

Audits & reviews:
  security-check, production-audit, review-ui

Curation:
  curate, lock-skill, unlock-skill, pin-skill, unpin-skill

Lifecycle & coaching:
  feature, recommend, add-rule, onboard-client

Engineering hygiene:
  migration, api-contract

Production setup:
  env-setup, observability-setup, audit-logging-setup, auth-setup,
  billing-setup, email-setup, dr-plan

Operations:
  deploy, release, feature-flag, incident, triage, timer

Compliance (production streams):
  compliance-audit, compliance-status, data-inventory,
  legal-docs, vendor-review

Safety modes:
  careful, guard, freeze, unfreeze

Report any missing as `MISSING — run install.bat to restore`.

## Step 3 — Check Agents

```
  Agents (7 total — 6 always-on + 1 on-demand):
    code-reviewer.md:      {EXISTS / MISSING}
    test-engineer.md:      {EXISTS / MISSING}
    wiki-updater.md:       {EXISTS / MISSING}
    security-auditor.md:   {EXISTS / MISSING}
    knowledge-agent.md:    {EXISTS / MISSING}
    compliance-officer.md: {EXISTS / MISSING}  (production)
    ui-ux-engineer.md:     {EXISTS / MISSING}  (on-demand)
```

## Step 4 — Check Rules

```
  Rules (10 total):
    security.md:          {EXISTS / MISSING}
    capability-gaps.md:   {EXISTS / MISSING}
    skill-evolution.md:   {EXISTS / MISSING}
    config-protection.md: {EXISTS / MISSING}
    fact-forcing.md:      {EXISTS / MISSING}
    pii-handling.md:      {EXISTS / MISSING}
    change-management.md: {EXISTS / MISSING}
    secrets-management.md:{EXISTS / MISSING}
    audit-everything.md:  {EXISTS / MISSING}
    safety-modes.md:      {EXISTS / MISSING}
```

## Step 5 — Check Hook Scripts

```
  Hooks (12 scripts):
    verify-before-stop.sh:  {EXISTS / MISSING}
    session-monitor.sh:     {EXISTS / MISSING}
    session-summary.sh:     {EXISTS / MISSING}
    session-start.sh:       {EXISTS / MISSING}
    loop-detector.sh:       {EXISTS / MISSING}
    bash-guard.sh:          {EXISTS / MISSING}
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
  Project files (base):
    CLAUDE.md:                   {EXISTS / MISSING}
    TEAM.md:                     {EXISTS / MISSING}
    .claude/agents/:             {EXISTS / MISSING}
    .claude/rules/debugging.md:  {EXISTS / MISSING}
    .claude/rules/testing.md:    {EXISTS / MISSING}
    .claude/skills/learned/:     {EXISTS / MISSING}
    .claude/state/mode.json:     {OPTIONAL — present only if mode != normal}
    wiki/:                       {EXISTS / MISSING}
    wiki/memory.md:              {EXISTS / MISSING}
    wiki/architecture.md:        {EXISTS / MISSING}
    wiki/logs/:                  {EXISTS / MISSING}
    wiki/features/:              {EXISTS / MISSING}  (lifecycle tracking)
    .gitignore:                  {EXISTS / MISSING}
```

If production scope is enabled (read from CLAUDE.md or /init-project output):

```
  Production-scope files:
    .claude/agents/compliance-officer.md:    {EXISTS / MISSING}
    wiki/compliance/:                        {EXISTS / MISSING}
    wiki/compliance/gaps.md:                 {EXISTS / MISSING}
    wiki/compliance/data-inventory.md:       {EXISTS / MISSING}
    wiki/compliance/vendor-register.md:      {EXISTS / MISSING}
    wiki/compliance/evidence-index.md:       {EXISTS / MISSING}
    wiki/compliance/policies/:               {EXISTS — 10 policies / MISSING}
    wiki/legal/:                             {EXISTS / MISSING}
    wiki/operations/:                        {EXISTS / MISSING}
    .env.development.example:                {EXISTS / MISSING}
    .env.staging.example:                    {EXISTS / MISSING}
    .env.production.example:                 {EXISTS / MISSING}
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
  Framework version: {from ~/.claude/VERSION}
  
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
