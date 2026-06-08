param(
    [string]$EvidenceRoot = "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live-scenarios",
    [string]$FixturePath = "D:\QaaS\_tools\zappa-harness\fixtures\weak-skill-scenarios.json",
    [string]$BlockersDir = "D:\QaaS\_tmp\zappa-dont-cry\blockers",
    [string]$IndexFileName = "weak-scenario-live-index-latest.json",
    [string]$RunnerIndexPath = "",
    [string]$PolicyPath = "D:\QaaS\_tools\weak-model-policy.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\WeakEvidence.Policy.psm1") -Force
$failures = New-Object System.Collections.Generic.List[string]
$script:WeakPolicy = $null

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
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

function Get-TranscriptExitCode {
    param([string]$Transcript)

    $match = [regex]::Match($Transcript, "(?m)^ExitCode:\s*(?<exit_code>-?\d+)\s*$")
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups["exit_code"].Value
}

function Get-ScenarioClassification {
    param(
        [string]$Transcript,
        [object]$ExitCode
    )

    if ([string]::IsNullOrWhiteSpace($Transcript)) {
        return "missing_transcript"
    }
    if ($Transcript -match "(?m)^Command:\s*DRY_RUN\b" -or $Transcript -match "(?m)^DryRun:\s*True\s*$") {
        return "dry_run_assembly"
    }
    if ($Transcript -match "additional_spend_limit_reached" -or
        $Transcript -match "additional usage limit" -or
        $Transcript -match "user_weekly_rate_limited" -or
        $Transcript -match "rate-limiting chat requests" -or
        $Transcript -match "retry-after" -or
        $Transcript -match "\b402\b" -or
        ($null -ne $ExitCode -and $ExitCode -eq 75)) {
        return "quota_blocked"
    }
    if ($Transcript -match "Model `"[^`"]+`" from --model flag is not available" -or $Transcript -match "model .* is not available") {
        return "model_unavailable"
    }
    if ($null -ne $ExitCode -and $ExitCode -eq 0) {
        return "live_transcript_ready"
    }
    return "unknown_failure"
}

function Get-SummaryForTranscript {
    param(
        [string]$TranscriptPath,
        [object[]]$SummaryFiles
    )

    $name = Split-Path -Leaf $TranscriptPath
    $prefix = $name -replace "-claude-copilot-.+\.md$", ""
    $summaryName = "$prefix-summary.md"
    $summary = @($SummaryFiles | Where-Object { $_.Name -eq $summaryName } | Select-Object -First 1)
    if ($summary.Count -eq 0) {
        return $null
    }
    return $summary[0].FullName
}

function Get-AllowedWeakModels {
    param([string]$Path)

    try {
        $script:WeakPolicy = Read-WeakEvidencePolicy -Path $Path
        return @(Get-WeakEvidenceAllowedModels -Policy $script:WeakPolicy -Harness "claude-copilot" -Profile "airgapped" -RequiredEvidenceClass @("preferred_weak"))
    } catch {
        Add-Failure "Weak model policy file does not exist: $Path"
        return @("id:gpt-3.5-turbo")
    }
}

function Test-AllowedWeakModel {
    param(
        [string]$Model,
        [string[]]$AllowedModels
    )

    if ([string]::IsNullOrWhiteSpace($Model)) {
        return $false
    }
    if ($Model -match "opus" -or $Model -match "sonnet" -or $Model -match "haiku" -or $Model -match "^claude-") {
        return $false
    }

    return $AllowedModels -contains $Model
}

function Get-TranscriptModelFromPath {
    param([string]$TranscriptPath)

    if ([string]::IsNullOrWhiteSpace($TranscriptPath)) {
        return ""
    }

    $name = Split-Path -Leaf $TranscriptPath
    $match = [regex]::Match($name, "-claude-copilot-(?<model>.+)\.md$")
    if (-not $match.Success) {
        return ""
    }

    $model = $match.Groups["model"].Value
    if ($model.StartsWith("id_")) {
        $model = "id:" + $model.Substring(3)
    }

    return $model
}

function Get-TranscriptModel {
    param(
        [string]$Transcript,
        [string]$TranscriptPath = ""
    )

    $match = [regex]::Match($Transcript, "(?m)^Model:\s*(?<model>.+?)\s*$")
    if ($match.Success) {
        return $match.Groups["model"].Value.Trim()
    }

    $pathModel = Get-TranscriptModelFromPath -TranscriptPath $TranscriptPath
    if ($pathModel) {
        return $pathModel
    }

    foreach ($candidate in @(Get-AllowedWeakModels -Path $PolicyPath)) {
        if ($Transcript -match [regex]::Escape($candidate)) {
            return $candidate
        }
    }

    return ""
}

function Get-TranscriptHeaderValue {
    param(
        [string]$Transcript,
        [string]$Name
    )

    $match = [regex]::Match($Transcript, "(?m)^$([regex]::Escape($Name)):\s*(?<value>.+?)\s*$")
    if (-not $match.Success) {
        return ""
    }

    return $match.Groups["value"].Value.Trim()
}

function Test-PathUnderRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }

    $rootFullPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $pathFullPath = [System.IO.Path]::GetFullPath($Path)
    return $pathFullPath.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)
}

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

