# Weak-Agent Task Packet

Use this packet when a weak or airgapped agent must use QaaS skills without relying on chat memory. It turns a broad request into a small written contract, a bounded plan, a command registry, state, and evidence paths.

## Required Files

Each packet directory must contain:

- `task.md`: role, task contract, public QaaS context, allowed actions, forbidden actions, process, output format, stop condition, and escalation rules.
- `plan.md`: a small ordered plan or DSL. `READ` must happen before `PATCH`; `RUN_TESTS` must use a `command_id` from `commands.json`; `REPORT` must cite evidence paths; `END` must state remaining blockers.
- `state.json`: explicit working state for context reset.
- `commands.json`: narrow deterministic commands by ID. Weak agents should pick a command ID, not invent raw shell.
- `evidence\summary.md`: short evidence ledger.
- `run-log.jsonl`: append-only event log.
- `final-report.md`: report scaffold with changed files, tests, risks, and blockers.

## Required Output Fields

Weak-agent responses should include:

- `task_contract`
- `intent_assumptions`
- `plan`
- `allowed_actions`
- `forbidden_actions`
- `validation_sequence`
- `evidence_paths`
- `stop_condition`
- `escalate_if`
- `final_report`
- `weak_validation_passed`

`weak_validation_passed` must stay `false` unless a live, non-dry-run, weak-validation-eligible transcript passes the configured checker. Codex fallback and `-DryRun` output are smoke or prompt assembly only.

## QaaS Command IDs

The standard packet command registry should include:

- `harness_smoke`: run the deterministic Zappa smoke suite.
- `harness_weak_scenarios`: dry-run cooperative weak-model scenario prompt assembly.
- `harness_weak_adversarial`: dry-run adversarial weak-model scenario prompt assembly.
- `harness_skill_output_contracts`: verify skill output contracts.
- `airgapped_all`: attempt all preferred hosted weak models through `weak-model-session.ps1 -Airgapped -All -ReasoningEffort none`.
- `airgapped_dry_run`: assemble weak-model prompts only; never counts as behavioral proof.
- `selected_candidates`: validate selected top-repo candidate packets.
- `completion_readiness`: write objective completion blockers.

## Stop Or Escalate

Stop and report a blocker when:

- Hosted weak-model quota blocks all eligible live routes.
- Required public QaaS docs or schema evidence is missing.
- Dependency gates are missing, unavailable, or not safely isolated.
- The same deterministic failure repeats after two clean attempts.
- Verification cannot run.
- A path, process, Docker container, or transcript is outside the managed work root.

## False Success Guards

- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Do not treat dry-run weak validation as live model behavior.
- Do not mark completion from structural validation alone.
- Do not weaken assertions, remove cases, skip tests, or broaden catches to make a run pass.
- Do not use QaaS source code as public evidence unless the user explicitly provided it for the task.
- Use `source_only_blocked` when public docs/schema evidence is insufficient.
- Cite evidence paths rather than pasting long logs.
