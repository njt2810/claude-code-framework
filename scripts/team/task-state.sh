#!/bin/bash
# Task-state helper — deterministic durable task records and transitions for the
# rebuild framework's lead/builder/verifier delivery loop.
# See docs/rebuild/DESIGN.md ("Delivery model", "Verification contract") and
# docs/rebuild/BUILD_PLAN.md Part 1.2.
#
# This is the ONLY thing that may ever mark a task complete. Per DESIGN.md's
# verification contract, an agent's own claim of "done" is never sufficient —
# only this script's own `complete` transition (checking -> done), invoked as a
# real tool call, constitutes completion.
#
# State lives at .claude/state/team-tasks.json, relative to the current working
# directory. That relative path is what makes state project-isolated: each
# project directory gets its own file, nothing here is keyed by an absolute
# path or shared across projects.
#
# Usage:
#   task-state.sh create <id> <title> [--depends id1,id2,...] [--builder name]
#                 [--verifier name] [--skills a,b] [--risk low|medium|high] [--budget N]
#   task-state.sh start <id>
#   task-state.sh check <id>
#   task-state.sh complete <id> [--staleness-verified yes|no]
#   task-state.sh fail <id> --reason "<why the attempt failed>"
#                 --hypothesis "<what will be different next attempt>"
#   task-state.sh reassess <id> --specialist "<who/what reassessed>"
#                 --finding "<what the reassessment concluded>"
#                 [--additional-budget N] [--resume-state building|checking]
#   task-state.sh block <id> <reason> [--resume-condition text]
#   task-state.sh unblock <id>
#   task-state.sh pause <id> --next-action "<exact next action text>"
#   task-state.sh resume <id>
#   task-state.sh record-external-action <id> --key <idempotency-key>
#                 --description "<what was done>"
#   task-state.sh check-external-action <id> --key <idempotency-key>
#   task-state.sh record-assignment <id> --role builder|verifier --agent-type name
#                 [--skill-hash path:hash,path:hash,...] [--acceptance-text text]
#                 [--code-snapshot text]
#   task-state.sh record-evidence <id> --command "<cmd>" --exit-code N
#                 --tests-total N --tests-skipped N --output-file <path>
#                 [--artifact <path>]... [--cwd <path>]
#   task-state.sh status <id>
#   task-state.sh list
#
# record-assignment (Part 1.3) appends a durable assignment record to the
# task's own "assignments" array -- it does NOT change the task's state.
# It's the mechanism behind scripts/team/assign.sh: durable proof of which
# agent type, which skill file revisions (by content hash, not just path --
# a path alone can't tell you whether the skill changed after assignment),
# and (for verifier assignments) which acceptance criteria and code snapshot
# a given assignment used. Callers should generally go through assign.sh
# rather than calling this subcommand directly, since assign.sh is what
# computes the skill hashes and the code snapshot identity in the first
# place -- this subcommand just records whatever it's given.
#
# record-evidence (Part 1.4) appends a durable evidence record to the task's
# own "evidence" array -- it does NOT change the task's state and it does
# NOT complete the task. See docs/rebuild/DESIGN.md's "Verification
# contract": the runner captures command, cwd, environment identity, time,
# exit status, test totals/skipped, output location, and code snapshot
# identity, and "a commit SHA alone is insufficient when uncommitted changes
# exist." This subcommand is what durably records that evidence; it does not
# itself judge whether the evidence is good enough to complete the task --
# that judgment is scripts/team/complete-gate.sh's job, which reads this
# array and is the ONLY sanctioned path to calling `complete` in the
# intended workflow (see complete-gate.sh's own header for why).
#
# --cwd, --output-file, and every --artifact are resolved to absolute paths
# HERE, at recording time, before being stored: --cwd first (relative to the
# actual invocation directory, same default as when --cwd is omitted), then
# --output-file and each --artifact relative to that now-absolute --cwd. An
# already-absolute path is stored unchanged. This is what makes "verify the
# exact claimed path" well-defined for complete-gate.sh later: without it, a
# relative artifact path's meaning would depend on which directory
# complete-gate.sh happens to be invoked from, which can differ from the
# directory evidence was recorded from.
#
# pause/resume + checkpoints (Part 2.1) implement DESIGN.md's "Wrap up and
# resume": "Pause stops new dispatch, safely handles current activity, and
# persists state. Resume checks actual code and external action state before
# continuing."
#
# `pause` is deliberately shaped exactly like `block` -- allowed only from
# planned/building/checking, records the state it came from (`paused_from`,
# the mirror of `blocked_from`), and `resume` restores that exact state the
# way `unblock` does. The difference from block/unblock is WHY it exists:
# block records an external obstacle, pause records a deliberate stop with a
# durable "here is exactly what to do next" note. `--next-action` is
# therefore REQUIRED, not optional -- a pause with no recorded next action
# cannot satisfy "restart restores the exact next action", which is the whole
# point of the mechanism.
#
# Each pause appends a record to the task's own `checkpoints` array:
# {next_action, code_snapshot, paused_from, paused_at}. It is an ARRAY, not a
# single field, so repeated pause/resume cycles keep their full history
# rather than each one destroying the last.
#
# `resume` does three things beyond restoring the state, and all three are
# part of the contract:
#   1. It prints the recorded next action VERBATIM, so a restarted session
#      gets back the exact next action rather than a paraphrase.
#   2. It CHECKS CURRENT CODE: it recomputes the code snapshot live and
#      compares it against the latest checkpoint's recorded code_snapshot.
#      THREE outcomes, never two:
#        - mismatch  -> a prominent warning naming BOTH snapshots and saying
#          the recorded next action may no longer be valid. It does NOT refuse
#          to resume on drift -- resuming is still the right outcome; the point
#          is that drift is surfaced rather than silently ignored.
#        - match     -> it says so explicitly, so a caller never has to wonder
#          whether the check actually ran.
#        - NOT VERIFIABLE (either snapshot is the "no-git-repository"
#          placeholder, i.e. there is no version control to compare against)
#          -> it says THAT, plainly, and never that the code is unchanged.
#          This case used to print the match message and claim a check that
#          could not run; see the note above compute_snapshot.
#   3. It DURABLY RECORDS that verdict, not just prints it: the history entry
#      `resume` appends carries `drift_detected` (boolean),
#      `staleness_verified` (boolean -- was the comparison possible at all),
#      `pause_snapshot` and `resume_snapshot` alongside the usual from/to/at.
#      Printing alone would not satisfy this subsystem's own founding principle
#      (see this file's opening comment) that only durably-recorded state
#      counts -- stdout can be swallowed by a pipe or never captured, leaving
#      nothing able to prove afterwards whether drift was seen at that resume.
#      `drift_detected: false` with `staleness_verified: false` means "no drift
#      was SEEN because none could be", which is not the same claim as "the
#      code is unchanged"; the pair is what makes the record honest.
#
# `complete` takes the same honesty flag from the other side:
# `complete <id> --staleness-verified yes|no` records `staleness_verified` on
# the checking -> done history entry. complete-gate.sh always passes it (its
# check 6 knows whether it could verify); omitting it writes no key at all,
# which reads as "whoever completed this did not say" -- see the flag's own
# comment at the `complete` subcommand.
#
# External-action idempotency (also Part 2.1) implements DESIGN.md's "Each
# step has an idempotency key so retrying wrap up does not duplicate a PR,
# note, or external action." Completed external actions are recorded in the
# task's own `external_actions` array as {key, description, recorded_at}, and
# a caller consults that array BEFORE performing an external action again.
#
#   record-external-action <id> --key K --description "..."
#     Appends {key, description, recorded_at}. If K is ALREADY recorded for
#     this task it does NOT append a duplicate and EXITS 0, printing that it
#     was already recorded. Rationale for exit 0 rather than an error:
#     re-recording an already-done action is a no-op SUCCESS from the
#     caller's point of view -- the desired end state ("this action is
#     recorded as done exactly once") already holds. Making it an error would
#     push callers to write `|| true` around it, which would then also
#     swallow genuine failures like a missing task. This is consistent with
#     check-external-action below, where "already recorded" is likewise 0.
#     Because both outcomes exit 0, the two are told apart by the OUTPUT's
#     distinct leading word -- "RECORDED-EXTERNAL-ACTION" (newly recorded by
#     this call) vs "ALREADY-RECORDED" (someone got there first). That
#     distinction is load-bearing: it is what makes the record-first idiom
#     below writable, so do not blur those two words.
#
#   check-external-action <id> --key K
#     READ-ONLY (it takes no lock and never writes). It answers exactly one
#     question -- "is this key already recorded for this task?" -- and it
#     answers it with its EXIT STATUS. That is easy to get backwards, and
#     backwards is exactly the duplicate-PR bug this exists to prevent, so
#     the full four-code contract is spelled out here:
#       EXIT 0 => CONFIRMED RECORDED     => SKIP the action, it is already done.
#       EXIT 1 => CONFIRMED NOT RECORDED => PROCEED with the action.
#       EXIT 2 => BAD USAGE (e.g. no --key) => UNDETERMINED, do NOT proceed.
#       EXIT 3 => THE TASK DOES NOT EXIST   => UNDETERMINED, do NOT proceed;
#                 fix the task id and re-check.
#     NONZERO NEVER MEANS "ALREADY DONE". That is the direction that matters
#     for safety and it holds for every nonzero code above.
#     Mnemonic: 0 means "nothing left to do".
#     Exit 3 exists because 1 and "task not found" used to collide: a typo'd
#     task id was then indistinguishable from "not recorded, go ahead", so a
#     caller branching on exit status -- the natural shell idiom, and the one
#     these very docs teach -- would silently PROCEED on a typo and cause the
#     duplicate this subcommand exists to prevent. The two failure directions
#     are asymmetrically costly: a hard error on a bad id is cheap and
#     recoverable, a false PROCEED creates a real external side effect that
#     nothing here rolls back. This is a DELIBERATE local divergence: every
#     other subcommand here reports a missing task as a plain error via
#     require_task and exits 1, which is correct there because no other
#     subcommand's exit status is a SKIP/PROCEED signal a script branches on.
#     All four cases also print a distinguishing line -- ALREADY-RECORDED
#     .../SKIP, NOT-RECORDED .../PROCEED, or an ERROR naming the bad usage or
#     the unknown task id -- so a caller reading output rather than only the
#     exit status can tell them apart too.
#
# WHICH IDIOM TO USE -- record-first is SAFE, check-then-act is ADVISORY ONLY.
# check-external-action is itself free of torn reads, but the natural sequence
# check -> perform the external action -> record is NOT atomic AS A SEQUENCE:
# the side effect happens outside this script's control, in the window between
# the check and the record. Two concurrent callers can both see PROCEED and
# both act, with record-external-action only deduping afterwards -- by which
# point two PRs exist.
#
#   RECORD-FIRST (safe). Call record-external-action BEFORE performing the
#   action, and branch on its OUTPUT rather than its exit status (both cases
#   exit 0 by design, see above); the two cases are distinguished by distinct,
#   greppable leading words:
#     "RECORDED-EXTERNAL-ACTION ..." => you newly recorded it  => DO the action.
#     "ALREADY-RECORDED ..."         => someone already had it => SKIP it.
#   That test-and-append runs inside the single exclusive lock, so of any
#   number of concurrent callers exactly one can ever get the newly-recorded
#   result. It fails toward "skipped" (a crash between the record and the
#   action leaves it recorded but not performed), never toward "duplicated".
#   Use it whenever the action is genuinely externally visible and
#   non-idempotent -- opening a PR, posting a note, sending mail.
#
#   CHECK-THEN-ACT (advisory). Fine when the action is cheap or idempotent
#   anyway so a duplicate costs nothing, or when the caller is strictly
#   sequential and no concurrent caller can exist. Never use it as the only
#   guard on a non-idempotent external side effect under concurrency.
#
# fail/reassess + bounded repair (Part 2.2) implement DESIGN.md's "Recovery
# and learning": "after two unsuccessful repair attempts, request specialist
# reassessment. Enforce a total attempt, time, and cost budget across agents
# and reviews. Every new attempt needs a changed hypothesis supported by
# evidence." The per-task `budget` field (default 2, set at `create` time)
# existed since Phase 1 but had no teeth until this part; `fail` is what gives
# it teeth.
#
#   fail <id> --reason "..." --hypothesis "..."
#     Allowed ONLY from `building` or `checking` -- an attempt can fail during
#     implementation or during verification, but a task that is planned,
#     blocked, paused, done, or already out of budget has no attempt in
#     flight to fail. Increments the monotonic `attempts_used` counter and
#     appends {attempt_number, reason, hypothesis, failed_at, code_snapshot}
#     to the task's own `attempts` array. Then, on the counter:
#       attempts_used <  budget -> state becomes `building` (repair proceeds),
#                                  and the output says how many attempts remain.
#       attempts_used >= budget -> state becomes `needs-reassessment`, and the
#                                  output says the budget is exhausted and that
#                                  only `reassess` can clear it.
#
#     `--hypothesis` is REQUIRED and must DIFFER from the immediately
#     preceding attempt's hypothesis. This is the literal implementation of
#     DESIGN.md's "every new attempt needs a changed hypothesis": retrying an
#     identical theory is the definition of the endless loop this part exists
#     to stop, so it is refused (exit 1, before any write) with a message
#     naming the prior hypothesis verbatim. Comparison is on a normalised form
#     -- case-folded, leading/trailing whitespace trimmed, internal whitespace
#     runs collapsed -- so the cheapest evasions (retype it in caps, add a
#     trailing space) do not slip past. DISCLOSED LIMIT, deliberately not
#     overclaimed: this catches a REPEATED hypothesis, not a MEANINGLESS one.
#     A caller who genuinely reworks the wording while thinking the same thing
#     ("the parser is wrong" -> "the parsing logic is incorrect") passes this
#     check. No string comparison can tell those apart; the total attempt
#     budget, not this check, is what bounds that case.
#
#   reassess <id> --specialist "..." --finding "..." [--additional-budget N]
#            [--resume-state building|checking]
#     Allowed ONLY from `needs-reassessment`, and it is the ONLY way out of
#     that state. Both `--specialist` and `--finding` are REQUIRED: an
#     unexplained budget reset is exactly the "conceal failures" pattern
#     DESIGN.md's "Recovery and learning" forbids, so the reassessment has to
#     say who did it and what they concluded, durably, in the task's own
#     `reassessments` array ({specialist, finding, additional_budget_granted,
#     reassessed_at, attempts_at_reassessment}).
#
#     `--additional-budget N` (N a positive integer) RAISES `budget` by N.
#     Omitting it grants NOTHING, which means the task returns to work still
#     at its cap and will re-enter `needs-reassessment` on the very next
#     `fail`. That is correct and intended, not a bug: a reassessment that
#     concluded nothing new is worth is not a licence for another attempt.
#     Restores `building` by default, or `checking` with `--resume-state
#     checking` -- and `--resume-state checking` is accepted ONLY for a task
#     whose own history shows it actually reached `checking` before it
#     failed. RESTORING means putting a task back where it was; placing one
#     somewhere it has never been is not restoring, and it would record a
#     `needs-reassessment -> checking` promotion with no `building ->
#     checking` transition behind it. This is an audit-integrity rule, NOT a
#     privilege one -- reassess (-> building) plus `check` reaches `checking`
#     in one further unrestricted step regardless; what is refused is the
#     false claim in the history, not the destination.
#
#     `--specialist` and `--finding` (like `fail`'s `--reason` and
#     `--hypothesis`) must carry actual content: whitespace-only is refused
#     exactly as empty is, since "   " records a field that merely LOOKS
#     answered.
#
# CONTROLS THAT CANNOT BE WEAKENED -- the part of this that actually matters,
# per DESIGN.md's "Never learn to remove checks, enlarge permissions, or
# conceal failures":
#   1. `attempts_used` is STRICTLY MONOTONIC. No subcommand here decreases or
#      resets it -- not `reassess`, not anything. There is deliberately no
#      flag anywhere in this script that writes a smaller value to it.
#      Reassessment grants MORE BUDGET; it never erases attempt history.
#   2. `budget` can only ever INCREASE, and only via `reassess
#      --additional-budget N` with N >= 1. `create --budget N` sets the
#      initial value at creation time and no other subcommand touches the
#      field. Adding a budget-lowering or budget-setting flag anywhere else
#      would BE the bypass this clause forbids -- do not add one.
#   3. Repeating the previous hypothesis is refused (see `fail` above).
#   4. Every rejected operation exits BEFORE any write, so the state file is
#      left byte-for-byte unchanged (the same rule the rest of this script
#      already follows, asserted by checksum in tests/task-state-smoke.sh).
#   5. A numeric field that is PRESENT BUT INVALID FAILS CLOSED. `budget` and
#      `attempts_used` are read through read_numeric_field()/
#      require_repair_counters() (see those functions), which distinguish a
#      key that is ABSENT -- a legitimate pre-2.2 legacy record, correctly
#      defaulted -- from a key that is present and null / non-numeric /
#      fractional / negative, which is corruption and is REFUSED. Reading
#      these with jq's `//` operator instead is the specific defect this
#      clause exists to forbid: `//` treats a stored `null` as absent, so
#      `.attempts_used // 0` silently RESETS a real counter to 0 before any
#      guard can see it, and the very next `fail` then writes a lower value
#      and re-issues an attempt_number that is already in the audit trail --
#      i.e. it breaks control #1 above from underneath. Related and for the
#      same reason: `attempts_used` is also refused if it has fallen BEHIND
#      the highest attempt_number already recorded in the task's `attempts`
#      array, which is what stops "delete the key on a task that has real
#      history" from masquerading as a legacy record.
#   6. EVERY OTHER FIELD FAILS CLOSED THE SAME WAY -- strings and arrays, not
#      just the two numbers in #5. Clause #5 was written when only numbers had
#      a hardened read, and that limit was itself the bug: the identical defect
#      then turned up in `hypothesis` (a string), in `external_actions`,
#      `checkpoints`, `attempts` and `depends_on` (arrays), and in `state`,
#      `blocked_from` and `paused_from` (strings again) -- three consecutive
#      reviews, one defect, a different field each time. The rule is now stated
#      once for all of them and implemented once, in the "fail-closed reads of
#      the stored task record" section below: NO VALUE READ OUT OF THE STORED
#      RECORD IS COMPARED, ITERATED, TESTED OR USED IN ARITHMETIC UNTIL IT HAS
#      BEEN THROUGH ONE OF THOSE HELPERS. Absent may default where a safe
#      absent-case genuinely exists (and each site says so in a comment);
#      present-but-wrong-typed always REFUSES, naming the task, the field and
#      the offending value, and changing nothing. Adding a raw `//`, `[]?`,
#      bare `?`, or `jq | [ ... ]` comparison on a decision-bearing field
#      anywhere in this file re-opens that defect and IS the bypass this clause
#      forbids -- do not add one.
#
# `needs-reassessment` is a real stop, not a speed bump: `fail`, `start`,
# `check`, `complete`, `block`, `pause`, `record-assignment`,
# `record-evidence` and `record-external-action` are ALL refused from it, each
# with a message pointing at `reassess`. The three `record-*` subcommands are
# in that list because freezing a task has to freeze its RECORD too: they do
# not change state, so allowing them would not be a completion bypass
# (complete-gate.sh independently requires state `checking`), but it would let
# an audit trail keep accreting on a task that is supposed to be stopped, and
# a record that keeps growing while the task is frozen is not a frozen record.
# `blocked` and `paused` are DELIBERATELY NOT treated the same way: those are
# suspensions, not stops, and both are designed to be resumed into the exact
# state they came from. Recording an assignment, evidence, or an external
# action during one is normal and expected -- the record-first external-action
# idiom above is part of the very wrap-up sequence that `pause` exists to
# support, and a `blocked` task is typically blocked BECAUSE of an external
# action that must be recorded. Refusing there would break the mechanism
# rather than protect it. There is no indirect escape either --
# `unblock` requires `blocked` and `resume` requires `paused`, and neither of
# those states is reachable from `needs-reassessment` because `block` and
# `pause` themselves refuse it. scripts/team/complete-gate.sh refuses it too,
# without needing a change of its own: its check 1 requires state `checking`
# and `needs-reassessment` is not `checking` (proven in
# tests/task-state-smoke.sh against a passing control task, so the refusal is
# not vacuous).
#
# States: planned -> building -> checking -> done
#         (any of planned/building/checking) -> blocked -> (restored state)
#         (any of planned/building/checking) -> paused  -> (restored state)
#         (building|checking) --fail--> building              (attempts remain)
#         (building|checking) --fail--> needs-reassessment    (budget exhausted)
#         needs-reassessment --reassess--> building|checking  (the ONLY exit)
#
# Exit codes: 0 ok
#             1 invalid transition / not found / duplicate id / unmet dependency
#               / a refused repair attempt (unchanged hypothesis)
#               (also: check-external-action's "key NOT recorded, PROCEED")
#             2 bad usage / missing jq dependency
#             3 check-external-action ONLY: the task does not exist, so
#               "already recorded?" could not be determined -- do NOT proceed
#
# Every transition is atomic: written to a temp file in the same directory as
# the state file, then mv'd into place — no command can leave the state file
# half-written. Every rejected/invalid attempt exits before any write happens,
# so the state file is left byte-for-byte unchanged. Every mutating command
# records an ISO-8601 timestamp and appends an entry to that task's own
# transition history array.
#
# Every mutating command (create/start/check/complete/fail/reassess/block/
# unblock/pause/resume/record-assignment/record-evidence/
# record-external-action) also
# holds an exclusive lock across its ENTIRE read-modify-write sequence — not
# just the final atomic_update write — so concurrent invocations (e.g. a lead
# plus several builder/verifier subagents all touching the same project's
# state file at once) are fully serialized instead of racing on stale reads.
# Uses flock when available; falls back to a portable mkdir-based mutex
# otherwise (flock is not reliably present under Git Bash on Windows — verify
# with `command -v flock` rather than assuming). See acquire_lock() below.
#
# No network calls, no model calls. Pure local state management.

