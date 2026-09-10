# Source selection

Research snapshot: 10 September 2026.
Scope: repository documentation and selected source inspection, not installed integration testing. Recommendations must be validated during implementation. No upstream code or skills are vendored by this PR.

1. [Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk-python): proposed managed execution adapter. Inspected README and tool configuration types. Explicit tool restrictions are required: allowed_tools alone is not a tool removal mechanism. Confirm applicable terms, authentication, and billing.
2. [Claude Code plugins](https://code.claude.com/docs/en/plugins): supported packaging for skills, agents, hooks, and MCP connections. The proposed team commands still require implementation.
3. [Addy Osmani Agent Skills](https://github.com/addyosmani/agent-skills): primary procedural source. Select planning, incremental implementation, debugging, review, and adoption. Adapt clarification rules to the user's business decision boundary. Inspected the adoption guide as well as README.
4. [Superpowers](https://github.com/obra/superpowers): borrow selected delegation, separate review, and verification procedures. Inspected verification-before-completion. Avoid stacking its entire lifecycle with Addy's. Use evidence tied to current code rather than mechanically rerunning every command on each message.
5. [Hermes Agent](https://github.com/NousResearch/hermes-agent): reference for memory and skill evolution. The project is hermes-agent, not Hermes-Function-Calling. Do not import the full runtime merely to add learning.
6. [Playwright](https://github.com/microsoft/playwright): browser test runner and traces alongside existing project tests. Browser evidence alone is insufficient for backend and security requirements.
7. [Obsidian Skills](https://github.com/kepano/obsidian-skills): Markdown, Bases, Canvas, and vault interaction. Define repeatable wrap up and identity rules ourselves.
8. [Serena](https://github.com/oraios/serena): semantic code navigation and references. Assess each project's language support. Not a complete persistent code graph exporter.
9. [GitHub CLI](https://github.com/cli/cli): PR and checks adapter. Enforce merge and deployment policy in the controller and applicable repository controls.
10. [Ponytail](https://github.com/dietrichgebert/ponytail): adopt restrained implementation and reuse principles. Do not optimise for minimum line count or treat repository benchmark claims as general guarantees.
11. [Karpathy inspired guidelines](https://github.com/multica-ai/andrej-karpathy-skills): narrow changes and verifiable goals. Community interpretation, not Karpathy's own framework. Reduce routine technical questions.
12. [Claude Cookbooks](https://github.com/anthropics/claude-cookbooks): examples for tools, evaluation, and cost control, not a project controller.
13. [Anthropic Skills](https://github.com/anthropics/skills): select relevant specialist skills. Repository includes both open source and source available content; inspect individual licences before copying.
14. [LangGraph](https://github.com/langchain-ai/langgraph): alternative if durable orchestration needs exceed the narrow controller. Avoid adding a second orchestration engine without a concrete need.
15. [GitNexus](https://github.com/abhigyanpatwari/GitNexus): close functional match for code graphs, excluded from the default commercial shortlist because the inspected README specifies PolyForm Noncommercial.
16. [Tree sitter](https://github.com/tree-sitter/tree-sitter): possible parsing foundation for a later graph adapter. Relationship extraction and persistence still need implementation.

## Dependency handling

Pin adopted revisions, preserve notices, record local changes, and evaluate updates before promotion. Repository popularity and recent commits are useful signals, not assurance of quality. Keep adapters replaceable and project records exportable if a dependency is abandoned.

## Unresolved implementation facts

Confirm SDK authentication and billing, native Windows process management, plugin tool transport, evidence isolation, selected graph export approach, Obsidian vault access, and each target repository's merge and deployment behaviour. Resolve engineering choices autonomously. Escalate only decisions affecting the user's agreed scope, cost, or access.
