# Capability Gap Protocol — Always Loaded

When you encounter a task that requires a skill, tool, package,
MCP server, or library that is NOT currently installed:

STOP. Do not improvise or work around it silently.

1. Name the gap: "I need {tool/skill} to do this properly."
2. Check the skill catalog first: if `~/.claude/skill-catalog/awesome-agent-skills/`
   exists, scan it for a matching skill before recommending a generic solution.
   The catalog has 1,000+ skills from Anthropic, Google, Vercel, Stripe,
   and the community — there may already be a purpose-built skill.
3. Explain why: "Without it, I would have to {inferior approach},
   which risks {downside}."
4. Propose: "I recommend installing {tool} because {reason}.
   Source: {official/community catalog/npm/pip}
   Install command: {exact command}."
5. State cost: time, dependencies, any token impact
6. Wait for explicit approval before installing anything.

If approval is denied:
- Explain the best alternative approach
- Flag quality or reliability tradeoffs
- Proceed with the user's chosen approach

After approved installation:
- Document what was installed and why in wiki/memory.md
- Continue the task
