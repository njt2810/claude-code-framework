---
globs: ["*.py", "*.js", "*.ts", "*.jsx", "*.tsx", "*.mjs", "*.cjs"]
---

# Evidence-Based Debugging

## Three Laws (non-negotiable)

**Law 1 — PROVE IT FIRST:** Before writing any fix, reproduce the bug
with actual output. If you cannot reproduce it, say so and ask for
more information. Do NOT guess at fixes.

**Law 2 — FAILING TEST BEFORE FIX:** Write a test that fails because
of the bug. Run it, confirm it fails, show the output. Only then
write the fix. Run the test again — it must pass. Run the full test
suite — no new failures.

**Law 3 — TWO-ATTEMPT LIMIT:** If your fix doesn't work after 2
attempts, STOP. Present what you tried, why it failed, and 2-3
alternative approaches. Wait for the user to choose.

## Red Flags — STOP if:
- Editing the same file for the 3rd time for one bug
- Fixing something your previous fix just broke
- Can't explain WHY the fix works
- More test failures after your fix than before

## NEVER:
- Say "I've fixed it" without showing passing test output
- Make multiple changes at once
- Silently retry a failed approach
