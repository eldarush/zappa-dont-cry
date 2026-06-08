param(
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness",
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs\manual\weak-suite-runner"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Read-Json {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-Sha256 {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Test-RunnerOutput {
    param(
        [string]$Kind,
        [string]$RunDir,
        [string]$IndexPath,
        [string]$FixturePath
    )

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        Add-Failure "$Kind runner did not write index: $IndexPath"
        return
    }

    $summaryPath = Join-Path $RunDir "weak-scenario-suite-runner-summary.json"
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        Add-Failure "$Kind runner did not write summary: $summaryPath"
        return
    }

    $fixture = Read-Json -Path $FixturePath
    $summary = Read-Json -Path $summaryPath
    $index = Read-Json -Path $IndexPath
    $expectedCount = @($fixture.scenarios).Count

    if ([int]$summary.scenario_count -ne $expectedCount) {
        Add-Failure "$Kind runner summary scenario_count mismatch"
    }
    if ([string]$summary.runner_status -ne "dry_run_prompt_assembly") {
        Add-Failure "$Kind runner summary status is not dry_run_prompt_assembly"
    }
    if ($summary.weak_validation_passed -ne $false) {
        Add-Failure "$Kind runner summary must not pass weak validation"
    }
    if (@($index.records).Count -ne $expectedCount) {
        Add-Failure "$Kind runner index record count mismatch"
    }

    foreach ($scenario in @($fixture.scenarios)) {
        $scenarioId = [string]$scenario.scenario_id
        $record = @($index.records | Where-Object { [string]$_.scenario_id -eq $scenarioId }) | Select-Object -First 1
        if ($null -eq $record) {
            Add-Failure "$Kind runner index missing scenario: $scenarioId"
            continue
        }
        if ([string]$record.match_status -ne "runner_recorded") {
            Add-Failure "$Kind runner index did not record runner ownership for ${scenarioId}: $($record.match_status)"
        }
        if ([string]$record.classification -ne "dry_run_assembly") {
            Add-Failure "$Kind runner index classification is not dry_run_assembly for ${scenarioId}: $($record.classification)"
        }
        if ($record.weak_validation_passed -ne $false) {
            Add-Failure "$Kind runner index must not pass weak validation for $scenarioId"
        }
        if ($record.dry_run -ne $true) {
            Add-Failure "$Kind runner index dry_run must be true for $scenarioId"
        }
        if ([string]::IsNullOrWhiteSpace([string]$record.prompt_hash_sha256)) {
            Add-Failure "$Kind runner index missing prompt hash for $scenarioId"
        }
        if ([string]::IsNullOrWhiteSpace([string]$record.transcript) -or -not (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf)) {
            Add-Failure "$Kind runner transcript missing for $scenarioId"
            continue
        }
        $transcript = Get-Content -LiteralPath ([string]$record.transcript) -Raw
        foreach ($required in @(
            "Command: DRY_RUN",
            "ScenarioId: $scenarioId",
            "PromptHashSha256: $($record.prompt_hash_sha256)",
            "Model: id:gpt-3.5-turbo",
            "DryRun: True"
        )) {
            if ($transcript -notmatch [regex]::Escape($required)) {
                Add-Failure "$Kind runner transcript missing '$required': $($record.transcript)"
            }
        }
    }
}

