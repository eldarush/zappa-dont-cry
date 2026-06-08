---
name: zappa-qaas-orchestrator
description: Coordinate the zappa-dont-cry QaaS skill pack. Use when the user asks for zappa-dont-cry, QaaS expertise from docs only, airgapped QaaS testing, recursive strong/weak model validation, broad QaaS test generation, or an end-to-end QaaS agent workflow.
---

# Zappa QaaS Orchestrator

Use this as the coordinator for the `zappa-dont-cry` namespace. The namespace folder is not itself a skill; each child folder with `SKILL.md` is a distinct skill.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when the user request is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.

## Core Rules

1. Treat `D:\QaaS\qaas-docs\docs` and generated schemas as the public QaaS contract.
2. Treat QaaS source code as unavailable unless the user explicitly gives it for a specific task.
3. Do not invent QaaS YAML fields, hook methods, CLI flags, or configuration APIs.
4. Ask focused intent questions when intent is ambiguous. If questions are forbidden, create `intent_assumptions` and answer them conservatively.
5. Prefer deterministic harness checks over prose-only validation.
6. For airgapped validation, call `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` and inspect the transcript. If quota blocks the weak path, run a dry run and record the blocker.
7. Strong-model output is not accepted until weak-model routing has exercised the prompt and a strong review has checked the output against docs evidence.
8. Run adversarial weak-model suite evidence when available. Treat dry-run adversarial weak validation as prompt assembly only, record `adversarial_scenario_count`, and do not accept adversarial dry-run validation as live model behavior.

## Route By Task

- Public docs/schema evidence: `zappa-qaas-docs-map`.
- Planning Runner, Mocker, hooks, and config tests: `zappa-qaas-test-planner`.
- Writing YAML, C# config, manifests, and support files: `zappa-qaas-test-author`.
- Custom hooks and configuration-as-code: `zappa-qaas-hook-config`.
- Debugging failures: `zappa-qaas-debugger`.
- Fixing generated or failing QaaS artifacts: `zappa-qaas-fixer`.
- Documentation authoring: `zappa-qaas-docs-author`.
- Experiments and scenario labs: `zappa-qaas-experiment-lab`.
- Weak-model and completion gates: `zappa-qaas-weak-model-gate`.
- Top GitHub repository campaigns: `zappa-qaas-top-repos`.

## Shared Harness

Use shared scripts and references from `D:\QaaS\_tools\zappa-harness`:

- `references\qaas-docs-index.md`
- `references\intent-clarification-protocol.md`
- `references\artifact-contract.md`
- `references\airgapped-validation.md`
- `references\recursive-development-loop.md`
- `Invoke-ZappaHarness.ps1`

## Required Output Shape

For QaaS work, produce:

- `intent_questions` or `intent_assumptions`
- `docs_evidence`
- `artifact_plan`
- `validation_sequence`
- `airgapped_result`
- `strong_review`
- `next_blocker`

## Hard Rules

- Do not claim completion from structural validation alone.
- Do not treat dry-run weak-model validation as live weak-model behavior.
- Do not promote blocked skeletons to executable QaaS tests without template/build/live evidence.
- Do not bypass the harness when deterministic checks are available.
