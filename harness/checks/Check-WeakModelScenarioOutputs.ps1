param(
    [string]$EvidenceRoot = "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live-scenarios",
    [string]$FixturePath = "D:\QaaS\_tools\zappa-harness\fixtures\weak-skill-scenarios.json",
    [string]$SkillContractsPath = "D:\QaaS\_tools\zappa-harness\fixtures\skill-output-contracts.json",
    [string]$BlockersDir = "D:\QaaS\_tmp\zappa-dont-cry\blockers",
    [string]$IndexPath = "D:\QaaS\_tmp\zappa-dont-cry\blockers\weak-scenario-live-index-latest.json",
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

function Get-TranscriptStdout {
    param([string]$Transcript)

    $match = [regex]::Match($Transcript, "(?s)## stdout\r?\n(?<stdout>.*?)(\r?\n## stderr|\z)")
    if (-not $match.Success) {
        return ""
    }

    return $match.Groups["stdout"].Value.Trim()
}

function Get-StringList {
    param(
        [object]$Object,
        [string]$PropertyName
    )

    if (-not ($Object.PSObject.Properties.Name -contains $PropertyName)) {
        return @()
    }

    return @($Object.$PropertyName | ForEach-Object { [string]$_ })
}

function Get-AnyTermGroups {
    param([object]$Object)

    if (-not ($Object.PSObject.Properties.Name -contains "required_any_term_groups")) {
        return @()
    }

    $groups = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($Object.required_any_term_groups)) {
        $terms = @($group | ForEach-Object { [string]$_ })
        if ($terms.Count -gt 0) {
            $groups.Add($terms)
        }
    }
    return $groups.ToArray()
}

