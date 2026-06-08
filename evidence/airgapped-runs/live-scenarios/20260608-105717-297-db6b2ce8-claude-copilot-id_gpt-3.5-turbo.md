# weak-model-session transcript

Command: C:\Users\eldar\copilot-claude\claude.cmd id:gpt-3.5-turbo -p You are validating a Codex/GitHub Copilot/Gemini-compatible SKILL.md workflow under a weaker model.

Constraints:
- Do not edit files.
- Do not run destructive commands.
- Use any explicitly requested skill if the harness exposes it.
- Prefer direct task output over explanation.
- Use modest reasoning; do not compensate with exhaustive analysis.
- If the skill is unavailable, say SKILL_NOT_FOUND and list what skills you can see.

Injected Codex skills:
Follow these SKILL.md instructions exactly when the task names or implies the skill.
If the task conflicts with the skill, say so briefly and continue with the closest safe interpretation.

## Skill: zappa-qaas-hook-config
Path: C:\Users\eldar\.codex\skills\zappa-dont-cry\zappa-qaas-hook-config\SKILL.md
```markdown
---
name: zappa-qaas-hook-config
description: Author or review QaaS custom hooks, generators, assertions, probes, processors, and configuration-as-code from docs-only evidence, rejecting custom code when documented built-ins are sufficient.
---

# Zappa QaaS Hook Config

Use this for custom hooks and C# configuration-as-code.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when hook/config intent is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.

## Workflow

1. Use `zappa-qaas-docs-map` to identify built-in assertions, generators, probes, processors, and configuration options.
2. State why each relevant built-in is insufficient before writing custom code.
3. Identify hook family: assertion, generator, probe, or transaction processor.
4. Require public docs/schema evidence for configuration shape and discovery behavior.
5. Write deterministic hook/config code with typed configuration, clear failures, cancellation/timeouts when applicable, and no ambient machine dependencies.
6. Add a minimal Runner or Mocker artifact proving discovery and execution.
7. Validate build first, then template, then live run if dependency gates are ready.

## Required Output

- `builtins_considered`
- `custom_reason`
- `docs_evidence`
- `hook_family`
- `configuration_contract`
- `files_to_create`
- `proving_artifact`
- `validation_sequence`
- `source_only_blockers`

## Hard Rules

- Do not invent base class methods.
- Do not use broad catches, `null!`, `.Result`, `.Wait()`, or hidden static state.
- Do not create custom hooks for common built-in assertions, probes, generators, or processors.
```

Task:
Use zappa-qaas-hook-config to decide whether a custom QaaS assertion hook is justified. List builtins_considered, docs_evidence, hook_family, and validation_sequence.
ExitCode: 1
ScenarioId: zappa-qaas-hook-config-builtins
ScenarioKind: scenario
PromptHashSha256: 440ba1eaff59416cafe86cbc2b3ac7ac7ee18d1bea8902c4a7bf053138dae172
Harness: claude-copilot
Profile: airgapped
Model: id:gpt-3.5-turbo
DryRun: False

## stdout
API Error: 402 {"error":{"message":"You've reached your additional usage limit for your plan. Go to https://github.com/settings/copilot/features for more details.","code":"additional_spend_limit_reached"}}


## stderr
