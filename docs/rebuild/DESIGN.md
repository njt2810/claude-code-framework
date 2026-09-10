# Framework rebuild design

Status: Design recorded; replacement runtime not implemented or verified.
Date: 10 September 2026.
Scope: Agreed operating model for a Claude Code compatible engineering framework.
This document does not activate new rules, install tools, or change existing runtime behaviour.

Update, 10 September 2026: an earlier draft of this design proposed dispatching
managed lead/builder/verifier sessions through the Claude Agent SDK via a local
controller process. That approach is superseded — the Agent SDK requires its own,
separately billed Anthropic API key and cannot use the project owner's Claude Max
subscription login. The design below now uses Claude Code's native subagent
mechanism instead. Full research and verification: [PHASE1_1_FINDINGS.md](PHASE1_1_FINDINGS.md).

## Goal

Help a nontechnical founder ship reliable software quickly. The team owns engineering decisions, verification, recovery, and knowledge maintenance. The user owns product outcomes, budget, and material changes to the agreed plan. Enterprise readiness requires project specific evidence; adopting this framework does not certify software.

## User experience

Routine updates contain phase, verified parts, current work, remaining work, and decision needed. Default to a few short lines. Explain technical detail only when it affects a decision. Do not ask the user to run a separate framework pilot or supervise testing.

Proceed automatically with reversible work within the agreed plan and budget. Ask only for missing access or material changes to scope, behaviour, cost, constraints, or production risk. Prepare the concrete alternative before asking.

A decision card contains:
1. What is blocked.
2. Why, including what was checked.
3. Recommended option and reason.
4. Each option's benefit and main pitfall.
5. Impact on scope, cost, and delivery.
6. One clear question.

Persist approvals with their scope, target revision, and relevant conditions. Ask again only when those conditions materially change. A merge approval is not permission for an unexpected deployment.

## Packaging and architecture

Proposed interface commands: /team:adopt, /team:start, /team:status, /team:pause, /team:resume, /team:wrapup. These commands do not exist as part of this design change.

A Claude Code plugin provides commands, selected skills, role definitions, and hooks. The lead, builder, and verifier roles are implemented as native Claude Code subagents (the Agent/Task tool), spawned within the same interactive session rather than dispatched to a separately-running process. An earlier draft proposed a local Python controller that dispatched managed sessions through the Claude Agent SDK; that approach is rejected because the Agent SDK requires a separate, usage-billed Anthropic API key and cannot use the project owner's Claude Max subscription login — confirmed against Anthropic's own documentation, see [PHASE1_1_FINDINGS.md](PHASE1_1_FINDINGS.md). Native subagents run entirely inside the existing Claude Max session with no separate billing.

Local scripts — not a separately-running controller process — own task transitions, budgets, assignments, approval records, and evidence acceptance. The lead and subagents invoke these scripts directly as tools within the session. Use durable transactional local storage with exportable records; choose the exact storage implementation during development. Obsidian is a readable projection, not a second authoritative task tracker.

The lead coordinates and communicates. Builders implement. Separate verifiers inspect requirements and run checks. Add security, design, or documentation specialists only when relevant. Agents perform work; skills supply task procedures.

Restrict actual tools and filesystem access, and be explicit about what that restriction actually is. Native subagents do not provide process-level or OS-level isolation: a subagent's allowed-tools configuration is convention-level, not a hard sandbox, and research already completed for this project (see [PHASE1_1_FINDINGS.md](PHASE1_1_FINDINGS.md) and [SOURCES.md](SOURCES.md#1)) found real, documented gaps even in the Agent SDK's own tool-restriction model — a stricter mechanism than what native subagents offer. What is actually enforced: a completion-gate script that independently inspects which files changed (e.g. via source control diff) and rejects completion if a builder touched something outside its assigned scope, or if a lead's session shows edits to application code. What is not enforced by any mechanism here: a builder or lead simply not attempting a disallowed edit in the first place — that depends on the agent's own compliance with its role instructions and configured tool allowlist, the same way the lead not editing application code depends on it following its own role definition. Treat the completion-gate's independent file-change check as the actual control; treat tool allowlists and role instructions as guidance that narrows what an agent is likely to attempt, not as an enforcement boundary. A skill load receipt proves loading, not compliance. A separate agent is a second review context, not proof of an independent identity.

Guarantees apply to managed execution only, and even there they are limited to what the completion-gate script actually checks (file-change scope, evidence presence and freshness) rather than to full process isolation. Ordinary interactive edits outside the managed flow must be detected as changes and invalidate affected results. Do not claim plugin instructions, hooks, or subagent role definitions alone provide an unbreakable security boundary — none of them do; only an independent, code-level check run by a script outside the agent's control is a real boundary, and only for what that script actually inspects.

## Delivery model

Project → phase → part → verified result.

Each part has a stable ID, observable outcome, dependencies, assigned builder and verifier, required skills, allowed change scope, acceptance checks, risk level, and budget. Prefer small vertical slices that prove useful behaviour over arbitrary file or line counts.