function Test-LiveOutputAttempt {
    param(
        [string]$ScenarioId,
        [object]$Scenario,
        [string]$ScenarioSkill,
        [object]$AttemptRecord,
        [object]$WeakPolicy,
        [hashtable]$ContractBySkill,
        [hashtable]$ContractAnyGroupsBySkill
    )

    $missingTerms = @()
    $missingAnyTermGroups = @()
    $rejectedTermsMatched = @()
    $transcriptPath = [string]$AttemptRecord.transcript
    $classification = [string]$AttemptRecord.classification
    $transcriptExitCode = $AttemptRecord.transcript_exit_code
    $recordDryRun = if ($AttemptRecord.PSObject.Properties.Name -contains "dry_run") { [bool]$AttemptRecord.dry_run } else { $true }
    $recordEligible = if ($AttemptRecord.PSObject.Properties.Name -contains "weak_validation_eligible") { [bool]$AttemptRecord.weak_validation_eligible } else { $false }

    if ([string]::IsNullOrWhiteSpace($transcriptPath) -or -not (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) {
        if (-not [string]::IsNullOrWhiteSpace($transcriptPath)) {
            Add-Failure "Indexed weak scenario transcript does not exist: $transcriptPath"
        }
        return [pscustomobject]@{ passed = $false; classification = "missing_transcript"; transcript = $transcriptPath; transcript_exit_code = $transcriptExitCode; missing_output_terms = @(); missing_any_term_groups = @(); rejected_terms_matched = @() }
    }
    if ($classification -ne "live_transcript_ready") {
        return [pscustomobject]@{ passed = $false; classification = $classification; transcript = $transcriptPath; transcript_exit_code = $transcriptExitCode; missing_output_terms = @(); missing_any_term_groups = @(); rejected_terms_matched = @() }
    }

    if ($recordDryRun -ne $false) {
        Add-Failure "$ScenarioId live transcript record is marked dry_run"
    }
    if ($recordEligible -ne $true) {
        Add-Failure "$ScenarioId live transcript record is not weak-validation eligible"
    }
    $transcript = Get-Content -LiteralPath $transcriptPath -Raw
    $transcriptDryRun = ($transcript -match "(?m)^Command:\s*DRY_RUN\b") -or ([string](Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "DryRun") -match "^(?i:true)$")
    if ($transcriptDryRun) {
        Add-Failure "$ScenarioId live transcript header is marked DryRun"
    }
    $transcriptHarness = Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "Harness"
    if ([string]::IsNullOrWhiteSpace($transcriptHarness)) {
        $transcriptHarness = "claude-copilot"
    }
    $transcriptProfile = Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "Profile"
    if ([string]::IsNullOrWhiteSpace($transcriptProfile)) {
        $transcriptProfile = "airgapped"
    }
    $transcriptModel = Get-WeakTranscriptModel -Transcript $transcript -TranscriptPath $transcriptPath
    $transcriptCommand = Get-WeakTranscriptHeaderValue -Transcript $transcript -Name "Command"
    $effectiveDryRun = $recordDryRun -or $transcriptDryRun
    $policyEligibility = Get-WeakEvidenceEligibility -Policy $WeakPolicy -Harness $transcriptHarness -Profile $transcriptProfile -Model $transcriptModel -DryRun:$effectiveDryRun -Command $transcriptCommand -RequiredEvidenceClass @("preferred_weak")
    if (-not [bool]$policyEligibility.weak_validation_eligible) {
        Add-Failure "$ScenarioId live transcript is not policy-eligible weak evidence: $transcriptModel ($($policyEligibility.not_weak_reason))"
    }
    if ($recordEligible -ne [bool]$policyEligibility.weak_validation_eligible) {
        Add-Failure "$ScenarioId indexed weak_validation_eligible does not match policy"
    }

    $stdout = Get-TranscriptStdout -Transcript $transcript
    $expectedTerms = New-Object System.Collections.Generic.List[string]
    foreach ($term in @(Get-StringList -Object $Scenario -PropertyName "expected_terms")) {
        $expectedTerms.Add($term)
    }
    foreach ($term in @(Get-StringList -Object $Scenario -PropertyName "required_all_terms")) {
        $expectedTerms.Add($term)
    }
    if (-not [string]::IsNullOrWhiteSpace($ScenarioSkill) -and $ContractBySkill.ContainsKey($ScenarioSkill)) {
        foreach ($term in @($ContractBySkill[$ScenarioSkill])) {
            $expectedTerms.Add($term)
        }
    }
    foreach ($term in $expectedTerms) {
        if ($stdout -notmatch [regex]::Escape($term)) {
            $missingTerms += $term
        }
    }
    foreach ($group in @(Get-AnyTermGroups -Object $Scenario)) {
        $matchedAny = $false
        foreach ($term in @($group)) {
            if ($stdout -match [regex]::Escape($term)) {
                $matchedAny = $true
                break
            }
        }
        if (-not $matchedAny) {
            $missingAnyTermGroups += ,@($group)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ScenarioSkill) -and $ContractAnyGroupsBySkill.ContainsKey($ScenarioSkill)) {
        foreach ($group in @($ContractAnyGroupsBySkill[$ScenarioSkill])) {
            $matchedAny = $false
            foreach ($term in @($group)) {
                if ($stdout -match [regex]::Escape($term)) {
                    $matchedAny = $true
                    break
                }
            }
            if (-not $matchedAny) {
                $missingAnyTermGroups += ,@($group)
            }
        }
    }
    $rejectTerms = New-Object System.Collections.Generic.List[string]
    foreach ($term in @(Get-StringList -Object $Scenario -PropertyName "reject_terms")) {
        $rejectTerms.Add($term)
    }
    foreach ($term in @(Get-StringList -Object $Scenario -PropertyName "output_reject_terms")) {
        $rejectTerms.Add($term)
    }
    foreach ($term in $rejectTerms) {
        if ($stdout -match [regex]::Escape($term)) {
            $rejectedTermsMatched += $term
        }
    }

    $passed = $expectedTerms.Count -gt 0 -and $missingTerms.Count -eq 0 -and $missingAnyTermGroups.Count -eq 0 -and $rejectedTermsMatched.Count -eq 0
    $resultClassification = if ($passed) { "live_output_contract_passed" } else { "live_output_contract_failed" }
    return [pscustomobject]@{
        passed = $passed
        classification = $resultClassification
        model = $transcriptModel
        transcript = $transcriptPath
        transcript_exit_code = $transcriptExitCode
        missing_output_terms = @($missingTerms)
        missing_any_term_groups = @($missingAnyTermGroups)
        rejected_terms_matched = @($rejectedTermsMatched)
    }
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    Add-Failure "Missing weak scenario fixture: $FixturePath"
}
if (-not (Test-Path -LiteralPath $SkillContractsPath -PathType Leaf)) {
    Add-Failure "Missing skill output contracts fixture: $SkillContractsPath"
}
if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) {
    Add-Failure "Missing live weak scenario evidence directory: $EvidenceRoot"
}
if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
    Add-Failure "Missing live weak scenario index: $IndexPath"
}

