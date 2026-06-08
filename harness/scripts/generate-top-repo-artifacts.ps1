param(
    [string]$ContractsDir = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\top-repos",
    [int]$Limit = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ContractsDir)) {
    throw "Contracts directory not found: $ContractsDir"
}

[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
$allowedRoot = [System.IO.Path]::GetFullPath("D:\QaaS\_tmp\zappa-dont-cry\generated-tests\top-repos")
if (-not $resolvedOutDir.Equals($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "This generator owns only the managed top-repos output directory: $allowedRoot"
}

Get-ChildItem -LiteralPath $resolvedOutDir -Force | Remove-Item -Recurse -Force

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

function New-CSharpIdentifier {
    param([string]$Value)

    $safe = (New-SafeName $Value) -replace '[^A-Za-z0-9_]', '_'
    if ($safe -notmatch '^[A-Za-z_]') {
        $safe = "R_$safe"
    }

    return $safe
}

function ConvertTo-YamlSingleQuoted {
    param([string]$Value)

    $escaped = $Value -replace "'", "''"
    return "'$escaped'"
}

function New-IntentAssumption {
    param(
        [string]$Assumption,
        [string]$WhySafe,
        [string]$RiskIfWrong,
        [string]$HowToOverride,
        [string[]]$PublicEvidence
    )

    return [ordered]@{
        assumption = $Assumption
        why_safe = $WhySafe
        risk_if_wrong = $RiskIfWrong
        how_to_override = $HowToOverride
        public_evidence = @($PublicEvidence)
    }
}

function New-IntentQuestion {
    param(
        [string]$QuestionId,
        [string]$Question,
        [string]$SelfAnswer,
        [string]$AnswerSource,
        [string]$RiskIfWrong,
        [string]$HowToOverride,
        [string[]]$PublicEvidence
    )

    return [ordered]@{
        question_id = $QuestionId
        question = $Question
        self_answer = $SelfAnswer
        answer_source = $AnswerSource
        risk_if_wrong = $RiskIfWrong
        how_to_override = $HowToOverride
        public_evidence = @($PublicEvidence)
    }
}

function New-TopRepoIntentQuestions {
    param([object]$Contract)

    $repository = [string]$Contract.repository
    $publicEvidence = @($Contract.public_evidence)
    return @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "For $repository, the current campaign proves only public contract discovery and blocked QaaS artifact planning; no executable repository behavior is selected." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model could claim tests exist for behavior that README/tree metadata does not specify." -HowToOverride "Provide the exact public API, CLI, service, or workflow behavior to test." -PublicEvidence $publicEvidence)
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "Runner, Mocker, and configuration-as-code skeletons are present, but the executable boundary for $repository is blocked until a public runtime or dependency contract is selected." -AnswerSource "blocked" -RiskIfWrong "Artifacts may target the wrong process, API, dependency, or hook host." -HowToOverride "Select the concrete Runner target, Mocker dependency, hook host, or configuration-as-code boundary with public evidence." -PublicEvidence $publicEvidence)
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "Evidence is limited to public QaaS docs plus repository README/tree snapshots for $repository." -AnswerSource "public_repo_contract" -RiskIfWrong "The manifest may cite unsupported QaaS fields or repository behavior." -HowToOverride "Attach exact QaaS docs/schema paths and repository-visible contract paths for the chosen behavior." -PublicEvidence $publicEvidence)
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Inputs, expected outputs, and side effects for $repository are blocked until public runtime contracts define them." -AnswerSource "blocked" -RiskIfWrong "Assertions could be guessed from popularity, language, or README wording." -HowToOverride "Provide public input/output examples, side effects, and success criteria." -PublicEvidence $publicEvidence)
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, outage, retry, cleanup, and observability cases are blocked until $repository exposes relevant behavior and dependency contracts." -AnswerSource "blocked" -RiskIfWrong "Failure handling and cleanup assertions may be incomplete or wrong." -HowToOverride "Provide public negative-case and cleanup contracts for the selected behavior." -PublicEvidence $publicEvidence)
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Dependency requirements for $repository are blocked until public docs identify protocols, endpoints, credentials, readiness, and cleanup." -AnswerSource "blocked" -RiskIfWrong "Mocker or probe artifacts could simulate the wrong dependency or miss required cleanup." -HowToOverride "Provide public dependency/stub contracts and readiness/cleanup semantics." -PublicEvidence $publicEvidence)
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Only structural artifact validation and C# syntax compilation can run now; QaaS template/build/live execution and live weak-model promotion are deferred." -AnswerSource "assumption" -RiskIfWrong "A weak model could promote blocked skeletons to executable tests." -HowToOverride "Provide successful QaaS template/build/live transcripts and live airgapped weak-model validation." -PublicEvidence $publicEvidence)
    )
}

