param(
    [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry",
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness",
    [string]$ExpectedSkillsFixture = "D:\QaaS\_tools\zappa-harness\fixtures\expected-skill-map.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Test-AbsoluteWindowsPath {
    param([string]$Path)
    return $Path -match '^[A-Za-z]:\\' -or $Path -match '^\\\\'
}

$manifestPath = Join-Path $Root "zappa-env.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Add-Failure "Missing environment manifest: $manifestPath"
} else {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    if ($manifest.schema_version -ne 1) {
        Add-Failure "Expected schema_version 1 in $manifestPath"
    }
    if ($manifest.environment_contract -ne "zappa-dynamic-env.v1") {
        Add-Failure "Unexpected environment_contract in $manifestPath"
    }
    if ($manifest.root -ne $Root) {
        Add-Failure "Manifest root mismatch. Expected $Root, got $($manifest.root)"
    }
    if ($manifest.skill_root -ne $SkillRoot) {
        Add-Failure "Manifest skill_root mismatch. Expected $SkillRoot, got $($manifest.skill_root)"
    }
    if ($manifest.harness_root -ne $HarnessRoot) {
        Add-Failure "Manifest harness_root mismatch. Expected $HarnessRoot, got $($manifest.harness_root)"
    }

    foreach ($topLevel in @("generated_root", "top_repos_root", "contracts_dir", "coverage_dir", "airgapped_dry_dir", "airgapped_live_dir", "blockers_dir", "strong_reviews_dir")) {
        if (-not ($manifest.PSObject.Properties.Name -contains $topLevel)) {
            Add-Failure "Manifest missing top-level path '$topLevel'"
            continue
        }
        $path = [string]$manifest.PSObject.Properties[$topLevel].Value
        if (-not (Test-AbsoluteWindowsPath $path)) {
            Add-Failure "Manifest path is not absolute: $topLevel => $path"
        }
    }

    foreach ($name in @("root", "top_repos", "contracts", "coverage", "generated_tests", "generated_docs_coverage", "generated_top_repos", "airgapped_runs", "airgapped_dry", "airgapped_live", "strong_reviews", "blockers", "harness_runs", "dynamic_sessions", "session_templates", "scratch")) {
        if (-not ($manifest.directories.PSObject.Properties.Name -contains $name)) {
            Add-Failure "Manifest directories missing '$name'"
            continue
        }
        $dir = [string]$manifest.directories.PSObject.Properties[$name].Value
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            Add-Failure "Manifest directory does not exist: $name => $dir"
        }
    }

    if (-not (Test-Path -LiteralPath $ExpectedSkillsFixture)) {
        Add-Failure "Missing expected skills fixture: $ExpectedSkillsFixture"
    } else {
        $expected = Get-Content -LiteralPath $ExpectedSkillsFixture -Raw | ConvertFrom-Json
        $expectedNames = @($expected.requiredSkills | ForEach-Object { [string]$_ } | Sort-Object)
        $actualNames = @($manifest.skills | ForEach-Object { [string]$_ } | Sort-Object)
        if (($expectedNames -join "|") -ne ($actualNames -join "|")) {
            Add-Failure "Manifest skill list mismatch. Expected '$($expectedNames -join ',')', got '$($actualNames -join ',')'"
        }
    }

    foreach ($skill in @($manifest.skills)) {
        $skillPath = Join-Path $SkillRoot ([string]$skill)
        $skillFile = Join-Path $skillPath "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillFile)) {
            Add-Failure "Manifest skill is not installed with SKILL.md: $skill"
        }
    }

    if (-not (Test-Path -LiteralPath ([string]$manifest.weak_model_policy))) {
        Add-Failure "Weak-model policy path from manifest does not exist: $($manifest.weak_model_policy)"
    } else {
        $policyText = Get-Content -LiteralPath ([string]$manifest.weak_model_policy) -Raw
        if ($policyText -notmatch [regex]::Escape("airgapped models")) {
            Add-Failure "Weak-model policy does not include trigger phrase 'airgapped models'"
        }
    }

    $airgappedPath = [string]$manifest.session_templates.airgapped
    if (-not (Test-Path -LiteralPath $airgappedPath)) {
        Add-Failure "Missing airgapped session template: $airgappedPath"
    } else {
        $airgapped = Get-Content -LiteralPath $airgappedPath -Raw | ConvertFrom-Json
        if ($airgapped.dry_output_dir -ne $manifest.airgapped_dry_dir) {
            Add-Failure "Airgapped session template dry_output_dir must match manifest airgapped_dry_dir"
        }
        if ($airgapped.live_output_dir -ne $manifest.airgapped_live_dir) {
            Add-Failure "Airgapped session template live_output_dir must match manifest airgapped_live_dir"
        }
        if ($airgapped.expected_harness -ne "claude-copilot") {
            Add-Failure "Airgapped session template has wrong expected_harness"
        }
        $expectedModels = @("id:gpt-3.5-turbo", "id:gpt-3.5-turbo-0613", "gpt-4o-mini", "gpt-4o-mini-2024-07-18")
        foreach ($expectedModel in $expectedModels) {
            if (@($airgapped.expected_models) -notcontains $expectedModel) {
                Add-Failure "Airgapped session template missing expected model: $expectedModel"
            }
        }
        foreach ($expectedArgument in @("-Airgapped", "-All", "-ReasoningEffort", "none")) {
            if (@($airgapped.default_arguments) -notcontains $expectedArgument) {
                Add-Failure "Airgapped session template missing default argument: $expectedArgument"
            }
        }
        if ($airgapped.dry_run_is_prompt_assembly_only -ne $true) {
            Add-Failure "Airgapped session template must label dry runs as prompt assembly only"
        }
        if ($airgapped.live_validation_required_for_completion -ne $true) {
            Add-Failure "Airgapped session template must require live validation for completion"
        }
    }

    $promotionPath = [string]$manifest.session_templates.promotion_policy
    if (-not (Test-Path -LiteralPath $promotionPath)) {
        Add-Failure "Missing promotion policy template: $promotionPath"
    } else {
        $promotion = Get-Content -LiteralPath $promotionPath -Raw | ConvertFrom-Json
        if ($promotion.default_state -ne "blocked") {
            Add-Failure "Promotion policy default_state must be blocked"
        }
        foreach ($required in @("repository_visible_contract", "qaas_docs_evidence", "runner_or_mocker_template_build_evidence", "executable_test_result", "live_airgapped_validation_or_recorded_quota_blocker")) {
            if (@($promotion.required_to_promote) -notcontains $required) {
                Add-Failure "Promotion policy missing required gate: $required"
            }
        }
        foreach ($forbidden in @("structural_manifest_validation_only", "dry_run_weak_model_prompt_assembly_only")) {
            if (@($promotion.forbidden_completion_evidence) -notcontains $forbidden) {
                Add-Failure "Promotion policy missing forbidden completion evidence: $forbidden"
            }
        }
    }

    foreach ($command in @("Invoke-ZappaHarness.ps1 -Suite smoke", "Invoke-ZappaHarness.ps1 -Suite all", "weak-model-session.ps1 -Airgapped")) {
        if (-not (@($manifest.validation_commands) -match [regex]::Escape($command))) {
            Add-Failure "Manifest validation_commands missing command fragment: $command"
        }
    }

    if ($failures.Count -eq 0) {
        $sentinels = New-Object System.Collections.Generic.List[string]
        foreach ($name in @($manifest.directories.PSObject.Properties.Name)) {
            $dir = [string]$manifest.directories.PSObject.Properties[$name].Value
            $sentinel = Join-Path $dir ".zappa-env-idempotence-sentinel"
            "preserve:$name" | Set-Content -LiteralPath $sentinel -Encoding UTF8
            $sentinels.Add($sentinel)
        }

        $bootstrap = Join-Path $HarnessRoot "scripts\bootstrap-zappa-env.ps1"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $bootstrap -Root $Root -SkillRoot $SkillRoot -HarnessRoot $HarnessRoot | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "Bootstrap idempotence rerun failed with exit code $LASTEXITCODE"
        }

        foreach ($sentinel in $sentinels) {
            if (-not (Test-Path -LiteralPath $sentinel)) {
                Add-Failure "Bootstrap idempotence rerun removed sentinel: $sentinel"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $SkillRoot -PathType Container)) {
    Add-Failure "Skill root does not exist: $SkillRoot"
} else {
    $badRootEntries = @(Get-ChildItem -LiteralPath $SkillRoot -Force | Where-Object {
        -not $_.PSIsContainer -or -not (Test-Path -LiteralPath (Join-Path $_.FullName "SKILL.md"))
    })
    if ($badRootEntries.Count -gt 0) {
        Add-Failure "zappa-dont-cry root contains non-skill entries: $($badRootEntries.FullName -join ', ')"
    }
}

if (-not (Test-Path -LiteralPath $HarnessRoot -PathType Container)) {
    Add-Failure "Harness root does not exist: $HarnessRoot"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Zappa dynamic environment contract check passed."
