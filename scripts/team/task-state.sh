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
#   task-state.sh record-decision <id> --blocked "<what is blocked>"
#                 --why "<why, including what was checked>"
#                 --recommend "<recommended option and reason>"
#                 --options "<each option's benefit and main pitfall>"
#                 --impact "<impact on scope, cost, and delivery>"
#                 --question "<one clear question>"
#   task-state.sh record-approval <id> --decision <decision-id>
#                 --scope "<what is approved>" --approved-by "<who/what approved>"
#                 --deployment-impact yes|no [--conditions "<text>"]
#   task-state.sh record-rejection <id> --decision <decision-id>
#                 --rejected-by "<who/what rejected>" --reason "<why>"
#   task-state.sh check-approval <id> --scope "<what you are about to do>"
#                 [--deployment]
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
# Decision cards + scoped approvals (Part 2.3) implement DESIGN.md's "User
# experience" ("Proceed automatically with reversible work within the agreed
# plan and budget. Ask only for missing access or material changes...") and its
# approval clause in full:
#
#   "A decision card contains: 1. What is blocked. 2. Why, including what was
#    checked. 3. Recommended option and reason. 4. Each option's benefit and
#    main pitfall. 5. Impact on scope, cost, and delivery. 6. One clear
#    question."
#
#   "Persist approvals with their scope, target revision, and relevant
#    conditions. Ask again only when those conditions materially change. A
#    MERGE APPROVAL IS NOT PERMISSION FOR AN UNEXPECTED DEPLOYMENT."
#
# ROUTINE REPAIRS PROCEED; MATERIAL DEVIATIONS WAIT. This part adds NOTHING to
# the ordinary repair path. A failed attempt inside budget still goes `fail` ->
# `building` and carries straight on, with no card, no approval and no extra
# step -- that is the "routine repairs proceed" half of this part's acceptance
# criterion and it is asserted by its own test. A decision card is raised
# EXPLICITLY, by calling `record-decision`, for a MATERIAL deviation. Nothing
# here raises one automatically, and nothing here makes the routine path
# harder; if it ever does, that is a defect against this paragraph.
#
#   record-decision <id> --blocked --why --recommend --options --impact
#                        --question
#     Allowed from planned, building or checking. Appends a card to the task's
#     own `decisions` array ({decision_id, blocked, why, recommend, options,
#     impact, question, status, raised_at, code_snapshot, decision_from}) and
#     moves the task to the new `awaiting-decision` state. `decision_id` is
#     "<task-id>-d<N>", stable and quotable in later commands.
#     ALL SIX FLAGS ARE REQUIRED and must carry actual content (whitespace-only
#     is refused exactly as empty is). That is not pedantry: DESIGN.md
#     enumerates six elements, and a card missing its recommendation or its
#     question is not a decision card -- it is a shrug that hands the whole
#     problem back to the person least equipped to answer it. The point of the
#     mechanism is that the team has already done the work of framing the
#     choice before it interrupts.
#
#   `awaiting-decision` is a REAL STOP, on exactly the same terms as
#   `needs-reassessment`: `start`, `check`, `complete`, `fail`, `block` and
#   `pause` are all refused from it, each pointing at the two commands that can
#   answer the card, and complete-gate.sh refuses it too (its check 1 requires
#   state `checking`; proven against a passing control in
#   tests/task-state-smoke.sh, so the refusal is not vacuous). `record-decision`
#   itself is refused from `awaiting-decision`, so exactly one card can be open
#   at a time, and from `needs-reassessment`, so a frozen task cannot be moved
#   sideways into a different freeze. The indirect doors are closed the same way
#   they are for `needs-reassessment`: `unblock` requires `blocked` and `resume`
#   requires `paused`, and neither state is reachable from here because `block`
#   and `pause` themselves refuse it.
#
#   ONE DELIBERATE DIFFERENCE FROM `needs-reassessment`, stated rather than left
#   to be discovered: record-assignment, record-evidence and
#   record-external-action are NOT refused from `awaiting-decision`. They are
#   refused from `needs-reassessment` because a task whose attempt budget is
#   exhausted should have nothing legitimate accreting on its record at all. A
#   task awaiting a decision is a different situation: it is waiting on a HUMAN,
#   while the session around it legitimately keeps recording what it checked
#   (DESIGN.md's card element 2 is "why, INCLUDING WHAT WAS CHECKED" -- that is
#   evidence) and what external actions have already happened, which is exactly
#   the wrap-up sequence `pause` exists to support. This follows the
#   `blocked`/`paused` precedent, where the same three stay available for the
#   same reason. What is frozen here is the WORK, not the audit trail.
#
#   record-approval <id> --decision <decision-id> --scope "..."
#                        --approved-by "..." --deployment-impact yes|no
#                        [--conditions "..."]
#   record-rejection <id> --decision <decision-id> --rejected-by "..."
#                         --reason "..."
#     The ONLY two exits from `awaiting-decision`. Both mark the open card
#     resolved (`status` becomes "approved" or "rejected") and restore the exact
#     state the task was in when the card was raised -- `decision_from`, read
#     through the same require_restorable_state enum guard `unblock` and
#     `resume` use, so a hand-edited restore target cannot send the task
#     straight to `done`.
#     REJECTION IS FIRST-CLASS, not an afterthought: a decision answered "no"
#     is answered, and it must not be left looking unanswered. It records who
#     rejected and why, in the task's own `rejections` array, and the work
#     resumes -- down some other path, which is the point of having asked.
#     `--approved-by` / `--rejected-by` are REQUIRED and non-blank: an
#     unattributed approval is precisely the "conceal failures" pattern
#     DESIGN.md's "Recovery and learning" forbids, in the one record whose whole
#     job is to say a human agreed to something.
#     `--deployment-impact yes|no` is REQUIRED, not a bare optional flag.
#     DESIGN.md says outright that a merge approval is not permission for an
#     unexpected deployment, so whether an approval carries deployment impact
#     has to be an EXPLICIT recorded property rather than something inferred
#     later from the scope text. Optional would make one of the two answers the
#     silent default, and a silent default on this particular question is the
#     failure DESIGN.md names.
#     The TARGET REVISION is not a flag at all: it is computed by
#     compute_snapshot() at approval time, the same way every other code
#     identity in this subsystem is. An approval is for the code as it actually
#     stood when it was granted, and letting a caller type that value in would
#     make the staleness check depend on the honesty of the thing being checked.
#
#   check-approval <id> --scope "<what you are about to do>" [--deployment]
#     READ-ONLY (takes no lock, never writes -- the same reasoning as
#     check-external-action: a read-only probe must not be able to block real
#     work). It answers ONE question -- "is the action I am about to take
#     covered by a valid approval?" -- and it answers it with its EXIT STATUS:
#
#       EXIT 0 => COVERED. A valid approval covers this action's scope, its
#                 revision and its deployment impact => PROCEED.
#       EXIT 1 => NOT COVERED: this task has no approval records at all.
#       EXIT 2 => BAD USAGE (e.g. no --scope) => UNDETERMINED, do NOT proceed.
#       EXIT 3 => THE TASK DOES NOT EXIST, or its record cannot be read =>
#                 UNDETERMINED, do NOT proceed; fix the task id and re-check.
#       EXIT 4 => NOT COVERED: approvals exist, but none of their scopes covers
#                 the action described.
#       EXIT 5 => NOT COVERED: an approval covers the scope, but THE REVISION
#                 HAS CHANGED since it was granted => reassess and ask again.
#       EXIT 6 => NOT COVERED: an approval covers the scope, but this action has
#                 DEPLOYMENT IMPACT that the approval did not carry. This is
#                 DESIGN.md's "a merge approval is not permission for an
#                 unexpected deployment", enforced.
#       EXIT 7 => UNDETERMINED: an approval covers the scope, but the revision
#                 could not be established (no version control), so whether it
#                 is still current cannot be answered => do NOT proceed.
#
#     *** NONZERO NEVER MEANS "APPROVED". *** Every single nonzero code above
#     means "do NOT take the action; ask". There is no input -- absent,
#     corrupt, unreadable, or merely unmatched -- that this subcommand turns
#     into permission; the only verdict that produces exit 0 is one validated
#     approval record that matched on all three of scope, deployment impact and
#     revision. This is the same discipline, for the same reason, as
#     check-external-action's "NONZERO NEVER MEANS ALREADY DONE" contract: a
#     caller branching on exit status is the natural shell idiom, and an
#     exit-code contract that reads the wrong way round in one edge case is how
#     a safety mechanism becomes the cause of the thing it was built to stop.
#     Every case also prints a distinguishing line -- APPROVAL-COVERS or
#     NOT-COVERED/UNDETERMINED plus the reason -- so a caller reading output
#     rather than exit status can tell them apart too.
#
#     THREE DISCLOSED LIMITS, so nothing here is overclaimed:
#       1. Scope matching is a NORMALISED EXACT MATCH (case-folded, trimmed,
#          internal whitespace collapsed), never a substring or prefix test --
#          a prefix test would let "merge PR 12" cover "merge PR 12 and deploy
#          to production". A paraphrased action therefore reports NOT COVERED
#          and you ask again. That is the safe direction on purpose.
#       2. `--conditions` is free text. check-approval PRINTS the recorded
#          conditions verbatim on the exit-0 path and states plainly that it did
#          not and cannot evaluate them; satisfying them is the caller's job.
#          Exit 0 means exactly "scope, revision and deployment impact are
#          covered", and it says so rather than implying more.
#       3. ONE CORRUPT ENTRY REFUSES EVERY SCOPE ON THAT TASK (exit 3), not
#          just that entry's own scope -- the whole approvals array is
#          validated before any scope matching, so a single malformed record
#          blocks approval checks a perfectly good approval beside it would
#          have covered. Same fail-closed whole-array validation `attempts`,
#          `checkpoints` and `external_actions` already use; narrowing it
#          would leave the untrusted remainder unexamined in the one read
#          whose answer is permission. The cost is availability -- one bad
#          record blocks every approval check on that task until it is
#          repaired -- and that is the cost being chosen, not overlooked.
#
#     THE NON-GIT CASE (exit 7), decided deliberately: compute_snapshot()
#     returns the constant "no-git-repository" when it cannot identify the code,
#     and two such values match for every possible state of the code. Reading
#     that match as "the revision is unchanged" would be this project's whole
#     defect class landing in the one place where "condition satisfied"
#     authorises an action, so it is its own outcome instead. It is kept
#     distinct from exit 5 because "the code moved" and "we could not tell
#     whether the code moved" are different claims. In a project without version
#     control this means check-approval can never answer 0 -- the intended
#     degradation, since it degrades to "ask a human every time", never to
#     "proceed". (`resume` warns rather than refusing on the same placeholder;
#     that is not an inconsistency -- `resume` reports on work that is resuming
#     either way, while check-approval exists solely to answer "may I?", and the
#     honest answer to "may I?" when you cannot tell is no.)
#
# States: planned -> building -> checking -> done
#         (any of planned/building/checking) -> blocked -> (restored state)
#         (any of planned/building/checking) -> paused  -> (restored state)
#         (any of planned/building/checking) -> awaiting-decision
#                                                       -> (restored state)
#         (building|checking) --fail--> building              (attempts remain)
#         (building|checking) --fail--> needs-reassessment    (budget exhausted)
#         needs-reassessment --reassess--> building|checking  (the ONLY exit)
#         awaiting-decision --record-approval|record-rejection--> (restored
#                                                     state; the ONLY exits)
#
# Exit codes: 0 ok
#             1 invalid transition / not found / duplicate id / unmet dependency
#               / a refused repair attempt (unchanged hypothesis)
#               (also: check-external-action's "key NOT recorded, PROCEED")
#               (also: check-approval's "no approval recorded at all")
#             2 bad usage / missing jq dependency
#             3 check-external-action ONLY: the task does not exist, so
#               "already recorded?" could not be determined -- do NOT proceed
#             3 check-approval ONLY: the task does not exist or its record is
#               unreadable -- UNDETERMINED, do NOT proceed
#             4/5/6/7 check-approval ONLY: scope not covered / revision changed
#               / deployment impact not covered / revision undeterminable --
#               all four mean do NOT proceed
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
# record-external-action/record-decision/record-approval/record-rejection) also
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

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (install: winget install jqlang.jq)" >&2
  exit 2
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "ERROR: sha256sum is required (used by compute_snapshot for dirty-tree content hashing)" >&2
  exit 2
