---
name: knowledge
description: |
  TRIGGER when: the user wants to build or update the project's knowledge base,
  decode workplace jargon, add people or project context, check for memory gaps,
  or says "remember this", "who is", "what does X mean", "update knowledge",
  "second brain", "glossary", "bootstrap memory".
  DO NOT TRIGGER when: the user wants documentation updates (/document-all),
  session state (/status), or to capture a reusable pattern (/learn).
argument-hint: [bootstrap|update|gaps|search <term>]
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Knowledge Management — Second Brain

## When to Use

When the user wants to build, update, or search the project's knowledge base.
For decoding jargon, tracking people, or detecting memory gaps across sessions.
Not for documentation updates (/document-all) or capturing reusable patterns (/learn).

## Procedure

Build and maintain a structured knowledge base so the team never loses
context across sessions, projects, or streams.

Inspired by Anthropic's knowledge-work plugin memory architecture.

## Memory Architecture

Two tiers — hot cache for speed, deep store for everything:

```
CLAUDE.md (Memory section)    ← Hot cache: top ~30 people, ~30 terms,
                                 active projects. Covers 90% of daily lookups.
memory/
  glossary.md                 ← Full decoder ring: every acronym, term, codename
  people/                     ← One file per person or team
    {name}.md                   Role, contact, preferences, context
  projects/                   ← One file per project or initiative
    {project}.md                Status, goals, key decisions, stakeholders
  context/                    ← Company, team structure, tools, processes
    {topic}.md                  Org charts, tool configs, domain knowledge
```

Lookup flow: CLAUDE.md → memory/glossary.md → memory/{subdirectory} → ask user.

## Step 1 — Detect Mode

Based on $ARGUMENTS or conversation context:

- **bootstrap** — First-time setup. Create the memory/ structure and populate
  from existing project context (CLAUDE.md, wiki/, code comments, README).
- **update** — Add or modify specific knowledge entries.
- **gaps** — Scan codebase and docs for terms not in the knowledge base.
- **search {term}** — Look up a term across all memory tiers.
- No argument — ask: "What would you like to do? Bootstrap the knowledge base,
  update an entry, scan for gaps, or search for something?"

## Step 2 — Bootstrap (first run)

If memory/ directory doesn't exist or is empty:

1. Create the directory structure:
   ```
   memory/glossary.md
   memory/people/
   memory/projects/
   memory/context/
   ```

2. Scan existing sources for knowledge:
   - CLAUDE.md — extract project name, stack, stream
   - wiki/memory.md — extract any accumulated knowledge
   - wiki/decisions/ — extract project names, people mentioned
   - README.md — extract project description, setup context
   - Code comments and config files — extract service names, API references

3. For each discovered term, person, or project:
   - If clearly understood: add to glossary.md or appropriate subdirectory
   - If ambiguous: collect and ask user in one batch

4. Ask the user interactively (grouped, not one-by-one):
   ```
   I found these terms in your project that I'd like to understand:

   ACRONYMS/TERMS:
     1. {term} (found in {where}) — What does this mean?
     2. {term} (found in {where}) — What does this mean?

   PEOPLE:
     3. {name} (mentioned in {where}) — Who is this? Role?

   PROJECTS/CODENAMES:
     4. {name} (referenced in {where}) — What is this?

   Answer as many as you'd like. Skip any that aren't important.
   ```

5. Build the hot cache — add the top ~30 most-used entries to CLAUDE.md
   in a Memory section:
   ```markdown
   ## Memory (Hot Cache)

   ### People
   | Who | Role |
   |-----|------|
   | {nickname} | {full name}, {role} |

   ### Terms
   | Term | Meaning |
   |------|---------|
   | {acronym} | {definition} |

   ### Active Projects
   | Project | Status |
   |---------|--------|
   | {name} | {one-line status} |

   → Full knowledge base: memory/
   ```

6. Delegate to the knowledge-agent subagent to write all files.

GATE — Present the bootstrapped knowledge base for approval before saving.

## Step 3 — Update

When adding or modifying knowledge:

1. Determine what's being added (person, term, project, context)
2. Check if it already exists in either tier
3. If new: add to memory/ and promote to CLAUDE.md hot cache if high-usage
4. If exists: update the entry, note the change date
5. Delegate to knowledge-agent to make the writes

Report:
```
Knowledge updated:
  ADDED: {count} new entries
  UPDATED: {count} modified entries
  Hot cache: {count} entries in CLAUDE.md
  Deep store: {count} files in memory/
```

## Step 4 — Gap Detection

Scan for knowledge gaps:

1. Read all source files (code, docs, configs, wiki/)
2. Extract names, acronyms, project references, service names
3. Check each against memory/glossary.md and CLAUDE.md
4. Collect unknowns

Present grouped:
```
KNOWLEDGE GAPS ({count} unknown terms found):

  ACRONYMS ({count}):
    {term} — found in: {file}:{line}
    {term} — found in: {file}:{line}

  PEOPLE ({count}):
    {name} — mentioned in: {file}
    {name} — mentioned in: {file}

  SERVICES/PROJECTS ({count}):
    {name} — referenced in: {file}

Would you like to fill in any of these? (answer by number, or "all")
```

After user provides answers, delegate to knowledge-agent to update the store.

## Step 5 — Search

When searching for a term:

1. Check CLAUDE.md hot cache
2. Check memory/glossary.md
3. Grep memory/ directory recursively
4. Grep wiki/ directory
5. Grep codebase for usage context

Report:
```
"{term}" found:
  Hot cache: {yes/no} — {definition if found}
  Glossary: {yes/no} — {definition if found}
  Deep store: {files where found}
  Codebase: {files where referenced}
```

If not found anywhere:
```
"{term}" not found in knowledge base or codebase.
Would you like to add it?
```

## Maintenance Rules

- Hot cache (CLAUDE.md) stays under ~80 lines
- Entries get timestamps: "Added: {date}" or "Updated: {date}"
- Never delete from deep store — mark deprecated if outdated
- After 3+ lookups that hit deep store instead of hot cache, promote to hot cache
- After /wrap-up, check if any new terms from the session should be captured

## Pitfalls

- Overloading the hot cache beyond ~80 lines — it defeats the purpose of a cache
- Deleting from deep store instead of marking deprecated
- Asking the user for every unknown term one-by-one — batch questions
- Adding project-specific terms to the global glossary (keep them in memory/projects/)

## Verification

- Hot cache stays under ~80 lines
- All new entries have timestamps
- Deep store structure matches the expected layout (glossary, people, projects, context)
- User was asked in batches, not one-by-one