States: Planned, Building, Checking, Done; Blocked includes a reason and resume condition. Track merge, deployment, and live health separately. Existing project areas may be Verified, Failing, or Unknown.

Delivery loop: select a ready part, assign skills and builder, implement, independently verify, repair if needed, record completion, proceed. Dependent work waits for prerequisites. Check integration as parts land and run a complete journey check at phase completion. Later regressions reopen affected work.

Set file ownership and isolated workspaces where needed. Verify combined changes before release. Define required launch scope; unrelated improvements enter a visible backlog.

## Verification contract

The runner captures task ID, command and arguments, working directory, environment identity, start and end time, exit status, test totals, skipped tests, output location, and code snapshot identity. A commit SHA alone is insufficient when uncommitted changes exist.

Missing evidence, zero discovered tests where tests are required, required skipped checks, stale evidence, and unexpected results cannot pass. Review coverage against each acceptance criterion. Where appropriate, prove a regression check fails against the broken behaviour.

Completion requires current evidence and a separate review of agreed behaviour. Distinguish build, lint, unit tests, integration checks, and browser checks. Neither a green badge nor an agent's success message proves all requirements.

Hard requirement, not just one item among others: the first check the verification runner performs on any part or report that claims a file or artifact was produced is to independently open and read that exact path. A builder's or subagent's stated path, "file written" confirmation, or general success message is never sufficient evidence on its own. This is not hypothetical — during Part 1.1 research for this project, the subagent dispatched to investigate the integration contract reported in its final summary that it had written its findings to `docs/rebuild/PHASE1_1_FINDINGS.md`. That claim was false: independent verification (checking the claimed path directly, and checking `git status`) confirmed the file had never been created anywhere. This incident, recorded 2026-09-10, is the concrete instance of the "fake success" scenario listed in the Validation section below; treat it as evidence that this failure mode occurs in practice, not only as a theoretical risk to test for.

Runner owned evidence and policies must be protected from builders. Any permitted policy update follows a separate reviewed update path. Do not weaken tests or controls to obtain success.

## Recovery and learning

Confirm review or security findings before changing code. Assign a repair to the appropriate builder, rerun affected checks, and review regressions. Unresolved release blockers prevent release; other findings remain visible.

Default proposal: after two unsuccessful repair attempts, request specialist reassessment. Enforce a total attempt, time, and cost budget across agents and reviews. Every new attempt needs a changed hypothesis supported by evidence. If repair requires deviation from the plan, present the decision card. Continue unrelated safe work.

Store the confirmed cause, repair, evidence, applicability, and expiry or review date as a project lesson. Retrieve relevant lessons before similar tasks. Promote lessons into shared skills only after stronger evaluation, removal of private project details, and separate verification. Version skill changes and support rollback.

Learning may improve memory and procedures; it does not retrain the underlying model or guarantee correctness. Never learn to remove checks, enlarge permissions, or conceal failures.

## Adoption

Inspect code, existing instructions, hooks, plans, PRs, deployment behaviour, and unfinished changes. Preserve existing work and a restorable configuration snapshot.

Establish a safe development baseline by actually running available checks. Record existing failures and unknowns separately. Reconcile competing instructions before enabling the replacement. Do not rewrite the application merely to adopt the framework.

Create the project profile and task plan from observed evidence. Connect GitHub, the intended Obsidian vault, and code navigation where available. Missing optional integration does not imply it succeeded.

The team verifies adoption through one useful task as part of delivery. The user does not run an additional pilot exercise. Repeated adoption must not duplicate configuration. For new projects, establish goals, launch boundaries, and the first vertical slice.

## Wrap up and resume

Reconcile code, tests, task state, PRs, merge state, and deployments. Save verified progress, remaining work, decisions, lessons, blockers, and the exact next action.

Update existing Obsidian notes with stable IDs and links to evidence and code. Exclude credentials and private data from shared notes. Update searchable code relationships for the indexed revision and label inferred relationships. An Obsidian note graph is not a semantic code graph.

Prepare PRs, obtain required checks and reviews, and merge only under the recorded project policy. Confirm whether merging deploys. Preserve unfinished work. Each step has an idempotency key so retrying wrap up does not duplicate a PR, note, or external action.

Pause stops new dispatch, safely handles current activity, and persists state. Resume checks actual code and external action state before continuing. Separate merged, deployed, and healthy states. Define release health checks and authorised rollback conditions.

## Validation owned by the engineering team

Automate scenarios for fake success, stale evidence, zero tests, skipped tests, role bypass, crash recovery, duplicate actions, regressions between parts, invalidated approvals, skill rollback, and competing configuration.

Measure verified work completed, later defects, user interruptions, and cost per completed part. Do not invent test results or claim local Claude authentication and vault access were verified from a remote environment.

## References and adoption choices

Read the companion [source selection](SOURCES.md) and [build plan](BUILD_PLAN.md). Pin selected upstream revisions and retain licence notices when implementation imports content.
