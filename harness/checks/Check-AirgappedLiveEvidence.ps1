param(
    [string]$EvidenceRoot = "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live",
    [string]$BlockersDir = "D:\QaaS\_tmp\zappa-dont-cry\blockers",
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

function Get-TranscriptExitCode {
    param([string]$Transcript)

    $match = [regex]::Match($Transcript, "(?m)^ExitCode:\s*(?<exit_code>-?\d+)\s*$")
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups["exit_code"].Value
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

    if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
        $name = Split-Path -Leaf $TranscriptPath
        $pathMatch = [regex]::Match($name, "-claude-copilot-(?<model>.+)\.md$")
        if ($pathMatch.Success) {
            $model = $pathMatch.Groups["model"].Value
            if ($model.StartsWith("id_")) {
                $model = "id:" + $model.Substring(3)
            }
            return $model
        }
    }

    return ""
}

function Get-TranscriptClassification {
    param(
        [string]$Transcript,
        [object]$ExitCode
    )

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

if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    Add-Failure "Missing live airgapped evidence directory: $EvidenceRoot"
} else {
    $allowedWeakModels = @(Get-AllowedWeakModels -Path $PolicyPath)
    if ($allowedWeakModels.Count -eq 0) {
        Add-Failure "Weak evidence policy does not define preferred claude-copilot airgapped models: $PolicyPath"
    }
    $summaryFiles = @(Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "*summary.md" | Sort-Object LastWriteTimeUtc -Descending)
    $latestSummaryFile = $summaryFiles | Select-Object -First 1

    if ($null -eq $latestSummaryFile) {
        Add-Failure "No live airgapped summary files found in $EvidenceRoot"
    } else {
        $latestSummary = Get-Content -LiteralPath $latestSummaryFile.FullName -Raw
        $latestPrefix = $latestSummaryFile.Name -replace "-summary\.md$", ""
        foreach ($required in @("Harness: claude-copilot", "Profile: airgapped", "DryRun: False", "Airgapped: True")) {
            if ($latestSummary -notmatch [regex]::Escape($required)) {
                Add-Failure "Live airgapped summary missing '$required': $($latestSummaryFile.FullName)"
            }
        }

        $summaryModelLine = [regex]::Match($latestSummary, "(?m)^Models:\s*(?<models>.+?)\s*$")
        if (-not $summaryModelLine.Success) {
            Add-Failure "Live airgapped summary missing Models line: $($latestSummaryFile.FullName)"
        } else {
            $summaryModels = @($summaryModelLine.Groups["models"].Value.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if (@($summaryModels | Where-Object { Test-AllowedWeakModel -Model $_ -AllowedModels $allowedWeakModels }).Count -eq 0) {
                Add-Failure "Live airgapped summary does not list any allowed weak proxy model: $($latestSummaryFile.FullName)"
            }
        }

        $records = New-Object System.Collections.Generic.List[object]
        $livePassCount = 0
        $quotaBlockedCount = 0
        $modelUnavailableCount = 0
        $unknownFailureCount = 0
        $dryRunAssemblyCount = 0
        $missingAttemptCount = 0

        foreach ($expectedModel in $allowedWeakModels) {
            $safeModel = $expectedModel.Replace(":", "_")
            $transcriptPath = Join-Path $EvidenceRoot "$latestPrefix-claude-copilot-$safeModel.md"
            $transcriptFile = if (Test-Path -LiteralPath $transcriptPath -PathType Leaf) { Get-Item -LiteralPath $transcriptPath } else { $null }

            if ($null -eq $transcriptFile) {
                $missingAttemptCount++
                $records.Add([ordered]@{
                    model = $expectedModel
                    classification = "missing_live_attempt"
                    weak_validation_eligible = $false
                    not_weak_reason = "missing_live_transcript"
                    weak_validation_passed = $false
                    transcript_exit_code = $null
                    transcript = $null
                    summary = $null
                })
                continue
            }

            $transcript = Get-Content -LiteralPath $transcriptFile.FullName -Raw
            $exitCode = Get-TranscriptExitCode -Transcript $transcript
            $model = Get-TranscriptModel -Transcript $transcript -TranscriptPath $transcriptFile.FullName
            if ([string]::IsNullOrWhiteSpace($model)) {
                $model = $expectedModel
            }
            if ($model -ne $expectedModel) {
                Add-Failure "Live airgapped transcript model '$model' does not match expected policy model '$expectedModel': $($transcriptFile.FullName)"
            }
            $classification = Get-TranscriptClassification -Transcript $transcript -ExitCode $exitCode
            $transcriptCommand = Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "Command"
            $transcriptHarness = Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "Harness"
            if ([string]::IsNullOrWhiteSpace($transcriptHarness)) {
                $transcriptHarness = "claude-copilot"
            }
            $transcriptProfile = Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "Profile"
            if ([string]::IsNullOrWhiteSpace($transcriptProfile)) {
                $transcriptProfile = "airgapped"
            }
            $eligibility = Get-WeakEvidenceEligibility -Policy $script:WeakPolicy -Harness $transcriptHarness -Profile $transcriptProfile -Model $model -DryRun:($classification -eq "dry_run_assembly") -Command $transcriptCommand -RequiredEvidenceClass @("preferred_weak")
            $passed = $false

            $prefix = $transcriptFile.Name -replace "-claude-copilot-$([regex]::Escape($safeModel))\.md$", ""
            $summaryPath = Join-Path $EvidenceRoot "$prefix-summary.md"
            $summary = ""
            if (Test-Path -LiteralPath $summaryPath -PathType Leaf) {
                $summary = Get-Content -LiteralPath $summaryPath -Raw
                if ($summary -notmatch [regex]::Escape($model)) {
                    Add-Failure "Live airgapped summary does not cite transcript model '$model': $summaryPath"
                }
            } else {
                Add-Failure "Missing live airgapped summary for transcript '$model': $($transcriptFile.FullName)"
            }

            if (-not [bool]$eligibility.weak_validation_eligible) {
                Add-Failure "Live airgapped transcript is not policy-eligible weak evidence: $model ($($eligibility.not_weak_reason))"
                $classification = "not_weak_route"
            }
            if ($classification -eq "dry_run_assembly") {
                Add-Failure "Live airgapped transcript is incorrectly marked DRY_RUN: $($transcriptFile.FullName)"
                $dryRunAssemblyCount++
            } elseif ($classification -eq "quota_blocked") {
                $quotaBlockedCount++
            } elseif ($classification -eq "model_unavailable") {
                $modelUnavailableCount++
            } elseif ($classification -eq "live_transcript_ready") {
                if ($summary -match "(?m)^- PASS exit 0: .*$([regex]::Escape($model))" -and $transcript -match "(?m)^WEAK_VALIDATOR_READY\.?\s*$") {
                    $classification = "live_model_execution_passed"
                    $passed = $true
                    $livePassCount++
                } else {
                    $classification = "live_model_execution_failed_contract"
                    $unknownFailureCount++
                    Add-Failure "Live airgapped transcript for '$model' exited 0 but did not satisfy the exact smoke contract: $($transcriptFile.FullName)"
                }
            } elseif ($classification -eq "unknown_failure") {
                $unknownFailureCount++
                Add-Failure "Live airgapped evidence for '$model' is neither quota-blocked, unavailable, nor a passing live smoke: $($transcriptFile.FullName)"
            }

            $records.Add([ordered]@{
                model = $model
                expected_model = $expectedModel
                classification = $classification
                weak_validation_eligible = [bool]$eligibility.weak_validation_eligible
                not_weak_reason = $eligibility.not_weak_reason
                evidence_class = $eligibility.evidence_class
                weak_validation_passed = $passed
                transcript_exit_code = $exitCode
                transcript = $transcriptFile.FullName
                summary = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { $summaryPath } else { $null }
            })
        }

        [System.IO.Directory]::CreateDirectory($BlockersDir) | Out-Null
        $recordPath = Join-Path $BlockersDir "airgapped-live-latest.json"
        [ordered]@{
            generated_at = (Get-Date).ToString("o")
            validation_kind = "live_model_execution"
            classification = if ($livePassCount -gt 0 -and $missingAttemptCount -eq 0 -and $quotaBlockedCount -eq 0 -and $modelUnavailableCount -eq 0 -and $unknownFailureCount -eq 0 -and $dryRunAssemblyCount -eq 0) { "live_model_execution_passed" } elseif ($quotaBlockedCount -gt 0) { "quota_blocked" } elseif ($missingAttemptCount -gt 0) { "missing_live_attempts" } elseif ($modelUnavailableCount -gt 0) { "model_unavailable" } else { "live_model_execution_not_ready" }
            weak_validation_passed = ($livePassCount -gt 0 -and $missingAttemptCount -eq 0 -and $quotaBlockedCount -eq 0 -and $modelUnavailableCount -eq 0 -and $unknownFailureCount -eq 0 -and $dryRunAssemblyCount -eq 0)
            any_weak_validation_passed = $livePassCount -gt 0
            quota_blocked = $quotaBlockedCount -gt 0
            dry_run = $false
            model = if ($records.Count -eq 1) { [string]$records[0].model } else { $null }
            models = @($records | ForEach-Object { [string]$_.model })
            expected_models = @($allowedWeakModels)
            summary = $latestSummaryFile.FullName
            transcript = if ($records.Count -eq 1) { [string]$records[0].transcript } else { $null }
            expected_model_count = $allowedWeakModels.Count
            attempted_model_count = $records.Count - $missingAttemptCount
            missing_attempt_count = $missingAttemptCount
            live_pass_count = $livePassCount
            quota_blocked_count = $quotaBlockedCount
            model_unavailable_count = $modelUnavailableCount
            dry_run_assembly_count = $dryRunAssemblyCount
            unknown_failure_count = $unknownFailureCount
            records = $records.ToArray()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding UTF8
        Write-Output "Airgapped live evidence classified."
        Write-Output "Record: $recordPath"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
