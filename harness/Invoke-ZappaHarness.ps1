param(
    [ValidateSet("all", "smoke", "environment", "default-environment", "layout", "metadata", "skill-quality", "skill-output-contracts", "objective-coverage", "intent-assumptions", "intent-clarification", "source-only-blockers", "qaas-yaml-schema", "completion-readiness", "strong-review", "weak-routing", "weak-scenarios", "weak-adversarial", "weak-adversarial-scenarios", "weak-suite-runner", "weak-scenario-live-index", "weak-adversarial-live-index", "weak-scenario-outputs", "weak-adversarial-outputs", "airgapped-live", "copilot-fallback", "artifacts", "promotion", "promotion-index", "promotion-packet", "promotion-seed", "top250", "contracts", "selected-contracts", "selected-candidates", "selected-promotion-readiness", "selected-lifecycle", "selected-live", "top-repo-triage", "docs-coverage", "compile", "harness-regression", "refresh-top250")]
    [string]$Suite = "smoke",
    [ValidateSet("all", "docs-coverage", "top-repos")]
    [string]$Target = "all",
    [switch]$DryRunOnly,
    [string]$RunRoot = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$harnessRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry"
$generatedRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests"
$runDir = Join-Path $RunRoot (Get-Date -Format "yyyyMMdd-HHmmss-fff")
[System.IO.Directory]::CreateDirectory($runDir) | Out-Null
$suiteStarted = Get-Date

$results = New-Object System.Collections.Generic.List[object]

function Invoke-HarnessCommand {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    $logPath = Join-Path $runDir "$Name.log"
    $exitCode = 0
    $started = Get-Date
    $commandText = $Script.ToString().Trim()
    try {
        $global:LASTEXITCODE = 0
        $output = & $Script 2>&1
        $exitCode = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 0 }
    } catch {
        $output = @($_.Exception.ToString())
        $exitCode = 1
    }

    $output | Set-Content -LiteralPath $logPath -Encoding UTF8
    $durationMs = [int]((Get-Date) - $started).TotalMilliseconds
    $logText = ($output | Out-String)
    $errorPattern = '(?m)^(ERROR:|Traceback|ParserError|PropertyNotFoundStrict|Cannot find path|Write-Error)'
    if ($exitCode -eq 0 -and $logText -match $errorPattern) {
        $exitCode = 1
    }

    $firstErrorExcerpt = $null
    if ($exitCode -ne 0) {
        $match = [regex]::Match($logText, $errorPattern)
        if ($match.Success) {
            $start = [Math]::Max(0, $match.Index - 120)
            $length = [Math]::Min(800, $logText.Length - $start)
            $firstErrorExcerpt = $logText.Substring($start, $length).Trim()
        } elseif ($logText.Length -gt 0) {
            $firstErrorExcerpt = $logText.Substring(0, [Math]::Min(800, $logText.Length)).Trim()
        }
    }

    $result = [ordered]@{
        name = $Name
        command = $commandText
        duration_ms = $durationMs
        status = if ($exitCode -eq 0) { "passed" } else { "failed" }
        exit_code = $exitCode
        log = $logPath
        first_error_excerpt = $firstErrorExcerpt
    }
    $results.Add($result)
    Write-Output "$($result.status): $Name"
}

function Add-LayoutChecks {
    Invoke-HarnessCommand "skill-layout" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SkillLayout.ps1") -SkillRoot $skillRoot }
}

function Add-EnvironmentCheck {
    Invoke-HarnessCommand "zappa-environment" {
        $envRoot = Join-Path $runDir "dynamic-env"
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\bootstrap-zappa-env.ps1") -Root $envRoot -SkillRoot $skillRoot -HarnessRoot $harnessRoot
        if ($LASTEXITCODE -ne 0) {
            throw "bootstrap-zappa-env.ps1 failed with exit code $LASTEXITCODE"
        }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-ZappaEnvironment.ps1") -Root $envRoot -SkillRoot $skillRoot -HarnessRoot $harnessRoot
    }
}

