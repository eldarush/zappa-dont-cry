param(
    [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry\weak-agent-packets",
    [string]$TaskId = "qaas-task",
    [Parameter(Mandatory = $true)]
    [string]$Goal,
    [string]$SkillName = "zappa-qaas-orchestrator",
    [ValidateSet("orchestrator", "test-planning", "test-authoring", "debugging", "fixing", "weak-gate", "top-repos", "experiment")]
    [string]$QaaSMode = "orchestrator",
    [int]$MaxSteps = 12,
    [int]$MaxToolCalls = 30,
    [int]$MaxWrites = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$allowedRoot = [System.IO.Path]::GetFullPath("D:\QaaS\_tmp\zappa-dont-cry\weak-agent-packets")
$resolvedRoot = [System.IO.Path]::GetFullPath($Root)
$allowedPrefix = $allowedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$resolvedRootPrefix = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($resolvedRoot -ne $allowedRoot -and -not $resolvedRootPrefix.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Packet root must stay under $allowedRoot"
}

if ($SkillName -notmatch '^[A-Za-z0-9_.:-]+$') {
    throw "SkillName may contain only letters, numbers, dot, underscore, colon, or hyphen."
}

$safeTaskId = ($TaskId -replace '[^A-Za-z0-9_.-]', '-').Trim("-")
if ([string]::IsNullOrWhiteSpace($safeTaskId)) {
    $safeTaskId = "qaas-task"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$packetDir = Join-Path $resolvedRoot "$timestamp-$safeTaskId"
$evidenceDir = Join-Path $packetDir "evidence"
[System.IO.Directory]::CreateDirectory($evidenceDir) | Out-Null

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$commands = [ordered]@{
    schema_version = 1
    registry_kind = "zappa_weak_agent_command_registry"
    note = "Use command_id values from this file. Do not invent raw shell commands."
    commands = @(
        [ordered]@{
            command_id = "harness_smoke"
            description = "Run deterministic Zappa smoke validation."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite smoke"
            evidence_expected = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs\<timestamp>\report.json"
        },
        [ordered]@{
            command_id = "harness_weak_scenarios"
            description = "Assemble cooperative weak-model scenario prompts; dry-run only."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite weak-scenarios"
            evidence_expected = "harness report plus weak scenario dry-run transcripts"
        },
        [ordered]@{
            command_id = "harness_weak_adversarial"
            description = "Assemble adversarial weak-model scenario prompts; dry-run only."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite weak-adversarial-scenarios"
            evidence_expected = "harness report plus adversarial dry-run transcripts"
        },
        [ordered]@{
            command_id = "harness_skill_output_contracts"
            description = "Check required output fields in every Zappa skill."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite skill-output-contracts"
            evidence_expected = "harness report"
        },
        [ordered]@{
            command_id = "airgapped_all"
            description = "Attempt all preferred hosted weak routes. A quota blocker is a blocker, not a pass."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none -Skill $SkillName -RejectPattern SKILL_NOT_FOUND"
            evidence_expected = "live weak-model transcript and summary"
        },
        [ordered]@{
            command_id = "airgapped_dry_run"
            description = "Assemble weak prompt only; never proves weak behavior."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none -DryRun -Skill $SkillName -RejectPattern SKILL_NOT_FOUND"
            evidence_expected = "dry-run transcript marked DryRun: True"
        },
        [ordered]@{
            command_id = "selected_candidates"
            description = "Validate selected top-repo candidate packets."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates"
            evidence_expected = "coverage summary and harness report"
        },
        [ordered]@{
            command_id = "completion_readiness"
            description = "Write objective completion blockers."
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite completion-readiness"
            evidence_expected = "D:\QaaS\_tmp\zappa-dont-cry\blockers\objective-completion-readiness.json"
        }
    )
}

$task = @"
# Weak-Agent QaaS Task

## ROLE

You are a weak airgapped QaaS agent using the zappa-dont-cry skills. You must work from public QaaS docs/schema evidence and written state, not from hidden source code or chat memory.

## TASK_CONTRACT

Goal: $Goal

Skill: $SkillName
QaaS mode: $QaaSMode

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
"@

$plan = @"
# Plan

Status: SCOPED

Rules:

- READ must happen before PATCH.
- RUN_TESTS must use a command_id from commands.json, not raw shell.
- REPORT must cite evidence paths.
- END must state blockers and whether weak_validation_passed is still false.

Steps:

1. READ task.md, state.json, and commands.json.
2. READ public QaaS docs/schema evidence for the task.
3. PLAN the smallest QaaS artifact or fix with hard assertions and dependency gates.
4. PATCH only the files needed for the task.
5. RUN_TESTS harness_skill_output_contracts for skill/output-shape work or the narrowest relevant command ID.
6. RUN_TESTS airgapped_all only when live weak evidence is required and quota is available.
7. REPORT changed files, commands, evidence paths, risks, and blockers.
8. END with completion_decision: blocked unless template/build/live/eligible weak validation and strong review are all proven.
"@

$state = [ordered]@{
    schema_version = 1
    packet_kind = "zappa_weak_agent_task_packet"
    status = "SCOPED"
    task_id = $safeTaskId
    goal = $Goal
    skill_name = $SkillName
    qaas_mode = $QaaSMode
    weak_model_profile = [ordered]@{
        preferred_harness = "claude-copilot"
        profile = "airgapped"
        weakest_model = "id:gpt-3.5-turbo"
        codex_fallback_is_weak_evidence = $false
    }
    budget = [ordered]@{
        max_steps = $MaxSteps
        max_tool_calls = $MaxToolCalls
        max_writes = $MaxWrites
    }
    current_step = "READ task.md, plan.md, state.json, and commands.json"
    files_inspected = @()
    files_changed = @()
    commands_run = @()
    evidence = @()
    open_questions = @()
    risks = @("Hosted weak-model quota may block live validation; record the quota blocker instead of passing.")
    next_action = "Collect public docs/schema evidence before editing."
    completion_guard = "Do not mark complete from dry-run, Codex fallback, structural validation, or missing weak evidence."
}

$evidence = @"
# Evidence Summary

- Packet status: SCOPED
- Goal: $Goal
- Weak validation: not run
- weak_validation_passed: false

Append evidence paths here as commands run.
"@

$runLog = ([ordered]@{
    timestamp = (Get-Date).ToString("o")
    event = "packet_created"
    status = "SCOPED"
    task_id = $safeTaskId
    skill_name = $SkillName
    qaas_mode = $QaaSMode
} | ConvertTo-Json -Compress)

$finalReport = @"
# Final Report

## Task Contract

$Goal

## Changed Files

- none yet

## Commands Run

- none yet

## Evidence Paths

- none yet

## Risks

- Live weak-model validation has not run.

## Completion Decision

completion_decision: blocked
weak_validation_passed: false
"@

$taskPath = Join-Path $packetDir "task.md"
$planPath = Join-Path $packetDir "plan.md"
$statePath = Join-Path $packetDir "state.json"
$commandsPath = Join-Path $packetDir "commands.json"
$evidencePath = Join-Path $evidenceDir "summary.md"
$runLogPath = Join-Path $packetDir "run-log.jsonl"
$finalReportPath = Join-Path $packetDir "final-report.md"

Write-Utf8NoBom -Path $taskPath -Content $task
Write-Utf8NoBom -Path $planPath -Content $plan
Write-Utf8NoBom -Path $statePath -Content ($state | ConvertTo-Json -Depth 8)
Write-Utf8NoBom -Path $commandsPath -Content ($commands | ConvertTo-Json -Depth 8)
Write-Utf8NoBom -Path $evidencePath -Content $evidence
Write-Utf8NoBom -Path $runLogPath -Content ($runLog + [Environment]::NewLine)
Write-Utf8NoBom -Path $finalReportPath -Content $finalReport

[ordered]@{
    packet_dir = $packetDir
    task = $taskPath
    plan = $planPath
    state = $statePath
    commands = $commandsPath
    evidence_summary = $evidencePath
    run_log = $runLogPath
    final_report = $finalReportPath
} | ConvertTo-Json -Depth 4
