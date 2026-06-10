---
globs: ["*test*", "*spec*", "*.test.*", "*.spec.*", "test_*", "*_test.*"]
---

# Testing Standards

- Every new feature must include tests before merging
- Test files live next to source or in a tests/ directory
- Minimum test types per feature:
  - Unit tests for pure logic
  - Integration tests for API endpoints or external calls
  - Edge case tests for error handling
- Run tests after every implementation step
- Never merge with failing tests
- Test names describe behavior, not implementation:
  GOOD: "returns 404 when user not found"
  BAD:  "test getUserById"
- Tests must be deterministic — no flaky tests
- Mock external services, don't call them in tests
