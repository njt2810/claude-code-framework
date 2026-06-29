# Audit Everything — Always Loaded (Production Streams Only)

For production streams (org1, org2, personal-with-production-flag), every
state-changing action must be auditable. SOC 2 evidence depends on this.

## What Must Be Audited

State changes that affect users, data, or system integrity:

**Authentication:**
- user.login.{success,failure}
- user.logout
- user.session_expired
- user.password_reset_requested
- user.password_changed
- user.mfa_enabled
- user.mfa_disabled

**Account lifecycle:**
- user.created
- user.deleted
- user.email_changed
- user.role_changed

**Data access (sensitive):**
- data.export — user downloads their data
- data.deletion_request — user requests deletion
- data.viewed_by_admin — admin views another user's data
- data.bulk_export — admin exports many records

**Admin / system:**
- admin.config_changed
- admin.user_impersonated
- admin.permission_granted
- admin.permission_revoked
- admin.feature_flag_toggled

**Billing (if applicable):**
- payment.{attempted,succeeded,failed,refunded}
- subscription.{created,upgraded,downgraded,canceled}
- trial.{started,ended}

**Compliance:**
- consent.granted
- consent.withdrawn
- privacy.policy_accepted

## What NOT to Audit

These do NOT need to be in the audit log (use application logs instead):
- Page views (use analytics)
- Successful read operations (unless sensitive)
- Background job ticks
- Health check responses
- Cache hits/misses

The audit log is for accountability, not observability.

## How to Audit

Use the `audit()` helper from `/audit-logging-setup`. Call it AFTER the action
completes successfully (so failed actions are logged with `outcome: "failure"`).

```typescript
await audit({
  actor: user.id,
  action: "user.login.success",
  resource: `user:${user.id}`,
  outcome: "success",
  metadata: { method: "password" },
  ip: req.ip,
});
```

## Never Include in Audit Metadata

- Password values (even hashed)
- Session tokens
- API keys / secrets
- Raw PII (use IDs)
- Credit card numbers
- The audit helper auto-redacts common keys; your code must also be careful

## When You're Coding a State Change

For production streams, ask:
1. Is this a state change that affects accountability? (yes → must audit)
2. Do I have the actor (user_id or "system")?
3. Do I have the resource being changed?
4. Is the outcome clear (success vs failure)?
5. Is metadata PII-free?

If you can't answer all yes, fix before merging.

## If You See Missing Audit Logging

```
🟡 MEDIUM: State change without audit log in {file}:{line}
   Action: {what}
   Suggest: add audit() call after action succeeds
```
