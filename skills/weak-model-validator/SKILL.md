---
name: weak-model-validator
description: Launch hosted weak-model validation sessions for Codex skills and agents. Use when the user asks for airgapped testing, airgapped models, airgapped validation, dumb-model testing, weak-model testing, MiniMax M2.5 proxy testing, weak/OSS-like hosted models, or making sure a skill works outside the current smart Codex model.
---

# Weak Model Validator

Use Codex as the orchestrator. Do not run local models unless the user explicitly asks for local inference.

Default to the QaaS launcher:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -Skill "<skill-name>"
```

When the user says "airgapped testing", "airgapped models", or asks whether a skill works for dumb airgapped models, run:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -Airgapped -Skill "<skill-name>" -RejectPattern "SKILL_NOT_FOUND"
```

`-Airgapped` resolves to the weakest known hosted path: `-Harness claude-copilot -Profile airgapped`, currently `id:gpt-3.5-turbo`. If that is blocked by Copilot quota, use `-Harness copilot -Profile airgapped -All -ReasoningEffort none`. Use `-Harness codex -Profile airgapped` only as a fallback smoke test because Codex Spark is still too strong.

Add `-ExpectPattern` only when the expected output has a stable marker. For a model-only smoke test, use `-Prompt "Say exactly WEAK_VALIDATOR_READY." -ExpectPattern "^WEAK_VALIDATOR_READY$"`.

Inspect active model policy when model choice matters:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -ListProfiles
```

Use Codex-native isolation when the user explicitly wants Codex sessions:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -Harness codex -Skill "<skill-name>" -Profile single
```

For broader validation, run:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -Harness copilot -Skill "<skill-name>" -Profile minimax-proxy -All
```

For a harsher stress check, run:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -Airgapped -Skill "<skill-name>"
```

If the skill is not discoverable by name, pass the exact path:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "<task>" -SkillPath "C:\path\to\skill\SKILL.md" -Profile minimax-proxy
```

Use `-DryRun` first when changing the launcher or checking skill injection without spending hosted quota.

Use `-ExpectPattern` and `-RejectPattern` when the test has obvious pass/fail markers, for example:

```powershell
D:\QaaS\_tools\weak-model-session.ps1 -Prompt "Say exactly WEAK_VALIDATOR_READY." -Airgapped -ExpectPattern "^WEAK_VALIDATOR_READY$" -RejectPattern "SKILL_NOT_FOUND"
```

Read `D:\QaaS\_tools\WEAK_MODEL_VALIDATION.md` for model policy, scoring rules, known Copilot limits, and fallback guidance.

Validation priority:

1. Claude-over-Copilot with `id:gpt-3.5-turbo` for airgapped testing.
2. Copilot CLI with explicit flash/haiku hosted model IDs when quota is available.
3. Codex CLI only as a fallback smoke test.
4. Antigravity `agy` only as a last resort.

Codex-visible hosted models are currently GPT-5-family models. They are too strong for the preferred airgapped proxy; use them only to test Codex session mechanics when weaker hosted paths are unavailable.

For dotted bridge model IDs, use `id:<model>` rather than the raw model ID.

Treat Copilot additional-usage limits as an operational blocker for live validation, not as a script failure. Still inspect generated dry-run prompts and transcripts when quota blocks a live model call.