function Add-DefaultEnvironmentCheck {
    Invoke-HarnessCommand "default-zappa-environment" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-DefaultZappaEnvironment.ps1") -Root "D:\QaaS\_tmp\zappa-dont-cry" -SkillRoot $skillRoot -HarnessRoot $harnessRoot }
}

function Add-MetadataChecks {
    Invoke-HarnessCommand "skill-metadata" { & python (Join-Path $harnessRoot "checks\Check-SkillMetadata.py") $skillRoot }
    Invoke-HarnessCommand "agent-metadata" { & python (Join-Path $harnessRoot "checks\Check-AgentMetadata.py") $skillRoot }
    Invoke-HarnessCommand "zappa-pack" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\validate-zappa-pack.ps1") -Root $skillRoot -HarnessRoot $harnessRoot }
}

function Add-SkillQualityChecks {
    Invoke-HarnessCommand "skill-quality" { & python (Join-Path $harnessRoot "checks\Check-SkillQuality.py") $skillRoot }
}

function Add-SkillOutputContractCheck {
    Invoke-HarnessCommand "skill-output-contracts" { & python (Join-Path $harnessRoot "checks\Check-SkillOutputContracts.py") $skillRoot (Join-Path $harnessRoot "fixtures\skill-output-contracts.json") }
}

function Add-ObjectiveCoverageCheck {
    Invoke-HarnessCommand "objective-coverage" { & python (Join-Path $harnessRoot "checks\Check-ObjectiveCoverage.py") $skillRoot $harnessRoot (Join-Path $harnessRoot "fixtures\objective-capability-map.json") "D:\QaaS\_tmp\zappa-dont-cry\coverage" }
}

function Add-IntentAssumptionsCheck {
    Invoke-HarnessCommand "intent-assumptions-schema" { & python (Join-Path $harnessRoot "checks\Check-IntentAssumptionsSchema.py") $generatedRoot }
}

function Add-IntentClarificationCheck {
    Invoke-HarnessCommand "intent-clarification-coverage" { & python (Join-Path $harnessRoot "checks\Check-IntentClarificationCoverage.py") $generatedRoot "D:\QaaS\_tmp\zappa-dont-cry\coverage" }
}

function Add-SourceOnlyBlockersCheck {
    Invoke-HarnessCommand "source-only-blockers" { & python (Join-Path $harnessRoot "checks\Check-SourceOnlyBlockers.py") $generatedRoot }
}

function Add-QaaSYamlSchemaCheck {
    Invoke-HarnessCommand "qaas-yaml-schema-evidence" { & python (Join-Path $harnessRoot "checks\Check-QaaSYamlSchemaEvidence.py") $generatedRoot "D:\QaaS\qaas-docs\docs\assets\schemas" "D:\QaaS\_tmp\zappa-dont-cry\coverage" }
}

function Add-CompletionReadinessCheck {
    Invoke-HarnessCommand "completion-readiness" { & python (Join-Path $harnessRoot "checks\Check-ObjectiveCompletionReadiness.py") "D:\QaaS\_tmp\zappa-dont-cry\generated-tests" "D:\QaaS\_tmp\zappa-dont-cry\coverage\objective-capability-coverage.json" "D:\QaaS\_tmp\zappa-dont-cry\blockers" }
}

function Add-StrongReviewEvidenceCheck {
    Invoke-HarnessCommand "strong-review-evidence" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-StrongReviewEvidence.ps1") }
}

