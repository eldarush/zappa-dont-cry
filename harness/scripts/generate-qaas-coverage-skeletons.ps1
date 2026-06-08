param(
    [string]$CoverageFile = "D:\QaaS\_tmp\zappa-dont-cry\coverage\qaas-docs-coverage.json",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\docs-coverage",
    [int]$Limit = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CoverageFile)) {
    throw "Coverage file not found: $CoverageFile"
}

[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
$coverage = Get-Content -LiteralPath $CoverageFile -Raw | ConvertFrom-Json -AsHashtable
$records = @($coverage["records"])
if ($Limit -gt 0) {
    $records = @($records | Select-Object -First $Limit)
}

function New-SafeName {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "unnamed"
    }

    $safe = ($Value -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    if ($safe.Length -gt 96) {
        return $safe.Substring(0, 96).Trim('-')
    }

    return $safe
}

function New-CSharpIdentifier {
    param([string]$Value)

    $safe = (New-SafeName $Value) -replace '[^A-Za-z0-9_]', '_'
    if ($safe -notmatch '^[A-Za-z_]') {
        $safe = "C_$safe"
    }

    return $safe
}

function ConvertTo-YamlSingleQuoted {
    param([string]$Value)

    $escaped = $Value -replace "'", "''"
    return "'$escaped'"
}

function Get-RecordValue {
    param(
        [object]$Record,
        [string]$Name
    )

    if ($Record -is [System.Collections.IDictionary]) {
        return $Record[$Name]
    }

    return $Record.$Name
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

function New-DocsCoverageIntentQuestions {
    param(
        [string]$FullPath,
        [string]$Family,
        [string[]]$ArtifactTypes
    )

    $artifactTypeText = if ($ArtifactTypes.Count -gt 0) { $ArtifactTypes -join ", " } else { "documentation" }
    return @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "This docs-coverage skeleton proves only that a public QaaS documentation capability was inventoried for $Family; target component behavior remains blocked." -AnswerSource "public_docs" -RiskIfWrong "A weak model could treat documentation coverage as an executable test for an unspecified component." -HowToOverride "Provide the concrete component behavior and public runtime contract to test." -PublicEvidence @($FullPath))
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "Potential artifact boundary is $artifactTypeText, but no runtime boundary is selected until a repository or component contract is provided." -AnswerSource "blocked" -RiskIfWrong "Generated YAML or C# could target the wrong QaaS surface." -HowToOverride "Select Runner, Mocker, hook host, or configuration-as-code and provide matching public contracts." -PublicEvidence @($FullPath))
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "The public docs evidence is $FullPath." -AnswerSource "public_docs" -RiskIfWrong "The skeleton may cite the wrong QaaS capability or unsupported fields." -HowToOverride "Point to the exact public docs or schema path that should control artifact generation." -PublicEvidence @($FullPath))
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Inputs, expected outputs, and side effects are blocked because the docs page is not a component contract." -AnswerSource "blocked" -RiskIfWrong "Assertions may be guessed or too shallow." -HowToOverride "Provide public input, expected-output, and side-effect contracts." -PublicEvidence @($FullPath))
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative and cleanup cases are required but blocked until component behavior, dependencies, and observability contracts are known." -AnswerSource "blocked" -RiskIfWrong "The generated plan may miss failure behavior or cleanup semantics." -HowToOverride "List required negative, outage, retry, cleanup, and observability cases with public evidence." -PublicEvidence @($FullPath))
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Dependency requirements are unknown and blocked because the docs page does not define the target system dependencies." -AnswerSource "blocked" -RiskIfWrong "Mocker stubs or probes could simulate the wrong dependency." -HowToOverride "Provide public dependency protocols, endpoints, ports, credentials policy, readiness, and cleanup contracts." -PublicEvidence @($FullPath))
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Only structural validation can run now; template, build, live QaaS execution, and weak-model promotion remain deferred." -AnswerSource "assumption" -RiskIfWrong "A blocked skeleton might be promoted without executable evidence." -HowToOverride "Provide contracts and successful template/build/live/airgapped evidence for promotion." -PublicEvidence @($FullPath))
    )
}

