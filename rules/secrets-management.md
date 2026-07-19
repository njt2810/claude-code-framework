# Secrets Management — Always Loaded

Extends `security.md` (no secrets in code/git, env vars for config, no logging
secrets — those baseline rules live there and are not repeated here).

## Hard Rules

1. **If a secret ever reached git history, it MUST be rotated** — removal from
   current code is not enough.

2. **NEVER expose secrets to the client bundle.** Variables prefixed with
   `NEXT_PUBLIC_*` or `VITE_*` are visible to the browser — never put
   anything sensitive there.

3. **NEVER use the same secret across environments.** Dev, staging, and
   production must have different API keys, database URLs, signing keys.

4. **NEVER share secrets via Slack, email, or chat.** Use the secret manager,
   or 1Password / similar.

## Required Patterns

5. **Secret manager for production.** Production secrets come from a secret
   manager (Vercel/Netlify env vars, AWS Secrets Manager, Doppler, etc.),
   not from `.env.production` files.

6. **`.env` files are gitignored.** Only `.env.example` files are committed,
   and they contain placeholder values.

7. **Generate secrets cryptographically.** Use `openssl rand -base64 32` or
   equivalent. Never invent a "memorable" secret.

8. **Rotate secrets:**
    - Immediately if exposed in git history or logs
    - Quarterly for production-critical secrets (JWT signing, encryption keys)
    - On employee departure (if multi-person team)
    - On vendor breach

9. **Document secret inventory** in `wiki/operations/environments.md`:
    - What each secret is for
    - Where it's stored (secret manager, env file)
    - When it was last rotated
    - Who has access

## If You Detect a Secret in Code

```
🔴 CRITICAL: Possible secret in {file}:{line}
   Pattern matched: {pattern}
   Required actions:
   1. Move to environment variable
   2. Replace usage with process.env.{NAME}
   3. Add to .env.example with placeholder
   4. ROTATE the exposed secret immediately
   5. If it was ever committed, treat git history as compromised
```

## If You Detect a Secret in Git History

```
🔴 CRITICAL: Secret found in git history (commit {sha})
   Even if removed from current code, this secret is exposed.
   Required actions:
   1. Rotate the secret IMMEDIATELY at the source
   2. Update the secret in all environments
   3. Consider using git-filter-repo or BFG to scrub history
      (note: scrubbing alone is not sufficient — rotation is what matters)
   4. Update wiki/operations/incidents/ with the exposure record
```

## Test Secrets

Test fixtures may contain dummy secrets. To prevent false positives:
- Use obviously fake values: `sk_test_FAKE_TOKEN_FOR_TESTS_ONLY`
- Prefix all test secrets with `TEST_` or `FAKE_`
- Document in test files: `// Test-only fake credentials, not real`
