> ⚠️ **REVIEW REQUIRED — adapt to this project before adopting**

# Encryption Policy

**Effective Date:** {{EFFECTIVE_DATE}}
**Owner:** {{DPO_NAME}}
**Review cycle:** Annual

## Purpose

Define encryption standards for data at rest and in transit.

## In Transit

- TLS 1.2 minimum, TLS 1.3 preferred
- HTTPS enforced (no HTTP fallback)
- HSTS enabled with `max-age=31536000`
- Certificate management automated (Let's Encrypt or vendor-managed)
- Internal service-to-service traffic encrypted (mTLS or VPN)

## At Rest

- Database PII columns: encrypted (column-level via pgcrypto, or DB-level via TDE)
- File storage (S3, GCS): encryption enabled (SSE-S3 minimum)
- Backups: encrypted with separate key from production
- Logs (audit + application): encrypted at storage destination
- Local development: developer laptops have full-disk encryption

## Key Management

- Production encryption keys: stored in secret manager ({{SECRET_MANAGER}})
- Key rotation: quarterly for production keys
- Key separation: dev/staging/production use separate keys
- Backup keys: stored separately from data backups

## Algorithms

- Symmetric: AES-256-GCM (preferred), AES-256-CBC (acceptable)
- Asymmetric: RSA-2048 or ECDSA P-256 minimum
- Password hashing: argon2id (preferred) or bcrypt (acceptable, cost ≥ 10)
- TLS: cipher suites approved by Mozilla "Modern" or "Intermediate"

## Banned Algorithms

- MD5, SHA1 for hashing
- DES, 3DES, RC4 for encryption
- TLS 1.0, TLS 1.1, SSL 3.0
- ECB mode

## Implementation

When implementing encryption:
- Use vendor primitives (don't roll your own crypto)
- Use authenticated encryption (GCM, ChaCha20-Poly1305)
- Use safe defaults (e.g., libsodium, AWS KMS SDK)

## Enforcement

`/security-check` audits encryption compliance.
`/compliance-audit` includes encryption controls (PDPA Protection Obligation, SOC 2 CC6).