function New-ArtifactCase {
    param(
        [string]$CaseId,
        [string]$Scenario,
        [string]$ArtifactType,
        [string]$EvidencePath,
        [string[]]$Setup,
        [string[]]$Action,
        [string[]]$Assertions,
        [string[]]$Cleanup,
        [string]$BlockedReason,
        [string[]]$ArtifactPaths
    )

    return [ordered]@{
        case_id = $CaseId
        scenario = $Scenario
        artifact_type = $ArtifactType
        public_evidence = @($EvidencePath)
        setup = @($Setup)
        action = @($Action)
        assertions = @($Assertions)
        cleanup = @($Cleanup)
        blocked_reason = $BlockedReason
        artifact_paths = @($ArtifactPaths)
    }
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
    param([object]$Record)

    $fullPath = Get-RecordValue -Record $Record -Name "full_path"
    $coverageId = Get-RecordValue -Record $Record -Name "coverage_id"
    $relativePath = Get-RecordValue -Record $Record -Name "relative_path"
    $fullPathYaml = ConvertTo-YamlSingleQuoted $fullPath
    $coverageIdYaml = ConvertTo-YamlSingleQuoted $coverageId
    $relativePathYaml = ConvertTo-YamlSingleQuoted $relativePath

    return @"
# Docs-only QaaS Runner skeleton.
# Status: blocked_until_contract_review
# Evidence: $fullPath
# This is not executable until target sessions, data sources, and dependency gates are filled from public contracts.

Links: []

Storages: []

DataSources: []

Sessions: []

Assertions:
  - Assertion: __DOCUMENTED_ASSERTION_OR_CUSTOM__
    AssertionConfiguration:
      EvidencePath: $fullPathYaml
      CoverageId: $coverageIdYaml

MetaData:
  CoverageId: $coverageIdYaml
  SourceDocument: $relativePathYaml
  BlockedReason: "Repository or component contract review required before executable YAML can be correct."
"@
}

function New-MockerYaml {
    param([object]$Record)

    $fullPath = Get-RecordValue -Record $Record -Name "full_path"
    $coverageId = Get-RecordValue -Record $Record -Name "coverage_id"
    $relativePath = Get-RecordValue -Record $Record -Name "relative_path"
    $coverageIdYaml = ConvertTo-YamlSingleQuoted $coverageId
    $relativePathYaml = ConvertTo-YamlSingleQuoted $relativePath

    return @"
# Docs-only QaaS Mocker skeleton.
# Status: blocked_until_contract_review
# Evidence: $fullPath
# This is not executable until public dependency contracts define stubs, ports, processors, and responses.
# BlockedReason: Dependency contract review required before executable Mocker YAML can be correct.

Stubs: []
"@
}

function New-CSharpSkeleton {
    param([object]$Record)

    $fullPath = Get-RecordValue -Record $Record -Name "full_path"
    $coverageId = Get-RecordValue -Record $Record -Name "coverage_id"
    $safeCoverage = New-CSharpIdentifier $coverageId

    return @"
// Docs-only QaaS configuration-as-code skeleton.
// Status: blocked_until_contract_review
// Evidence: $fullPath
// Fill from public QaaS docs plus repository-visible contracts only.

namespace ZappaDontCry.Generated.$safeCoverage;

public static class QaaSConfigSkeleton
{
    public const string CoverageId = "$coverageId";
    public const string SourceDocument = @"$fullPath";
    public const string BlockedReason = "Repository or component contract review required before executable C# configuration can be correct.";
}
"@
}

$manifestRecords = New-Object System.Collections.Generic.List[object]

