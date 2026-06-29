# Deploy Runbook

How to deploy this project to each environment. Use `/deploy [env]` to run
this automatically.

## Environments

| Env | URL | Auto-deploy from | Manual deploy required |
|-----|-----|------------------|------------------------|
| development | http://localhost:3000 | n/a | n/a |
| staging | https://staging.{{DOMAIN}} | merge to main | optional |
| production | https://{{DOMAIN}} | manual via /deploy production | yes |

## Pre-Deploy Checklist

Before any production deploy, verify:
- [ ] Tests pass on main
- [ ] Linter passes
- [ ] Build succeeds
- [ ] Migrations are backward-compatible
- [ ] No CRITICAL gaps in `wiki/compliance/gaps.md`
- [ ] Production secrets are in secret manager
- [ ] Health check endpoint responds 200

## Deploy Commands

### Development
```bash
{{DEV_COMMAND}}  # e.g., npm run dev
```

### Staging
```bash
{{STAGING_DEPLOY_COMMAND}}  # e.g., vercel deploy
```

### Production
```bash
{{PROD_DEPLOY_COMMAND}}  # e.g., vercel deploy --prod
```

Or run `/deploy production` which enforces all gates.

## Post-Deploy Verification

After deploy, verify:
1. Health check: `curl https://{{DOMAIN}}/health` → expect 200
2. Check error tracking dashboard for new errors
3. Spot-check key flows (signup, login, primary feature)
4. Monitor for 30 minutes

If issues: follow `wiki/operations/rollback-runbook.md`.

## Rollback

```bash
{{ROLLBACK_COMMAND}}
```

See `wiki/operations/rollback-runbook.md` for full procedure.

## Logs

- Recent deploys: `wiki/operations/deploy-log.md`
- Application logs: {{LOGS_URL}}
- Error tracking: {{ERROR_TRACKING_URL}}
