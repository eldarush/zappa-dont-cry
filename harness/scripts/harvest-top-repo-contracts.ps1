param(
    [string]$RepoManifest = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\top-github-repos.json",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts",
    [int]$Offset = 0,
    [int]$Count = 10,
    [int]$MaxReadmeChars = 20000,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $RepoManifest)) {
    throw "Repository manifest not found: $RepoManifest"
}

$gh = Get-Command gh -ErrorAction Stop
[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null

if ($Clean) {
    $resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
    $allowedRoot = [System.IO.Path]::GetFullPath("D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts")
    if (-not $resolvedOutDir.Equals($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "-Clean is only allowed for the managed contracts directory: $allowedRoot"
    }

    Get-ChildItem -LiteralPath $resolvedOutDir -Force | Remove-Item -Recurse -Force
}

$manifest = Get-Content -LiteralPath $RepoManifest -Raw | ConvertFrom-Json
$repositories = @($manifest.repositories | Select-Object -Skip $Offset -First $Count)

function New-SafeName {
    param([string]$Value)

    $safe = ($Value -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "unnamed"
    }

    if ($safe.Length -gt 96) {
        return $safe.Substring(0, 96).Trim('-')
    }

    return $safe
}

function Invoke-GhJson {
    param([string]$Endpoint)

    $output = & $gh.Source api $Endpoint 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh api failed for ${Endpoint}: $output"
    }

    return ($output | Out-String | ConvertFrom-Json)
}

function Invoke-GhRaw {
    param([string]$Endpoint)

    $output = & $gh.Source api $Endpoint --header "Accept: application/vnd.github.raw" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh api failed for ${Endpoint}: $output"
    }

    return ($output | Out-String)
}

function Get-PathMatches {
    param([object[]]$Tree)

    $patterns = [ordered]@{
        api_contracts = '(?i)(openapi|swagger|asyncapi|graphql|proto|\.proto$|schema)'
        ci = '(?i)^\.github/workflows/|azure-pipelines|gitlab-ci|circleci|jenkinsfile'
        containers = '(?i)(dockerfile|docker-compose|compose\.ya?ml|containerfile)'
        dotnet = '(?i)(\.sln$|\.csproj$|global\.json$|Directory\.Build\.(props|targets)$)'
        node = '(?i)(package\.json$|pnpm-lock\.yaml$|yarn\.lock$|package-lock\.json$|tsconfig\.json$)'
        python = '(?i)(pyproject\.toml$|requirements.*\.txt$|setup\.py$|tox\.ini$)'
        go = '(?i)(go\.mod$|go\.sum$)'
        java = '(?i)(pom\.xml$|build\.gradle|settings\.gradle|gradlew$)'
        rust = '(?i)(Cargo\.toml$|Cargo\.lock$)'
        docs = '(?i)(^docs/|/docs/|README|CHANGELOG|CONTRIBUTING|SECURITY|API)'
        tests = '(?i)(^test/|^tests/|/test/|/tests/|spec|__tests__)'
    }

    $result = [ordered]@{}
    foreach ($key in $patterns.Keys) {
        $matches = @(
            $Tree |
                Where-Object { $_.type -eq "blob" -and $_.path -match $patterns[$key] } |
                Select-Object -First 50 -ExpandProperty path
        )
        $result[$key] = $matches
    }

    return $result
}

function Get-ContractStrength {
    param(
        [object]$Matches,
        [bool]$HasReadme
    )

    if (@($Matches.api_contracts).Count -gt 0) {
        return "contract_files_found"
    }

    if ($HasReadme -and (@($Matches.containers).Count -gt 0 -or @($Matches.ci).Count -gt 0)) {
        return "readme_plus_runtime_hints"
    }

    if ($HasReadme) {
        return "readme_only"
    }

    return "metadata_only"
}