foreach ($record in $records) {
    $coverageId = Get-RecordValue -Record $record -Name "coverage_id"
    $family = Get-RecordValue -Record $record -Name "family"
    $fullPath = Get-RecordValue -Record $record -Name "full_path"
    $artifactTypes = @(Get-RecordValue -Record $record -Name "artifact_types")
    $safeName = New-SafeName $coverageId
    $caseDir = Join-Path $OutDir $safeName
    [System.IO.Directory]::CreateDirectory($caseDir) | Out-Null

    $artifactPaths = New-Object System.Collections.Generic.List[string]
    $runnerYamlPath = $null
    $mockerYamlPath = $null
    $codePath = $null

    if ($artifactTypes -contains "runner-yaml") {
        $path = Join-Path $caseDir "test.qaas.yaml"
        New-RunnerYaml -Record $record | Set-Content -LiteralPath $path -Encoding UTF8
        $runnerYamlPath = $path
        $artifactPaths.Add($path)
    }

    if ($artifactTypes -contains "mocker-yaml") {
        $path = Join-Path $caseDir "mocker.qaas.yaml"
        New-MockerYaml -Record $record | Set-Content -LiteralPath $path -Encoding UTF8
        $mockerYamlPath = $path
        $artifactPaths.Add($path)
    }

    if ($artifactTypes -contains "runner-code" -or
        $artifactTypes -contains "mocker-code" -or
        $artifactTypes -contains "config-as-code" -or
        $artifactTypes -contains "hook") {
        $path = Join-Path $caseDir "QaaSConfigSkeleton.cs"
        New-CSharpSkeleton -Record $record | Set-Content -LiteralPath $path -Encoding UTF8
        $codePath = $path
        $artifactPaths.Add($path)
    }

    $manifestPath = Join-Path $caseDir "qaas-artifact-manifest.json"
    $artifactPaths.Add($manifestPath)
    $artifactArray = $artifactPaths.ToArray()

    $cases = New-Object System.Collections.Generic.List[object]
    $cases.Add((New-ArtifactCase `
        -CaseId "docs-coverage-contract-review" `
        -Scenario "Review the public QaaS documentation page and decide whether executable Runner, Mocker, hook, or configuration artifacts can be authored." `
        -ArtifactType "documentation" `
        -EvidencePath $fullPath `
        -Setup @("Review public QaaS docs/schema evidence.") `
        -Action @("Classify required repository/component contracts and QaaS artifact types.") `
        -Assertions @("Generated executable artifacts remain blocked until component contracts provide sessions, inputs, assertions, dependencies, and cleanup.") `
        -Cleanup @("No external resources are created by docs-only review.") `
        -BlockedReason "Generated from docs coverage only; executable behavior requires component or repository contract review." `
        -ArtifactPaths @($manifestPath)))

    foreach ($artifactType in $artifactTypes) {
        switch ($artifactType) {
            "runner-yaml" {
                $cases.Add((New-ArtifactCase `
                    -CaseId "runner-yaml-contract-placeholder" `
                    -Scenario "Blocked Runner YAML skeleton for a documented QaaS capability." `
                    -ArtifactType "runner-yaml" `
                    -EvidencePath $fullPath `
                    -Setup @("Map the documented QaaS capability to required Runner sessions, inputs, and data sources.") `
                    -Action @("Replace Runner placeholders only after public component contracts provide executable behavior.") `
                    -Assertions @("Runner YAML stays blocked until sessions and assertions are filled from public contracts.") `
                    -Cleanup @("Cleanup cannot be authored until the target component contract defines side effects.") `
                    -BlockedReason "Missing component or repository contract for executable Runner sessions and assertions." `
                    -ArtifactPaths @($runnerYamlPath)))
            }
            "mocker-yaml" {
                $cases.Add((New-ArtifactCase `
                    -CaseId "mocker-yaml-contract-placeholder" `
                    -Scenario "Blocked Mocker YAML skeleton for documented dependency simulation." `
                    -ArtifactType "mocker-yaml" `
                    -EvidencePath $fullPath `
                    -Setup @("Map documented Mocker concepts to dependency ports, stubs, processors, and responses.") `
                    -Action @("Replace Mocker placeholders only after public dependency contracts are available.") `
                    -Assertions @("Mocker YAML stays blocked until public dependency contracts define stubs and processors.") `
                    -Cleanup @("No stub cleanup can be made executable without dependency lifecycle evidence.") `
                    -BlockedReason "Missing public dependency contract for executable Mocker stubs and processors." `
                    -ArtifactPaths @($mockerYamlPath)))
            }
            "runner-code" {
                $cases.Add((New-ArtifactCase `
                    -CaseId "runner-code-contract-placeholder" `
                    -Scenario "Blocked Runner configuration-as-code skeleton for documented behavior." `
                    -ArtifactType "runner-code" `
                    -EvidencePath $fullPath `
                    -Setup @("Identify the Runner configuration behavior that cannot be expressed safely as YAML yet.") `
                    -Action @("Keep C# configuration syntax-only until public contracts prove concrete values and lifecycle.") `
                    -Assertions @("Runner code skeleton compiles only as syntax evidence and is not executable QaaS behavior.") `
                    -Cleanup @("No runtime cleanup is claimed by syntax-only C# skeletons.") `
                    -BlockedReason "Missing executable Runner configuration contract." `
                    -ArtifactPaths @($codePath)))
            }
            "mocker-code" {
                $cases.Add((New-ArtifactCase `
                    -CaseId "mocker-code-contract-placeholder" `
                    -Scenario "Blocked Mocker configuration-as-code skeleton for documented dependency behavior." `
                    -ArtifactType "mocker-code" `
                    -EvidencePath $fullPath `
                    -Setup @("Identify dependency simulation behavior that requires code rather than YAML.") `
                    -Action @("Keep C# Mocker code syntax-only until public dependency contracts prove processors and responses.") `
                    -Assertions @("Mocker code skeleton compiles only as syntax evidence and is not executable dependency simulation.") `
                    -Cleanup @("No runtime cleanup is claimed by syntax-only C# skeletons.") `
                    -BlockedReason "Missing executable Mocker configuration contract." `
                    -ArtifactPaths @($codePath)))
            }
            "config-as-code" {
                $cases.Add((New-ArtifactCase `
                    -CaseId "config-as-code-contract-placeholder" `
                    -Scenario "Blocked C# configuration-as-code skeleton for documented QaaS configuration." `
                    -ArtifactType "config-as-code" `
                    -EvidencePath $fullPath `
                    -Setup @("Identify documented QaaS configuration fields and required public runtime values.") `
                    -Action @("Keep configuration code syntax-only until runtime values and validation commands are public.") `
                    -Assertions @("Configuration code skeleton is not promoted without template, build, and live validation evidence.") `
                    -Cleanup @("No runtime cleanup is claimed by syntax-only C# skeletons.") `
                    -BlockedReason "Missing runtime configuration contract and validation evidence." `
                    -ArtifactPaths @($codePath)))
            }
            "hook" {
                $cases.Add((New-ArtifactCase `
                    -CaseId "hook-contract-placeholder" `
                    -Scenario "Blocked custom hook skeleton for documented QaaS extension behavior." `
                    -ArtifactType "hook" `
                    -EvidencePath $fullPath `
                    -Setup @("Prove documented built-ins are insufficient before authoring a custom hook.") `
                    -Action @("Keep hook code syntax-only until hook discovery and execution contracts are public.") `
                    -Assertions @("Hook skeleton is not promoted without built-in rejection, build evidence, and live discovery evidence.") `
                    -Cleanup @("No hook runtime cleanup is claimed by syntax-only C# skeletons.") `
                    -BlockedReason "Missing public hook discovery and execution contract." `
                    -ArtifactPaths @($codePath)))
            }
            "dependency-gate" {
                $cases.Add((New-ArtifactCase `
                    -CaseId "dependency-gate-contract-placeholder" `
                    -Scenario "Blocked dependency gate record for a documented QaaS probe or dependency capability." `
                    -ArtifactType "dependency-gate" `
                    -EvidencePath $fullPath `
                    -Setup @("Identify public dependency readiness, credentials, ports, lifecycle, and cleanup contracts.") `
                    -Action @("Keep dependency gates blocked until public contracts define how readiness and cleanup are verified.") `
                    -Assertions @("Dependency gate remains blocked and cannot be used as live readiness evidence without public dependency contracts.") `
                    -Cleanup @("No dependency cleanup is claimed until lifecycle contracts are public.") `
                    -BlockedReason "Missing public dependency readiness and cleanup contract." `
                    -ArtifactPaths @($manifestPath)))
            }
        }
    }

    $manifest = [ordered]@{
        campaign_id = "qaas-docs-coverage"
        source_repository = "qaas-docs"
        coverage_id = $coverageId
        source_document = $fullPath
        family = $family
        artifact_types = $artifactTypes
        artifacts = $artifactArray
        artifact_count = $artifactArray.Count
        status = "blocked_until_contract_review"
        docs_evidence = @($fullPath)
        intent_questions = @(New-DocsCoverageIntentQuestions -FullPath $fullPath -Family $family -ArtifactTypes $artifactTypes)
        intent_assumptions = @(
            (New-IntentAssumption `
                -Assumption "User wants public-docs-only QaaS coverage skeletons." `
                -WhySafe "The campaign is generated from public documentation inventory and does not claim executable behavior." `
                -RiskIfWrong "The artifacts may cover documentation breadth rather than the user's intended component behavior." `
                -HowToOverride "Provide a concrete repository/component contract and requested behavior." `
                -PublicEvidence @($fullPath))
            (New-IntentAssumption `
                -Assumption "Generated artifacts must remain blocked until repository or component contracts provide executable behavior." `
                -WhySafe "Blocked promotion prevents weak models from treating placeholders as runnable QaaS tests." `
                -RiskIfWrong "Executable tests might be delayed when the user already has sufficient runtime contracts." `
                -HowToOverride "Attach public runtime/API contracts and ask for executable promotion." `
                -PublicEvidence @($fullPath))
            (New-IntentAssumption `
                -Assumption "No QaaS source code is available as evidence." `
                -WhySafe "The zappa workflow is required to operate from public QaaS docs/schema evidence only." `
                -RiskIfWrong "Source-only implementation details may be omitted from generated skeletons." `
                -HowToOverride "Explicitly provide source files or source excerpts as allowed evidence." `
                -PublicEvidence @($fullPath))
        )
        cases = $cases.ToArray()
        assertions = @(
            "No executable QaaS claim without component or repository contract evidence.",
            "Every generated artifact records blocked_until_contract_review."
        )
        source_only_blockers = @(
            (New-SourceOnlyBlocker `
                -BlockerId "component-contract-missing" `
                -BlockerType "repository_or_component_contract" `
                -Description "The public QaaS documentation page proves a QaaS capability exists, but it does not provide the target component sessions, inputs, expected outputs, dependency contracts, or cleanup semantics needed for an executable test." `
                -RequiredEvidence @("Repository or component runtime contract", "Concrete sessions/data sources/assertions", "Dependency readiness and cleanup contract") `
                -PublicEvidence @($fullPath) `
                -UnblockInstruction "Provide a public repository/component contract or explicitly allowed source evidence for the behavior under test.")
            (New-SourceOnlyBlocker `
                -BlockerId "qaas-source-not-available" `
                -BlockerType "source_boundary" `
                -Description "The zappa workflow is operating from public QaaS docs/schema evidence only and cannot use QaaS implementation source behavior as a contract." `
                -RequiredEvidence @("Public docs/schema path for each QaaS field or hook API", "Explicit user permission before source evidence is used") `
                -PublicEvidence @($fullPath) `
                -UnblockInstruction "Provide source files or source excerpts explicitly as allowed evidence, or add matching public documentation/schema evidence.")
        )
        dependency_gates = @(
            [ordered]@{
                gate_id = "component-contract"
                kind = "runtime"
                required = $true
                status = "blocked"
                evidence = @()
                check_command = $null
                blocked_reason = "Repository or component contract is required before executable QaaS sessions and assertions can be correct."
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
                blocked_reason = "Generated C# syntax compiles, but QaaS configuration build validation requires executable code."
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
                "Repository or component contract",
                "Public API, CLI, or runtime contract",
                "Public input and expected-output contract",
                "Public dependency/stub contract",
                "Cleanup contract",
                "Concrete QaaS sessions, data sources, assertions, and cleanup",
                "QaaS template validation result",
                "C# build result when code artifacts exist",
                "Live QaaS run/act/assert result when dependency gates are ready",
                "Airgapped weak-model validation transcript"
            )
        }
        cleanup = @()
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_coverage_record"
        }
        validation_sequence = @(
            "Review public QaaS docs/schema evidence",
            "Fill repository/component contract",
            "Run template/build checks",
            "Run live execution only after dependency gates are ready"
        )
        promotion_state = "blocked"
        blocked_reason = "Generated from docs coverage only; executable correctness requires repository or component contract review."
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $manifestRecords.Add([ordered]@{
        coverage_id = $coverageId
        source_repository = "qaas-docs"
        family = $family
        source_document = $fullPath
        directory = $caseDir
        artifact_count = $artifactPaths.Count
        status = "blocked_until_contract_review"
        promotion_state = "blocked"
    })
}

$index = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    coverage_file = $CoverageFile
    output_directory = $OutDir
    count = $manifestRecords.Count
    contract_policy = "docs-only skeletons; not executable until public contract review fills placeholders"
    records = $manifestRecords.ToArray()
}

$indexPath = Join-Path $OutDir "coverage-skeleton-index.json"
$index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $indexPath -Encoding UTF8
Write-Output "Wrote $($manifestRecords.Count) docs-coverage skeleton directories to $OutDir"
Write-Output "Index: $indexPath"
