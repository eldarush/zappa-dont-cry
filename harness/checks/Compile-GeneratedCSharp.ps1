param(
    [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs\manual\compile",
    [string]$TargetFramework = "net10.0"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([string]$Path)

    $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
}

function Test-PathUnderRoot {
    param(
        [string]$Path,
        [string]$RootPath
    )

    $fullPath = Get-NormalizedPath -Path $Path
    $rootFullPath = Get-NormalizedPath -Path $RootPath
    if ([string]::Equals($fullPath, $rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootPrefix = "$rootFullPath$([System.IO.Path]::DirectorySeparatorChar)"
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

$seen = @{}
foreach ($manifestPath in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "qaas-artifact-manifest.json")) {
    $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw | ConvertFrom-Json
    foreach ($artifact in @($manifest.artifacts)) {
        if ([string]::IsNullOrWhiteSpace([string]$artifact)) {
            continue
        }

        if ([System.IO.Path]::GetExtension([string]$artifact).ToLowerInvariant() -ne ".cs") {
            continue
        }

        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
            throw "Manifest references missing generated C# artifact: $artifact"
        }

        $resolved = (Resolve-Path -LiteralPath $artifact).Path
        if (-not (Test-PathUnderRoot -Path $resolved -RootPath $Root)) {
            throw "Manifest references C# artifact outside generated root: $resolved"
        }

        $seen[(Get-NormalizedPath -Path $resolved)] = $true
    }
}

$files = @($seen.Keys | Sort-Object | ForEach-Object { Get-Item -LiteralPath $_ })
if ($files.Count -eq 0) {
    throw "No manifest-declared generated C# files found under $Root"
}

[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
$projectPath = Join-Path $OutDir "GeneratedCompileCheck.csproj"
$compileItems = @($files | ForEach-Object {
    $escapedPath = [System.Security.SecurityElement]::Escape($_.FullName)
    "    <Compile Include=""$escapedPath"" />"
}) -join [Environment]::NewLine

@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$TargetFramework</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
$compileItems
  </ItemGroup>
</Project>
"@ | Set-Content -LiteralPath $projectPath -Encoding UTF8

dotnet build $projectPath --nologo "-clp:ErrorsOnly"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "Generated C# compile check passed for $($files.Count) manifest-declared files."
