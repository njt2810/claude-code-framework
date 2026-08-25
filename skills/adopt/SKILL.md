---
name: adopt
description: |
  TRIGGER when: the user wants to start a new project, bring an existing project under management,
  or says adopt, init, initialize, setup project, start project, new project, bootstrap.
  DO NOT TRIGGER when: the user wants to start building a feature (/new-feature), fix a bug (/bug-fix),
  or resume work (/resume). This is for project SETUP only.
argument-hint: [realm-key] (optional — overrides auto-detection)
disable-model-invocation: true
user_locked: true
pinned: true
---

# Adopt — Realm-Aware Project Bootstrap

## When to Use

When the user wants to start a new project or bring an existing project under
management. Not for starting a feature, fixing a bug, or resuming work.

`/adopt` replaces `/init-project`. The behavioral difference: realm identity
and rules (persona, delegation style, production-tier status) are resolved
automatically from `~/.claude/realms.json` and the realm's own `CLAUDE.md` —
via Claude Code's native `CLAUDE.md` ancestor-directory-walk — instead of
being typed in as a `[stream]` argument and duplicated into per-project
copies. `/adopt` never copies agent definitions, `TEAM.md`, or realm
identity/rules into the project — the global `~/.claude/agents/` and the
realm-root `CLAUDE.md` already cover every project underneath them
automatically. Everything else `/init-project` did (GitHub repo creation,
security audit, CI/CD setup, wiki/knowledge scaffolding, and — for
production-tier realms — branch protection, compliance/legal doc drafts,
audit-logging scaffolding, environment separation) still happens; only how
production-tier status and org/GitHub info get determined has changed.

## Procedure

### Step 1 — Resolve Realm

If `$ARGUMENTS` was given (a `[realm-key]` argument — see frontmatter), it
**overrides auto-detection entirely**: look it up directly in
`~/.claude/realms.json` by key.
- Key found → use that realm, skip the prefix-match below. If cwd isn't
  actually under that realm's registered root, say so explicitly ("Note:
  this project is outside {realm-key}'s registered path {root} — proceeding
  anyway since you named it directly") rather than silently proceeding as if
  nothing's unusual.
- Key not found in `realms.json` (or `realms.json` doesn't exist) → say so
  plainly: "No realm named '{key}' in realms.json{ — or realms.json doesn't
  exist yet}." and fall through to auto-detection below rather than failing
  outright — the argument was an override attempt, not a hard requirement.

Otherwise (no argument given), auto-detect: read `~/.claude/realms.json` if
it exists (JSON map of `realm-key` → absolute realm-root path; see
`realms.json.example` for the format).

- **If it doesn't exist**: note that the realm system isn't configured on
  this install yet. Treat this adoption as a one-off (skip to the one-off
  branch below) — don't block on it, `/adopt` still works without it.
