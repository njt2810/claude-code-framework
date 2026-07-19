---
name: security-check
description: |
  TRIGGER when: the user wants a security audit, says check security, scan for secrets,
  is worried about exposed credentials, or is preparing to deploy/share/open-source code.
  DO NOT TRIGGER when: the user is doing a code review (/code-review), general documentation
  (/document-all), or project setup (/init-project — which has its own security step).
disable-model-invocation: true
context: fork
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Agent
user_locked: true
pinned: true
---

# Security Check — On-Demand Security Audit

## When to Use

When the user wants a security audit before deploying, sharing, or open-sourcing code.
Not for code reviews, documentation, or project setup (which has its own security step).

## Procedure

Run a complete security review of this project right now.

## Step 1 — Delegate to Security Auditor

Delegate to the security-auditor subagent with full project access:

"Run a complete security audit of this project:
 1. Scan all files for hardcoded secrets (API keys, passwords, tokens,
    private keys, credentials, connection strings)
 2. Scan git history for previously committed secrets
 3. Check .env and .gitignore configuration
 4. Check config files for hardcoded credentials
 5. Check for insecure dependencies (run pip-audit or npm audit)
 6. Review any auth, payment, or user data handling code"

## Step 2 — Present Results

Show the audit results clearly:

```
SECURITY CHECK RESULTS

  Project: {name}
  Date: {today}
  Files scanned: {count}
  Git history checked: {yes/no}

  CRITICAL:  {count}
  HIGH:      {count}
  MEDIUM:    {count}
  INFO:      {count}

  {For each finding:}
  {severity} {type}: {description}
     File: {filepath}:{line}
     Fix: {what to do}
```

## Step 3 — Offer Remediation

If any CRITICAL or HIGH issues found:

"I found {count} issues that should be fixed.

 I can fix these for you now:
 - Move {count} secrets from code to .env
 - Update {count} files to use environment variables
 - Update .gitignore to cover missing entries
 - Update .env.example with new placeholder entries

 Fix these now? (yes / show me details first / skip)"

If approved:
1. Move secrets to .env
2. Update code to reference env vars
3. Update .gitignore and .env.example
4. Commit: "Security remediation — {summary}"

For secrets found in git history:
"These secrets exist in git history and should be rotated:
 {list with service names}
 
 Even though they're removed from current code, anyone who clones
 the repo can find them. Generate new credentials from each
 service provider and update your .env."

## Step 4 — Update Security Baseline

Update `wiki/runbooks/security-baseline.md` with:
- Date of this check
- Result (pass / issues found)
- What was remediated
- What still needs manual action (key rotation, history cleaning)

## Step 5 — Summary

```
SECURITY CHECK COMPLETE

  Result: {PASS / REMEDIATED / NEEDS ATTENTION}
  
  {If PASS}: No security issues found. Your project is clean.
  
  {If REMEDIATED}: {count} issues fixed automatically.
    {If secrets in git history}: {count} secrets need manual
    rotation — see details above.
  
  {If NEEDS ATTENTION}: {count} issues need your manual action.
    See remediation plan above.
  
  Security baseline updated: wiki/runbooks/security-baseline.md
  Next recommended check: before your next deployment
```

## Pitfalls

- Missing git history check — secrets removed from code may still be in history
- Not checking .env.example against actual required vars
- Running npm audit on a project without node_modules installed (install first)
- Modifying code directly during the audit — this is a read-only analysis

## Verification

- All files were scanned (not just a sample)
- Git history was checked for committed secrets
- Each finding has a severity level and remediation step
- Security baseline was updated in wiki/runbooks/
