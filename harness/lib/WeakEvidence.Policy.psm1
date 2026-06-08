Set-StrictMode -Version Latest

function Read-WeakEvidencePolicy {
    param([string]$Path = "D:\QaaS\_tools\weak-model-policy.json")

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Weak model policy file does not exist: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-WeakEvidenceSection {
    param([object]$Policy)

    if ($null -eq $Policy -or -not ($Policy.PSObject.Properties.Name -contains "weakEvidence")) {
        throw "Weak model policy missing weakEvidence section."
    }
    if ([int]$Policy.weakEvidence.schemaVersion -ne 1) {
        throw "Weak model policy weakEvidence.schemaVersion must be 1."
    }

    return $Policy.weakEvidence
}

function Get-WeakEvidenceAllowedModels {
    param(
        [object]$Policy,
        [string]$Harness = "claude-copilot",
        [string]$Profile = "airgapped",
        [string[]]$RequiredEvidenceClass = @()
    )

    $weakEvidence = Get-WeakEvidenceSection -Policy $Policy
    $allowProperty = $weakEvidence.allow.PSObject.Properties[$Harness]
    if (-not $allowProperty) {
        return @()
    }

    $entry = $allowProperty.Value
    if (@($entry.profiles | ForEach-Object { [string]$_ }) -notcontains $Profile) {
        return @()
    }

    if ($RequiredEvidenceClass.Count -gt 0 -and $RequiredEvidenceClass -notcontains [string]$entry.evidenceClass) {
        return @()
    }

    return @($entry.models | ForEach-Object { [string]$_ })
}

function Get-WeakTranscriptHeaderValue {
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

function Get-WeakTranscriptExitCode {
    param([string]$Transcript)

    $match = [regex]::Match($Transcript, "(?m)^ExitCode:\s*(?<exit_code>-?\d+)\s*$")
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups["exit_code"].Value
}

function Get-WeakTranscriptModel {
    param(
        [string]$Transcript,
        [string]$TranscriptPath = ""
    )

    $model = Get-WeakTranscriptHeaderValue -Transcript $Transcript -Name "Model"
    if (-not [string]::IsNullOrWhiteSpace($model)) {
        return $model
    }

    if ([string]::IsNullOrWhiteSpace($TranscriptPath)) {
        return ""
    }

    $name = Split-Path -Leaf $TranscriptPath
    $match = [regex]::Match($name, "-(?:claude-copilot|copilot)-(?<model>.+)\.md$")
    if (-not $match.Success) {
        return ""
    }

    $pathModel = $match.Groups["model"].Value
    if ($pathModel.StartsWith("id_")) {
        $pathModel = "id:" + $pathModel.Substring(3)
    }
    return $pathModel
}

function Get-WeakTranscriptClassification {
    param(
        [string]$Transcript,
        [object]$ExitCode,
        [bool]$DryRun = $false
    )

    if ([string]::IsNullOrWhiteSpace($Transcript)) {
        return "missing_transcript"
    }
    if ($DryRun -or $Transcript -match "(?m)^Command:\s*DRY_RUN\b") {
        return "dry_run_assembly"
    }
    if ($Transcript -match "additional_spend_limit_reached" -or
        $Transcript -match "additional usage limit" -or
        $Transcript -match "user_weekly_rate_limited" -or
        $Transcript -match "rate-limiting chat requests" -or
        $Transcript -match "retry-after" -or
        $Transcript -match "\b402\b" -or
        ($null -ne $ExitCode -and [int]$ExitCode -eq 75)) {
        return "quota_blocked"
    }
    if ($Transcript -match "Model `"[^`"]+`" from --model flag is not available" -or $Transcript -match "model .* is not available") {
        return "model_unavailable"
    }
    if ($null -ne $ExitCode -and [int]$ExitCode -eq 0) {
        return "live_transcript_ready"
    }
    return "unknown_failure"
}

function Get-WeakEvidenceEligibility {
    param(
        [object]$Policy,
        [string]$Harness,
        [string]$Profile,
        [string]$Model,
        [bool]$DryRun,
        [string]$Command = "",
        [string[]]$RequiredEvidenceClass = @()
    )

    $weakEvidence = Get-WeakEvidenceSection -Policy $Policy
    $reason = ""
    $evidenceClass = ""

    if ($DryRun -and $weakEvidence.dryRunAlwaysNotWeak -eq $true) {
        $reason = "dry-run-is-never-weak-evidence"
    } elseif (@($weakEvidence.denyHarnesses | ForEach-Object { [string]$_ }) -contains $Harness) {
        $reason = "harness-denied-for-weak-evidence"
    } elseif ([string]::IsNullOrWhiteSpace($Model)) {
        $reason = "model-missing"
    } else {
        foreach ($pattern in @($weakEvidence.denyModelPatterns | ForEach-Object { [string]$_ })) {
            if ($Model -match $pattern) {
                $reason = "model-denied-by-weak-evidence-policy"
                break
            }
        }
    }

    $allowProperty = $null
    if ([string]::IsNullOrWhiteSpace($reason)) {
        $allowProperty = $weakEvidence.allow.PSObject.Properties[$Harness]
        if (-not $allowProperty) {
            $reason = "harness-not-in-weak-evidence-allowlist"
        }
    }

    if ([string]::IsNullOrWhiteSpace($reason)) {
        $entry = $allowProperty.Value
        $evidenceClass = [string]$entry.evidenceClass
        if (@($entry.profiles | ForEach-Object { [string]$_ }) -notcontains $Profile) {
            $reason = "profile-not-in-weak-evidence-allowlist"
        } elseif (@($entry.models | ForEach-Object { [string]$_ }) -notcontains $Model) {
            $reason = "model-not-in-weak-evidence-allowlist"
        } elseif ($RequiredEvidenceClass.Count -gt 0 -and $RequiredEvidenceClass -notcontains $evidenceClass) {
            $reason = "evidence-class-not-accepted-for-promotion"
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$entry.requiredCommandRegex) -and -not [string]::IsNullOrWhiteSpace($Command) -and $Command -notmatch [string]$entry.requiredCommandRegex) {
            $reason = "command-does-not-match-weak-route"
        }
    }

    if ([string]::IsNullOrWhiteSpace($reason) -and -not [string]::IsNullOrWhiteSpace($Command)) {
        $forbidden = @(
            "(?i)(^|[\\/\s])codex(\.cmd|\.exe|\.ps1)?(\s|$)",
            "(?i)(^|[\\/\s])agy(\.cmd|\.exe|\.ps1)?(\s|$)"
        )
        if ($Harness -ne "copilot") {
            $forbidden += "(?i)(^|[\\/\s])copilot(\.cmd|\.exe|\.ps1)?(\s|$)"
        }
        foreach ($pattern in $forbidden) {
            if ($Command -match $pattern) {
                $reason = "command-uses-ineligible-hosted-route"
                break
            }
        }
    }

    $eligible = [string]::IsNullOrWhiteSpace($reason)
    [pscustomobject]@{
        weak_validation_eligible = $eligible
        evidence_class = $evidenceClass
        eligibility_source = "weakEvidence.allow"
        not_weak_reason = if ($eligible) { $null } else { $reason }
    }
}

function Test-WeakEvidenceEligible {
    param(
        [object]$Policy,
        [string]$Harness,
        [string]$Profile,
        [string]$Model,
        [bool]$DryRun,
        [string]$Command = "",
        [string[]]$RequiredEvidenceClass = @()
    )

    $result = Get-WeakEvidenceEligibility -Policy $Policy -Harness $Harness -Profile $Profile -Model $Model -DryRun:$DryRun -Command $Command -RequiredEvidenceClass $RequiredEvidenceClass
    return [bool]$result.weak_validation_eligible
}

Export-ModuleMember -Function @(
    "Read-WeakEvidencePolicy",
    "Get-WeakEvidenceSection",
    "Get-WeakEvidenceAllowedModels",
    "Get-WeakTranscriptHeaderValue",
    "Get-WeakTranscriptExitCode",
    "Get-WeakTranscriptModel",
    "Get-WeakTranscriptClassification",
    "Get-WeakEvidenceEligibility",
    "Test-WeakEvidenceEligible"
)