function New-SourceOnlyBlocker {
    param(
        [string]$BlockerId,
        [string]$BlockerType,
        [string]$Description,
        [string[]]$RequiredEvidence,
        [string[]]$PublicEvidence,
        [string]$UnblockInstruction
    )

    return [ordered]@{
        blocker_id = $BlockerId
        blocker_type = $BlockerType
        description = $Description
        required_evidence = @($RequiredEvidence)
        public_evidence = @($PublicEvidence)
        unblock_instruction = $UnblockInstruction
    }
}

function New-RunnerYaml {
    param([object]$Contract)

    $repository = ConvertTo-YamlSingleQuoted ([string]$Contract.repository)
    $contractStrength = ConvertTo-YamlSingleQuoted ([string]$Contract.contract_strength)
    $evidence = @($Contract.public_evidence)
    $evidencePath = if ($evidence.Count -gt 0) { ConvertTo-YamlSingleQuoted ([string]$evidence[0]) } else { "''" }

    return @"
# Docs-only QaaS top-repository Runner skeleton.
# Status: blocked_until_repo_contract_review
# Repository: $($Contract.repository)
# This is not executable until public runtime/API contracts define sessions, inputs, assertions, and cleanup.

Links: []

Storages: []

DataSources: []

Sessions: []

Assertions:
  - Assertion: __DOCUMENTED_ASSERTION_OR_CUSTOM__
    AssertionConfiguration:
      Repository: $repository
      ContractStrength: $contractStrength
      EvidencePath: $evidencePath

MetaData:
  Repository: $repository
  ContractStrength: $contractStrength
  BlockedReason: "Public repository contracts are not sufficient yet for executable QaaS Runner YAML."
"@
}

function New-MockerYaml {
    param([object]$Contract)

    $repository = ConvertTo-YamlSingleQuoted ([string]$Contract.repository)
    $contractStrength = ConvertTo-YamlSingleQuoted ([string]$Contract.contract_strength)

    return @"
# Docs-only QaaS top-repository Mocker skeleton.
# Status: blocked_until_repo_contract_review
# Repository: $($Contract.repository)
# This is not executable until public dependency contracts define stubs, ports, processors, and responses.
# BlockedReason: Public dependency contracts are not sufficient yet for executable QaaS Mocker YAML.

Stubs: []
"@
}

function New-CSharpSkeleton {
    param([object]$Contract)

    $repoId = New-CSharpIdentifier ("R{0:D3}_{1}" -f [int]$Contract.rank, [string]$Contract.repository)
    $repoId = $repoId.Replace("__", "_")
    $repository = [string]$Contract.repository
    $contractStrength = [string]$Contract.contract_strength

    return @"
// Docs-only QaaS top-repository configuration-as-code skeleton.
// Status: blocked_until_repo_contract_review
// Repository: $repository
// Fill from public repository contracts plus QaaS docs only.

namespace ZappaDontCry.TopRepos.$repoId;

public static class QaaSTopRepoConfigSkeleton
{
    public const string Repository = "$repository";
    public const string ContractStrength = "$contractStrength";
    public const string BlockedReason = "Public repository contracts are not sufficient yet for executable QaaS configuration.";
}
"@
}