set -u

STATE_DIR=".claude/state"
STATE="$STATE_DIR/team-tasks.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (install: winget install jqlang.jq)" >&2
  exit 2
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum is required (used by compute_snapshot for dirty-tree content hashing)" >&2
  exit 2
fi

now_iso() { date -Iseconds; }

# Code snapshot identity: short commit SHA when the tree is clean, or
# "uncommitted, base SHA X, diff Y" when it is dirty, where Y is a short
# prefix of a sha256 hash over the ACTUAL dirty content -- tracked changes
# (via `git diff HEAD`) plus the content of every untracked file -- not just
# a bare clean/dirty flag. A bare flag plus the base SHA is NOT enough: two
# materially different dirty trees off the same base commit would otherwise
# produce the identical snapshot string, so evidence recorded against one
# dirty state would be wrongly accepted as still-fresh after the tree
# changed again without a commit. This is an exact mirror of
# scripts/team/assign.sh's own compute_snapshot() -- kept as a second copy
# rather than sourced, since these are independent CLI entry points, but the
# logic must stay identical to assign.sh's (see docs/rebuild/DESIGN.md,
# "Verification contract": "A commit SHA alone is insufficient when
# uncommitted changes exist."). If you change this, change assign.sh's and
# complete-gate.sh's compute_snapshot to match.
#
# REQUIRES .claude/state/ to be excluded from `git status` in the target
# repo (this repo's own .gitignore already does this, as of Phase 1.2) --
# otherwise this script's own state writes get hashed into the snapshot and
# cause spurious "evidence is stale" failures in complete-gate.sh. See that
# script's compute_snapshot comment for the full explanation.
#
# *** THE "no-git-repository" RETURN IS NOT A CODE IDENTITY. READ THIS BEFORE
# *** COMPARING TWO SNAPSHOTS ANYWHERE.
# When there is no git repository (or git is broken/absent), this function
# CANNOT compute a code identity, and it returns the fixed string
# "no-git-repository" -- the same string every time, for every possible state of
# the code. Two such values comparing EQUAL therefore proves NOTHING about the
# code: rewrite every file in the directory and the two snapshots still match.
# Any comparison that treats that match as "the code is unchanged" is claiming a
# check it did not perform, which is this project's whole defect class (an
# unavailable input becoming a value that means "condition satisfied") wearing a
# different hat. This is a DELIBERATE degradation, not an oversight -- a
# non-git project is legitimate and must still be able to pause, resume and
# complete work -- but every caller that compares snapshots must detect this
# value FIRST and say plainly that nothing was verified. Compare against
# $NO_GIT_SNAPSHOT below rather than retyping the literal.
# The two callers in this file that compare snapshots, both handled:
#   - `resume`'s CODE CHECK          (search "CODE CHECK", ~line 2160)
#   - complete-gate.sh's check 6     (its own copy of this note is above its
#                                     compute_snapshot, and its check 6 says so
#                                     in the GATE PASS line and records
#                                     staleness_verified in the state file)
# This note lives ABOVE the function rather than inside it on purpose: the three
# copies of compute_snapshot's BODY (here, assign.sh, complete-gate.sh) must
# stay byte-for-byte identical, while these preamble comments are already
# per-file. Do not move it into the body.
compute_snapshot() {
  local sha
  sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
  if [ -z "$sha" ]; then
    echo "no-git-repository"
    return
  fi
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    local diff_hash
    diff_hash=$(
      {
        # Tracked changes (staged and unstaged) against the base commit.
        git diff HEAD 2>/dev/null
        # Untracked files: `git diff HEAD` says nothing about these, so list
        # them (the porcelain line itself, which captures the path) and hash
        # their actual content too -- a new/renamed untracked file with
        # different content must produce a different hash, not just "some
        # untracked file changed".
        git status --porcelain --untracked-files=all 2>/dev/null | while IFS= read -r line; do
          echo "$line"
          case "$line" in
            '??'*) f="${line#???}"; [ -f "$f" ] && cat "$f" ;;
          esac
        done
      } | sha256sum | awk '{print $1}' | cut -c1-12
    )
    echo "uncommitted, base SHA $sha, diff $diff_hash"
  else
    echo "$sha"
  fi
}

# The exact string compute_snapshot returns when it could not compute a code
# identity at all. Declared OUTSIDE the function (which must stay byte-identical
# to assign.sh's and complete-gate.sh's copies -- so the literal stays inline
# there) purely so the comparison sites below cannot drift from it by a typo. A
# snapshot equal to this is an ABSENCE of information, never a code identity;
# see the note above compute_snapshot. complete-gate.sh declares the same
# constant, with the same value, for the same reason.
NO_GIT_SNAPSHOT="no-git-repository"

# warn_if_state_not_gitignored -- Part 1.6. Prints ONE advisory warning to
# stderr (never fails the run) if the current directory is a git repository
# AND .claude/state/ is not excluded from `git status` in it. This is purely
# advisory: it must never block a legitimate record-evidence run, so it never
# affects this script's exit code.
#
# The risk it names: compute_snapshot() above (and complete-gate.sh's
# identical copy) hashes `git status --porcelain` / `git diff HEAD` output to
# build the dirty-tree code_snapshot identity. If .claude/state/ is not
# gitignored, this script's own bookkeeping writes to
# .claude/state/team-tasks.json (including the very evidence-write this call
# is about to make) show up as tracked/untracked changes and get hashed into
# that snapshot too -- so the snapshot recorded here at evidence time and the
# snapshot recomputed later at gate time can differ EVEN THOUGH NO REAL CODE
# CHANGED, causing complete-gate.sh's check 6 to reject genuinely-fresh
# evidence as stale. See compute_snapshot()'s own comment above and
# complete-gate.sh's identical copy for the fuller explanation.
#
# "one-time-per-run": guarded by _STATE_GITIGNORE_WARNED so repeated calls in
# one script invocation only ever print once (record-evidence, the only
# caller today, calls this once, but the guard keeps that safe if that ever
# changes). Keep this function's detection logic and wording identical to
# complete-gate.sh's copy.
_STATE_GITIGNORE_WARNED=""
warn_if_state_not_gitignored() {
  [ -n "$_STATE_GITIGNORE_WARNED" ] && return
  _STATE_GITIGNORE_WARNED=1

  # Not a git repository at all -> nothing to warn about (git rev-parse
  # exits non-zero with a "not a git repository" fatal on stderr in that
  # case; discard it, this is a routine, expected outcome here, not an
  # error).
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

  # `git check-ignore -q PATH` exits 0 if PATH is excluded (ignored), 1 if
  # it is not excluded, and >1 on a real error. Query a path CLEARLY NESTED
  # under .claude/state/ (not the bare directory name) -- a directory-only
  # gitignore pattern like ".claude/state/" only reliably matches through
  # check-ignore once something actually exists at or under that path; a
  # bare, not-yet-existing .claude/state directory can spuriously report
  # exit 1 ("not ignored") even when the pattern would in fact ignore it
  # once created. A nested probe path sidesteps this regardless of whether
  # .claude/state itself exists yet. Only the "not excluded" case (exit
  # exactly 1) should warn -- a real error (e.g. run outside a usable work
  # tree, such as a bare repository) means we can't determine the answer,
  # so stay silent rather than guessing.
  git check-ignore -q .claude/state/.gitcheck-probe 2>/dev/null
  rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "WARNING: .claude/state/ is not excluded from 'git status' in this repository. task-state.sh's own bookkeeping writes to .claude/state/team-tasks.json will then show up as tracked/untracked changes and get hashed into compute_snapshot()'s dirty-tree code_snapshot identity, which can make genuinely-fresh evidence look stale (spurious 'evidence is stale' failures in complete-gate.sh's check 6) even though no real code changed. Fix: add '.claude/state/' to this repository's .gitignore." >&2
  fi
}

