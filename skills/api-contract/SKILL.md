---
name: api-contract
description: |
  TRIGGER when: the user wants to set up API contract (OpenAPI/GraphQL),
  add contract tests, check for breaking changes, generate client SDKs from
  schema, or audit API design.
  DO NOT TRIGGER when: the user wants to debug a specific API endpoint (use /bug-fix),
  or add a single endpoint (just add it then run /api-contract verify).
argument-hint: "[setup|generate|verify|diff|publish]"
disable-model-invocation: true
effort: medium
user_locked: true
pinned: true
---

# API Contract Management

## When to Use

When the project exposes an API to external consumers (clients, mobile apps,
third-party integrations, other internal services). Manages the schema as
a contract — changes are deliberate, breaking changes are visible, consumers
can rely on stability.

## Lead Engineer Guidance — Why This Matters

Without a contract:
- Every API change risks breaking unknown consumers
- New team members can't tell what endpoints exist
- Client SDKs drift from server reality
- Integration testing is manual and incomplete
- Documentation rots within a week of writing

With a contract (OpenAPI for REST, GraphQL schema for GraphQL):
- Schema is generated FROM code (or code is generated FROM schema)
- Breaking changes are detected automatically in CI
- Client SDKs are auto-generated, always in sync
- Documentation is generated, always current
- Contract tests verify implementation matches schema

**When to set up:**
- Any project that exposes endpoints to >1 consumer (frontend + 3rd party = 2)
- Before signing a client who'll integrate via API
- When you want to publish public API docs

**When to skip:**
- Internal-only endpoints used by one frontend you control (less critical, but still good)
- Pure server-rendered apps with no JSON endpoints

## Procedure

## Step 1 — Operation: SETUP (first time)

Detect API style:
- REST → OpenAPI 3.x
- GraphQL → SDL or code-first
- tRPC → tRPC's built-in type sharing (no manual contract needed)
- gRPC → .proto files

Present setup options based on style + stack:

**REST + Node/TS:**
- Code-first: `zod-openapi` (zod schemas → OpenAPI doc) — recommended
- Schema-first: write `openapi.yml` manually, generate handlers
- Framework-integrated: NestJS Swagger, Fastify Swagger, Hono OpenAPI

**REST + Python:**
- FastAPI (automatic OpenAPI from type hints) — best DX
- Flask + apispec
- Django + drf-spectacular

**GraphQL + Node:**
- Apollo Server / GraphQL Yoga (SDL)
- Pothos (code-first with TypeScript)

**GraphQL + Python:**
- Strawberry (code-first)
- Graphene

Install dependencies. Set up the contract source-of-truth file path:
- `openapi.yml` or `docs/api/openapi.yml` for REST
- `schema.graphql` for GraphQL

## Step 2 — Operation: GENERATE

For code-first (zod, Pothos, FastAPI, Strawberry):
- Build / introspect the app
- Emit the schema file
- Diff against committed version
- Commit if changed

For schema-first:
- Edit the schema file
- Re-generate handler stubs / types
- Wire to existing code

Output the artifact path. Suggest:
"Want to generate a client SDK from this? (yes/no)"
If yes, use:
- TypeScript: `openapi-typescript` or `openapi-fetch` for REST; `graphql-codegen` for GraphQL
- Python: `openapi-python-client` for REST

## Step 3 — Operation: VERIFY (contract tests)

Generate contract tests that compare runtime behavior to schema:

**For REST (Dredd or schemathesis):**
- Run requests for every documented endpoint
- Verify response shape matches schema
- Test parameter validation (required fields, types)
- Detect undocumented endpoints

**For GraphQL:**
- Schema introspection in CI
- Type-check resolvers against schema
- Run example queries from documentation

Add to CI: contract tests run on every PR. PR blocked if schema doesn't
match implementation.

## Step 4 — Operation: DIFF (breaking change detection)

Compare current schema against the version on main:
- REST: use `openapi-diff` or `oasdiff`
- GraphQL: use `graphql-inspector`

Classify changes:
- **Safe** (non-breaking):
  - Add new endpoint
  - Add new optional field to response
  - Add new optional field to request
  - Add new GraphQL type / query / mutation
- **Risky**:
  - Add required field to request
  - Change response field's optional/required status
  - Add new required parameter
- **Breaking**:
  - Remove endpoint
  - Remove field
  - Change field type
  - Change required/optional
  - Change auth requirements

For RISKY or BREAKING changes:
- Generate a notice for downstream consumers
- Require explicit confirmation in PR description
- Block merge until consumer notification is sent (for production streams)

## Step 5 — Operation: PUBLISH

Generate human-readable docs:
- REST: Redoc, Swagger UI, Mintlify, Bump.sh, Stoplight
- GraphQL: GraphQL Playground, Apollo Studio, gql.tada

Publish destination options:
- `docs.{domain}` (public)
- Internal docs portal (private)
- README.md (basic version)

For production streams: also publish to `wiki/api/` as committed reference.

## Step 6 — Auditor's Checklist

For production streams, the Compliance Officer cares about:
- Authentication scheme documented (OAuth, API key, etc.)
- Rate limits documented
- PII fields marked in schema (use `x-pii: true` extension in OpenAPI)
- Error response shapes documented
- Versioning strategy stated (URL path, header, etc.)

## Step 7 — Report

```
API Contract Management — {operation}

  Style:             {REST / GraphQL / etc.}
  Tool:              {chosen}
  Schema file:       {path}
  Endpoints:         {N}  (REST) or {types: N, queries: N, mutations: N} (GraphQL)
  Generated SDK:     {if generated}

  Contract tests:    {N in CI}
  Last diff vs main: {N safe, N risky, N breaking}

  Documentation:     {URL or path}

Recommended next:
  - Add contract tests to CI (run on every PR)
  - For each consumer of this API, document them in wiki/api/consumers.md
  - Set up breaking-change alerts (block PRs that introduce them)
  - For production: publish docs to a stable URL
```

## Pitfalls

- Hand-writing OpenAPI while also hand-writing handlers — they will drift. Pick one source of truth.
- Schema-first without code generation — same drift problem
- No contract tests in CI — schema rots silently
- Treating breaking changes as "minor" — consumers will break
- No PII annotation in schema — auditor can't tell what's sensitive
- Publishing internal API as public — leak of attack surface

## Verification

- Schema file exists at the chosen path
- Contract tests added to CI
- Diff command works against main
- Auto-generated client SDK matches schema (if generated)
- Public docs accessible (if published)
- PII annotations present in schema for sensitive fields
