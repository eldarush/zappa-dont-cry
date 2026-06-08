param(
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $ReportPath)) {
    throw "Report not found: $ReportPath"
}

$report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
$reportDir = Split-Path -Parent $ReportPath
$markdownPath = Join-Path $reportDir "report.md"

if ($report.overall_status -notin @("passed", "failed")) {
    $failures.Add("overall_status is missing or invalid.")
}
if ($null -eq $report.summary) {
    $failures.Add("summary is missing.")
} else {
    $total = @($report.results).Count
    if ([int]$report.summary.total -ne $total) {
        $failures.Add("summary.total does not match results count.")
    }
    if ([int]$report.summary.passed + [int]$report.summary.failed -ne [int]$report.summary.total) {
        $failures.Add("summary passed+failed does not equal total.")
    }
}

$markdown = if (Test-Path -LiteralPath $markdownPath) { Get-Content -LiteralPath $markdownPath -Raw } else { "" }
if ([string]::IsNullOrWhiteSpace($markdown)) {
    $failures.Add("report.md missing or empty.")
}
if ($markdown -match '\$\(|System\.Collections\.Specialized\.OrderedDictionary') {
    $failures.Add("report.md contains broken interpolation text.")
}

foreach ($result in @($report.results)) {
    foreach ($field in @("name", "command", "duration_ms", "status", "exit_code", "log")) {
        if (-not ($result.PSObject.Properties.Name -contains $field)) {
            $failures.Add("Result missing $field.")
        }
    }
    if (-not (Test-Path -LiteralPath $result.log)) {
        $failures.Add("Result log path missing: $($result.log)")
    }
    if ($markdown -and $markdown -notmatch [regex]::Escape([string]$result.log)) {
        $failures.Add("report.md does not contain log path: $($result.log)")
    }
    if ($result.status -eq "failed" -and [string]::IsNullOrWhiteSpace([string]$result.first_error_excerpt)) {
        $failures.Add("Failed result lacks first_error_excerpt: $($result.name)")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Harness report check passed: $ReportPath"
