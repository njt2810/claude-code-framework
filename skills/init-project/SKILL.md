---
name: init-project
description: |
  TRIGGER when: the user wants to start a new project, bring an existing project under management,
  or says init, initialize, setup project, start project, new project, bootstrap.
  DO NOT TRIGGER when: the user wants to start building a feature (/new-feature), fix a bug (/bug-fix),
  or resume work (/resume). This is for project SETUP only.
argument-hint: [stream-name]
disable-model-invocation: true
effort: high
user_locked: true
pinned: true
---

# Init Project — Project Bootstrap Framework

## When to Use

When the user wants to start a new project or bring an existing project under
management. Not for starting a feature, fixing a bug, or resuming work.

## Procedure

You are initializing a project with a professional development framework.
The stream argument tells you which context this project belongs to.

## Stream Configuration

Based on $ARGUMENTS (or ask if not provided), apply these settings:

### personal
- GitHub org: `github.com/njt2810` (personal account)
- GitHub naming: `{project_name}` (no prefix)
- Obsidian wiki: `C:\Users\Nirej\Documents\Personal\AI-Wiki`
- Cost tracking: yes
- Cost dashboard: `C:\Users\Nirej\Documents\Personal\5-Project Dashboard`

### omasu
- GitHub org: `github.com/omasu2-0` (omasu org)
- GitHub naming: `{project_name}` (no prefix needed — org provides context)
- Obsidian wiki: `C:\Users\Nirej\Documents\Personal\6-Omasu\Omasu-Wiki`
- Cost tracking: yes
- Cost dashboard: `C:\Users\Nirej\Documents\Personal\5-Project Dashboard`

### xtend
- GitHub org: `github.com/xtend-adtech` (xtend org)
- GitHub naming: `{project_name}` (no prefix needed — org provides context)
- Obsidian wiki: `C:\Users\Nirej\Documents\Personal\AI-Wiki`
- Cost tracking: no (employer pays)
- Cost dashboard: n/a

### learning
- GitHub naming: none (no repo)
- Obsidian wiki: `C:\Users\Nirej\Documents\Personal\AI-Wiki`
- Cost tracking: no
- Minimal setup: CLAUDE.md + skills/learned/ + wiki/ only
- No agents, no CI/CD, no hooks, no rules

If no stream is provided, ask:
"Which stream is this project for?
 1. personal — your own projects
 2. omasu — side hustle / client work
 3. xtend — work projects
 4. learning — experiments, no shipping"

## Step 1 — Detect Existing Project

Scan the current directory. Report what you find:

```
Checking for existing project...
```

