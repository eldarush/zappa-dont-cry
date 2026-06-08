param(
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness",
    [string]$PacketRoot = "D:\QaaS\_tmp\zappa-dont-cry\weak-agent-packets\harness-check"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Test-NoBom {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-Failure "File has UTF-8 BOM: $Path"
    }
}

function Test-TextContains {
    param(
        [string]$Path,
        [string[]]$Terms
    )

    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($term in $Terms) {
        if ($text -notmatch [regex]::Escape($term)) {
            Add-Failure "$Path missing required text: $term"
        }
    }
}

function Test-PathUnderRoot {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Label
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $pathPrefix = $resolvedPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedPath -ne $resolvedRoot -and -not $pathPrefix.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "$Label escaped root: $Path"
    }
}

$generator = Join-Path $HarnessRoot "scripts\new-weak-agent-task-packet.ps1"
$reference = Join-Path $HarnessRoot "references\weak-agent-task-packet.md"
if (-not (Test-Path -LiteralPath $generator -PathType Leaf)) {
    Add-Failure "Missing packet generator: $generator"
}
if (-not (Test-Path -LiteralPath $reference -PathType Leaf)) {
    Add-Failure "Missing packet reference: $reference"
}

if ($failures.Count -eq 0) {
    [System.IO.Directory]::CreateDirectory($PacketRoot) | Out-Null
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $generator `
        -Root $PacketRoot `
        -TaskId "harness-check" `
        -Goal "Plan a docs-only QaaS Runner task for a weak airgapped model." `
        -SkillName "zappa-qaas-test-planner" `
        -QaaSMode "test-planning" 2>&1

    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Packet generator failed: $($output | Out-String)"
    } else {
        try {
            $packet = ($output | Out-String) | ConvertFrom-Json
        } catch {
            Add-Failure "Packet generator did not return JSON: $($output | Out-String)"
        }
    }
}

if ($failures.Count -eq 0) {
    $packetDir = [string]$packet.packet_dir
    $expectedFiles = @(
        [string]$packet.task,
        [string]$packet.plan,
        [string]$packet.state,
        [string]$packet.commands,
        [string]$packet.evidence_summary,
        [string]$packet.run_log,
        [string]$packet.final_report
    )

    foreach ($path in $expectedFiles) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "Packet missing file: $path"
        } else {
            Test-NoBom -Path $path
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($packetDir)) {
        Test-PathUnderRoot -Path $packetDir -Root $PacketRoot -Label "Packet directory"
    }
}

if ($failures.Count -eq 0) {
    Test-TextContains -Path ([string]$packet.task) -Terms @(
        "TASK_CONTRACT",
        "ALLOWED_ACTIONS",
        "FORBIDDEN_ACTIONS",
        "OUTPUT_FORMAT",
        "task_contract",
        "intent_assumptions",
        "validation_sequence",
        "evidence_paths",
        "stop_condition",
        "escalate_if",
        "final_report",
        "weak_validation_passed",
        "source_only_blocked",
        "Do not invent QaaS YAML fields",
        "DryRun"
    )

    Test-TextContains -Path ([string]$packet.plan) -Terms @(
        "READ",
        "PATCH",
        "RUN_TESTS",
        "command_id",
        "REPORT",
        "END",
        "completion_decision: blocked"
    )

    Test-TextContains -Path $reference -Terms @(
        "task contract",
        "state.json",
        "commands.json",
        "evidence",
        "false success",
        "dry-run",
        "source_only_blocked",
        "Do not invent"
    )
}

if ($failures.Count -eq 0) {
    $state = Get-Content -LiteralPath ([string]$packet.state) -Raw | ConvertFrom-Json
    if ([string]$state.packet_kind -ne "zappa_weak_agent_task_packet") {
        Add-Failure "state.json packet_kind mismatch"
    }
    if ([string]$state.status -ne "SCOPED") {
        Add-Failure "state.json status must be SCOPED"
    }
    if ([string]$state.skill_name -ne "zappa-qaas-test-planner") {
        Add-Failure "state.json skill_name mismatch"
    }
    if ($state.weak_model_profile.codex_fallback_is_weak_evidence -ne $false) {
        Add-Failure "state.json must mark Codex fallback as non-weak evidence"
    }
    if ([string]$state.completion_guard -notmatch "dry-run") {
        Add-Failure "state.json completion_guard must mention dry-run"
    }

    $commands = Get-Content -LiteralPath ([string]$packet.commands) -Raw | ConvertFrom-Json
    $ids = @($commands.commands | ForEach-Object { [string]$_.command_id })
    foreach ($requiredId in @(
        "harness_smoke",
        "harness_weak_scenarios",
        "harness_weak_adversarial",
        "harness_skill_output_contracts",
        "airgapped_all",
        "airgapped_dry_run",
        "selected_candidates",
        "completion_readiness"
    )) {
        if ($ids -notcontains $requiredId) {
            Add-Failure "commands.json missing command_id: $requiredId"
        }
    }

    foreach ($commandRecord in @($commands.commands)) {
        $commandText = [string]$commandRecord.command
        if ($commandText -match "git\s+push|git\s+reset|Remove-Item\s+-Recurse|rm\s+-rf") {
            Add-Failure "commands.json contains unsafe command for $($commandRecord.command_id)"
        }
        if ($commandText -notmatch "D:\\QaaS\\_tools") {
            Add-Failure "commands.json command is not anchored to managed QaaS tools: $($commandRecord.command_id)"
        }
    }

    $commandById = @{}
    foreach ($commandRecord in @($commands.commands)) {
        $commandById[[string]$commandRecord.command_id] = [string]$commandRecord.command
    }

    $airgappedAll = [string]$commandById["airgapped_all"]
    if ($airgappedAll -notmatch "-Airgapped" -or $airgappedAll -notmatch "-All" -or $airgappedAll -notmatch "-ReasoningEffort\s+none") {
        Add-Failure "airgapped_all must use -Airgapped -All -ReasoningEffort none"
    }
    if ($airgappedAll -match "-DryRun") {
        Add-Failure "airgapped_all must not include -DryRun"
    }
    if ($airgappedAll -notmatch "-Skill\s+zappa-qaas-test-planner") {
        Add-Failure "airgapped_all must target the generated packet skill"
    }

    $airgappedDryRun = [string]$commandById["airgapped_dry_run"]
    if ($airgappedDryRun -notmatch "-Airgapped" -or $airgappedDryRun -notmatch "-All" -or $airgappedDryRun -notmatch "-ReasoningEffort\s+none" -or $airgappedDryRun -notmatch "-DryRun") {
        Add-Failure "airgapped_dry_run must use -Airgapped -All -ReasoningEffort none -DryRun"
    }
    if ($airgappedDryRun -notmatch "-Skill\s+zappa-qaas-test-planner") {
        Add-Failure "airgapped_dry_run must target the generated packet skill"
    }

    $evidenceText = Get-Content -LiteralPath ([string]$packet.evidence_summary) -Raw
    if ($evidenceText -match "weak_validation_passed:\s*true") {
        Add-Failure "evidence summary must not claim weak validation passed"
    }
    if ($evidenceText -notmatch "weak_validation_passed:\s*false") {
        Add-Failure "evidence summary must keep weak_validation_passed false"
    }

    $finalText = Get-Content -LiteralPath ([string]$packet.final_report) -Raw
    if ($finalText -match "completion_decision:\s*complete") {
        Add-Failure "final report scaffold must not claim completion"
    }
    if ($finalText -notmatch "completion_decision:\s*blocked") {
        Add-Failure "final report scaffold must keep completion_decision blocked"
    }
    if ($finalText -notmatch "weak_validation_passed:\s*false") {
        Add-Failure "final report scaffold must keep weak_validation_passed false"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Weak-agent task packet check passed."
