---
name: zappa-qaas-test-planner
description: Plan QaaS Runner, Mocker, hook, and configuration-as-code tests from docs-only evidence, including airgapped self-questioning, dependency gates, YAML/code artifact choices, and blockers.
---

# Zappa QaaS Test Planner

Create implementation-ready QaaS test plans from public QaaS docs and user-provided contracts.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when planning intent is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.
- For weak or airgapped planning, create or cite `weak_agent_packet` so the task contract, state, command IDs, and evidence paths are written to disk.

## Workflow

1. Read `D:\QaaS\_tools\zappa-harness\references\intent-clarification-protocol.md`, then ask focused questions or create `intent_assumptions` if questions are forbidden.
2. For airgapped planning, read `D:\QaaS\_tools\zappa-harness\references\weak-agent-task-packet.md` and create `weak_agent_packet` with `scripts\new-weak-agent-task-packet.ps1`.
3. Use `zappa-qaas-docs-map` or `D:\QaaS\_tools\zappa-harness\references\qaas-docs-index.md` to collect public evidence.
4. Classify test shape:
   - Runner YAML for documented actions and assertions.
   - Runner C# configuration-as-code for generated variants or code-owned values.
   - Mocker YAML for declarative dependency simulation.
   - Mocker C# configuration-as-code for dynamic stubs or reusable processors.
   - Custom hook only after documented built-ins are rejected.
5. Build a matrix covering happy path, validation failure, malformed data, dependency outage, retry/recovery, ordering/concurrency, cleanup, and observability.
6. Define dependency gates before live execution.
7. Output a plan that `zappa-qaas-test-author` can implement without guessing.

## Required Output

Include:

- `intent_questions` or `intent_assumptions`
- `docs_evidence`
- `weak_agent_packet`
- `case_matrix`
- `artifact_map`
- `dependency_gates`
- `assertions`
- `source_only_blockers`
- `validation_sequence`
- `airgapped_validation_prompt`

## Hard Rules

- Do not plan a test without at least one hard assertion per behavior.
- Do not mark a live run ready without concrete dependency gates.
- Do not use QaaS source code as public evidence.
- Do not choose a custom hook before naming the built-ins that are insufficient.
