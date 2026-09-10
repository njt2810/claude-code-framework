---
name: team-status
description: |
  TRIGGER when: the user says /team:status, "team status", "how's the build
  going", "what parts are done", or wants a snapshot of the
  docs/rebuild/BUILD_PLAN.md delivery loop's task state (see
  docs/rebuild/DESIGN.md "Delivery model" and BUILD_PLAN.md Part 1.5).
  DO NOT TRIGGER when: the user wants to dispatch/start a specific part
  (/team:start), wants the general project status (/status), or wants
  coached next-action guidance (/recommend).
disable-model-invocation: true
user_locked: true
---

# Team Status — Delivery-Loop Snapshot

## When to Use

When the user wants a concise snapshot of every tracked
`docs/rebuild/BUILD_PLAN.md` part's state (planned/building/checking/
blocked/done) from the lead/builder/verifier delivery loop. This is a
read-only report — it dispatches nothing and changes no state. For starting
a specific part, use `/team:start`. For the general project's git/PR/wiki
snapshot, use `/status`.

## Lead Engineer Guidance

This is a status read, not a judgment call — every line in the output must
trace back to something actually read from
`.claude/state/team-tasks.json` or freshly computed from the working tree,
never inferred or remembered from earlier in the conversation. State can
move between invocations (another session, a builder subagent, or a plain
interactive edit), so re-read it fresh every time this skill runs.

**Where the scripts live vs. where you run them — two different things.**
`task-state.sh` is invoked by its *installed absolute path*
(`~/.claude/scripts/team/task-state.sh`, where `install.bat` puts it), so it
works from any working directory. But you must still run it **from the
target project's root**, because it resolves
`.claude/state/team-tasks.json` relative to the current working directory
(see `task-state.sh`'s own header comment). The scripts are global tooling;
the task state is per-project data, and the cwd is the only thing that
decides *which* project's state this report describes. The same applies to
Step 2's `git` commands — run them from that same project root, or the
computed snapshot describes the wrong tree.

**Exception — working inside a checkout of this framework repo itself.**
If you are developing the framework rather than using it on another
project, call the repo-local copy instead — `bash scripts/team/task-state.sh
...`, from the repo root. That copy is the version under development; the
installed copy at `~/.claude/scripts/team/` only refreshes when
`install.bat` is re-run, so it may lag behind the repo.

## Procedure

**Before running any command below, settle which copy of the scripts you are
calling.** The commands here are written in their *installed* form
(`~/.claude/scripts/team/...`). If your working directory is a checkout of
the framework repo itself, substitute the repo-local `scripts/team/...`
instead, per the exception above — that is the common case today, since
`docs/rebuild/BUILD_PLAN.md` parts currently only exist in this repo.

### Step 1 — Read all tasks

Run `bash ~/.claude/scripts/team/task-state.sh list`. If it prints "No tasks
recorded.", report that plainly and stop — there is nothing further to
compute.

Otherwise, for each task also read its full record —
`bash ~/.claude/scripts/team/task-state.sh status <id>` — since `list` alone
only gives id/state/title/depends_on, and Step 2 below needs each task's latest
`evidence[-1].code_snapshot` and `assignments[-1]` too.

### Step 2 — Flag staleness for tasks in "building" or "checking"

For a task whose evidence might now be stale — i.e. its `state` is
`building` or `checking` — the underlying code may have moved since the
task's most recent assignment or evidence entry was recorded. Compute the
CURRENT code snapshot with the exact same logic `compute_snapshot()` uses
in `task-state.sh` / `assign.sh` / `complete-gate.sh` (documented at length
in each script's own header comment; this is intentionally a fourth,
read-only copy of that logic for the same reason those three are already
independent copies of each other — keep it in sync if that logic changes):

```bash
sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
if [ -z "$sha" ]; then
  echo "no-git-repository"
elif [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  diff_hash=$({
    git diff HEAD 2>/dev/null
    git status --porcelain --untracked-files=all 2>/dev/null | while IFS= read -r line; do
      echo "$line"
      case "$line" in
        '??'*) f="${line#???}"; [ -f "$f" ] && cat "$f" ;;
      esac
    done
  } | sha256sum | awk '{print $1}' | cut -c1-12)
  echo "uncommitted, base SHA $sha, diff $diff_hash"
else
  echo "$sha"
fi
```

Compare this CURRENT value against the task's most recently recorded
snapshot:

- For a `checking` task: compare against `evidence[-1].code_snapshot` if
  any evidence exists, otherwise against `assignments[-1].code_snapshot`
  (whichever assignment is most recent — usually the verifier's, but if a
  task just reached `checking` and no verifier assignment has been recorded
  yet, `assignments[-1]` is still the builder's; either way, no evidence
  existing yet is itself worth flagging, separately, as "no evidence
  recorded yet").
- For a `building` task: compare against the builder `assignments[-1]`
  entry's `code_snapshot`.

If the two values differ, the task's recorded snapshot no longer matches
the actual current tree — flag it. This is the literal meaning of this
project's "unmanaged changes invalidate affected results" requirement: an
ordinary interactive edit made outside the managed builder/verifier flow,
or any commit landed after the snapshot was taken, must show up here rather
than silently leaving a `checking` task looking fine. Do not silently pass
a task whose snapshot doesn't match.

### Step 3 — Display concisely

Do not dump the raw JSON state file. Match this repo's global Process
Monitoring tone (concise, no unexplained gaps, no spam) — one line per task
plus a flag line only where something needs attention:

```
Team status — {N} tasks

  {id}  [{state}]  {title}
  {id}  [{state}]  {title}   ⚠ evidence stale — recorded {old-snapshot}, current {new-snapshot}, re-verify
  {id}  [{state}]  {title}   ⚠ no evidence recorded since verifier assignment — run /team:start's Step 9 check
  {id}  [{state}]  {title}   (blocked: {blocked_reason})
  ...

  Planned: {N}   Building: {N}   Checking: {N}   Blocked: {N}   Done: {N}
```

Only add a `⚠` line for a task that actually failed the Step 2 comparison,
is `blocked`, or has genuinely no evidence where one would be expected — do
not add a flag line to every task as noise. A clean task gets exactly one
line: id, state, title.

If the user asks for more detail on one specific task, only then read and
show that task's full `assignments`/`evidence`/`history` — do not preemptively
dump that detail for every task in the default view.

## Pitfalls

- Dumping the full `team-tasks.json` content as the default answer — that's
  not concise and buries the one or two things that actually need
  attention.
- Reporting a `checking`/`building` task as fine without doing the Step 2
  snapshot comparison — that silently defeats the "unmanaged changes
  invalidate affected results" requirement this skill exists to satisfy.
- Treating a `blocked` task the same as a healthy `planned` one — always
  surface the `blocked_reason`.
- Caching or remembering a previous run's status instead of re-reading
  `task-state.sh list`/`status` fresh — state can and does move between
  invocations.
- Using this skill to decide whether to complete a task — that judgment,
  and any resulting `complete-gate.sh` run, belongs to `/team:start`'s
  Step 9, not here.

## Verification

- Every task listed by `task-state.sh list` appears in the output exactly
  once.
- Every `building`/`checking` task was checked against a freshly computed
  current snapshot, not skipped.
- A task whose snapshot differs from its recorded one is visibly flagged,
  not silently shown as normal.
- A `blocked` task shows its `blocked_reason`.
- The output is a short per-task summary plus a totals line — not the raw
  JSON file.
