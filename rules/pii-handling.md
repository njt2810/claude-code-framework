# PII Handling — Always Loaded

When code touches personal data, apply these rules without being asked.

## What Counts as PII

Direct identifiers:
- email, phone, name, address, date of birth, photo, voice, biometric

Quasi-identifiers (PII under PDPA / GDPR):
- IP address, device ID, location, MAC address, browser fingerprint, user-agent

Sensitive PII (extra scrutiny):
- government ID (NRIC/passport), financial (card/bank), health, religious,
  political, criminal records, sexual orientation, children's data

## Hard Rules

1. **NEVER log PII values.** Log IDs, not contents.
   - Bad: `logger.info("user logged in", { email: user.email })`
   - Good: `logger.info("user logged in", { user_id: user.id })`

2. **NEVER include PII in error messages thrown to the client.**
   - Bad: `throw new Error("User not found: john@example.com")`
   - Good: `throw new NotFound("User not found")`

3. **NEVER store PII in localStorage / sessionStorage.**
   - Use httpOnly cookies for session tokens.
   - Don't cache PII client-side beyond the active session.

4. **NEVER use PII as a URL parameter.**
   - URLs end up in browser history, server access logs, analytics, referrers.
   - Use opaque IDs in URLs, not emails or names.

5. **NEVER seed test/staging databases with real PII.**
   - Use Faker / synthetic data.
   - If you must clone prod for debugging, run a PII scrubber first.

6. **NEVER expose PII via API to users who shouldn't see it.**
   - Authorization check before every PII-returning endpoint.
   - Default deny: explicit allow per resource.

## Required Patterns

7. **Encryption at rest.** Any PII column in a database must be encrypted at
   rest (column-level if available, or DB-level otherwise). Document where.

8. **Retention policy.** Every PII field has a retention period. Default if
   not specified: delete on account deletion + 30 days for legal hold.

9. **Right to access / delete.** Every project storing PII must have:
   - An endpoint or process for users to export their data (PDPA s.21)
   - An endpoint or process for users to delete their data (PDPA s.22)

10. **Cross-border transfers.** PII sent to non-Singapore vendors requires
    a DPA. Document in `wiki/compliance/vendor-register.md`.

## When in Doubt

- Treat the value as PII if uncertain
- Ask the user if it's collected with consent
- Delegate to Compliance Officer for a sanity check

If you detect a violation in existing code, flag it:
"⚠️ PII handling concern in {file}:{line} — {what}. Compliance Officer should review."
