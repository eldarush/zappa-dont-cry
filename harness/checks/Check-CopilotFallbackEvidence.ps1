param(
    [string]$EvidenceRoot = "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live-copilot-fallback",
    [string]$BlockersDir = "D:\QaaS\_tmp\zappa-dont-cry\blockers",
    [string]$PolicyPath = "D:\QaaS\_tools\weak-model-policy.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\WeakEvidence.Policy.psm1") -Force
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    Add-Failure "Missing Copilot fallback evidence directory: $EvidenceRoot"
} else {
    $summaryFile = Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "*summary.md" |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($null -eq $summaryFile) {
        Add-Failure "No Copilot fallback summary files found in $EvidenceRoot"
    } else {
        $summary = Get-Content -LiteralPath $summaryFile.FullName -Raw
        foreach ($required in @("Harness: copilot", "Profile: airgapped", "ReasoningEffort: none", "DryRun: False")) {
            if ($summary -notmatch [regex]::Escape($required)) {
                Add-Failure "Copilot fallback summary missing '$required': $($summaryFile.FullName)"
            }
        }

        $weakPolicy = Read-WeakEvidencePolicy -Path $PolicyPath
        $models = @(Get-WeakEvidenceAllowedModels -Policy $weakPolicy -Harness "copilot" -Profile "airgapped" -RequiredEvidenceClass @("hosted_fallback_weak"))
        if ($models.Count -eq 0) {
            Add-Failure "Weak evidence policy does not define Copilot airgapped fallback models: $PolicyPath"
        }
        foreach ($model in $models) {
            if ($summary -notmatch [regex]::Escape($model)) {
                Add-Failure "Copilot fallback summary missing model '$model': $($summaryFile.FullName)"
            }
        }

        $prefix = $summaryFile.Name -replace "-summary\.md$", ""
        $records = New-Object System.Collections.Generic.List[object]
        $livePassCount = 0
        $quotaBlockedCount = 0
        $unavailableCount = 0

        foreach ($model in $models) {
            $transcriptFile = Get-ChildItem -LiteralPath $EvidenceRoot -File -Filter "$prefix-copilot-$model.md" |
                Select-Object -First 1
            if ($null -eq $transcriptFile) {
                Add-Failure "Missing Copilot fallback transcript for model '$model'"
                continue
            }

            $transcript = Get-Content -LiteralPath $transcriptFile.FullName -Raw
            if ($transcript -match "Command: DRY_RUN") {
                Add-Failure "Copilot fallback transcript is incorrectly marked DRY_RUN: $($transcriptFile.FullName)"
            }
            if ($transcript -notmatch [regex]::Escape("--model $model")) {
                Add-Failure "Copilot fallback transcript missing model command marker '$model': $($transcriptFile.FullName)"
            }
            $eligibility = Get-WeakEvidenceEligibility -Policy $weakPolicy -Harness "copilot" -Profile "airgapped" -Model $model -DryRun:$false -Command (Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "Command") -RequiredEvidenceClass @("hosted_fallback_weak")
            if (-not [bool]$eligibility.weak_validation_eligible) {
                Add-Failure "Copilot fallback transcript is not policy-eligible fallback weak evidence: $model ($($eligibility.not_weak_reason))"
            }

            $classification = "unknown_failure"
            $passed = $false
            if ($transcript -match "additional_spend_limit_reached" -or
                $transcript -match "additional usage limit" -or
                $transcript -match "user_weekly_rate_limited" -or
                $transcript -match "rate-limiting chat requests" -or
                $transcript -match "retry-after" -or
                $transcript -match "\b402\b" -or
                $transcript -match "(?m)^ExitCode:\s*75\s*$") {
                $classification = "quota_blocked"
                $quotaBlockedCount++
            } elseif ($transcript -match "Model `"$([regex]::Escape($model))`" from --model flag is not available") {
                $classification = "model_unavailable"
                $unavailableCount++
            } elseif ($summary -match "(?m)^- PASS exit 0: .*$([regex]::Escape($model))" -and $transcript -match "(?m)^WEAK_VALIDATOR_READY\.?\s*$") {
                $classification = "live_model_execution_passed"
                $passed = $true
                $livePassCount++
            } else {
                Add-Failure "Copilot fallback transcript for '$model' is neither unavailable, quota-blocked, nor a passing live smoke: $($transcriptFile.FullName)"
            }

            $records.Add([ordered]@{
                model = $model
                classification = $classification
                weak_validation_eligible = [bool]$eligibility.weak_validation_eligible
                evidence_class = $eligibility.evidence_class
                weak_validation_passed = $passed
                transcript = $transcriptFile.FullName
            })
        }

        [System.IO.Directory]::CreateDirectory($BlockersDir) | Out-Null
        $recordPath = Join-Path $BlockersDir "copilot-fallback-latest.json"
        [ordered]@{
            generated_at = (Get-Date).ToString("o")
            validation_kind = "fallback_live_model_execution"
            classification = if ($livePassCount -gt 0) { "fallback_live_model_execution_partially_passed" } else { "fallback_unavailable_or_quota_blocked" }
            weak_validation_passed = $livePassCount -eq $models.Count
            dry_run = $false
            summary = $summaryFile.FullName
            model_count = $models.Count
            live_pass_count = $livePassCount
            quota_blocked_count = $quotaBlockedCount
            unavailable_count = $unavailableCount
            records = $records.ToArray()
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding UTF8

        Write-Output "Copilot fallback evidence classified."
        Write-Output "Record: $recordPath"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
