# Config Protection — Always Loaded

NEVER modify linter, formatter, or build config files to make checks pass.
Fix the actual code instead.

Protected files (do not weaken or disable rules in these):
- ESLint: .eslintrc*, eslint.config.*
- Prettier: .prettierrc*, prettier.config.*
- Biome: biome.json, biome.jsonc
- Ruff: .ruff.toml, ruff section in pyproject.toml
- TypeScript: tsconfig.json, tsconfig.*.json
- Stylelint: .stylelintrc*
- EditorConfig: .editorconfig

If a linter or formatter flags an error:
1. Fix the code to satisfy the rule
2. If the rule is genuinely wrong for this project, explain why
   and ask the user before changing the config
3. NEVER silently disable, downgrade, or add ignores to make CI pass

Exception: adding NEW rules or tightening existing ones is fine without asking.