if ($failures.Count -eq 0) {
    $weakPolicy = Read-WeakEvidencePolicy -Path $PolicyPath
    $expectedWeakModels = @(Get-WeakEvidenceAllowedModels -Policy $weakPolicy -Harness "claude-copilot" -Profile "airgapped" -RequiredEvidenceClass @("preferred_weak"))
    $fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    $contracts = Get-Content -LiteralPath $SkillContractsPath -Raw | ConvertFrom-Json
    $index = Get-Content -LiteralPath $IndexPath -Raw | ConvertFrom-Json

    if ([string]$index.validation_kind -ne [string]$fixture.live_validation_kind) {
        Add-Failure "Weak scenario index validation_kind does not match fixture live_validation_kind"
    }
    if ([int]$index.required_scenario_count -ne @($fixture.scenarios).Count) {
        Add-Failure "Weak scenario index required_scenario_count does not match fixture"
    }

    $indexByScenario = @{}
    foreach ($record in @($index.records)) {
        $scenarioId = [string]$record.scenario_id
        if ([string]::IsNullOrWhiteSpace($scenarioId)) {
            Add-Failure "Weak scenario index has record without scenario_id"
            continue
        }
        if ($indexByScenario.ContainsKey($scenarioId)) {
            Add-Failure "Weak scenario index has duplicate scenario_id: $scenarioId"
        }
        $indexByScenario[$scenarioId] = $record
    }

    $contractBySkill = @{}
    $contractAnyGroupsBySkill = @{}
    foreach ($contract in @($contracts.contracts)) {
        $contractBySkill[[string]$contract.skill] = @($contract.required_output_terms | ForEach-Object { [string]$_ })
        $groups = New-Object System.Collections.Generic.List[object]
        if ($contract.PSObject.Properties.Name -contains "required_any_output_term_groups") {
            foreach ($group in @($contract.required_any_output_term_groups)) {
                $terms = @($group | ForEach-Object { [string]$_ })
                if ($terms.Count -gt 0) {
                    $groups.Add($terms)
                }
            }
        }
        $contractAnyGroupsBySkill[[string]$contract.skill] = $groups.ToArray()
    }

    $records = New-Object System.Collections.Generic.List[object]
    $quotaBlockedCount = 0
    $modelUnavailableCount = 0
    $livePassCount = 0
    $liveOutputContractFailureCount = 0
    $dryRunAssemblyCount = 0
    $missingTranscriptCount = 0
    $unknownFailureCount = 0
    $transcriptCount = 0

    foreach ($scenario in @($fixture.scenarios)) {
        $scenarioId = [string]$scenario.scenario_id
        $scenarioSkill = [string]$scenario.skill
        $indexRecord = $indexByScenario[$scenarioId]

        $classification = "missing_transcript"
        $weakValidationPassed = $false
        $missingTerms = @()
        $missingAnyTermGroups = @()
        $rejectedTermsMatched = @()
        $transcriptExitCode = $null
        $transcriptPath = $null

        $attemptResults = @()
        $attemptRecords = @()
        $expectedModelsForRecord = @($expectedWeakModels)
        $missingModels = @($expectedModelsForRecord)

        if ($null -eq $indexRecord) {
            $missingTranscriptCount++
        } else {
            $classification = [string]$indexRecord.classification
            if ($indexRecord.PSObject.Properties.Name -contains "expected_models") {
                $expectedModelsForRecord = @($indexRecord.expected_models | ForEach-Object { [string]$_ })
            }
            if ($indexRecord.PSObject.Properties.Name -contains "attempts" -and @($indexRecord.attempts).Count -gt 0) {
                $attemptRecords = @($indexRecord.attempts)
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$indexRecord.transcript)) {
                $attemptRecords = @($indexRecord)
            }

            $attemptModels = @($attemptRecords | ForEach-Object {
                if ($_.PSObject.Properties.Name -contains "model") { [string]$_.model } else { "" }
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $missingModels = @($expectedModelsForRecord | Where-Object { $attemptModels -notcontains $_ })
            foreach ($attempt in @($attemptRecords)) {
                $attemptResult = Test-LiveOutputAttempt -ScenarioId $scenarioId -Scenario $scenario -ScenarioSkill $scenarioSkill -AttemptRecord $attempt -WeakPolicy $weakPolicy -ContractBySkill $contractBySkill -ContractAnyGroupsBySkill $contractAnyGroupsBySkill
                $attemptResults += $attemptResult
                if (-not [string]::IsNullOrWhiteSpace([string]$attemptResult.transcript)) {
                    $transcriptCount++
                }
                switch ([string]$attemptResult.classification) {
                    "quota_blocked" { $quotaBlockedCount++ }
                    "model_unavailable" { $modelUnavailableCount++ }
                    "dry_run_assembly" { $dryRunAssemblyCount++ }
                    "missing_transcript" { $missingTranscriptCount++ }
                    "live_output_contract_failed" { $liveOutputContractFailureCount++ }
                    "live_output_contract_passed" { }
                    default { $unknownFailureCount++ }
                }
                $missingTerms += @($attemptResult.missing_output_terms)
                $missingAnyTermGroups += @($attemptResult.missing_any_term_groups)
                $rejectedTermsMatched += @($attemptResult.rejected_terms_matched)
            }

            if ($missingModels.Count -gt 0) {
                $classification = "missing_preferred_models"
                $missingTranscriptCount++
            } elseif (@($attemptResults | Where-Object { $_.passed -eq $true -and $expectedModelsForRecord -contains [string]$_.model }).Count -eq $expectedModelsForRecord.Count) {
                $classification = "live_output_contract_passed"
                $weakValidationPassed = $true
                $livePassCount++
            } elseif (@($attemptResults | Where-Object { [string]$_.classification -eq "quota_blocked" }).Count -gt 0) {
                $classification = "quota_blocked"
            } elseif (@($attemptResults | Where-Object { [string]$_.classification -eq "model_unavailable" }).Count -gt 0) {
                $classification = "model_unavailable"
            } elseif (@($attemptResults | Where-Object { [string]$_.classification -eq "dry_run_assembly" }).Count -gt 0) {
                $classification = "dry_run_assembly"
            } elseif (@($attemptResults | Where-Object { [string]$_.classification -eq "live_output_contract_failed" }).Count -gt 0) {
                $classification = "live_output_contract_failed"
            } else {
                $unknownFailureCount++
            }
            $transcriptPath = if ($attemptRecords.Count -eq 1) { [string]$attemptRecords[0].transcript } else { $null }
            $transcriptExitCode = if ($attemptRecords.Count -eq 1) { $attemptRecords[0].transcript_exit_code } else { $null }
        }

        $records.Add([ordered]@{
            scenario_id = $scenarioId
            skill = $scenarioSkill
            classification = $classification
            weak_validation_passed = $weakValidationPassed
            transcript_exit_code = $transcriptExitCode
            missing_output_terms = @($missingTerms)
            missing_any_term_groups = @($missingAnyTermGroups)
            missing_models = @($missingModels)
            expected_models = @($expectedModelsForRecord)
            rejected_terms_matched = @($rejectedTermsMatched)
            index = $IndexPath
            transcript = $transcriptPath
            attempts = @($attemptResults)
        })
    }

    [System.IO.Directory]::CreateDirectory($BlockersDir) | Out-Null
    $recordPath = Join-Path $BlockersDir "weak-scenario-output-latest.json"
    $scenarioCount = @($fixture.scenarios).Count
    [ordered]@{
        generated_at = (Get-Date).ToString("o")
        validation_kind = "live_scenario_model_execution"
        classification = if ($livePassCount -eq $scenarioCount) { "all_live_scenario_outputs_passed" } elseif ($quotaBlockedCount -gt 0) { "quota_blocked" } elseif ($livePassCount -gt 0) { "partial_live_scenario_outputs" } else { "live_scenario_outputs_not_ready" }
        weak_validation_passed = $livePassCount -eq $scenarioCount
        dry_run = $false
        required_scenario_count = $scenarioCount
        transcript_count = $transcriptCount
        live_pass_count = $livePassCount
        quota_blocked_count = $quotaBlockedCount
        model_unavailable_count = $modelUnavailableCount
        live_output_contract_failure_count = $liveOutputContractFailureCount
        dry_run_assembly_count = $dryRunAssemblyCount
        missing_transcript_count = $missingTranscriptCount
        unknown_failure_count = $unknownFailureCount
        scenario_index = $IndexPath
        records = $records.ToArray()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $recordPath -Encoding UTF8

    Write-Output "Weak-model live scenario output evidence classified from index."
    Write-Output "Record: $recordPath"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}