- **If it exists**: prefix-match the current working directory against every
  registered realm root. Longest match wins.
  - **Match found**: proceed silently, no question asked. Read the matched
    realm root's `AGENTS.md` and `CLAUDE.md` (see Step 1a below) to resolve
    GitHub org and production-tier status.
  - **No match**: ask once, listing the actual realms found in `realms.json`
    by key: "Which realm is this project for? {list of realm keys from
    realms.json} — or 'one-off, not part of a realm'?" If the user names an
    existing realm, treat it as a match (even though the path didn't prefix
    correctly — flag this to the user, since it may mean the project lives
    outside its realm's expected folder tree). If "one-off", proceed to the
    one-off branch.

**One-off branch** (no `realms.json`, or the user explicitly says this
project isn't part of any realm): no realm-level identity/rules apply beyond
the global default. Ask for a GitHub destination (personal account, or an
org name) instead of reading one from a realm's `AGENTS.md`. Production-tier
status is decided per Step 2's self-declare path — never assumed ON.

#### Step 1a — Read Realm Configuration (when a realm matched)

From the matched realm root:
- Read `AGENTS.md` for a `GitHub org: github.com/{org}` line (or similar) —
  this is the GitHub destination for repo creation in Step 3.1. If absent,
  ask once rather than guessing.
- Read `CLAUDE.md` for a production-tier declaration (a line stating this
  realm is production-tier, however the realm author phrased it — look for
  "production-tier" / "production tier" language). Presence → production
  scope ON for every project under this realm, no prompt. Absence → OFF by
  default, but Step 2's self-declare escape hatch still applies per-project.
- Check whether `<realm-root>/.realm-skills/` exists and has any skill
  folders — feeds Step 3.5's realm-skill sync.

Do **not** copy anything from the realm root into the project. This step is
read-only — the realm's `CLAUDE.md`/`AGENTS.md` stay exactly where they are
and keep governing the project automatically via the ancestor-walk; nothing
needs to be duplicated for that to work.

### Step 2 — Production Scope

Production scope adds real infrastructure on top of the base setup: branch
protection, Compliance Officer agent delegation, compliance/legal doc
scaffolding, security policies, an audit-logging stub, and environment
separation (`.env.{development,staging,production}.example`).

**Decision logic:**
- Realm resolved AND its `CLAUDE.md` declares production-tier (Step 1a) →
  **ON**, no prompt.
- Realm resolved, no declaration → **OFF by default**. Ask: "This project's
  realm isn't declared production-tier. Enable production scope for this
  project specifically anyway? This adds compliance docs, security
  policies, branch protection, and audit logging. Recommended when shipping
  to real users. (yes/no)" A yes here is a per-project self-declaration —
  it doesn't change the realm's own status.
- One-off (no realm) → same self-declare question as above.

Whatever this resolves to gets written once into the project's own
`CLAUDE.md` as `Production-tier: yes` or `Production-tier: no` (see the
template in Step 3.2) — the single source of truth every downstream
consumer (statusline, `/wrap-up`, `/status`) reads, so nothing needs to
re-resolve the realm chain itself.

Steps below that depend on production scope are marked `(production)`.

### Step 3 — Automated Setup

CRITICAL: Never overwrite existing files. Only create what's MISSING.
For existing files, offer to ENHANCE (append framework pointers) with approval.

Execute these steps, skipping any that are already present:

#### 3.0 — Already Adopted? (idempotency)

Before anything else, check `.claude/framework-version`. If it exists and
matches (or is newer than) the currently installed `~/.claude/VERSION`,
report: "Already adopted (framework {version}). Nothing to do." and stop —
unless the user explicitly wants to re-run setup. If it exists but is
*older*, say: "This project was initialized with an older framework version
({old} vs {new}). Run /upgrade-project instead — it assesses what changed,
archives outdated files (never deletes), and applies updates with your
approval." Then stop.

#### 3.0b — Setup Depth

Ask (skip if answer is obvious from context, e.g. an existing populated repo
clearly isn't a throwaway experiment): "Full setup (git, GitHub repo, CI/CD,
security audit, full wiki scaffolding) or minimal (just `CLAUDE.md` +
`.claude/skills/learned/` + a bare `wiki/` — for a quick experiment you may
throw away)?" Minimal setup skips Steps 3.1 (GitHub repo creation, though
still runs local `git init`), 3.3 (scoped rules — an experiment doesn't need
`debugging.md`/`testing.md` glob rules any more than it needs CI), 3.9
(security audit), 3.10 (CI/CD), and all production-scope steps regardless of
Step 2's answer — an experiment isn't where you want SOC 2 scaffolding.
Everything else in this section assumes
full setup; minimal-setup skips are called out inline where relevant.

#### 3.1 Git Initialization
- If `.git/` missing: `git init`
- Full setup, not one-off with a name conflict: check if `gh` CLI is
  available
  - If `gh` available: create a private repo under the resolved GitHub
    destination (the realm's org from Step 1a, or the one-off answer):
    `gh repo create {org-or-account}/{project_name} --private`
  - If `gh` not available: say "GitHub CLI (gh) is not installed. I can
    help you install it later, or you can create the repo manually on
    github.com. Continuing without GitHub integration."
- Minimal setup: local `git init` only, skip GitHub entirely

#### 3.2 CLAUDE.md
- If MISSING: generate from the template below
- If EXISTS: ask "Your CLAUDE.md exists. I'd like to add framework routing
  pointers (about 10 lines). These help me find rules, skills, and
  documentation faster. Add them? (yes/no)"

CLAUDE.md template (adapt based on detected stack; keep it short — identity,
delegation style, and the always-loaded rules are already inherited
automatically from the realm root and global `~/.claude/`, so this file
should NOT restate them — restating invites the exact drift this framework
exists to prevent). Two fields the old `/init-project` template had are
deliberately gone, not just forgotten: an Obsidian wiki path (superseded —
wiki content lives in this project's own `wiki/`, and a realm's shared docs
belong in the realm root, not duplicated per-project) and a cost-dashboard
path (superseded by `/wrap-up`'s per-project opt-in cost tracking, Step 9 —
there's no longer a stream-level flag to derive a dashboard path from):

```markdown
# {Project Name}

{One-line description}

## Stack
{Auto-detected or provided: language, framework, key dependencies}

## Commands
{Auto-detected from package.json scripts or common patterns}
- Dev: {detected or "to be configured"}
- Test: {detected or "to be configured"}
- Build: {detected or "to be configured"}
- Lint: {detected or "to be configured"}

## Project Context
{If a realm resolved}: Realm: {realm-key} (see the realm root's CLAUDE.md
for identity/rules — inherited automatically, not restated here).
{If one-off}: Not part of a registered realm — global defaults apply.
Production-tier: {yes/no} — resolved once at adopt time from
{"the realm's CLAUDE.md declaration" / "a self-declaration for this project"
/ "no declaration, defaults to no"}. Machine-readable for tooling (e.g. the
statusline) — re-run `/adopt` or edit this line directly if it ever needs to
change; nothing re-resolves it automatically after this point.

## Documentation
- Architecture and system design: wiki/architecture.md
- Code patterns and conventions: wiki/conventions.md
- Past decisions: wiki/decisions/
- Accumulated project knowledge: wiki/memory.md
```

#### 3.3 Rules (scoped)
Create `.claude/rules/` if missing. Create each file only if it doesn't exist:

**debugging.md** (scoped to source files):
```yaml
---
globs: ["*.py", "*.js", "*.ts", "*.jsx", "*.tsx"]
---
```
Then the evidence-based debugging rules (Three Laws: prove first, failing test before fix, two-attempt limit).

**testing.md** (scoped to test files):
```yaml
---
globs: ["*test*", "*spec*", "*.test.*", "*.spec.*"]
---
```
Then the testing standards.

#### 3.4 Skills
- Create `.claude/skills/learned/` directory if missing (for the learning system)
- Preserve any existing skills — do NOT modify or delete them

#### 3.4b Version Stamp
- Write the installed framework version (from `~/.claude/VERSION`) to
  `.claude/framework-version` — this is what lets `/upgrade-project` (and
  Step 3.0's idempotency check) know what the project was adopted with

#### 3.5 Realm-Skill Sync (only if a realm resolved with `.realm-skills/`)

If Step 1a found skills under `<realm-root>/.realm-skills/`, offer to copy
each one into this project's `.claude/skills/`, logged with source path and
timestamp in the final report — never silent, never automatic.

#### 3.6 Skill Discovery (from Community Catalog)

Determine the project stack from one of two sources:
- EXISTING PROJECT: auto-detect from files present (`.py`, `.js`/`.ts`,
  `.jsx`/`.tsx`, `package.json`, `requirements.txt`, etc.)
- NEW/EMPTY PROJECT: ask "What will you be building this with? For example:
  a Python script, a website (React/Next.js/HTML), browser automation, a
  data pipeline, an API, or not sure yet." Store the answer as the intended
  stack.

If no stack is known (user said "not sure yet"), skip skill discovery and
say: "Once you start building, I'll recommend relevant skills from the
community catalog as needed."

Check if the community skill catalog is available locally at
`~/.claude/skill-catalog/awesome-agent-skills/`:

If NOT cloned yet:
  "The community skill catalog has 1,000+ skills from Anthropic, Google,
   Vercel, Stripe, and the developer community. It helps me find the right
   tools for your specific project.

   Repository: github.com/VoltAgent/awesome-agent-skills
   One-time download (~50MB). Clone it? (yes/no)"

   If yes: `git clone https://github.com/VoltAgent/awesome-agent-skills.git ~/.claude/skill-catalog/awesome-agent-skills`

If the catalog exists and a stack is known, read its README.md and map the
stack to relevant skills (Python, JS/TS, React, Next.js, Playwright,
Database/SQL, API development, SEO/Marketing, CSS/Styling, DevOps,
Documentation, Google Workspace — same mapping `/init-project` used).

Present recommendations grouped RECOMMENDED / OPTIONAL, with source
attribution. Install only with approval — per skill-evolution.md, nothing
installs silently.

Document installed skills in `wiki/memory.md` and `TEAM.md`'s (project-local
if one exists, otherwise skip — `TEAM.md` is no longer copied into every
project) "Catalog Skills" section if applicable.

#### 3.7 Wiki and Knowledge Structure

Full setup — create `wiki/` and subdirectories if missing (only files that
don't exist):
- `wiki/architecture.md`, `wiki/conventions.md`, `wiki/memory.md`,
  `wiki/learnings.md`, `wiki/PROJECT_STATUS.md`
- `wiki/decisions/_template.md`, `wiki/runbooks/_template.md`,
  `wiki/runbooks/incident-response.md`, `wiki/logs/`

Minimal setup — just `wiki/memory.md` (empty template) and `wiki/logs/`.

Create `memory/` two-tier knowledge structure if missing (full setup only):
- `memory/glossary.md`, `memory/people/`, `memory/projects/`, `memory/context/`

After creating (full setup), suggest: "Knowledge base structure created. Run
/knowledge bootstrap to populate it from your existing project context, or
fill it in as you go."

#### 3.8 Environment Files
- If `README.md` missing: create a basic README with project name,
  description, stack, and setup instructions
- If `.env.example` missing: create with any detected config keys (scan for
  environment variable references in code)
- If `.gitignore` missing: create a comprehensive one (`.env`, `__pycache__`,
  `node_modules`, `.venv`, `graphify-out/`, `.archive/`, `build/`, `dist/`)
- If `.gitignore` EXISTS: check it includes `.env` and `graphify-out/`,
  offer to add if missing

#### 3.9 Security Audit (full setup, existing projects especially)

Delegate to the security-auditor subagent: scan for hardcoded secrets
(current files and git history), check `.env`/`.gitignore` configuration,
check config files for hardcoded credentials. Present results with severity
and a remediation plan. Wait for approval before making security changes.
Record the audit date/results in `wiki/runbooks/security-baseline.md`.

#### 3.10 CI/CD Pipeline (full setup only)
- If `.github/workflows/` missing: detect stack, create appropriate `ci.yml`
  (Python: pytest + ruff/flake8 + pip-audit; Node: npm test + eslint + npm
  audit + npm run build). If stack unclear, ask what command runs tests.

#### 3.11 Graphify (Codebase Knowledge Graph, optional)

Same as before: check `graphify --version`, offer to install
(`uv tool install graphifyy && graphify install`, PyPI package name is
`graphifyy` with a double-y, CLI command is `graphify`), build the graph
(`graphify .`), install always-on integration (`graphify claude install`)
and git hooks (`graphify hook install`). Follow `capability-gaps.md` — ask
before installing.

#### 3.12 Constitution (optional)

Suggest `/constitution` to establish project principles and constraints.

#### 3.13 Initial Commit
If git is initialized and there are changes: commit ("Project adopted via
/adopt ({realm-key or 'one-off'})"), push if a GitHub remote exists.

#### 3.14 Branch Protection (production)
If production scope is ON and a GitHub remote was created: enable branch
protection on `main` (`gh api -X PUT repos/{org}/{repo}/branches/main/
protection ...`, 1 required approving review, strict status checks). If it
fails (e.g. free-tier private repo can't enforce protection), warn and note
that change-management is enforced by convention instead. Document in
`wiki/operations/change-management.md`.

#### 3.15 Production Directory Structure (production)
Create (only if missing): `wiki/compliance/` (gaps.md, data-inventory.md,
vendor-register.md, evidence-index.md, policies/), `wiki/legal/`
(dpa-template.md, privacy-policy.md, terms-of-service.md, cookie-policy.md —
copied from `~/.claude/templates/legal/`, headers marked "DRAFT — LAWYER
REVIEW REQUIRED"), `wiki/operations/` (deploy-runbook.md, rollback-runbook.md,
on-call-rotation.md, change-management.md). If global templates aren't
installed yet, create placeholders noting where to copy from once they are.

#### 3.16 Security Policies Pack (production)
Copy the 10 standard security policies from
`~/.claude/templates/security-policies/` to `wiki/compliance/policies/`
(acceptable-use, access-control, password, encryption,
vulnerability-management, vendor-management, data-classification,
data-retention, business-continuity, incident-response), each with a DRAFT
header. Placeholder-note if templates aren't installed yet.

#### 3.17 Audit Logging Scaffold (production)
Create a language-appropriate audit-log helper stub (`src/lib/audit-log.ts`
for Node/TS, `src/audit_log.py` for Python — same stub shape as
`/init-project` used: `actor`, `action`, `resource`, `metadata`, `timestamp`,
prints `[AUDIT] {...}` as a TODO placeholder for wiring to a real
destination). Document in `wiki/compliance/audit-logging.md`: what to log
(auth, data access, config changes, admin actions), where logs go (TBD —
vendor choice), retention (default 1 year, adjust per regulation).

#### 3.18 Compliance Workbook (production)
Create `wiki/compliance/soc2-controls.md`, `evidence/` +
`evidence/_index.md`, `risk-register.md`, `asset-inventory.md` — templates
the Compliance Officer agent populates over time.

#### 3.19 Environment Separation (production)
`cp .env.example .env.{development,staging,production}.example`. Add
`.env.development`, `.env.staging`, `.env.production`, `audit-logs/`,
`evidence/`, `backups/` to `.gitignore` if not already there. Document env
separation and secret-manager choice in `wiki/operations/environments.md`.

### Step 4 — Framework Health Check

Unlike `/init-project`, this does NOT check for project-local copies of
agent files — there aren't any anymore. Instead, verify the *global*
install is actually reachable from here:

```
Verifying framework is reachable...
```
- `~/.claude/agents/` exists and has all 7 agent files: {found/MISSING}
- `~/.claude/TEAM.md` exists: {found/MISSING}
- If a realm resolved: the realm root's `CLAUDE.md` exists and is readable:
  {found/MISSING}

If ANY missing, warn clearly rather than silently continuing — this is
exactly the failure mode (agents/TEAM.md not discoverable) that used to be
masked by copying files into every project. Suggest re-running `install.bat`
or checking the realm root's `CLAUDE.md` path. Run `/context` for a full
resolved-identity view.

### Step 5 — Final Report

```
{project_name} adopted

  Realm:            {realm-key, or "one-off — not part of a realm"}
  Production scope: {ON / OFF} {(realm declared) / (self-declared) / n/a}
  Setup depth:      {full / minimal}
  GitHub:           {repo URL or "not configured"}
  Stack:            {detected stack}
  Rules:            {count} active ({list})
  Wiki:             {count} pages ({existing} existing + {new} new)
  CI/CD:            {status}
  Graphify:         {status}
  Security:         {PASS / {count} issues found and remediated / {count} issues need attention}
  Realm skills synced: {count} (or "none available")
  Framework health: {PASS / INCOMPLETE}

  (production-only outputs below — omit if production scope is OFF)
  Branch protection: {ON / disabled — reason}
  Compliance docs:   {N} files in wiki/compliance/
  Legal docs:        {N} drafts in wiki/legal/ (LAWYER REVIEW REQUIRED)
  Security policies: {10/10} in wiki/compliance/policies/ (REVIEW REQUIRED)
  Audit logging:     scaffold created at {path}
  Env separation:    .env.development.example, .env.staging.example, .env.production.example

  Ready to build.
  /resume          pick up previous work (if session logs exist)
  /new-feature     start building something new (creates feature branch + PR)
  /bug-fix         fix something that's broken (creates fix branch + PR)
  /pr              open a PR from the current branch
  /context         see the resolved identity/rules chain for this project
  /status          see project overview
  /help            see all available commands

  (production-only commands)
  /compliance-audit  PDPA + SOC 2 gap analysis
  /data-inventory    map PII flows in the codebase
  /legal-docs        draft DPA / Privacy Policy / ToS
  /deploy [env]      deploy to dev/staging/production
  /incident          start incident response
```

## Pitfalls

- Overwriting existing CLAUDE.md or README — always check first, offer to enhance
- Copying agent definitions or realm identity/rules into the project — don't.
  The ancestor-walk already covers this; copying recreates the exact drift
  problem this redesign exists to fix
- Not verifying the global framework is actually reachable (Step 4) — silent
  failure defeats the purpose
- Running graphify install without asking — follow capability-gaps protocol
- Assuming production scope from a stream name — there is no stream name
  anymore; it comes from the realm's own `CLAUDE.md` declaration, or an
  explicit per-project self-declare
- Forgetting to ask "production scope?" when no realm declaration exists —
  defaults to OFF, user must opt in
- Skipping Step 3.14 (branch protection) on production scope — change
  management collapses
- Skipping Step 3.16 (security policies) on production scope — SOC 2
  evidence pipeline never starts
- Re-adopting an already-adopted project without checking Step 3.0 first —
  wastes the user's time re-answering questions that are already answered

## Verification

- All expected files exist (CLAUDE.md, wiki/, etc. — NOT `.claude/agents/`,
  which is deliberately absent now)
- Framework health check passes (global agents/TEAM.md reachable, realm
  CLAUDE.md readable if applicable)
- Security audit ran (full setup) and results recorded
- No existing files were overwritten
- git initialized and initial commit created (unless minimal setup)
- Re-running `/adopt` on the same project reports "already adopted" instead
  of re-doing work
