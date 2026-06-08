---
name: zappa-qaas-docs-author
description: Author and update QaaS test documentation, manifests, runbooks, troubleshooting notes, docs evidence maps, and generated coverage reports from public QaaS docs and validation evidence.
---

# Zappa QaaS Docs Author

Use this for documenting QaaS tests, hooks, configuration, debugging results, and validation evidence.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when documentation intent is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.

## Workflow

1. Start from actual artifacts, manifests, command output, and docs evidence.
2. Separate public QaaS facts from repository-specific assumptions.
3. Document intent questions or `intent_assumptions`.
4. Record exact file paths for QaaS docs/schema evidence.
5. Explain validation status as passed, blocked, failed, or not run.
6. Keep generated docs operational: how to run, what proves success, and what blocks execution.
7. If docs and behavior disagree, mark the behavior `source_only_blocked` unless the user explicitly provided source as evidence.

## Required Output

- `summary`
- `docs_evidence`
- `artifacts_documented`
- `commands`
- `validation_status`
- `known_blockers`
- `next_verification`

## Hard Rules

- Do not write marketing copy.
- Do not claim a test is executable without validation evidence.
- Do not turn blockers into caveats; keep them visible.
