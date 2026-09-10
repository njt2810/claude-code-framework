# Phased implementation plan

Status: Part 1.1 is Done (research/decision only — see below); Part 1.2 is Done; Part 1.3 is Partially implemented (see its own status line below); Part 1.4 is Done for its own literal acceptance text, with one explicitly separate item deferred (see its own status line below); all other implementation parts are Planned. No replacement code or runtime tests are delivered by this documentation PR.
Read [DESIGN.md](DESIGN.md) first. The team owns validation; the user supplies business decisions and access only when needed.

## Phase 1: Reliable managed delivery

1.1 Inspect current configuration and resolve the integration contract. **Done.**
Finding: the Claude Agent SDK requires a separate, usage-billed Anthropic API key and cannot use the project owner's Claude Max subscription login — confirmed directly against Anthropic's live documentation on 2026-09-10. Decision: the lead/builder/verifier roles are implemented with Claude Code's native subagent mechanism (Agent/Task tool) in-session instead of SDK-dispatched managed sessions through a separate controller process. Full detail, including which secondary claims from the original research were and were not independently re-verified: [PHASE1_1_FINDINGS.md](PHASE1_1_FINDINGS.md). The Windows-specific and plugin-transport findings from that research remain informationally useful (status: worth checking, not confirmed) for how the local scripts in 1.2 onward and the plugin interface in 1.5 should handle paths and process behaviour — but the SDK-specific findings (authentication model, SDK/CLI version coupling) are moot now that the SDK is not adopted.

1.2 Implement durable task records and transitions.
Acceptance: dependencies block premature dispatch; only the local task-state script accepts completion; invalid transitions fail; project state is isolated.
**Done.** `scripts/team/task-state.sh`, verified against all four acceptance clauses by `tests/task-state-smoke.sh` (60 checks, all passing).

