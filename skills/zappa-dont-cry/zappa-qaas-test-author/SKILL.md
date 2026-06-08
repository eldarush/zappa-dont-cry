---
name: zappa-qaas-test-author
description: Write QaaS YAML and C# configuration-as-code artifacts from a docs-only QaaS test plan, including manifests, variables, dependency gates, assertions, validation commands, and airgapped weak-model checks.
---

# Zappa QaaS Test Author

Turn a validated plan into concrete QaaS artifacts.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when authoring intent is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.
- For weak or airgapped authoring, create or cite `weak_agent_packet` and keep packet state/evidence paths current.

## Workflow

1. Read `D:\QaaS\_tools\zappa-harness\references\artifact-contract.md` and, for weak sessions, `D:\QaaS\_tools\zappa-harness\references\weak-agent-task-packet.md`.
2. Require a plan with docs evidence and case IDs. If missing, route to `zappa-qaas-test-planner`.
3. Author the smallest artifacts that prove the plan:
   - `test.qaas.yaml` for Runner flows.
   - `mocker.qaas.yaml` for dependency simulation.
   - C# configuration-as-code only when YAML cannot express the behavior.
   - Variables files for environment differences.
   - Hook projects only through `zappa-qaas-hook-config`.
4. Write `qaas-artifact-manifest.json` beside generated artifacts.
5. Validate in this order: static shape, template, build, then live run only if gates are ready.
6. If validation fails, fix the artifact. Do not weaken assertions to pass.

## Output Contract

Return:

- file paths
- `weak_agent_packet`
- generated YAML/code snippets or patches
- manifest content
- `validation_sequence`
- `source_only_blockers`
- validation commands
- `commands_run` with exit status
- dependency blockers
- airgapped validation transcript path
- promotion state and remaining blockers

## Hard Rules

- Prefer YAML for declarative tests.
- Keep environment-specific values in variables.
- Include cleanup and negative coverage.
- Do not claim "100 percent correct" without fresh validation evidence.
