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
