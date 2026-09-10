---
name: team-start
description: |
  TRIGGER when: the user says /team:start, "start part <id>", "start building
  part <id>", "dispatch the builder for <id>", or otherwise asks to advance
  one specific docs/rebuild/BUILD_PLAN.md part through the lead/builder/
  verifier delivery loop defined in docs/rebuild/DESIGN.md ("Packaging and
  architecture", "Verification contract") and implemented by
  docs/rebuild/BUILD_PLAN.md Part 1.5.
  DO NOT TRIGGER when: the user wants a status snapshot across all parts
  (/team:status), wants to build an ordinary application feature outside the
  framework-rebuild delivery loop (that stays with the Lead Engineer directly
  per CLAUDE.md's "Handle yourself: Implementation" rule, or use
  /new-feature / /bug-fix), or the part's acceptance criteria in
  docs/rebuild/BUILD_PLAN.md are not yet agreed (settle those first).
disable-model-invocation: true
user_locked: true
pinned: true
---

# Team Start — Lead-Driven Build/Verify Dispatch

## When to Use

When the user wants to advance ONE named `docs/rebuild/BUILD_PLAN.md` part
(e.g. "2.1") from assignment through independent verification, using the
native-subagent lead/builder/verifier loop. Not for general application
features (those are `/new-feature` or `/bug-fix`), not for a multi-part or
whole-phase run (this skill handles exactly one part per invocation), and
not for checking status without dispatching anything (`/team:status`).

## Lead Engineer Guidance

You (the lead session) are the only party that runs this procedure. You
never write application code yourself here — you assign it, dispatch a
`team-builder` subagent to write it, independently confirm state
transitions by reading `.claude/state/team-tasks.json` yourself (never by
trusting a subagent's chat report), dispatch a `team-verifier` subagent to
check it, and only then attempt completion through the one sanctioned gate.

**Where the scripts live, and where you must stand when you run them —
these are two different things, and both matter.** Every script below is
invoked by its *installed absolute path* (`~/.claude/scripts/team/...`,
where `install.bat` puts them); the three scripts locate each other
relative to their own file location, so they work from any working
directory. But you must still run every one of them **from the target
project's root**, because `task-state.sh` resolves
`.claude/state/team-tasks.json` relative to the current working directory
(see `task-state.sh`'s own header comment). That is deliberate: the scripts
are global tooling, the task state is per-project data, and the cwd is the
only thing that decides *which* project's task state you are reading and
writing. Get either half wrong and something breaks — a relative script
path fails outright outside a checkout of this repo, and the right script
run from the wrong directory silently touches the wrong project's state.

**Exception — working inside a checkout of this framework repo itself.**
If you are developing the framework rather than using it on another
project, call the repo-local copy instead — `bash scripts/team/task-state.sh
...`, `bash scripts/team/assign.sh ...`, `bash scripts/team/complete-gate.sh
...`, from the repo root. That copy is the version under development; the
installed copy at `~/.claude/scripts/team/` only refreshes when
`install.bat` is re-run, so it may lag behind the repo.

**Hard rule, stated here directly, not just inherited from the scripts:**
a task is NEVER marked complete by any means other than a successful run of
`~/.claude/scripts/team/complete-gate.sh <id>`. Not by you editing state,
not by a builder's or verifier's claim of "done," not by `task-state.sh complete`
called directly outside the gate. If the gate fails, the task stays in
`checking` and you report the gate's real failure message — you do not
paper over it, retry blindly, or call `task-state.sh complete` yourself to
route around a failing check.

## Procedure

**Before running any command below, settle which copy of the scripts you are
calling.** Every command in these steps is written in its *installed* form
(`~/.claude/scripts/team/...`). If your working directory is a checkout of
the framework repo itself, substitute the repo-local `scripts/team/...`
instead, per the exception above — do not copy the commands below literally
in that case. This is not a rare corner: `docs/rebuild/BUILD_PLAN.md` parts
currently only exist in this repo, so the repo-local form is the common case
today, and using the installed copy while actively editing those same
scripts would silently run a stale version. Decide once, here, and use that
form consistently for every step.

### Step 1 — Confirm the part exists in task state

1. Run `bash ~/.claude/scripts/team/task-state.sh status <id>`.
2. If it succeeds (task found), read its current `state` and move to Step 2.
3. If it fails ("task '<id>' not found"), the task record does not exist
   yet — create it before anything else:
   a. Open `docs/rebuild/BUILD_PLAN.md` and find the part's own numbered
      entry (e.g. "1.5 Implement plugin start and status interface.") and
      its "Acceptance:" line — this is the title and acceptance text you
      will use everywhere below. Do not paraphrase the acceptance text away
      from what BUILD_PLAN.md actually says.
   b. Identify this part's real dependencies: which other BUILD_PLAN.md
      parts must already be `done` before this one can start, per
      BUILD_PLAN.md's own phase/part ordering and this part's acceptance
      text. Use the same part-number strings as task IDs (e.g. a task
      created for part "1.5" depends on the task already recorded as
      "1.4"). If a dependency's task record doesn't exist yet either, this
      skill does not create it for you — stop and say which upstream part
      needs to be started first.
   c. Create the record:
      `bash ~/.claude/scripts/team/task-state.sh create <id> "<title>" --depends <dep-ids-or-omit> --risk <low|medium|high> --budget <N>`
      Use `--skills a,b` only if specific `skills/*/SKILL.md` files
      genuinely govern this part's own deliverable (e.g. the part is itself
      about building or changing a skill) — it's optional, per
      `task-state.sh`'s own usage text.
   d. Confirm creation by re-running `task-state.sh status <id>` yourself —
      do not assume the `CREATED` echo line alone means the record is
      correct; read back what was actually stored.

### Step 2 — Check dependencies (do not re-implement the check)

`task-state.sh start <id>` already enforces "all `depends_on` tasks are
`done`" before it will transition anything — do not re-read
`depends_on` and re-check state yourself first. Just attempt Step 3, and if
it's rejected, surface the rejection plainly (see Step 3).

### Step 3 — Transition to building

Run `bash ~/.claude/scripts/team/task-state.sh start <id>`.

- On success: state is now `building`. Continue to Step 4.
- On failure (unmet dependency, wrong starting state, task not found): stop
  here. Report the exact error `task-state.sh` printed — which dependency
  is unmet, or which state the task is actually in — and do not attempt any
  workaround (no hand-editing state, no dispatching a builder anyway). This
  is exactly the enforcement DESIGN.md and BUILD_PLAN.md Part 1.2 describe;
  route the user to whatever upstream part is actually blocking.

### Step 4 — Record the builder assignment

Determine the skill file path(s), if any, that genuinely govern this part's
own deliverable (see Step 1c) — this is what gets hashed as the "loaded
skill revision" evidence for the assignment.

Run:
```
bash ~/.claude/scripts/team/assign.sh <id> --role builder --agent-type team-builder \
  [--skills path1,path2,...]
```

- On success: `assign.sh` durably records the assignment (agent type, per-
  skill sha256 hashes, timestamp, code snapshot) via
  `task-state.sh record-assignment`, and prints a `BRIEFING` block —
  including ready-to-use "Instructions to the builder subagent" text. Keep
  this output; it is the factual basis for Step 5's dispatch, not something
  to paraphrase from memory.
- On failure (missing skill file, colon in a skill path, part not found):
  stop and report the exact error. Do not dispatch a builder against an
  assignment that was never actually recorded.

### Step 5 — Dispatch the team-builder subagent

Using the Agent/Task tool, dispatch a subagent with `subagent_type:
team-builder` (see `agents/team-builder.md`). Build its prompt from real
material only — no invented context:

1. The part's title and full "Acceptance:" text, copied verbatim from
   `docs/rebuild/BUILD_PLAN.md` (Step 1a).
2. The assignment record `assign.sh` just wrote (Step 4's `BRIEFING` block:
   part ID, role, agent type, code snapshot, skill paths + hashes).
3. `agents/team-builder.md`'s own stated workflow, made explicit again in
   the prompt: implement real working code and tests; run the tests
   yourself and read the actual output; when implementation and tests are
   ready, move the task to `checking` yourself
   (`bash ~/.claude/scripts/team/task-state.sh check <id>`); **never call
   `task-state.sh complete` and never claim the task is "done"** —
   completion is not the builder's to grant.
4. The scope boundary from `agents/team-builder.md`: no hand-editing
   `.claude/state/*`, no editing `docs/rebuild/*` beyond this part's own
   status line (and only if asked), no touching verification/evidence code.

Wait for the subagent to finish and report back.

### Step 6 — Independently confirm the builder actually reached "checking"

Do not trust the builder's chat report by itself — this project's own
incident record (BUILD_PLAN.md, "Definition of implementation completion")
is exactly a case where a subagent's self-report was false. Run:

`bash ~/.claude/scripts/team/task-state.sh status <id>`

- If `state` is `checking`: proceed to Step 7.
- If `state` is still `building`: the builder did not actually transition
  the task, regardless of what it reported in chat. Stop and report this
  discrepancy plainly to the user — do not proceed to verification, and do
  not call `task-state.sh check <id>` yourself on the builder's behalf.
- If `state` is `blocked`: read `blocked_reason` and `resume_condition` and
  report them; this is an escalation, not a bug to route around.

### Step 7 — Record the verifier assignment

Run:
```
bash ~/.claude/scripts/team/assign.sh <id> --role verifier --agent-type team-verifier \
  --acceptance-text "<the exact acceptance text from BUILD_PLAN.md, Step 1a>"
```
(`--acceptance-file <path>` works too if you saved the text to a file
first.) `--role verifier` requires this — `assign.sh` will refuse
otherwise, per its own usage text. This call also records a fresh code
snapshot identity at verifier-assignment time; that is what lets
`complete-gate.sh` later detect if the code moves again before evidence is
recorded.

On failure, stop and report the exact error, same as Step 4.

### Step 8 — Dispatch the team-verifier subagent

Using the Agent/Task tool, dispatch a subagent with `subagent_type:
team-verifier` (see `agents/team-verifier.md`). Build its prompt from:

1. The acceptance criteria text (verbatim, same text used in Step 7).
2. The code snapshot identity recorded in Step 7's `BRIEFING` block.
3. `agents/team-verifier.md`'s own stated workflow: independently open and
   read every file the builder's report claims to have produced; confirm
   the code snapshot; run the actual tests/checks and read the real output;
   map each acceptance criterion to concrete evidence; **record that
   evidence via `task-state.sh record-evidence` before reporting** (see
   `agents/team-verifier.md`, "How you work" — this call is what gives
   `complete-gate.sh` something real to check; a PASS/FAIL verdict that
   exists only in chat is not evidence); then report PASS/FAIL per
   criterion plus one overall verdict.

Wait for the subagent to finish and report back.

### Step 9 — Attempt completion through the gate — the only sanctioned path

1. Independently confirm evidence actually landed — do not rely on the
   verifier's chat claim that it called `record-evidence`. Run
   `bash ~/.claude/scripts/team/task-state.sh status <id>` and check the
   `evidence` array is non-empty and its last entry's `recorded_at` is
   recent (from this verification pass, not a stale entry from an earlier builder
   run). If `evidence` is empty or unchanged since Step 4, the verifier did
   not actually record evidence despite what it reported — say so plainly;
   this is a defect in that run, not something to paper over by inventing
   evidence yourself.
2. If a fresh evidence entry exists, run the gate as the real completion
   attempt:
   `bash ~/.claude/scripts/team/complete-gate.sh <id>` (add
   `--allow-no-tests` only if this part genuinely has no test surface — do
   not use it to dodge a real gap in coverage).
3. Report the gate's actual output verbatim — `GATE PASS ... COMPLETED ...
   state=done`, or `GATE FAIL (check N): <reason>` — whichever it actually
   printed. A gate failure (stale evidence, missing artifact, nonzero exit
   code, skipped/zero tests) means the task is still `checking`, not done;
   report the specific check that failed and stop there. Do not retry the
   gate blindly — if the failure is fixable (e.g. code moved since
   verification), the fix is to re-verify (back to Step 8, or a fresh
   builder pass if the underlying code needs to change), not to re-run the
   same gate hoping for a different result.

## Pitfalls

- Trusting a builder's or verifier's chat report instead of independently
  reading `task-state.sh status <id>` — this is the exact failure mode
  BUILD_PLAN.md's "Definition of implementation completion" section
  documents actually happening once already.
- Calling `task-state.sh complete <id>` directly, or hand-editing
  `.claude/state/team-tasks.json`, to route around a failing
  `complete-gate.sh` check — never do this; a gate failure is the correct,
  informative outcome, not an obstacle to bypass.
- Dispatching a verifier before independently confirming the builder
  actually reached `checking` state.
- Skipping Step 9.1's independent evidence check and just running
  `complete-gate.sh` on faith that the verifier called `record-evidence` —
  the gate itself will catch a genuinely missing evidence array (its own
  check 2), but confirming first gives you a clear diagnosis instead of a
  bare gate failure to puzzle over.
- Inventing dependency IDs, acceptance text, or skill paths instead of
  reading them from `docs/rebuild/BUILD_PLAN.md` and the repo itself.

## Verification

- `task-state.sh status <id>` was read independently at least twice: once
  after the builder reported (Step 6) and once before attempting the gate
  (Step 9.1) — never taken on a subagent's word alone.
- Both assignments (builder and verifier) were recorded via `assign.sh`
  before their respective subagent was dispatched, not after.
- The verifier's evidence is present in `task-state.sh status <id>`'s
  `evidence` array before `complete-gate.sh` is run.
- The task reaches `done` only if `complete-gate.sh` itself printed `GATE
  PASS ... COMPLETED ... state=done` — never any other way.
- If the gate failed, the exact `GATE FAIL (check N): <reason>` line was
  reported to the user verbatim, not summarized into "mostly done."
