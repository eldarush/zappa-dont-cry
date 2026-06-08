# zappa-dont-cry QaaS Skill Pack

This repository packages the current `zappa-dont-cry` QaaS skill pack, harness, generated artifacts, and validation records.

Current state: structurally validated, not complete. The harness passes, but policy promotion remains blocked until live preferred weak-model validation succeeds.

## Contents

- `skills/zappa-dont-cry/` - Codex skills for QaaS planning, docs mapping, test authoring, hooks, debugging, fixing, experiments, top-repo campaigns, and weak-model gates.
- `harness/` - deterministic validation scripts and regression tests.
- `generated-tests/` - generated QaaS artifacts and manifests, with `bin` and `obj` build outputs excluded.
- `coverage/` - campaign and promotion-readiness summaries.
- `blockers/` - current fail-closed completion and weak-model blocker records.
- `evidence/weak-model-validation/` - latest weak-model retry transcripts.
- `reports/full-harness-report-20260608-164833-201.json` - latest full harness report.
- `status-overview.html` - short human-readable status snapshot.
- `tools/weak-model-session.ps1` and `tools/weak-model-policy.json` - weak-model routing wrapper and policy.

## Latest Validation

Run completed on 2026-06-08:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite all
```

Result:

- Full harness: `61/61` passed.
- Harness regression tests: `195` checks passed.
- Policy-executable manifests: `0`.
- Deterministic QaaS-ready candidates: `6`.
- Weak-only deterministic candidates: `5`.
- Selected-scope deterministic candidates: `1`.

The completion record is `blockers/objective-completion-readiness.json`.

## Current Blockers

The work remains blocked by policy, not by structural harness failures:

- Preferred weak-model routes are quota-blocked: all four configured weak profiles returned Copilot API `402 additional_spend_limit_reached`.
- No manifest is promoted to `promotion_state: executable`.
- No promotion packet is executable.
- Crawl4AI remains deterministic-blocked because the current public `unclecode/crawl4ai:latest` image starts with `unable to find user appuser`; cleanup is verified and promotion remains blocked.
- Deno remains deterministic-ready but selected-scope blocked for broad runtime coverage.

This is intentional. The harness is designed to fail closed and should not turn dry runs, quota failures, or partial weak-model attempts into completion evidence.

## Weak-Model Policy

Preferred weak routes are configured in `tools/weak-model-policy.json`:

- `id:gpt-3.5-turbo`
- `id:gpt-3.5-turbo-0613`
- `gpt-4o-mini`
- `gpt-4o-mini-2024-07-18`

To retry weak validation from `D:\QaaS`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none -Prompt "Validate the Zappa QaaS artifacts from public docs only. Preserve all blockers unless live weak-model evidence passes."
```

Then classify the evidence:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\checks\Check-AirgappedLiveEvidence.ps1 -EvidenceRoot D:\QaaS\_tmp\weak-model-validation -BlockersDir D:\QaaS\_tmp\zappa-dont-cry\blockers -PolicyPath D:\QaaS\_tools\weak-model-policy.json
```

## Running The Harness

From the original `D:\QaaS` workspace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite all
```

Focused checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-live
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite promotion-index
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite completion-readiness
```

## Using The Skills

Install or update the skills by copying `skills/zappa-dont-cry` to:

```text
C:\Users\eldar\.codex\skills\zappa-dont-cry
```

Use `zappa-qaas-orchestrator` as the entrypoint. The folder `zappa-dont-cry` is only a namespace folder; each child folder with `SKILL.md` is a distinct skill.

Recommended skill order for a QaaS task:

1. `zappa-qaas-orchestrator`
2. `zappa-qaas-docs-map`
3. `zappa-qaas-test-planner`
4. `zappa-qaas-test-author` or `zappa-qaas-hook-config`
5. `zappa-qaas-fixer` or `zappa-qaas-debugger`
6. `zappa-qaas-weak-model-gate`

## Guardrails

- Use public QaaS docs and schemas as the contract unless source code is explicitly provided.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, or result files.
- Do not promote artifacts from structure alone.
- Do not accept dry-run weak-model evidence.
- Do not accept one preferred weak model as proof when policy requires all preferred routes.
- Preserve selected-scope blockers such as Crawl4AI body, `/crawl`, and Deno broad-runtime coverage until exact public contracts exist.

## Publication Status

This package is safe to publish as a current-state artifact, but it is not a claim of objective completion. The next real unblockers are live weak-model quota and an upstream Crawl4AI image/runtime state that can satisfy `/health`.
