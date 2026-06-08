param(
    [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\docs-coverage",
    [string]$IndexFileName = "coverage-skeleton-index.json",
    [string]$TargetFramework = "net10.0",
    [switch]$SkipCSharpBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Generated artifact root not found: $Root"
}

$indexPath = Join-Path $Root $IndexFileName
if (-not (Test-Path -LiteralPath $indexPath)) {
    Add-Failure "Missing coverage skeleton index: $indexPath"
} else {
    try {
        $index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
        $directories = @(Get-ChildItem -LiteralPath $Root -Directory)
        if ([int]$index.count -ne $directories.Count) {
            Add-Failure "Index count $($index.count) does not match directory count $($directories.Count)."
        }
    } catch {
        Add-Failure "Index JSON did not parse: $($_.Exception.Message)"
    }
}

$manifestFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "qaas-artifact-manifest.json")
if ($manifestFiles.Count -eq 0) {
    Add-Failure "No qaas-artifact-manifest.json files found under $Root."
}

foreach ($manifestFile in $manifestFiles) {
    try {
        $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
    } catch {
        Add-Failure "Manifest JSON did not parse: $($manifestFile.FullName): $($_.Exception.Message)"
        continue
    }

    if ($manifest.status -notmatch '^blocked_until_(repo_)?contract_review$') {
        Add-Failure "Manifest status is not a recognized blocked contract-review status: $($manifestFile.FullName)"
    }

    $artifacts = @($manifest.artifacts)
    if ([int]$manifest.artifact_count -ne $artifacts.Count) {
        Add-Failure "Manifest artifact_count mismatch: $($manifestFile.FullName)"
    }

    if (@($manifest.docs_evidence).Count -eq 0) {
        Add-Failure "Manifest has no docs_evidence: $($manifestFile.FullName)"
    }

    foreach ($artifact in $artifacts) {
        if (-not (Test-Path -LiteralPath $artifact)) {
            Add-Failure "Manifest references missing artifact: $artifact"
        }
    }
}

$yamlFiles = @(
    Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $_.Extension -in @(".yaml", ".yml") }
)
foreach ($yamlFile in $yamlFiles) {
    $content = Get-Content -LiteralPath $yamlFile.FullName -Raw

    if ($content -match "`t") {
        Add-Failure "YAML contains a tab character: $($yamlFile.FullName)"
    }

    if ($content -match 'EvidencePath:\s+"[A-Z]:') {
        Add-Failure "YAML has double-quoted Windows EvidencePath: $($yamlFile.FullName)"
    }

    if ($content -notmatch 'Status:\s*blocked_until_(repo_)?contract_review') {
        Add-Failure "YAML missing blocked status header: $($yamlFile.FullName)"
    }

    if ($content -notmatch 'BlockedReason:') {
        Add-Failure "YAML missing BlockedReason: $($yamlFile.FullName)"
    }
}

$csharpFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.cs")
foreach ($csharpFile in $csharpFiles) {
    $content = Get-Content -LiteralPath $csharpFile.FullName -Raw

    if ($content -notmatch '(?m)^namespace ZappaDontCry\.(Generated|TopRepos)\.[A-Za-z_][A-Za-z0-9_]*;') {
        Add-Failure "C# skeleton has an invalid generated namespace: $($csharpFile.FullName)"
    }

    if ($content -notmatch 'Status:\s*blocked_until_(repo_)?contract_review') {
        Add-Failure "C# skeleton missing blocked status header: $($csharpFile.FullName)"
    }
}

if (-not $SkipCSharpBuild -and $csharpFiles.Count -gt 0) {
    $validationRoot = "D:\QaaS\_tmp\zappa-dont-cry\artifact-validation"
    [System.IO.Directory]::CreateDirectory($validationRoot) | Out-Null
    $compileDir = Join-Path $validationRoot ("cs-compile-" + (Get-Date).ToString("yyyyMMdd-HHmmss-fff"))
    [System.IO.Directory]::CreateDirectory($compileDir) | Out-Null

    $compileGlob = [System.Security.SecurityElement]::Escape((Join-Path $Root "**\*.cs"))
    $projectPath = Join-Path $compileDir "GeneratedCompileCheck.csproj"
    $project = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$TargetFramework</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="$compileGlob" />
  </ItemGroup>
</Project>
"@
    $project | Set-Content -LiteralPath $projectPath -Encoding UTF8

    $buildOutputPath = Join-Path $compileDir "dotnet-build.log"
    $buildOutput = & dotnet build $projectPath --nologo "-clp:ErrorsOnly" 2>&1
    $buildExitCode = $LASTEXITCODE
    $buildOutput | Set-Content -LiteralPath $buildOutputPath -Encoding UTF8

    if ($buildExitCode -ne 0) {
        Add-Failure "Generated C# skeleton build failed; see $buildOutputPath"
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure
    }

    exit 1
}

Write-Output "Generated artifact validation passed."
Write-Output "Manifests: $($manifestFiles.Count)"
Write-Output "YAML files: $($yamlFiles.Count)"
Write-Output "C# files: $($csharpFiles.Count)"
