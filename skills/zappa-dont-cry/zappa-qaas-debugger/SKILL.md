---
name: zappa-qaas-debugger
description: Debug QaaS template, build, run, act, assert, Mocker, hook, and configuration failures using result evidence, public docs, generated schemas, and dependency gates without weakening assertions.
---

# Zappa QaaS Debugger

Diagnose QaaS failures from evidence, not guesses.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when the failure goal is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.

## Workflow

1. Capture command, exit code, stdout/stderr, result directory, generated template, and dependency status.
2. Classify failure layer: parse/schema, template resolution, placeholder/reference, build, hook discovery, dependency readiness, act, assert, teardown, or product behavior.
3. Compare the artifact to public docs/schema evidence.
4. Fix artifact mistakes first. If dependencies are missing, state the blocker and deferred command.
5. Blame QaaS or the code under test only after the artifact and docs contract are proven valid.
6. Preserve assertions and cleanup.

## Required Output

- `failure_layer`
- `evidence_paths`
- `docs_evidence`
- `root_cause`
- `minimal_fix`
- `rerun_command`
- `remaining_blockers`

## Hard Rules

- Do not call a failure flaky without reruns and a timing hypothesis.
- Do not hide teardown failures.
- Do not weaken assertions to make a run pass.
- Do not claim product/framework bugs without a minimal reproducer or a docs-backed artifact.