function Add-ArtifactChecks {
    Invoke-HarnessCommand "artifact-manifests-$Target" { & python (Join-Path $harnessRoot "checks\Check-GeneratedArtifacts.py") $generatedRoot $Target }
    if ($Target -eq "all" -or $Target -eq "docs-coverage") {
        Invoke-HarnessCommand "legacy-docs-artifact-validator" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\validate-generated-artifacts.ps1") -Root (Join-Path $generatedRoot "docs-coverage") -IndexFileName "coverage-skeleton-index.json" }
    }
    if ($Target -eq "all" -or $Target -eq "top-repos") {
        Invoke-HarnessCommand "legacy-top-artifact-validator" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\validate-generated-artifacts.ps1") -Root (Join-Path $generatedRoot "top-repos") -IndexFileName "top-repo-artifact-index.json" }
    }
}

function Add-CompileCheck {
    Invoke-HarnessCommand "compile-generated-csharp" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Compile-GeneratedCSharp.ps1") -Root $generatedRoot -OutDir (Join-Path $runDir "compile") }
}

function Add-HarnessRegressionCheck {
    Invoke-HarnessCommand "harness-regression-tests" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-HarnessRegressionTests.ps1") -HarnessRoot $harnessRoot -OutDir (Join-Path $runDir "harness-regression") }
    Invoke-HarnessCommand "deno-selected-candidate-regression" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-DenoSelectedCandidateRegression.ps1") -HarnessRoot $harnessRoot -OutDir (Join-Path $runDir "harness-regression\deno-selected-candidate") }
}

function Add-PromotionCheck {
    Invoke-HarnessCommand "promotion-readiness" { & python (Join-Path $harnessRoot "checks\Check-PromotionReadiness.py") $generatedRoot }
    Invoke-HarnessCommand "promotion-candidate-index" { & python (Join-Path $harnessRoot "checks\Check-PromotionCandidateIndex.py") $generatedRoot "D:\QaaS\_tmp\zappa-dont-cry\coverage" }
    Invoke-HarnessCommand "promotion-packet" { & python (Join-Path $harnessRoot "checks\Check-PromotionPacket.py") $generatedRoot "D:\QaaS\_tmp\zappa-dont-cry\coverage" "D:\QaaS\_tmp\zappa-dont-cry\promotion-packets" }
    Invoke-HarnessCommand "dependency-gates" { & python (Join-Path $harnessRoot "checks\Check-DependencyGates.py") $generatedRoot }
    Invoke-HarnessCommand "executable-artifact-shape" { & python (Join-Path $harnessRoot "checks\Check-ExecutableArtifactShape.py") $generatedRoot }
    Invoke-HarnessCommand "qaas-template-build-evidence" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-QaaSTemplateBuildEvidence.ps1") -Root $generatedRoot }
    Invoke-HarnessCommand "docs-evidence-coverage" { & python (Join-Path $harnessRoot "checks\Check-DocsEvidenceCoverage.py") $generatedRoot }
    Invoke-HarnessCommand "index-manifest-consistency" { & python (Join-Path $harnessRoot "checks\Check-IndexManifestConsistency.py") $generatedRoot }
    Invoke-HarnessCommand "top-repo-promotion-evidence" { & python (Join-Path $harnessRoot "checks\Check-TopRepoPromotionEvidence.py") }
}

function Add-PromotionSeedCheck {
    Invoke-HarnessCommand "promotion-seed-lifecycle" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\generate-promotion-seed.ps1") -HarnessRoot $harnessRoot
        if ($LASTEXITCODE -ne 0) {
            throw "generate-promotion-seed.ps1 failed with exit code $LASTEXITCODE"
        }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-PromotionSeedLifecycle.ps1")
    }
}

function Add-Top250Check {
    Invoke-HarnessCommand "top250" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-Top250.ps1") }
}

function Add-ContractsCheck {
    Invoke-HarnessCommand "contracts" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-ContractHarvest.ps1") }
}

function Add-SelectedTopRepoContractsCheck {
    Invoke-HarnessCommand "selected-top-repo-contracts" { & python (Join-Path $harnessRoot "checks\Check-SelectedTopRepoContracts.py") "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts" "D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts" (Join-Path $generatedRoot "top-repos") "D:\QaaS\_tmp\zappa-dont-cry\coverage" }
}

