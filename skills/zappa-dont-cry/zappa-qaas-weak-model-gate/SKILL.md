---
name: zappa-qaas-weak-model-gate
description: Run and adjudicate weak-model airgapped validation gates, pass/fail evidence, blockers, strong-model review checks, generated artifact validation, and completion decisions for QaaS work.
---

# Zappa QaaS Weak Model Gate

Use this before claiming QaaS work is done, correct, complete, or ready.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when completion criteria are ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.
- Require a `weak_agent_packet` for airgapped task execution so weak models have `task.md`, `state.json`, `commands.json`, and evidence paths.

## Workflow

1. Derive concrete requirements from the user request, manifests, and skill contracts.
2. Create or inspect `weak_agent_packet` via `D:\QaaS\_tools\zappa-harness\references\weak-agent-task-packet.md` before judging weak-model output.
3. Map each requirement to authoritative evidence: files, validators, build output, transcripts, or live QaaS results.
4. Run deterministic checks before subjective review:
   - `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1`
   - `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped`
   - generated artifact validators from the harness
5. If live weak-model calls are quota-blocked, run dry validation and record the blocker. Do not treat dry runs as behavioral proof.
6. Classify each requirement as proven, incomplete, blocked, contradicted, or not checked.
7. Reject completion if any required evidence is missing or weak.
8. Use the adversarial weak-model suite for hostile prompts such as fake live validation, source-only assumptions, invented QaaS APIs, assertion weakening, and output-contract drift.
9. Record dry-run adversarial weak validation with `adversarial_scenario_count`, but do not accept adversarial dry-run validation as live model behavior.

## Required Output

- `requirements`
- `weak_agent_packet`
- `evidence`
- `commands_run`
- `pass_fail_matrix`
- `airgapped_result`
- `weak_validation_passed`
- `completion_decision`
- `remaining_work`

## Hard Rules

- Do not use a narrow sample to prove a broad requirement.
- Do not accept dry-run weak validation as live model behavior.
- Do not mark completion when artifacts are only structurally valid but not executable.
