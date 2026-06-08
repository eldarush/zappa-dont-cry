param(
    [string]$RepoManifest = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\top-github-repos.json",
    [string]$OutFile = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\qaas-campaign-plan.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $RepoManifest)) {
    throw "Repository manifest not found: $RepoManifest"
}

$manifest = Get-Content -LiteralPath $RepoManifest -Raw | ConvertFrom-Json
$outDir = Split-Path -Parent $OutFile
[System.IO.Directory]::CreateDirectory($outDir) | Out-Null

function Get-CandidateSurfaces {
    param([string]$Language)

    switch -Regex ($Language) {
        "C#|F#" {
            return @("http-api-runner", "message-or-background-worker", "configuration-as-code", "custom-hook-host")
        }
        "Java|Kotlin|Scala" {
            return @("http-api-runner", "grpc-or-message-boundary", "mocker-dependency-simulation")
        }
        "JavaScript|TypeScript" {
            return @("http-api-runner", "frontend-contract-smoke", "node-service-dependency-mock")
        }
        "Python" {
            return @("http-api-runner", "cli-or-service-smoke", "mocker-dependency-simulation")
        }
        "Go|Rust" {
            return @("http-api-runner", "grpc-or-cli-smoke", "process-boundary-test")
        }
        default {
            return @("repo-contract-discovery-needed", "docs-only-smoke-plan")
        }
    }
}

function New-CampaignSourceOnlyBlocker {
    param(
        [string]$Repository
    )

    [ordered]@{
        blocker_id = "campaign-plan-repo-contract-missing"
        blocker_type = "repository_contract"
        description = "Top-repository popularity metadata is not enough to produce executable QaaS sessions, assertions, stubs, or cleanup for $Repository."
        required_evidence = @(
            "Public runtime/API/CLI contract",
            "Public input and expected-output contract",
            "Public dependency/stub contract",
            "Public cleanup contract"
        )
        public_evidence = @(
            "D:\QaaS\_tmp\zappa-dont-cry\top-repos\top-github-repos.json",
            "D:\QaaS\qaas-docs\docs"
        )
        unblock_instruction = "Harvest and review repository-visible contracts before promoting this campaign-plan record to executable QaaS artifacts."
    }
}

$records = foreach ($repo in $manifest.repositories) {
    $surfaces = @(Get-CandidateSurfaces -Language $repo.language)

    [ordered]@{
        rank = $repo.rank
        repository = $repo.full_name
        url = $repo.html_url
        language = $repo.language
        stars = $repo.stars
        candidate_qaas_surfaces = $surfaces
        required_public_docs = @(
            "README or public API docs from repository",
            "QaaS docs/schema evidence under D:\QaaS\qaas-docs\docs",
            "dependency readiness contract before live execution"
        )
        recommended_artifacts = @(
            "qaas-artifact-manifest.json",
            "test.qaas.yaml when a documented runtime boundary exists",
            "mocker.qaas.yaml when dependency contracts are public",
            "C# configuration-as-code only when YAML is insufficient"
        )
        test_plan_status = "blocked_until_repo_contract_review"
        blocker = "Top-repo metadata alone is insufficient for correct executable QaaS YAML/code. Inspect repository-visible contracts before generating artifacts."
        source_only_blockers = @((New-CampaignSourceOnlyBlocker -Repository $repo.full_name))
        airgapped_validation_required = $true
    }
}

$campaign = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    source_manifest = $RepoManifest
    count = @($records).Count
    contract_policy = "docs-only; no source-only QaaS claims; no executable tests from popularity metadata alone"
    qaas_docs_root = "D:\QaaS\qaas-docs\docs"
    repositories = @($records)
}

$campaign | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Output "Wrote campaign plan for $(@($records).Count) repositories to $OutFile"
