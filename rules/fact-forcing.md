# Fact-Forcing — Always Loaded

Before editing an unfamiliar file for the first time in a session,
investigate first. Do not edit based on assumptions.

Required before first edit to any file you haven't read this session:
1. Read the full file (or the relevant section if very large)
2. Identify what imports/calls this file — who depends on it?
3. Identify what this file imports/calls — what does it depend on?
4. If the file defines a public API, data schema, or type contract,
   understand the contract before changing it

This prevents:
- Breaking callers you didn't know existed
- Changing a type/schema that downstream code relies on
- Editing a file based on a guess about what it contains
- Cascading failures from one uninformed edit

If you are already familiar with the file from earlier in this session
(you read it, wrote it, or reviewed it), proceed without re-investigating.