function Test-LiveIndexConsumption {
    param(
        [string]$Kind,
        [string]$RunDir,
        [string]$RunnerIndexPath,
        [string]$FixturePath,
        [string]$IndexFileName
    )

    $liveIndexCheck = Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1"
    if (-not (Test-Path -LiteralPath $liveIndexCheck -PathType Leaf)) {
        Add-Failure "$Kind missing live index checker: $liveIndexCheck"
        return
    }

    $blockersDir = Join-Path $RunDir "live-index-check"
    $global:LASTEXITCODE = 0
    & powershell -NoProfile -ExecutionPolicy Bypass -File $liveIndexCheck -EvidenceRoot $RunDir -FixturePath $FixturePath -BlockersDir $blockersDir -IndexFileName $IndexFileName -RunnerIndexPath $RunnerIndexPath
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "$Kind live index checker did not consume runner index"
        return
    }

    $indexPath = Join-Path $blockersDir $IndexFileName
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        Add-Failure "$Kind live index checker did not write index: $indexPath"
        return
    }

    $fixture = Read-Json -Path $FixturePath
    $index = Read-Json -Path $indexPath
    $expectedCount = @($fixture.scenarios).Count
    if ([string]$index.runner_index -ne $RunnerIndexPath) {
        Add-Failure "$Kind live index did not cite runner index"
    }
    if ([int]$index.runner_recorded_count -ne $expectedCount) {
        Add-Failure "$Kind live index runner_recorded_count mismatch"
    }
    if ([int]$index.dry_run_assembly_count -ne $expectedCount) {
        Add-Failure "$Kind live index dry_run_assembly_count mismatch"
    }
    if ([int]$index.missing_transcript_count -ne 0) {
        Add-Failure "$Kind live index should have zero missing transcripts from runner index"
    }
    if ($index.weak_validation_passed -ne $false) {
        Add-Failure "$Kind live index must not pass weak validation for dry-run runner evidence"
    }
    foreach ($record in @($index.records)) {
        if ([string]$record.match_status -ne "runner_recorded") {
            Add-Failure "$Kind live index record is not runner_recorded for $($record.scenario_id)"
        }
    }
}

