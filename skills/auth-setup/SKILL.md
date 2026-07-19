---
name: auth-setup
description: |
  TRIGGER when: the user wants to add authentication, set up login/signup,
  add SSO, MFA, magic links, or choose an auth provider.
  DO NOT TRIGGER when: the user wants to debug existing auth (use /bug-fix),
  or to set up authorization rules (different concern — handle in code review).
disable-model-invocation: true
user_locked: true
pinned: true
---

# Authentication Setup

## When to Use

When a project needs to add user authentication for the first time, or to
migrate from a brittle DIY auth to a managed provider. Vendor-neutral —
the skill walks the user through the choice.

## Procedure

## Step 1 — Stream Check & Project Needs

Read CLAUDE.md to confirm stream. For learning: usually skip auth or use the
simplest possible setup.

Ask the user about requirements:
1. Sign-in methods needed: email+password / magic link / Google / Apple / GitHub / SSO?
2. Multi-factor (MFA): required for any users? (yes recommended for production)
3. Multi-tenancy: per-user or per-organization?
4. Roles: admin/user only, or fine-grained permissions?
5. Compliance constraints: SOC 2 / PDPA / SSO required for enterprise clients?
6. Scale expectation: <1k users, 1k-100k, >100k?
7. Budget for auth: free tier OK, or willing to pay for managed?

## Step 2 — Present Options (vendor-neutral)

| Provider | Strengths | Tradeoffs | Free tier |
|----------|-----------|-----------|-----------|
| **Clerk** | Best UX, easy setup, all features included | Pricier above free tier | 10k MAU |
| **Auth0** | Mature, enterprise-ready, broad SSO | Pricey at scale | 7.5k MAU |
| **Supabase Auth** | Free with Postgres, simple | Less polished UX | Free generous |
| **NextAuth.js / Auth.js** | Free, self-host, code-owned | More integration work | Free (you host) |
| **Better Auth** | Modern, full-featured, open-source | Newer ecosystem | Free (you host) |
| **Lucia / Oslo** | Library not service, full control | DIY everything | Free (you host) |
| **DIY (bcrypt + JWT + sessions)** | Total control, no vendor | Brittle, security-risky | Free |

Strong recommendations:
- For client-facing SaaS (paying users): managed provider (Clerk, Auth0, Better Auth)
- For internal tools: NextAuth or DIY OK
- For solo founder, fast MVP: Clerk (highest velocity)
- For cost-sensitive: Better Auth or NextAuth

NEVER recommend DIY for anything touching real customer data — too easy to
break and SOC 2 auditors don't trust it.

Ask the user to pick.

## Step 3 — Install & Configure

Based on choice, install SDK and create wrapper:

For **Clerk**:
1. `npm install @clerk/{framework}`
2. Add `CLERK_SECRET_KEY` and `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` to `.env.example`
3. Wrap app with `<ClerkProvider>`
4. Add middleware for protected routes
5. Use `useUser()`, `auth()` per Clerk docs

For **Better Auth**:
1. `npm install better-auth`
2. Configure adapter (Postgres/Neon/SQLite)
3. Set up auth handler
4. Add session middleware

For **NextAuth.js**:
1. `npm install next-auth`
2. Configure providers
3. Add `[...nextauth]` route handler

Etc. for each provider.

## Step 4 — Session & Token Conventions

Document in `wiki/conventions.md` (auth section):

```markdown
## Authentication

- Provider: {chosen}
- Session storage: {cookie / database / vendor-managed}
- Session lifetime: {N} hours
- MFA: {required for roles / optional / disabled}
- Password requirements: {12+ chars, no breach list, no upper-bound}
- Login throttling: {N attempts per IP per hour}
- Magic link expiry: {N} minutes

## Authorization

- Role check pattern: `if (!user.has('admin')) throw new Unauthorized()`
- Resource ownership check: `if (resource.owner_id !== user.id) throw new NotFound()`  // never reveal existence
- Default deny: any route without explicit auth check is treated as protected
```

## Step 5 — Audit Logging for Auth

Wire audit log helper (from `/audit-logging-setup`) to fire on:
- user.login.success / user.login.failure
- user.signup
- user.password_reset_requested
- user.password_changed
- user.mfa_enabled / disabled
- user.logout
- session.created / expired

If the helper doesn't exist yet: STOP and suggest running
`/audit-logging-setup` first for production streams.

## Step 6 — Test Auth Flow

Manually verify (or have the user verify):
1. Signup with new email → user created in DB
2. Login with credentials → session established
3. Login with wrong password → fails, audit log captures
4. Logout → session destroyed
5. Access protected route without session → redirected/401
6. Password reset flow end-to-end
7. (If MFA) MFA enrollment and challenge

## Step 7 — Update Data Inventory

If `/data-inventory` has been run, append auth-related PII:
- email — collected at signup
- password (hashed) — stored in users table or provider
- IP address (login attempts) — for fraud/security
- Session tokens — for active sessions
- MFA secrets (if applicable)

## Step 8 — Report

```
Auth Setup Complete

  Provider:        {chosen}
  Sign-in methods: {list}
  MFA:             {required/optional/disabled}
  Audit logging:   {wired/TODO}

  SDK installed:   {package}
  Env vars added:  {list}
  Wrapper file:    {path}

  Conventions doc: wiki/conventions.md (auth section)

Next steps:
  1. Sign up for {provider} and configure your project
  2. Add real API keys to .env (not .env.example)
  3. Test signup → login → logout end-to-end
  4. If production: run /security-check on the auth integration
  5. If production: run /compliance-audit to verify auth controls
```

## Pitfalls

- DIY auth for production projects — high security risk, SOC 2 will reject
- Storing passwords without bcrypt/argon2 — instant CRITICAL
- No login throttling — credential stuffing attacks
- Sessions in localStorage instead of httpOnly cookies — XSS-vulnerable
- No MFA option for admins — single password is single point of failure
- Forgetting password reset flow — locked-out users churn
- No audit logs for auth events — can't investigate compromises
- Different auth on different services (SSO not used) — fragmented security

## Verification

- Provider SDK installed
- Auth pages/components added
- Protected routes use auth middleware
- Audit logging fires on auth events
- `wiki/conventions.md` updated with auth section
- User has tested at least signup → login → logout flow
- For production: SOC 2 controls for access management covered
