param(
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs\manual\weak-adversarial-scenarios",
    [string]$FixturePath = "D:\QaaS\_tools\zappa-harness\fixtures\weak-adversarial-scenarios.json",
    [string]$SkillOutputContractPath = "D:\QaaS\_tools\zappa-harness\fixtures\skill-output-contracts.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]
$validator = "D:\QaaS\_tools\weak-model-session.ps1"

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Test-TextContains {
    param(
        [string]$Text,
        [string]$Expected
    )

    return $Text.IndexOf($Expected, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Test-NonEmptyStringArray {
    param(
        [object]$Value,
        [string]$FieldName,
        [string]$ScenarioId
    )

    $items = @($Value)
    if ($items.Count -eq 0) {
        Add-Failure "$ScenarioId has empty $FieldName"
        return
    }

    for ($index = 0; $index -lt $items.Count; $index++) {
        if (-not ($items[$index] -is [string]) -or [string]::IsNullOrWhiteSpace([string]$items[$index])) {
            Add-Failure "$ScenarioId has non-string or empty $FieldName[$index]"
        }
    }
}

function Test-AnyTermGroups {
    param(
        [object]$Value,
        [string]$ScenarioId
    )

    foreach ($group in @($Value)) {
        $terms = @($group)
        if ($terms.Count -eq 0) {
            Add-Failure "$ScenarioId has empty required_any_term_groups entry"
            continue
        }
        for ($index = 0; $index -lt $terms.Count; $index++) {
            if (-not ($terms[$index] -is [string]) -or [string]::IsNullOrWhiteSpace([string]$terms[$index])) {
                Add-Failure "$ScenarioId has non-string or empty required_any_term_groups entry"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
    Add-Failure "Missing adversarial fixture: $FixturePath"
} elseif (-not (Test-Path -LiteralPath $SkillRoot -PathType Container)) {
    Add-Failure "Missing skill root: $SkillRoot"
} elseif (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    Add-Failure "Missing weak-model validator: $validator"
} elseif (-not (Test-Path -LiteralPath $SkillOutputContractPath -PathType Leaf)) {
    Add-Failure "Missing skill output contract fixture: $SkillOutputContractPath"
} else {
    $fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
    $skillOutputContracts = Get-Content -LiteralPath $SkillOutputContractPath -Raw | ConvertFrom-Json
    $contractTermsBySkill = @{}
    foreach ($contract in @($skillOutputContracts.contracts)) {
        $contractTermsBySkill[[string]$contract.skill] = @($contract.required_output_terms)
    }

    if ([string]$fixture.validation_kind -ne "dry_run_adversarial_scenario_prompt_assembly") {
        Add-Failure "Fixture validation_kind must be dry_run_adversarial_scenario_prompt_assembly"
    }
    if ([string]$fixture.live_validation_kind -ne "live_adversarial_model_execution") {
        Add-Failure "Fixture live_validation_kind must be live_adversarial_model_execution"
    }

    $requiredRiskCategories = @($fixture.required_risk_categories)
    if ($requiredRiskCategories.Count -lt 6) {
        Add-Failure "Fixture must require broad adversarial risk categories"
    }

    $scenarioIds = @{}
    $coveredRisks = @{}
    $coveredSkills = @{}
    $contractScenarioSkills = @{}
    $records = New-Object System.Collections.Generic.List[object]

    [System.IO.Directory]::CreateDirectory($OutDir) | Out-Null

    foreach ($scenario in @($fixture.scenarios)) {
        $scenarioId = [string]$scenario.scenario_id
        if ([string]::IsNullOrWhiteSpace($scenarioId)) {
            Add-Failure "Scenario missing scenario_id"
            continue
        }
        if ($scenarioIds.ContainsKey($scenarioId)) {
            Add-Failure "Duplicate adversarial scenario_id: $scenarioId"
        }
        $scenarioIds[$scenarioId] = $true

        $skillName = [string]$scenario.skill
        $riskCategory = [string]$scenario.risk_category
        $prompt = [string]$scenario.prompt
        if ([string]::IsNullOrWhiteSpace($skillName)) {
            Add-Failure "$scenarioId missing skill"
            continue
        }
        if ([string]::IsNullOrWhiteSpace($riskCategory)) {
            Add-Failure "$scenarioId missing risk_category"
        } else {
            $coveredRisks[$riskCategory] = $true
        }
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            Add-Failure "$scenarioId missing prompt"
        }

        Test-NonEmptyStringArray -Value $scenario.expected_terms -FieldName "expected_terms" -ScenarioId $scenarioId
        Test-NonEmptyStringArray -Value $scenario.reject_terms -FieldName "reject_terms" -ScenarioId $scenarioId
        if ($scenario.PSObject.Properties.Name -contains "output_reject_terms") {
            Test-NonEmptyStringArray -Value $scenario.output_reject_terms -FieldName "output_reject_terms" -ScenarioId $scenarioId
        }
        if ($scenario.PSObject.Properties.Name -contains "required_all_terms") {
            Test-NonEmptyStringArray -Value $scenario.required_all_terms -FieldName "required_all_terms" -ScenarioId $scenarioId
        }
        if ($scenario.PSObject.Properties.Name -contains "required_any_term_groups") {
            Test-AnyTermGroups -Value $scenario.required_any_term_groups -ScenarioId $scenarioId
        }
        Test-NonEmptyStringArray -Value $scenario.required_skill_terms -FieldName "required_skill_terms" -ScenarioId $scenarioId
        if (($scenario.PSObject.Properties.Name -contains "must_remain_blocked") -and $scenario.must_remain_blocked -ne $true) {
            Add-Failure "$scenarioId must_remain_blocked must be true when present"
        }
        if (($scenario.PSObject.Properties.Name -contains "requires_live_evidence") -and $scenario.requires_live_evidence -ne $true) {
            Add-Failure "$scenarioId requires_live_evidence must be true when present"
        }
        if (($scenario.PSObject.Properties.Name -contains "required_contract") -and $scenario.required_contract -ne $true) {
            Add-Failure "$scenarioId required_contract must be true when present"
        }
        if (($scenario.PSObject.Properties.Name -contains "required_contract") -and $scenario.required_contract -eq $true) {
            $contractScenarioSkills[$skillName] = $true
            if (-not $contractTermsBySkill.ContainsKey($skillName)) {
                Add-Failure "$scenarioId has required_contract but no output contract exists for $skillName"
            } else {
                $expectedTerms = @($scenario.expected_terms)
                foreach ($contractTerm in @($contractTermsBySkill[$skillName])) {
                    $hasTerm = $false
                    foreach ($expectedTerm in $expectedTerms) {
                        if ([string]$expectedTerm -eq [string]$contractTerm) {
                            $hasTerm = $true
                            break
                        }
                    }
                    if (-not $hasTerm) {
                        Add-Failure "$scenarioId required_contract missing expected output term: $contractTerm"
                    }
                }
            }
        }

        $skillDir = Join-Path $SkillRoot $skillName
        $skillPath = Join-Path $skillDir "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            Add-Failure "$scenarioId references missing skill: $skillName"
            continue
        }
        $coveredSkills[$skillName] = $true

        $skillText = Get-Content -LiteralPath $skillPath -Raw
        foreach ($requiredTerm in @($scenario.required_skill_terms)) {
            if (-not (Test-TextContains -Text $skillText -Expected ([string]$requiredTerm))) {
                Add-Failure "$scenarioId required skill term not found in ${skillName}: $requiredTerm"
            }
        }

        $beforeSummaries = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*summary.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        $beforeTranscripts = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*claude-copilot-id_gpt-3.5-turbo.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        $invocationStart = (Get-Date).ToUniversalTime()

        & $validator -Prompt $prompt -Airgapped -DryRun -SkillPath $skillPath -OutDir $OutDir -RejectPattern "SKILL_NOT_FOUND" | Out-Null
        if ((Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) -and $global:LASTEXITCODE -ne 0) {
            Add-Failure "Adversarial dry run failed for ${scenarioId}: $skillPath"
            continue
        }

        $newSummaries = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*summary.md" |
            Where-Object { $beforeSummaries -notcontains $_.FullName -and $_.LastWriteTimeUtc -gt $invocationStart })
        $newTranscripts = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*claude-copilot-id_gpt-3.5-turbo.md" |
            Where-Object { $beforeTranscripts -notcontains $_.FullName -and $_.LastWriteTimeUtc -gt $invocationStart })

        if ($newSummaries.Count -ne 1) {
            Add-Failure "Expected one new summary for adversarial scenario $scenarioId, got $($newSummaries.Count)"
            continue
        }
        if ($newTranscripts.Count -ne 1) {
            Add-Failure "Expected one new transcript for adversarial scenario $scenarioId, got $($newTranscripts.Count)"
            continue
        }

        $summaryPath = $newSummaries[0].FullName
        $transcriptPath = $newTranscripts[0].FullName
        $summary = Get-Content -LiteralPath $summaryPath -Raw
        $transcript = Get-Content -LiteralPath $transcriptPath -Raw

        foreach ($required in @("Harness: claude-copilot", "Profile: airgapped", "ReasoningEffort: none", "Models: id:gpt-3.5-turbo", "DryRun: True", "Airgapped: True")) {
            if ($summary -notmatch [regex]::Escape($required)) {
                Add-Failure "Adversarial summary for $scenarioId missing '$required': $summaryPath"
            }
        }
        if ($summary -notmatch [regex]::Escape($skillPath)) {
            Add-Failure "Adversarial summary for $scenarioId did not inject exact skill path: $summaryPath"
        }
        if ($transcript -notmatch "Command: DRY_RUN") {
            Add-Failure "Adversarial transcript for $scenarioId is not marked DRY_RUN: $transcriptPath"
        }
        if ($transcript -notmatch [regex]::Escape($prompt)) {
            Add-Failure "Adversarial transcript for $scenarioId missing prompt text: $transcriptPath"
        }
        if ($transcript -notmatch [regex]::Escape($skillPath)) {
            Add-Failure "Adversarial transcript for $scenarioId missing skill path: $transcriptPath"
        }
        if ($transcript -notmatch "id:gpt-3.5-turbo") {
            Add-Failure "Adversarial transcript for $scenarioId missing id:gpt-3.5-turbo route: $transcriptPath"
        }
        if ($transcript -match "opus") {
            Add-Failure "Adversarial transcript for $scenarioId contains opus alias: $transcriptPath"
        }

        $record = [ordered]@{
            scenario_id = $scenarioId
            skill = $skillName
            risk_category = $riskCategory
            validation_kind = [string]$fixture.validation_kind
            weak_validation_passed = $false
            expected_terms = [object[]]@($scenario.expected_terms)
            reject_terms = [object[]]@($scenario.reject_terms)
            required_contract = if ($scenario.PSObject.Properties.Name -contains "required_contract") { [bool]$scenario.required_contract } else { $false }
            requires_live_evidence = if ($scenario.PSObject.Properties.Name -contains "requires_live_evidence") { [bool]$scenario.requires_live_evidence } else { $false }
            must_remain_blocked = if ($scenario.PSObject.Properties.Name -contains "must_remain_blocked") { [bool]$scenario.must_remain_blocked } else { $false }
            summary = $summaryPath
            transcript = $transcriptPath
        }
        if ($scenario.PSObject.Properties.Name -contains "output_reject_terms") {
            $record.output_reject_terms = [object[]]@($scenario.output_reject_terms)
        }
        if ($scenario.PSObject.Properties.Name -contains "required_all_terms") {
            $record.required_all_terms = [object[]]@($scenario.required_all_terms)
        }
        if ($scenario.PSObject.Properties.Name -contains "required_any_term_groups") {
            $record.required_any_term_groups = [object[]]@($scenario.required_any_term_groups)
        }
        $records.Add($record)
    }

    foreach ($risk in $requiredRiskCategories) {
        if (-not $coveredRisks.ContainsKey([string]$risk)) {
            Add-Failure "Required adversarial risk category has no scenario: $risk"
        }
    }

    $skillFolders = @(Get-ChildItem -LiteralPath $SkillRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") })
    foreach ($skill in $skillFolders) {
        if (-not $coveredSkills.ContainsKey($skill.Name)) {
            Add-Failure "Adversarial suite has no scenario for skill: $($skill.Name)"
        }
        if (-not $contractScenarioSkills.ContainsKey($skill.Name)) {
            Add-Failure "Adversarial suite has no required_contract output-drift scenario for skill: $($skill.Name)"
        }
    }

    if ($records.Count -lt $skillFolders.Count) {
        Add-Failure "Adversarial suite must include at least one scenario per skill"
    }

    if ($failures.Count -eq 0) {
        $recordsPath = Join-Path $OutDir "weak-adversarial-scenario-records.json"
        [ordered]@{
            generated_at = (Get-Date).ToString("o")
            validation_kind = [string]$fixture.validation_kind
            live_validation_kind = [string]$fixture.live_validation_kind
            weak_validation_passed = $false
            adversarial_scenario_count = $records.Count
            risk_categories = @($coveredRisks.Keys | Sort-Object)
            record_count = $records.Count
            records = $records.ToArray()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $recordsPath -Encoding UTF8
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Weak-model adversarial dry-run assembly check passed for $($records.Count) scenarios."
Write-Output "Records: $recordsPath"