function Add-SelectedTopRepoCandidatesCheck {
    Invoke-HarnessCommand "selected-top-repo-candidates" { & python (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidates.py") (Join-Path $generatedRoot "selected-top-repo-candidates") "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts" "D:\QaaS\_tmp\zappa-dont-cry\coverage" }
    Invoke-HarnessCommand "selected-candidate-promotion-readiness" { & python (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidatePromotionReadiness.py") (Join-Path $generatedRoot "selected-top-repo-candidates") "D:\QaaS\_tmp\zappa-dont-cry\coverage" }
}

function Add-SelectedTopRepoCandidateLifecycleCheck {
    Invoke-HarnessCommand "selected-top-repo-candidate-lifecycle" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1") }
    Invoke-HarnessCommand "selected-top-repo-candidate-lifecycle-flask" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1") `
            -SummaryPath "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle-flask.json" `
            -CandidateDir "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\227-pallets-flask"
    }
    Invoke-HarnessCommand "selected-top-repo-candidate-lifecycle-express" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1") `
            -SummaryPath "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle-express.json" `
            -CandidateDir "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\243-expressjs-express"
    }
    Invoke-HarnessCommand "selected-top-repo-candidate-lifecycle-fastapi" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1") `
            -SummaryPath "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle-fastapi.json" `
            -CandidateDir "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\114-fastapi-fastapi"
    }
    Invoke-HarnessCommand "selected-top-repo-candidate-lifecycle-gin" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1") `
            -SummaryPath "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle-gin.json" `
            -CandidateDir "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\138-gin-gonic-gin"
    }
    Invoke-HarnessCommand "selected-top-repo-candidate-lifecycle-deno" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1") `
            -SummaryPath "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle-deno.json" `
            -CandidateDir "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\098-denoland-deno"
    }
    Invoke-HarnessCommand "selected-top-repo-candidate-lifecycle-crawl4ai" {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1") `
            -SummaryPath "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle-crawl4ai.json" `
            -CandidateDir "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\250-unclecode-crawl4ai"
    }
}

function Add-SelectedTopRepoCandidateLiveCheck {
    Invoke-HarnessCommand "selected-top-repo-candidate-live" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLive.ps1") }
    Invoke-HarnessCommand "selected-top-repo-candidate-live-flask" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLiveFlask.ps1") }
    Invoke-HarnessCommand "selected-top-repo-candidate-live-express" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLiveExpress.ps1") }
    Invoke-HarnessCommand "selected-top-repo-candidate-live-fastapi" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLiveFastApi.ps1") }
    Invoke-HarnessCommand "selected-top-repo-candidate-live-gin" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLiveGin.ps1") }
    Invoke-HarnessCommand "selected-top-repo-candidate-live-deno" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLiveDeno.ps1") }
    Invoke-HarnessCommand "selected-top-repo-candidate-live-crawl4ai" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidateLiveCrawl4Ai.ps1") }
}

function Add-TopRepoPromotionTriageCheck {
    Invoke-HarnessCommand "top-repo-promotion-triage" { & python (Join-Path $harnessRoot "checks\Check-TopRepoPromotionTriage.py") "D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts" (Join-Path $generatedRoot "top-repos") "D:\QaaS\_tmp\zappa-dont-cry\coverage" 250 }
}

function Add-DocsCoverageCheck {
    Invoke-HarnessCommand "docs-coverage" { & python (Join-Path $harnessRoot "checks\Check-DocsCoverage.py") }
}

function Add-WeakRoutingCheck {
    Invoke-HarnessCommand "weak-routing" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakModelRouting.ps1") -SkillRoot $skillRoot -OutDir (Join-Path $runDir "weak-routing") }
}

function Add-WeakScenarioCheck {
    Invoke-HarnessCommand "weak-scenarios" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakModelScenarios.ps1") -SkillRoot $skillRoot -OutDir (Join-Path $runDir "weak-scenarios") }
}

function Add-WeakAdversarialScenarioCheck {
    Invoke-HarnessCommand "weak-adversarial-scenarios" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakModelAdversarialScenarios.ps1") -SkillRoot $skillRoot -OutDir (Join-Path $runDir "weak-adversarial-scenarios") }
}

function Add-WeakSuiteRunnerCheck {
    Invoke-HarnessCommand "weak-suite-runner" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakScenarioSuiteRunner.ps1") -HarnessRoot $harnessRoot -SkillRoot $skillRoot -OutDir (Join-Path $runDir "weak-suite-runner") }
}

function Add-WeakScenarioLiveIndexCheck {
    Invoke-HarnessCommand "weak-scenario-live-index" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live-scenarios" -FixturePath (Join-Path $harnessRoot "fixtures\weak-skill-scenarios.json") -BlockersDir "D:\QaaS\_tmp\zappa-dont-cry\blockers" -IndexFileName "weak-scenario-live-index-latest.json" }
}

function Add-WeakAdversarialLiveIndexCheck {
    Invoke-HarnessCommand "weak-adversarial-live-index" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1") -EvidenceRoot "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live-adversarial-scenarios" -FixturePath (Join-Path $harnessRoot "fixtures\weak-adversarial-scenarios.json") -BlockersDir "D:\QaaS\_tmp\zappa-dont-cry\blockers" -IndexFileName "weak-adversarial-live-index-latest.json" }
}

function Add-WeakScenarioOutputCheck {
    Add-WeakScenarioLiveIndexCheck
    Invoke-HarnessCommand "weak-scenario-outputs" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakModelScenarioOutputs.ps1") }
}

function Add-WeakAdversarialOutputCheck {
    Add-WeakAdversarialLiveIndexCheck
    Invoke-HarnessCommand "weak-adversarial-outputs" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-WeakModelAdversarialOutputs.ps1") }
}

function Add-AirgappedLiveEvidenceCheck {
    Invoke-HarnessCommand "airgapped-live-evidence" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-AirgappedLiveEvidence.ps1") -EvidenceRoot "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live" -BlockersDir "D:\QaaS\_tmp\zappa-dont-cry\blockers" }
}

function Add-CopilotFallbackEvidenceCheck {
    Invoke-HarnessCommand "copilot-fallback-evidence" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-CopilotFallbackEvidence.ps1") -EvidenceRoot "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs\live-copilot-fallback" -BlockersDir "D:\QaaS\_tmp\zappa-dont-cry\blockers" }
}

function Invoke-RefreshTop250 {
    Invoke-HarnessCommand "refresh-fetch-top250" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\fetch-top-github-repos.ps1") -Count 250 }
    Invoke-HarnessCommand "refresh-campaign" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\generate-top-repos-campaign.ps1") }
    Invoke-HarnessCommand "refresh-contracts" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\harvest-top-repo-contracts.ps1") -Offset 0 -Count 250 -Clean }
    Invoke-HarnessCommand "refresh-selected-contracts" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\harvest-selected-top-repo-contracts.ps1") -Clean }
    Invoke-HarnessCommand "refresh-selected-candidates" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\generate-selected-top-repo-candidates.ps1") -Clean }
    Invoke-HarnessCommand "refresh-top-artifacts" { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "scripts\generate-top-repo-artifacts.ps1") }
}

switch ($Suite) {
    "layout" { Add-LayoutChecks }
    "environment" { Add-EnvironmentCheck }
    "default-environment" { Add-DefaultEnvironmentCheck }
    "metadata" { Add-MetadataChecks }
    "skill-quality" { Add-SkillQualityChecks }
    "skill-output-contracts" { Add-SkillOutputContractCheck }
    "objective-coverage" { Add-ObjectiveCoverageCheck }
    "intent-assumptions" { Add-IntentAssumptionsCheck }
    "intent-clarification" { Add-IntentClarificationCheck }
    "source-only-blockers" { Add-SourceOnlyBlockersCheck }
    "qaas-yaml-schema" { Add-QaaSYamlSchemaCheck }
    "completion-readiness" { Add-CompletionReadinessCheck }
    "strong-review" { Add-StrongReviewEvidenceCheck }
    "weak-routing" { Add-WeakRoutingCheck }
    "weak-scenarios" { Add-WeakScenarioCheck }
    "weak-adversarial-scenarios" { Add-WeakAdversarialScenarioCheck }
    "weak-adversarial" { Add-WeakAdversarialScenarioCheck }
    "weak-suite-runner" { Add-WeakSuiteRunnerCheck }
    "weak-scenario-live-index" { Add-WeakScenarioLiveIndexCheck }
    "weak-adversarial-live-index" { Add-WeakAdversarialLiveIndexCheck }
    "weak-scenario-outputs" { Add-WeakScenarioOutputCheck }
    "weak-adversarial-outputs" { Add-WeakAdversarialOutputCheck }
    "airgapped-live" { Add-AirgappedLiveEvidenceCheck }
    "copilot-fallback" { Add-CopilotFallbackEvidenceCheck }
    "artifacts" { Add-ArtifactChecks }
    "promotion" { Add-PromotionCheck }
    "promotion-index" { Invoke-HarnessCommand "promotion-candidate-index" { & python (Join-Path $harnessRoot "checks\Check-PromotionCandidateIndex.py") $generatedRoot "D:\QaaS\_tmp\zappa-dont-cry\coverage" } }
    "promotion-packet" { Invoke-HarnessCommand "promotion-packet" { & python (Join-Path $harnessRoot "checks\Check-PromotionPacket.py") $generatedRoot "D:\QaaS\_tmp\zappa-dont-cry\coverage" "D:\QaaS\_tmp\zappa-dont-cry\promotion-packets" } }
    "promotion-seed" { Add-PromotionSeedCheck }
    "top250" { Add-Top250Check }
    "contracts" { Add-ContractsCheck }
    "selected-contracts" { Add-SelectedTopRepoContractsCheck }
    "selected-candidates" { Add-SelectedTopRepoCandidatesCheck }
    "selected-promotion-readiness" { Invoke-HarnessCommand "selected-candidate-promotion-readiness" { & python (Join-Path $harnessRoot "checks\Check-SelectedTopRepoCandidatePromotionReadiness.py") (Join-Path $generatedRoot "selected-top-repo-candidates") "D:\QaaS\_tmp\zappa-dont-cry\coverage" } }
    "selected-lifecycle" { Add-SelectedTopRepoCandidateLifecycleCheck }
    "selected-live" { Add-SelectedTopRepoCandidateLiveCheck }
    "top-repo-triage" { Add-TopRepoPromotionTriageCheck }
    "docs-coverage" { Add-DocsCoverageCheck }
    "compile" { Add-CompileCheck }
    "harness-regression" { Add-HarnessRegressionCheck }
    "refresh-top250" { Invoke-RefreshTop250; Add-Top250Check; Add-ContractsCheck; Add-SelectedTopRepoContractsCheck; Add-SelectedTopRepoCandidatesCheck; Add-TopRepoPromotionTriageCheck; Add-ArtifactChecks; Add-CompileCheck }
    "smoke" {
        Add-EnvironmentCheck
        Add-DefaultEnvironmentCheck
        Add-LayoutChecks
        Add-MetadataChecks
        Add-SkillQualityChecks
        Add-SkillOutputContractCheck
        Add-ObjectiveCoverageCheck
        Add-Top250Check
        Add-ContractsCheck
        Add-SelectedTopRepoContractsCheck
        Add-SelectedTopRepoCandidatesCheck
        Add-SelectedTopRepoCandidateLifecycleCheck
        Add-SelectedTopRepoCandidateLiveCheck
        Add-TopRepoPromotionTriageCheck
        Add-PromotionSeedCheck
        Add-DocsCoverageCheck
        Add-ArtifactChecks
        Add-IntentAssumptionsCheck
        Add-IntentClarificationCheck
        Add-SourceOnlyBlockersCheck
        Add-QaaSYamlSchemaCheck
        Add-PromotionCheck
        Add-CompileCheck
        Add-HarnessRegressionCheck
        Add-AirgappedLiveEvidenceCheck
        Add-CopilotFallbackEvidenceCheck
        Add-WeakSuiteRunnerCheck
        Add-WeakScenarioOutputCheck
        Add-WeakAdversarialOutputCheck
        Add-CompletionReadinessCheck
        Add-WeakScenarioCheck
        Add-WeakAdversarialScenarioCheck
    }
    "all" {
        Add-EnvironmentCheck
        Add-DefaultEnvironmentCheck
        Add-LayoutChecks
        Add-MetadataChecks
        Add-SkillQualityChecks
        Add-SkillOutputContractCheck
        Add-ObjectiveCoverageCheck
        Add-Top250Check
        Add-ContractsCheck
        Add-SelectedTopRepoContractsCheck
        Add-SelectedTopRepoCandidatesCheck
        Add-SelectedTopRepoCandidateLifecycleCheck
        Add-SelectedTopRepoCandidateLiveCheck
        Add-TopRepoPromotionTriageCheck
        Add-PromotionSeedCheck
        Add-DocsCoverageCheck
        Add-ArtifactChecks
        Add-IntentAssumptionsCheck
        Add-IntentClarificationCheck
        Add-SourceOnlyBlockersCheck
        Add-QaaSYamlSchemaCheck
        Add-PromotionCheck
        Add-CompileCheck
        Add-HarnessRegressionCheck
        Add-WeakRoutingCheck
        Add-WeakScenarioCheck
        Add-WeakAdversarialScenarioCheck
        Add-AirgappedLiveEvidenceCheck
        Add-CopilotFallbackEvidenceCheck
        Add-WeakSuiteRunnerCheck
        Add-WeakScenarioOutputCheck
        Add-WeakAdversarialOutputCheck
        Add-CompletionReadinessCheck
    }
}

$passedCount = @($results | Where-Object { $_["status"] -eq "passed" }).Count
$failedCount = @($results | Where-Object { $_["status"] -ne "passed" }).Count

$report = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    suite = $Suite
    target = $Target
    run_dir = $runDir
    overall_status = if ($failedCount -eq 0) { "passed" } else { "failed" }
    duration_ms = [int]((Get-Date) - $suiteStarted).TotalMilliseconds
    summary = [ordered]@{
        total = $results.Count
        passed = $passedCount
        failed = $failedCount
    }
    results = $results.ToArray()
}

$jsonPath = Join-Path $runDir "report.json"
$mdPath = Join-Path $runDir "report.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Zappa Harness Report")
$md.Add("")
$md.Add("Suite: $Suite")
$md.Add("Target: $Target")
$md.Add("Run: $runDir")
$md.Add("")
foreach ($result in $results) {
    $md.Add(("- {0}: {1} (`{2}`)" -f $result["status"], $result["name"], $result["log"]))
}
$md | Set-Content -LiteralPath $mdPath -Encoding UTF8

$reportCheckOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $harnessRoot "checks\Check-HarnessReport.ps1") -ReportPath $jsonPath 2>&1
if ($LASTEXITCODE -ne 0) {
    $reportCheckOutput | Write-Output
    Write-Error "Harness report self-check failed."
    exit 1
}

$failed = @($results | Where-Object { $_.status -ne "passed" })
Write-Output "Report: $jsonPath"
if ($failed.Count -gt 0) {
    Write-Error "$($failed.Count) harness check(s) failed."
    exit 1
}

Write-Output "Zappa harness suite '$Suite' passed."
