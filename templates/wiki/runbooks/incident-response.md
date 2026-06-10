# Incident Response

## When Something Breaks in Production

1. Check error monitoring (Sentry, logs, or wherever errors surface)
2. Copy the error trace
3. In Claude Code, run: `/bug-fix` and paste the error
4. Claude follows the evidence-based debugging workflow
5. Fix, test, deploy
6. Document in wiki/decisions/ if it reveals a design flaw

## When a Secret May Have Been Exposed

1. Immediately rotate the compromised credential (generate new key/password)
2. Revoke the old credential from the service provider
3. Update your .env with the new values
4. Check git history: `git log --all -p --grep="secret_name"` to see if it was committed
5. If found in git history, consider cleaning with git-filter-repo or BFG Repo Cleaner
6. Update wiki/runbooks/security-baseline.md with the incident

## Monitoring Checklist
- [ ] Error tracking configured
- [ ] Key user flows have health checks
- [ ] Alert notifications configured
- [ ] Rollback procedure documented
- [ ] Security baseline document current (wiki/runbooks/security-baseline.md)
