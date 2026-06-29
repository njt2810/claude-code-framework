# Rollback Runbook

How to roll back a failed deploy. Time matters — use this immediately when
post-deploy health checks fail.

## When to Roll Back

Trigger rollback if any of these occur after deploy:
- Health check fails for > 30 seconds
- Error rate jumps > 5x baseline within 5 minutes
- p95 latency degrades > 2x baseline within 5 minutes
- Customer reports of major brokenness
- Critical functionality broken in spot checks

## Pre-Rollback

1. Capture state for postmortem:
   - Screenshot dashboards before rollback
   - Save logs from the deploy window
   - Note the failed deploy commit SHA

2. Decide: full rollback vs targeted fix?
   - Full rollback = revert to previous deploy
   - Targeted fix = hotfix forward (only if root cause is clear AND small)

When uncertain → ALWAYS roll back first, investigate after.

## Rollback Commands

### {{HOSTING_VENDOR}}

```bash
{{ROLLBACK_COMMAND}}
```

Examples per vendor:
- **Vercel**: `vercel rollback {previous-deployment-url}`
- **Netlify**: re-publish previous deploy from UI or `netlify deploy --prod --dir={previous-build}`
- **Fly.io**: `fly deploy --image {previous-image-tag}`
- **Cloud Run**: `gcloud run services update-traffic SERVICE --to-revisions=PREVIOUS=100`
- **Kubernetes**: `kubectl rollout undo deployment/SERVICE`
- **AWS ECS**: re-deploy previous task definition

## Database Migrations

If the failed deploy included migrations:

1. **Forward-compatible migrations:** Code rollback is safe; data unchanged
2. **Breaking migrations:** Code rollback may not work — see migration-specific rollback in `wiki/operations/migration-history.md`

Common patterns:
- Adding a column with default: forward-compat, safe to roll back code
- Dropping a column: NOT safe to roll back code if old code reads it
- Renaming a column: NOT safe — need migration rollback

If migration was destructive: contact the user immediately. Do not improvise.

## Post-Rollback Verification

After rollback:
1. Health check: confirm 200 response
2. Error rate: confirm returned to baseline
3. Latency: confirm returned to baseline
4. Spot check key flows
5. Monitor for 30 minutes

## Communication

If customers were affected, send incident communication per template:
`wiki/operations/incident-comms-template.md`

Update status page if you have one.

## After the Smoke Clears

1. Run `/incident` to formally document the failed deploy
2. Postmortem within 5 days
3. Action items: what tests/gates would have caught this?
