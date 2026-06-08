param(
    [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry",
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$HarnessRoot = "",
    [string]$QaaSDocsRoot = "D:\QaaS\qaas-docs\docs",
    [string]$WeakModelPolicyPath = "D:\QaaS\_tools\weak-model-policy.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($HarnessRoot)) {
    $HarnessRoot = Split-Path -Parent $PSScriptRoot
}

$Root = [System.IO.Path]::GetFullPath($Root)
$SkillRoot = [System.IO.Path]::GetFullPath($SkillRoot)
$HarnessRoot = [System.IO.Path]::GetFullPath($HarnessRoot)
$QaaSDocsRoot = [System.IO.Path]::GetFullPath($QaaSDocsRoot)
$WeakModelPolicyPath = [System.IO.Path]::GetFullPath($WeakModelPolicyPath)

$dirs = [ordered]@{
    root = $Root
    top_repos = Join-Path $Root "top-repos"
    contracts = Join-Path $Root "top-repos\contracts"
    coverage = Join-Path $Root "coverage"
    generated_tests = Join-Path $Root "generated-tests"
    generated_docs_coverage = Join-Path $Root "generated-tests\docs-coverage"
    generated_top_repos = Join-Path $Root "generated-tests\top-repos"
    airgapped_runs = Join-Path $Root "airgapped-runs"
    airgapped_dry = Join-Path $Root "airgapped-runs\dry"
    airgapped_live = Join-Path $Root "airgapped-runs\live"
    strong_reviews = Join-Path $Root "strong-reviews"
    blockers = Join-Path $Root "blockers"
    harness_runs = Join-Path $Root "harness-runs"
    dynamic_sessions = Join-Path $Root "dynamic-sessions"
    session_templates = Join-Path $Root "dynamic-sessions\templates"
    scratch = Join-Path $Root "scratch"
}

foreach ($key in @($dirs.Keys)) {
    $dirs[$key] = [System.IO.Path]::GetFullPath([string]$dirs[$key])
}

foreach ($dir in $dirs.Values) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$skillNames = @()
if (Test-Path -LiteralPath $SkillRoot) {
    $skillNames = @(Get-ChildItem -LiteralPath $SkillRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md") } |
        Sort-Object Name |
        Select-Object -ExpandProperty Name)
}

$airgappedProfilePath = Join-Path $dirs.session_templates "airgapped-session-profile.json"
$airgappedProfile = [ordered]@{
    schema_version = 1
    profile_name = "airgapped"
    launcher = "D:\QaaS\_tools\weak-model-session.ps1"
    default_arguments = @("-Airgapped", "-All", "-ReasoningEffort", "none", "-RejectPattern", "SKILL_NOT_FOUND")
    dry_output_dir = $dirs.airgapped_dry
    live_output_dir = $dirs.airgapped_live
    expected_harness = "claude-copilot"
    expected_profile = "airgapped"
    expected_models = @("id:gpt-3.5-turbo", "id:gpt-3.5-turbo-0613", "gpt-4o-mini", "gpt-4o-mini-2024-07-18")
    dry_run_is_prompt_assembly_only = $true
    live_validation_required_for_completion = $true
    live_quota_blocker = "github_copilot_additional_spend_limit_reached"
}
$airgappedProfile | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $airgappedProfilePath -Encoding UTF8

$promotionPolicyPath = Join-Path $dirs.session_templates "promotion-policy.json"
$promotionPolicy = [ordered]@{
    schema_version = 1
    default_state = "blocked"
    docs_only_assumption = "public_qaaS_docs_and_schema_only_unless_user_explicitly_provides_source"
    required_to_promote = @(
        "repository_visible_contract",
        "qaas_docs_evidence",
        "runner_or_mocker_template_build_evidence",
        "executable_test_result",
        "live_airgapped_validation_or_recorded_quota_blocker"
    )
    forbidden_completion_evidence = @(
        "structural_manifest_validation_only",
        "dry_run_weak_model_prompt_assembly_only",
        "strong_model_review_without_docs_evidence"
    )
}
$promotionPolicy | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $promotionPolicyPath -Encoding UTF8

$manifest = [ordered]@{
    schema_version = 1
    environment_contract = "zappa-dynamic-env.v1"
    created_at = (Get-Date).ToString("o")
    root = $Root
    skill_root = $SkillRoot
    harness_root = $HarnessRoot
    qaas_docs_root = $QaaSDocsRoot
    weak_model_policy = $WeakModelPolicyPath
    generated_root = $dirs.generated_tests
    top_repos_root = $dirs.top_repos
    contracts_dir = $dirs.contracts
    coverage_dir = $dirs.coverage
    airgapped_dry_dir = $dirs.airgapped_dry
    airgapped_live_dir = $dirs.airgapped_live
    blockers_dir = $dirs.blockers
    strong_reviews_dir = $dirs.strong_reviews
    directories = $dirs
    skills = $skillNames
    session_templates = [ordered]@{
        airgapped = $airgappedProfilePath
        promotion_policy = $promotionPolicyPath
    }
    validation_commands = @(
        "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite smoke",
        "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite all",
        "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none -SkillPath <skill> -Prompt <prompt>"
    )
    completion_policy = "blocked_until_executable_qaaS_evidence_and_live_or_explicitly_blocked_airgapped_evidence"
    status = "initialized"
}

$manifestPath = Join-Path $Root "zappa-env.json"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Output "Zappa environment ready: $Root"
Write-Output "Manifest: $manifestPath"
