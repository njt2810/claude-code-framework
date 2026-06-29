> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Password Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Annual

## Purpose

Define password requirements for users and personnel accessing systems.

## Scope

All accounts: customer-facing, internal, service accounts.

## Customer Password Requirements

- Minimum 12 characters
- Must not be in known breach lists (check via HaveIBeenPwned / similar)
- No mandatory composition rules (no "must have uppercase + number + symbol" — modern guidance per NIST)
- No periodic rotation requirement (rotate only on compromise)
- Stored using bcrypt or argon2 (never plaintext, never MD5/SHA1)
- MFA option offered to all users
- MFA required for admin/staff accounts

## Personnel Password Requirements

- Same minimum as customer (12+ chars)
- Stored in approved password manager (1Password, Bitwarden)
- Rotated only on:
  - Suspected compromise
  - Personnel departure (revoke and rotate shared secrets)
  - Quarterly for production-critical service account passwords

## MFA Required For

- Production system access
- Source code repository (GitHub)
- Cloud console (AWS, GCP, Vercel)
- Secret manager
- Customer-facing admin panels
- Email accounts (especially DPO and incident response contacts)

## Banned Practices

- Sharing passwords in chat, email, or documents
- Reusing passwords across systems
- Writing passwords on physical media
- Disabling MFA "for convenience"

## Account Lockout

- 5 failed login attempts within 15 minutes triggers temporary lockout (1 hour)
- After 10 failed attempts in 24 hours, account requires password reset
- All failures logged to audit log

## Enforcement

Violations reported and remediated per incident response policy.

## Review

Annual review of this policy and any incidents involving passwords.
