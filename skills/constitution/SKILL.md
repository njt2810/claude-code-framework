---
name: constitution
description: |
  TRIGGER when: the user wants to establish project principles, governance, or architectural
  constraints. Also trigger during /init-project for new projects, or when the user says
  "set project rules", "define how we build", "project constitution", or "project principles".
  DO NOT TRIGGER when: the user wants to start a specific feature (/new-feature), fix a bug
  (/bug-fix), or do a security audit (/security-check). This is for project-level governance only.
argument-hint: [project-name]
disable-model-invocation: true
effort: high
user_locked: true
---

# Project Constitution

## When to Use

When establishing or updating project governance — principles, quality standards,
architectural constraints, and non-negotiable rules. Runs once per project during
/init-project, or on demand when the user wants to formalize how the project is built.

## Procedure

Establish the principles, constraints, and quality standards that govern how
this project is built. This runs once per project (during /init-project or
on demand) and creates a living document that all future work references.

Inspired by spec-driven development — decisions made here prevent rework later.

## Step 1 — Understand the Project

Before asking questions, gather context:

1. Read `CLAUDE.md` for project identity and stack
2. Read `wiki/architecture.md` if it exists
3. Read `wiki/conventions.md` if it exists
4. Read `wiki/decisions/` for any existing ADRs
5. Scan the codebase for patterns already in use

Summarize what you found:
"Here's what I know about this project: {summary}.
 Now I need to understand how you want it built."

## Step 2 — Ask the Governance Questions

Ask these in conversational order. Explain each one in plain language.
Accept short answers — you'll expand them into the constitution.

### Principles (what matters most)
"When I'm building and have to make a tradeoff, what should I prioritize?
 For example:
 - Speed of delivery vs code quality?
 - Simplicity vs flexibility?
 - User experience vs technical elegance?
 - Security vs convenience?

 Pick your top 3 priorities, or tell me in your own words."

### Quality Standards
"What's the minimum quality bar for this project?
 - Should every feature have tests? (yes/no/only critical paths)
 - Should code be reviewed before merging? (yes/no/for sensitive areas)
 - Any performance targets? (e.g., pages load in under 2 seconds)
 - Any accessibility requirements? (e.g., WCAG compliance)
 - Any browser/device requirements? (e.g., must work on mobile)"

### Architectural Constraints
"Are there any hard rules about how the project is built?
 For example:
 - Must use specific technologies (e.g., React, Python, Supabase)
 - Must NOT use certain approaches (e.g., no ORMs, no server-side rendering)
 - Must integrate with specific services (e.g., Stripe, Auth0)
 - Any deployment constraints (e.g., must run on Vercel, must be serverless)

 If you're not sure yet, that's fine — we can add constraints later."

### Non-Negotiable Rules
"What should NEVER happen in this project? These become hard rules I always follow.
 Examples:
 - Never store user passwords in plain text
 - Never deploy without running tests
 - Never add a dependency without checking its maintenance status
 - Never make breaking API changes without versioning

 What are yours?"

### Decision-Making Framework
"When I face a choice you haven't explicitly decided (e.g., which library to use,
 how to structure a module), how should I handle it?
 1. Always ask you first (safest, slower)
 2. Make the call and tell you what I chose (faster, I explain my reasoning)
 3. Make the call for small decisions, ask for big ones (balanced)

 Which approach?"

## Step 3 — Draft the Constitution

Based on the answers, create `constitution.md` in the project root:

```markdown
# Project Constitution — {Project Name}

Established: {date}
Last updated: {date}

## Principles (in priority order)
1. {Principle} — {why this matters}
2. {Principle} — {why this matters}
3. {Principle} — {why this matters}

## Quality Standards
- Testing: {requirement}
- Code review: {requirement}
- Performance: {targets or "no specific targets"}
- Accessibility: {requirements or "not specified"}
- Compatibility: {requirements or "not specified"}

## Architectural Constraints
- Must use: {technologies/services}
- Must not use: {excluded approaches}
- Must integrate with: {services}
- Deployment: {constraints}

## Non-Negotiable Rules
1. {Rule}
2. {Rule}
3. {Rule}

## Decision-Making
{How the Lead Engineer should handle undecided choices}

## Evolution
This constitution evolves as the project grows. Changes require
explicit approval. To update: `/constitution` and discuss changes.
```

Present the draft to the user.
GATE — Wait for approval before saving.

## Step 4 — Save and Integrate

After approval:

1. Save `constitution.md` to the project root
2. Add a reference in `CLAUDE.md`:
   "Read constitution.md for project principles and constraints.
    All features, fixes, and decisions must align with the constitution."
3. Add to `wiki/memory.md`:
   "Project constitution established on {date}. Key principles: {top 3}."
4. If an ADR doesn't exist for the constitution:
   Create `wiki/decisions/001-project-constitution.md`

Report:
"Constitution established. All future /new-feature and /bug-fix work
 will reference these principles. Run /constitution again to update."

## When Called on an Existing Constitution

If `constitution.md` already exists:

1. Read it
2. Present the current constitution
3. Ask: "What would you like to change?"
4. Show the proposed changes (CURRENT vs PROPOSED)
5. Wait for approval before updating
6. Log the change in `wiki/decisions/` as an ADR

## Pitfalls

- Making the constitution too rigid — it should evolve as the project grows
- Not referencing the constitution in CLAUDE.md — it won't be consulted during builds
- Adding specific implementation details (use X library) instead of principles
- Not creating an ADR for the initial constitution or subsequent changes

## Verification

- constitution.md exists in the project root
- CLAUDE.md references constitution.md
- All sections are populated (Principles, Quality Standards, Constraints, Rules, Decision-Making)
- An ADR was created in wiki/decisions/
