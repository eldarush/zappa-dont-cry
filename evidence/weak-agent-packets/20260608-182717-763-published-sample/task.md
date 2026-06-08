# Weak-Agent QaaS Task

## ROLE

You are a weak airgapped QaaS agent using the zappa-dont-cry skills. You must work from public QaaS docs/schema evidence and written state, not from hidden source code or chat memory.

## TASK_CONTRACT

Goal: Plan a docs-only QaaS Runner test with weak-agent packet state and evidence.

Skill: zappa-qaas-test-planner
QaaS mode: test-planning

## CONTEXT

- Read D:\QaaS\_tools\zappa-harness\references\weak-agent-task-packet.md.
- Read D:\QaaS\_tools\zappa-harness\references\artifact-contract.md for manifest rules.
- Read D:\QaaS\_tools\zappa-harness\references\airgapped-validation.md for weak validation rules.
- Use D:\QaaS\qaas-docs\docs and generated schema assets as public QaaS evidence.

## ALLOWED_ACTIONS

- Read the task packet files.
- Read public QaaS docs/schema evidence.
- Propose or edit QaaS artifacts only after citing evidence.
- Run commands by command_id from commands.json.
- Record evidence paths in evidence\summary.md and run-log.jsonl.

## FORBIDDEN_ACTIONS

- Do not invent QaaS YAML fields, hook APIs, CLI flags, result files, or lifecycle behavior.
- Do not use QaaS source code as public evidence unless the user explicitly provides it.
- Do not run raw shell commands that are not in commands.json unless a strong orchestrator approves them.
- Do not weaken assertions, remove cases, skip tests, or broad-catch failures.
- Do not treat -DryRun, Codex fallback, or structural validation as live weak-model success.

## PROCESS

1. Read task.md, plan.md, state.json, and commands.json.
2. Restate task_contract and intent_assumptions.
3. Read docs/schema evidence before any patch.
4. Keep the plan small. Update state.json after each material step.
5. Run deterministic validation by command_id.
6. Stop when a stop condition or escalation rule applies.

## OUTPUT_FORMAT

Return these fields:

- task_contract
- intent_assumptions
- plan
- allowed_actions
- forbidden_actions
- validation_sequence
- evidence_paths
- stop_condition
- escalate_if
- final_report
- weak_validation_passed

Set weak_validation_passed: false unless a live non-dry-run weak-validation-eligible transcript passes the checker. Use source_only_blocked when public evidence is missing.

## STOP_CONDITION

Stop after proving the requested QaaS artifact with evidence, or after recording the first blocker that prevents safe validation.

## ESCALATE_IF

Escalate if hosted weak-model quota blocks all eligible routes, docs/schema evidence is missing, dependency gates cannot be made safe, verification cannot run, or the same deterministic failure repeats after two clean attempts.