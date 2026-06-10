# Security Rules — Always Loaded

- NEVER write API keys, tokens, passwords, or secrets in code files
- NEVER commit .env files — only .env.example with placeholder values
- NEVER log sensitive data (passwords, tokens, PII, credit card numbers)
- Always use environment variables for configuration and secrets
- Always validate and sanitize user input before processing
- When touching auth, payments, user data, or external APIs:
  delegate to the security-auditor subagent before committing
- If you detect what appears to be a secret in existing code,
  alert immediately: "⚠️ Possible secret found in {file}:{line}"
