param(
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs\manual\weak-routing",
    [string]$FixturePath = "D:\QaaS\_tools\zappa-harness\fixtures\weak-routing-prompts.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]
$validator = "D:\QaaS\_tools\weak-model-session.ps1"
$fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
$expected = $fixture.expected

[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
$routeRecords = New-Object System.Collections.Generic.List[object]

foreach ($skill in Get-ChildItem -LiteralPath $SkillRoot -Directory) {
    $skillPath = Join-Path $skill.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) {
        continue
    }

    foreach ($term in @($fixture.airgappedTerms)) {
        $beforeSummaries = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*summary.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        $beforeTranscripts = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*claude-copilot-id_gpt-3.5-turbo.md" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        $invocationStart = (Get-Date).ToUniversalTime()
        $global:LASTEXITCODE = 0
        & $validator -Prompt "Use $($skill.Name) for $term. Say whether this skill is available." -Airgapped -DryRun -SkillPath $skillPath -OutDir $OutDir -RejectPattern "SKILL_NOT_FOUND" | Out-Null
        if ((Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) -and $global:LASTEXITCODE -ne 0) {
            $failures.Add("weak dry run failed for $skillPath")
            continue
        }

        $newSummaries = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*summary.md" |
            Where-Object { $beforeSummaries -notcontains $_.FullName -and $_.LastWriteTimeUtc -gt $invocationStart })
        $newTranscripts = @(Get-ChildItem -LiteralPath $OutDir -File -Filter "*claude-copilot-id_gpt-3.5-turbo.md" |
            Where-Object { $beforeTranscripts -notcontains $_.FullName -and $_.LastWriteTimeUtc -gt $invocationStart })

        if ($newSummaries.Count -ne 1) {
            $failures.Add("expected exactly one new summary for $($skill.Name) / $term, got $($newSummaries.Count)")
            continue
        }
        if ($newTranscripts.Count -ne 1) {
            $failures.Add("expected exactly one new transcript for $($skill.Name) / $term, got $($newTranscripts.Count)")
            continue
        }

        $summaryFile = $newSummaries[0]
        $transcriptFile = $newTranscripts[0]
        $summary = Get-Content -LiteralPath $summaryFile.FullName -Raw
        $transcript = Get-Content -LiteralPath $transcriptFile.FullName -Raw

        foreach ($property in $expected.PSObject.Properties) {
            $required = "$($property.Name): $($property.Value)"
            if ($summary -notmatch [regex]::Escape($required)) {
                $failures.Add("summary for $($skill.Name) missing '$required': $($summaryFile.FullName)")
            }
        }

        if ($summary -notmatch "DryRun: True") {
            $failures.Add("summary did not mark dry run: $($summaryFile.FullName)")
        }
        if ($summary -notmatch [regex]::Escape($skillPath)) {
            $failures.Add("summary for $($skill.Name) did not inject exact skill path: $($summaryFile.FullName)")
        }
        if ($transcript -notmatch "Command: DRY_RUN") {
            $failures.Add("transcript is not marked DRY_RUN: $($transcriptFile.FullName)")
        }
        if ($transcript -notmatch "id:gpt-3.5-turbo") {
            $failures.Add("transcript missing id:gpt-3.5-turbo route: $($transcriptFile.FullName)")
        }
        if ($transcript -match "opus") {
            $failures.Add("transcript contains opus alias: $($transcriptFile.FullName)")
        }

        $routeRecords.Add([ordered]@{
            skill = $skill.Name
            term = $term
            validation_kind = "dry_run_prompt_assembly"
            weak_validation_passed = $false
            summary = $summaryFile.FullName
            transcript = $transcriptFile.FullName
        })
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

$recordsPath = Join-Path $OutDir "weak-routing-records.json"
[ordered]@{
    generated_at = (Get-Date).ToString("o")
    validation_kind = "dry_run_prompt_assembly"
    weak_validation_passed = $false
    records = $routeRecords.ToArray()
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordsPath -Encoding UTF8

Write-Output "Weak-model dry routing check passed."
Write-Output "Records: $recordsPath"