# is_absolute_path <path> -- true if <path> is already absolute. Covers both
# POSIX/MSYS-style ("/..." ) and Windows drive-letter style ("C:/..." or
# "C:\...", realistic input on this project's primary platform, Git Bash on
# Windows -- see assign.sh's own comment on colon-containing skill paths for
# the same platform reality).
is_absolute_path() {
  case "$1" in
    /*) return 0 ;;
    [A-Za-z]:[/\\]*) return 0 ;;
    *) return 1 ;;
  esac
}

# resolve_path <path> <base-dir> -- returns an absolute path. If <path> is
# already absolute, returns it unchanged; otherwise joins it onto <base-dir>
# (which must itself already be absolute -- callers resolve base-dir first).
# Deliberately does NOT use `realpath`: that's a GNU coreutils extension not
# guaranteed present in every environment this needs to run in (this repo's
# other path handling, e.g. assign.sh's and complete-gate.sh's `HERE="$(cd
# "$(dirname "$0")" && pwd)"`, resolves absolute paths via `cd ... && pwd`
# rather than `realpath` for the same portability reason). Also deliberately
# does NOT require <path> to exist on disk and does NOT collapse "." or ".."
# segments -- a claimed artifact may not exist yet (recording is not
# judging; see the ghost-artifact regression test), and any "." / ".."
# segments left in a joined path are resolved correctly by the OS the same
# way for `[ -f ]` / `[ -s ]` as for any other path, so textual collapsing
# would only be cosmetic, not load-bearing, and skipping it keeps this
# dependency-free.
resolve_path() {
  local path="$1" base="$2"
  if is_absolute_path "$path"; then
    echo "$path"
  else
    echo "${base%/}/$path"
  fi
}

# Comma-separated string -> compact JSON array. Empty string -> [].
csv_to_json_array() {
  local csv="$1"
  if [ -z "$csv" ]; then
    echo '[]'
    return
  fi
  jq -R -c 'split(",") | map(select(length > 0))' <<< "$csv"
}

# Create .claude/state/ and an empty team-tasks.json skeleton if neither exists
# yet. Only ever called from `create`, and only actually writes when the file
# is truly absent — it never fires against an already-populated state file, so
# it never counts as a mutation on an otherwise-rejected create.
ensure_state_file() {
  mkdir -p "$STATE_DIR"
  [ -f "$STATE" ] || echo '{"tasks":{}}' > "$STATE"
}

# Acquire an exclusive lock covering the whole duration of the current
# mutating command, released automatically when this process exits (normal
# exit, error exit, or signal). Two locking strategies:
#
#   1. flock, when present: opens $STATE_DIR/.team-tasks.lock on fd 9 and
#      blocks (up to LOCK_WAIT_SECS) until an exclusive lock is granted. The
#      lock is released the moment fd 9 closes, which happens automatically
#      when this script process exits — no explicit unlock needed.
#
#   2. Portable mkdir-based mutex, when flock is unavailable: `mkdir` is
#      atomic even on network/shared filesystems and works identically on
#      Linux CI runners and Windows Git Bash (unlike flock, which is not
#      reliably present under Git Bash). Only one concurrent caller can
#      successfully mkdir the lock directory; everyone else retries with a
#      short sleep until they succeed or LOCK_WAIT_SECS is exhausted. An EXIT
#      trap rmdir's the lock directory so it's released whenever this process
#      ends, including on Ctrl-C.
#
# Either way, the lock is held for the FULL read-modify-write sequence of the
# calling command (duplicate/dependency checks through atomic_update), not
# just the final write — that's what prevents the lost-update race where two
# concurrent invocations both read the same pre-update state and the second
# write silently clobbers the first.
LOCK_WAIT_SECS=30

acquire_lock() {
  mkdir -p "$STATE_DIR"
  if command -v flock >/dev/null 2>&1; then
    local lock_file="$STATE_DIR/.team-tasks.lock"
    exec 9>"$lock_file"
    if ! flock -w "$LOCK_WAIT_SECS" 9; then
      echo "ERROR: could not acquire task-state lock within ${LOCK_WAIT_SECS}s (another invocation may be stuck on: $lock_file)" >&2
      exit 1
    fi
  else
    local lock_dir="$STATE_DIR/.team-tasks.lockdir"
    local tries=0
    local max_tries=$((LOCK_WAIT_SECS * 5)) # 0.2s per try
    while ! mkdir "$lock_dir" 2>/dev/null; do
      tries=$((tries + 1))
      if [ "$tries" -ge "$max_tries" ]; then
        echo "ERROR: could not acquire task-state lock within ${LOCK_WAIT_SECS}s (another invocation may be stuck on: $lock_dir)" >&2
        exit 1
      fi
      sleep 0.2
    done
    trap 'rmdir "'"$lock_dir"'" 2>/dev/null' EXIT INT TERM
  fi
}

# Atomically replace $STATE with the result of running `jq "$@"` over it.
# The temp file is created inside $STATE_DIR so `mv` is a same-filesystem
# rename (not a copy), which is what makes the replacement atomic.
atomic_update() {
  local tmp
  tmp=$(mktemp "$STATE_DIR/.team-tasks.XXXXXX") || {
    echo "ERROR: failed to create temp file for atomic write" >&2
    exit 1
  }
  if ! jq "$@" "$STATE" > "$tmp"; then
    rm -f "$tmp"
    echo "ERROR: internal jq failure while updating state; state file left unchanged" >&2
    exit 1
  fi
  mv "$tmp" "$STATE"
}

# NOTE: the old `task_state_of` lived here. It has been replaced by
# read_task_state / require_task_state further down, in the "fail-closed reads
# of the stored task record" section -- see that section's comment for what its
# `.tasks[$id].state // "missing"` did to the needs-reassessment freeze.

# reassessment_required_error <id> <what-was-attempted> -- the single refusal
# message every subcommand uses when it is asked to act on a task whose
# repair-attempt budget is exhausted (state `needs-reassessment`). Shared
# rather than copy-pasted per subcommand for one reason: `needs-reassessment`
# is meant to be a real stop, and a real stop has to name its ONE exit
# consistently no matter which door the caller tried. Prints only -- the
# caller exits 1 itself, keeping the "rejected operations exit before any
# write" rule visible at each call site rather than hidden in here.
reassessment_required_error() {
  echo "ERROR: task '$1' is in state 'needs-reassessment', cannot $2 — its repair-attempt budget is exhausted. The ONLY way out of this state is: task-state.sh reassess $1 --specialist \"<who/what reassessed>\" --finding \"<what the reassessment concluded>\" [--additional-budget N]" >&2
}

# require_nonblank <flag-label> <value> <why-it-matters> -- guard for the free-
# text flags whose values are DURABLY RECORDED and later read by a human
# deciding whether an attempt or a reassessment was legitimate (`--reason`,
# `--hypothesis`, `--specialist`, `--finding`). A bare `[ -n ]` check is not
# enough: " " is non-empty but records exactly as much accountability as ""
# does, i.e. none, while looking like a supplied value in the stored record.
# Whitespace-only is therefore refused the same way empty is (exit 2, bad
# usage, before any write). "Whitespace" here is the shell's own [:space:]
# class, so tabs and newlines are caught too, not just spaces.
require_nonblank() {
  case "$2" in
    *[![:space:]]*) return 0 ;;
  esac
  echo "ERROR: $1 is required and must not be empty or whitespace-only ($3)" >&2
  exit 2
}

# --- fail-closed reads of the stored task record -----------------------------
#
# THE DEFECT CLASS THIS SECTION EXISTS FOR. Read this before "simplifying" any
# read below back into a `//` chain, a `[]?`, a bare `?`, a `2>/dev/null` on a
# jq whose output is then compared, or a `[ ... ]` test on a raw `jq -r`.
#
# The shape, precisely: A VALUE THAT CANNOT BE PARSED IS SILENTLY CONVERTED
# INTO A VALUE THAT MEANS "THE CONDITION WAS NOT MET", SO A SAFETY CHECK
# BECOMES A NO-OP INSTEAD OF AN ERROR. Three spellings of the same bug, all
# three of which were live in this file:
#
#   1. `//` swallows a stored null.  `.[-1].hypothesis // ""` turned a corrupt
#      previous hypothesis into "", and since an incoming hypothesis is already
#      validated non-blank, `"" == it` could never be true -- so the
#      changed-hypothesis control (this file's control #3, "cannot be
#      weakened") passed unconditionally, forever, and the same theory could be
#      retried without limit.
#   2. `[]?` / `?` swallow a type error.  `.depends_on[]?` on a `depends_on`
#      corrupted to a bare string yielded NO dependencies, so `start` reported
#      no unmet dependencies and dispatched a task whose dependency was still
#      `planned`. Same spelling, same silence, as `.artifacts[]?` in
#      complete-gate.sh. `map(select(.key == $key))` over an
#      `external_actions` array holding one non-object entry errored out
#      entirely, leaving an empty result: `check-external-action` then answered
#      NOT-RECORDED/PROCEED for a key that WAS recorded, and
#      `record-external-action` appended a duplicate. A false PROCEED there is
#      the duplicate-PR bug the whole mechanism exists to prevent.
#   3. an unvalidated value reaching `[ ... ]`.  `checkpoints | length` on a
#      `checkpoints` corrupted to `true` made jq error, leaving CP_COUNT empty;
#      `[ "" -eq 0 ]` then printed "integer expression expected" and returned
#      2, and an `if` reads ANY non-zero return as "condition not met", so
#      `resume`'s no-checkpoint guard was SKIPPED rather than failed.
#
# THE RULE: no value read out of the stored task record is compared, iterated,
# tested or used in arithmetic until it has been through one of the helpers in
# this section (or read_numeric_field / require_repair_counters below, which
# are the same discipline applied to the two numeric counters and predate it).
# They are the single implementation of "is this value usable at all", and they
# FAIL CLOSED.
#
# ABSENT vs PRESENT-BUT-WRONG is the distinction that makes this safe to apply
# everywhere, and it is inherited from read_numeric_field:
#
#   Key ABSENT entirely (or null where the schema has always written a value
#   only when it had one) -> may be a legitimate legacy record, from before the
#   field existed. Defaulting is correct WHERE A SAFE ABSENT-CASE GENUINELY
#   EXISTS, and each site below says in a comment which case it is in.
#   Key PRESENT but of the wrong type / null / empty where the schema always
#   writes content -> corruption or a partial or hand write. REFUSE: name the
#   task, the field and the offending value, and change nothing.
#
# WHY A SHARED FAMILY AND NOT PER-SITE CHECKS. This class has now been found
# three separate times, in a different field each time (the numeric counters,
# then the gate's evidence fields, then the three fields below), because the
# hardening lived in ONE helper that only covered NUMBERS. Strings and arrays
# had no equivalent, so every string and array read stayed ad-hoc and each new
# one re-introduced the defect. Extending the family is what stops the fourth.
#
# WHY THESE MUST NEVER BE CALLED INSIDE $( ). Their refusal path is `exit`. An
# `exit` inside a command substitution kills only the subshell and leaves the
# caller running on with an empty value -- which IS the silent-degradation
# class they exist to make impossible. They therefore publish their result in a
# global rather than printing it. Same convention, same reason, as
# read_numeric_field below and complete-gate.sh's require_evidence_* helpers.
#
# WHAT THIS SECTION COVERS, AND THE ONE INSTANCE THAT LIVES OUTSIDE IT.
# This section covers reads of the STATE FILE. The same defect class had one
# further instance in a read of the ENVIRONMENT, and it is now fixed -- but
# fixed elsewhere, so look for it there rather than here:
# compute_snapshot()'s `git rev-parse ... 2>/dev/null || echo ""` degrades a
# missing or broken git into the constant "no-git-repository". `resume` and
# complete-gate.sh's check 6 then compared that constant against itself, matched
# every time, and reported the code as unchanged / the evidence as fresh having
# verified nothing -- the same shape (an unavailable value becoming an answer
# that means "the condition is satisfied"), and worse than a skipped check
# because the OUTPUT asserted a check that could not run.
# THE FIX IS AT THE COMPARISON SITES, NOT IN compute_snapshot. The function
# still returns the placeholder (a non-git project is legitimate and must still
# be able to work), and its three copies here, in assign.sh and in
# complete-gate.sh stay byte-for-byte identical. What changed is that every
# caller comparing two snapshots now detects the placeholder FIRST, refuses to
# claim a verification it could not perform, and records that verdict durably:
#   - `resume`'s CODE CHECK -- third "NOT VERIFIED" outcome, and
#     `staleness_verified` on the resume history entry.
#   - complete-gate.sh check 6 -- warns, passes WITHOUT staleness verification
#     rather than reporting a snapshot match, and records staleness_verified
#     via `complete --staleness-verified no`.
# See the note above compute_snapshot for the rule, and $NO_GIT_SNAPSHOT for the
# constant every such comparison must test against.
#
# Two further reads are deliberately NOT hardened because they gate nothing:
# `status` and `list`. Both say so in a comment at their own site.
#
# WHY EVERY case STATEMENT BELOW HAS A CATCH-ALL. The verdict reads pass
# `2>/dev/null` so jq's own raw error text does not reach the user in place of
# a real message. That is only safe because an EMPTY verdict (jq failed
# outright) falls through to a `*)` branch that REFUSES. Never add a verdict
# read here without one.

# STATE_FAIL_EXIT -- the exit code every refusal in this section uses.
#
# It is 1 everywhere EXCEPT check-external-action, which sets it to 3 before
# its first read. There, exit 1 is the documented "CONFIRMED NOT RECORDED ->
# PROCEED WITH THE EXTERNAL ACTION" answer (see this file's header), so a
# corrupt record refusing with 1 would tell the caller to go ahead and open the
# PR -- turning a corruption refusal into the very duplicate this subcommand
# exists to prevent. 3 is that subcommand's UNDETERMINED / do-NOT-proceed code.
STATE_FAIL_EXIT=1

# state_field_fail <id> <field> <what-this-read-needs> <what-was-wrong>
# The single refusal message every helper below shares, so the wording and the
# "corruption, not 'condition not met'" framing cannot drift between them.
state_field_fail() {
  echo "ERROR: task '$1' has an unusable '$2' field in the state file (got: $4) — this read needs $3. Refusing this operation — nothing was changed." >&2
  echo "  A value that is PRESENT but cannot be parsed as that is treated as CORRUPTION, never as 'the condition was not met'. Silently degrading it is exactly how a guard becomes a no-op and fails OPEN, which is why this read is checked rather than defaulted." >&2
  echo "  The state file may have been hand-edited or partially written — only task-state.sh should write it." >&2
  exit "$STATE_FAIL_EXIT"
}

# read_task_state <id> -> TASK_STATE_VALUE ("missing" when the task genuinely
# does not exist), plus STATE_FILE_PRESENT for the caller's error wording.
#
# This replaces the old `task_state_of`, whose `.tasks[$id].state // "missing"`
# was the single most load-bearing unguarded read in the file: EVERY subcommand
# branches on its result. A `state` corrupted to an ARRAY rendered through
# `jq -r` as a multi-line JSON blob that matched none of the state names, which
# read as "this task is not in needs-reassessment" and let the record-*
# subcommands write to a task that is supposed to be frozen. The old
# `// "missing"` also could not tell a task that does not exist from a task
# whose record is a string, a number or null -- and for a non-object record jq
# errored out entirely, leaving the caller with an empty state that the
# follow-on comparison reported as `state ''`.
#
# ABSENT-CASE: a task id with no entry under .tasks (or no .tasks at all) is
# genuinely "missing" -- the normal not-found path, not corruption. Everything
# else that is not a non-empty JSON string is corruption.
TASK_STATE_VALUE=""
STATE_FILE_PRESENT=""
read_task_state() {
  local id="$1" verdict
  if [ ! -f "$STATE" ]; then
    STATE_FILE_PRESENT=""
    TASK_STATE_VALUE="missing"
    return 0
  fi
  STATE_FILE_PRESENT=1
  verdict=$(jq -r --arg id "$id" '
    if type != "object" then "bad:the state file root is not a JSON object — it is " + (type)
    elif (has("tasks") | not) or (.tasks == null) then "missing"
    elif (.tasks | type) != "object" then "bad:.tasks is not a JSON object — " + (.tasks | tojson | .[0:200])
    elif (.tasks | has($id) | not) then "missing"
    elif (.tasks[$id] | type) != "object" then "bad:the task record itself is not a JSON object — " + (.tasks[$id] | tojson | .[0:200])
    elif (.tasks[$id] | has("state") | not) then "bad:the task record carries no state field at all"
    elif (.tasks[$id].state | type) != "string" then "bad:" + (.tasks[$id].state | tojson | .[0:200])
    elif (.tasks[$id].state | length) == 0 then "bad:an empty string"
    else "ok:" + .tasks[$id].state
    end
  ' "$STATE" 2>/dev/null)

  case "$verdict" in
    missing) TASK_STATE_VALUE="missing"; return 0 ;;
    ok:*)    TASK_STATE_VALUE="${verdict#ok:}"; return 0 ;;
    bad:*)   state_field_fail "$id" "state" "a non-empty JSON string naming the task's current state" "${verdict#bad:}" ;;
    *)       state_field_fail "$id" "state" "a non-empty JSON string naming the task's current state" "unreadable — the state file could not be parsed as JSON" ;;
  esac
}

# require_task_state <id> -> TASK_STATE_VALUE. Refuses if the state file or the
# task is missing, or if the record is corrupt. MUST NOT be called in $( ).
#
# This replaces `CUR_STATE=$(require_task "$ID")`, which was a latent instance
# of the same class in a different disguise: require_task's not-found path is
# an `exit`, and inside a command substitution that killed only the subshell,
# so CUR_STATE became "" and the script carried on. Every caller happened to
# refuse anyway on the follow-on state comparison, but it refused with the
# nonsense message "task 'x' is in state ''" -- i.e. the not-found guard was
# already degrading into "the condition was not met" and only the next check
# saved it. Called directly (not in $( )), the exit propagates properly.
#
# It also validates `history` here, centrally: every mutating subcommand
# appends to that array, and this is the one place they all pass through.
# (read_task_state deliberately does NOT, so `start`'s per-dependency probe
# below does not refuse because some OTHER task's history is malformed.)
require_task_state() {
  read_task_state "$1"
  if [ "$TASK_STATE_VALUE" = "missing" ]; then
    if [ -z "$STATE_FILE_PRESENT" ]; then
      echo "ERROR: task '$1' not found (no tasks recorded yet)" >&2
    else
      echo "ERROR: task '$1' not found" >&2
    fi
    exit "$STATE_FAIL_EXIT"
  fi
  require_appendable_array "$1" "history"
}

# require_appendable_array <id> <field> -- the weakest of the array guards, for
# an array this script only ever APPENDS to and never reads a decision out of
# (history, and the record-* arrays). Absent or null is a legitimate legacy
# record and is accepted (the `// []` in the write itself starts one); a
# PRESENT non-array is refused here, by name, rather than being left to blow up
# inside atomic_update's jq as an anonymous "internal jq failure".
require_appendable_array() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "ok"
      elif ($t[$f] | type) != "array" then "bad:not a JSON array — " + ($t[$f] | tojson | .[0:200])
      else "ok"
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok)    return 0 ;;
    bad:*) state_field_fail "$id" "$field" "a JSON array (or no such key at all, on a legacy record)" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "a JSON array (or no such key at all, on a legacy record)" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_object_array <id> <field> -> ARRAY_LENGTH
#
# For every array this script reads a DECISION out of: attempts (the
# changed-hypothesis control and the monotonic-counter control),
# checkpoints (resume's next action), external_actions (idempotency).
#
# ABSENT-CASE: no such key, or null, is a legitimate legacy/never-written
# record and yields length 0 -- which is exactly what "no previous attempt" /
# "no checkpoint" / "nothing recorded yet" already mean, so the existing
# behaviour for those records is unchanged. PRESENT but not an array, or an
# array holding an entry that is not a JSON object, is corruption and refuses:
# `map(select(.key == ...))`, `.[-1].hypothesis` and friends all silently
# produce nothing on such an array, and "nothing" is precisely the answer that
# turns each of those guards off.
ARRAY_LENGTH=""
require_object_array() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "ok:0"
      elif ($t[$f] | type) != "array" then "bad:not a JSON array — " + ($t[$f] | tojson | .[0:200])
      else ([$t[$f][] | select(type != "object")]) as $bad
        | if ($bad | length) > 0
          then "bad:the array holds entries that are not JSON objects — " + ($bad | tojson | .[0:200])
          else "ok:" + ($t[$f] | length | tostring)
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      ARRAY_LENGTH="${verdict#ok:}"
      # Belt and braces, the same reason read_numeric_field does it: a length
      # that does not reach bash as a plain run of digits would be mangled by
      # the arithmetic comparisons the callers do on it.
      case "$ARRAY_LENGTH" in
        ''|*[!0-9]*)
          state_field_fail "$id" "$field" "an array whose length renders as a plain integer" "a length of '$ARRAY_LENGTH'" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "$field" "an array of JSON objects (or no such key at all, on a legacy record)" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an array of JSON objects (or no such key at all, on a legacy record)" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_string_array <id> <field> -> ARRAY_LENGTH
# Same contract for an array of plain strings. Used for depends_on, whose
# `[]?` iteration silently yielded nothing when the field was not iterable at
# all -- and "no dependencies" is the answer that lets `start` dispatch.
# ABSENT-CASE: no key / null means no dependencies, which is what a task
# created without --depends legitimately has.
require_string_array() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "ok:0"
      elif ($t[$f] | type) != "array" then "bad:not a JSON array — " + ($t[$f] | tojson | .[0:200])
      else ([$t[$f][] | select((type != "string") or (length == 0))]) as $bad
        | if ($bad | length) > 0
          then "bad:the array holds entries that are not non-empty strings — " + ($bad | tojson | .[0:200])
          else "ok:" + ($t[$f] | length | tostring)
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      ARRAY_LENGTH="${verdict#ok:}"
      case "$ARRAY_LENGTH" in
        ''|*[!0-9]*)
          state_field_fail "$id" "$field" "an array whose length renders as a plain integer" "a length of '$ARRAY_LENGTH'" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "$field" "an array of non-empty strings (or no such key at all, on a legacy record)" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an array of non-empty strings (or no such key at all, on a legacy record)" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_entry_string <id> <field> <index> <key> -> ENTRY_STRING
#
# The entry at <index> of <field> must be a JSON object carrying a NON-EMPTY
# STRING at <key>. There is deliberately no absent-case here: these are fields
# the writing subcommand has always written with content in the same atomic
# object as the entry itself (`fail` always writes hypothesis, `pause` always
# writes next_action and code_snapshot), so a missing or null one is as much a
# sign of a hand-edited record as a wrong-typed one. Call require_object_array
# on <field> first -- this assumes the array shape is settled and <index> is in
# range.
ENTRY_STRING=""
require_entry_string() {
  local id="$1" field="$2" index="$3" key="$4" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" --argjson i "$index" --arg k "$key" '
    (.tasks[$id][$f][$i]) as $e
    | if ($e | type) != "object" then "bad:entry \($i) is not a JSON object — " + ($e | tojson | .[0:200])
      elif ($e | has($k) | not) then "bad:entry \($i) carries no \"\($k)\" field at all"
      elif ($e[$k] | type) != "string" then "bad:entry \($i)'"'"'s \"\($k)\" is " + ($e[$k] | tojson | .[0:200])
      elif ($e[$k] | length) == 0 then "bad:entry \($i)'"'"'s \"\($k)\" is an empty string"
      else "ok:" + $e[$k]
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)  ENTRY_STRING="${verdict#ok:}"; return 0 ;;
    bad:*) state_field_fail "$id" "$field" "an entry carrying a non-empty string '$key'" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an entry carrying a non-empty string '$key'" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_entry_number <id> <field> <index> <key> -> ENTRY_NUMBER
# The same contract for a non-negative integer entry field (attempt_number).
ENTRY_NUMBER=""
require_entry_number() {
  local id="$1" field="$2" index="$3" key="$4" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" --argjson i "$index" --arg k "$key" '
    (.tasks[$id][$f][$i]) as $e
    | if ($e | type) != "object" then "bad:entry \($i) is not a JSON object — " + ($e | tojson | .[0:200])
      elif ($e | has($k) | not) then "bad:entry \($i) carries no \"\($k)\" field at all"
      else $e[$k] as $v
        | if ($v | type) == "number" and $v >= 0 and $v == ($v | floor)
          then "ok:" + ($v | tostring)
          else "bad:entry \($i)'"'"'s \"\($k)\" is " + ($v | tojson | .[0:200])
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      ENTRY_NUMBER="${verdict#ok:}"
      case "$ENTRY_NUMBER" in
        ''|*[!0-9]*)
          state_field_fail "$id" "$field" "an entry whose '$key' renders as a plain non-negative integer" "$ENTRY_NUMBER" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "$field" "an entry carrying a non-negative integer '$key'" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "$field" "an entry carrying a non-negative integer '$key'" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_restorable_state <id> <field> -> RESTORE_STATE ("missing" when the
# field is absent or null, which is the caller's own "nothing to restore to"
# refusal, unchanged).
#
# For blocked_from and paused_from. This one is NOT merely a type check, and it
# is the most permissive read that was in this file: `unblock` restored
# whatever string it found, so a `blocked_from` hand-set to "done" moved the
# task straight to `done` -- past `checking`, past complete-gate.sh, past the
# entire verification contract, with `unblock` reporting success. `block` and
# `pause` only ever record planned/building/checking (they refuse every other
# source state), so restricting the restore target to exactly those three is
# behaviour-preserving for every honestly-written record and closes the
# completion bypass for every other one. A non-string, or a string naming any
# other state, is refused.
RESTORE_STATE=""
require_restorable_state() {
  local id="$1" field="$2" verdict
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | has($f) | not) or ($t[$f] == null) then "missing"
      elif ($t[$f] | type) != "string" then "bad:" + ($t[$f] | tojson | .[0:200])
      elif ($t[$f] | length) == 0 then "bad:an empty string"
      elif ((["planned", "building", "checking"] | index($t[$f])) == null)
        then "bad:the string \"\($t[$f])\", which is not a state \($f) is ever written with (only planned, building or checking are)"
      else "ok:" + $t[$f]
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    missing) RESTORE_STATE="missing"; return 0 ;;
    ok:*)    RESTORE_STATE="${verdict#ok:}"; return 0 ;;
    bad:*)   state_field_fail "$id" "$field" "one of the states it is ever recorded with: planned, building or checking" "${verdict#bad:}" ;;
    *)       state_field_fail "$id" "$field" "one of the states it is ever recorded with: planned, building or checking" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# --- numeric state-field reads on the mutation paths -------------------------
#
# read_numeric_field <id> <field-name> <default-when-absent>
#   Resolves ONE numeric field of a task and leaves the result in the global
#   NUMERIC_FIELD_VALUE. It does NOT print the value and MUST NOT be called in
#   a command substitution: its refusal path is `exit 1`, and an `exit` inside
#   `$( )` only kills the subshell, leaving the caller running on with an
#   empty value -- which for these fields is precisely the silent-reset class
#   of bug this function exists to make impossible.
#
#   THE DISTINCTION THIS FUNCTION EXISTS FOR -- "absent" and "present but
#   invalid" are genuinely different and must behave differently:
#
#     Key ABSENT entirely  -> a legitimate pre-2.2 legacy record (tasks
#                             created before `attempts_used` / `budget`
#                             existed genuinely have no such key). Defaulting
#                             is correct, and stays correct.
#     Key PRESENT but null, non-numeric, fractional or negative
#                          -> corruption or a partial/hand write. FAIL CLOSED:
#                             refuse, name the task, the field and the
#                             offending value, and change nothing.
#
#   Why this is not done with jq's `//` default operator: `//` treats `null`
#   (and `false`) as ABSENT, so `.attempts_used // 0` collapses a *stored*
#   null to 0 before any guard can see it. A validator downstream of `//`
#   then only ever validates the already-defaulted value and structurally
#   cannot catch the corruption -- it reports a healthy "0" for a task that
#   really is at attempt 2, the counter goes BACKWARDS on the next write, and
#   the attempts array ends up with a duplicate attempt_number. The
#   presence test therefore has to be `has(...)`, and the validation has to
#   run against the RAW value, before any defaulting. Do not "simplify" this
#   back into a `//` chain.
NUMERIC_FIELD_VALUE=""
read_numeric_field() {
  local id="$1" field="$2" default="$3" verdict invalid_desc
  verdict=$(jq -r --arg id "$id" --arg f "$field" '
    .tasks[$id] as $t
    | if ($t | type) != "object" then "shape:" + ($t | tojson | .[0:200])
      elif ($t | has($f) | not) then "absent"
      else ($t[$f]) as $v
        | if ($v | type) == "number" and $v >= 0 and $v == ($v | floor)
          then "ok:" + ($v | tostring)
          else "bad:" + ($v | tojson) end
      end
  ' "$STATE" 2>/dev/null)

  case "$verdict" in
    shape:*)
      # The task record is not a JSON object at all, so there is no field here
      # to be absent OR invalid. Refuse via the shared message rather than
      # falling through to the field-specific one below, which would blame the
      # field for a record-level problem. (read_task_state normally catches
      # this first; this is the belt to its braces, and it is what stops an
      # empty verdict from a jq that errored out being read as "not absent,
      # not ok" and landing on a message with an empty offending value.)
      state_field_fail "$id" "$field" "a task record that is a JSON object" "${verdict#shape:}"
      ;;
    absent)
      NUMERIC_FIELD_VALUE="$default"
      return 0
      ;;
    ok:*)
      NUMERIC_FIELD_VALUE="${verdict#ok:}"
      # Belt and braces: a value can satisfy jq's numeric checks above and
      # still not render as a plain run of digits by the time it reaches bash
      # -- exponent form ("1E+30"), or a decimal spelling of a whole number
      # ("0.0"), depending on the jq version. Bash arithmetic would mangle
      # either, so anything that is not plain digits here is refused too.
      case "$NUMERIC_FIELD_VALUE" in
        ''|*[!0-9]*)
          echo "ERROR: task '$id' has a '$field' field that is numeric in the state file but does not render as a plain non-negative integer (got: $NUMERIC_FIELD_VALUE); it cannot be used as an attempt counter or budget. Refusing this operation — nothing was changed." >&2
          exit 1
          ;;
      esac
      return 0
      ;;
    bad:*)
      invalid_desc="${verdict#bad:}"
      ;;
    *)
      # EXPLICIT CATCH-ALL, per this section's own rule ("why every case
      # statement below has a catch-all"). This branch is reached when the
      # verdict is EMPTY or is none of the four words this read can produce --
      # i.e. jq itself failed, and `2>/dev/null` swallowed its error text. It
      # already exited 1 (safe) before this branch existed, because an
      # unmatched `bad:*` prefix strip left the message intact -- but it
      # reported the offending value as a BLANK "(got: )", which reads like a
      # field that is present and empty rather than a state file that could not
      # be parsed at all. Same refusal, honest description.
      invalid_desc="unreadable — the state file could not be parsed as JSON, so no verdict was produced for this field"
      ;;
  esac

  echo "ERROR: task '$id' has an invalid '$field' field in the state file (got: $invalid_desc); it is PRESENT but is not a non-negative integer, so it cannot be a trustworthy attempt counter or budget. Refusing this operation — nothing was changed." >&2
  echo "  A field that is present-but-invalid is treated as CORRUPTION, not as 'unset': defaulting it to 0 here would silently reset a real attempt counter and let the same attempt_number be issued twice. (A genuinely legacy record, created before this field existed, has no '$field' key at all and is still accepted.)" >&2
  echo "  The state file may have been hand-edited or partially written — only task-state.sh should write it." >&2
  exit 1
}

# require_task_presence <id> -> TASK_PRESENCE (yes|no). Answers ONLY "does an
# entry exist under this id", which is what `create`'s duplicate-id guard and
# its dependency-exists guard each need -- neither of them can use
# read_task_state, because a record that exists but is corrupt must still count
# as EXISTING for the duplicate guard (refusing to overwrite it is the safe
# answer) rather than being reported as usable.
#
# The read it replaces was `.tasks[$id] // empty`, and `//` treats a stored
# `null` (and `false`) as absent: a task whose record had been corrupted to
# null read as "does not exist", so `create` silently REPLACED it. has() cannot
# be fooled that way. A `.tasks` that is not an object at all used to make jq
# error out and yield an empty answer, which read as "no such task" too; it is
# refused here instead.
TASK_PRESENCE=""
require_task_presence() {
  local id="$1" probe
  probe=$(jq -r --arg id "$id" '
    if type != "object" then "bad:the state file root is not a JSON object"
    elif (has("tasks") | not) or (.tasks == null) then "no"
    elif (.tasks | type) != "object" then "bad:.tasks is not a JSON object — " + (.tasks | tojson | .[0:200])
    elif (.tasks | has($id)) then "yes"
    else "no"
    end
  ' "$STATE" 2>/dev/null)
  case "$probe" in
    yes|no) TASK_PRESENCE="$probe"; return 0 ;;
    bad:*)  state_field_fail "$id" "tasks" "a JSON object mapping task ids to task records" "${probe#bad:}" ;;
    *)      state_field_fail "$id" "tasks" "a JSON object mapping task ids to task records" "unreadable — the state file could not be parsed as JSON" ;;
  esac
}

# require_external_action <id> <key> -> EA_RECORDED_AT ("" when the key is NOT
# recorded for this task).
#
# THE ONE implementation of the already-recorded lookup, shared by
# record-external-action and check-external-action. It was previously the same
# jq expression copy-pasted into both, and both copies had the same hole:
# `map(select(.key == $key))` over an external_actions array containing a
# single non-object entry makes jq abort the whole program ("Cannot index
# string with string"), leaving an EMPTY result -- which both call sites read
# as "this key is not recorded". record-external-action then appended a
# DUPLICATE entry, and check-external-action answered NOT-RECORDED / PROCEED
# for a key that was in fact already recorded. A false PROCEED there is
# precisely the duplicate-PR failure the external-action mechanism exists to
# prevent, so both directions of this read now refuse instead.
#
# Note the two DELIBERATE defaults here, so a later reader can tell them from
# an unhardened read: an absent/null external_actions array legitimately means
# "nothing recorded yet" (require_object_array's absent-case), and a matched
# entry whose recorded_at is unusable still counts as RECORDED, falling back to
# the literal "unknown time" purely for the message. That fallback is
# display-only -- it can never turn a recorded key into an unrecorded one,
# which is the only direction that could cause a duplicate.
EA_RECORDED_AT=""
require_external_action() {
  local id="$1" key="$2" verdict
  require_object_array "$id" "external_actions"
  verdict=$(jq -r --arg id "$id" --arg key "$key" '
    ((.tasks[$id].external_actions) // []) as $a
    | [ $a[] | select((has("key") | not)
                      or ((.key | type) != "string")
                      or ((.key | length) == 0)) ] as $bad
    | if ($bad | length) > 0
      then "bad:entries carrying no usable \"key\" — " + ($bad | tojson | .[0:200])
      else [ $a[] | select(.key == $key) ] as $hit
        | if ($hit | length) == 0 then "no"
          else ($hit[0].recorded_at) as $t
            | if ($t | type) == "string" and ($t | length) > 0
              then "yes:" + $t
              else "yes:unknown time"
              end
          end
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    no)     EA_RECORDED_AT=""; return 0 ;;
    yes:*)  EA_RECORDED_AT="${verdict#yes:}"; return 0 ;;
    bad:*)  state_field_fail "$id" "external_actions" "every entry to carry a non-empty string idempotency key" "${verdict#bad:}" ;;
    *)      state_field_fail "$id" "external_actions" "every entry to carry a non-empty string idempotency key" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_max_attempt_number <id> -> MAX_ATTEMPT_NUMBER (0 when the task has no
# recorded attempts at all). Call require_object_array "$id" "attempts" first:
# this assumes the array is already known to be absent, empty, or made of
# objects, and it settles the remaining question -- that EVERY entry carries a
# usable attempt_number, so the maximum it returns really is the high-water
# mark of the audit trail and not just the maximum of the entries that happened
# to be readable.
MAX_ATTEMPT_NUMBER=""
require_max_attempt_number() {
  local id="$1" verdict
  verdict=$(jq -r --arg id "$id" '
    (.tasks[$id].attempts) as $a
    | (if ($a == null) then []
       else [ $a[] | select((has("attempt_number") | not)
                            or (.attempt_number | type) != "number"
                            or (.attempt_number < 0)
                            or (.attempt_number != (.attempt_number | floor))) ]
       end) as $bad
    | if ($bad | length) > 0
      then "bad:entries with no usable attempt_number — " + ($bad | tojson | .[0:200])
      elif ($a == null) or ($a | length) == 0 then "ok:0"
      else "ok:" + ([$a[].attempt_number] | max | tostring)
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      MAX_ATTEMPT_NUMBER="${verdict#ok:}"
      case "$MAX_ATTEMPT_NUMBER" in
        ''|*[!0-9]*)
          state_field_fail "$id" "attempts" "a highest attempt_number that renders as a plain integer" "$MAX_ATTEMPT_NUMBER" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "attempts" "every entry to carry a non-negative integer attempt_number" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "attempts" "every entry to carry a non-negative integer attempt_number" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_transition_count <id> <to-state> -> TRANSITION_COUNT
#
# "How many times has this task transitioned INTO <to-state>?", answered off the
# task's own history array. Used by `reassess --resume-state checking`, whose
# audit-integrity rule needs "has this task ever actually reached checking?".
#
# WHY THIS EXISTS AS A FAMILY MEMBER RATHER THAN A ONE-OFF jq AT THE CALL SITE.
# It was a one-off, and that was the whole problem: it was the last
# decision-bearing read in this file still spelled out inline, with its own
# hand-written `case`, its own `2>/dev/null`, and its own idea of what a
# malformed history means. It happened to fail closed -- but "happened to" is
# exactly the property this family exists to replace with "by construction",
# and a lone hand-rolled guard is where the next instance of the defect class
# gets introduced by someone copying the nearest example. There is now no
# decision-bearing state read in this file outside the family.
#
# Two things the inline version did that this deliberately does NOT do:
#   1. `select(type == "object")` SKIPPED non-object history entries, so a
#      history holding garbage counted as "no checking transition" -- an
#      unreadable value quietly becoming an answer, the exact shape of the
#      defect class. require_object_array settles that first and REFUSES.
#   2. It read `to` with no type check at all. Every history entry this script
#      has ever written carries a non-empty string `to` (`create` writes
#      to:"planned", every transition writes its destination), so an entry
#      without one is a hand-edit, not a legacy record, and is refused by name.
# ABSENT-CASE: no history key at all, or null, is require_object_array's
# legitimate legacy case and yields 0 -- which is what "this task has never
# reached that state" already means, so the caller's behaviour is unchanged for
# every honestly-written record.
TRANSITION_COUNT=""
require_transition_count() {
  local id="$1" to_state="$2" verdict
  require_object_array "$id" "history"
  verdict=$(jq -r --arg id "$id" --arg to "$to_state" '
    ((.tasks[$id].history) // []) as $h
    | [ $h[] | select((has("to") | not)
                      or ((.to | type) != "string")
                      or ((.to | length) == 0)) ] as $bad
    | if ($bad | length) > 0
      then "bad:entries carrying no usable \"to\" state — " + ($bad | tojson | .[0:200])
      else "ok:" + ([ $h[] | select(.to == $to) ] | length | tostring)
      end
  ' "$STATE" 2>/dev/null)
  case "$verdict" in
    ok:*)
      TRANSITION_COUNT="${verdict#ok:}"
      case "$TRANSITION_COUNT" in
        ''|*[!0-9]*)
          state_field_fail "$id" "history" "a count of transitions into '$to_state' that renders as a plain integer" "a count of '$TRANSITION_COUNT'" ;;
      esac
      return 0
      ;;
    bad:*) state_field_fail "$id" "history" "every entry to record the state it transitioned TO, so 'has this task ever reached $to_state?' can be answered" "${verdict#bad:}" ;;
    *)     state_field_fail "$id" "history" "every entry to record the state it transitioned TO, so 'has this task ever reached $to_state?' can be answered" "unreadable — the task record could not be parsed as JSON" ;;
  esac
}

# require_repair_counters <id> -- resolve BOTH numeric fields the bounded-repair
# paths do arithmetic on, into the globals BUDGET_VALUE and
# ATTEMPTS_USED_VALUE. `fail` and `reassess` both need exactly this, identically;
# it lives here as ONE implementation rather than two copies because the
# duplicated version is what let the guard drift out of step with the read it
# was supposed to be guarding in the first place.
#
# Beyond the per-field validation, this also enforces the cross-field
# invariant that makes `attempts_used` an audit counter rather than a hint:
# attempts_used must be at least the highest attempt_number already recorded
# in the task's own `attempts` array. A counter that has fallen BEHIND its own
# audit trail would re-issue an attempt_number that is already in use, so it
# is refused here rather than written. This is what closes the "delete the key
# on a task that has real history" door, which `has()` alone cannot tell apart
# from a genuine legacy record: a legacy record has no attempts either, so it
# passes; a stripped record with recorded attempts does not.
BUDGET_VALUE=""
ATTEMPTS_USED_VALUE=""
require_repair_counters() {
  local id="$1" max_recorded

  read_numeric_field "$id" "budget" 2
  BUDGET_VALUE="$NUMERIC_FIELD_VALUE"
  read_numeric_field "$id" "attempts_used" 0
  ATTEMPTS_USED_VALUE="$NUMERIC_FIELD_VALUE"

  # THE ATTEMPTS ARRAY IS SETTLED BEFORE IT IS SUMMARISED. The read this
  # replaces was `[ (.attempts // []) | .[]? | .attempt_number? | numbers ]`,
  # with a `case` that degraded anything unreadable to 0 -- and it carried a
  # comment calling that "defense in depth". It was the opposite. Every one of
  # `// []`, `.[]?`, `.attempt_number?`, `numbers` and the degrade-to-0 turns
  # an unreadable attempts array into "no recorded attempts", and "no recorded
  # attempts" is the exact answer that switches this guard OFF. Corrupting the
  # entries to strings and deleting attempts_used therefore reset the counter
  # to 0 and re-issued attempt_number 1 -- reopening, by another door, the very
  # monotonic-counter hole (control #1) this function was added to close.
  # Now: absent/null -> genuinely no history (a legacy record, still accepted);
  # present but not an array of objects each carrying a non-negative integer
  # attempt_number -> corruption, refused by name.
  require_object_array "$id" "attempts"
  require_max_attempt_number "$id"
  max_recorded="$MAX_ATTEMPT_NUMBER"

  if [ "$ATTEMPTS_USED_VALUE" -lt "$max_recorded" ]; then
    echo "ERROR: task '$id' has an 'attempts_used' counter ($ATTEMPTS_USED_VALUE) that is BEHIND its own recorded attempt history (highest recorded attempt_number: $max_recorded). Refusing this operation — nothing was changed." >&2
    echo "  attempts_used is strictly monotonic by design; a counter below the audit trail would re-issue attempt_number $ATTEMPTS_USED_VALUE and durably corrupt the attempts array with a duplicate. The state file may have been hand-edited or partially written — only task-state.sh should write it." >&2
    exit 1
  fi
}

# NOTE: the old `require_task` lived here. Every call site now uses
# require_task_state (above), which publishes the state in TASK_STATE_VALUE
# instead of printing it -- so it can be called DIRECTLY rather than inside
# `$( )`, where its `exit` only ever killed the subshell. Its two not-found
# messages are preserved verbatim there.

CMD="${1:-}"

# Every mutating command is serialized against every other mutating command
# via a single project-wide lock, held for the command's entire
# read-modify-write sequence (see acquire_lock() above).
#
# `check-external-action` is deliberately ABSENT from this list: it is
# strictly read-only (it never calls atomic_update) so it needs no lock, and
# taking one would let a read-only idempotency probe block real work.
case "$CMD" in
  create|start|check|complete|fail|reassess|block|unblock|pause|resume|record-assignment|record-evidence|record-external-action) acquire_lock ;;
esac

case "$CMD" in

  create)
    ID="${2:-}"; TITLE="${3:-}"
    if [ -z "$ID" ] || [ -z "$TITLE" ]; then
      echo "Usage: task-state.sh create <id> <title> [--depends id1,id2,...] [--builder name] [--verifier name] [--skills a,b] [--risk low|medium|high] [--budget N]" >&2
      exit 2
    fi
    if [ $# -ge 3 ]; then shift 3; else shift $#; fi

    DEPENDS=""; BUILDER=""; VERIFIER=""; SKILLS=""; RISK="medium"; BUDGET=2
    while [ $# -gt 0 ]; do
      case "$1" in
        --depends) [ $# -ge 2 ] || { echo "ERROR: --depends requires a value" >&2; exit 2; }; DEPENDS="$2"; shift 2 ;;
        --builder) [ $# -ge 2 ] || { echo "ERROR: --builder requires a value" >&2; exit 2; }; BUILDER="$2"; shift 2 ;;
        --verifier) [ $# -ge 2 ] || { echo "ERROR: --verifier requires a value" >&2; exit 2; }; VERIFIER="$2"; shift 2 ;;
        --skills) [ $# -ge 2 ] || { echo "ERROR: --skills requires a value" >&2; exit 2; }; SKILLS="$2"; shift 2 ;;
        --risk) [ $# -ge 2 ] || { echo "ERROR: --risk requires a value" >&2; exit 2; }; RISK="$2"; shift 2 ;;
        --budget) [ $# -ge 2 ] || { echo "ERROR: --budget requires a value" >&2; exit 2; }; BUDGET="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    case "$RISK" in
      low|medium|high) ;;
      *) echo "ERROR: --risk must be one of low, medium, high (got: $RISK)" >&2; exit 2 ;;
    esac
    # This is the ONLY place `budget` is ever SET. After creation the single
    # path that may change it is `reassess --additional-budget N`, which can
    # only RAISE it (see this file's header, "controls that cannot be
    # weakened" #2). `attempts_used` starts at 0 below and is only ever
    # incremented, by `fail`.
    case "$BUDGET" in
      ''|*[!0-9]*) echo "ERROR: --budget must be a non-negative integer (got: $BUDGET)" >&2; exit 2 ;;
    esac

    ensure_state_file

    # DUPLICATE-ID GUARD, read through has() rather than `// empty`. `// empty`
    # treats a stored `null` (and `false`) as absent, so a task id whose record
    # had been corrupted to null read as "does not exist" and `create` SILENTLY
    # REPLACED it -- the duplicate-id guard degrading into "the condition was
    # not met", the same shape as everything else in the fail-closed section
    # above. has() cannot be fooled that way, and a `.tasks` that is not an
    # object at all is refused rather than left to error out inside jq and
    # yield an empty answer that reads as "no such task".
    require_task_presence "$ID"
    if [ "$TASK_PRESENCE" = "yes" ]; then
      echo "ERROR: task '$ID' already exists" >&2
      exit 1
    fi

    if [ -n "$DEPENDS" ]; then
      IFS=',' read -ra DEP_ARR <<< "$DEPENDS"
      for dep in "${DEP_ARR[@]}"; do
        [ -n "$dep" ] || continue
        require_task_presence "$dep"
        if [ "$TASK_PRESENCE" != "yes" ]; then
          echo "ERROR: dependency '$dep' does not exist; create it before task '$ID'" >&2
          exit 1
        fi
      done
    fi

    DEPENDS_JSON=$(csv_to_json_array "$DEPENDS")
    SKILLS_JSON=$(csv_to_json_array "$SKILLS")
    NOW=$(now_iso)

    atomic_update --arg id "$ID" --arg title "$TITLE" --arg builder "$BUILDER" \
      --arg verifier "$VERIFIER" --arg risk "$RISK" --argjson budget "$BUDGET" \
      --argjson depends "$DEPENDS_JSON" --argjson skills "$SKILLS_JSON" --arg now "$NOW" '
      (if $builder == "" then null else $builder end) as $builder_val
      | (if $verifier == "" then null else $verifier end) as $verifier_val
      | .tasks[$id] = {
        id: $id, title: $title, state: "planned",
        depends_on: $depends, builder: $builder_val, verifier: $verifier_val,
        skills: $skills, risk: $risk, budget: $budget,
        attempts_used: 0,
        blocked_from: null, blocked_reason: null, resume_condition: null,
        paused_from: null,
        created_at: $now, updated_at: $now,
        history: [{from: null, to: "planned", at: $now}],
        assignments: [],
        evidence: [],
        checkpoints: [],
        external_actions: [],
        attempts: [],
        reassessments: []
      }
    '
    echo "CREATED $ID \"$TITLE\" state=planned"
    ;;

  start)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh start <id>" >&2; exit 2; }
    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "planned" ]; then
      if [ "$CUR_STATE" = "needs-reassessment" ]; then
        reassessment_required_error "$ID" "start"
      else
        echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot start (must be 'planned')" >&2
      fi
      exit 1
    fi

    # DEPENDENCY GUARD -- "dependencies block premature dispatch", this
    # subcommand's core acceptance criterion.
    #
    # The read this replaces was a single jq: `.tasks[$id].depends_on[]? as $d
    # | (.tasks[$d].state // "missing") as $s | select($s != "done") | ...`.
    # Both halves of it failed OPEN. `[]?` swallows the type error when
    # depends_on is not iterable at all, so a depends_on corrupted to the bare
    # string "task-a" produced NO dependencies, an empty UNMET, and a task that
    # started while its dependency was still `planned`. And if any `.tasks[$d]`
    # was not an object, jq aborted the whole program, again leaving UNMET
    # empty and again dispatching. This is the same `[]?` spelling as the
    # `artifacts[]?` hole in complete-gate.sh's most important check.
    #
    # Now: the array's shape is settled first (absent/null still legitimately
    # means "no dependencies" -- a task created without --depends), and each
    # dependency's state goes through the same validated read every other state
    # comparison in this file uses, so a corrupt DEPENDENCY record refuses too
    # instead of silently dropping out of the list. read_task_state is used
    # rather than require_task_state because a dependency that does not exist
    # is not an error here -- it is an UNMET dependency, reported as
    # "(state: missing)" exactly as before.
    require_string_array "$ID" "depends_on"
    UNMET=""
    if [ "$ARRAY_LENGTH" -gt 0 ]; then
      # The dependency ids are collected with a single-scalar command
      # substitution and then walked with a HERE-STRING, not a pipe. That is
      # not stylistic: under MSYS/Git Bash, `jq -r ... | read` delivers each
      # line with a trailing CR (verified: `jq -r '.x' f | od -c` shows
      # "done \r \n" where `$(jq -r '.x' f)` shows "done"), so a piped read
      # would look up a task id of "task-a\r", find nothing, and report a
      # satisfied dependency as `(state: missing)`. The rest of this file
      # already reads jq through `$( )` for exactly this reason. Using a
      # here-string also keeps the loop body in THIS shell, so
      # read_task_state's refusal `exit` propagates instead of dying in a
      # subshell -- the same reason these helpers are never called in `$( )`.
      # The `// []` here is a DELIBERATE, already-settled default: this line
      # runs only after require_string_array above has proved depends_on is
      # absent, null, or an array of non-empty strings, so `//` can no longer
      # be reached by a value of the wrong type. It is not a guard.
      DEP_IDS=$(jq -r --arg id "$ID" '(.tasks[$id].depends_on // []) | .[]' "$STATE")
      while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        read_task_state "$dep"
        [ "$TASK_STATE_VALUE" = "done" ] && continue
        UNMET="${UNMET}${dep} (state: ${TASK_STATE_VALUE})"$'\n'
      done <<< "$DEP_IDS"
      UNMET="${UNMET%$'\n'}"
    fi
    if [ -n "$UNMET" ]; then
      echo "ERROR: task '$ID' cannot start — unmet dependencies:" >&2
      while IFS= read -r line; do echo "  - $line" >&2; done <<< "$UNMET"
      exit 1
    fi

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" '
      .tasks[$id].state = "building"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{from: "planned", to: "building", at: $now}]
    '
    echo "STARTED $ID state=building"
    ;;

  check)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh check <id>" >&2; exit 2; }
    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "building" ]; then
      if [ "$CUR_STATE" = "needs-reassessment" ]; then
        reassessment_required_error "$ID" "move to checking"
      else
        echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot move to checking (must be 'building')" >&2
      fi
      exit 1
    fi
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" '
      .tasks[$id].state = "checking"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{from: "building", to: "checking", at: $now}]
    '
    echo "CHECKING $ID state=checking"
    ;;

  complete)
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh complete <id> [--staleness-verified yes|no]" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    # --staleness-verified yes|no -- OPTIONAL, and it records a CLAIM MADE BY
    # THE CALLER about a check the caller performed, not one made here.
    # complete-gate.sh is the only intended caller and always passes it: its
    # check 6 compares the evidence's recorded code_snapshot against a live one,
    # and outside a git repository that comparison is impossible (see the note
    # above compute_snapshot -- both sides degrade to the same placeholder and
    # match no matter what the code did). The gate must not report a staleness
    # pass it could not perform, and this flag is how that honest verdict
    # becomes DURABLE rather than a line of stdout that a pipe can swallow --
    # this subsystem's founding rule is that only recorded state is ground
    # truth, so an unverifiable completion has to be legible in the state file
    # itself, months later, to someone who never saw the terminal.
    #
    # Recorded as `staleness_verified` on the checking -> done history entry.
    # OMITTED writes NO key at all, which is deliberate and means exactly
    # "whoever completed this task did not say" -- i.e. it was completed by
    # something other than complete-gate.sh, since the gate always states it.
    # That is the same ABSENT-vs-PRESENT-BUT-WRONG convention the fail-closed
    # section uses, and it keeps every pre-existing record readable rather than
    # retroactively asserting `true` for completions nothing ever checked.
    # Deliberately yes/no rather than a bare flag: a flag that can only be
    # present would make "verified" the silent default, and silent defaults on
    # verification claims are the entire problem this exists to fix.
    STALENESS_VERIFIED_ARG=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --staleness-verified)
          [ $# -ge 2 ] || { echo "ERROR: --staleness-verified requires a value (yes or no)" >&2; exit 2; }
          case "$2" in
            yes) STALENESS_VERIFIED_ARG="true" ;;
            no)  STALENESS_VERIFIED_ARG="false" ;;
            *)   echo "ERROR: --staleness-verified must be 'yes' or 'no' (got: $2)" >&2; exit 2 ;;
          esac
          shift 2
          ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "checking" ]; then
      if [ "$CUR_STATE" = "needs-reassessment" ]; then
        reassessment_required_error "$ID" "complete"
      else
        echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot complete (must be 'checking')" >&2
      fi
      exit 1
    fi
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg sv "$STALENESS_VERIFIED_ARG" '
      (if $sv == "" then {} else {staleness_verified: ($sv == "true")} end) as $verdict
      | .tasks[$id].state = "done"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [({from: "checking", to: "done", at: $now} + $verdict)]
    '
    if [ -z "$STALENESS_VERIFIED_ARG" ]; then
      echo "COMPLETED $ID state=done"
    else
      echo "COMPLETED $ID state=done staleness_verified=$STALENESS_VERIFIED_ARG"
    fi
    ;;

  fail)
    # Part 2.2. See this file's header for the full contract; the short
    # version is: a failed attempt enters recovery, bounded by the task's own
    # attempt budget, and every new attempt must carry a changed hypothesis.
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh fail <id> --reason \"<why the attempt failed>\" --hypothesis \"<what will be different next attempt>\"" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    FAIL_REASON=""; FAIL_HYPOTHESIS=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason) [ $# -ge 2 ] || { echo "ERROR: --reason requires a value" >&2; exit 2; }; FAIL_REASON="$2"; shift 2 ;;
        --hypothesis) [ $# -ge 2 ] || { echo "ERROR: --hypothesis requires a value" >&2; exit 2; }; FAIL_HYPOTHESIS="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    # Both REQUIRED and both must carry actual content -- checked before
    # require_task and before any write, so a rejected fail leaves the state
    # file byte-for-byte unchanged. Whitespace-only is refused as well as
    # empty: "   " would record as a supplied reason/hypothesis while carrying
    # no accountability at all, and the hypothesis normalisation used by the
    # changed-hypothesis control below would collapse every such value to the
    # same empty string anyway.
    require_nonblank "--reason" "$FAIL_REASON" \
      "a failed attempt with no recorded reason cannot be reviewed or reassessed later"
    require_nonblank "--hypothesis" "$FAIL_HYPOTHESIS" \
      "DESIGN.md, 'Recovery and learning': every new attempt needs a changed hypothesis supported by evidence"

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    case "$CUR_STATE" in
      building|checking) ;;
      needs-reassessment)
        reassessment_required_error "$ID" "record another failed attempt"
        exit 1
        ;;
      *)
        echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot fail from this state (must be one of building, checking)" >&2
        exit 1
        ;;
    esac

    # Resolve and VALIDATE the two counters before anything else reads them.
    # Deliberately ahead of the changed-hypothesis control below: a corrupt
    # counter is a more fundamental problem than a repeated theory, and
    # reporting it first stops a caller from "fixing" their hypothesis in
    # response to a message that was never about the hypothesis. Both refusals
    # exit before any write either way.
    require_repair_counters "$ID"
    BUDGET="$BUDGET_VALUE"
    ATTEMPTS_USED="$ATTEMPTS_USED_VALUE"

    # CHANGED-HYPOTHESIS CONTROL. Compared against the IMMEDIATELY PRECEDING
    # attempt only -- an older hypothesis may legitimately be revisited once
    # evidence has moved on, but repeating the one you just tried is the
    # endless loop this part exists to stop. Normalised (case-folded,
    # trimmed, internal whitespace collapsed) so retyping it in caps or with
    # a trailing space does not slip past; see the header's disclosed limit
    # on what a string comparison can and cannot catch. Both reads are
    # single-scalar command substitutions, the pattern this script uses
    # everywhere and the one that is unaffected by MSYS/Git Bash's
    # CRLF-on-piped-jq behaviour.
    # THIS CONTROL USED TO BE UNCONDITIONALLY OFF FOR A CORRUPT RECORD, and it
    # is the reason the fail-closed section above exists. The old reads were
    # `.[-1].hypothesis // ""` and `def norm: (. // "") | ...`: a stored
    # hypothesis of `null` became "", and because the INCOMING hypothesis has
    # already been validated non-blank by require_nonblank above, `"" == it`
    # could never be true. So `jq '.attempts[0].hypothesis = null'` disabled
    # the changed-hypothesis control permanently and the identical theory could
    # be resubmitted forever -- defeating both this part's own acceptance text
    # ("every new attempt needs a changed hypothesis") and control #3 of
    # "controls that cannot be weakened" in this file's header.
    #
    # ABSENT-CASE, PRESERVED: no attempts array, or an empty one, genuinely
    # means there is no preceding attempt to repeat, so the control passes --
    # that is a legacy/first-attempt record, not corruption, and
    # require_object_array's own absent-case is what expresses it.
    # PRESENT-BUT-UNUSABLE (a last entry that is not an object, or whose
    # hypothesis is missing, null, non-string or empty) is corruption: `fail`
    # always writes a validated non-blank hypothesis into the same atomic
    # object as the entry, so such an entry cannot have come from this script.
    # It refuses instead of being compared as "".
    require_object_array "$ID" "attempts"
    PREV_HYP=""
    SAME_HYP="no"
    if [ "$ARRAY_LENGTH" -gt 0 ]; then
      require_entry_string "$ID" "attempts" -1 "hypothesis"
      PREV_HYP="$ENTRY_STRING"
      # Normalisation is unchanged (case-folded, trimmed, internal whitespace
      # collapsed) -- but it now runs on a value already known to be a
      # non-empty string, so there is no `// ""` left in it to swallow one.
      SAME_HYP=$(jq -rn --arg p "$PREV_HYP" --arg h "$FAIL_HYPOTHESIS" '
        def norm: ascii_downcase | gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; "");
        if ($p | norm) == ($h | norm) then "yes" else "no" end
      ')
      # A verdict that is neither of the two words this comparison can produce
      # means jq itself failed. Refuse rather than let an unreadable answer
      # fall through the `= "yes"` test below as "not the same hypothesis".
      case "$SAME_HYP" in
        yes|no) ;;
        *)
          echo "ERROR: task '$ID' — the changed-hypothesis comparison could not be evaluated (got: '$SAME_HYP'). Refusing this attempt — nothing was changed." >&2
          exit 1
          ;;
      esac
    fi
    if [ "$SAME_HYP" = "yes" ]; then
      require_entry_number "$ID" "attempts" -1 "attempt_number"
      PREV_NUM="$ENTRY_NUMBER"
      echo "ERROR: task '$ID' — this attempt repeats the immediately preceding attempt's hypothesis, so it is REFUSED and nothing was recorded." >&2
      echo "  previous hypothesis (attempt $PREV_NUM): $PREV_HYP" >&2
      echo "  submitted hypothesis:                    $FAIL_HYPOTHESIS" >&2
      echo "  DESIGN.md ('Recovery and learning'): every new attempt needs a changed hypothesis supported by evidence. Retrying an identical theory is what an endless loop IS. Supply a genuinely different hypothesis, or run 'task-state.sh reassess $ID ...' if the theory has run out." >&2
      exit 1
    fi

    # MONOTONIC: the only arithmetic ever applied to attempts_used in this
    # entire script. It goes up by exactly one, here, and nowhere else.
    NEW_ATTEMPTS_USED=$((ATTEMPTS_USED + 1))
    if [ "$NEW_ATTEMPTS_USED" -lt "$BUDGET" ]; then
      NEW_STATE="building"
    else
      NEW_STATE="needs-reassessment"
    fi
    REMAINING=$((BUDGET - NEW_ATTEMPTS_USED))
    [ "$REMAINING" -ge 0 ] || REMAINING=0

    # Snapshot the code AS IT WAS WHEN THE ATTEMPT FAILED, so a later
    # reassessment can see which revision each attempt was actually made
    # against rather than guessing from timestamps.
    SNAPSHOT=$(compute_snapshot)
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg from "$CUR_STATE" \
      --arg to "$NEW_STATE" --arg reason "$FAIL_REASON" --arg hyp "$FAIL_HYPOTHESIS" \
      --arg snapshot "$SNAPSHOT" --argjson n "$NEW_ATTEMPTS_USED" --argjson budget "$BUDGET" '
      .tasks[$id].attempts_used = $n
      | .tasks[$id].attempts = ((.tasks[$id].attempts // []) + [{
          attempt_number: $n,
          reason: $reason,
          hypothesis: $hyp,
          failed_at: $now,
          code_snapshot: $snapshot
        }])
      | .tasks[$id].state = $to
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{
          from: $from, to: $to, at: $now,
          reason: $reason, hypothesis: $hyp,
          attempt_number: $n, attempts_used: $n, budget: $budget
        }]
    '
    echo "FAILED $ID from=$CUR_STATE attempt=$NEW_ATTEMPTS_USED/$BUDGET state=$NEW_STATE"
    if [ "$NEW_STATE" = "building" ]; then
      echo "REPAIR MAY PROCEED: $REMAINING repair attempt(s) remain before this task's attempt budget is exhausted."
    else
      echo "ATTEMPT BUDGET EXHAUSTED: $NEW_ATTEMPTS_USED of $BUDGET attempt(s) used, 0 remain. This task is now in 'needs-reassessment': no further fail, start, check, block, pause or completion is accepted. The ONLY way out is: task-state.sh reassess $ID --specialist \"<who/what reassessed>\" --finding \"<what the reassessment concluded>\" [--additional-budget N]"
    fi
    ;;

  reassess)
    # Part 2.2. The ONLY exit from 'needs-reassessment'. Grants MORE budget;
    # never erases attempt history. See this file's header, "controls that
    # cannot be weakened".
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh reassess <id> --specialist \"<who/what reassessed>\" --finding \"<what the reassessment concluded>\" [--additional-budget N] [--resume-state building|checking]" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    SPECIALIST=""; FINDING=""; ADDITIONAL_BUDGET=0; ADDITIONAL_GIVEN=""; RESUME_STATE="building"
    while [ $# -gt 0 ]; do
      case "$1" in
        --specialist) [ $# -ge 2 ] || { echo "ERROR: --specialist requires a value" >&2; exit 2; }; SPECIALIST="$2"; shift 2 ;;
        --finding) [ $# -ge 2 ] || { echo "ERROR: --finding requires a value" >&2; exit 2; }; FINDING="$2"; shift 2 ;;
        --additional-budget) [ $# -ge 2 ] || { echo "ERROR: --additional-budget requires a value" >&2; exit 2; }; ADDITIONAL_BUDGET="$2"; ADDITIONAL_GIVEN=1; shift 2 ;;
        --resume-state) [ $# -ge 2 ] || { echo "ERROR: --resume-state requires a value" >&2; exit 2; }; RESUME_STATE="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    # Both REQUIRED, and both must carry actual content. An unexplained budget
    # grant is exactly the "conceal failures" pattern DESIGN.md's "Recovery
    # and learning" forbids, so a reassessment that will not say who
    # reassessed and what they concluded is refused outright, before any
    # write. A whitespace-only value conceals just as effectively as an empty
    # one -- it merely leaves a stored field that LOOKS answered -- so it is
    # refused on the same terms.
    require_nonblank "--specialist" "$SPECIALIST" \
      "an unexplained reset of an exhausted attempt budget is exactly the 'conceal failures' pattern DESIGN.md forbids"
    require_nonblank "--finding" "$FINDING" \
      "a reassessment that records no conclusion is not a reassessment"

    # Positive integer only -- validated the same way `create` validates
    # --budget, plus a >= 1 floor. 0 is rejected rather than silently
    # accepted as a no-op: omitting the flag is how you grant nothing, and
    # keeping those two spellings distinct stops "--additional-budget 0" from
    # reading like a deliberate grant in a shell history. A negative value
    # fails the same non-numeric case (the '-' is a non-digit).
    if [ -n "$ADDITIONAL_GIVEN" ]; then
      case "$ADDITIONAL_BUDGET" in
        ''|*[!0-9]*) echo "ERROR: --additional-budget must be a positive integer (got: $ADDITIONAL_BUDGET)" >&2; exit 2 ;;
      esac
      [ "$ADDITIONAL_BUDGET" -ge 1 ] || {
        echo "ERROR: --additional-budget must be a positive integer (got: $ADDITIONAL_BUDGET) — omit the flag entirely to grant no additional budget" >&2
        exit 2
      }
    fi

    case "$RESUME_STATE" in
      building|checking) ;;
      *) echo "ERROR: --resume-state must be 'building' or 'checking' (got: $RESUME_STATE)" >&2; exit 2 ;;
    esac

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "needs-reassessment" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot reassess (must be 'needs-reassessment'). Reassessment is not a general-purpose budget grant — it exists only to clear an exhausted attempt budget." >&2
      exit 1
    fi

    # RESUME-STATE MUST BE A STATE THIS TASK HAS ACTUALLY HELD. `building` is
    # always legitimate: every task passes through it before it can fail at
    # all. `checking` is only legitimate for a task that genuinely reached
    # `checking` at some point (i.e. it has a history entry landing there),
    # which is exactly the case this flag was added for -- a task that failed
    # DURING verification and whose reassessment concluded the implementation
    # was fine and the verification method was wrong.
    #
    # BE PRECISE ABOUT WHAT THIS DOES AND DOES NOT CLOSE. It is NOT a
    # privilege fix: `reassess` (default, -> building) followed by `check`
    # reaches `checking` in one further, entirely unrestricted step, so
    # nothing here gates a state that was otherwise unreachable. What it
    # closes is an AUDIT-INTEGRITY hole, which is the currency this whole
    # subsystem trades in: `--resume-state` is documented as RESTORING a
    # state, and letting it "restore" a task into a state the task had never
    # held writes a history entry (`needs-reassessment -> checking`) asserting
    # a promotion that never happened, with no `building -> checking`
    # transition anywhere in the record to back it. A task that reaches
    # `checking` the honest way leaves that trail; this made it possible to
    # arrive there without one. Refused (exit 1 -- the value is well-formed,
    # it is this TASK it does not apply to), with the honest route named.
    if [ "$RESUME_STATE" = "checking" ]; then
      # ROUTED THROUGH THE SHARED FAIL-CLOSED FAMILY, like every other
      # decision-bearing read in this file. It used to be a hand-rolled jq here
      # with its own inline `case`: `.[]?` and `.to?` suppressed type errors and
      # `// []` swallowed a null, so a malformed history degraded to "zero
      # checking transitions" -- which happens to REFUSE, the safe direction, so
      # that part was never a live hole; and a jq that failed outright left
      # EVER_CHECKED EMPTY, where `[ "" = "0" ]` is false and the guard was
      # SKIPPED, which was. The inline `case` closed the second half, but left
      # this as the one A-class guard outside the family -- i.e. the one place a
      # future reader would find a hand-rolled example to copy. It is now
      # require_transition_count's, which additionally REFUSES a history holding
      # non-object entries rather than silently not counting them.
      require_transition_count "$ID" "checking"
      EVER_CHECKED="$TRANSITION_COUNT"
      if [ "$EVER_CHECKED" = "0" ]; then
        echo "ERROR: task '$ID' has never been in state 'checking', so --resume-state checking cannot RESTORE it there. Nothing was changed." >&2
        echo "  --resume-state restores a state the task actually held before it failed; using it to place a task into a state it never reached would record a 'needs-reassessment -> checking' promotion that never happened, with no 'building -> checking' transition in the task's history to support it." >&2
        echo "  If this task is genuinely ready for verification, take the honest route: 'task-state.sh reassess $ID ...' (which restores 'building'), then 'task-state.sh check $ID' once the repair is actually ready." >&2
        exit 1
      fi
    fi

    require_repair_counters "$ID"
    OLD_BUDGET="$BUDGET_VALUE"
    ATTEMPTS_USED="$ATTEMPTS_USED_VALUE"
    # The array this subcommand appends to -- absent/null is a legitimate
    # legacy record (the `// []` in the write starts one), a present non-array
    # is refused by name here rather than inside atomic_update's jq.
    require_appendable_array "$ID" "reassessments"

    # RAISES the budget, never lowers it: ADDITIONAL_BUDGET is validated
    # >= 1 above when given, and is 0 when omitted, so NEW_BUDGET >=
    # OLD_BUDGET always holds. attempts_used is deliberately NOT touched by
    # the update below.
    NEW_BUDGET=$((OLD_BUDGET + ADDITIONAL_BUDGET))
    REMAINING=$((NEW_BUDGET - ATTEMPTS_USED))
    [ "$REMAINING" -ge 0 ] || REMAINING=0

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg to "$RESUME_STATE" \
      --arg specialist "$SPECIALIST" --arg finding "$FINDING" \
      --argjson granted "$ADDITIONAL_BUDGET" --argjson new_budget "$NEW_BUDGET" \
      --argjson old_budget "$OLD_BUDGET" --argjson used "$ATTEMPTS_USED" '
      .tasks[$id].budget = $new_budget
      | .tasks[$id].reassessments = ((.tasks[$id].reassessments // []) + [{
          specialist: $specialist,
          finding: $finding,
          additional_budget_granted: $granted,
          reassessed_at: $now,
          attempts_at_reassessment: $used
        }])
      | .tasks[$id].state = $to
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{
          from: "needs-reassessment", to: $to, at: $now,
          specialist: $specialist, finding: $finding,
          additional_budget_granted: $granted,
          budget_before: $old_budget, budget_after: $new_budget,
          attempts_used: $used
        }]
    '
    # "attempts_used=N (unchanged)" is a CLAIM ABOUT STORED STATE, so it is
    # read back from the state file after the write rather than echoed from a
    # variable this command computed. Printing a computed value next to the
    # word "unchanged" is how the F1 report's `attempts_used=0 (unchanged)`
    # came to assert the field was untouched while displaying a number that
    # was never in the file. The read is the same validated read as above, so
    # it cannot re-introduce the defaulting bug either; a mismatch here would
    # mean something wrote this task outside the lock, which is reported
    # rather than papered over.
    read_numeric_field "$ID" "attempts_used" 0
    STORED_ATTEMPTS_USED="$NUMERIC_FIELD_VALUE"
    if [ "$STORED_ATTEMPTS_USED" != "$ATTEMPTS_USED" ]; then
      echo "ERROR: task '$ID' — attempts_used read back as $STORED_ATTEMPTS_USED immediately after a reassessment that read it as $ATTEMPTS_USED and did not touch it. The reassessment itself was written, but this counter cannot be reported as unchanged. Something wrote this task outside the lock; re-read 'task-state.sh status $ID' before continuing." >&2
      exit 1
    fi
    echo "REASSESSED $ID specialist=\"$SPECIALIST\" state=$RESUME_STATE budget=$OLD_BUDGET->$NEW_BUDGET attempts_used=$STORED_ATTEMPTS_USED (unchanged)"
    if [ "$REMAINING" -gt 0 ]; then
      echo "REPAIR MAY PROCEED: $REMAINING further repair attempt(s) are now permitted before this task returns to 'needs-reassessment'."
    else
      echo "NO ADDITIONAL BUDGET GRANTED: this task returns to work still at its cap ($STORED_ATTEMPTS_USED of $NEW_BUDGET attempt(s) used), so the very NEXT 'fail' will put it straight back into 'needs-reassessment'. That is intended, not a bug — pass --additional-budget N if further repair attempts are genuinely warranted."
    fi
    ;;

  block)
    ID="${2:-}"; REASON="${3:-}"
    if [ -z "$ID" ] || [ -z "$REASON" ]; then
      echo "Usage: task-state.sh block <id> <reason> [--resume-condition text]" >&2
      exit 2
    fi
    if [ $# -ge 3 ]; then shift 3; else shift $#; fi

    RESUME_COND=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --resume-condition) [ $# -ge 2 ] || { echo "ERROR: --resume-condition requires a value" >&2; exit 2; }; RESUME_COND="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    case "$CUR_STATE" in
      planned|building|checking) ;;
      # Refused, and pointed at the one real exit. Also load-bearing as a
      # bypass closure: if block accepted a needs-reassessment task, unblock
      # would then restore it -- but since blocked_from would record
      # "needs-reassessment", unblock would restore THAT, not a working
      # state. Refusing outright keeps the stop unambiguous either way.
      needs-reassessment) reassessment_required_error "$ID" "block"; exit 1 ;;
      *) echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot block from this state" >&2; exit 1 ;;
    esac

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg reason "$REASON" \
      --arg resume "$RESUME_COND" --arg from "$CUR_STATE" '
      (if $resume == "" then null else $resume end) as $resume_val
      | .tasks[$id].blocked_from = $from
      | .tasks[$id].blocked_reason = $reason
      | .tasks[$id].resume_condition = $resume_val
      | .tasks[$id].state = "blocked"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{from: $from, to: "blocked", at: $now, reason: $reason, resume_condition: $resume_val}]
    '
    echo "BLOCKED $ID from=$CUR_STATE reason=\"$REASON\""
    ;;

  unblock)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh unblock <id>" >&2; exit 2; }
    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "blocked" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', not blocked" >&2
      exit 1
    fi

    # THE WORST PERMISSIVE READ THAT WAS IN THIS FILE. `.blocked_from //
    # "missing"` restored whatever string it found, so a blocked_from hand-set
    # to "done" moved the task straight to `done` -- past `checking`, past
    # complete-gate.sh, past the entire verification contract, with `unblock`
    # printing success. `block` only ever records planned/building/checking
    # (it refuses every other source state), so require_restorable_state's
    # enum is behaviour-preserving for every honestly-written record.
    # ABSENT-CASE PRESERVED: absent or null still means "nothing to restore
    # to", refused below with the original message.
    require_restorable_state "$ID" "blocked_from"
    RESTORE="$RESTORE_STATE"
    if [ "$RESTORE" = "missing" ]; then
      echo "ERROR: task '$ID' has no recorded prior state to restore to" >&2
      exit 1
    fi

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg restore "$RESTORE" '
      .tasks[$id].state = $restore
      | .tasks[$id].updated_at = $now
      | .tasks[$id].blocked_from = null
      | .tasks[$id].blocked_reason = null
      | .tasks[$id].resume_condition = null
      | .tasks[$id].history += [{from: "blocked", to: $restore, at: $now}]
    '
    echo "UNBLOCKED $ID state=$RESTORE"
    ;;

  pause)
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh pause <id> --next-action \"<exact next action text>\"" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    NEXT_ACTION=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --next-action) [ $# -ge 2 ] || { echo "ERROR: --next-action requires a value" >&2; exit 2; }; NEXT_ACTION="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    # REQUIRED, not optional. See this file's header: a pause with no
    # recorded next action cannot satisfy "restart restores the exact next
    # action", so accepting one would quietly defeat the mechanism. Checked
    # before require_task and before any write, so a rejected pause leaves
    # the state file byte-for-byte unchanged.
    [ -n "$NEXT_ACTION" ] || {
      echo "ERROR: --next-action is required (a pause with no recorded next action cannot restore an exact next action on resume)" >&2
      exit 2
    }

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    case "$CUR_STATE" in
      planned|building|checking) ;;
      paused)
        echo "ERROR: task '$ID' is already paused; run 'task-state.sh resume $ID' before pausing it again" >&2
        exit 1
        ;;
      # Same closure as block's above: pause is refused, so `resume` (which
      # requires state 'paused') can never become an indirect exit from
      # 'needs-reassessment' either.
      needs-reassessment)
        reassessment_required_error "$ID" "pause"
        exit 1
        ;;
      *)
        echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot pause from this state (must be one of planned, building, checking)" >&2
        exit 1
        ;;
    esac

    # The array this subcommand appends to, and that `resume` then reads a
    # decision out of. Settled here as well as there, so a corrupt checkpoints
    # array is refused at the point it would be WRITTEN to, not only at the
    # point the damage is read back.
    require_object_array "$ID" "checkpoints"

    # Snapshot the code AS IT IS AT PAUSE TIME. `resume` recomputes this live
    # and compares, which is how "resume checks actual code" is implemented.
    SNAPSHOT=$(compute_snapshot)
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg from "$CUR_STATE" \
      --arg next_action "$NEXT_ACTION" --arg snapshot "$SNAPSHOT" '
      .tasks[$id].paused_from = $from
      | .tasks[$id].state = "paused"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].checkpoints = ((.tasks[$id].checkpoints // []) + [{
          next_action: $next_action,
          code_snapshot: $snapshot,
          paused_from: $from,
          paused_at: $now
        }])
      | .tasks[$id].history += [{from: $from, to: "paused", at: $now, next_action: $next_action}]
    '
    echo "PAUSED $ID from=$CUR_STATE snapshot=\"$SNAPSHOT\""
    echo "NEXT ACTION: $NEXT_ACTION"
    ;;

  resume)
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh resume <id>" >&2; exit 2; }
    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "paused" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', not paused" >&2
      exit 1
    fi

    # Same enum guard as unblock's, for the same reason: `pause` only ever
    # records planned/building/checking, and an unvalidated paused_from would
    # let a hand-edit restore a task into `done`.
    require_restorable_state "$ID" "paused_from"
    RESTORE="$RESTORE_STATE"
    if [ "$RESTORE" = "missing" ]; then
      echo "ERROR: task '$ID' has no recorded prior state to restore to" >&2
      exit 1
    fi

    # Read the LATEST checkpoint. `pause` is the only way into the paused
    # state and it always appends a checkpoint, so an empty array here means
    # the state file was tampered with by hand; refuse rather than resume
    # without the next action that gives resume its point.
    #
    # THE GUARD IMMEDIATELY BELOW USED TO BE SKIPPABLE. It read
    # `(.checkpoints // []) | length` and compared with `-eq 0`. With
    # checkpoints corrupted to a JSON boolean, `true // []` keeps `true`,
    # `true | length` is a jq ERROR, CP_COUNT came back EMPTY, and
    # `[ "" -eq 0 ]` printed "integer expression expected" and returned 2 --
    # which the `if` read as "condition not met", so the no-checkpoint guard
    # was SKIPPED and resume carried on to print an empty next action against
    # an empty snapshot. require_object_array settles the shape in jq first and
    # refuses; its absent-case (no key / null -> length 0) still lands on the
    # original message below, unchanged.
    require_object_array "$ID" "checkpoints"
    CP_COUNT="$ARRAY_LENGTH"
    if [ "$CP_COUNT" -eq 0 ]; then
      echo "ERROR: task '$ID' is paused but has no checkpoint recorded, so the exact next action cannot be restored" >&2
      exit 1
    fi
    # Both of these were `// ""`, and both defaults were silent degradations of
    # this subcommand's own contract: an empty CP_NEXT_ACTION prints
    # "NEXT ACTION: " and defeats "restart restores the EXACT next action"
    # outright, while an empty CP_SNAPSHOT can never equal a real snapshot, so
    # the code check reports drift and blames changed code for a corrupt
    # record. `pause` writes both, with content, in the same atomic object as
    # the checkpoint entry -- so neither has a legitimate absent-case, and both
    # now refuse. (Still single-scalar reads from the state FILE rather than
    # through a pipe -- the pattern complete-gate.sh documents as unaffected by
    # MSYS/Git Bash's CRLF-on-piped-jq behaviour.)
    require_entry_string "$ID" "checkpoints" -1 "next_action"
    CP_NEXT_ACTION="$ENTRY_STRING"
    require_entry_string "$ID" "checkpoints" -1 "code_snapshot"
    CP_SNAPSHOT="$ENTRY_STRING"

    # "Resume checks actual code": recompute live, right now, rather than
    # trusting anything cached.
    CURRENT_SNAPSHOT=$(compute_snapshot)

    # WAS THE COMPARISON EVEN POSSIBLE? Settled BEFORE the drift verdict,
    # because the drift verdict is meaningless without it.
    #
    # THE DEFECT THIS CLOSES. Outside a git repository compute_snapshot cannot
    # compute a code identity and returns the constant "no-git-repository" (see
    # the note above it). The comparison below then compared that constant
    # against itself, matched every time no matter what happened to the code,
    # and this subcommand printed "CODE CHECK: OK — code is unchanged since the
    # pause" having verified NOTHING. That is the project's defect class exactly
    # -- an unavailable input silently becoming a value that means "condition
    # satisfied" -- and it is worse here than a missed check, because the output
    # actively ASSERTED a check that could not run.
    #
    # THE SEMANTICS, decided deliberately: a project without version control is
    # legitimate and must still be able to resume, so this does NOT refuse. What
    # it must never do again is CLAIM the code is unchanged. Unverifiable is
    # therefore its own third outcome, printed as such and recorded as such.
    if [ "$CP_SNAPSHOT" = "$NO_GIT_SNAPSHOT" ] || [ "$CURRENT_SNAPSHOT" = "$NO_GIT_SNAPSHOT" ]; then
      STALENESS_VERIFIED=false
    else
      STALENESS_VERIFIED=true
    fi

    # The drift verdict is DURABLY RECORDED, not merely printed. See this
    # file's header (resume contract, point 3): only durably-recorded state
    # counts here, and a verdict living solely in stdout can be swallowed by
    # a pipe, leaving nothing able to prove afterwards whether drift was seen
    # at this resume. Both snapshots are stored alongside the boolean so the
    # verdict can be re-derived and audited, not just trusted.
    #
    # `staleness_verified` is recorded for the same reason and is the field that
    # makes `drift_detected` readable: drift_detected:false with
    # staleness_verified:false means "no drift was SEEN because none could be",
    # not "the code is unchanged". An auditor reading this record later can tell
    # those apart; before this field existed, they were the same two bytes.
    # drift_detected stays a plain boolean (rather than becoming null when
    # unverifiable) so it remains re-derivable from the two stored snapshots.
    if [ "$CP_SNAPSHOT" = "$CURRENT_SNAPSHOT" ]; then
      DRIFT_DETECTED=false
    else
      DRIFT_DETECTED=true
    fi

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg restore "$RESTORE" \
      --argjson drift "$DRIFT_DETECTED" --argjson verified "$STALENESS_VERIFIED" \
      --arg pause_snap "$CP_SNAPSHOT" \
      --arg resume_snap "$CURRENT_SNAPSHOT" '
      .tasks[$id].state = $restore
      | .tasks[$id].updated_at = $now
      | .tasks[$id].paused_from = null
      | .tasks[$id].history += [{
          from: "paused", to: $restore, at: $now,
          drift_detected: $drift,
          staleness_verified: $verified,
          pause_snapshot: $pause_snap,
          resume_snapshot: $resume_snap
        }]
    '
    echo "RESUMED $ID state=$RESTORE"
    echo "NEXT ACTION: $CP_NEXT_ACTION"
    # Drift is SURFACED, never silent -- but it is also never a refusal to
    # resume: resuming is still the right outcome, the caller just has to
    # know the ground moved. All THREE outcomes print, so a caller is never
    # left guessing whether the check actually ran -- and, since the fix above,
    # never told it ran when it could not.
    if [ "$STALENESS_VERIFIED" = "false" ]; then
      echo "CODE CHECK: *** NOT VERIFIED — THIS PROJECT IS NOT UNDER VERSION CONTROL ***"
      echo "  snapshot at pause: $CP_SNAPSHOT"
      echo "  snapshot now:      $CURRENT_SNAPSHOT"
      echo "  At least one of those is the placeholder '$NO_GIT_SNAPSHOT' — what compute_snapshot returns when it cannot identify the code at all — so the two cannot be compared as code identities. When BOTH are the placeholder they match for every possible state of the code, which is not evidence of anything. Either way: ANY change made while this task was paused is UNDETECTED here, and the recorded next action above may no longer be valid. Re-check the current code against that next action yourself. Recorded durably as staleness_verified: false."
    elif [ "$DRIFT_DETECTED" = "false" ]; then
      echo "CODE CHECK: OK — code is unchanged since the pause (snapshot: $CURRENT_SNAPSHOT). The recorded next action was written against exactly this code."
    else
      echo "CODE CHECK: *** WARNING — THE CODE CHANGED WHILE THIS TASK WAS PAUSED ***"
      echo "  snapshot at pause: $CP_SNAPSHOT"
      echo "  snapshot now:      $CURRENT_SNAPSHOT"
      echo "  The recorded next action above may no longer be valid, because the code moved while the task was paused. Re-check the current code against that next action before acting on it."
    fi
    ;;

  record-external-action)
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-external-action <id> --key <idempotency-key> --description \"<what was done>\"" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    EA_KEY=""; EA_DESC=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --key) [ $# -ge 2 ] || { echo "ERROR: --key requires a value" >&2; exit 2; }; EA_KEY="$2"; shift 2 ;;
        --description) [ $# -ge 2 ] || { echo "ERROR: --description requires a value" >&2; exit 2; }; EA_DESC="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    [ -n "$EA_KEY" ] || { echo "ERROR: --key is required" >&2; exit 2; }
    [ -n "$EA_DESC" ] || { echo "ERROR: --description is required" >&2; exit 2; }

    # `needs-reassessment` is a FROZEN stop, and freezing means the record
    # stops growing too, not just the state machine. Checked BEFORE the
    # already-recorded shortcut below on purpose: under the record-first
    # idiom a caller treats anything other than "RECORDED-EXTERNAL-ACTION" as
    # "do not perform the action", and a hard error is the safe answer for a
    # task nobody should be acting on at all. require_task_state publishes the
    # state in a global rather than printing it, so it can be called directly
    # -- inside `$( )` its refusal `exit` would only kill the subshell and let
    # this command carry on to write. A `state` that is present but not a
    # usable string is refused there rather than silently failing to match
    # "needs-reassessment", which is how a corrupt state used to walk straight
    # through this freeze.
    require_task_state "$ID"
    EA_STATE="$TASK_STATE_VALUE"
    if [ "$EA_STATE" = "needs-reassessment" ]; then
      reassessment_required_error "$ID" "record an external action"
      exit 1
    fi

    # Idempotency: if this key is already recorded for this task, do NOT
    # append a second entry. Exit 0 -- see this file's header for why an
    # already-done action is a no-op SUCCESS rather than an error. The lookup
    # is require_external_action's, shared with check-external-action so the
    # two can never answer the same question differently.
    require_external_action "$ID" "$EA_KEY"
    EA_EXISTING="$EA_RECORDED_AT"
    if [ -n "$EA_EXISTING" ]; then
      echo "ALREADY-RECORDED $ID key=$EA_KEY (first recorded at $EA_EXISTING) — not appended again; this external action is already done, do NOT repeat it"
      exit 0
    fi

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg key "$EA_KEY" --arg desc "$EA_DESC" '
      .tasks[$id].external_actions = ((.tasks[$id].external_actions // []) + [{
          key: $key, description: $desc, recorded_at: $now
        }])
      | .tasks[$id].updated_at = $now
    '
    echo "RECORDED-EXTERNAL-ACTION $ID key=$EA_KEY description=\"$EA_DESC\""
    ;;

  check-external-action)
    # READ-ONLY: takes no lock, never writes.
    # EXIT 0 => CONFIRMED RECORDED     => caller must SKIP the action.
    # EXIT 1 => CONFIRMED NOT RECORDED => caller must PROCEED with the action.
    # EXIT 2 => bad usage              => UNDETERMINED, caller must NOT proceed.
    # EXIT 3 => task does not exist    => UNDETERMINED, caller must NOT
    #           proceed; fix the task id and re-check.
    # NONZERO NEVER MEANS "ALREADY DONE". Getting this backwards causes
    # exactly the duplicate-PR/duplicate-note problem this exists to prevent;
    # see this file's header, including why record-first rather than
    # check-then-act is the safe idiom under concurrency.
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh check-external-action <id> --key <idempotency-key>" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    EA_KEY=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --key) [ $# -ge 2 ] || { echo "ERROR: --key requires a value" >&2; exit 2; }; EA_KEY="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done
    [ -n "$EA_KEY" ] || { echo "ERROR: --key is required" >&2; exit 2; }

    # EVERY REFUSAL IN THIS SUBCOMMAND MUST EXIT 3, NOT 1. Exit 1 here is the
    # documented "CONFIRMED NOT RECORDED -> PROCEED WITH THE EXTERNAL ACTION"
    # answer, so a corruption refusal that exited 1 would tell the caller to go
    # ahead and open the PR -- turning the refusal into the very duplicate this
    # subcommand exists to prevent. Setting STATE_FAIL_EXIT before the first
    # read is what redirects the shared fail-closed helpers onto this
    # subcommand's UNDETERMINED code. It is deliberately set here rather than
    # globally: for every other subcommand 1 is correct, and "not found" there
    # is a plain error rather than a signal any script branches on.
    STATE_FAIL_EXIT=3

    # Task existence is checked HERE, and reported as 3, for the same reason:
    # a typo'd task id landing on exit 1 would look exactly like a green light.
    if [ ! -f "$STATE" ]; then
      echo "ERROR: task '$ID' not found — cannot determine whether external action key '$EA_KEY' has already been recorded. Do NOT proceed with the external action (exit 3 is NOT the 'PROCEED' answer, exit 1 is); fix the task id and re-check." >&2
      exit 3
    fi
    # read_task_state (not require_task_state) so the not-found MESSAGE below
    # stays this subcommand's own, more specific one. A corrupt record still
    # refuses inside read_task_state, at exit 3 per STATE_FAIL_EXIT above --
    # never at 1, and never by quietly failing to match a state name.
    read_task_state "$ID"
    if [ "$TASK_STATE_VALUE" = "missing" ]; then
      echo "ERROR: task '$ID' not found — cannot determine whether external action key '$EA_KEY' has already been recorded. Do NOT proceed with the external action (exit 3 is NOT the 'PROCEED' answer, exit 1 is); fix the task id and re-check." >&2
      exit 3
    fi

    # The SAME lookup record-external-action uses, by construction -- see
    # require_external_action. The two answering this question differently is
    # what a duplicate external action is made of.
    require_external_action "$ID" "$EA_KEY"
    EA_FOUND="$EA_RECORDED_AT"
    if [ -n "$EA_FOUND" ]; then
      echo "ALREADY-RECORDED $ID key=$EA_KEY (recorded at $EA_FOUND) — SKIP this external action, it has already been performed"
      exit 0
    fi
    echo "NOT-RECORDED $ID key=$EA_KEY — PROCEED with this external action, it has not been performed yet"
    exit 1
    ;;

  record-assignment)
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-assignment <id> --role builder|verifier --agent-type name [--skill-hash path:hash,path:hash,...] [--acceptance-text text] [--code-snapshot text]" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    ROLE=""; AGENT_TYPE=""; SKILL_HASH=""; ACCEPTANCE=""; SNAPSHOT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --role) [ $# -ge 2 ] || { echo "ERROR: --role requires a value" >&2; exit 2; }; ROLE="$2"; shift 2 ;;
        --agent-type) [ $# -ge 2 ] || { echo "ERROR: --agent-type requires a value" >&2; exit 2; }; AGENT_TYPE="$2"; shift 2 ;;
        --skill-hash) [ $# -ge 2 ] || { echo "ERROR: --skill-hash requires a value" >&2; exit 2; }; SKILL_HASH="$2"; shift 2 ;;
        --acceptance-text) [ $# -ge 2 ] || { echo "ERROR: --acceptance-text requires a value" >&2; exit 2; }; ACCEPTANCE="$2"; shift 2 ;;
        --code-snapshot) [ $# -ge 2 ] || { echo "ERROR: --code-snapshot requires a value" >&2; exit 2; }; SNAPSHOT="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    case "$ROLE" in
      builder|verifier) ;;
      *) echo "ERROR: --role must be 'builder' or 'verifier' (got: '$ROLE')" >&2; exit 2 ;;
    esac
    [ -n "$AGENT_TYPE" ] || { echo "ERROR: --agent-type is required" >&2; exit 2; }

    # Defense in depth: validate --skill-hash BEFORE ever touching the state
    # file, even though scripts/team/assign.sh (the normal caller) already
    # rejects colon-containing skill paths itself. Something could call this
    # subcommand directly, bypassing assign.sh's check, so this subcommand
    # must not trust its caller.
    #
    # "path:hash,path:hash,..." is parsed below by splitting each entry on
    # its FIRST colon: skill paths in this repo are POSIX-relative (see
    # skills/*/SKILL.md and how they're referenced elsewhere in this repo --
    # never absolute, never Windows-style, so never containing a colon), so
    # the first colon always separates path from the hex sha256 that follows.
    # A colon-containing path (e.g. a Windows absolute path like
    # "C:/fakepath/skill.md", realistic input on this project's primary
    # platform) would otherwise silently split into garbage instead of
    # failing -- exactly the silent-corruption bug this validation closes.
    # An entry with zero colons is still valid (path only, no hash) and
    # records (path, sha256: null); an entry with exactly one colon is valid
    # only if the text after it actually looks like a sha256 hex hash --
    # otherwise that colon is almost certainly part of the path itself, not
    # a path/hash separator, so it's rejected too. Two or more colons is
    # always rejected outright.
    if [ -n "$SKILL_HASH" ]; then
      IFS=',' read -ra _SKILL_HASH_ENTRIES <<< "$SKILL_HASH"
      for _entry in "${_SKILL_HASH_ENTRIES[@]}"; do
        [ -n "$_entry" ] || continue
        _colon_count=$(awk -F: '{print NF-1}' <<< "$_entry")
        case "$_colon_count" in
          0) ;; # path only, no colon -- fine
          1)
            _hash_part="${_entry#*:}"
            if ! [[ "$_hash_part" =~ ^[0-9a-fA-F]+$ ]]; then
              echo "ERROR: invalid --skill-hash entry '$_entry': skill paths must not contain a colon and must be relative POSIX-style paths (e.g. skills/foo/SKILL.md) -- the text after the colon does not look like a sha256 hash, which usually means the colon is part of the path itself" >&2
              exit 2
            fi
            ;;
          *)
            echo "ERROR: invalid --skill-hash entry '$_entry': skill paths must not contain a colon and must be relative POSIX-style paths (e.g. skills/foo/SKILL.md)" >&2
            exit 2
            ;;
        esac
      done
    fi

    # require_task_state exits (before any write) if the state file or task is
    # missing, or if the record's own state is present but unusable.
    require_task_state "$ID"
    # Refused from the frozen stop -- see record-external-action's comment for
    # why the state comes from a global rather than a command substitution.
    RA_STATE="$TASK_STATE_VALUE"
    if [ "$RA_STATE" = "needs-reassessment" ]; then
      reassessment_required_error "$ID" "record an assignment"
      exit 1
    fi
    # The array this subcommand appends to. Absent/null is a legitimate legacy
    # record (the `// []` in the write below starts one); a present non-array
    # is refused by name here rather than blowing up anonymously inside
    # atomic_update's jq as an "internal jq failure".
    require_appendable_array "$ID" "assignments"

    # "path:hash,path:hash,..." -> [{path, sha256}, ...]. Split each entry on
    # its FIRST colon: skill paths in this repo are POSIX-relative (no colons),
    # so the first colon always separates path from the hex sha256 that follows.
    # An entry with no colon still records (path, sha256: null) rather than
    # silently dropping it.
    SKILLS_JSON=$(jq -R -c '
      split(",") | map(select(length > 0)) | map(
        (index(":")) as $i
        | if $i == null then {path: ., sha256: null}
          else {path: .[0:$i], sha256: .[($i + 1):]} end
      )
    ' <<< "$SKILL_HASH")

    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg role "$ROLE" --arg agent_type "$AGENT_TYPE" \
      --argjson skills "$SKILLS_JSON" --arg now "$NOW" \
      --arg acceptance "$ACCEPTANCE" --arg snapshot "$SNAPSHOT" '
      (if $acceptance == "" then null else $acceptance end) as $acceptance_val
      | (if $snapshot == "" then null else $snapshot end) as $snapshot_val
      | .tasks[$id].assignments = ((.tasks[$id].assignments // []) + [{
          role: $role, agent_type: $agent_type, skills: $skills,
          assigned_at: $now, acceptance_criteria: $acceptance_val,
          code_snapshot: $snapshot_val
        }])
      | .tasks[$id].updated_at = $now
    '
    SKILL_COUNT=$(echo "$SKILLS_JSON" | jq 'length')
    echo "RECORDED-ASSIGNMENT $ID role=$ROLE agent_type=$AGENT_TYPE skills=$SKILL_COUNT"
    ;;

  record-evidence)
    # Part 1.6 advisory check, run before any of this subcommand's normal
    # work below.
    warn_if_state_not_gitignored

    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-evidence <id> --command \"<cmd>\" --exit-code N --tests-total N --tests-skipped N --output-file <path> [--artifact <path>]... [--cwd <path>]" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    EV_COMMAND=""; EXIT_CODE=""; TESTS_TOTAL=""; TESTS_SKIPPED=""; OUTPUT_FILE=""; CWD_ARG=""
    ARTIFACTS=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --command) [ $# -ge 2 ] || { echo "ERROR: --command requires a value" >&2; exit 2; }; EV_COMMAND="$2"; shift 2 ;;
        --exit-code) [ $# -ge 2 ] || { echo "ERROR: --exit-code requires a value" >&2; exit 2; }; EXIT_CODE="$2"; shift 2 ;;
        --tests-total) [ $# -ge 2 ] || { echo "ERROR: --tests-total requires a value" >&2; exit 2; }; TESTS_TOTAL="$2"; shift 2 ;;
        --tests-skipped) [ $# -ge 2 ] || { echo "ERROR: --tests-skipped requires a value" >&2; exit 2; }; TESTS_SKIPPED="$2"; shift 2 ;;
        --output-file) [ $# -ge 2 ] || { echo "ERROR: --output-file requires a value" >&2; exit 2; }; OUTPUT_FILE="$2"; shift 2 ;;
        --artifact) [ $# -ge 2 ] || { echo "ERROR: --artifact requires a value" >&2; exit 2; }; ARTIFACTS+=("$2"); shift 2 ;;
        --cwd) [ $# -ge 2 ] || { echo "ERROR: --cwd requires a value" >&2; exit 2; }; CWD_ARG="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    [ -n "$EV_COMMAND" ] || { echo "ERROR: --command is required" >&2; exit 2; }
    [ -n "$OUTPUT_FILE" ] || { echo "ERROR: --output-file is required" >&2; exit 2; }

    # Same validation style as `create`'s --budget check: non-negative
    # integers only, reject non-numeric input cleanly rather than silently
    # coercing it.
    [ -n "$EXIT_CODE" ] || { echo "ERROR: --exit-code is required" >&2; exit 2; }
    case "$EXIT_CODE" in
      ''|*[!0-9]*) echo "ERROR: --exit-code must be a non-negative integer (got: $EXIT_CODE)" >&2; exit 2 ;;
    esac
    [ -n "$TESTS_TOTAL" ] || { echo "ERROR: --tests-total is required" >&2; exit 2; }
    case "$TESTS_TOTAL" in
      ''|*[!0-9]*) echo "ERROR: --tests-total must be a non-negative integer (got: $TESTS_TOTAL)" >&2; exit 2 ;;
    esac
    [ -n "$TESTS_SKIPPED" ] || { echo "ERROR: --tests-skipped is required" >&2; exit 2; }
    case "$TESTS_SKIPPED" in
      ''|*[!0-9]*) echo "ERROR: --tests-skipped must be a non-negative integer (got: $TESTS_SKIPPED)" >&2; exit 2 ;;
    esac

    # Resolve --cwd itself to an absolute path FIRST, relative to the actual
    # invocation directory ($(pwd), the same default used when --cwd is
    # omitted) -- otherwise a caller-supplied relative --cwd (e.g. "subdir")
    # would leave every artifact/output_file path resolved below still
    # relative to some other, ambiguous base. This is the fix for the
    # artifact/output_file path-resolution ambiguity between recording time
    # and gate time (see complete-gate.sh's check 3): every path this
    # subcommand records from here on is stored fully absolute, so a later
    # `complete-gate.sh` run from any directory resolves it identically,
    # without ever needing to guess at or reconstruct a cwd.
    [ -n "$CWD_ARG" ] || CWD_ARG="$(pwd)"
    CWD_ARG=$(resolve_path "$CWD_ARG" "$(pwd)")

    # require_task_state exits (before any write) if the state file or task is
    # missing, or the record's state is unusable -- same defense-in-depth as
    # record-assignment.
    require_task_state "$ID"
    # Refused from the frozen stop -- see record-external-action's comment for
    # why the state comes from a global rather than a command substitution.
    RE_STATE="$TASK_STATE_VALUE"
    if [ "$RE_STATE" = "needs-reassessment" ]; then
      reassessment_required_error "$ID" "record evidence"
      exit 1
    fi
    # The array this subcommand appends to -- same rationale as
    # record-assignment's. complete-gate.sh validates the CONTENT of these
    # records when it reads them; this only settles that there is an array to
    # append to at all.
    require_appendable_array "$ID" "evidence"

    # --output-file: same ambiguity as --artifact below -- resolve to
    # absolute against the (now-absolute) recorded cwd before storing, so
    # complete-gate.sh's Bug-3 output_file check needs no cwd guessing either.
    OUTPUT_FILE=$(resolve_path "$OUTPUT_FILE" "$CWD_ARG")

    # Artifacts: resolve each to an absolute path against the (now-absolute)
    # recorded cwd BEFORE building the JSON array below -- an artifact
    # recorded as a relative path from one directory must resolve to the
    # same file regardless of which directory complete-gate.sh is later
    # invoked from; storing it pre-resolved is what makes that unambiguous,
    # rather than leaving complete-gate.sh to guess a cwd at check time.
    if [ "${#ARTIFACTS[@]}" -gt 0 ]; then
      RESOLVED_ARTIFACTS=()
      for _art in "${ARTIFACTS[@]}"; do
        RESOLVED_ARTIFACTS+=("$(resolve_path "$_art" "$CWD_ARG")")
      done
      ARTIFACTS=("${RESOLVED_ARTIFACTS[@]}")
    fi

    # Artifacts: bash array -> JSON array of strings, via jq --args so paths
    # containing spaces or special characters survive intact (each array
    # element reaches jq as its own argv entry). ${ARTIFACTS[@]+"${ARTIFACTS[@]}"}
    # is the portable idiom for "expand this array, or nothing, under set -u"
    # that also behaves under older bash where expanding a truly empty array
    # directly can error.
    ARTIFACTS_JSON=$(jq -c -n --args '$ARGS.positional' ${ARTIFACTS[@]+"${ARTIFACTS[@]}"})

    # Environment identity: OS + bash version is enough per BUILD_PLAN.md
    # Part 1.4's own instruction -- not overengineered further.
    ENV_ID="$(uname -s 2>/dev/null || echo unknown) / $(bash --version 2>/dev/null | head -1)"

    SNAPSHOT=$(compute_snapshot)
    NOW=$(now_iso)

    atomic_update --arg id "$ID" --arg command "$EV_COMMAND" --arg cwd "$CWD_ARG" \
      --arg env "$ENV_ID" --arg now "$NOW" --argjson exit_code "$EXIT_CODE" \
      --argjson tests_total "$TESTS_TOTAL" --argjson tests_skipped "$TESTS_SKIPPED" \
      --arg output_file "$OUTPUT_FILE" --argjson artifacts "$ARTIFACTS_JSON" \
      --arg snapshot "$SNAPSHOT" '
      .tasks[$id].evidence = ((.tasks[$id].evidence // []) + [{
          command: $command, cwd: $cwd, environment: $env, recorded_at: $now,
          exit_code: $exit_code, tests_total: $tests_total,
          tests_skipped: $tests_skipped, output_file: $output_file,
          artifacts: $artifacts, code_snapshot: $snapshot
        }])
      | .tasks[$id].updated_at = $now
    '
    ARTIFACT_COUNT=$(echo "$ARTIFACTS_JSON" | jq 'length')
    echo "RECORDED-EVIDENCE $ID exit_code=$EXIT_CODE tests_total=$TESTS_TOTAL tests_skipped=$TESTS_SKIPPED artifacts=$ARTIFACT_COUNT snapshot=\"$SNAPSHOT\""
    ;;

  status)
    # DISPLAY-ONLY, AND DELIBERATELY NOT HARDENED. `status` prints a record and
    # gates nothing: it takes no lock, performs no transition, and no other
    # code in this repo branches on its output as a safety decision (assign.sh
    # and complete-gate.sh read it, and complete-gate.sh validates every field
    # it then acts on, in its own require_evidence_* helpers). The `// empty`
    # below is therefore a legitimate default and not an instance of the class
    # the fail-closed section above exists to stop -- its worst case is
    # reporting "not found" for a record corrupted to null, which is a refusal,
    # not a permission. Keeping it unvalidated is also useful on purpose: this
    # is the command the refusal messages tell you to run when a record IS
    # corrupt, so it should show you what is actually stored rather than
    # refusing to look at it.
    ID="${2:-}"
    [ -n "$ID" ] || { echo "Usage: task-state.sh status <id>" >&2; exit 2; }
    if [ ! -f "$STATE" ]; then
      echo "ERROR: task '$ID' not found (no tasks recorded yet)" >&2
      exit 1
    fi
    TASK=$(jq --arg id "$ID" '.tasks[$id] // empty' "$STATE")
    if [ -z "$TASK" ]; then
      echo "ERROR: task '$ID' not found" >&2
      exit 1
    fi
    echo "$TASK"
    ;;

  list)
    # DISPLAY-ONLY, same reasoning as `status` above: no lock, no transition,
    # no decision. The `(.depends_on // [])` below is a formatting default for
    # a task with no dependencies -- `start`, which is where depends_on
    # actually gates something, reads it through require_string_array instead.
    if [ ! -f "$STATE" ] || [ "$(jq '.tasks | length' "$STATE")" = "0" ]; then
      echo "No tasks recorded."
      exit 0
    fi
    jq -r '
      .tasks[] |
      "\(.id)  [\(.state)]  \(.title)  (depends_on: \(
        (.depends_on // []) | if length == 0 then "none" else join(",") end
      ))"
    ' "$STATE"
    ;;

  *)
    cat >&2 <<'USAGE'
