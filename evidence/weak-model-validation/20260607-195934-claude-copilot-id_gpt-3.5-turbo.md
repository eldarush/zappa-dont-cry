# weak-model-session transcript

Command: DRY_RUN claude-copilot id:gpt-3.5-turbo
CommandPreview: claude id:gpt-3.5-turbo -p You are validating a Codex/GitHub Copilot/Gemini-compatible SKILL.md workflow under a weaker model.

Constraints:
- Do not edit files.
- Do not run destructive commands.
- Use any explicitly requested skill if the harness exposes it.
- Prefer direct task output over explanation.
- Use modest reasoning; do not compensate with exhaustive analysis.
- If the skill is unavailable, say SKILL_NOT_FOUND and list what skills you can see.



Task:
Say exactly WEAK_VALIDATOR_READY.
ExitCode: 0

## prompt
You are validating a Codex/GitHub Copilot/Gemini-compatible SKILL.md workflow under a weaker model.

Constraints:
- Do not edit files.
- Do not run destructive commands.
- Use any explicitly requested skill if the harness exposes it.
- Prefer direct task output over explanation.
- Use modest reasoning; do not compensate with exhaustive analysis.
- If the skill is unavailable, say SKILL_NOT_FOUND and list what skills you can see.



Task:
Say exactly WEAK_VALIDATOR_READY.