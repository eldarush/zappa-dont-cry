param(
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs\manual\weak-scenarios",
    [string]$FixturePath = "D:\QaaS\_tools\zappa-harness\fixtures\weak-skill-scenarios.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]
$validator = "D:\QaaS\_tools\weak-model-session.ps1"
$fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
$records = New-Object System.Collections.Generic.List[object]

[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
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

foreach ($scenario in @($fixture.scenarios)) {
    $scenarioId = [string]$scenario.scenario_id
    if ([string]::IsNullOrWhiteSpace($scenarioId)) {
        Add-Failure "Weak scenario missing scenario_id"
        continue
    }
    Test-NonEmptyStringArray -Value $scenario.expected_terms -FieldName "expected_terms" -ScenarioId $scenarioId
    Test-NonEmptyStringArray -Value $scenario.reject_terms -FieldName "reject_terms" -ScenarioId $scenarioId
    if ($scenario.PSObject.Properties.Name -contains "required_any_term_groups") {
        Test-AnyTermGroups -Value $scenario.required_any_term_groups -ScenarioId $scenarioId
    }

    $skillDir = Join-Path $SkillRoot ([string]$scenario.skill)
    $skillPath = Join-Path $skillDir "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) {
        $failures.Add("Scenario references missing skill: $($scenario.skill)")
        continue
    }

    $beforeSummaries = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*summary.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    $beforeTranscripts = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*claude-copilot-id_gpt-3.5-turbo.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    $invocationStart = (Get-Date).ToUniversalTime()

    & $validator -Prompt ([string]$scenario.prompt) -Airgapped -DryRun -SkillPath $skillPath -OutDir $OutDir -RejectPattern "SKILL_NOT_FOUND" | Out-Null

    $newSummaries = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*summary.md" |
        Where-Object { $beforeSummaries -notcontains $_.FullName -and $_.LastWriteTimeUtc -gt $invocationStart })
    $newTranscripts = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*claude-copilot-id_gpt-3.5-turbo.md" |
        Where-Object { $beforeTranscripts -notcontains $_.FullName -and $_.LastWriteTimeUtc -gt $invocationStart })

    if ($newSummaries.Count -ne 1) {
        $failures.Add("Expected one new summary for scenario $($scenario.skill), got $($newSummaries.Count)")
        continue
    }
    if ($newTranscripts.Count -ne 1) {
        $failures.Add("Expected one new transcript for scenario $($scenario.skill), got $($newTranscripts.Count)")
        continue
    }

    $summary = Get-Content -LiteralPath $newSummaries[0].FullName -Raw
    $transcript = Get-Content -LiteralPath $newTranscripts[0].FullName -Raw
    foreach ($required in @("Harness: claude-copilot", "Profile: airgapped", "Models: id:gpt-3.5-turbo", "DryRun: True", "Airgapped: True")) {
        if ($summary -notmatch [regex]::Escape($required)) {
            $failures.Add("Scenario summary missing '$required': $($newSummaries[0].FullName)")
        }
    }
    if ($summary -notmatch [regex]::Escape($skillPath)) {
        $failures.Add("Scenario summary did not inject exact skill: $($newSummaries[0].FullName)")
    }
    if ($transcript -notmatch "Command: DRY_RUN") {
        $failures.Add("Scenario transcript not marked DRY_RUN: $($newTranscripts[0].FullName)")
    }
    if ($transcript -notmatch [regex]::Escape([string]$scenario.prompt)) {
        $failures.Add("Scenario transcript missing prompt text: $($newTranscripts[0].FullName)")
    }
    if ($transcript -notmatch [regex]::Escape($skillPath)) {
        $failures.Add("Scenario transcript missing skill path: $($newTranscripts[0].FullName)")
    }

    $record = [ordered]@{
        scenario_id = $scenarioId
        skill = [string]$scenario.skill
        validation_kind = [string]$fixture.validation_kind
        weak_validation_passed = $false
        expected_terms = [object[]]@($scenario.expected_terms)
        reject_terms = [object[]]@($scenario.reject_terms)
        summary = $newSummaries[0].FullName
        transcript = $newTranscripts[0].FullName
    }
    if ($scenario.PSObject.Properties.Name -contains "required_any_term_groups") {
        $record.required_any_term_groups = [object[]]@($scenario.required_any_term_groups)
    }
    $records.Add($record)
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

$recordsPath = Join-Path $OutDir "weak-scenario-records.json"
[ordered]@{
    generated_at = (Get-Date).ToString("o")
    validation_kind = [string]$fixture.validation_kind
    weak_validation_passed = $false
    records = $records.ToArray()
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordsPath -Encoding UTF8

Write-Output "Weak-model scenario dry-run assembly check passed."
Write-Output "Records: $recordsPath"
