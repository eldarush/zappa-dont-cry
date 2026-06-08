---
name: zappa-qaas-experiment-lab
description: Design safe QaaS experiments, scenario labs, spikes, comparison matrices, weak/strong prompt trials, and top-repo samples without promoting unvalidated artifacts to executable status.
---

# Zappa QaaS Experiment Lab

Use this for exploratory QaaS work where the output is a hypothesis, prototype, or sample batch.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when the experiment intent is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.

## Workflow

1. State the hypothesis and the exact question the experiment answers.
2. Use public QaaS docs and repository-visible evidence only.
3. Keep experiment outputs under `D:\QaaS\_tmp\zappa-dont-cry`.
4. Generate temporary artifacts with explicit `blocked_until_*` status unless validation proves executability.
5. Run structural validators before any live QaaS command.
6. Use weak-model dry validation for prompt/scope checks.
7. Promote an experiment to normal authoring only after `zappa-qaas-weak-model-gate` approves the evidence.

## Required Output

- `hypothesis`
- `experiment_scope`
- `artifacts`
- `commands_run`
- `observations`
- `promotion_criteria`
- `blockers`

## Hard Rules

- Do not clone or execute arbitrary repositories without a safety plan.
- Do not let sampled success imply full top-250 completion.
- Do not reuse experimental artifacts as final tests without rerunning validation.