1.3 Implement lead, builder, and verifier invocation via native subagents with explicit skill selection.
Acceptance: recorded assignments and loaded skill revisions; lead write attempts to application code are denied by the lead subagent's own tool-allowlist configuration and independently caught by the completion-gate script's file-change check (this is a convention-level allowlist plus an independent script check, not a process sandbox — see DESIGN.md); builder cannot modify evidence or task-state script rules through its own allowed tools, and any attempt is caught by the same completion-gate check; verifier receives the agreed requirements and code snapshot.
**Partially implemented.** Done: `agents/team-builder.md` and `agents/team-verifier.md` (role definitions, each disclosing in its own instructions that its scope restriction is convention/tool-allowlist-level, not a hard sandbox); `scripts/team/assign.sh` (assignment recording -- agent type, per-skill sha256 content hashes as the "loaded skill revision" evidence, timestamp, and for verifier assignments the supplied acceptance criteria and a code snapshot identity) plus the `task-state.sh record-assignment` subcommand it drives, sharing `task-state.sh`'s existing lock/atomic-write path; `tests/assign-smoke.sh` (42 checks, all passing, including a real dirty-vs-clean-tree snapshot check, a same-base-SHA/different-content dirty-tree check added alongside the Part 1.4 staleness fix, and a skill-hash-changes-when-content-changes check). Deferred to Part 1.4 by design, not a shortfall of this part: the "independently caught by the completion-gate script's file-change check" half of this acceptance line, since the completion-gate script is Part 1.4's own deliverable and did not exist yet at the time this status line was first written. **That half is now available**: Part 1.4 shipped `scripts/team/complete-gate.sh`, whose check 3 independently opens and reads every artifact path a builder's recorded evidence claims to have produced (see Part 1.4's own status line). What is still NOT covered, even now: complete-gate.sh's checks are about evidence quality (artifacts real, exit code 0, tests run/not skipped, snapshot fresh), not about an out-of-scope file-change diff against a declared allowed-scope -- `task-state.sh create` has no `--allowed-scope` field, so "a lead's session shows edits to application code" or "a builder touched something outside its assigned scope" is still not independently checked by any script; the scope restrictions in `agents/team-builder.md` and `agents/team-verifier.md` remain enforced by agent compliance with their own written instructions only for that specific claim, exactly as DESIGN.md's "Packaging and architecture" section discloses for native subagents generally. That remains a disclosed gap for a future increment (see Part 1.4's status line).

1.4 Implement verification runner and completion gate.
Acceptance: actual output retained; false reports, no required tests, skipped required checks, and changed code reject completion; acceptance requirements map to evidence. The runner's first check on any claimed file/artifact is to independently open and read that exact path — see "Definition of implementation completion" below.
**Done, for this part's own literal acceptance text; one related item is explicitly deferred (see below), not silently covered.** A Code Reviewer pass on the initial implementation found 2 CRITICAL and 1 HIGH defect (staleness detection, artifact/output_file path-resolution ambiguity, and a missing output_file existence check); all three are now fixed and independently re-verified against the reviewer's own reproduction scenarios (see below) -- this status line describes the fixed state, not the originally-shipped one. Built: `task-state.sh record-evidence` (new subcommand, same locked/atomic pattern as `record-assignment`; appends to a new per-task `evidence` array recording command, cwd, environment identity, timestamp, exit code, tests_total, tests_skipped, output_file, artifacts[], and a code snapshot identity computed with the exact same logic as `assign.sh`'s `compute_snapshot`); `scripts/team/complete-gate.sh` (the completion gate itself -- the only sanctioned path to completion in the intended workflow, though `task-state.sh complete` remains directly callable since task-state.sh itself has no knowledge of this script). The gate runs, in order, stopping at the first failure: (1) task exists and is in `checking` state; (2) at least one evidence record exists; (3) **artifact check on the latest evidence entry, run first among the evidence-content checks as BUILD_PLAN.md's own hard rule requires** -- every claimed artifact path in `artifacts[]`, AND `output_file`, is independently `[ -f ]`/`[ -s ]`-checked on disk, a missing OR zero-byte file both reject by name, with the failure message always saying whether it was a declared artifact or the output_file; (4) latest evidence's exit_code is 0; (5) under the default `--require-tests`, tests_total > 0 and tests_skipped == 0 (skippable via `--allow-no-tests` for parts with no test surface); (6) the latest evidence's recorded code_snapshot matches the snapshot computed live, right now -- stale evidence rejects. Only if every check passes does the gate call `task-state.sh complete` as its own final step. Verified by `tests/complete-gate-smoke.sh` (68 checks, all passing) and `tests/assign-smoke.sh` (42 checks, all passing), including the regression test named directly after the Part 1.1 incident (a claimed artifact that does not exist on disk is rejected, by exact path, and the task independently re-checked via `task-state.sh status` afterward still shows `checking`, not `done`), a zero-byte-artifact variant of the same check, the no-evidence/nonzero-exit-code/skipped-tests/no-tests/wrong-state rejection cases, and a happy path that independently re-confirms `done` rather than trusting the gate's own success message. Also wired into `scripts/ci-checks.sh` (already covered by its existing `scripts/team/*.sh` / `tests/*.sh` globs, no changes needed there) and added explicitly to `.github/workflows/ci.yml` alongside the prior two test steps.

**Fixes applied after Code Reviewer findings (this status line's current, accurate state):**
- **Staleness detection now covers content, not just a clean/dirty flag (was CRITICAL).** `compute_snapshot()` (identically duplicated in `task-state.sh`, `complete-gate.sh`, and `assign.sh` -- verified byte-identical with `diff` after the fix) now returns, for a dirty tree, `uncommitted, base SHA <sha>, diff <12-char sha256 prefix>`, where the hash covers `git diff HEAD` (tracked changes) combined with the listed path *and* actual content of every untracked file (`git status --porcelain --untracked-files=all`). Two different dirty trees off the same base commit now produce different snapshot strings, so evidence recorded against one is correctly rejected as stale once the tree changes again without a commit -- the previously-undetectable common case (builder still dirty at evidence-recording time). A clean tree's snapshot is unchanged (bare short SHA). Reproduced directly: recorded evidence with `tracked.txt` at "v1", then changed it to "v2" with no commit in between -- `complete-gate.sh` now fails at check 6 ("evidence is stale") instead of wrongly passing (see the reviewer-repro re-run below). `tests/complete-gate-smoke.sh` keeps the original commit-based staleness test and adds a new dirty-content-only staleness test reproducing this exact scenario; `tests/assign-smoke.sh` adds a same-base-SHA/different-content case proving two dirty trees now hash differently.
- **Artifact/output_file path resolution is now unambiguous (was CRITICAL).** `task-state.sh record-evidence` resolves `--cwd` to an absolute path first (relative to the actual invocation directory, the same default used when `--cwd` is omitted), then resolves every `--artifact` and `--output-file` value onto that absolute cwd (already-absolute paths pass through unchanged) *before* storing them. Resolution uses a small portable `resolve_path`/`is_absolute_path` pair (no `realpath` dependency, consistent with this repo's existing `cd ... && pwd` convention for absolute-path resolution) and does not require the path to exist yet, since recording is not judging. `complete-gate.sh` now checks the stored (already-absolute) paths directly and needs no cwd guessing of its own at all -- correct regardless of which directory the gate is invoked from. `tests/complete-gate-smoke.sh` adds regression tests recording evidence with an explicit `--cwd` into a subdirectory and relative artifact/output_file paths, then confirming the gate (run from the project root, the only directory `task-state.sh`'s cwd-relative state file can be reached from) finds the real files correctly, and still correctly rejects a genuinely missing one.
- **output_file is now independently verified, same as a declared artifact (was HIGH).** `complete-gate.sh`'s check 3 now also verifies the recorded `output_file` exists and is non-empty at its resolved path, failing the gate with a message that clearly distinguishes "declared artifact missing/empty" from "output_file missing/empty" rather than folding it in anonymously. `tests/complete-gate-smoke.sh` adds missing/zero-byte/present-and-valid cases for `output_file` specifically.

**Independent re-verification of both CRITICAL reproductions, run standalone outside the test suite** (both before/after confirmed): (1) staleness -- recording evidence against `tracked.txt`="v1 - the version that was tested", then changing it to "v2 - DIFFERENT, UNTESTED logic, changed after evidence was recorded" with no commit, now yields `GATE FAIL (check 6): evidence is stale` instead of the previous `GATE PASS ... COMPLETED ... state=done`; (2) path resolution -- recording evidence with `--cwd work/subdir` and relative `findings.txt`/`run.log` (the real files living only under `work/subdir/`), then running the gate from the project root, now correctly finds both real files via their stored absolute paths (`GATE PASS ... COMPLETED ... state=done`), where the old code would have checked for a bare `findings.txt` at the project root (confirmed absent) and falsely rejected the evidence as missing.

**Explicitly NOT covered by this part, disclosed rather than silently expanded into**: DESIGN.md's separately-mentioned "rejects completion if a builder touched something outside its assigned scope" -- an out-of-scope file-change diff check against a declared allowed-scope. `task-state.sh create` has no `--allowed-scope` field yet, and this gate does not inspect `git diff` against any such declared scope at all. This part's own acceptance text is specifically about false reports, missing tests, skipped checks, and stale evidence -- not scope-of-change -- so this is an accurate scoping decision, not a gap being hidden; it is a reasonable separate increment for whoever picks up Phase 2 or a future Phase 1 increment. Also disclosed in `complete-gate.sh`'s own header comment: reading task state via `task-state.sh status`, validating it, and only then separately calling `task-state.sh complete` is not covered by a single lock spanning both calls -- `task-state.sh complete` itself still re-validates (under its own lock) that the task is in `checking` state at the moment it runs, so this cannot corrupt state or double-complete a task, but a concurrent `record-evidence` call landing in that narrow gap would not be re-validated by the gate before the final `complete` call. Narrower than the read-modify-write races fixed in Part 1.2/1.3 (which were within a single command's own sequence), and disclosed rather than fixed here.

1.5 Implement plugin start and status interface.
Acceptance: a useful small task passes from assignment to independent verification via native subagent invocation; progress comes from stored state; output is concise; unmanaged changes invalidate affected results.

## Phase 2: Continuity and recovery

2.1 Add pause, resume, and checkpoints.
Acceptance: restart restores the exact next action and checks current code; completed external actions are not repeated.

2.2 Add bounded repair and specialist reassessment.
Acceptance: failure enters recovery; two failed attempts trigger reassessment by default; total budgets stop endless loops; controls cannot be weakened.

2.3 Add decision cards and scoped approval records.
Acceptance: routine repairs proceed; material deviations wait; unchanged approvals remain valid; changed revision or deployment impact triggers reassessment.

2.4 Add integration and overlap checks.
Acceptance: concurrent ownership conflicts are caught; combined changes are checked; a later regression reopens affected parts.

## Phase 3: Adoption and packaging

3.1 Inspect and baseline an existing repository.
Acceptance: preserve unfinished files and open PRs; distinguish existing failures from introduced failures; no production mutation during baseline.

3.2 Migrate configuration reversibly.
Acceptance: backup and reconcile old hooks and instructions; repeated adoption creates no duplicates; rollback restores prior configuration.

3.3 Add Windows installer and versioned updates.
Acceptance: dependencies and connections are checked; failed installation reports an actionable reason; updates preserve project settings; old versions are recoverable.

3.4 Support new projects and existing project delivery plans.
Acceptance: goals become phases and observable parts with launch boundaries. Validate on real work under team supervision, without assigning testing work to the user.

## Phase 4: Wrap up and release workflow

4.1 Add Obsidian projection and next action record.
Acceptance: stable note identity; no repeated notes; decisions include reasons and evidence; missing vault access is visible.

4.2 Add PR preparation, checks, and merge policy.
Acceptance: PR references verified revision; changed head invalidates acceptance; draft work stays unfinished; merge and deployment permissions remain distinct.

4.3 Add repeatable wrap up.
Acceptance: second run creates no duplicate PR or note; partial failure resumes at the unfinished step; status distinguishes verified, merged, deployed, and healthy.

4.4 Add live health and authorised rollback.
Acceptance: release failure is visible; rollback only under recorded conditions; evidence remains available after rollback.

## Phase 5: Learning and code mapping

5.1 Record and retrieve project lessons.
Acceptance: confirmed cause and evidence required; unrelated project data excluded; stale and contradictory lessons are flagged.

5.2 Add skill improvement evaluation.
Acceptance: independently evaluate proposed updates on the original failure and relevant cases; reject harmful updates; retain version history and restore capability. Protect governing permissions and completion rules.

5.3 Add semantic navigation and persistent graph adapter.
Acceptance: language coverage documented; source revision recorded; stale indexes detected; confirmed and inferred edges distinguished; code remains authoritative. Serena alone does not satisfy persistent graph export.

## Definition of implementation completion

Each part must record actual evidence and remaining limitations. A documentation change, mocked integration, successful import, or agent claim cannot establish end to end runtime readiness. Use automated failure scenarios and targeted real integration checks as engineering work.

No part is marked complete without independently reading every artifact it claims to have produced. This is a hard rule, not a preference: during Part 1.1 research, the dispatched subagent's final report claimed a findings file had been written to `docs/rebuild/PHASE1_1_FINDINGS.md`; the file did not exist anywhere in the repository, and this was only caught because the claim was independently checked rather than taken at face value. Treat a stated file path, a "done" or "written" message, or any other self-report from a builder or subagent as a claim to be checked, never as evidence on its own.

## First execution instruction

Start with 1.1 and inspect the repository before changing runtime files. Use the existing framework only as a migration source. Its instruction that the lead implements code conflicts with the agreed replacement design and must not be copied into the new managed roles. Preserve current installation behaviour until a verified replacement path exists.
