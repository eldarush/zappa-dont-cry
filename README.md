# zappa-dont-cry QaaS Skill Pack

This repository packages the current `zappa-dont-cry` QaaS skill pack, deterministic harness, generated QaaS artifacts, public evidence snapshots, and weak-model validation records.

Current state: published current-state artifact, not objective-complete. The deterministic harness passes (`64/64`), but promotion remains fail-closed: all selected candidates still lack eligible live weak-model evidence, 3 are selected-scope blocked, and 2 still have deterministic/QaaS-template evidence gaps.

Local source folder used for this package:

```text
D:\QaaS\_deliverables\zappa-dont-cry-20260608-1607
```

Public repository:

```text
https://github.com/eldarush/zappa-dont-cry
```

## What Is Included

- `skills/zappa-dont-cry/` - the QaaS skill namespace. Each child folder with `SKILL.md` is a distinct Codex skill.
- `skills/weak-model-validator/` - the Codex helper skill for airgapped and MiniMax M2.5 proxy validation.
- `harness/` - deterministic validation, regression checks, candidate generators, and QaaS evidence validators.
- `generated-tests/` - generated QaaS YAML, support code, manifests, custom assertion packets, and selected top-repo candidates.
- `coverage/` - promotion indexes, selected-candidate readiness, top-repo triage, and docs/schema coverage records.
- `blockers/` - fail-closed completion and weak-model blocker records.
- `evidence/top-repos/` - harvested public repo contracts and selected-contract evidence.
- `evidence/airgapped-runs/` - prior weak-model and adversarial scenario evidence.
- `evidence/weak-model-validation/` - current weak-model launcher transcripts and quota-blocked summaries.
- `evidence/weak-agent-packets/` - generated task packets that give weak agents explicit state, command IDs, evidence paths, and stop conditions.
- `reports/` - latest full harness report, historical timestamped reports, objective-readiness snapshots, package verification note, Spring Boot lifecycle/JAR summary, and Spring Boot weak-model quota-blocked summary.
- `tools/weak-model-session.ps1` - hosted weak-model launcher.
- `weak-model-policy.json` and `tools/weak-model-policy.json` - active model routing policy.
- `status-overview.html` - one-page human status snapshot.

`bin`, `obj`, cache, and transient log outputs are intentionally excluded from the published git history.

## Current Validation

Latest full deterministic harness run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite all
```

Result from `reports/report.json` (same content as `reports/full-harness-report-20260608-190335-164.json`):

- Full harness: `64/64` passed.
- Overall status: `passed`.
- Generated manifests: `772`.
- Policy-executable manifests: `0`.
- Promotable candidates: `0`.
- Selected top-repo candidates: `8`.
- Deterministic-ready selected candidates: `6`.
- Selected candidates still missing live airgapped weak evidence: `8`.
- Spring Boot lifecycle/JAR validation: `passed` with Spring Boot `4.0.6`, Java `25+`, HTTP `200`, exact body `Hello World!`, and cleanup evidence.
- Weak-agent task packet suite: `passed`.

Completion is still blocked by `blockers/objective-completion-readiness.json`.

## Selected Candidate State

Deterministic-ready, blocked only by live weak-model evidence:

- `fastapi/fastapi`
- `gin-gonic/gin`
- `typicode/json-server`
- `pallets/flask`
- `expressjs/express`

Deterministic-ready, blocked by live weak-model evidence plus selected-scope coverage:

- `denoland/deno`

Deterministic-evidence-blocked:

- `spring-projects/spring-boot` - docs-only candidate for `GET /`, `8080`, and body `Hello World!`; dependency version, JAR build, Java process lifecycle, response contract, and cleanup are now proven, but it remains blocked until the exact text assertion hook is schema/template/live validated through QaaS, selected-scope coverage is broadened, and weak-model evidence passes.
- `unclecode/crawl4ai` - remains blocked by Docker/lifecycle and custom status-below-400 validation gaps, plus weak-model evidence.

## Weak-Model Policy

When the user says `airgapped testing`, `airgapped models`, `dumb-model testing`, or `test this with weaker models`, Codex should use the `weak-model-validator` skill and call:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none -PolicyPath .\weak-model-policy.json -OutDir .\evidence\weak-model-validation -Prompt "Validate the current QaaS artifact from public docs only. Preserve blockers unless live weak-model evidence passes."
```