$contractFiles = @(Get-ChildItem -LiteralPath $ContractsDir -Recurse -File -Filter "repo-contract.json" | Sort-Object FullName)
if ($Limit -gt 0) {
    $contractFiles = @($contractFiles | Select-Object -First $Limit)
}

$records = New-Object System.Collections.Generic.List[object]

foreach ($contractFile in $contractFiles) {
    $contract = Get-Content -LiteralPath $contractFile.FullName -Raw | ConvertFrom-Json
    $safeRepo = "{0:D3}-{1}" -f [int]$contract.rank, (New-SafeName ([string]$contract.repository).Replace("/", "-"))
    $repoOutDir = Join-Path $OutDir $safeRepo
    [System.IO.Directory]::CreateDirectory($repoOutDir) | Out-Null

    $runnerPath = Join-Path $repoOutDir "test.qaas.yaml"
    $mockerPath = Join-Path $repoOutDir "mocker.qaas.yaml"
    $codePath = Join-Path $repoOutDir "QaaSTopRepoConfigSkeleton.cs"
    $manifestPath = Join-Path $repoOutDir "qaas-artifact-manifest.json"

    New-RunnerYaml -Contract $contract | Set-Content -LiteralPath $runnerPath -Encoding UTF8
    New-MockerYaml -Contract $contract | Set-Content -LiteralPath $mockerPath -Encoding UTF8
    New-CSharpSkeleton -Contract $contract | Set-Content -LiteralPath $codePath -Encoding UTF8

    $docsEvidence = @(
        "D:\QaaS\qaas-docs\docs"
        @($contract.public_evidence)
    )

    $cases = @(
        [ordered]@{
            case_id = "repo-contract-discovery"
            scenario = "Use public repository evidence to determine whether executable QaaS Runner and Mocker tests can be safely authored."
            artifact_type = "documentation"
            public_evidence = @($contract.public_evidence)
            setup = @("Review README/tree snapshots and QaaS docs.")
            action = @("Classify runtime/API/dependency contracts.")
            assertions = @("Generated executable artifacts remain blocked unless public contracts identify sessions, inputs, assertions, dependencies, and cleanup.")
            cleanup = @("No external resources are created by public contract discovery.")
            blocked_reason = "Repository contract review has not promoted this repo to executable QaaS tests."
            artifact_paths = @($manifestPath)
        },
        [ordered]@{
            case_id = "runner-yaml-skeleton"
            scenario = "Blocked Runner YAML placeholder for future public-contract-backed execution."
            artifact_type = "runner-yaml"
            public_evidence = @($contract.public_evidence)
            setup = @("Identify public runtime/API contracts for $($contract.repository).")
            action = @("Replace Runner YAML placeholders only after public sessions, inputs, assertions, and cleanup are known.")
            assertions = @("Runner YAML must not be treated as executable until placeholders are replaced from public contracts.")
            cleanup = @("No runtime cleanup is claimed until public side-effect contracts exist.")
            blocked_reason = "Missing concrete QaaS sessions/data/assertions for $($contract.repository)."
            artifact_paths = @($runnerPath)
        },
        [ordered]@{
            case_id = "mocker-yaml-skeleton"
            scenario = "Blocked Mocker YAML placeholder for future public dependency simulation."
            artifact_type = "mocker-yaml"
            public_evidence = @($contract.public_evidence)
            setup = @("Identify public dependency contracts, ports, protocols, processors, and response shapes for $($contract.repository).")
            action = @("Replace Mocker YAML placeholders only after public dependency contracts are known.")
            assertions = @("Mocker YAML must not be treated as executable until dependency contracts are public.")
            cleanup = @("No stub cleanup is claimed until dependency lifecycle contracts exist.")
            blocked_reason = "Missing public dependency contracts for $($contract.repository)."
            artifact_paths = @($mockerPath)
        },
        [ordered]@{
            case_id = "config-code-skeleton"
            scenario = "Blocked C# configuration-as-code placeholder for future QaaS configuration."
            artifact_type = "config-as-code"
            public_evidence = @($contract.public_evidence)
            setup = @("Identify public runtime configuration values and QaaS configuration docs for $($contract.repository).")
            action = @("Keep C# configuration syntax-only until public contracts prove executable values and lifecycle.")
            assertions = @("C# skeleton compiles as syntax-only evidence but has no executable QaaS behavior.")
            cleanup = @("No runtime cleanup is claimed by syntax-only C# skeletons.")
            blocked_reason = "Missing public runtime contract for executable C# QaaS configuration."
            artifact_paths = @($codePath)
        }
    )

    $artifacts = @($runnerPath, $mockerPath, $codePath, $manifestPath)
    $manifest = [ordered]@{
        campaign_id = "top-github-repos"
        source_repository = $contract.repository
        repository_rank = [int]$contract.rank
        docs_evidence = $docsEvidence
        repo_contract = $contractFile.FullName
        contract_strength = $contract.contract_strength
        intent_questions = @(New-TopRepoIntentQuestions -Contract $contract)
        intent_assumptions = @(
            (New-IntentAssumption `
                -Assumption "User wants public-docs-only QaaS tests." `
                -WhySafe "The top-repo campaign is required to use repository-visible evidence and public QaaS docs only." `
                -RiskIfWrong "The generated plans may omit behavior the user expected from private or local source execution." `
                -HowToOverride "Provide an explicit repository checkout, component contract, or allowed source evidence." `
                -PublicEvidence @($contract.public_evidence))
            (New-IntentAssumption `
                -Assumption "Source execution and cloning are not allowed during contract harvesting." `
                -WhySafe "Avoids executing arbitrary top repositories while still harvesting README/tree metadata." `
                -RiskIfWrong "Some executable contracts may remain undiscovered and artifacts stay blocked." `
                -HowToOverride "Provide a safety plan and explicitly allow cloning or execution for selected repositories." `
                -PublicEvidence @($contract.public_evidence))
            (New-IntentAssumption `
                -Assumption "Generated artifacts must remain blocked unless public contracts prove exact runtime behavior." `
                -WhySafe "Fail-closed promotion prevents weak models from treating placeholders as correct tests." `
                -RiskIfWrong "Executable promotion may be conservative for repositories with sufficient public contracts." `
                -HowToOverride "Attach public runtime/API/dependency contracts and request promotion for selected repositories." `
                -PublicEvidence @($contract.public_evidence))
        )
        artifacts = $artifacts
        artifact_count = $artifacts.Count
        cases = $cases
        assertions = @(
            "No executable QaaS claim without public repository contract evidence.",
            "Every generated artifact records blocked_until_repo_contract_review."
        )
        dependency_gates = @(
            [ordered]@{
                gate_id = "public-runtime-contract"
                kind = "runtime"
                required = $true
                status = "blocked"
                evidence = @($contract.public_evidence)
                check_command = $null
                blocked_reason = "A concrete public API, CLI, or runtime contract must be selected before executable QaaS sessions can be correct."
            },
            [ordered]@{
                gate_id = "public-input-output-contract"
                kind = "runtime"
                required = $true
                status = "blocked"
                evidence = @($contract.public_evidence)
                check_command = $null
                blocked_reason = "Executable assertions require public input and expected-output contracts."
            },
            [ordered]@{
                gate_id = "public-dependency-or-stub-contract"
                kind = "dependency"
                required = $true
                status = "blocked"
                evidence = @($contract.public_evidence)
                check_command = $null
                blocked_reason = "Mocker stubs require public dependency contracts."
            },
            [ordered]@{
                gate_id = "cleanup-contract"
                kind = "cleanup"
                required = $true
                status = "blocked"
                evidence = @($contract.public_evidence)
                check_command = $null
                blocked_reason = "Live execution requires a public cleanup contract."
            },
            [ordered]@{
                gate_id = "qaas-template"
                kind = "qaas-template"
                required = $true
                status = "blocked"
                evidence = @()
                check_command = $null
                blocked_reason = "Template validation can run only after placeholders are replaced from public contracts."
            },
            [ordered]@{
                gate_id = "qaas-build"
                kind = "qaas-build"
                required = $true
                status = "blocked"
                evidence = @()
                check_command = $null
                blocked_reason = "Generated C# syntax compiles, but executable QaaS configuration build validation requires real configuration."
            },
            [ordered]@{
                gate_id = "airgapped-validation"
                kind = "airgapped"
                required = $true
                status = "blocked"
                evidence = @()
                check_command = "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none"
                blocked_reason = "Live weak-model validation is required before promotion."
            }
        )
        promotion_requirements = [ordered]@{
            current_state = "blocked"
            target_state = "executable_ready"
            required_evidence = @(
                "Public API, CLI, or runtime contract",
                "Public input and expected-output contract",
                "Public dependency/stub contract",
                "Cleanup contract",
                "QaaS template validation result",
                "C# build result when code artifacts exist",
                "Live QaaS run/act/assert result when dependency gates are ready",
                "Airgapped weak-model validation transcript"
            )
        }
        cleanup = @()
        validation_sequence = @(
            "Review public QaaS docs/schema evidence",
            "Review repository README/tree contract snapshots",
            "Run generated artifact structural validator",
            "Promote to executable only after QaaS template/build/live validation is available"
        )
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_repository"
        }
        source_only_blockers = @(
            (New-SourceOnlyBlocker `
                -BlockerId "private-source-behavior-not-assumed" `
                -BlockerType "source_boundary" `
                -Description "No private source-code behavior may be assumed from repository popularity, primary language, or README/tree metadata." `
                -RequiredEvidence @("Public runtime/API/CLI contract", "Public input and expected-output contract", "Public dependency/stub contract", "Public cleanup contract") `
                -PublicEvidence @($contract.public_evidence) `
                -UnblockInstruction "Provide an explicit repository checkout/source excerpt as allowed evidence, or point to public runtime and dependency contracts for selected behavior.")
            (New-SourceOnlyBlocker `
                -BlockerId "executable-contract-missing" `
                -BlockerType "repository_contract" `
                -Description "The harvested repository evidence is insufficient to produce exact executable QaaS sessions, assertions, stubs, and cleanup." `
                -RequiredEvidence @("Concrete QaaS session boundary", "Inputs and expected outputs", "Dependency readiness/stub behavior", "Cleanup and side-effect contract") `
                -PublicEvidence @($contract.public_evidence) `
                -UnblockInstruction "Promote only after adding repository-visible contracts that satisfy the dependency gates.")
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Generated from public repository evidence and QaaS docs only; exact executable QaaS behavior requires repository/component contract review."
    }

    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $records.Add([ordered]@{
        rank = [int]$contract.rank
        repository = $contract.repository
        contract_strength = $contract.contract_strength
        directory = $repoOutDir
        artifact_count = $artifacts.Count
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
    })
}

$index = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    source_contracts_directory = $ContractsDir
    output_directory = $OutDir
    count = $records.Count
    contract_policy = "top-repo artifacts are docs-only skeletons until public repository contracts promote them"
    records = $records.ToArray()
}

$indexPath = Join-Path $OutDir "top-repo-artifact-index.json"
$index | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $indexPath -Encoding UTF8
Write-Output "Generated top-repo QaaS artifact skeletons for $($records.Count) repositories."
Write-Output "Index: $indexPath"
