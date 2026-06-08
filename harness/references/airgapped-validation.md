# Airgapped Validation

Use this when validating whether weaker agents can follow a skill.

Preferred command for promotion/completion evidence:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -Airgapped -All -ReasoningEffort none -SkillPath "<path-to-SKILL.md>" -RejectPattern "SKILL_NOT_FOUND"
```

Quick single-model smoke command:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -Airgapped -SkillPath "<path-to-SKILL.md>" -RejectPattern "SKILL_NOT_FOUND"
```

For model-only promotion/completion smoke tests:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "Say exactly WEAK_VALIDATOR_READY." -Airgapped -All -ReasoningEffort none -ExpectPattern "^WEAK_VALIDATOR_READY$"
```

Interpretation:

- Passing weak output must use the injected skill, follow the requested shape, and avoid unsupported QaaS claims.
- Failing weak output should drive a skill rewrite: shorter instructions, stricter output schema, fewer branch choices, and stronger docs evidence requirements.
- If Copilot quota blocks live weak validation, record the quota blocker per preferred model. Run `-DryRun` only for prompt assembly diagnostics. Do not claim weak validation passed.

Strong review after weak pass:

1. Read the weak transcript.
2. Compare every QaaS claim to docs/schema evidence.
3. Patch the skill or references to remove ambiguity.
4. Rerun weak validation.