Usage: task-state.sh <command> [args]

Commands:
  create <id> <title> [--depends id1,id2,...] [--builder name] [--verifier name]
                       [--skills a,b] [--risk low|medium|high] [--budget N]
  start <id>
  check <id>
  complete <id> [--staleness-verified yes|no]
  fail <id> --reason "<why the attempt failed>"
            --hypothesis "<what will be different next attempt>"
  reassess <id> --specialist "<who/what reassessed>"
                --finding "<what the reassessment concluded>"
                [--additional-budget N] [--resume-state building|checking]
  block <id> <reason> [--resume-condition text]
  unblock <id>
  pause <id> --next-action "<exact next action text>"
  resume <id>
  record-external-action <id> --key <idempotency-key> --description "<what was done>"
  check-external-action <id> --key <idempotency-key>
  record-assignment <id> --role builder|verifier --agent-type name
                     [--skill-hash path:hash,path:hash,...]
                     [--acceptance-text text] [--code-snapshot text]
  record-evidence <id> --command "<cmd>" --exit-code N --tests-total N
                   --tests-skipped N --output-file <path>
                   [--artifact <path>]... [--cwd <path>]
  status <id>
  list

States: planned -> building -> checking -> done
        (any of planned/building/checking) -> blocked -> (restored state)
        (any of planned/building/checking) -> paused  -> (restored state)
        (building|checking) --fail--> building             (attempts remain)
        (building|checking) --fail--> needs-reassessment   (budget exhausted)
        needs-reassessment --reassess--> building|checking (the ONLY exit)