fi

# Guard/helper library. Everything this script needs beyond dependency
# checking and CLI dispatch lives in task-state-lib.sh, sourced from THIS
# SCRIPT'S OWN DIRECTORY rather than the current one. That distinction is
# load-bearing: install.bat copies both files to %CLAUDE_HOME%\scripts\team\,
# and the team skills invoke this script BY ABSOLUTE PATH from whatever
# project directory the session happens to be in, so a cwd-relative source
# would find nothing at all outside a checkout of this repo. Same $0-relative
# resolution convention assign.sh and complete-gate.sh already use to find
# their sibling scripts.
#
# This block sits AFTER the two dependency checks above, deliberately: the
# `dirname` below is an external binary, so resolving the library first
# would, on a stripped PATH, report a missing library instead of the missing
# jq that is the actual and much more likely problem. Dependency checks stay
# first, exactly where they were, and keep reporting exactly what they did.
HERE="$(cd "$(dirname "$0")" && pwd)"
TASK_STATE_LIB="$HERE/task-state-lib.sh"
if [ ! -f "$TASK_STATE_LIB" ]; then
  echo "ERROR: required library not found: $TASK_STATE_LIB" >&2
  echo "  task-state.sh cannot run without it. The two files are installed side by side (install.bat copies both into scripts\team\) and must stay that way. Refusing to run — nothing was changed." >&2
  exit 2
