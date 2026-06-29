---
name: email-setup
description: |
  TRIGGER when: the user wants to add transactional email (signup, password reset,
  receipts), marketing email, or any email infrastructure.
  DO NOT TRIGGER when: the user wants to add an email field to a form (just add it),
  or to integrate inbound email parsing (different concern).
argument-hint: "[transactional|marketing|both]"
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# Email Infrastructure Setup

## When to Use

When the project needs to send emails — transactional (system-triggered) or
marketing (campaign-style). Vendor-neutral. Most early-stage SaaS only needs
transactional initially.

## Procedure

## Step 1 — Determine Scope

From `$ARGUMENTS`:
- `transactional` — signup confirmation, password reset, receipts, notifications
- `marketing` — newsletters, drip campaigns, announcements
- `both` — set up both
- empty — ask

## Step 2 — Present Options

**Transactional:**

| Provider | Strengths | Tradeoffs | Free tier |
|----------|-----------|-----------|-----------|
| **Resend** | Best DX for devs, React Email integration | Newer | 3k/mo free |
| **Postmark** | Best deliverability, dedicated to transactional | More expensive | 100/mo free |
| **SendGrid** | Mature, broad features | Mediocre UX | 100/day free |
| **AWS SES** | Cheapest at scale | Setup complexity | 62k/mo (from EC2) |
| **Mailgun** | Solid, EU presence | Mediocre UX | First 5k/mo |

Strong recommendation: **Resend** for new projects (best DX, React Email templates).

**Marketing:**

| Provider | Strengths | Tradeoffs |
|----------|-----------|-----------|
| **Resend Audiences** | One vendor for both, growing features | Marketing features lighter |
| **Loops** | Designed for SaaS marketing, lifecycle automation | Subscription |
| **Mailchimp** | Mature, broad templates | Heavy, pricey |
| **ConvertKit** | Indie/creator focus, automation strong | Subscription |
| **PostHog Email** | If using PostHog already, one less vendor | Newer |

For very early stage: skip marketing email, use transactional only.
Add marketing when you have user base + lifecycle to nurture.

## Step 3 — Install & Configure Transactional

For **Resend** (recommended):

1. `npm install resend react-email @react-email/components`
2. Add to `.env.example`:
   - `RESEND_API_KEY=re_...`
   - `EMAIL_FROM=noreply@yourdomain.com`
3. Create `src/lib/email.ts`:

```typescript
import { Resend } from "resend";

const resend = new Resend(process.env.RESEND_API_KEY!);
const FROM = process.env.EMAIL_FROM ?? "noreply@example.com";

export async function sendEmail({
  to,
  subject,
  html,
  replyTo,
}: {
  to: string;
  subject: string;
  html: string;
  replyTo?: string;
}): Promise<void> {
  const { error } = await resend.emails.send({
    from: FROM,
    to,
    subject,
    html,
    reply_to: replyTo,
  });
  if (error) {
    // log error, don't throw — email failures shouldn't break the user flow
    console.error("[email]", error);
  }
}
```

4. Create email templates in `emails/` directory using React Email:
   - `emails/WelcomeEmail.tsx`
   - `emails/PasswordResetEmail.tsx`
   - `emails/ReceiptEmail.tsx`

## Step 4 — DNS Setup

Email deliverability requires DNS configuration:

1. **SPF record** — authorizes sender domain
2. **DKIM record** — signs outgoing email
3. **DMARC record** — policy for unauthorized senders

The provider's onboarding shows exact DNS records to add. Use the user's DNS
provider (Cloudflare, Vercel, Route 53) to add them.

Document in `wiki/operations/email-deliverability.md`:
- SPF: included in DNS
- DKIM: included in DNS
- DMARC: policy set to `p=quarantine` (or `p=reject` once verified)
- From address: noreply@{domain}
- Reply-to address: support@{domain} (or none)
- Bounce handling: provider absorbs (Resend, Postmark)

## Step 5 — Email Templates

Email content conventions:
- Plain language, no marketing speak in transactional
- Always include user-relevant context (their name, the action they took)
- Include a footer with reason for the email and unsubscribe link
- Single CTA per email
- Mobile-responsive (React Email handles this)

Template inventory to build:
- Welcome (after signup)
- Email verification (if not using magic links)
- Password reset
- Receipt / invoice (if billing exists)
- Subscription renewal reminder
- Subscription canceled confirmation
- Account deletion confirmation

## Step 6 — Compliance & PDPA

Transactional emails to existing users: PDPA-compliant by purpose limitation.
Marketing emails: require consent.

In Singapore PDPA:
- Marketing must have opt-in or pre-existing customer relationship
- Every marketing email needs unsubscribe link (CAN-SPAM, PDPA)
- Unsubscribe must work within 30 days (CAN-SPAM) or 14 days (some jurisdictions)

For production streams:
- Add `marketing_consent` field to users table
- Honor opt-out immediately
- Document email categories in privacy policy

## Step 7 — Audit Logging

Wire audit log helper to fire on:
- email.sent.{category}.success
- email.sent.{category}.failure
- email.bounced
- email.complained (marked as spam)
- marketing.consent.granted / withdrawn

## Step 8 — Test Send

Send a test email to your own address to verify:
- Email arrives in inbox (not spam)
- Renders correctly on mobile and desktop
- Links work
- Unsubscribe (if marketing) works

## Step 9 — Update Data Inventory

Add to `/data-inventory`:
- email — already there
- marketing_consent (boolean) — for marketing
- email_bounce_count — for deliverability tracking
- last_email_sent_at — for rate limiting

## Step 10 — Report

```
Email Setup Complete

  Provider:        {chosen}
  Scope:           {transactional/marketing/both}
  From:            {EMAIL_FROM}
  Templates:       {N} created

  DNS:             SPF / DKIM / DMARC documented
  Wrapper:         src/lib/email.ts
  Audit logging:   wired

  Documentation:
    wiki/operations/email-deliverability.md
    wiki/conventions.md (email section)

Next steps:
  1. Sign up for {provider} and verify your domain
  2. Add DNS records to your DNS provider
  3. Wait 24h for DNS propagation, then verify in provider dashboard
  4. Add real API key to .env (not .env.example)
  5. Send a test email to yourself
  6. (Marketing) Add unsubscribe flow and marketing_consent column
  7. Run /vendor-review for {provider} (DPA check)
```

## Pitfalls

- Skipping DNS setup → emails land in spam, customers think you ghosted them
- Not handling bounces → list rot, deliverability degrades
- Sending marketing without explicit consent → PDPA / CAN-SPAM violation
- One template for everything → terrible UX
- Storing email body in DB → privacy risk and storage cost
- No reply-to → support emails get black-holed
- Sending transactional and marketing from same domain without subdomain strategy → marketing complaints kill transactional deliverability
- Forgetting unsubscribe link in marketing → instant CAN-SPAM violation

## Verification

- Provider SDK installed and wrapper exists
- DNS records documented (and added by user)
- At least 1 template created and tested
- Audit logging fires on send events
- For production: marketing_consent column exists if marketing is scoped
- For production: unsubscribe flow works end-to-end
- Documentation written