function Test-ScenarioSummary {
    param(
        [string]$ScenarioId,
        [string]$SummaryPath,
        [bool]$DryRun,
        [string]$Model
    )

    if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
        return
    }
    if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
        Add-Failure "$ScenarioId summary path does not exist: $SummaryPath"
        return
    }

    $summary = Get-Content -LiteralPath $SummaryPath -Raw
    $required = @("Harness: claude-copilot", "Profile: airgapped", "Models: $Model", "Airgapped: True")
    $required += if ($DryRun) { "DryRun: True" } else { "DryRun: False" }
    foreach ($text in $required) {
        if ($summary -notmatch [regex]::Escape($text)) {
            Add-Failure "$ScenarioId summary missing '$text': $SummaryPath"
        }
    }
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    Add-Failure "Missing weak scenario fixture: $FixturePath"
}
if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    Add-Failure "Missing live weak scenario evidence directory: $EvidenceRoot"
}

if ($failures.Count -eq 0) {
    $allowedWeakModels = @(Get-AllowedWeakModels -Path $PolicyPath)
    $fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    $validationKind = [string]$fixture.live_validation_kind
    if ([string]::IsNullOrWhiteSpace($validationKind)) {
        Add-Failure "Fixture must define live_validation_kind: $FixturePath"
    }

    $summaryFiles = @(Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "*summary.md" -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    $transcriptFiles = @(Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "*claude-copilot-*.md" -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    $runnerIndexWasProvided = -not [string]::IsNullOrWhiteSpace($RunnerIndexPath)
    if (-not $runnerIndexWasProvided) {
        $runnerIndexFileName = if ($validationKind -eq "live_adversarial_model_execution") { "weak-adversarial-runner-index.json" } else { "weak-scenario-runner-index.json" }
        $candidateRunnerIndex = Join-Path $EvidenceRoot $runnerIndexFileName
        if (Test-Path -LiteralPath $candidateRunnerIndex -PathType Leaf) {
            $RunnerIndexPath = $candidateRunnerIndex
        }
    }

    $runnerRecordCount = 0
    $runnerRecordedCount = 0
    $runnerRecordsByScenario = @{}
    if (-not [string]::IsNullOrWhiteSpace($RunnerIndexPath)) {
        if (-not (Test-Path -LiteralPath $RunnerIndexPath -PathType Leaf)) {
            Add-Failure "Runner index path was provided but does not exist: $RunnerIndexPath"
        } else {
            $runnerIndex = Get-Content -LiteralPath $RunnerIndexPath -Raw | ConvertFrom-Json
            foreach ($runnerRecord in @($runnerIndex.records)) {
                $runnerRecordCount++
                $runnerScenarioId = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "scenario_id")
                if ([string]::IsNullOrWhiteSpace($runnerScenarioId)) {
                    Add-Failure "Runner index has a record without scenario_id: $RunnerIndexPath"
                    continue
                }
                if ($runnerRecordsByScenario.ContainsKey($runnerScenarioId)) {
                    $runnerRecordsByScenario[$runnerScenarioId] = @($runnerRecordsByScenario[$runnerScenarioId]) + @($runnerRecord)
                } else {
                    $runnerRecordsByScenario[$runnerScenarioId] = @($runnerRecord)
                }
            }
        }
    }

    $records = New-Object System.Collections.Generic.List[object]

    $quotaBlockedCount = 0
    $modelUnavailableCount = 0
    $dryRunAssemblyCount = 0
    $missingTranscriptCount = 0
    $liveReadyCount = 0
    $unknownFailureCount = 0

    foreach ($scenario in @($fixture.scenarios)) {
        $scenarioId = [string]$scenario.scenario_id
        $skill = [string]$scenario.skill
        $prompt = [string]$scenario.prompt
        if ([string]::IsNullOrWhiteSpace($scenarioId)) {
            Add-Failure "Scenario missing scenario_id in $FixturePath"
            continue
        }
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            Add-Failure "$scenarioId missing prompt in $FixturePath"
            continue
        }

        $promptHash = Get-Sha256 -Text $prompt
        $transcriptPath = $null
        $summaryPath = $null
        $transcriptExitCode = $null
        $dryRun = $false
        $classification = "missing_transcript"
        $matchStatus = "missing_transcript"

        $runnerRecordsForScenario = @()
        $runnerRecord = $null
        if ($runnerRecordsByScenario.ContainsKey($scenarioId)) {
            $runnerRecordsForScenario = @($runnerRecordsByScenario[$scenarioId])
            $runnerRecord = $runnerRecordsForScenario[0]
        }

        if ($null -ne $runnerRecord) {
            $runnerRecordedCount++
            $matchStatus = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "match_status")
            $transcriptPath = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "transcript")
            $summaryPath = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "summary")
            $classification = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "classification" -DefaultValue "missing_transcript")
            $dryRun = [bool](Get-ObjectValue -Object $runnerRecord -PropertyName "dry_run" -DefaultValue $false)
            $transcriptExitCodeValue = Get-ObjectValue -Object $runnerRecord -PropertyName "transcript_exit_code"
            if ($null -ne $transcriptExitCodeValue -and -not [string]::IsNullOrWhiteSpace([string]$transcriptExitCodeValue)) {
                $transcriptExitCode = [int]$transcriptExitCodeValue
            }

            $runnerPromptHash = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "prompt_hash_sha256")
            if ($runnerPromptHash -ne $promptHash) {
                Add-Failure "$scenarioId runner prompt hash mismatch in $RunnerIndexPath"
            }
            if ($matchStatus -ne "runner_recorded") {
                Add-Failure "$scenarioId runner index match_status is not runner_recorded: $matchStatus"
            }
            $runnerHarness = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "harness")
            $runnerProfile = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "profile")
            if ($runnerHarness -ne "claude-copilot") {
                Add-Failure "$scenarioId runner index harness is not claude-copilot"
            }
            if ($runnerProfile -ne "airgapped") {
                Add-Failure "$scenarioId runner index profile is not airgapped"
            }
            $runnerModel = [string](Get-ObjectValue -Object $runnerRecord -PropertyName "model")
            $runnerEligibility = Get-WeakEvidenceEligibility -Policy $script:WeakPolicy -Harness $runnerHarness -Profile $runnerProfile -Model $runnerModel -DryRun:$dryRun -RequiredEvidenceClass @("preferred_weak")
            if (-not [bool]$runnerEligibility.weak_validation_eligible -and -not $dryRun) {
                Add-Failure "$scenarioId runner index model is not policy-eligible weak evidence: $runnerModel ($($runnerEligibility.not_weak_reason))"
            }
            if (($runnerRecord.PSObject.Properties.Name -contains "weak_validation_eligible") -and [bool]$runnerRecord.weak_validation_eligible -ne [bool]$runnerEligibility.weak_validation_eligible) {
                Add-Failure "$scenarioId runner index weak_validation_eligible does not match policy: $runnerModel"
            }
            if (($runnerRecord.PSObject.Properties.Name -contains "not_weak_reason") -and [bool]$runnerEligibility.weak_validation_eligible -and -not [string]::IsNullOrWhiteSpace([string]$runnerRecord.not_weak_reason)) {
                Add-Failure "$scenarioId runner index must not carry not_weak_reason for allowed weak proxy: $runnerModel"
            }
            if (-not [string]::IsNullOrWhiteSpace($summaryPath) -and -not (Test-PathUnderRoot -Path $summaryPath -Root $EvidenceRoot)) {
                Add-Failure "$scenarioId summary must be under EvidenceRoot: $summaryPath"
            }
            if (-not [string]::IsNullOrWhiteSpace($transcriptPath) -and -not (Test-PathUnderRoot -Path $transcriptPath -Root $EvidenceRoot)) {
                Add-Failure "$scenarioId transcript must be under EvidenceRoot: $transcriptPath"
            }

            if ([string]::IsNullOrWhiteSpace($transcriptPath) -or -not (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) {
                $classification = "missing_transcript"
                $missingTranscriptCount++
            } else {
                $transcript = Get-Content -LiteralPath $transcriptPath -Raw
                $transcriptDryRun = $transcript -match "(?m)^Command:\s*DRY_RUN\b" -or $transcript -match "(?m)^DryRun:\s*True\s*$"
                if ($transcriptDryRun -ne $dryRun) {
                    Add-Failure "$scenarioId runner dry_run does not match transcript: $transcriptPath"
                }
                if ($transcript -notmatch [regex]::Escape("ScenarioId: $scenarioId")) {
                    Add-Failure "$scenarioId transcript missing scenario id marker: $transcriptPath"
                }
                if ($transcript -notmatch [regex]::Escape("PromptHashSha256: $promptHash")) {
                    Add-Failure "$scenarioId transcript missing prompt hash marker: $transcriptPath"
                }
                $transcriptHarness = Get-TranscriptHeaderValue -Transcript $transcript -Name "Harness"
                if ($transcriptHarness -and $transcriptHarness -ne "claude-copilot") {
                    Add-Failure "$scenarioId transcript harness is not claude-copilot: $transcriptHarness"
                } elseif (-not $transcriptHarness -and (Split-Path -Leaf $transcriptPath) -notmatch "-claude-copilot-") {
                    Add-Failure "$scenarioId transcript path does not identify claude-copilot route: $transcriptPath"
                }
                $transcriptProfile = Get-TranscriptHeaderValue -Transcript $transcript -Name "Profile"
                if (-not $dryRun -and $transcriptProfile -and $transcriptProfile -ne "airgapped") {
                    Add-Failure "$scenarioId transcript profile is not airgapped: $transcriptProfile"
                }
                $transcriptCommand = Get-TranscriptHeaderValue -Transcript $transcript -Name "Command"
                if (-not $dryRun -and ($transcriptCommand -match "(?i)(^|[\\\s])codex(\.cmd|\.exe)?\s" -or $transcriptCommand -match "(?i)(^|[\\\s])agy(\.cmd|\.exe)?\s" -or $transcriptCommand -match "(?i)(^|[\\\s])copilot(\.cmd|\.exe)?\s")) {
                    Add-Failure "$scenarioId transcript command is not a claude-copilot weak route: $transcriptPath"
                }
                $transcriptModel = Get-TranscriptModel -Transcript $transcript -TranscriptPath $transcriptPath
                $transcriptEligibility = Get-WeakEvidenceEligibility -Policy $script:WeakPolicy -Harness $(if ($transcriptHarness) { $transcriptHarness } else { "claude-copilot" }) -Profile $(if ($transcriptProfile) { $transcriptProfile } else { "airgapped" }) -Model $transcriptModel -DryRun:$dryRun -Command $transcriptCommand -RequiredEvidenceClass @("preferred_weak")
                if (-not $dryRun -and $transcriptModel -ne $runnerModel) {
                    Add-Failure "$scenarioId transcript model '$transcriptModel' does not match runner model '$runnerModel': $transcriptPath"
                }
                if (-not $dryRun -and -not [bool]$transcriptEligibility.weak_validation_eligible) {
                    Add-Failure "$scenarioId transcript is not policy-eligible weak evidence: $transcriptModel ($($transcriptEligibility.not_weak_reason))"
                }
                $transcriptClassification = Get-ScenarioClassification -Transcript $transcript -ExitCode $transcriptExitCode
                if ($classification -ne $transcriptClassification) {
                    Add-Failure "$scenarioId runner classification '$classification' does not match transcript classification '$transcriptClassification'"
                }
                Test-ScenarioSummary -ScenarioId $scenarioId -SummaryPath $summaryPath -DryRun $dryRun -Model $runnerModel
                switch ($classification) {
                    "quota_blocked" { $quotaBlockedCount++ }
                    "model_unavailable" { $modelUnavailableCount++ }
                    "dry_run_assembly" { $dryRunAssemblyCount++ }
                    "live_transcript_ready" { $liveReadyCount++ }
                    "unknown_failure" { $unknownFailureCount++ }
                    "missing_transcript" { }
                    default { $unknownFailureCount++ }
                }
            }
        } else {
            $matchedTranscript = @($transcriptFiles | Where-Object {
                $candidateText = Get-Content -LiteralPath $_.FullName -Raw
                $candidateText -match [regex]::Escape($prompt)
            } | Select-Object -First 1)

            if ($matchedTranscript.Count -eq 0) {
                $missingTranscriptCount++
            } else {
                $transcriptPath = $matchedTranscript[0].FullName
                $summaryPath = Get-SummaryForTranscript -TranscriptPath $transcriptPath -SummaryFiles $summaryFiles
                $matchStatus = "exact_prompt_match"
                $transcript = Get-Content -LiteralPath $transcriptPath -Raw
                $transcriptExitCode = Get-TranscriptExitCode -Transcript $transcript
                $dryRun = $transcript -match "(?m)^Command:\s*DRY_RUN\b" -or $transcript -match "(?m)^DryRun:\s*True\s*$"
                $transcriptModel = Get-TranscriptModel -Transcript $transcript -TranscriptPath $transcriptPath
                $transcriptHarness = Get-TranscriptHeaderValue -Transcript $transcript -Name "Harness"
                if ($transcriptHarness -and $transcriptHarness -ne "claude-copilot") {
                    Add-Failure "$scenarioId transcript harness is not claude-copilot: $transcriptHarness"
                } elseif (-not $transcriptHarness -and (Split-Path -Leaf $transcriptPath) -notmatch "-claude-copilot-") {
                    Add-Failure "$scenarioId transcript path does not identify claude-copilot route: $transcriptPath"
                }
                $transcriptProfile = Get-TranscriptHeaderValue -Transcript $transcript -Name "Profile"
                if (-not $dryRun -and $transcriptProfile -and $transcriptProfile -ne "airgapped") {
                    Add-Failure "$scenarioId transcript profile is not airgapped: $transcriptProfile"
                }
                $transcriptCommand = Get-TranscriptHeaderValue -Transcript $transcript -Name "Command"
                $transcriptEligibility = Get-WeakEvidenceEligibility -Policy $script:WeakPolicy -Harness $(if ($transcriptHarness) { $transcriptHarness } else { "claude-copilot" }) -Profile $(if ($transcriptProfile) { $transcriptProfile } else { "airgapped" }) -Model $transcriptModel -DryRun:$dryRun -Command $transcriptCommand -RequiredEvidenceClass @("preferred_weak")
                if (-not $dryRun -and -not [bool]$transcriptEligibility.weak_validation_eligible) {
                    Add-Failure "$scenarioId transcript is not policy-eligible weak evidence: $transcriptModel ($($transcriptEligibility.not_weak_reason))"
                }
                Test-ScenarioSummary -ScenarioId $scenarioId -SummaryPath $summaryPath -DryRun $dryRun -Model $transcriptModel
                $classification = Get-ScenarioClassification -Transcript $transcript -ExitCode $transcriptExitCode
                switch ($classification) {
                    "quota_blocked" { $quotaBlockedCount++ }
                    "model_unavailable" { $modelUnavailableCount++ }
                    "dry_run_assembly" { $dryRunAssemblyCount++ }
                    "live_transcript_ready" { $liveReadyCount++ }
                    "unknown_failure" { $unknownFailureCount++ }
                }
            }
        }

        $attempts = New-Object System.Collections.Generic.List[object]
        foreach ($attemptRecord in @($runnerRecordsForScenario)) {
            $attemptModel = [string](Get-ObjectValue -Object $attemptRecord -PropertyName "model")
            $attemptDryRun = [bool](Get-ObjectValue -Object $attemptRecord -PropertyName "dry_run" -DefaultValue $false)
            $attemptTranscript = [string](Get-ObjectValue -Object $attemptRecord -PropertyName "transcript")
            $attemptSummary = [string](Get-ObjectValue -Object $attemptRecord -PropertyName "summary")
            $attemptClassification = [string](Get-ObjectValue -Object $attemptRecord -PropertyName "classification" -DefaultValue "missing_transcript")
            $attemptExitCode = Get-ObjectValue -Object $attemptRecord -PropertyName "transcript_exit_code"
            $attemptEligibility = Get-WeakEvidenceEligibility -Policy $script:WeakPolicy -Harness "claude-copilot" -Profile "airgapped" -Model $attemptModel -DryRun:$attemptDryRun -RequiredEvidenceClass @("preferred_weak")
            $attempts.Add([ordered]@{
                model = $attemptModel
                dry_run = $attemptDryRun
                classification = $attemptClassification
                weak_validation_eligible = [bool]$attemptEligibility.weak_validation_eligible
                not_weak_reason = if ([bool]$attemptEligibility.weak_validation_eligible) { $null } else { $attemptEligibility.not_weak_reason }
                transcript_exit_code = $attemptExitCode
                summary = $attemptSummary
                transcript = $attemptTranscript
            })
        }
        if ($attempts.Count -eq 0 -and $transcriptPath) {
            $attemptModel = if (Test-Path -LiteralPath $transcriptPath -PathType Leaf) { Get-TranscriptModel -Transcript (Get-Content -LiteralPath $transcriptPath -Raw) -TranscriptPath $transcriptPath } else { "" }
            $attemptEligibility = Get-WeakEvidenceEligibility -Policy $script:WeakPolicy -Harness "claude-copilot" -Profile "airgapped" -Model $attemptModel -DryRun:$dryRun -RequiredEvidenceClass @("preferred_weak")
            $attempts.Add([ordered]@{
                model = $attemptModel
                dry_run = $dryRun
                classification = $classification
                weak_validation_eligible = [bool]$attemptEligibility.weak_validation_eligible
                not_weak_reason = if ([bool]$attemptEligibility.weak_validation_eligible) { $null } else { $attemptEligibility.not_weak_reason }
                transcript_exit_code = $transcriptExitCode
                summary = $summaryPath
                transcript = $transcriptPath
            })
        }

        $attemptModels = @($attempts | ForEach-Object { [string]$_["model"] } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $missingPreferredModels = @($allowedWeakModels | Where-Object { $attemptModels -notcontains $_ })
        $allPreferredModelsPresent = $missingPreferredModels.Count -eq 0
        $livePreferredAttemptCount = @($attempts | Where-Object { [string]$_["classification"] -eq "live_transcript_ready" -and $_["dry_run"] -eq $false -and $allowedWeakModels -contains [string]$_["model"] }).Count
        if ($attempts.Count -gt 1 -or $missingPreferredModels.Count -gt 0) {
            $attemptClassifications = @($attempts | ForEach-Object { [string]$_["classification"] })
            if ($attemptClassifications -contains "quota_blocked") {
                $classification = "quota_blocked"
            } elseif ($attemptClassifications -contains "model_unavailable") {
                $classification = "model_unavailable"
            } elseif ($attemptClassifications -contains "dry_run_assembly") {
                $classification = "dry_run_assembly"
            } elseif (-not $allPreferredModelsPresent) {
                $classification = "missing_preferred_models"
            } elseif ($livePreferredAttemptCount -eq $allowedWeakModels.Count) {
                $classification = "live_transcript_ready"
            } else {
                $classification = "unknown_failure"
            }
            if ($attempts.Count -ne 1) {
                $transcriptPath = $null
                $summaryPath = $null
                $transcriptExitCode = $null
            }
        }

        $recordModel = if ($attemptModels.Count -eq 1) { [string]$attemptModels[0] } elseif ($attemptModels.Count -gt 1) { $attemptModels -join ", " } elseif ($runnerRecord) { [string](Get-ObjectValue -Object $runnerRecord -PropertyName "model") } elseif ($transcriptPath -and (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) { Get-TranscriptModel -Transcript (Get-Content -LiteralPath $transcriptPath -Raw) -TranscriptPath $transcriptPath } else { "id:gpt-3.5-turbo" }
        $recordEligibility = Get-WeakEvidenceEligibility -Policy $script:WeakPolicy -Harness "claude-copilot" -Profile "airgapped" -Model $recordModel -DryRun:$dryRun -RequiredEvidenceClass @("preferred_weak")
        $recordWeakEligible = [bool]$recordEligibility.weak_validation_eligible
        $record = [ordered]@{
            scenario_id = $scenarioId
            skill = $skill
            risk_category = if ($scenario.PSObject.Properties.Name -contains "risk_category") { [string]$scenario.risk_category } else { $null }
            prompt_hash_sha256 = $promptHash
            prompt_length = $prompt.Length
            match_status = $matchStatus
            validation_kind = $validationKind
            harness = "claude-copilot"
            model = $recordModel
            dry_run = $dryRun
            classification = $classification
            weak_validation_eligible = $recordWeakEligible
            not_weak_reason = if ($recordWeakEligible) { $null } else { $recordEligibility.not_weak_reason }
            weak_validation_passed = $false
            transcript_exit_code = $transcriptExitCode
            summary = $summaryPath
            transcript = $transcriptPath
            expected_models = @($allowedWeakModels)
            attempted_models = @($attemptModels)
            missing_models = @($missingPreferredModels)
            expected_model_count = $allowedWeakModels.Count
            attempted_model_count = $attemptModels.Count
            missing_model_count = $missingPreferredModels.Count
            all_preferred_models_present = $allPreferredModelsPresent
            all_preferred_models_live_ready = ($allPreferredModelsPresent -and $livePreferredAttemptCount -eq $allowedWeakModels.Count)
            attempts = $attempts.ToArray()
        }
        $records.Add($record)
    }

    $liveReadyCount = @($records | Where-Object { [string]$_["classification"] -eq "live_transcript_ready" }).Count
    $quotaBlockedCount = @($records | Where-Object { [string]$_["classification"] -eq "quota_blocked" }).Count
    $modelUnavailableCount = @($records | Where-Object { [string]$_["classification"] -eq "model_unavailable" }).Count
    $dryRunAssemblyCount = @($records | Where-Object { [string]$_["classification"] -eq "dry_run_assembly" }).Count
    $missingTranscriptCount = @($records | Where-Object { [string]$_["classification"] -in @("missing_transcript", "missing_preferred_models") }).Count
    $unknownFailureCount = @($records | Where-Object { [string]$_["classification"] -eq "unknown_failure" }).Count

    [System.IO.Directory]::CreateDirectory($BlockersDir) | Out-Null
    $indexPath = Join-Path $BlockersDir $IndexFileName
    $scenarioCount = @($fixture.scenarios).Count
    [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        validation_kind = $validationKind
        evidence_root = $EvidenceRoot
        fixture = $FixturePath
        required_scenario_count = $scenarioCount
        indexed_scenario_count = $records.Count
        transcript_file_count = $transcriptFiles.Count
        summary_file_count = $summaryFiles.Count
        runner_index = if ([string]::IsNullOrWhiteSpace($RunnerIndexPath)) { $null } else { $RunnerIndexPath }
        runner_record_count = $runnerRecordCount
        runner_recorded_count = $runnerRecordedCount
        live_ready_count = $liveReadyCount
        quota_blocked_count = $quotaBlockedCount
        model_unavailable_count = $modelUnavailableCount
        dry_run_assembly_count = $dryRunAssemblyCount
        missing_transcript_count = $missingTranscriptCount
        unknown_failure_count = $unknownFailureCount
        weak_validation_passed = $false
        index_status = if ($liveReadyCount -eq $scenarioCount) { "all_transcripts_ready_for_contract_scoring" } elseif ($quotaBlockedCount -gt 0) { "quota_blocked" } else { "incomplete" }
        records = $records.ToArray()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $indexPath -Encoding UTF8
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Weak-model live scenario index check passed."
Write-Output "Index: $indexPath"