Bounded repair: `fail` increments a monotonic attempts_used counter and
requires a hypothesis that DIFFERS from the immediately preceding attempt's.
While attempts_used < budget the task returns to `building`; once it reaches
budget the task enters `needs-reassessment`, where fail/start/check/complete/
block/pause AND record-assignment/record-evidence/record-external-action are
ALL refused, and complete-gate.sh refuses it too. (`blocked` and `paused` are
suspensions rather than stops, so the record-* subcommands stay available
there.) Only `reassess` clears it, and only with a recorded specialist and
finding. `--additional-budget N` (N >= 1) RAISES the budget; omitting it grants
nothing, so the task returns to work still at its cap and re-trips on the next
`fail`. `--resume-state checking` is accepted only for a task whose history
shows it actually reached `checking`. attempts_used is never decreased and
budget is never lowered, by any subcommand; a `budget` or `attempts_used`
field that is present in the state file but is not a non-negative integer
(null included) is refused outright rather than defaulted, and a task whose
attempts_used has fallen behind its own recorded attempt history is refused
too. A field that is genuinely ABSENT (a pre-2.2 record) still defaults.

That same fail-closed rule covers EVERY decision-bearing field, not only the
two counters: state, depends_on, blocked_from, paused_from, attempts (and its
hypothesis / attempt_number), checkpoints (and its next_action /
code_snapshot), external_actions (and its key), history, assignments, evidence
and reassessments. Present but of the wrong type, null, or empty where the
schema always writes content => REFUSED, naming the task, the field and the
offending value, with nothing written. Genuinely absent => still defaults,
where a safe absent-case exists. `status` and `list` are display-only and are
deliberately not hardened; they gate nothing.