Preferred hosted weak routes, in order:

- `id:gpt-3.5-turbo`
- `id:gpt-3.5-turbo-0613`
- `gpt-4o-mini`
- `gpt-4o-mini-2024-07-18`

Latest live attempt:

- File: `reports/weak-model-spring-boot-quota-blocked-20260608-173406-860.md`
- Harness: `claude-copilot`
- Profile: `airgapped`
- Result: all four preferred weak routes failed with Copilot API `402 additional_spend_limit_reached`.

This is an operational blocker, not a pass. Dry runs and Codex-native fallbacks do not count as MiniMax M2.5 proxy evidence. Codex-native `-Harness codex -Profile airgapped` is only a smoke test for session mechanics because the available Codex models are too strong for this policy.

## Weak-Agent Task Packets

For weak or airgapped QaaS sessions, create a packet before asking the weaker model to plan, edit, debug, or judge completion:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\harness\scripts\new-weak-agent-task-packet.ps1 -Goal "Plan a docs-only QaaS Runner test" -SkillName zappa-qaas-test-planner -QaaSMode test-planning
```

Each packet contains `task.md`, `plan.md`, `state.json`, `commands.json`, `evidence\summary.md`, `run-log.jsonl`, and `final-report.md`. The packet forces the weaker model to use a written task contract, command IDs, evidence paths, stop conditions, and `weak_validation_passed: false` until a live eligible weak-model transcript passes.

Validate packet support with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite weak-agent-packet
```

## Install The Skills

From the cloned repository root:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.codex\skills" | Out-Null
Copy-Item -Recurse -Force .\skills\zappa-dont-cry "$env:USERPROFILE\.codex\skills\zappa-dont-cry"
Copy-Item -Recurse -Force .\skills\weak-model-validator "$env:USERPROFILE\.codex\skills\weak-model-validator"
```

Then start a new Codex session so the skill list refreshes.

Use `zappa-qaas-orchestrator` as the entrypoint. The recommended sequence for QaaS work is:

1. `zappa-qaas-orchestrator`
2. `zappa-qaas-docs-map`
3. `zappa-qaas-test-planner`
4. `zappa-qaas-test-author` or `zappa-qaas-hook-config`
5. `zappa-qaas-fixer` or `zappa-qaas-debugger`
6. `zappa-qaas-weak-model-gate`

For weak-model checks, use `weak-model-validator` directly or let `zappa-qaas-weak-model-gate` call the launcher.

## Run The Harness

The current harness scripts are built for the original Windows workspace layout:

```text
D:\QaaS
C:\Users\eldar\.codex\skills
```

Replay the exact validation from that workspace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite all
```

Focused checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-live
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite weak-agent-packet
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite weak-suite-runner
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite promotion-index
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite completion-readiness
```

The packaged `harness/` folder is included for review and portability work, but some scripts still reference the original absolute workspace paths. Keep that limitation visible rather than treating the package as a generic installer.

## Guardrails

- Use public QaaS docs and schemas as the contract unless source code is explicitly provided.
- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, lifecycle behavior, or repository behavior.
- Do not promote an artifact from structure alone.
- Do not accept dry-run weak-model evidence.
- Do not accept Codex fallback output as preferred weak-model evidence.
- Preserve selected-scope blockers until exact public contracts exist.
- If preferred weak routes are quota-blocked, record the blocker and keep completion blocked.

## Publication Status

This repository is safe to publish as a current-state artifact. It is not a claim that the original recursive top-250 objective is complete. Keep completion fail-closed until live, non-dry-run preferred weak-model evidence passes and the remaining selected-scope/deterministic blockers are cleared.
