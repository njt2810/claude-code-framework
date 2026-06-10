---
name: evaluate-repo
description: |
  TRIGGER when: the user shares a GitHub repo URL, wants to assess a tool/library/skill,
  or says "check this repo", "is this useful", "evaluate this", "should we use this".
  DO NOT TRIGGER when: the user wants to clone and work on a repo directly,
  or wants to init their own project (/init-project).
argument-hint: [github-url]
disable-model-invocation: true
effort: medium
user_locked: true
---

# Repository Evaluation

## When to Use

When the user shares a GitHub repo URL and wants to know if it's worth adopting.
Not for cloning and working on a repo directly, or initializing their own project.

## Procedure

Assess whether a GitHub repo is useful for THIS project.

## Step 1 — Fetch and Understand

Read the repo at $ARGUMENTS:
1. Fetch the README
2. Check: stars, last commit date, open issues count
3. Identify: what it does, what problem it solves, what it requires

Summarize in 2-3 sentences.

## Step 2 — Relevance Assessment

Score against THIS project by reading CLAUDE.md and wiki/architecture.md:

**RELEVANCE:** Does this solve a problem we actually have?
- Direct match — solves a current pain point or gap
- Adjacent — useful but not immediately needed
- Irrelevant — doesn't apply to this project

**OVERLAP:** Does this duplicate something we already have?
- Check .claude/skills/ for similar skills
- Check package.json / requirements.txt for similar packages
- If overlap: is the new one better?

**QUALITY:**
- Stars: {count}
- Last commit: {date} — {active/stale/abandoned}
- Open issues: {count} — are they being addressed?
- Contributors: {count}
- Tests in repo: yes/no

**COST:**
- Dependencies it pulls in
- Token cost if it's a skill
- Learning curve: low/medium/high
- Maintenance: actively maintained? Bus factor risk?

**RISK:**
- Last commit >6 months ago = maintenance risk
- Few contributors = bus factor risk
- No tests = quality risk
- Lots of unanswered issues = abandoned risk

## Step 3 — Verdict

Present a clear recommendation:

```
{Repo Name} — {one-line description}

  Relevance: {rating} {explanation}
  Overlap:   {what it replaces or complements}
  Quality:   {stars} stars, last commit {date}, {maintenance status}
  Cost:      {dependencies, complexity}
  Risk:      {any concerns}

  Verdict: {ADOPT / EVALUATE FURTHER / SKIP}
```

If ADOPT:
- Install method: {exact command}
- Where it fits: {.claude/skills/ or dependencies}
- "Install now? (yes/no)" — follow capability-gaps protocol

If EVALUATE FURTHER:
- What to test before deciding

If SKIP:
- Why and what to use instead

## Step 4 — Cross-Project Check

"This repo could also be useful for your other projects:
 - {project}: {why it might apply}
 Consider noting this in your Obsidian wiki."

## Pitfalls

- Recommending ADOPT based on star count alone — check last commit date and open issues
- Not checking for security issues (malicious packages, exposed secrets in repo)
- Installing without following capability-gaps protocol
- Recommending repos that duplicate existing skills without noting the overlap

## Verification

- Verdict is one of ADOPT / EVALUATE FURTHER / SKIP with clear reasoning
- Security risks were checked before recommending adoption
- Cross-project applicability was considered
