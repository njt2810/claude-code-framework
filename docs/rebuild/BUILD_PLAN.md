# Phased implementation plan

Status: Part 1.1 is Done (research/decision only — see below); all other implementation parts are Planned. No replacement code or runtime tests are delivered by this documentation PR.
Read [DESIGN.md](DESIGN.md) first. The team owns validation; the user supplies business decisions and access only when needed.

## Phase 1: Reliable managed delivery

1.1 Inspect current configuration and resolve the integration contract. **Done.**
Finding: the Claude Agent SDK requires a separate, usage-billed Anthropic API key and cannot use the project owner's Claude Max subscription login — confirmed directly against Anthropic's live documentation on 2026-09-10. Decision: the lead/builder/verifier roles are implemented with Claude Code's native subagent mechanism (Agent/Task tool) in-session instead of SDK-dispatched managed sessions through a separate controller process. Full detail, including which secondary claims from the original research were and were not independently re-verified: [PHASE1_1_FINDINGS.md](PHASE1_1_FINDINGS.md). The Windows-specific and plugin-transport findings from that research remain informationally useful (status: worth checking, not confirmed) for how the local scripts in 1.2 onward and the plugin interface in 1.5 should handle paths and process behaviour — but the SDK-specific findings (authentication model, SDK/CLI version coupling) are moot now that the SDK is not adopted.

1.2 Implement durable task records and transitions.
Acceptance: dependencies block premature dispatch; only the local task-state script accepts completion; invalid transitions fail; project state is isolated.

1.3 Implement lead, builder, and verifier invocation via native subagents with explicit skill selection.
Acceptance: recorded assignments and loaded skill revisions; lead write attempts to application code are denied by the lead subagent's own tool-allowlist configuration and independently caught by the completion-gate script's file-change check (this is a convention-level allowlist plus an independent script check, not a process sandbox — see DESIGN.md); builder cannot modify evidence or task-state script rules through its own allowed tools, and any attempt is caught by the same completion-gate check; verifier receives the agreed requirements and code snapshot.

1.4 Implement verification runner and completion gate.
Acceptance: actual output retained; false reports, no required tests, skipped required checks, and changed code reject completion; acceptance requirements map to evidence. The runner's first check on any claimed file/artifact is to independently open and read that exact path — see "Definition of implementation completion" below.

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
