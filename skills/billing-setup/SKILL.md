---
name: billing-setup
description: |
  TRIGGER when: the user wants to add billing, payments, subscriptions, or
  set up a payment provider for the first time.
  DO NOT TRIGGER when: the user wants to add invoicing only (different scope),
  or to handle a billing bug (use /bug-fix).
argument-hint: "[subscription|usage|one-time]"
disable-model-invocation: true
user_locked: true
pinned: true
---

# Billing & Payments Setup

## When to Use

When the project needs to charge customers — subscriptions, usage-based, or
one-time payments. Vendor-neutral skill walks the user through the choice.
Critical for any SaaS turning on revenue.

## Procedure

## Step 1 — Determine Billing Model

From `$ARGUMENTS` or ask:
- `subscription` — recurring monthly/annual (most SaaS)
- `usage` — pay-per-use (API products, AI products)
- `one-time` — one-shot purchases (digital goods, lifetime deals)

Get details:
- Pricing tiers (if subscription): how many, what features per tier?
- Free trial offered? Length?
- Annual discount?
- Currencies to support? (Singapore: SGD, USD, others?)
- Tax handling: vendor handles (Stripe Tax, Paddle MOR) or DIY?
- Invoicing for B2B clients required?

## Step 2 — Present Provider Options

| Provider | Best For | Strengths | Tradeoffs | Fees |
|----------|----------|-----------|-----------|------|
| **Stripe** | Most SaaS | Best DX, broad coverage, Stripe Tax | Self-handle some compliance | 2.9% + S$0.50 |
| **Paddle** | International SaaS | Merchant of Record (handles tax/VAT), simpler compliance | Higher fees, less flexible | 5% + S$0.50 |
| **Lemon Squeezy** | Indie SaaS | MoR, easy setup, "fair use" | Less customization | 5% + S$0.50 |
| **Polar** | Open-source / developer tools | Github-native, MoR | Newer, narrower | 4% + S$0.40 |
| **DodoPayments** | Developer-friendly MoR | MoR, simple UX | Newer | ~5% + small fee |

Strong recommendations:
- **Singapore-based, international customers**: Paddle or Lemon Squeezy (MoR absorbs VAT/tax complexity)
- **Singapore B2B, custom invoices needed**: Stripe + Stripe Invoicing
- **High-volume, cost-sensitive**: Stripe (lowest fees)
- **Open-source / developer tools**: Polar

**MoR (Merchant of Record) explanation:**
- MoR is the legal seller — they collect tax, handle PCI-DSS, manage chargebacks
- Without MoR (e.g., Stripe), YOU are the seller — you must register for VAT
  in countries where you sell, handle sales tax, etc.
- MoR is worth the higher fee for solo founders selling internationally

Ask user to pick.

## Step 3 — Install SDK & Wire Webhooks

For **Stripe**:
1. `npm install stripe @stripe/stripe-js`
2. Add to `.env.example`:
   - `STRIPE_SECRET_KEY=sk_test_...`
   - `STRIPE_WEBHOOK_SECRET=whsec_...`
   - `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_...`
3. Create products/prices in Stripe Dashboard
4. Wire checkout flow:
   - Server: create Checkout Session
   - Client: redirect to Stripe-hosted Checkout
5. Wire webhook handler at `/api/webhooks/stripe`:
   - Verify signature with webhook secret
   - Handle: checkout.session.completed, invoice.payment_succeeded,
     customer.subscription.updated, customer.subscription.deleted

For **Paddle** / **Lemon Squeezy** / **Polar**: similar pattern, MoR handles
more of the complexity.

## Step 4 — Subscription State Management

Add a `subscriptions` (or similar) table that mirrors provider state:

