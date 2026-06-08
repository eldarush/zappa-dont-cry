param(
    [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($manifestFile in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "qaas-artifact-manifest.json") {
    $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
    if ($manifest.promotion_state -ne "executable") {
        continue
    }

    $checked++
    foreach ($field in @("template_validation", "build_validation", "live_validation")) {
        if (-not ($manifest.PSObject.Properties.Name -contains $field)) {
            $failures.Add("Executable manifest missing ${field}: $($manifestFile.FullName)")
            continue
        }

        $validation = $manifest.$field
        if ($validation.status -ne "passed" -or [int]$validation.exit_code -ne 0) {
            $failures.Add("Executable manifest has non-passed ${field}: $($manifestFile.FullName)")
        }
        if ([string]::IsNullOrWhiteSpace([string]$validation.command) -or [string]$validation.command -match '<|>|TODO|__') {
            $failures.Add("Executable manifest has invalid ${field} command: $($manifestFile.FullName)")
        }
        if ([string]::IsNullOrWhiteSpace([string]$validation.transcript) -or -not (Test-Path -LiteralPath $validation.transcript)) {
            $failures.Add("Executable manifest has missing ${field} transcript: $($manifestFile.FullName)")
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "QaaS template/build/live evidence check passed; executable manifests checked: $checked."
