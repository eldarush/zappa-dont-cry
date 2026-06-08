param(
    [string]$ManifestPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\top-github-repos.json",
    [string]$ContractsDir = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

$repos = @((Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json).repositories)
$contracts = @(Get-ChildItem -LiteralPath $ContractsDir -Recurse -File -Filter "repo-contract.json")

if ($contracts.Count -ne $repos.Count) {
    $failures.Add("Contract count $($contracts.Count) does not match repo count $($repos.Count).")
}

$byRepo = @{}
foreach ($contractPath in $contracts) {
    $contract = Get-Content -LiteralPath $contractPath.FullName -Raw | ConvertFrom-Json
    if ($byRepo.ContainsKey([string]$contract.repository)) {
        $failures.Add("Duplicate contract repository key: $($contract.repository)")
        continue
    }
    $byRepo[[string]$contract.repository] = [ordered]@{ path = $contractPath.FullName; contract = $contract }
}

foreach ($repo in $repos) {
    $name = [string]$repo.full_name
    if (-not $byRepo.ContainsKey($name)) {
        $failures.Add("Missing contract for $name")
        continue
    }

    $entry = $byRepo[$name]
    $contract = $entry.contract
    if ($contract.status -ne "contract_harvested") {
        $failures.Add("Contract was harvested with errors for ${name}: $($entry.path)")
    }
    if (@($contract.errors).Count -ne 0) {
        $failures.Add("Contract has errors for ${name}: $($entry.path)")
    }
    if ([int]$contract.rank -ne [int]$repo.rank) {
        $failures.Add("Contract rank mismatch for ${name}: manifest=$($repo.rank) contract=$($contract.rank)")
    }
    if ([string]::IsNullOrWhiteSpace([string]$contract.contract_strength)) {
        $failures.Add("Missing contract_strength for $name")
    }
    if (@($contract.candidate_qaas_surfaces).Count -eq 0) {
        $failures.Add("Missing candidate_qaas_surfaces for $name")
    }
    if (@($contract.public_evidence).Count -eq 0) {
        $failures.Add("Missing public_evidence for $name")
    }
    foreach ($evidence in @($contract.public_evidence)) {
        if (-not (Test-Path -LiteralPath $evidence)) {
            $failures.Add("Evidence path missing for ${name}: $evidence")
        }
    }
    if (-not $contract.has_readme_snapshot -or -not (Test-Path -LiteralPath $contract.readme_snapshot)) {
        $failures.Add("Missing README snapshot for $name")
    }
    if (-not (Test-Path -LiteralPath $contract.tree_snapshot)) {
        $failures.Add("Missing tree snapshot for $name")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Contract harvest check passed for $($repos.Count) repositories."
