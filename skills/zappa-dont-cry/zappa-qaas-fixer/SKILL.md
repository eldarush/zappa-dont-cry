---
name: zappa-qaas-fixer
description: Fix failing or incomplete QaaS YAML, Mocker YAML, C# configuration-as-code, hooks, generated manifests, and validation runs using docs-only evidence, without weakening assertions or hiding failures.
---

# Zappa QaaS Fixer

Use this when QaaS artifacts fail static validation, template/build checks, live execution, or review.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when the fix goal is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.
- In airgapped fixing, create or cite `weak_agent_packet` and keep packet state/evidence paths aligned with changed files and reruns.

## Workflow

1. Collect the failing command, exit code, transcript, artifact paths, manifest, and any `weak_agent_packet` state.
2. Classify the failure as intent, docs evidence, YAML shape, C# build, hook contract, dependency gate, assertion mismatch, cleanup, or environment.
3. Use `zappa-qaas-docs-map` and `D:\QaaS\_tools\zappa-harness\references\qaas-docs-index.md` for public QaaS evidence before changing behavior.
4. Patch the smallest artifact that addresses the root cause.
5. Keep assertions strong. Do not remove cases, skip tests, broaden catches, or replace precise assertions with smoke checks.
6. Rerun the narrowest validator first, then broader harness checks.
7. If a dependency is unavailable, record a blocker instead of simulating success.

## Required Output

- `failure_classification`
- `weak_agent_packet`
- `root_cause`
- `docs_evidence`
- `files_changed`
- `commands_run`
- `remaining_blockers`
- `airgapped_validation_prompt`

## Hard Rules

- Do not use QaaS source code unless the user explicitly provided it.
- Do not weaken assertions.
- Do not use `.Result`, `.Wait()`, `null!`, broad catches, or hidden static state in C# fixes.
- Do not mark a fix complete until the relevant validator passed or the blocker is explicit.
