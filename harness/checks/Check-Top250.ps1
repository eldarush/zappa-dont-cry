param(
    [string]$ManifestPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\top-github-repos.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$repos = @($manifest.repositories)

if ($repos.Count -ne 250) {
    $failures.Add("Expected 250 repositories, found $($repos.Count)")
}

$unique = @($repos | Select-Object -ExpandProperty full_name -Unique)
if ($unique.Count -ne $repos.Count) {
    $failures.Add("Repository full_name values are not unique.")
}

for ($i = 0; $i -lt $repos.Count; $i++) {
    $expectedRank = $i + 1
    if ([int]$repos[$i].rank -ne $expectedRank) {
        $failures.Add("Rank mismatch at index $i; expected $expectedRank got $($repos[$i].rank)")
    }

    foreach ($field in @("full_name", "html_url", "clone_url", "stars", "default_branch")) {
        if ($null -eq $repos[$i].$field -or [string]::IsNullOrWhiteSpace([string]$repos[$i].$field)) {
            $failures.Add("Missing $field for rank $expectedRank")
        }
    }

    if ($i -gt 0 -and [int]$repos[$i].stars -gt [int]$repos[$i - 1].stars) {
        $failures.Add("Stars are not non-increasing at rank $expectedRank")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Top-250 manifest check passed."
