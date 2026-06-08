param(
    [string]$FixturePath = "D:\QaaS\_tools\zappa-harness\fixtures\weak-skill-scenarios.json",
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [ValidateSet("", "scenario", "adversarial")]
    [string]$ScenarioKind = "",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live-scenarios",
    [string]$IndexPath = "",
    [string[]]$ScenarioIds = @(),
    [switch]$OnlyIncomplete,
    [int]$MaxScenarios = 0,
    [switch]$StopOnQuotaBlocked,
    [switch]$StopOnModelUnavailable,
    [switch]$NoFailOnRecordedBlocker,
    [switch]$AllAirgappedModels,
    [switch]$DryRun,
    [int]$TimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\run-airgapped-validation.ps1"
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "Airgapped validation runner not found: $runner"
}
if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    throw "Weak scenario fixture not found: $FixturePath"
}
if (-not (Test-Path -LiteralPath $SkillRoot -PathType Container)) {
    throw "Skill root not found: $SkillRoot"
}

$fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
if (-not $ScenarioKind) {
    $ScenarioKind = if ([string]$fixture.live_validation_kind -eq "live_adversarial_model_execution") { "adversarial" } else { "scenario" }
}
if (-not $IndexPath) {
    $indexFileName = if ($ScenarioKind -eq "adversarial") { "weak-adversarial-runner-index.json" } else { "weak-scenario-runner-index.json" }
    $IndexPath = Join-Path $OutDir $indexFileName
}

[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $IndexPath)) | Out-Null

function Get-ObjectValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        [object]$DefaultValue = $null
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $PropertyName)) {
        return $DefaultValue
    }

    return $Object.$PropertyName
}

function Get-ExistingScenarioRecords {
    param([string]$Path)

    $records = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $records
    }

    $index = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not ($index.PSObject.Properties.Name -contains "records")) {
        return $records
    }

    foreach ($record in @($index.records)) {
        $recordScenarioId = [string](Get-ObjectValue -Object $record -PropertyName "scenario_id")
        if (-not [string]::IsNullOrWhiteSpace($recordScenarioId)) {
            $records[$recordScenarioId] = $record
        }
    }

    return $records
}

function Test-ScenarioIsComplete {
    param([object]$Record)

    if ($null -eq $Record) {
        return $false
    }

    if ((Get-ObjectValue -Object $Record -PropertyName "weak_validation_passed" -DefaultValue $false) -eq $true) {
        return $true
    }

    if ((Get-ObjectValue -Object $Record -PropertyName "all_preferred_models_live_ready" -DefaultValue $false) -eq $true) {
        return $true
    }

    return $false
}