--reason, --hypothesis, --specialist and --finding must all carry actual
content: whitespace-only values are refused exactly as empty ones are.

Code-identity honesty: compute_snapshot returns the fixed placeholder
"no-git-repository" when there is no version control to identify the code with.
Two such values MATCH for every possible state of the code, so nothing that
compares snapshots may read that match as "unchanged". `resume` prints a third
"CODE CHECK: NOT VERIFIED" outcome in that case and records
staleness_verified=false on its history entry; complete-gate.sh's check 6 does
the same and passes the verdict here via `complete --staleness-verified no`,
which records staleness_verified on the checking -> done history entry. A
completion history entry with NO staleness_verified key was completed by
something that did not state one -- i.e. not by complete-gate.sh, which always
does.

Exit codes: 0 ok · 1 invalid transition / not found / duplicate id / unmet
            dependency / refused repair attempt (unchanged hypothesis)
            2 bad usage / missing jq dependency
            3 check-external-action ONLY: the task does not exist (see below)

check-external-action answers "is this key already recorded?" with its exit
status, and it is easy to get backwards:
  EXIT 0 = CONFIRMED RECORDED         -> SKIP the action, it is already done.
  EXIT 1 = CONFIRMED NOT RECORDED     -> PROCEED with the action.
  EXIT 2 = bad usage (e.g. no --key)  -> UNDETERMINED, do NOT proceed.
  EXIT 3 = the task does not exist    -> UNDETERMINED, do NOT proceed; fix
           the task id and re-check.
NONZERO NEVER MEANS "ALREADY DONE".

For an externally visible, non-idempotent action (opening a PR, posting a
note) under any concurrency, prefer the record-first idiom: call
record-external-action BEFORE performing the action and branch on its OUTPUT
("RECORDED-EXTERNAL-ACTION" = you newly recorded it, so do the action;
"ALREADY-RECORDED" = skip it). That test-and-append is atomic under the lock;
check-then-act is advisory only. See this script's file header.
USAGE
    exit 2
    ;;
esac
