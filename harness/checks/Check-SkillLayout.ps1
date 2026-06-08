param(
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$ExpectedMap = "D:\QaaS\_tools\zappa-harness\fixtures\expected-skill-map.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $SkillRoot)) {
    throw "Skill root not found: $SkillRoot"
}

if (Test-Path -LiteralPath (Join-Path $SkillRoot "SKILL.md")) {
    $failures.Add("Root SKILL.md is not allowed; namespace root must contain skill folders only.")
}

$expected = Get-Content -LiteralPath $ExpectedMap -Raw | ConvertFrom-Json
$childDirs = @(Get-ChildItem -LiteralPath $SkillRoot -Directory)
$skillNames = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

foreach ($dir in $childDirs) {
    $skillPath = Join-Path $dir.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) {
        $failures.Add("Direct child is not a skill folder: $($dir.FullName)")
        continue
    }

    $skillNames.Add($dir.Name) | Out-Null
}

foreach ($required in @($expected.requiredSkills)) {
    if (-not $skillNames.Contains([string]$required)) {
        $failures.Add("Missing required skill folder: $required")
    }
}

$coordinatorPath = Join-Path (Join-Path $SkillRoot ([string]$expected.coordinator)) "SKILL.md"
if (-not (Test-Path -LiteralPath $coordinatorPath)) {
    $failures.Add("Missing coordinator skill: $coordinatorPath")
} else {
    $coordinator = Get-Content -LiteralPath $coordinatorPath -Raw
    foreach ($required in @($expected.requiredSkills)) {
        if ($required -eq $expected.coordinator) {
            continue
        }
        if ($coordinator -notmatch [regex]::Escape([string]$required)) {
            $failures.Add("Coordinator does not route required skill: $required")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Skill layout check passed for $($childDirs.Count) child folders."