fi
# source-path=SCRIPTDIR makes shellcheck -x resolve the library the same way
# this script does at runtime -- relative to the script, not to whatever
# directory shellcheck was invoked from (scripts/ci-checks.sh runs it from the
# repo root). Without it, shellcheck cannot see that STATE_FAIL_EXIT below is
# read by the library's state_field_fail().
# shellcheck source-path=SCRIPTDIR
# shellcheck source=task-state-lib.sh
. "$TASK_STATE_LIB"

CMD="${1:-}"

# Every mutating command is serialized against every other mutating command
# via a single project-wide lock, held for the command's entire
# read-modify-write sequence (see acquire_lock() above).
#
# `check-external-action` is deliberately ABSENT from this list: it is
# strictly read-only (it never calls atomic_update) so it needs no lock, and
# taking one would let a read-only idempotency probe block real work.
# `check-approval` (Part 2.3) is absent for exactly the same two reasons, and
# the reasoning is worth restating rather than inferring: it never calls
# atomic_update, and it is the probe a caller is expected to run BEFORE every
# action it is unsure about, so making it contend for the project-wide lock
# would turn "check whether you are allowed" into a source of delay and give
# callers a reason to skip it. It reads the state file without a lock, which
# is safe because atomic_update replaces that file by rename: a concurrent
# write is never half-visible, so the worst case is that check-approval
# answers against the state as of an instant slightly before or after a
# concurrent record-approval -- and both of those are states this answer was
# legitimately true for.
case "$CMD" in
  create|start|check|complete|fail|reassess|block|unblock|pause|resume|record-assignment|record-evidence|record-external-action|record-decision|record-approval|record-rejection) acquire_lock ;;
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
        decision_from: null,
        created_at: $now, updated_at: $now,
        history: [{from: null, to: "planned", at: $now}],
        assignments: [],
        evidence: [],
        checkpoints: [],
        external_actions: [],
        attempts: [],
        reassessments: [],
        decisions: [],
        approvals: [],
        rejections: []
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
      elif [ "$CUR_STATE" = "awaiting-decision" ]; then
        decision_required_error "$ID" "start"
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
      elif [ "$CUR_STATE" = "awaiting-decision" ]; then
        decision_required_error "$ID" "move to checking"
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
      elif [ "$CUR_STATE" = "awaiting-decision" ]; then
        decision_required_error "$ID" "complete"
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
      # The OTHER real stop. A task waiting on a human decision has no attempt
      # in flight to fail either, and letting `fail` run from here would burn
      # attempt budget against a question nobody has answered yet.
      awaiting-decision)
        decision_required_error "$ID" "record another failed attempt"
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
      # Same closure for the Part 2.3 stop: if block accepted an
      # awaiting-decision task, `unblock` would become a second exit from it --
      # and worse, one that discards the open card without answering it.
      awaiting-decision) decision_required_error "$ID" "block"; exit 1 ;;
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
      # Same closure again: pause is refused, so `resume` (which requires state
      # 'paused') can never become an indirect exit from 'awaiting-decision'.
      awaiting-decision)
        decision_required_error "$ID" "pause"
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

  record-decision)
    # Part 2.3. Raise a decision card and STOP the task on it. See this file's
    # header for the full contract; the short version is: routine repairs
    # proceed untouched, a MATERIAL deviation is raised here explicitly and the
    # task waits in `awaiting-decision` until a human answers.
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-decision <id> --blocked \"<what is blocked>\" --why \"<why, including what was checked>\" --recommend \"<recommended option and reason>\" --options \"<each option's benefit and main pitfall>\" --impact \"<impact on scope, cost, and delivery>\" --question \"<one clear question>\"" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    DC_BLOCKED=""; DC_WHY=""; DC_RECOMMEND=""; DC_OPTIONS=""; DC_IMPACT=""; DC_QUESTION=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --blocked) [ $# -ge 2 ] || { echo "ERROR: --blocked requires a value" >&2; exit 2; }; DC_BLOCKED="$2"; shift 2 ;;
        --why) [ $# -ge 2 ] || { echo "ERROR: --why requires a value" >&2; exit 2; }; DC_WHY="$2"; shift 2 ;;
        --recommend) [ $# -ge 2 ] || { echo "ERROR: --recommend requires a value" >&2; exit 2; }; DC_RECOMMEND="$2"; shift 2 ;;
        --options) [ $# -ge 2 ] || { echo "ERROR: --options requires a value" >&2; exit 2; }; DC_OPTIONS="$2"; shift 2 ;;
        --impact) [ $# -ge 2 ] || { echo "ERROR: --impact requires a value" >&2; exit 2; }; DC_IMPACT="$2"; shift 2 ;;
        --question) [ $# -ge 2 ] || { echo "ERROR: --question requires a value" >&2; exit 2; }; DC_QUESTION="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    # ALL SIX REQUIRED, all six non-blank, all six checked BEFORE any state
    # read and before any write -- so a rejected card leaves the state file
    # byte-for-byte unchanged. DESIGN.md ("User experience") enumerates exactly
    # these six elements; a card that omits one is not a decision card, and
    # accepting a partial one would let the mechanism degrade into an
    # interruption that hands the whole problem back unframed. Whitespace-only
    # is refused the same way empty is, for the same reason it is everywhere
    # else here: "   " records a field that merely LOOKS answered.
    require_nonblank "--blocked" "$DC_BLOCKED" \
      "DESIGN.md decision card element 1: what is blocked"
    require_nonblank "--why" "$DC_WHY" \
      "DESIGN.md decision card element 2: why, including what was checked"
    require_nonblank "--recommend" "$DC_RECOMMEND" \
      "DESIGN.md decision card element 3: recommended option and reason — a card with no recommendation asks the least-equipped person to do the team's thinking"
    require_nonblank "--options" "$DC_OPTIONS" \
      "DESIGN.md decision card element 4: each option's benefit and main pitfall"
    require_nonblank "--impact" "$DC_IMPACT" \
      "DESIGN.md decision card element 5: impact on scope, cost, and delivery"
    require_nonblank "--question" "$DC_QUESTION" \
      "DESIGN.md decision card element 6: one clear question — a card with no question cannot be answered"

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    case "$CUR_STATE" in
      planned|building|checking) ;;
      # Only ONE card can be open at a time. Refusing here is what makes "the
      # latest decisions entry is the open one" true by construction, which is
      # what require_open_decision relies on.
      awaiting-decision)
        echo "ERROR: task '$ID' is already in state 'awaiting-decision' — a decision card is open and unanswered, so a second one cannot be raised on top of it." >&2
        decision_required_error "$ID" "raise another decision card"
        exit 1
        ;;
      needs-reassessment)
        reassessment_required_error "$ID" "raise a decision card"
        exit 1
        ;;
      *)
        echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot raise a decision card from this state (must be one of planned, building, checking)" >&2
        exit 1
        ;;
    esac

    # The array this subcommand appends to and that record-approval /
    # record-rejection then read a decision out of. Settled here, at the point
    # it is WRITTEN to, not only where the damage would later be read back --
    # and its validated length is also what numbers the card.
    require_object_array "$ID" "decisions"
    DECISION_ID="$ID-d$((ARRAY_LENGTH + 1))"

    # Snapshot the code AS IT WAS WHEN THE QUESTION WAS ASKED, so a later
    # reader can see which revision the card's "what was checked" refers to.
    SNAPSHOT=$(compute_snapshot)
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg from "$CUR_STATE" \
      --arg did "$DECISION_ID" --arg blocked "$DC_BLOCKED" --arg why "$DC_WHY" \
      --arg recommend "$DC_RECOMMEND" --arg options "$DC_OPTIONS" \
      --arg impact "$DC_IMPACT" --arg question "$DC_QUESTION" \
      --arg snapshot "$SNAPSHOT" '
      .tasks[$id].decisions = ((.tasks[$id].decisions // []) + [{
          decision_id: $did,
          blocked: $blocked,
          why: $why,
          recommend: $recommend,
          options: $options,
          impact: $impact,
          question: $question,
          status: "open",
          raised_at: $now,
          resolved_at: null,
          code_snapshot: $snapshot,
          decision_from: $from
        }])
      | .tasks[$id].decision_from = $from
      | .tasks[$id].state = "awaiting-decision"
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{
          from: $from, to: "awaiting-decision", at: $now,
          decision_id: $did, question: $question, code_snapshot: $snapshot
        }]
    '
    echo "RECORDED-DECISION $ID decision=$DECISION_ID from=$CUR_STATE state=awaiting-decision snapshot=\"$SNAPSHOT\""
    # The card is printed in full, in DESIGN.md's own order, because it is a
    # communication artifact as much as a state record -- the lead is meant to
    # be able to put this in front of a person unchanged.
    echo "DECISION CARD $DECISION_ID"
    echo "  1. BLOCKED:    $DC_BLOCKED"
    echo "  2. WHY:        $DC_WHY"
    echo "  3. RECOMMEND:  $DC_RECOMMEND"
    echo "  4. OPTIONS:    $DC_OPTIONS"
    echo "  5. IMPACT:     $DC_IMPACT"
    echo "  6. QUESTION:   $DC_QUESTION"
    echo "THIS TASK IS NOW STOPPED. No start, check, complete, fail, block or pause is accepted, and complete-gate.sh refuses it too. Answer the card to release it:"
    echo "  approve: task-state.sh record-approval $ID --decision $DECISION_ID --scope \"<what is approved>\" --approved-by \"<who/what approved>\" --deployment-impact yes|no [--conditions \"<text>\"]"
    echo "  reject:  task-state.sh record-rejection $ID --decision $DECISION_ID --rejected-by \"<who/what rejected>\" --reason \"<why>\""
    ;;

  record-approval)
    # Part 2.3. One of the two exits from `awaiting-decision`. Records a SCOPED
    # approval -- scope, target revision, conditions, who approved, and whether
    # it carries deployment impact -- and restores the state the task was in
    # when the card was raised.
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-approval <id> --decision <decision-id> --scope \"<what is approved>\" --approved-by \"<who/what approved>\" --deployment-impact yes|no [--conditions \"<text>\"]" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    AP_DECISION=""; AP_SCOPE=""; AP_BY=""; AP_CONDITIONS=""; AP_CONDITIONS_GIVEN=""
    AP_DEPLOYMENT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --decision) [ $# -ge 2 ] || { echo "ERROR: --decision requires a value" >&2; exit 2; }; AP_DECISION="$2"; shift 2 ;;
        --scope) [ $# -ge 2 ] || { echo "ERROR: --scope requires a value" >&2; exit 2; }; AP_SCOPE="$2"; shift 2 ;;
        --approved-by) [ $# -ge 2 ] || { echo "ERROR: --approved-by requires a value" >&2; exit 2; }; AP_BY="$2"; shift 2 ;;
        --conditions) [ $# -ge 2 ] || { echo "ERROR: --conditions requires a value" >&2; exit 2; }; AP_CONDITIONS="$2"; AP_CONDITIONS_GIVEN=1; shift 2 ;;
        --deployment-impact)
          [ $# -ge 2 ] || { echo "ERROR: --deployment-impact requires a value (yes or no)" >&2; exit 2; }
          case "$2" in
            yes) AP_DEPLOYMENT="true" ;;
            no)  AP_DEPLOYMENT="false" ;;
            *)   echo "ERROR: --deployment-impact must be 'yes' or 'no' (got: $2)" >&2; exit 2 ;;
          esac
          shift 2
          ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    require_nonblank "--decision" "$AP_DECISION" \
      "an approval must say which decision card it answers"
    require_nonblank "--scope" "$AP_SCOPE" \
      "an approval with no recorded scope is an approval of everything, which is not a scoped approval at all"
    require_nonblank "--approved-by" "$AP_BY" \
      "an unattributed approval is exactly the 'conceal failures' pattern DESIGN.md forbids, in the one record whose job is to say a human agreed"
    if [ -n "$AP_CONDITIONS_GIVEN" ]; then
      require_nonblank "--conditions" "$AP_CONDITIONS" \
        "omit --conditions entirely to record no conditions; a blank one records a condition that merely looks stated"
    fi
    # REQUIRED, deliberately, and deliberately yes/no rather than a bare
    # presence flag. DESIGN.md: "A merge approval is not permission for an
    # unexpected deployment." Whether an approval carries deployment impact is
    # therefore a property that has to be STATED, not inferred later from the
    # scope text and not silently defaulted -- a bare flag would make one of the
    # two answers the default, and a silent default on this exact question is
    # the failure DESIGN.md names.
    [ -n "$AP_DEPLOYMENT" ] || {
      echo "ERROR: --deployment-impact is required and must be 'yes' or 'no'. DESIGN.md: a merge approval is not permission for an unexpected deployment — whether this approval covers deployment has to be stated explicitly, not inferred from the scope text later." >&2
      exit 2
    }

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "awaiting-decision" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot record an approval (must be 'awaiting-decision'). An approval answers an OPEN decision card; raise one with 'task-state.sh record-decision $ID --blocked ... --why ... --recommend ... --options ... --impact ... --question ...' if a material deviation genuinely needs one." >&2
      exit 1
    fi

    require_open_decision "$ID"
    if [ "$AP_DECISION" != "$OPEN_DECISION_ID" ]; then
      echo "ERROR: task '$ID' — --decision '$AP_DECISION' does not name the decision card this task is waiting on, which is '$OPEN_DECISION_ID'. Refusing this approval — nothing was changed." >&2
      echo "  An approval recorded against the wrong card would resolve a question nobody asked and leave the real one open. Re-run with --decision $OPEN_DECISION_ID, or run 'task-state.sh status $ID' to read the open card." >&2
      exit 1
    fi

    # Same enum guard `unblock` and `resume` use on blocked_from/paused_from,
    # for the same reason: `record-decision` only ever records
    # planned/building/checking, and an unvalidated restore target would let a
    # hand-edited decision_from move the task straight to `done` -- past
    # `checking`, past complete-gate.sh, past the entire verification contract.
    require_restorable_state "$ID" "decision_from"
    RESTORE="$RESTORE_STATE"
    if [ "$RESTORE" = "missing" ]; then
      echo "ERROR: task '$ID' has no recorded prior state to restore to" >&2
      exit 1
    fi
    require_appendable_array "$ID" "approvals"

    # THE TARGET REVISION IS COMPUTED, NEVER SUPPLIED. An approval is for the
    # code as it actually stood when it was granted; letting a caller type that
    # value in would make the staleness check depend on the honesty of the
    # thing being checked. Same compute_snapshot() every other code identity in
    # this subsystem uses -- including its "no-git-repository" placeholder,
    # which check-approval detects and reports as UNDETERMINED rather than
    # matching against itself and claiming the revision is unchanged.
    TARGET_REVISION=$(compute_snapshot)
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg did "$AP_DECISION" \
      --arg scope "$AP_SCOPE" --arg by "$AP_BY" --arg conditions "$AP_CONDITIONS" \
      --argjson deployment "$AP_DEPLOYMENT" --arg revision "$TARGET_REVISION" \
      --arg restore "$RESTORE" '
      (if $conditions == "" then null else $conditions end) as $conditions_val
      | .tasks[$id].approvals = ((.tasks[$id].approvals // []) + [{
          decision_id: $did,
          scope: $scope,
          target_revision: $revision,
          conditions: $conditions_val,
          approved_by: $by,
          deployment_impact: $deployment,
          approved_at: $now
        }])
      | .tasks[$id].decisions = [ .tasks[$id].decisions[]
          | if .decision_id == $did then (.status = "approved" | .resolved_at = $now) else . end ]
      | .tasks[$id].decision_from = null
      | .tasks[$id].state = $restore
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{
          from: "awaiting-decision", to: $restore, at: $now,
          decision_id: $did, resolution: "approved",
          scope: $scope, approved_by: $by,
          deployment_impact: $deployment,
          target_revision: $revision,
          conditions: $conditions_val
        }]
    '
    echo "RECORDED-APPROVAL $ID decision=$AP_DECISION scope=\"$AP_SCOPE\" approved_by=\"$AP_BY\" deployment_impact=$AP_DEPLOYMENT revision=\"$TARGET_REVISION\" state=$RESTORE"
    if [ -n "$AP_CONDITIONS" ]; then
      echo "CONDITIONS: $AP_CONDITIONS"
      echo "  Recorded verbatim. task-state.sh does NOT evaluate conditions — check-approval prints them back and says so; satisfying them is the caller's job."
    fi
    if [ "$AP_DEPLOYMENT" = "false" ]; then
      echo "NOTE: this approval does NOT cover deployment. 'check-approval $ID --scope \"...\" --deployment' will refuse against it (exit 6). DESIGN.md: a merge approval is not permission for an unexpected deployment."
    fi
    echo "SCOPE MATCHING IS AN EXACT (normalised) MATCH: a later 'check-approval $ID --scope \"...\"' is covered by this approval only if the scope text matches \"$AP_SCOPE\" up to case and whitespace. A paraphrase reports NOT COVERED and you will be asked again."
    ;;

  record-rejection)
    # Part 2.3. The OTHER exit from `awaiting-decision`. A decision answered
    # "no" is answered: it is recorded, attributed and reasoned, and it must
    # never be left looking like an unanswered card. The work resumes in the
    # state it was raised from -- down some other path, which is the point of
    # having asked.
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh record-rejection <id> --decision <decision-id> --rejected-by \"<who/what rejected>\" --reason \"<why>\"" >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    RJ_DECISION=""; RJ_BY=""; RJ_REASON=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --decision) [ $# -ge 2 ] || { echo "ERROR: --decision requires a value" >&2; exit 2; }; RJ_DECISION="$2"; shift 2 ;;
        --rejected-by) [ $# -ge 2 ] || { echo "ERROR: --rejected-by requires a value" >&2; exit 2; }; RJ_BY="$2"; shift 2 ;;
        --reason) [ $# -ge 2 ] || { echo "ERROR: --reason requires a value" >&2; exit 2; }; RJ_REASON="$2"; shift 2 ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    require_nonblank "--decision" "$RJ_DECISION" \
      "a rejection must say which decision card it answers"
    require_nonblank "--rejected-by" "$RJ_BY" \
      "an unattributed rejection is as unreviewable later as an unattributed approval"
    require_nonblank "--reason" "$RJ_REASON" \
      "a rejection with no recorded reason tells the next attempt nothing about why this option was refused"

    require_task_state "$ID"
    CUR_STATE="$TASK_STATE_VALUE"
    if [ "$CUR_STATE" != "awaiting-decision" ]; then
      echo "ERROR: task '$ID' is in state '$CUR_STATE', cannot record a rejection (must be 'awaiting-decision'). A rejection answers an OPEN decision card." >&2
      exit 1
    fi

    require_open_decision "$ID"
    if [ "$RJ_DECISION" != "$OPEN_DECISION_ID" ]; then
      echo "ERROR: task '$ID' — --decision '$RJ_DECISION' does not name the decision card this task is waiting on, which is '$OPEN_DECISION_ID'. Refusing this rejection — nothing was changed." >&2
      echo "  A rejection recorded against the wrong card would mark a question answered that nobody asked and leave the real one open. Re-run with --decision $OPEN_DECISION_ID, or run 'task-state.sh status $ID' to read the open card." >&2
      exit 1
    fi

    require_restorable_state "$ID" "decision_from"
    RESTORE="$RESTORE_STATE"
    if [ "$RESTORE" = "missing" ]; then
      echo "ERROR: task '$ID' has no recorded prior state to restore to" >&2
      exit 1
    fi
    require_appendable_array "$ID" "rejections"

    SNAPSHOT=$(compute_snapshot)
    NOW=$(now_iso)
    atomic_update --arg id "$ID" --arg now "$NOW" --arg did "$RJ_DECISION" \
      --arg by "$RJ_BY" --arg reason "$RJ_REASON" --arg snapshot "$SNAPSHOT" \
      --arg restore "$RESTORE" '
      .tasks[$id].rejections = ((.tasks[$id].rejections // []) + [{
          decision_id: $did,
          rejected_by: $by,
          reason: $reason,
          code_snapshot: $snapshot,
          rejected_at: $now
        }])
      | .tasks[$id].decisions = [ .tasks[$id].decisions[]
          | if .decision_id == $did then (.status = "rejected" | .resolved_at = $now) else . end ]
      | .tasks[$id].decision_from = null
      | .tasks[$id].state = $restore
      | .tasks[$id].updated_at = $now
      | .tasks[$id].history += [{
          from: "awaiting-decision", to: $restore, at: $now,
          decision_id: $did, resolution: "rejected",
          rejected_by: $by, reason: $reason
        }]
    '
    echo "RECORDED-REJECTION $ID decision=$RJ_DECISION rejected_by=\"$RJ_BY\" state=$RESTORE"
    echo "REASON: $RJ_REASON"
    echo "NOTE: a rejection records NO approval, so 'check-approval $ID --scope \"...\"' is unaffected by it — the rejected option is still not approved, which is the whole point."
    ;;

  check-approval)
    # Part 2.3. READ-ONLY: takes no lock, never writes.
    #
    # *** NONZERO NEVER MEANS "APPROVED". *** Read that again before editing
    # anything below. Every nonzero code this subcommand can produce means "do
    # NOT take the action; ask". The ONLY route to exit 0 is one validated
    # approval record that matched on all three of scope, deployment impact and
    # revision.
    #   EXIT 0 => COVERED (scope + revision + deployment impact) => PROCEED.
    #   EXIT 1 => NOT COVERED: no approval records at all.
    #   EXIT 2 => bad usage => UNDETERMINED, do NOT proceed.
    #   EXIT 3 => task does not exist / record unreadable => UNDETERMINED, do
    #             NOT proceed; fix the task id and re-check.
    #   EXIT 4 => NOT COVERED: no approval's scope covers this action.
    #   EXIT 5 => NOT COVERED: the revision changed since the approval.
    #   EXIT 6 => NOT COVERED: this action has deployment impact the approval
    #             did not carry ("a merge approval is not permission for an
    #             unexpected deployment").
    #   EXIT 7 => UNDETERMINED: the revision could not be established (no
    #             version control), so currency could not be checked.
    # This is the same discipline, for the same reason, as
    # check-external-action's contract above: a caller branching on exit status
    # is the natural shell idiom, and an exit-code contract that reads the wrong
    # way round in one edge case is how a safety mechanism becomes the cause of
    # the thing it was built to prevent.
    ID="${2:-}"
    [ -n "$ID" ] || {
      echo "Usage: task-state.sh check-approval <id> --scope \"<what you are about to do>\" [--deployment]" >&2
      echo "  NONZERO NEVER MEANS APPROVED: 0 = covered, proceed; every other code = do NOT proceed." >&2
      exit 2
    }
    if [ $# -ge 2 ]; then shift 2; else shift $#; fi

    CA_SCOPE=""
    # DEFAULT "no", and the default is the SAFE direction here, unlike
    # `complete --staleness-verified` where a presence-only flag would have made
    # "verified" the silent default. Here presence of --deployment only ever
    # makes the check HARDER to pass (it additionally requires an approval that
    # explicitly carried deployment impact). Its absence cannot authorise a
    # deployment: it describes the action the CALLER says it is about to take,
    # and a caller that is about to deploy without saying so has not been let
    # through by this flag's default -- it has simply not asked the question it
    # meant to ask. The recorded side of that pair, record-approval's
    # --deployment-impact, is required precisely because THAT one could
    # otherwise default toward permission.
    CA_DEPLOYMENT="no"
    while [ $# -gt 0 ]; do
      case "$1" in
        --scope) [ $# -ge 2 ] || { echo "ERROR: --scope requires a value" >&2; exit 2; }; CA_SCOPE="$2"; shift 2 ;;
        # Valueless flag, so `shift 1` rather than the `[ $# -ge 2 ]` + `shift 2`
        # guard the value-taking flags use. Called out rather than left to look
        # like an omission.
        --deployment) CA_DEPLOYMENT="yes"; shift ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
      esac
    done

    require_nonblank "--scope" "$CA_SCOPE" \
      "check-approval must be told what action it is being asked about; a blank scope could not be matched against any approval and would answer a question nobody asked"

    # EVERY REFUSAL BELOW THAT COMES OUT OF THE SHARED GUARD FAMILY MUST EXIT 3,
    # NOT 1. Exit 1 here is a meaningful answer of its own ("no approval
    # records at all"), so a corruption refusal exiting 1 would be
    # indistinguishable from it. Both are still "do NOT proceed" -- unlike
    # check-external-action, where 1 means PROCEED and the distinction is
    # safety-critical -- but conflating "there are no approvals" with "the
    # record could not be read" would report a determinate answer for an
    # undeterminable one, which is the same dishonesty in a smaller dose.
    STATE_FAIL_EXIT=3

    if [ ! -f "$STATE" ]; then
      echo "ERROR: task '$ID' not found (no tasks recorded yet) — cannot determine whether any approval covers that action. UNDETERMINED: do NOT proceed (exit 3 is not an approval; NOTHING nonzero is)." >&2
      exit 3
    fi
    # read_task_state (not require_task_state) so the not-found MESSAGE stays
    # this subcommand's own, more specific one. A corrupt record still refuses
    # inside read_task_state, at exit 3 per STATE_FAIL_EXIT above.
    read_task_state "$ID"
    if [ "$TASK_STATE_VALUE" = "missing" ]; then
      echo "ERROR: task '$ID' not found — cannot determine whether any approval covers that action. UNDETERMINED: do NOT proceed (exit 3 is not an approval; NOTHING nonzero is); fix the task id and re-check." >&2
      exit 3
    fi

    # Recompute the code identity live, right now, rather than trusting
    # anything cached -- the same way `resume` does.
    CA_CURRENT=$(compute_snapshot)
    require_approval_verdict "$ID" "$CA_SCOPE" "$CA_DEPLOYMENT" "$CA_CURRENT"

    case "$APPROVAL_VERDICT" in
      ok)
        echo "APPROVAL-COVERS $ID scope=\"$CA_SCOPE\" deployment=$CA_DEPLOYMENT — PROCEED."
        [ -n "$APPROVAL_DETAIL" ] && echo "$APPROVAL_DETAIL"
        echo "  Exit 0 means exactly: a recorded approval matches this scope, was granted at the revision the code is at now, and covers this action's deployment impact. It does NOT mean any recorded conditions have been checked — task-state.sh cannot evaluate free text. If conditions are printed above, satisfying them is yours to do."
        exit 0
        ;;
      none)
        echo "NOT-COVERED $ID scope=\"$CA_SCOPE\" — no approval has ever been recorded for this task. Do NOT proceed; raise a decision card ('task-state.sh record-decision $ID ...') and get one." >&2
        exit 1
        ;;
      scope)
        echo "NOT-COVERED $ID scope=\"$CA_SCOPE\" — approvals exist for this task, but none of them covers that action. Do NOT proceed." >&2
        [ -n "$APPROVAL_DETAIL" ] && echo "$APPROVAL_DETAIL" >&2
        echo "  Scope matching is a normalised EXACT match (case and whitespace are ignored; nothing else is). That is deliberate: a prefix or substring test would let an approval for \"merge PR 12\" cover \"merge PR 12 and deploy to production\". If this action genuinely is the approved one, use the approval's own wording; if it is not, raise a decision card." >&2
        exit 4
        ;;
      revision)
        echo "NOT-COVERED $ID scope=\"$CA_SCOPE\" — an approval covers that scope, but THE CODE HAS CHANGED since it was granted. Do NOT proceed." >&2
        [ -n "$APPROVAL_DETAIL" ] && echo "$APPROVAL_DETAIL" >&2
        echo "  DESIGN.md: persist approvals with their target revision, and ask again when the conditions materially change. The revision changed, so this approval no longer applies to the code you are about to act on. Reassess and raise a fresh decision card." >&2
        exit 5
        ;;
      deployment)
        echo "NOT-COVERED $ID scope=\"$CA_SCOPE\" — an approval covers that scope, but it does NOT carry deployment impact and you said this action does. Do NOT proceed." >&2
        [ -n "$APPROVAL_DETAIL" ] && echo "$APPROVAL_DETAIL" >&2
        echo "  DESIGN.md, verbatim: \"A merge approval is not permission for an unexpected deployment.\" Raise a decision card for the deployment and record an approval with --deployment-impact yes." >&2
        exit 6
        ;;
      unverifiable)
        echo "UNDETERMINED $ID scope=\"$CA_SCOPE\" — an approval covers that scope, but the revision could not be established, so whether it is still current CANNOT BE ANSWERED. Do NOT proceed." >&2
        [ -n "$APPROVAL_DETAIL" ] && echo "$APPROVAL_DETAIL" >&2
        echo "  At least one of those is the placeholder '$NO_GIT_SNAPSHOT' — what compute_snapshot returns when there is no version control to identify the code with. Two such values match for every possible state of the code, so reading that match as 'the revision is unchanged' would claim a check that did not happen. This degrades to ASK A HUMAN EVERY TIME, never to 'proceed': confirm by hand that the approval still applies to the code as it stands." >&2
        exit 7
        ;;
      *)
        # UNREACHABLE by construction: require_approval_verdict validates its
        # verdict against exactly the six words above and refuses (exit 3)
        # otherwise. Present anyway because the alternative to an explicit
        # catch-all on a `case` that gates an action is falling through to exit
        # 0, and exit 0 here means PROCEED.
        echo "ERROR: task '$ID' — internal: unrecognised approval verdict '$APPROVAL_VERDICT'. UNDETERMINED: do NOT proceed." >&2
        exit 3
        ;;
    esac
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
  record-decision <id> --blocked "<what is blocked>"
                  --why "<why, including what was checked>"
                  --recommend "<recommended option and reason>"
                  --options "<each option's benefit and main pitfall>"
                  --impact "<impact on scope, cost, and delivery>"
                  --question "<one clear question>"
  record-approval <id> --decision <decision-id> --scope "<what is approved>"
                  --approved-by "<who/what approved>"
                  --deployment-impact yes|no [--conditions "<text>"]
  record-rejection <id> --decision <decision-id>
                   --rejected-by "<who/what rejected>" --reason "<why>"
  check-approval <id> --scope "<what you are about to do>" [--deployment]
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
        (any of planned/building/checking) -> awaiting-decision
                                                      -> (restored state)
        (building|checking) --fail--> building             (attempts remain)
        (building|checking) --fail--> needs-reassessment   (budget exhausted)
        needs-reassessment --reassess--> building|checking (the ONLY exit)
        awaiting-decision --record-approval|record-rejection--> (restored
                                                    state; the ONLY exits)

