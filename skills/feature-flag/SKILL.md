---
name: feature-flag
description: |
  TRIGGER when: the user wants to add a feature flag, set up flag infrastructure,
  do a gradual rollout, A/B test, or add a kill switch.
  DO NOT TRIGGER when: the user wants a permanent config toggle (use env vars),
  or a UI preference (those are user settings, different concern).
argument-hint: "[setup|add|list|remove]"
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Feature Flags

## When to Use

When the project needs gradual rollouts, kill switches, A/B testing, or
per-customer overrides. Especially important for SaaS where shipping a bad
change to all customers at once is unacceptable.

## Procedure

## Step 1 — Determine Mode

From `$ARGUMENTS`:
- `setup` — first-time flag infrastructure setup
- `add` — add a new flag to existing infrastructure
- `list` — list current flags and their state
- `remove` — retire an unused flag
- If empty: ask

## Step 2 — Setup (First Time)

Detect existing flag setup:
- LaunchDarkly SDK in package.json/requirements?
- GrowthBook SDK?
- Posthog feature flags (free tier)?
- Custom env-based flags?

If nothing exists, present options (vendor-neutral):

| Option | Pros | Cons | Cost |
|--------|------|------|------|
| **PostHog** | Free up to 1M events/mo, also gives analytics | Setup needed | Free tier |
| **GrowthBook** | Open-source, self-host option, A/B testing | Self-host or paid cloud | Free self-host |
| **LaunchDarkly** | Best-in-class UX, mature | Expensive | $0 for tiny scale, paid above |
| **Statsig** | Free tier, A/B testing | Less polished | Free tier generous |
| **DIY env-based** | No vendor | No UI, no targeting, can't change at runtime | $0 |

Ask user to pick. Common early-stage choice: PostHog (gives flags + analytics in one).

For DIY env-based:
- Flag values come from env vars like `FEATURE_NEW_ONBOARDING=true`
- No targeting (all users see it or none)
- Toggle requires deploy
- Acceptable for small user base or kill switches only

## Step 3 — Install SDK

Based on choice, install SDK and create a wrapper:

**`src/lib/feature-flags.ts` (Node + PostHog example):**

```typescript
import { PostHog } from "posthog-node";

const client = new PostHog(process.env.POSTHOG_API_KEY!, {
  host: process.env.POSTHOG_HOST ?? "https://app.posthog.com",
});

export type FlagContext = {
  userId: string | "anonymous";
  email?: string;
  organizationId?: string;
  // Any other targeting attributes
};

export async function isFlagEnabled(
  flag: string,
  context: FlagContext,
): Promise<boolean> {
  if (context.userId === "anonymous") {
    return false; // safer default
  }
  const result = await client.isFeatureEnabled(flag, context.userId, {
    personProperties: {
      email: context.email,
      organization_id: context.organizationId,
    },
  });
  return result === true;
}
```

**Python (PostHog) equivalent** — analogous setup.

## Step 4 — Add a Flag

Ask user:
- Flag key (kebab-case, e.g., `new-onboarding-flow`)
- Description (what it controls)
- Type: release toggle / experiment / kill switch / permission
- Default value
- Rollout plan: % of users, specific users, or full

Steps:
1. Create the flag in the vendor UI (provide instructions for chosen vendor)
2. Use `isFlagEnabled('flag-key', context)` in code
3. Add to flag registry

## Step 5 — Flag Registry

Maintain `wiki/operations/feature-flags.md`:

```markdown
# Feature Flags

## Active Flags

| Key | Type | Description | Owner | Added | Removal target |
|-----|------|-------------|-------|-------|----------------|
| new-onboarding-flow | release | Gradual rollout of new signup UX | NT | 2026-06-29 | when 100% rolled out |
| ... | ... | ... | ... | ... | ... |

## Retired Flags

| Key | Retired | Final state | Reason |
|-----|---------|-------------|--------|
| old-payment-flow | 2026-05-12 | OFF for all | Replaced by new flow |
| ... | ... | ... | ... |

## Conventions
- Flag keys: kebab-case
- Types:
  - **release**: gradual rollout, retire after 100%
  - **experiment**: A/B test, retire after winner picked
  - **kill switch**: permanent, for emergency disable
  - **permission**: per-customer feature gating
- Every release/experiment flag MUST have a removal target
- Retire flags within 3 months of full rollout (technical debt)
```

## Step 6 — List Active Flags

`/feature-flag list` reads the registry and reports:
- Active flag count
- Flags overdue for retirement (past removal target)
- Flags without removal target (technical debt)

## Step 7 — Remove a Flag

When retiring:
1. Set flag to ON or OFF for all in vendor UI (final state)
2. Remove `isFlagEnabled()` calls from code (replace with the chosen branch)
3. Move flag from "Active" to "Retired" in registry
4. Commit with message: `chore: retire flag {key}`

## Step 8 — Report

```
Feature Flag {action}

  {Action-specific summary}

  Registry: wiki/operations/feature-flags.md
  Active:   {N} flags
  Overdue:  {N} flags past removal target
```

## Pitfalls

- Flag without removal target — becomes permanent technical debt
- Forgetting to remove old code paths after flag retired — both paths drift
- Using flags for config (use env vars instead) — flags are for rollout/A/B
- Flag check inside a tight loop — measure performance impact
- Anonymous users get inconsistent flag state — define default behavior explicitly
- Storing flag config in env vars then needing runtime toggle — wrong tool

## Verification

- Flag SDK installed and wrapper exists
- Flag added to vendor UI AND code AND registry
- Removal target is specified (or marked permanent for kill switches)
- Registry shows current state of all active flags
