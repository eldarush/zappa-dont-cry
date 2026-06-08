param(
    [string]$Root = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$quickValidate = "C:\Users\eldar\.codex\skills\.system\skill-creator\scripts\quick_validate.py"
if (-not (Test-Path -LiteralPath $quickValidate)) {
    throw "quick_validate.py not found: $quickValidate"
}

$skillFiles = Get-ChildItem -LiteralPath $Root -Recurse -Filter "SKILL.md" -File
if (-not $skillFiles) {
    throw "No SKILL.md files found under $Root"
}

$failures = New-Object System.Collections.Generic.List[string]

$rootSkill = Join-Path $Root "SKILL.md"
if (Test-Path -LiteralPath $rootSkill) {
    $failures.Add("Root SKILL.md is not allowed; zappa-dont-cry must be a namespace folder only: $rootSkill")
}

foreach ($child in Get-ChildItem -LiteralPath $Root -Directory) {
    $childSkill = Join-Path $child.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $childSkill)) {
        $failures.Add("Direct child is not a skill folder: $($child.FullName)")
    }
}

foreach ($skillFile in $skillFiles) {
    $skillDir = Split-Path -Parent $skillFile.FullName
    & python $quickValidate $skillDir
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("quick_validate failed: $skillDir")
    }

    $content = Get-Content -LiteralPath $skillFile.FullName -Raw
    if ($content -match '\[TODO|TODO:|Replace with') {
        $failures.Add("Unresolved template text: $($skillFile.FullName)")
    }
}

$requiredReferences = @(
    "qaas-docs-index.md",
    "intent-clarification-protocol.md",
    "artifact-contract.md",
    "airgapped-validation.md",
    "recursive-development-loop.md"
)

foreach ($reference in $requiredReferences) {
    $path = Join-Path (Join-Path $HarnessRoot "references") $reference
    if (-not (Test-Path -LiteralPath $path)) {
        $failures.Add("Missing reference: $path")
    }
}

$requiredScripts = @(
    "bootstrap-zappa-env.ps1",
    "build-qaas-docs-coverage.ps1",
    "fetch-top-github-repos.ps1",
    "generate-qaas-coverage-skeletons.ps1",
    "generate-top-repo-artifacts.ps1",
    "generate-top-repos-campaign.ps1",
    "harvest-top-repo-contracts.ps1",
    "run-airgapped-validation.ps1",
    "validate-generated-artifacts.ps1",
    "validate-zappa-pack.ps1"
)

foreach ($script in $requiredScripts) {
    $path = Join-Path (Join-Path $HarnessRoot "scripts") $script
    if (-not (Test-Path -LiteralPath $path)) {
        $failures.Add("Missing script: $path")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "zappa-dont-cry validation passed for $($skillFiles.Count) skills."