Decision cards and scoped approvals: ROUTINE REPAIRS PROCEED UNTOUCHED — a
failed attempt inside budget still goes fail -> building with no card and no
approval. A MATERIAL deviation is raised explicitly with `record-decision`,
whose six flags are DESIGN.md's six card elements (what is blocked; why,
including what was checked; recommended option and reason; each option's
benefit and main pitfall; impact on scope, cost and delivery; one clear
question). All six are required and non-blank. The task then waits in
`awaiting-decision`, where start/check/complete/fail/block/pause are ALL
refused and complete-gate.sh refuses it too; record-assignment/record-evidence/
record-external-action deliberately stay available, as they do for
blocked/paused, because the session is still legitimately recording what it
checked while a human is asked. Only `record-approval` or `record-rejection`
releases it, and both restore the exact state the card was raised from. An
approval records its scope, its target revision (computed here, never supplied),
any conditions, who approved, and — explicitly, never inferred — whether it
carries deployment impact.

check-approval answers "is the action I am about to take covered by a valid
approval?" with its exit status:
  EXIT 0 = COVERED (scope + revision + deployment impact) -> PROCEED.
  EXIT 1 = NOT COVERED: no approval records at all.
  EXIT 2 = bad usage                  -> UNDETERMINED, do NOT proceed.
  EXIT 3 = task not found/unreadable  -> UNDETERMINED, do NOT proceed.
  EXIT 4 = NOT COVERED: no approval's scope covers this action.
  EXIT 5 = NOT COVERED: the revision changed since the approval was granted.
  EXIT 6 = NOT COVERED: this action has deployment impact the approval did not
           carry. DESIGN.md: "A merge approval is not permission for an
           unexpected deployment."
  EXIT 7 = UNDETERMINED: the revision could not be established (no version
           control), so currency could not be checked -> do NOT proceed.