function Get-TranscriptClassification {
    param(
        [string]$TranscriptPath,
        [int]$ExitCode,
        [bool]$IsDryRun
    )

    if ($IsDryRun) {
        return "dry_run_assembly"
    }

    if ([string]::IsNullOrWhiteSpace($TranscriptPath) -or -not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) {
        return "missing_transcript"
    }

    $transcript = Get-Content -LiteralPath $TranscriptPath -Raw
    if ($transcript -match "additional_spend_limit_reached" -or
        $transcript -match "additional usage limit" -or
        $transcript -match "user_weekly_rate_limited" -or
        $transcript -match "rate-limiting chat requests" -or
        $transcript -match "retry-after" -or
        $transcript -match "\b402\b" -or
        $ExitCode -eq 75) {
        return "quota_blocked"
    }
    if ($transcript -match "Model `"[^`"]+`" from --model flag is not available" -or $transcript -match "model .* is not available") {
        return "model_unavailable"
    }
    if ($ExitCode -eq 0) {
        return "live_transcript_ready"
    }

    return "unknown_failure"
}

$records = New-Object System.Collections.Generic.List[object]
$started = Get-Date
$existingRecords = Get-ExistingScenarioRecords -Path $IndexPath
$effectiveAllAirgappedModels = $AllAirgappedModels.IsPresent -or -not $DryRun.IsPresent
$requestedScenarioIds = @{}
foreach ($requestedScenarioId in @($ScenarioIds)) {
    if (-not [string]::IsNullOrWhiteSpace($requestedScenarioId)) {
        $requestedScenarioIds[[string]$requestedScenarioId] = $true
    }
}
$selectedScenarioCount = 0
$skippedScenarioCount = 0
$stoppedEarlyReason = $null

foreach ($scenario in @($fixture.scenarios)) {
    $currentScenarioId = [string]$scenario.scenario_id
    $skillName = [string]$scenario.skill
    $prompt = [string]$scenario.prompt
    if ([string]::IsNullOrWhiteSpace($currentScenarioId)) {
        throw "Scenario missing scenario_id in $FixturePath"
    }
    if ([string]::IsNullOrWhiteSpace($skillName)) {
        throw "$currentScenarioId missing skill"
    }
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        throw "$currentScenarioId missing prompt"
    }

    if ($requestedScenarioIds.Count -gt 0 -and -not $requestedScenarioIds.ContainsKey($currentScenarioId)) {
        $skippedScenarioCount++
        continue
    }

    if ($OnlyIncomplete -and $existingRecords.ContainsKey($currentScenarioId) -and (Test-ScenarioIsComplete -Record $existingRecords[$currentScenarioId])) {
        $skippedScenarioCount++
        continue
    }

    if ($MaxScenarios -gt 0 -and $selectedScenarioCount -ge $MaxScenarios) {
        $stoppedEarlyReason = "max_scenarios_reached"
        break
    }

    $skillPath = Join-Path (Join-Path $SkillRoot $skillName) "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
        throw "$currentScenarioId references missing skill path: $skillPath"
    }

    $selectedScenarioCount++
    $scenarioStarted = Get-Date
    $params = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $runner,
        "-Prompt",
        $prompt,
        "-SkillPath",
        $skillPath,
        "-RejectPattern",
        "SKILL_NOT_FOUND",
        "-ScenarioId",
        $currentScenarioId,
        "-ScenarioKind",
        $ScenarioKind,
        "-IndexPath",
        $IndexPath,
        "-ReasoningEffort",
        "none",
        "-TimeoutSeconds",
        $TimeoutSeconds,
        "-OutDir",
        $OutDir
    )
    if ($DryRun) {
        $params += "-DryRun"
    }
    if ($effectiveAllAirgappedModels) {
        $params += "-All"
    }

    $global:LASTEXITCODE = 0
    $output = @()
    try {
        $output = @(& powershell @params 2>&1)
    } catch {
        $output = @($output + $_)
        if ([int]$global:LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = 1
        }
    }
    $exitCode = [int]$global:LASTEXITCODE
    $summaryPath = $null
    $transcriptPath = $null
    $transcriptPaths = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($output | ForEach-Object { [string]$_ })) {
        if ($line -match "^Summary:\s*(?<path>.+)$") {
            $summaryPath = $matches.path.Trim()
        }
        if ($line -match "^Transcript:\s*(?<path>.+)$") {
            $transcriptPath = $matches.path.Trim()
            $transcriptPaths.Add($transcriptPath)
        }
    }
    if ([string]::IsNullOrWhiteSpace($summaryPath) -or [string]::IsNullOrWhiteSpace($transcriptPath)) {
        $latestIndexRecords = Get-ExistingScenarioRecords -Path $IndexPath
        if ($latestIndexRecords.ContainsKey($currentScenarioId)) {
            $latestRecord = $latestIndexRecords[$currentScenarioId]
            if ([string]::IsNullOrWhiteSpace($summaryPath)) {
                $summaryPath = [string](Get-ObjectValue -Object $latestRecord -PropertyName "summary")
            }
            if ([string]::IsNullOrWhiteSpace($transcriptPath)) {
                $transcriptPath = [string](Get-ObjectValue -Object $latestRecord -PropertyName "transcript")
            }
            $indexedExitCode = Get-ObjectValue -Object $latestRecord -PropertyName "transcript_exit_code"
            if ($null -ne $indexedExitCode -and -not [string]::IsNullOrWhiteSpace([string]$indexedExitCode)) {
                $exitCode = [int]$indexedExitCode
            }
        }
    }
    $classification = Get-TranscriptClassification -TranscriptPath $transcriptPath -ExitCode $exitCode -IsDryRun:$DryRun.IsPresent

    $records.Add([ordered]@{
        scenario_id = $currentScenarioId
        skill = $skillName
        scenario_kind = $ScenarioKind
        dry_run = $DryRun.IsPresent
        exit_code = $exitCode
        classification = $classification
        duration_ms = [int]((Get-Date) - $scenarioStarted).TotalMilliseconds
        summary = $summaryPath
        transcript = $transcriptPath
        transcripts = $transcriptPaths.ToArray()
    })

    if ($StopOnQuotaBlocked -and $classification -eq "quota_blocked") {
        $stoppedEarlyReason = "quota_blocked"
        break
    }
    if ($StopOnModelUnavailable -and $classification -eq "model_unavailable") {
        $stoppedEarlyReason = "model_unavailable"
        break
    }
}

$summaryPath = Join-Path $OutDir "weak-scenario-suite-runner-summary.json"
$failedCount = @($records | Where-Object { [int]$_["exit_code"] -ne 0 }).Count
$recordedBlockerCount = @($records | Where-Object { [string]$_["classification"] -in @("quota_blocked", "model_unavailable") }).Count
$unknownFailureCount = @($records | Where-Object { [int]$_["exit_code"] -ne 0 -and [string]$_["classification"] -notin @("quota_blocked", "model_unavailable") }).Count
$record = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    fixture = $FixturePath
    skill_root = $SkillRoot
    scenario_kind = $ScenarioKind
    dry_run = $DryRun.IsPresent
    out_dir = $OutDir
    index_path = $IndexPath
    requested_scenario_ids = @($ScenarioIds)
    only_incomplete = $OnlyIncomplete.IsPresent
    max_scenarios = $MaxScenarios
    all_airgapped_models = $effectiveAllAirgappedModels
    selected_scenario_count = $selectedScenarioCount
    skipped_scenario_count = $skippedScenarioCount
    scenario_count = $records.Count
    failed_invocation_count = $failedCount
    recorded_blocker_count = $recordedBlockerCount
    unknown_failure_count = $unknownFailureCount
    stopped_early_reason = $stoppedEarlyReason
    duration_ms = [int]((Get-Date) - $started).TotalMilliseconds
    weak_validation_passed = $false
    runner_status = if ($DryRun) { "dry_run_prompt_assembly" } elseif ($records.Count -eq 0) { "no_scenarios_selected" } elseif ($unknownFailureCount -gt 0) { "live_invocations_failed" } elseif ($recordedBlockerCount -gt 0) { "live_invocations_blocked" } else { "live_invocations_recorded" }
    records = $records.ToArray()
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Output "Weak scenario suite runner complete."
Write-Output "Summary: $summaryPath"
Write-Output "Index: $IndexPath"

if ($failedCount -gt 0 -and -not $DryRun -and -not ($NoFailOnRecordedBlocker -and $unknownFailureCount -eq 0)) {
    Write-Error "$failedCount weak scenario invocation(s) failed or were blocked. Evidence was recorded; see summary and index."
    exit 1
}