Check for each of these and report EXISTS or MISSING:
- `.git/` directory
- `CLAUDE.md`
- `.claude/` directory (and what's inside)
- `TEAM.md`
- `.claude/agents/` (and which agents exist)
- `wiki/` directory (and what pages exist)
- `package.json` or `requirements.txt` (detect stack)
- Test files (any files with "test" or "spec" in the name)
- `.github/workflows/` (CI/CD)
- `.env` or `.env.example`
- `.gitignore`
- `project-costs.json`
- `README.md`

Auto-detect the primary stack:
- `.py` files → Python
- `.js` / `.ts` files → JavaScript/TypeScript
- `.jsx` / `.tsx` files → React
- `package.json` → Node.js (read it for framework info)
- `requirements.txt` → Python (read it for framework info)
- If mixed, note both

## Step 2 — Ask for Project Identity (if new)

If no CLAUDE.md or README exists, ask:
- Project name (suggest from folder name)
- One-line description: "What does this project do, in one sentence?"
- If the folder is EMPTY (no code files detected in Step 1):
  "What will you be building this with? For example:
   - Python script or automation
   - A website (React, Next.js, HTML)
   - A browser automation (Playwright, Puppeteer)
   - A data pipeline
   - An API
   - Not sure yet
   This helps me recommend the right tools and set up the project correctly."
  Store the answer as the intended stack.

If CLAUDE.md already exists, read it and extract the project identity.

## Step 3 — Automated Setup

CRITICAL: Never overwrite existing files. Only create what's MISSING.
For existing files, offer to ENHANCE (append framework pointers) with approval.

Execute these steps, skipping any that are already present:

### 3.1 Git Initialization
- If `.git/` missing: `git init`
- If stream is NOT learning: check if `gh` CLI is available
  - If `gh` available: create private repo on the correct GitHub org:
    - personal → `gh repo create njt2810/{project_name} --private`
    - omasu → `gh repo create omasu2-0/{project_name} --private`
    - xtend → `gh repo create xtend-adtech/{project_name} --private`
  - If `gh` not available: say "GitHub CLI (gh) is not installed. I can help you install it later, or you can create the repo manually on github.com. Continuing without GitHub integration."
- If stream IS learning: skip GitHub entirely

### 3.2 CLAUDE.md
- If MISSING: generate from the template below
- If EXISTS: ask "Your CLAUDE.md exists. I'd like to add framework routing pointers (about 15 lines). These help me find rules, skills, and documentation faster. Add them? (yes/no)"

CLAUDE.md template (adapt based on detected stack and stream):

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
Stream: {personal/omasu/xtend}
Obsidian wiki: {path from stream config}
{If cost tracking enabled}: Cost dashboard: {path}

## Your Team
Your team is defined in TEAM.md. Agent definitions are in .claude/agents/.
Delegate to Code Reviewer, Test Engineer, Wiki Updater, Security Auditor,
and Knowledge Agent as described in the global rules and TEAM.md.

## Rules
- NEVER say "I've fixed the bug" without showing passing test output
- NEVER commit secrets, API keys, or .env files
- When working on {detected framework} files, read .claude/rules/debugging.md
- When working on test files, read .claude/rules/testing.md

## Long-Running Commands
For commands expected to take >2 minutes, use run_in_background.
NEVER chain long commands with && or ;. Run each separately with progress reports.

## Session Hygiene
- Use /clear between unrelated tasks
- Use subagents for research to keep main context clean
- After 2 failed fix attempts, /rewind and try a different approach

## Process Monitoring
- For multi-step tasks, always report: "Stage X/Y: doing Z..."
- If a command fails, report the error IMMEDIATELY — do not silently retry
- If any process exceeds 5 minutes, report status and ask whether to continue

## Codebase Structure
If graphify is installed, it manages its own integration via `graphify claude install`.
Otherwise: read graphify-out/GRAPH_REPORT.md before exploring the codebase.
Use `/graphify query "question"` for specific graph queries.
Use `/graphify path "A" "B"` to trace connections between components.

## Documentation
- Architecture and system design: wiki/architecture.md
- Code patterns and conventions: wiki/conventions.md
- Past decisions: wiki/decisions/
- Accumulated project knowledge: wiki/memory.md
```

### 3.3 Team Setup (CRITICAL — ensures agents work in this project)

This step copies the team infrastructure into the project so agents are
always discoverable, regardless of how Claude resolves global vs project paths.

**Copy TEAM.md to project root:**
```
cp ~/.claude/TEAM.md ./TEAM.md
```

**Copy agent definitions to project .claude/agents/:**
```
mkdir -p .claude/agents/
cp ~/.claude/agents/code-reviewer.md .claude/agents/
cp ~/.claude/agents/test-engineer.md .claude/agents/
cp ~/.claude/agents/wiki-updater.md .claude/agents/
cp ~/.claude/agents/security-auditor.md .claude/agents/
cp ~/.claude/agents/knowledge-agent.md .claude/agents/
cp ~/.claude/agents/ui-ux-engineer.md .claude/agents/
```

If the global agent files don't exist (framework not installed globally),
warn: "Global agent definitions not found at ~/.claude/agents/. Run
install.bat first, or the team won't be available in this project."

For **learning** stream: skip this step entirely (no agents needed).

### 3.4 Rules (scoped)
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

### 3.5 Skills
- Create `.claude/skills/learned/` directory if missing (for the learning system)
- Preserve any existing skills — do NOT modify or delete them

### 3.6 Skill Discovery (from Community Catalog)

Determine the project stack from one of two sources:
- EXISTING PROJECT: use the auto-detected stack from Step 1
- NEW/EMPTY PROJECT: use the intended stack stated by the user in Step 2

If no stack is known (user said "not sure yet"), skip skill discovery
and say: "Once you start building, I'll recommend relevant skills
from the community catalog as needed."

Check if the community skill catalog is available locally at
`~/.claude/skill-catalog/awesome-agent-skills/`:

If NOT cloned yet:
  "The community skill catalog has 1,000+ skills from Anthropic, Google,
   Vercel, Stripe, and the developer community. It helps me find the right
   tools for your specific project.

   Repository: github.com/VoltAgent/awesome-agent-skills
   One-time download (~50MB). Clone it? (yes/no)"

   If yes: `git clone https://github.com/VoltAgent/awesome-agent-skills.git ~/.claude/skill-catalog/awesome-agent-skills`

If the catalog exists and a stack is known (detected or stated),
read its README.md and map the stack to relevant skills:

  Python              → anthropics/pdf, duckdb/query, data analysis
  JavaScript/TS       → anthropics/frontend-design, vercel skills
  React               → google-labs-code/react-components, shadcn-ui
  Next.js             → vercel/next-js, google-labs-code/stitch-loop
  Playwright          → browser testing, automation skills
  Database/SQL        → duckdb skills (attach-db, query, read-file)
  API development     → stripe integration, API design skills
  SEO/Marketing       → AgriciDaniel/claude-seo, marketing skills
  CSS/Styling         → gsap animation, tailwind skills
  DevOps              → deployment, CI/CD, infrastructure skills
  Documentation       → anthropics/docx, anthropics/pptx, anthropics/xlsx
  Google Workspace    → googleworkspace/gws-drive, gws-sheets

Present recommendations grouped by relevance:

  For EXISTING projects (detected stack):
  "Based on your detected stack ({stack}), these skills are relevant:"

  For NEW projects (stated intent):
  "Based on what you're planning to build ({intent}), these skills
   will help you get started:"

  Then list:
   RECOMMENDED (directly matches your project):
     {skill} — {description} — {source: official/community}

   OPTIONAL (useful but not essential):
     {skill} — {description} — {source}

   Install recommended skills? (yes / pick individually / skip)"

Installation methods:
  - Plugin-based: `claude plugin add {source}` or `/plugin install {name}`
  - File-based: copy SKILL.md from catalog to `~/.claude/skills/{name}/`
  - Project-specific: copy to `.claude/skills/{name}/` (for this project only)

All installations follow the skill-evolution protocol — nothing installs
without explicit approval.

Document installed skills in wiki/memory.md:
  "Community skills installed: {list with sources}"

Update TEAM.md "Catalog Skills" section:
  Add each installed skill to the list under "### Catalog Skills (installed from community)"
  Format: `- {skill name} — {one-line description} ({source})`

### 3.7 Wiki and Knowledge Structure
Create `wiki/` and subdirectories if missing. Create each file only if it doesn't exist:
- `wiki/architecture.md` — stub: "# Architecture\n\nDocument system design here."
- `wiki/conventions.md` — stub with detected stack patterns
- `wiki/memory.md` — empty template for accumulated knowledge
- `wiki/learnings.md` — empty log for /learn captures
- `wiki/PROJECT_STATUS.md` — template with project identity filled in
- `wiki/decisions/_template.md` — ADR template
- `wiki/runbooks/_template.md` — runbook template
- `wiki/runbooks/incident-response.md` — basic incident response playbook
- `wiki/logs/` — empty directory for session logs

Create `memory/` two-tier knowledge structure if missing:
- `memory/glossary.md` — template: "# Glossary\n\n| Term | Meaning | Added |\n|------|---------|-------|\n"
- `memory/people/` — empty directory for people profiles
- `memory/projects/` — empty directory for project context
- `memory/context/` — empty directory for company/domain knowledge

After creating, suggest:
  "Knowledge base structure created. Run /knowledge bootstrap to populate it
   from your existing project context, or fill it in as you go."

### 3.8 Environment Files
- If `README.md` missing: create a basic README with project name, description, stack, and setup instructions
- If `.env.example` missing: create with any detected config keys (scan for environment variable references in code)
- If `.gitignore` missing: create comprehensive one (include .env, __pycache__, node_modules, .venv, graphify-out/, .archive/, build/, dist/)
- If `.gitignore` EXISTS: check if it includes .env and graphify-out/, offer to add if missing

### 3.9 Security Audit (CRITICAL for existing projects)

This step runs a full security audit of the project. For new empty projects
this will be brief. For existing projects this is essential.

Delegate to the security-auditor subagent:

"Run a complete security audit of this project:
 1. Scan all files for hardcoded secrets (API keys, passwords, tokens,
    private keys, credentials, connection strings)
 2. Scan git history for previously committed secrets
 3. Check .env and .gitignore configuration
 4. Check config files for hardcoded credentials"

Present results with severity levels and a remediation plan.
Wait for approval before making any security changes.

After the audit (whether issues were found or not), create or update
`wiki/runbooks/security-baseline.md` with the audit date and results.

### 3.10 CI/CD Pipeline (skip for learning stream)
- If `.github/workflows/` missing:
  - Detect stack and create appropriate `ci.yml`
  - Python projects: pytest + ruff/flake8 + pip-audit
  - Node projects: npm test + eslint + npm audit + npm run build
  - If stack unclear, ask: "What command runs your tests?"

### 3.11 Graphify (Codebase Knowledge Graph)

Graphify turns your project files into a queryable knowledge graph.

**IMPORTANT: The PyPI package is `graphifyy` (double y). The CLI command is `graphify`.**

Step 1 — Check if graphify is installed:
  Run: `graphify --version`
  If not installed, ask:
    "Graphify maps your codebase into a knowledge graph so I can navigate
     it intelligently. Install it? (yes/no)"

  If yes, install:
    - Preferred: `uv tool install graphifyy && graphify install`
    - Alternative: `pip install graphifyy && graphify install`
    - On Windows: `pip install graphifyy && graphify install --platform windows`

Step 2 — Build the graph (if code exists):
  Run: `graphify .`

Step 3 — Install always-on integration:
  Run: `graphify claude install`

Step 4 — Install git hooks for auto-rebuild:
  Run: `graphify hook install`

Step 5 — Obsidian integration (optional):
  If the user's stream has an Obsidian wiki, mention:
    "Graphify can also generate an Obsidian vault from the knowledge graph.
     Run: /graphify . --obsidian --obsidian-dir {obsidian_wiki_path}
     Want to set this up? (yes/no)"

### 3.12 Constitution (optional)
After setup, suggest establishing project governance:
  "Would you like to set up a project constitution? This defines your
   principles, quality standards, and non-negotiable rules — so I always
   know what tradeoffs to make when building.
   Run /constitution to set it up, or skip for now."

If the user says yes, run /constitution. If no, continue.

### 3.13 Initial Commit (if git is initialized and there are changes)
```
git add .
git commit -m "Project bootstrapped via init-project ({stream} profile)"
```
If GitHub remote exists, push.

## Step 4 — Team Verification (CRITICAL)

After all setup steps, verify that the team infrastructure is discoverable.
This catches the Bug 2 failure mode where agents and TEAM.md aren't found.

```
Verifying team setup...
```

Check each of these and report:
- TEAM.md at project root: {found/MISSING}
- .claude/agents/code-reviewer.md: {found/MISSING}
- .claude/agents/test-engineer.md: {found/MISSING}
- .claude/agents/wiki-updater.md: {found/MISSING}
- .claude/agents/security-auditor.md: {found/MISSING}
- .claude/agents/knowledge-agent.md: {found/MISSING}
- .claude/agents/ui-ux-engineer.md: {found/MISSING}

If ALL found:
```
Team verification: PASS
  Code Reviewer: found
  Test Engineer: found
  Wiki Updater: found
  Security Auditor: found
  Knowledge Agent: found
  UI/UX Engineer: found
  TEAM.md: found
```

If ANY missing:
```
Team verification: INCOMPLETE
  {agent}: MISSING — copy from ~/.claude/agents/ or run install.bat
```

## Step 5 — Final Report

After all steps complete, present a summary:

```
{project_name} initialized

  Stream:     {stream}
  GitHub:     {repo URL or "not configured"}
  Stack:      {detected stack}
  Rules:      {count} active ({list})
  Wiki:       {count} pages ({existing} existing + {new} new)
  CI/CD:      {status}
  Graphify:   {status}
  Security:   {PASS / {count} issues found and remediated / {count} issues need attention}
  Team:       {PASS / INCOMPLETE}

  Obsidian:   {path from stream config}
  {If cost tracking}: Costs: {dashboard path}

  Recommendations:
  {List any issues found}

  Ready to build.
  /resume       pick up previous work (if session logs exist)
  /new-feature  start building something new
  /bug-fix      fix something that's broken
  /status       see project overview
  /help         see all available commands
```

## Pitfalls

- Overwriting existing CLAUDE.md or README — always check first, offer to enhance
- Not copying agents to the project directory — this causes Bug 2 (agents not found)
- Not verifying team setup at the end — silent failure defeats the purpose
- Running graphify install without asking — follow capability-gaps protocol
- Learning stream should NOT get agents, CI/CD, hooks, or rules

## Verification

- All expected files exist (CLAUDE.md, .claude/agents/, TEAM.md, wiki/, etc.)
- Team verification passes (all agents found at project level)
- Security audit ran and results recorded
- No existing files were overwritten
- git initialized and initial commit created (if not learning stream)

## Important Notes
- This command is ADDITIVE — it never deletes or overwrites existing files
- For learning stream, skip: agents, CI/CD, hooks, rules, GitHub, cost tracking
- Always ask before installing tools (graphify, gh CLI, etc.)
- If anything fails (GitHub creation, graphify install), continue with the rest and note the failure