```sql
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id),
  provider_subscription_id TEXT NOT NULL,
  provider_customer_id TEXT NOT NULL,
  status TEXT NOT NULL,  -- active, trialing, past_due, canceled, etc.
  plan TEXT NOT NULL,
  current_period_start TIMESTAMP NOT NULL,
  current_period_end TIMESTAMP NOT NULL,
  cancel_at_period_end BOOLEAN DEFAULT false,
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

Webhooks keep this table in sync with the provider.

NEVER use this table as the source of truth for "is the user paid right now" —
always confirm against the provider for high-stakes actions (granting access
to expensive features). But it's fine for UI display.

## Step 5 — Authorization Tied to Subscription

Document in `wiki/conventions.md` (billing section):

```markdown
## Billing & Authorization

- Subscription status check pattern:
  `const sub = await getActiveSubscription(user.id);`
  `if (!sub || sub.status !== 'active') throw new SubscriptionRequired();`

- For high-stakes actions (e.g., create_expensive_resource), re-confirm with
  the provider: `await stripe.subscriptions.retrieve(sub.provider_subscription_id)`
  This guards against drift if webhooks have lagged.

- Grace period: users with `past_due` subscriptions retain access for 7 days
  while we retry payment.

- Cancellation: `cancel_at_period_end=true` keeps access until period_end.
```

## Step 6 — Audit Logging for Billing

Wire audit log helper to fire on:
- payment.attempted
- payment.succeeded
- payment.failed
- payment.refunded
- subscription.created
- subscription.upgraded / downgraded
- subscription.canceled
- trial.started / ended

## Step 7 — Compliance Considerations

If not using MoR:
- Need to register for GST in Singapore once you cross the threshold (S$1M)
- Need to handle sales tax in US states with economic nexus
- Need to handle VAT in EU
- **Strongly recommend MoR for solo founders to avoid this complexity**

Document in `wiki/compliance/billing-compliance.md`:
- Provider: {chosen}
- MoR or DIY tax: {choice}
- Tax registration status: {what you have/need}
- Refund policy: {documented in ToS}

## Step 8 — Test End-to-End

In Stripe test mode (or provider's equivalent):
1. Sign up new user
2. Subscribe to a plan with test card 4242 4242 4242 4242
3. Verify webhook fires, subscription record created
4. Verify access granted
5. Cancel subscription
6. Verify access retained until period_end
7. Test failed payment with test card 4000 0000 0000 9995
8. Verify past_due handling

## Step 9 — Report

```
Billing Setup Complete

  Provider:        {chosen}
  Billing model:   {subscription/usage/one-time}
  MoR:             {yes/no}
  Tiers:           {list}

  SDK installed:   {package}
  Env vars added:  {list}
  Webhook URL:     /api/webhooks/stripe (or equivalent)
  DB tables added: subscriptions

  Audit logging:   wired for billing events
  Documentation:   wiki/conventions.md (billing section)
                   wiki/compliance/billing-compliance.md

Next steps:
  1. Create products/prices in {provider} dashboard
  2. Wire frontend checkout buttons
  3. Run end-to-end test in test mode
  4. Switch to live keys when ready to charge
  5. Update Privacy Policy + ToS to mention billing data handling
  6. Run /vendor-review for {provider} (DPA check)
```

## Pitfalls

- Relying on local subscription state for high-stakes auth — webhooks lag
- No webhook signature verification — attackers can forge events
- Not handling `past_due` gracefully — annoy paying users
- DIY tax handling without realizing the burden — get hit by regulators
- No refund policy documented — disputes get ugly
- Storing card data yourself — instant PCI-DSS hell, NEVER do this
- No grace period on payment failures — losing customers who had a card decline
- Forgetting to test cancellation flow — users find ways to be charged forever
- Not auditing billing events — disputes become impossible to investigate

## Verification

- Provider SDK installed
- Webhook handler verifies signatures
- subscriptions table created and synced from webhooks
- Audit log fires for all billing events
- Test mode E2E flow succeeded (signup → subscribe → cancel → past_due)
- Documentation updated (conventions + billing-compliance)
- Privacy Policy reflects billing data handling
