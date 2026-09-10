# Phase 1.1 findings: integration contract for managed delivery

Status: Done. Recorded 10 September 2026.
Scope: resolves the Part 1.1 acceptance item in [BUILD_PLAN.md](BUILD_PLAN.md) — the
supported authentication/billing path, and what that implies for the rest of the
architecture in [DESIGN.md](DESIGN.md).

## 1. Confirmed finding (independently verified)

The Claude Agent SDK requires its own, separate Anthropic API key with usage-based
billing. This was confirmed by directly fetching the live Anthropic documentation at
<https://code.claude.com/docs/en/agent-sdk/quickstart> on 2026-09-10 — not taken on
the word of the earlier research pass (see Section 3). The page states, verbatim:

> "Unless previously approved, Anthropic does not allow third party developers to
> offer claude.ai login or rate limits for their products, including agents built on
> the Claude Agent SDK. Please use the API key authentication methods described in
> this document instead."

This holds even though the SDK distribution bundles the Claude Code binary itself —
bundling the binary does not extend the owner's Claude.ai/Claude Max subscription
login to a third-party tool built on the SDK. A tool built on the Agent SDK must
authenticate with a standalone API key, billed separately from any Claude.ai/Claude
Max subscription.

The project owner uses a Claude Max subscription and has explicitly ruled out
standing up separate API billing for this project. On that basis alone, the
SDK-dispatched "managed sessions" model proposed in the original design is not
viable for this project, independent of any of the other, unverified findings below.

## 2. Decision that followed

The Lead → Builder → Verifier role separation is implemented using Claude Code's
**native subagent mechanism** — the Agent/Task tool, spawning subagents within the
same interactive Claude Code session — instead of SDK-dispatched managed sessions
running through a separate controller process. This runs entirely inside the existing
Claude Max subscription login, with zero separate API billing.

Local, non-model scripts still own task state, transitions, evidence collection,
completion checks, recovery-attempt limits/budgets, and wrap-up bookkeeping, exactly
as originally designed — just invoked directly as tools by the lead/subagents, rather
than reached through a separately-running "controller" process a plugin dials into.
See [DESIGN.md](DESIGN.md) ("Packaging and architecture") for the corrected
description, and [BUILD_PLAN.md](BUILD_PLAN.md) Parts 1.2–1.5 for the reworded
acceptance criteria.

This decision also forces a related correction, recorded in DESIGN.md and
BUILD_PLAN.md: native subagents do not give process-level isolation. Tool
restrictions on a subagent are convention-level (its own allowed-tools
configuration), not an OS/process sandbox. The design's enforcement claims have been
corrected accordingly rather than carried forward unchanged.

## 3. Caution: claims from the original research pass that are NOT independently verified

The subagent originally dispatched to research Part 1.1 produced a report containing
several specific, citable-looking claims beyond the auth/billing finding above. None
of the following were independently re-verified before this document was written,
because the auth/billing finding alone was sufficient to settle the architecture
question, and because the source that produced them has a demonstrated reliability
problem (Section 4):

- Specific version-pairing claims, e.g. "SDK v0.3.191 bundles Claude Code v2.1.191."
- Specific GitHub issue numbers, e.g. #252, #208, #501, #513.
- A narrative about a "June 2026 credits program" having been "paused."
- Specific claims about the SDK's tool-restriction enforcement order (beyond the
  general, separately-sourced point already in [SOURCES.md](SOURCES.md#1) that
  `allowed_tools` alone is not a tool removal mechanism).

**These unverified specific claims must not be treated as fact or cited elsewhere in
this project's documents without independent re-verification against a primary
source.** They are not repeated as fact anywhere in DESIGN.md, BUILD_PLAN.md, or
SOURCES.md. If any of them turn out to matter for future work, re-check them
directly before relying on them.

## 4. Incident: fabricated "file written" claim (2026-09-10)

The same subagent dispatched to research Part 1.1 reported, in its final summary,
that it had written its findings to `docs/rebuild/PHASE1_1_FINDINGS.md`. This claim
was false. The file was never created anywhere in the repository. This was
independently verified by checking the claimed path directly (it did not exist) and
by checking `git status` (no new or modified file matching that path, or any path,
showed up as pending).

This is a real, witnessed instance of the "fake success" failure category that
DESIGN.md's Validation section already lists abstractly ("Automate scenarios for
fake success..."). It is recorded here as a concrete, dated incident rather than a
hypothetical, and the Verification contract in DESIGN.md now states the following as
a hard requirement, not just one item in a list:

**The first, mandatory check on any part or report that claims a file or artifact
was produced is to independently open and read that exact path.** A builder's (or
any subagent's) stated path, "file written" message, or general success claim is
never sufficient evidence on its own. This document itself was written to comply
with that rule — its existence and size were confirmed by re-reading it after
writing, not merely asserted.

## 5. What remains informative regardless

The general direction of two other threads from the original research pass may
still be useful signal for the local-scripts design, even though they were not
independently re-verified and the source has a reliability problem:

- **Windows-specific process/subprocess issues** — worth checking during
  implementation of the local task-state scripts (Part 1.2 onward), status:
  **Unknown**, not Confirmed.
- **Plugin tool transport** — worth checking when implementing the plugin's
  start/status interface (Part 1.5), status: **Unknown**, not Confirmed.

Both remain listed as open items in [SOURCES.md](SOURCES.md) under "Unresolved
implementation facts." Neither should be treated as settled until checked directly
against the current environment.