function Get-CandidateSurfaces {
    param(
        [string]$Language,
        [object]$Matches
    )

    $surfaces = New-Object System.Collections.Generic.List[string]

    if (@($Matches.api_contracts).Count -gt 0) {
        $surfaces.Add("api-contract-validation")
        $surfaces.Add("runner-yaml-from-public-contract")
    }

    if (@($Matches.containers).Count -gt 0) {
        $surfaces.Add("containerized-runtime-smoke")
    }

    if (@($Matches.ci).Count -gt 0) {
        $surfaces.Add("ci-documented-command-discovery")
    }

    switch -Regex ($Language) {
        "C#|F#" { $surfaces.Add("dotnet-configuration-as-code") }
        "JavaScript|TypeScript" { $surfaces.Add("node-service-or-package-contract") }
        "Python" { $surfaces.Add("python-cli-or-service-contract") }
        "Go" { $surfaces.Add("go-cli-or-service-contract") }
        "Rust" { $surfaces.Add("rust-cli-or-service-contract") }
        "Java|Kotlin|Scala" { $surfaces.Add("jvm-service-contract") }
        default { $surfaces.Add("repo-contract-discovery-needed") }
    }

    return @($surfaces | Select-Object -Unique)
}

$records = New-Object System.Collections.Generic.List[object]

foreach ($repo in $repositories) {
    $repoName = [string]$repo.full_name
    $safeName = "{0:D3}-{1}" -f [int]$repo.rank, (New-SafeName $repoName.Replace("/", "-"))
    $repoOutDir = Join-Path $OutDir $safeName
    [System.IO.Directory]::CreateDirectory($repoOutDir) | Out-Null

    $errors = New-Object System.Collections.Generic.List[string]
    $readmePath = Join-Path $repoOutDir "README.snapshot.md"
    $treePath = Join-Path $repoOutDir "tree.snapshot.json"
    $recordPath = Join-Path $repoOutDir "repo-contract.json"

    $repoDetails = $null
    $tree = @()
    $readme = ""
    $hasReadme = $false

    try {
        $repoDetails = Invoke-GhJson "repos/$repoName"
    } catch {
        $errors.Add($_.Exception.Message)
    }

    try {
        $readme = Invoke-GhRaw "repos/$repoName/readme"
        if ($readme.Length -gt $MaxReadmeChars) {
            $readme = $readme.Substring(0, $MaxReadmeChars)
        }

        $readme | Set-Content -LiteralPath $readmePath -Encoding UTF8
        $hasReadme = $true
    } catch {
        $errors.Add($_.Exception.Message)
    }

    $branch = if ($repoDetails -and $repoDetails.default_branch) { [string]$repoDetails.default_branch } else { [string]$repo.default_branch }
    if (-not [string]::IsNullOrWhiteSpace($branch)) {
        try {
            $treeResponse = Invoke-GhJson "repos/$repoName/git/trees/$branch`?recursive=1"
            $tree = @($treeResponse.tree)
            $treeResponse | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $treePath -Encoding UTF8
        } catch {
            $errors.Add($_.Exception.Message)
        }
    }

    $matches = Get-PathMatches -Tree $tree
    $contractStrength = Get-ContractStrength -Matches $matches -HasReadme $hasReadme
    $surfaces = Get-CandidateSurfaces -Language ([string]$repo.language) -Matches $matches

    $record = [ordered]@{
        harvested_at = (Get-Date).ToString("o")
        rank = [int]$repo.rank
        repository = $repoName
        url = $repo.html_url
        language = $repo.language
        stars = $repo.stars
        default_branch = $branch
        contract_strength = $contractStrength
        candidate_qaas_surfaces = $surfaces
        has_readme_snapshot = $hasReadme
        readme_snapshot = if ($hasReadme) { $readmePath } else { $null }
        tree_snapshot = if ($tree.Count -gt 0) { $treePath } else { $null }
        path_matches = $matches
        public_evidence = @(
            if ($hasReadme) { $readmePath }
            if ($tree.Count -gt 0) { $treePath }
        )
        status = if ($errors.Count -eq 0) { "contract_harvested" } else { "contract_harvested_with_errors" }
        errors = @($errors)
    }

    $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $recordPath -Encoding UTF8
    $records.Add([ordered]@{
        rank = [int]$repo.rank
        repository = $repoName
        contract_strength = $contractStrength
        status = $record.status
        record_path = $recordPath
    })
}

$index = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    source_manifest = $RepoManifest
    output_directory = $OutDir
    offset = $Offset
    count = $records.Count
    policy = "GitHub API metadata, tree, and README snapshots only; no cloning or execution"
    records = $records.ToArray()
}

$indexPath = Join-Path $OutDir ("contract-index-offset-{0}-count-{1}.json" -f $Offset, $Count)
$index | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $indexPath -Encoding UTF8
Write-Output "Harvested contracts for $($records.Count) repositories."
Write-Output "Index: $indexPath"
