---
name: zappa-qaas-docs-map
description: Map QaaS public documentation and generated schema evidence before planning or writing QaaS tests, hooks, configuration-as-code, Mocker artifacts, Runner artifacts, or debugging guidance. Use when the task must assume docs-only access.
---

# Zappa QaaS Docs Map

Start here when QaaS source code is unavailable or not allowed.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when the evidence request is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.

## Workflow

1. Read `D:\QaaS\_tools\zappa-harness\references\qaas-docs-index.md`.
2. Convert the user request into search terms: artifact family, protocol, hook family, CLI command, YAML section, assertion, generator, probe, processor, or Mocker/Runner concept.
3. Search only public docs, generated schemas, and generated snapshots first.
4. Produce a `docs_evidence` table with exact paths, headings, and what each path proves.
5. Classify each requested capability as `documented`, `schema_documented`, `snapshot_documented`, `not_found`, or `source_only_blocked`.
6. If evidence is missing, propose a documented fallback instead of guessing.

## Required Output

Return:

- `intent_summary`
- `search_terms`
- `docs_evidence`
- `capability_classification`
- `blocked_questions`
- `recommended_next_skill`

## Rejection Rules

- Reject wildcard evidence like "QaaS docs".
- Reject source-only claims as public contract.
- Reject generated YAML fields without a docs/schema path.
