param(
    [string]$DocsRoot = "D:\QaaS\qaas-docs\docs",
    [string]$OutFile = "D:\QaaS\_tmp\zappa-dont-cry\coverage\qaas-docs-coverage.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DocsRoot)) {
    throw "Docs root not found: $DocsRoot"
}

$outDir = Split-Path -Parent $OutFile
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null

function Get-FrontMatterValue {
    param(
        [string]$Content,
        [string]$Name
    )

    $match = [regex]::Match($Content, "(?m)^$([regex]::Escape($Name)):\s*(.+?)\s*$")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim().Trim('"')
    }

    return ""
}

function Get-CoverageFamily {
    param([string]$RelativePath)

    $normalized = $RelativePath.Replace("\", "/").ToLowerInvariant()

    switch -Regex ($normalized) {
        "^assertions/" { return "assertion" }
        "^generators/" { return "generator" }
        "^probes/" { return "probe" }
        "^processors/" { return "processor" }
        "^mocker/" { return "mocker" }
        "^qaas/userinterfaces/runner/" { return "runner" }
        "^framework/" { return "framework" }
        "^configuration/" { return "configuration" }
        "_generated/schemas/assertions" { return "assertion-schema" }
        "_generated/schemas/generators" { return "generator-schema" }
        "_generated/schemas/probes" { return "probe-schema" }
        "_generated/schemas/processors" { return "processor-schema" }
        default { return "documentation" }
    }
}

function Get-ArtifactTypes {
    param([string]$Family)

    switch ($Family) {
        "assertion" { return @("runner-yaml", "runner-code") }
        "assertion-schema" { return @("runner-yaml", "runner-code") }
        "generator" { return @("runner-yaml", "runner-code") }
        "generator-schema" { return @("runner-yaml", "runner-code") }
        "probe" { return @("runner-yaml", "runner-code", "dependency-gate") }
        "probe-schema" { return @("runner-yaml", "runner-code", "dependency-gate") }
        "processor" { return @("mocker-yaml", "mocker-code") }
        "processor-schema" { return @("mocker-yaml", "mocker-code") }
        "mocker" { return @("mocker-yaml", "mocker-code") }
        "runner" { return @("runner-yaml", "runner-code") }
        "framework" { return @("hook", "config-as-code") }
        "configuration" { return @("config-as-code", "runner-yaml", "mocker-yaml") }
        default { return @("documentation") }
    }
}

$records = foreach ($file in Get-ChildItem -LiteralPath $DocsRoot -Recurse -File -Filter "*.md") {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $relative = [System.IO.Path]::GetRelativePath($DocsRoot, $file.FullName)
    $family = Get-CoverageFamily -RelativePath $relative
    $headings = @([regex]::Matches($content, "(?m)^#{1,3}\s+(.+?)\s*$") | ForEach-Object { $_.Groups[1].Value.Trim() })

    [ordered]@{
        coverage_id = ($relative -replace '[\\/]', '_' -replace '\.md$', '').ToLowerInvariant()
        relative_path = $relative
        full_path = $file.FullName
        family = $family
        title = if ($headings.Count -gt 0) { $headings[0] } else { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }
        doc_id = Get-FrontMatterValue -Content $content -Name "id"
        summary = Get-FrontMatterValue -Content $content -Name "summary"
        applies_to = Get-FrontMatterValue -Content $content -Name "applies_to"
        keywords = Get-FrontMatterValue -Content $content -Name "keywords"
        artifact_types = @(Get-ArtifactTypes -Family $family)
        headings = $headings
        has_yaml = ($content -match '```ya?ml')
        has_csharp = ($content -match '```csharp|```cs')
        has_cli = ($content -match '\b(template|run|act|assert)\b')
        requires_contract_review = $true
    }
}

$records = @($records | Sort-Object family, relative_path)
$byFamily = @{}
foreach ($group in ($records | Group-Object { $_["family"] })) {
    $byFamily[$group.Name] = $group.Count
}

$result = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    docs_root = $DocsRoot
    count = $records.Count
    by_family = $byFamily
    records = $records
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Output "Wrote QaaS docs coverage inventory for $($records.Count) pages to $OutFile"