function Test-TargetedResumeOutput {
    param(
        [string]$RunDir,
        [string]$FixturePath
    )

    $fixture = Read-Json -Path $FixturePath
    $scenarios = @($fixture.scenarios)
    if ($scenarios.Count -lt 2) {
        Add-Failure "Targeted resume test requires at least two scenarios"
        return
    }

    $firstScenarioId = [string]$scenarios[0].scenario_id
    $secondScenarioId = [string]$scenarios[1].scenario_id
    $indexPath = Join-Path $RunDir "weak-scenario-runner-index.json"
    [System.IO.Directory]::CreateDirectory($RunDir) | Out-Null
    [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        validation_kind = "live_scenario_model_execution"
        index_status = "runner_recorded"
        records = @(
            [ordered]@{
                scenario_id = $firstScenarioId
                scenario_kind = "scenario"
                prompt_hash_sha256 = "synthetic-complete-record"
                match_status = "runner_recorded"
                harness = "claude-copilot"
                profile = "airgapped"
                model = "id:gpt-3.5-turbo"
                dry_run = $false
                classification = "live_transcript_ready"
                all_preferred_models_live_ready = $true
                weak_validation_passed = $false
                transcript_exit_code = 0
                summary = $null
                transcript = $null
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexPath -Encoding UTF8

    $global:LASTEXITCODE = 0
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -FixturePath $FixturePath -SkillRoot $SkillRoot -ScenarioKind scenario -OutDir $RunDir -IndexPath $indexPath -OnlyIncomplete -MaxScenarios 1 -DryRun
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Targeted resume dry run failed"
        return
    }

    $summaryPath = Join-Path $RunDir "weak-scenario-suite-runner-summary.json"
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        Add-Failure "Targeted resume did not write summary: $summaryPath"
        return
    }

    $summary = Read-Json -Path $summaryPath
    $index = Read-Json -Path $indexPath
    if ([int]$summary.scenario_count -ne 1) {
        Add-Failure "Targeted resume should run exactly one scenario"
    }
    if ([int]$summary.selected_scenario_count -ne 1) {
        Add-Failure "Targeted resume selected_scenario_count mismatch"
    }
    if ([int]$summary.skipped_scenario_count -lt 1) {
        Add-Failure "Targeted resume should skip the completed first scenario"
    }
    if ($summary.only_incomplete -ne $true) {
        Add-Failure "Targeted resume summary did not record only_incomplete"
    }
    if ([int]$summary.max_scenarios -ne 1) {
        Add-Failure "Targeted resume summary did not record max_scenarios"
    }
    if ([string]$summary.runner_status -ne "dry_run_prompt_assembly") {
        Add-Failure "Targeted resume runner status should remain dry_run_prompt_assembly"
    }
    if ($summary.weak_validation_passed -ne $false) {
        Add-Failure "Targeted resume must not pass weak validation"
    }

    $firstDryRunRecords = @($index.records | Where-Object { [string]$_.scenario_id -eq $firstScenarioId -and [string]$_.classification -eq "dry_run_assembly" })
    if ($firstDryRunRecords.Count -ne 0) {
        Add-Failure "Targeted resume reran the completed first scenario"
    }

    $secondRecord = @($index.records | Where-Object { [string]$_.scenario_id -eq $secondScenarioId -and [string]$_.classification -eq "dry_run_assembly" }) | Select-Object -First 1
    if ($null -eq $secondRecord) {
        Add-Failure "Targeted resume did not run the next incomplete scenario"
        return
    }
    if ($secondRecord.weak_validation_passed -ne $false) {
        Add-Failure "Targeted resume index must not pass weak validation"
    }
    if ([string]$secondRecord.model -ne "id:gpt-3.5-turbo") {
        Add-Failure "Targeted resume index did not preserve weak airgapped model"
    }
}

function New-SyntheticWeakTranscript {
    param(
        [string]$RunDir,
        [string]$ScenarioId,
        [string]$ScenarioKind,
        [string]$PromptHash,
        [string]$Harness,
        [string]$Profile,
        [string]$Model,
        [int]$ExitCode = 1,
        [string]$StdOut = "additional_spend_limit_reached"
    )

    [System.IO.Directory]::CreateDirectory($RunDir) | Out-Null
    $safeModel = $Model -replace '[^A-Za-z0-9_.-]', '_'
    $prefix = "synthetic-$ScenarioId-$safeModel"
    $transcriptPath = Join-Path $RunDir "$prefix-$Harness-$safeModel.md"
    $summaryPath = Join-Path $RunDir "$prefix-summary.md"
    $command = switch ($Harness) {
        "claude-copilot" { "C:\Users\eldar\copilot-claude\claude.cmd $Model -p prompt" }
        "copilot" { "C:\Users\eldar\AppData\Roaming\npm\copilot.ps1 --model $Model -p prompt" }
        "codex" { "C:\Users\eldar\AppData\Roaming\npm\codex.cmd exec --model $Model" }
        default { "synthetic" }
    }

    @(
        "# weak-model-session transcript",
        "",
        "Command: $command",
        "ExitCode: $ExitCode",
        "ScenarioId: $ScenarioId",
        "ScenarioKind: $ScenarioKind",
        "PromptHashSha256: $PromptHash",
        "Harness: $Harness",
        "Profile: $Profile",
        "Model: $Model",
        "DryRun: False",
        "",
        "## stdout",
        $StdOut,
        "",
        "## stderr"
    ) -join [Environment]::NewLine | Set-Content -LiteralPath $transcriptPath -Encoding UTF8

    @(
        "# Weak Model Validation Summary",
        "",
        "Harness: $Harness",
        "Profile: $Profile",
        "Models: $Model",
        "DryRun: False",
        "Airgapped: True",
        "ScenarioId: $ScenarioId",
        "ScenarioKind: $ScenarioKind",
        "PromptHashSha256: $PromptHash"
    ) -join [Environment]::NewLine | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    return [pscustomobject]@{
        Transcript = $transcriptPath
        Summary = $summaryPath
    }
}

function Test-FallbackWeakProxyIndex {
    param(
        [string]$RunDir,
        [string]$FixturePath
    )

    $fixture = Read-Json -Path $FixturePath
    $scenario = @($fixture.scenarios)[0]
    $scenarioId = [string]$scenario.scenario_id
    $promptHash = Get-Sha256 -Text ([string]$scenario.prompt)
    $model = "id:gpt-3.5-turbo-0613"
    $paths = New-SyntheticWeakTranscript -RunDir $RunDir -ScenarioId $scenarioId -ScenarioKind "scenario" -PromptHash $promptHash -Harness "claude-copilot" -Profile "airgapped" -Model $model
    $runnerIndexPath = Join-Path $RunDir "weak-scenario-runner-index.json"
    [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        validation_kind = "live_scenario_model_execution"
        index_status = "quota_blocked"
        records = @(
            [ordered]@{
                scenario_id = $scenarioId
                scenario_kind = "scenario"
                prompt_hash_sha256 = $promptHash
                prompt_length = ([string]$scenario.prompt).Length
                match_status = "runner_recorded"
                harness = "claude-copilot"
                profile = "airgapped"
                model = $model
                weak_validation_eligible = $true
                dry_run = $false
                classification = "quota_blocked"
                weak_validation_passed = $false
                transcript_exit_code = 1
                summary = $paths.Summary
                transcript = $paths.Transcript
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runnerIndexPath -Encoding UTF8

    $blockersDir = Join-Path $RunDir "live-index-check"
    $global:LASTEXITCODE = 0
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot $RunDir -FixturePath $FixturePath -BlockersDir $blockersDir -IndexFileName "weak-scenario-live-index-latest.json" -RunnerIndexPath $runnerIndexPath 2>&1 | Out-Null
    } catch {
        if ($LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = 1
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Fallback weak proxy index was rejected"
        return
    }

    $indexPath = Join-Path $blockersDir "weak-scenario-live-index-latest.json"
    $index = Read-Json -Path $indexPath
    $record = @($index.records | Where-Object { [string]$_.scenario_id -eq $scenarioId }) | Select-Object -First 1
    if ($null -eq $record) {
        Add-Failure "Fallback weak proxy index did not record scenario"
    } elseif ([string]$record.model -ne $model) {
        Add-Failure "Fallback weak proxy index did not preserve model: $($record.model)"
    }
    if ([int]$index.quota_blocked_count -ne 1) {
        Add-Failure "Fallback weak proxy index should classify one quota-blocked transcript"
    }
    if ($index.weak_validation_passed -ne $false) {
        Add-Failure "Fallback weak proxy quota blocker must not pass weak validation"
    }
}

function New-RunnerIndexFixture {
    param(
        [string]$RunnerIndexPath,
        [string]$ScenarioId,
        [string]$Prompt,
        [string]$Model,
        [string]$Summary,
        [string]$Transcript,
        [int]$ExitCode,
        [string]$Classification = "live_transcript_ready",
        [string]$Harness = "claude-copilot",
        [string]$Profile = "airgapped"
    )

    [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        validation_kind = "live_scenario_model_execution"
        index_status = "runner_recorded"
        records = @(
            [ordered]@{
                scenario_id = $ScenarioId
                scenario_kind = "scenario"
                prompt_hash_sha256 = (Get-Sha256 -Text $Prompt)
                prompt_length = $Prompt.Length
                match_status = "runner_recorded"
                harness = $Harness
                profile = $Profile
                model = $Model
                weak_validation_eligible = $true
                dry_run = $false
                classification = $Classification
                weak_validation_passed = $false
                transcript_exit_code = $ExitCode
                summary = $Summary
                transcript = $Transcript
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $RunnerIndexPath -Encoding UTF8
}

function Test-RunnerIndexContainmentRejected {
    param(
        [string]$RunDir,
        [string]$FixturePath
    )

    $fixture = Read-Json -Path $FixturePath
    $scenario = @($fixture.scenarios)[0]
    $scenarioId = [string]$scenario.scenario_id
    $prompt = [string]$scenario.prompt
    $model = "id:gpt-3.5-turbo"
    $outsideDir = Join-Path (Split-Path -Parent $RunDir) "outside-evidence"
    $paths = New-SyntheticWeakTranscript -RunDir $outsideDir -ScenarioId $scenarioId -ScenarioKind "scenario" -PromptHash (Get-Sha256 -Text $prompt) -Harness "claude-copilot" -Profile "airgapped" -Model $model -ExitCode 0 -StdOut "ready"
    [System.IO.Directory]::CreateDirectory($RunDir) | Out-Null
    $runnerIndexPath = Join-Path $RunDir "weak-scenario-runner-index.json"
    New-RunnerIndexFixture -RunnerIndexPath $runnerIndexPath -ScenarioId $scenarioId -Prompt $prompt -Model $model -Summary $paths.Summary -Transcript $paths.Transcript -ExitCode 0

    $blockersDir = Join-Path $RunDir "live-index-check"
    $global:LASTEXITCODE = 0
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot $RunDir -FixturePath $FixturePath -BlockersDir $blockersDir -IndexFileName "weak-scenario-live-index-latest.json" -RunnerIndexPath $runnerIndexPath 2>&1 | Out-Null
    } catch {
        if ($LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = 1
        }
    }
    if ($LASTEXITCODE -eq 0) {
        Add-Failure "Runner index transcript/summary outside EvidenceRoot was accepted"
    }
}

function Test-LaunderedTranscriptHarnessRejected {
    param(
        [string]$RunDir,
        [string]$FixturePath
    )

    $fixture = Read-Json -Path $FixturePath
    $scenario = @($fixture.scenarios)[0]
    $scenarioId = [string]$scenario.scenario_id
    $prompt = [string]$scenario.prompt
    $model = "id:gpt-3.5-turbo"
    $paths = New-SyntheticWeakTranscript -RunDir $RunDir -ScenarioId $scenarioId -ScenarioKind "scenario" -PromptHash (Get-Sha256 -Text $prompt) -Harness "claude-copilot" -Profile "airgapped" -Model $model -ExitCode 0 -StdOut "ready"
    $transcript = Get-Content -LiteralPath $paths.Transcript -Raw
    $transcript = $transcript -replace "(?m)^Command: .+$", "Command: codex exec --model gpt-5.3-codex-spark" -replace "(?m)^Harness: .+$", "Harness: codex"
    Set-Content -LiteralPath $paths.Transcript -Value $transcript -Encoding UTF8

    $runnerIndexPath = Join-Path $RunDir "weak-scenario-runner-index.json"
    New-RunnerIndexFixture -RunnerIndexPath $runnerIndexPath -ScenarioId $scenarioId -Prompt $prompt -Model $model -Summary $paths.Summary -Transcript $paths.Transcript -ExitCode 0

    $blockersDir = Join-Path $RunDir "live-index-check"
    $global:LASTEXITCODE = 0
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot $RunDir -FixturePath $FixturePath -BlockersDir $blockersDir -IndexFileName "weak-scenario-live-index-latest.json" -RunnerIndexPath $runnerIndexPath 2>&1 | Out-Null
    } catch {
        if ($LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = 1
        }
    }
    if ($LASTEXITCODE -eq 0) {
        Add-Failure "Codex transcript laundered through an allowed weak runner index was accepted"
    }
}

function Test-QuotaExit75Index {
    param(
        [string]$RunDir,
        [string]$FixturePath
    )

    $fixture = Read-Json -Path $FixturePath
    $scenario = @($fixture.scenarios)[0]
    $scenarioId = [string]$scenario.scenario_id
    $promptHash = Get-Sha256 -Text ([string]$scenario.prompt)
    $model = "id:gpt-3.5-turbo"
    $paths = New-SyntheticWeakTranscript -RunDir $RunDir -ScenarioId $scenarioId -ScenarioKind "scenario" -PromptHash $promptHash -Harness "claude-copilot" -Profile "airgapped" -Model $model -ExitCode 75 -StdOut "user_weekly_rate_limited: rate-limiting chat requests; retry-after: 60"
    $runnerIndexPath = Join-Path $RunDir "weak-scenario-runner-index.json"
    [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        validation_kind = "live_scenario_model_execution"
        index_status = "runner_recorded"
        records = @(
            [ordered]@{
                scenario_id = $scenarioId
                scenario_kind = "scenario"
                prompt_hash_sha256 = $promptHash
                prompt_length = ([string]$scenario.prompt).Length
                match_status = "runner_recorded"
                harness = "claude-copilot"
                profile = "airgapped"
                model = $model
                weak_validation_eligible = $true
                dry_run = $false
                classification = "unknown_failure"
                weak_validation_passed = $false
                transcript_exit_code = 75
                summary = $paths.Summary
                transcript = $paths.Transcript
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runnerIndexPath -Encoding UTF8

    $blockersDir = Join-Path $RunDir "live-index-check"
    $global:LASTEXITCODE = 0
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot $RunDir -FixturePath $FixturePath -BlockersDir $blockersDir -IndexFileName "weak-scenario-live-index-latest.json" -RunnerIndexPath $runnerIndexPath 2>&1 | Out-Null
    } catch {
        if ($LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = 1
        }
    }
    if ($LASTEXITCODE -eq 0) {
        Add-Failure "Quota exit 75 runner classification mismatch was accepted"
        return
    }

    $indexText = Get-Content -LiteralPath $runnerIndexPath -Raw
    $indexText = $indexText -replace '"classification":\s*"unknown_failure"', '"classification": "quota_blocked"'
    Set-Content -LiteralPath $runnerIndexPath -Value $indexText -Encoding UTF8

    $global:LASTEXITCODE = 0
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot $RunDir -FixturePath $FixturePath -BlockersDir $blockersDir -IndexFileName "weak-scenario-live-index-latest.json" -RunnerIndexPath $runnerIndexPath 2>&1 | Out-Null
    } catch {
        if ($LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = 1
        }
    }
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Quota exit 75 transcript was not accepted as a recorded quota blocker"
        return
    }

    $indexPath = Join-Path $blockersDir "weak-scenario-live-index-latest.json"
    $index = Read-Json -Path $indexPath
    if ([int]$index.quota_blocked_count -ne 1) {
        Add-Failure "Quota exit 75 transcript should classify one quota-blocked transcript"
    }
    if ($index.weak_validation_passed -ne $false) {
        Add-Failure "Quota exit 75 blocker must not pass weak validation"
    }
}

function Test-CodexWeakProxyRejected {
    param(
        [string]$RunDir,
        [string]$FixturePath
    )

    $fixture = Read-Json -Path $FixturePath
    $scenario = @($fixture.scenarios)[0]
    $scenarioId = [string]$scenario.scenario_id
    $promptHash = Get-Sha256 -Text ([string]$scenario.prompt)
    $model = "gpt-5.3-codex-spark"
    $paths = New-SyntheticWeakTranscript -RunDir $RunDir -ScenarioId $scenarioId -ScenarioKind "scenario" -PromptHash $promptHash -Harness "codex" -Profile "airgapped" -Model $model
    $runnerIndexPath = Join-Path $RunDir "weak-scenario-runner-index.json"
    [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        validation_kind = "live_scenario_model_execution"
        index_status = "quota_blocked"
        records = @(
            [ordered]@{
                scenario_id = $scenarioId
                scenario_kind = "scenario"
                prompt_hash_sha256 = $promptHash
                prompt_length = ([string]$scenario.prompt).Length
                match_status = "runner_recorded"
                harness = "codex"
                profile = "airgapped"
                model = $model
                weak_validation_eligible = $false
                not_weak_reason = "codex-hosted-models-are-too-strong-for-weak-validation"
                dry_run = $false
                classification = "quota_blocked"
                weak_validation_passed = $false
                transcript_exit_code = 1
                summary = $paths.Summary
                transcript = $paths.Transcript
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runnerIndexPath -Encoding UTF8

    $blockersDir = Join-Path $RunDir "live-index-check"
    $global:LASTEXITCODE = 0
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot $RunDir -FixturePath $FixturePath -BlockersDir $blockersDir -IndexFileName "weak-scenario-live-index-latest.json" -RunnerIndexPath $runnerIndexPath 2>&1 | Out-Null
    } catch {
        if ($LASTEXITCODE -eq 0) {
            $global:LASTEXITCODE = 1
        }
    }
    if ($LASTEXITCODE -eq 0) {
        Add-Failure "Codex weak proxy transcript was accepted as weak validation evidence"
    }
}

$runner = Join-Path $HarnessRoot "scripts\run-weak-scenario-suite.ps1"
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    Add-Failure "Missing weak scenario suite runner: $runner"
} elseif (-not (Test-Path -LiteralPath $SkillRoot -PathType Container)) {
    Add-Failure "Missing skill root: $SkillRoot"
} else {
    $cooperativeFixture = Join-Path $HarnessRoot "fixtures\weak-skill-scenarios.json"
    $adversarialFixture = Join-Path $HarnessRoot "fixtures\weak-adversarial-scenarios.json"
    $cooperativeOut = Join-Path $OutDir "cooperative"
    $adversarialOut = Join-Path $OutDir "adversarial"
    $cooperativeIndex = Join-Path $cooperativeOut "weak-scenario-runner-index.json"
    $adversarialIndex = Join-Path $adversarialOut "weak-adversarial-runner-index.json"

    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -FixturePath $cooperativeFixture -SkillRoot $SkillRoot -ScenarioKind scenario -OutDir $cooperativeOut -IndexPath $cooperativeIndex -DryRun
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Cooperative weak scenario suite dry run failed"
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -FixturePath $adversarialFixture -SkillRoot $SkillRoot -ScenarioKind adversarial -OutDir $adversarialOut -IndexPath $adversarialIndex -DryRun
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Adversarial weak scenario suite dry run failed"
    }

    Test-RunnerOutput -Kind "cooperative" -RunDir $cooperativeOut -IndexPath $cooperativeIndex -FixturePath $cooperativeFixture
    Test-RunnerOutput -Kind "adversarial" -RunDir $adversarialOut -IndexPath $adversarialIndex -FixturePath $adversarialFixture
    Test-LiveIndexConsumption -Kind "cooperative" -RunDir $cooperativeOut -RunnerIndexPath $cooperativeIndex -FixturePath $cooperativeFixture -IndexFileName "weak-scenario-live-index-latest.json"
    Test-LiveIndexConsumption -Kind "adversarial" -RunDir $adversarialOut -RunnerIndexPath $adversarialIndex -FixturePath $adversarialFixture -IndexFileName "weak-adversarial-live-index-latest.json"
    Test-TargetedResumeOutput -RunDir (Join-Path $OutDir "targeted-resume") -FixturePath $cooperativeFixture
    Test-FallbackWeakProxyIndex -RunDir (Join-Path $OutDir "fallback-weak-proxy") -FixturePath $cooperativeFixture
    Test-RunnerIndexContainmentRejected -RunDir (Join-Path $OutDir "runner-containment") -FixturePath $cooperativeFixture
    Test-LaunderedTranscriptHarnessRejected -RunDir (Join-Path $OutDir "laundered-transcript") -FixturePath $cooperativeFixture
    Test-QuotaExit75Index -RunDir (Join-Path $OutDir "quota-exit-75") -FixturePath $cooperativeFixture
    Test-CodexWeakProxyRejected -RunDir (Join-Path $OutDir "codex-rejected") -FixturePath $cooperativeFixture
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Weak scenario suite runner check passed."