NONZERO NEVER MEANS "APPROVED". Every nonzero code above means ask, not act.
Three disclosed limits: scope matching is a normalised EXACT match (never a
prefix test — that would let "merge PR 12" cover "merge PR 12 and deploy to
production"); `--conditions` is free text that check-approval prints back
verbatim and explicitly does NOT evaluate; and one corrupt entry in a task's
approvals array makes check-approval refuse for EVERY scope on that task
(exit 3), not just that entry's own — deliberate, the same fail-closed
whole-array validation attempts/checkpoints/external_actions use. One bad
record blocks all approval checks on that task until it is repaired.

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
two counters: state, depends_on, blocked_from, paused_from, decision_from,
attempts (and its hypothesis / attempt_number), checkpoints (and its
next_action / code_snapshot), external_actions (and its key), decisions (and
its decision_id / status), approvals (and its decision_id / scope /
target_revision / approved_by / deployment_impact / conditions), history,
assignments, evidence, reassessments and rejections. Present but of the wrong
type, null, or empty where the
schema always writes content => REFUSED, naming the task, the field and the
offending value, with nothing written. Genuinely absent => still defaults,
where a safe absent-case exists. `status` and `list` are display-only and are
deliberately not hardened; they gate nothing.

--reason, --hypothesis, --specialist, --finding, record-decision's six card
flags, and record-approval's / record-rejection's --scope, --approved-by,
--rejected-by and --decision must all carry actual content: whitespace-only
values are refused exactly as empty ones are.

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
            3 check-approval ONLY: task not found / record unreadable
            4/5/6/7 check-approval ONLY: scope not covered / revision changed /
            deployment impact not covered / revision undeterminable (see above)

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
