---
name: zappa-qaas-top-repos
description: Build a dynamic QaaS test-planning campaign for the current top GitHub repositories, fetching repo metadata, classifying likely test surfaces, and producing docs-only QaaS test plans and blockers.
---

# Zappa QaaS Top Repos

Use this to plan QaaS tests for the current top GitHub repositories.

## Weak-Model Guardrails

- Start with `intent_questions` or `intent_assumptions` when top-repo test intent is ambiguous.
- Use public QaaS docs/schema evidence only unless the user explicitly provides source code.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Use `D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1` for deterministic validation where applicable.
- Use `D:\QaaS\_tools\weak-model-session.ps1 -Airgapped` for weak-model checks and label dry runs as prompt assembly only.

## Workflow

1. Bootstrap the work area:
   `D:\QaaS\_tools\zappa-harness\scripts\bootstrap-zappa-env.ps1`
2. Fetch current repositories:
   `D:\QaaS\_tools\zappa-harness\scripts\fetch-top-github-repos.ps1 -Count 250`
3. Generate the first campaign plan:
   `D:\QaaS\_tools\zappa-harness\scripts\generate-top-repos-campaign.ps1`
4. Harvest public repository contracts in batches without cloning or executing repos:
   `D:\QaaS\_tools\zappa-harness\scripts\harvest-top-repo-contracts.ps1 -Offset 0 -Count 10`
5. Generate blocked top-repo QaaS YAML/code skeletons from harvested contracts:
   `D:\QaaS\_tools\zappa-harness\scripts\generate-top-repo-artifacts.ps1`
6. Validate generated artifact structure:
   `D:\QaaS\_tools\zappa-harness\scripts\validate-generated-artifacts.ps1 -Root D:\QaaS\_tmp\zappa-dont-cry\generated-tests\top-repos -IndexFileName top-repo-artifact-index.json`
7. Classify each repository by language, runtime, service boundary, likely protocols, and dependency surfaces from public metadata and repository-visible docs.
8. For each repository, create a docs-only QaaS planning record:
   - `repo`
   - `rank`
   - `language`
   - `candidate_qaas_surfaces`
   - `required_public_docs`
   - `test_plan_status`
   - `blockers`
9. Promote QaaS YAML/code from blocked skeleton to executable only when repository-visible contracts and QaaS docs are sufficient.
10. Use airgapped validation on representative generated plans before scaling.

## Required Output

- top-repo manifest path
- campaign plan path
- repository classification summary
- generated artifact count
- blocked repository count and reasons
- airgapped validation transcript paths

## Hard Rules

- Do not claim all 250 repositories are fully tested until every repo has executable artifacts and validation evidence.
- Do not infer private runtime dependencies from popularity alone.
- Do not clone or execute arbitrary repositories without an explicit safety plan.
