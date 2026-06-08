param(
    [int]$Count = 250,
    [string]$OutFile = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\top-github-repos.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Count -lt 1 -or $Count -gt 1000) {
    throw "Count must be between 1 and 1000 for the GitHub search API."
}

$gh = Get-Command gh -ErrorAction Stop
$outDir = Split-Path -Parent $OutFile
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null

$pageSize = 100
$repos = New-Object System.Collections.Generic.List[object]
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$page = 1
$maxPages = 10

while ($repos.Count -lt $Count -and $page -le $maxPages) {
    $endpoint = "search/repositories?q=stars:%3E1&sort=stars&order=desc&per_page=$pageSize&page=$page"
    $response = & $gh.Source api $endpoint | ConvertFrom-Json
    if (-not $response.items -or @($response.items).Count -eq 0) {
        break
    }

    foreach ($repo in $response.items) {
        if (-not $seen.Add([string]$repo.full_name)) {
            continue
        }

        $repos.Add([ordered]@{
            rank = $repos.Count + 1
            full_name = $repo.full_name
            html_url = $repo.html_url
            clone_url = $repo.clone_url
            language = $repo.language
            stars = $repo.stargazers_count
            description = $repo.description
            default_branch = $repo.default_branch
        })

        if ($repos.Count -ge $Count) {
            break
        }
    }

    $page++
}

if ($repos.Count -lt $Count) {
    throw "Only found $($repos.Count) unique repositories before GitHub search limit; requested $Count."
}

$result = [ordered]@{
    fetched_at = (Get-Date).ToString("o")
    source = "GitHub search/repositories sorted by stars; de-duplicated by full_name"
    count = $repos.Count
    repositories = $repos
}

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Output "Wrote $($repos.Count) repositories to $OutFile"
