param(
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-regression"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\WeakEvidence.Policy.psm1") -Force
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$failures = New-Object System.Collections.Generic.List[string]
$passed = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Add-Pass {
    param([string]$Message)
    $passed.Add($Message)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 16), $script:Utf8NoBom)
}

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Value
    )

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Value, $script:Utf8NoBom)
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Set-JsonProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    } else {
        $property.Value = $Value
    }
}

function Move-HttpStatusDocsBlockerToAdvisory {
    param(
        [object]$Manifest,
        [string]$SummaryPath
    )

    $validationAdvisories = @()
    if ($Manifest.PSObject.Properties.Name -contains "validation_advisories") {
        $validationAdvisories = @($Manifest.validation_advisories)
    }
    $hasHttpStatusAdvisory = (@($validationAdvisories | Where-Object { $_.advisory_id -eq "httpstatus-docs-inconsistency-recorded" }).Count -ne 0)
    $remainingBlockers = @()
    foreach ($blocker in @($Manifest.source_only_blockers)) {
        if ($blocker.blocker_id -eq "httpstatus-docs-inconsistency-recorded") {
            if (-not $hasHttpStatusAdvisory) {
                $validationAdvisories += [ordered]@{
                    advisory_id = "httpstatus-docs-inconsistency-recorded"
                    advisory_type = "qaas_docs_contract"
                    description = [string]$blocker.description
                    public_evidence = @($blocker.public_evidence)
                    resolved_by = "schema-derived StatusCode/OutputNames template and live validation"
                    validation_summary = $SummaryPath
                    blocking = $false
                }
                $hasHttpStatusAdvisory = $true
            }
        } else {
            $remainingBlockers += $blocker
        }
    }
    $Manifest.source_only_blockers = @($remainingBlockers)
    Set-JsonProperty -Object $Manifest -Name "validation_advisories" -Value @($validationAdvisories)
}

function Invoke-CapturedCommand {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments
    )

    $logPath = Join-Path $OutDir "$Name.log"
    $global:LASTEXITCODE = 0
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    } catch {
        $output = @($_.Exception.ToString())
        $exitCode = 1
    }

    $output | Set-Content -LiteralPath $logPath -Encoding UTF8
    [pscustomobject]@{
        Name = $Name
        ExitCode = $exitCode
        LogPath = $logPath
        Text = ($output | Out-String)
    }
}

function Assert-ExitCode {
    param(
        [string]$Name,
        [object]$Result,
        [int]$ExpectedExitCode,
        [string]$ExpectedText = ""
    )

    if ([int]$Result.ExitCode -ne $ExpectedExitCode) {
        Add-Failure "$Name expected exit $ExpectedExitCode, got $($Result.ExitCode). Log: $($Result.LogPath)"
        return
    }

    if ($ExpectedText -and $Result.Text -notmatch [regex]::Escape($ExpectedText)) {
        Add-Failure "$Name did not include expected text '$ExpectedText'. Log: $($Result.LogPath)"
        return
    }

    Add-Pass $Name
}

function New-SeedFixture {
    param([string]$SeedRoot)

    $runnerDir = Join-Path $SeedRoot "runner\ZappaPromotionSeed.Runner"
    $mockerDir = Join-Path $SeedRoot "mocker\ZappaPromotionSeed.Mocker"
    $evidenceDir = Join-Path $SeedRoot "evidence"
    $airgappedDir = Join-Path $SeedRoot "airgapped"
    foreach ($dir in @($runnerDir, $mockerDir, $evidenceDir, $airgappedDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $runnerYaml = Join-Path $runnerDir "test.qaas.yaml"
    @"
MetaData:
  Name: Zappa Harness Regression Runner
Storages:
  - JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data
DataSources:
  - Name: HelloInputs
    FromFileSystem:
      Path: ./TestData/input.json
Sessions:
  - Name: HelloSession
    Transactions:
      - Name: CallHello
        DataSourceNames: [HelloInputs]
        HttpRequest:
          Method: Get
          Route: hello
Assertions:
  - Assertion: HttpStatus
    StatusCode: 200
    OutputNames: [CallHello]
"@ | Set-Content -LiteralPath $runnerYaml -Encoding UTF8

    $mockerYaml = Join-Path $mockerDir "mocker.qaas.yaml"
    @"
Stubs:
  - Name: HelloStub
    Endpoint:
      Path: /hello
      Method: Get
    Processor: StaticResponseProcessor
    Response:
      StatusCode: 200
      ContentType: text/plain; charset=utf-8
      Body: hello
"@ | Set-Content -LiteralPath $mockerYaml -Encoding UTF8

    $templateTranscript = Join-Path $evidenceDir "template-validation.transcript.txt"
    $buildTranscript = Join-Path $evidenceDir "build-validation.transcript.txt"
    $liveTranscript = Join-Path $evidenceDir "live-validation.transcript.txt"
    $airgappedTranscript = Join-Path $evidenceDir "airgapped-validation.transcript.txt"
    foreach ($path in @($templateTranscript, $buildTranscript, $liveTranscript)) {
        "ExitCode: 0`nPASS" | Set-Content -LiteralPath $path -Encoding UTF8
    }
    "DryRun: True`ndry_run_prompt_assembly" | Set-Content -LiteralPath $airgappedTranscript -Encoding UTF8

    $airgappedSummary = Join-Path $airgappedDir "summary.md"
    "DryRun: True`nAirgapped: True`n- PASS exit 0: dry-run prompt assembly only" | Set-Content -LiteralPath $airgappedSummary -Encoding UTF8
    $airgappedIndex = Join-Path $airgappedDir "promotion-seed-airgapped-index.json"
    Write-JsonFile -Path $airgappedIndex -Value ([ordered]@{
        schema_version = 1
        index_status = "dry_run_assembly"
        records = @()
    })

    $docsRoot = "D:\QaaS\qaas-docs\docs"
    $manifest = [ordered]@{
        schema_version = 1
        campaign_id = "promotion-seed-qaas-docs-hello-world-http"
        source_repository = "qaas-docs"
        docs_evidence = @(
            [ordered]@{ path = (Join-Path $docsRoot "qaas\quickStart\helloWorldHttp.md"); claim = "Documents HTTP seed."; supports = @("runner") },
            [ordered]@{ path = (Join-Path $docsRoot "processors\availableProcessors\StaticResponseProcessor\overview.md"); claim = "Documents static response."; supports = @("mocker") },
            [ordered]@{ path = (Join-Path $docsRoot "assertions\availableAssertions\HttpStatus\overview.md"); claim = "Documents HTTP status."; supports = @("assertion") },
            [ordered]@{ path = (Join-Path $docsRoot "assets\schemas\runner-family-schema.json"); claim = "Runner schema."; supports = @("runner-schema") },
            [ordered]@{ path = (Join-Path $docsRoot "assets\schemas\mocker-family-schema.json"); claim = "Mocker schema."; supports = @("mocker-schema") }
        )
        artifacts = @($runnerYaml, $mockerYaml)
        status = "blocked_until_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Template/build/local live validation is recorded, but live airgapped weak-model validation has not passed."
        template_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "template"; transcript = $templateTranscript }
        build_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "build"; transcript = $buildTranscript }
        live_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "live"; transcript = $liveTranscript }
        airgapped_validation = [ordered]@{
            required = $true
            status = "dry_run_prompt_assembly"
            dry_run = $true
            exit_code = 0
            command = "run-airgapped-validation.ps1"
            transcript = $airgappedTranscript
            summary = $airgappedSummary
            index = $airgappedIndex
            expected_patterns = @(
                "intent_assumptions",
                "docs_evidence",
                "artifact_plan",
                "validation_sequence",
                "airgapped_result",
                "strong_review",
                "next_blocker",
                "weak_validation_passed:\s*true",
                "dry_run:\s*false"
            )
        }
        source_only_blockers = @(
            [ordered]@{
                blocker_id = "promotion-seed-live-airgapped-not-passed"
                blocker_type = "qaas_docs_contract"
                description = "Live weak-model validation has not passed."
                required_evidence = @("Live weak-model transcript with dry_run false.")
                public_evidence = @((Join-Path $HarnessRoot "references\airgapped-validation.md"))
                unblock_instruction = "Rerun live airgapped validation."
            }
        )
        validation_evidence = [ordered]@{}
    }

    Write-JsonFile -Path (Join-Path $SeedRoot "qaas-artifact-manifest.json") -Value $manifest
}

function Copy-Directory {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Invoke-SeedLifecycle {
    param(
        [string]$Name,
        [string]$SeedRoot
    )

    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-PromotionSeedLifecycle.ps1"),
        "-SeedRoot",
        $SeedRoot,
        "-ExpectedSeedRoot",
        $SeedRoot
    )
}

function New-PromotionWeakEvidenceFixture {
    param(
        [string]$Root,
        [ValidateSet("valid", "partial-preferred", "dry-run", "codex-route", "missing-marker", "outside-transcript")]
        [string]$CaseName = "valid"
    )

    $caseRoot = Join-Path $Root "promotion-weak-evidence"
    $evidenceDir = Join-Path $caseRoot "evidence"
    $airgappedDir = Join-Path $caseRoot "airgapped"
    $outsideDir = Join-Path $Root "outside"
    foreach ($dir in @($caseRoot, $evidenceDir, $airgappedDir, $outsideDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $artifactPath = Join-Path $caseRoot "artifact.txt"
    Write-TextFile -Path $artifactPath -Value "executable artifact"

    $templateTranscript = Join-Path $evidenceDir "template-validation.transcript.txt"
    $buildTranscript = Join-Path $evidenceDir "build-validation.transcript.txt"
    $liveTranscript = Join-Path $evidenceDir "live-validation.transcript.txt"
    foreach ($path in @($templateTranscript, $buildTranscript, $liveTranscript)) {
        Write-TextFile -Path $path -Value "ExitCode: 0`nPASS"
    }

    $preferredModels = @("id:gpt-3.5-turbo", "id:gpt-3.5-turbo-0613", "gpt-4o-mini", "gpt-4o-mini-2024-07-18")
    $summaryPath = Join-Path $airgappedDir "20260608-weak-summary.md"
    $indexPath = Join-Path $airgappedDir "promotion-weak-index.json"
    $wrapperTranscript = Join-Path $evidenceDir "airgapped-validation.transcript.txt"

    $model = "id:gpt-3.5-turbo"
    $harness = "claude-copilot"
    $profile = "airgapped"
    $commandTemplate = "C:\Users\eldar\copilot-claude\claude.cmd {0} -p prompt"
    $dryRunHeader = "False"
    $manifestDryRun = $false
    $stdout = "weak_validation_passed: true`ndry_run: false"
    $weakValidationPassed = $CaseName -in @("valid", "partial-preferred")

    if ($CaseName -eq "dry-run") {
        $commandTemplate = "DRY_RUN claude-copilot {0}"
        $dryRunHeader = "True"
        $manifestDryRun = $true
        $weakValidationPassed = $false
    } elseif ($CaseName -eq "codex-route") {
        $commandTemplate = "C:\Users\eldar\AppData\Roaming\npm\codex.cmd exec --model {0}"
        $harness = "codex"
        $model = "gpt-5.4-mini"
        $weakValidationPassed = $false
    } elseif ($CaseName -eq "missing-marker") {
        $stdout = "airgapped_result: pass"
        $weakValidationPassed = $false
    } elseif ($CaseName -eq "outside-transcript") {
        $weakValidationPassed = $false
    }

    $modelsToWrite = if ($CaseName -eq "valid") { @($preferredModels) } else { @($model) }
    $actualTranscripts = @()
    $indexRecords = @()
    foreach ($currentModel in $modelsToWrite) {
        $safeModel = $currentModel.Replace(":", "_")
        $actualTranscript = Join-Path $airgappedDir "20260608-weak-claude-copilot-$safeModel.md"
        if ($CaseName -eq "outside-transcript") {
            $actualTranscript = Join-Path $outsideDir "outside-claude-copilot-$safeModel.md"
        }
        $command = $commandTemplate -f $currentModel

        Write-TextFile -Path $actualTranscript -Value @"
# weak-model-session transcript

Command: $command
ExitCode: 0
ScenarioId: promotion-weak-fixture
ScenarioKind: scenario
PromptHashSha256: 0000
Harness: $harness
Profile: $profile
Model: $currentModel
DryRun: $dryRunHeader

## stdout
$stdout

## stderr
"@

        $actualTranscripts += $actualTranscript
        $indexRecords += [ordered]@{
            scenario_id = "promotion-weak-fixture"
            scenario_kind = "scenario"
            harness = $harness
            profile = $profile
            model = $currentModel
            weak_validation_eligible = $CaseName -ne "codex-route"
            dry_run = $manifestDryRun
            classification = if ($manifestDryRun) { "dry_run_assembly" } else { "live_transcript_ready" }
            weak_validation_passed = $weakValidationPassed
            transcript_exit_code = 0
            summary = $summaryPath
            transcript = $actualTranscript
        }
    }

    $summaryDryRun = if ($manifestDryRun) { "True" } else { "False" }
    $summaryModels = $modelsToWrite -join ", "
    $summaryResults = ($actualTranscripts | ForEach-Object { "- PASS exit 0: $_" }) -join "`n"
    Write-TextFile -Path $summaryPath -Value @"
# Weak Model Validation Summary

Workspace: D:\QaaS
Harness: claude-copilot
Profile: airgapped
ReasoningEffort: none
Models: $summaryModels
DryRun: $summaryDryRun
Airgapped: True
PolicyPath: D:\QaaS\_tools\weak-model-policy.json

## Results
$summaryResults
"@

    $wrapperTranscriptLines = @("Weak model validation complete.", "Summary: $summaryPath")
    foreach ($actualTranscript in $actualTranscripts) {
        $wrapperTranscriptLines += "Transcript: $actualTranscript"
    }
    Write-TextFile -Path $wrapperTranscript -Value @"
$($wrapperTranscriptLines -join "`n")
"@

    Write-JsonFile -Path $indexPath -Value ([ordered]@{
        schema_version = 1
        validation_kind = "live_scenario_model_execution"
        records = @($indexRecords)
    })

    $manifestPath = Join-Path $caseRoot "qaas-artifact-manifest.json"
    $manifest = [ordered]@{
        schema_version = 1
        campaign_id = "promotion-weak-fixture"
        source_repository = "qaas-docs"
        status = "executable"
        promotion_state = "executable"
        docs_evidence = @(
            [ordered]@{ path = "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md"; claim = "docs"; supports = @("runner") }
        )
        intent_questions = @(
            [ordered]@{ question = "Use public docs only?"; answer = "yes" }
        )
        artifacts = @($artifactPath)
        dependency_gates = @(
            [ordered]@{ gate_id = "public-contract"; required = $true; status = "passed"; evidence = @("public"); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-template"; required = $true; status = "passed"; evidence = @($templateTranscript); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-build"; required = $true; status = "passed"; evidence = @($buildTranscript); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-live"; required = $true; status = "passed"; evidence = @($liveTranscript); blocked_reason = "" },
            [ordered]@{ gate_id = "airgapped-validation"; required = $true; status = "passed"; evidence = @($wrapperTranscript); blocked_reason = "" }
        )
        source_only_blockers = @()
        promotion_requirements = [ordered]@{
            current_state = "executable"
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
        template_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "template"; transcript = $templateTranscript }
        build_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "build"; transcript = $buildTranscript }
        live_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "live"; transcript = $liveTranscript }
        airgapped_validation = [ordered]@{
            required = $true
            status = "passed"
            dry_run = $manifestDryRun
            weak_validation_passed = $weakValidationPassed
            exit_code = 0
            command = "run-airgapped-validation.ps1"
            transcript = $wrapperTranscript
            summary = $summaryPath
            index = $indexPath
        }
        validation_evidence = [ordered]@{
            template = $templateTranscript
            build = $buildTranscript
            live = $liveTranscript
            airgapped = $wrapperTranscript
        }
    }

    Write-JsonFile -Path $manifestPath -Value $manifest

    [pscustomobject]@{
        Root = $caseRoot
        Coverage = (Join-Path $Root "coverage")
        PacketDir = (Join-Path $Root "packets")
        Manifest = $manifestPath
    }
}

function Invoke-PromotionCandidateIndexCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "python" -Arguments @(
        (Join-Path $HarnessRoot "checks\Check-PromotionCandidateIndex.py"),
        $Fixture.Root,
        $Fixture.Coverage
    )
}

function Invoke-PromotionReadinessCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "python" -Arguments @(
        (Join-Path $HarnessRoot "checks\Check-PromotionReadiness.py"),
        $Fixture.Root
    )
}

function Invoke-PromotionPacketCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "python" -Arguments @(
        (Join-Path $HarnessRoot "checks\Check-PromotionPacket.py"),
        $Fixture.Root,
        $Fixture.Coverage,
        $Fixture.PacketDir
    )
}

function New-WeakOutputForgeryFixture {
    param(
        [string]$Root,
        [switch]$Adversarial,
        [switch]$DryRunHeaderSpoof
    )

    $evidenceRoot = Join-Path $Root "evidence"
    $blockersDir = Join-Path $Root "blockers"
    [System.IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($blockersDir) | Out-Null

    $scenarioId = if ($Adversarial) { "forged-adversarial-eligibility" } else { "forged-scenario-eligibility" }
    if ($DryRunHeaderSpoof) {
        $scenarioId = if ($Adversarial) { "dry-run-adversarial-header-spoof" } else { "dry-run-scenario-header-spoof" }
    }
    $validationKind = if ($Adversarial) { "live_adversarial_model_execution" } else { "live_scenario_model_execution" }
    $transcriptPath = Join-Path $evidenceRoot "$scenarioId-claude-copilot-id_gpt-3.5-turbo.md"
    $summaryPath = Join-Path $evidenceRoot "$scenarioId-summary.md"
    $transcriptCommand = "C:\Users\eldar\AppData\Roaming\npm\codex.cmd exec --model gpt-5.4-mini"
    $transcriptHarness = "codex"
    $transcriptModel = "gpt-5.4-mini"
    $transcriptDryRun = "False"
    if ($DryRunHeaderSpoof) {
        $transcriptCommand = "C:\Users\eldar\copilot-claude\claude.cmd id:gpt-3.5-turbo -p prompt"
        $transcriptHarness = "claude-copilot"
        $transcriptModel = "id:gpt-3.5-turbo"
        $transcriptDryRun = "True"
    }
    Write-TextFile -Path $transcriptPath -Value @"
# weak-model-session transcript

Command: $transcriptCommand
ExitCode: 0
ScenarioId: $scenarioId
ScenarioKind: scenario
PromptHashSha256: 0000
Harness: $transcriptHarness
Profile: airgapped
Model: $transcriptModel
DryRun: $transcriptDryRun

## stdout
intent_assumptions
docs_evidence
artifact_plan
validation_sequence
airgapped_result
strong_review
next_blocker

## stderr
"@
    Write-TextFile -Path $summaryPath -Value @"
Harness: claude-copilot
Profile: airgapped
Models: $transcriptModel
DryRun: False
Airgapped: True
- PASS exit 0: $transcriptPath
"@

    $fixturePath = Join-Path $Root "weak-output-fixture.json"
    $prompt = "Return a QaaS weak output contract."
    $scenarioRecord = [ordered]@{
        scenario_id = $scenarioId
        skill = "zappa-qaas-test-author"
        prompt = $prompt
        expected_terms = @("intent_assumptions", "docs_evidence", "artifact_plan", "validation_sequence", "airgapped_result", "strong_review", "next_blocker")
    }
    if ($Adversarial) {
        $scenarioRecord.risk_category = "forged_weak_evidence"
    }
    Write-JsonFile -Path $fixturePath -Value ([ordered]@{
        live_validation_kind = $validationKind
        scenarios = @($scenarioRecord)
    })

    $contractsPath = Join-Path $Root "skill-output-contracts.json"
    Write-JsonFile -Path $contractsPath -Value ([ordered]@{
        contracts = @(
            [ordered]@{
                skill = "zappa-qaas-test-author"
                required_output_terms = @()
                required_any_output_term_groups = @()
            }
        )
    })

    $indexPath = Join-Path $Root "weak-output-index.json"
    $promptHash = Get-Sha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($prompt))
    $runnerIndexPath = Join-Path $Root "weak-output-runner-index.json"
    Write-JsonFile -Path $runnerIndexPath -Value ([ordered]@{
        schema_version = 1
        records = @(
            [ordered]@{
                scenario_id = $scenarioId
                skill = "zappa-qaas-test-author"
                prompt_hash_sha256 = $promptHash
                match_status = "runner_recorded"
                harness = "claude-copilot"
                profile = "airgapped"
                model = "id:gpt-3.5-turbo"
                dry_run = $false
                classification = "live_transcript_ready"
                weak_validation_eligible = $true
                weak_validation_passed = $false
                transcript_exit_code = 0
                summary = $summaryPath
                transcript = $transcriptPath
            }
        )
    })
    Write-JsonFile -Path $indexPath -Value ([ordered]@{
        schema_version = 1
        validation_kind = $validationKind
        required_scenario_count = 1
        records = @(
            [ordered]@{
                scenario_id = $scenarioId
                skill = "zappa-qaas-test-author"
                classification = "live_transcript_ready"
                dry_run = $false
                weak_validation_eligible = $true
                weak_validation_passed = $false
                transcript_exit_code = 0
                transcript = $transcriptPath
            }
        )
    })

    [pscustomobject]@{
        EvidenceRoot = $evidenceRoot
        FixturePath = $fixturePath
        ContractsPath = $contractsPath
        BlockersDir = $blockersDir
        IndexPath = $indexPath
        RunnerIndexPath = $runnerIndexPath
    }
}

function Invoke-WeakScenarioOutputCheck {
    param(
        [string]$Name,
        [object]$Fixture,
        [switch]$Adversarial
    )

    $scriptName = if ($Adversarial) { "Check-WeakModelAdversarialOutputs.ps1" } else { "Check-WeakModelScenarioOutputs.ps1" }
    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\$scriptName"),
        "-EvidenceRoot",
        $Fixture.EvidenceRoot,
        "-FixturePath",
        $Fixture.FixturePath,
        "-SkillContractsPath",
        $Fixture.ContractsPath,
        "-BlockersDir",
        $Fixture.BlockersDir,
        "-IndexPath",
        $Fixture.IndexPath
    )
}

function Invoke-WeakScenarioLiveIndexCheck {
    param(
        [string]$Name,
        [object]$Fixture,
        [switch]$Adversarial
    )

    $indexFileName = if ($Adversarial) { "weak-adversarial-live-index-latest.json" } else { "weak-scenario-live-index-latest.json" }
    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-WeakModelLiveScenarioIndex.ps1"),
        "-EvidenceRoot",
        $Fixture.EvidenceRoot,
        "-FixturePath",
        $Fixture.FixturePath,
        "-BlockersDir",
        $Fixture.BlockersDir,
        "-IndexFileName",
        $indexFileName,
        "-RunnerIndexPath",
        $Fixture.RunnerIndexPath
    )
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($Bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha256.Dispose()
    }
}

function Get-GitBlobSha {
    param([byte[]]$Bytes)

    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
    $payload = New-Object byte[] ($header.Length + $Bytes.Length)
    [System.Buffer]::BlockCopy($header, 0, $payload, 0, $header.Length)
    [System.Buffer]::BlockCopy($Bytes, 0, $payload, $header.Length, $Bytes.Length)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash($payload)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha1.Dispose()
    }
}

function Get-FileSha256Hex {
    param([string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha.Dispose()
    }
}

function New-SelectedContractFixture {
    param(
        [string]$Root,
        [string]$PromotionState = "blocked",
        [switch]$BadLocalContent,
        [switch]$LocalPathInGeneratedRoot
    )

    $contractsRoot = Join-Path $Root "contracts"
    $selectedRoot = Join-Path $Root "selected-contracts"
    $generatedRoot = Join-Path $Root "generated-tests\top-repos"
    $contractDir = Join-Path $contractsRoot "001-example-repo"
    $selectedDir = Join-Path $selectedRoot "001-example-repo"
    $selectedFilesDir = Join-Path $selectedDir "files"
    $generatedRepoDir = Join-Path $generatedRoot "001-example-repo"
    foreach ($dir in @($contractDir, $selectedFilesDir, $generatedRepoDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes("selected contract evidence`n")
    $sha = Get-GitBlobSha -Bytes $bytes
    $sha256 = Get-Sha256Hex -Bytes $bytes
    $readmePath = Join-Path $contractDir "README.snapshot.md"
    [System.IO.File]::WriteAllBytes($readmePath, $bytes)

    $treePath = Join-Path $contractDir "tree.snapshot.json"
    Write-JsonFile -Path $treePath -Value ([ordered]@{
        sha = "tree-sha"
        tree = @(
            [ordered]@{
                path = "README.md"
                mode = "100644"
                type = "blob"
                sha = $sha
                size = $bytes.Length
                url = "https://api.github.com/repos/example/repo/git/blobs/$sha"
            }
        )
        truncated = $false
    })

    $contractPath = Join-Path $contractDir "repo-contract.json"
    Write-JsonFile -Path $contractPath -Value ([ordered]@{
        rank = 1
        repository = "example/repo"
        readme_snapshot = $readmePath
        tree_snapshot = $treePath
        public_evidence = @($readmePath, $treePath)
        status = "contract_harvested"
    })

    $localPath = Join-Path $selectedFilesDir "README.md"
    if ($LocalPathInGeneratedRoot) {
        $localPath = Join-Path $generatedRepoDir "README.md"
    }
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $localPath)) | Out-Null
    $localBytes = if ($BadLocalContent) { [System.Text.Encoding]::UTF8.GetBytes("selected contract evidencf`n") } else { $bytes }
    [System.IO.File]::WriteAllBytes($localPath, $localBytes)

    $selectedRecordPath = Join-Path $selectedDir "selected-contract.json"
    $selectedFileRecord = [ordered]@{
        source_path = "README.md"
        local_path = $localPath
        sha = $sha
        git_blob_sha_verified = $true
        content_sha256 = $sha256
        size = $bytes.Length
        fetched_size = $bytes.Length
        reason = "fixture"
        github_blob_url = "https://api.github.com/repos/example/repo/git/blobs/$sha"
    }
    Write-JsonFile -Path $selectedRecordPath -Value ([ordered]@{
        schema_version = 1
        repository = "example/repo"
        rank = 1
        source_contract = $contractPath
        readme_snapshot = $readmePath
        tree_snapshot = $treePath
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        readiness_state = "selected_public_contract_content_harvested"
        fetched_files = @($selectedFileRecord)
        selected_public_contracts = @($selectedFileRecord)
        candidate_promotion_contracts = @(
            [ordered]@{
                supports = "runtime-contract"
                status = "candidate_evidence_harvested"
                evidence_markers = @("fixture-marker")
            }
        )
        remaining_blockers = @(
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation"
        )
    })

    Write-JsonFile -Path (Join-Path $selectedRoot "selected-contract-index.json") -Value ([ordered]@{
        schema_version = 1
        selected_repository_count = 1
        records = @(
            [ordered]@{
                repository = "example/repo"
                rank = 1
                record_path = $selectedRecordPath
                fetched_file_count = 1
                status = "contract_content_harvested_not_executable"
                promotion_state = "blocked"
            }
        )
    })

    Write-JsonFile -Path (Join-Path $generatedRepoDir "qaas-artifact-manifest.json") -Value ([ordered]@{
        source_repository = "example/repo"
        status = if ($PromotionState -eq "executable") { "executable" } else { "blocked_until_repo_contract_review" }
        promotion_state = $PromotionState
    })

    [pscustomobject]@{
        ContractsRoot = $contractsRoot
        SelectedRoot = $selectedRoot
        GeneratedRoot = $generatedRoot
    }
}

function Invoke-SelectedContractCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "python" -Arguments @(
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoContracts.py"),
        $Fixture.SelectedRoot,
        $Fixture.ContractsRoot,
        $Fixture.GeneratedRoot,
        (Join-Path $OutDir "$Name-coverage")
    )
}

function New-SelectedCandidateFixture {
    param(
        [string]$Root,
        [string]$PromotionState = "blocked",
        [switch]$CandidateRootUnderPromotionPackets,
        [switch]$RawGitHubUrl,
        [switch]$UnsafeSourcePath,
        [switch]$PublicEvidenceInGeneratedRoot,
        [switch]$InventedYamlKey
    )

    $selectedRoot = Join-Path $Root "selected-contracts"
    $candidateRoot = if ($CandidateRootUnderPromotionPackets) {
        Join-Path $Root "promotion-packets\selected-top-repo-candidates"
    } else {
        Join-Path $Root "generated-tests\selected-top-repo-candidates"
    }
    $selectedDir = Join-Path $selectedRoot "200-typicode-json-server"
    $selectedFilesDir = Join-Path $selectedDir "files"
    $candidateDir = Join-Path $candidateRoot "200-typicode-json-server"
    $fixtureDir = Join-Path $candidateDir "fixtures"
    $expectationsDir = Join-Path $candidateDir "expectations"
    $requestPayloadsDir = Join-Path $candidateDir "request-payloads"
    foreach ($dir in @($selectedFilesDir, $fixtureDir, $expectationsDir, $requestPayloadsDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $readmePath = Join-Path $selectedFilesDir "README.md"
    Write-TextFile -Path $readmePath -Value @"
npx json-server db.json
http://localhost:3000
curl http://localhost:3000/posts/1
"id": "1"
"title": "a title"
"views": 100
"@

    $sha = "2fc9ded8eb5e5afd6c8ba6368eba08f6f4105b0d"
    $blobUrl = if ($RawGitHubUrl) {
        "https://raw.githubusercontent.com/typicode/json-server/main/README.md"
    } else {
        "https://api.github.com/repos/typicode/json-server/git/blobs/$sha"
    }
    $sourcePath = if ($UnsafeSourcePath) { "..\README.md" } else { "README.md" }
    $selectedFileRecord = [ordered]@{
        source_path = $sourcePath
        local_path = $readmePath
        sha = $sha
        git_blob_sha_verified = $true
        content_sha256 = "fixture-sha256"
        size = 128
        fetched_size = 128
        reason = "fixture"
        github_blob_url = $blobUrl
    }

    $selectedRecordPath = Join-Path $selectedDir "selected-contract.json"
    Write-JsonFile -Path $selectedRecordPath -Value ([ordered]@{
        schema_version = 1
        repository = "typicode/json-server"
        rank = 200
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        selected_public_contracts = @($selectedFileRecord)
        candidate_promotion_contracts = @(
            [ordered]@{ supports = "runtime-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("runtime-url-localhost-3000") },
            [ordered]@{ supports = "http-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("http-route-posts-one") },
            [ordered]@{ supports = "candidate-executable-command"; status = "candidate_evidence_harvested"; evidence_markers = @("json-server-command") },
            [ordered]@{ supports = "input-output-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("expected-json-id-one") }
        )
    })

    $runnerPath = Join-Path $candidateDir "test.qaas.yaml"
    $yamlPrefix = if ($InventedYamlKey) { "CandidateContracts: []`n" } else { "" }
    Write-TextFile -Path $runnerPath -Value @"
$yamlPrefix# Status: blocked_until_template_live_airgapped_validation
MetaData:
  Team: ZappaDontCry
  System: typicode-json-server

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetPostOnePayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-post-one.bin'
      StorageMetaData: ItemName

  - Name: ExpectedPostOneCsv
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './expectations'
        SearchPattern: 'posts-1.csv'
      StorageMetaData: ItemName

Sessions:
  - Name: JsonServerReadPost
    Transactions:
      - Name: GetPostOne
        TimeoutMs: 5000
        DataSourceNames:
          - GetPostOnePayload
        DataSourcePatterns:
          - GetPostOnePayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 3000
          Route: /posts/1
          Method: Get
        OutputDeserialize:
          Deserializer: Json

Assertions:
  - Name: GetPostOneReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - JsonServerReadPost
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetPostOne
  - Name: GetPostOneBodyMatchesReadme
    Assertion: OutputContentByExpectedCsvResults
    SessionNames:
      - JsonServerReadPost
    DataSourceNames:
      - ExpectedPostOneCsv
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetPostOne
      DataSourceName: ExpectedPostOneCsv
      JsonConverterType: Json
      CompareRowsNotInOrder: false
      ColumnNameToFieldPathMap:
        id:
          Path: $.id
        title:
          Path: $.title
        views:
          Path: $.views
"@

    $dbPath = Join-Path $fixtureDir "db.json"
    Write-TextFile -Path $dbPath -Value @"
{
  "posts": [
    { "id": "1", "title": "a title", "views": 100 }
  ]
}
"@

    $expectationPath = Join-Path $expectationsDir "posts-1.csv"
    [System.IO.File]::WriteAllText($expectationPath, "id,title,views`n1,a title,100`n1,a title,100", $script:Utf8NoBom)
    $requestPayloadPath = Join-Path $requestPayloadsDir "get-post-one.bin"
    [System.IO.File]::WriteAllBytes($requestPayloadPath, [byte[]]::new(0))

    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "typicode/json-server"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        command = "npx json-server db.json"
        cleanup = [ordered]@{ required = $true; status = "not_validated" }
        blockers = @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation", "run_live_airgapped_weak_model_validation")
    })

    $generatedEvidence = Join-Path $candidateDir "generated-evidence.txt"
    Write-TextFile -Path $generatedEvidence -Value "not-public-evidence"
    $docsEvidence = @(
        "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md",
        "D:\QaaS\qaas-docs\docs\generators\availableGenerators\FromFileSystem\overview.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $publicEvidence = if ($PublicEvidenceInGeneratedRoot) { @($generatedEvidence) } else { @($selectedRecordPath, $readmePath) }

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $artifacts = @($runnerPath, $dbPath, $expectationPath, $requestPayloadPath, $runtimePlanPath, $manifestPath)
    Write-JsonFile -Path $manifestPath -Value ([ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-json-server-candidate"
        source_repository = "typicode/json-server"
        repository_rank = 200
        selected_contract = $selectedRecordPath
        docs_evidence = $docsEvidence
        public_evidence = @($publicEvidence)
        artifacts = $artifacts
        artifact_count = $artifacts.Count
        source_only_blockers = @(
            [ordered]@{ blocker_id = "json-server-process-lifecycle-not-proven"; blocker_type = "repository_contract"; description = "blocked"; required_evidence = @("lifecycle"); public_evidence = @($publicEvidence); unblock_instruction = "validate lifecycle" },
            [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = $docsEvidence; unblock_instruction = "run qaas" },
            [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("airgapped"); public_evidence = @($readmePath); unblock_instruction = "run weak model" },
            [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = $docsEvidence; unblock_instruction = "use schema" }
        )
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($publicEvidence); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($publicEvidence); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; kind = "runtime"; required = $true; status = "ready"; evidence = $docsEvidence; check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "node-json-server-process-lifecycle"; kind = "dependency"; required = $true; status = "blocked"; evidence = @($publicEvidence); check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "cleanup-contract"; kind = "cleanup"; required = $true; status = "blocked"; evidence = @($publicEvidence); check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-template"; kind = "qaas-template"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; kind = "qaas-build"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; kind = "airgapped"; required = $true; status = "blocked"; evidence = @(); check_command = ""; blocked_reason = "blocked" }
        )
        airgapped_validation = [ordered]@{ required = $true; status = "not_run_for_this_candidate" }
        status = "blocked_until_repo_contract_review"
        promotion_state = $PromotionState
        blocked_reason = "blocked"
    })

    Write-JsonFile -Path (Join-Path $candidateRoot "selected-candidate-index.json") -Value ([ordered]@{
        schema_version = 1
        selected_candidate_count = 1
        output_directory = $candidateRoot
        records = @(
            [ordered]@{
                rank = 200
                repository = "typicode/json-server"
                directory = $candidateDir
                manifest = $manifestPath
                selected_contract = $selectedRecordPath
                status = "candidate_packet_blocked_until_template_live_airgapped_validation"
                promotion_state = "blocked"
                artifact_count = $artifacts.Count
            }
        )
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        SelectedRoot = $selectedRoot
    }
}

function New-Crawl4AiDeferredCandidateFixture {
    param(
        [string]$Root,
        [switch]$MissingInputOutputBlocker
    )

    $fixture = New-SelectedCandidateFixture -Root $Root
    $selectedRoot = $fixture.SelectedRoot
    $candidateRoot = $fixture.CandidateRoot
    $crawlSelectedDir = Join-Path $selectedRoot "250-unclecode-crawl4ai"
    $crawlFilesDir = Join-Path $crawlSelectedDir "files"
    $deployDockerDir = Join-Path $crawlFilesDir "deploy\docker"
    foreach ($dir in @($crawlFilesDir, $deployDockerDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $readmePath = Join-Path $crawlFilesDir "README.md"
    Write-TextFile -Path $readmePath -Value @'
docker pull unclecode/crawl4ai:latest
docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest
http://localhost:11235/dashboard
http://localhost:11235/playground
response = requests.post(
    "http://localhost:11235/crawl",
    json={"urls": ["https://example.com"], "priority": 10}
)
if response.status_code == 200:
    print("Crawl job submitted successfully.")

if "results" in response.json():
    results = response.json()["results"]
else:
    task_id = response.json()["task_id"]
    result = requests.get(f"http://localhost:11235/task/{task_id}")
'@

    $dockerfilePath = Join-Path $crawlFilesDir "Dockerfile"
    Write-TextFile -Path $dockerfilePath -Value @'
ENV REDIS_PORT=6379
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD bash -c 'MEM=$(free -m | awk "/^Mem:/{print $2}"); if [ $MEM -lt 2048 ]; then exit 1; fi && redis-cli ping > /dev/null && curl -f http://localhost:11235/health || exit 1'
'@

    $composePath = Join-Path $crawlFilesDir "docker-compose.yml"
    Write-TextFile -Path $composePath -Value @'
services:
  crawl4ai:
    ports:
      - "11235:11235"
    volumes:
      - /dev/shm:/dev/shm
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11235/health"]
'@

    $schemasPath = Join-Path $deployDockerDir "schemas.py"
    Write-TextFile -Path $schemasPath -Value @'
from typing import List, Optional, Dict
from pydantic import BaseModel, Field

class CrawlRequest(BaseModel):
    urls: List[str] = Field(min_length=1, max_length=100)
    browser_config: Optional[Dict] = Field(default_factory=dict)
    crawler_config: Optional[Dict] = Field(default_factory=dict)
'@

    $records = @(
        [ordered]@{ source_path = "README.md"; local_path = $readmePath; sha = "1ab6fd26e9eb8d7125272597df6ac324c3155b6d"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 512; fetched_size = 512; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/1ab6fd26e9eb8d7125272597df6ac324c3155b6d" },
        [ordered]@{ source_path = "Dockerfile"; local_path = $dockerfilePath; sha = "8d7e06f75de4f33b2a8adc25527b5d416567c4df"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 128; fetched_size = 128; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/8d7e06f75de4f33b2a8adc25527b5d416567c4df" },
        [ordered]@{ source_path = "docker-compose.yml"; local_path = $composePath; sha = "cb99c18fee106890ecd3db61c12acfe0402d0fc3"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 128; fetched_size = 128; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/cb99c18fee106890ecd3db61c12acfe0402d0fc3" },
        [ordered]@{ source_path = "deploy/docker/schemas.py"; local_path = $schemasPath; sha = "dd561bb214f82b332e4d42ef8a9c1a840bf7c5e1"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 128; fetched_size = 128; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/dd561bb214f82b332e4d42ef8a9c1a840bf7c5e1" }
    )
    $crawlSelectedPath = Join-Path $crawlSelectedDir "selected-contract.json"
    Write-JsonFile -Path $crawlSelectedPath -Value ([ordered]@{
        schema_version = 1
        repository = "unclecode/crawl4ai"
        rank = 250
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        selected_public_contracts = $records
        candidate_promotion_contracts = @(
            [ordered]@{ supports = "candidate-executable-command"; status = "candidate_evidence_harvested"; evidence_markers = @("docker-run-command") }
        )
    })

    $jsonServerSelectedPath = Join-Path $selectedRoot "200-typicode-json-server\selected-contract.json"
    Write-JsonFile -Path (Join-Path $selectedRoot "selected-contract-index.json") -Value ([ordered]@{
        schema_version = 1
        selected_repository_count = 2
        records = @(
            [ordered]@{ repository = "typicode/json-server"; rank = 200; record_path = $jsonServerSelectedPath; status = "contract_content_harvested_not_executable"; promotion_state = "blocked" },
            [ordered]@{ repository = "unclecode/crawl4ai"; rank = 250; record_path = $crawlSelectedPath; status = "contract_content_harvested_not_executable"; promotion_state = "blocked" }
        )
    })

    $deferredBlockers = @(
        "selected_input_output_contract_missing",
        "selected_crawl_response_is_branching_async_or_results_contract",
        "selected_healthcheck_status_is_not_exact_http_contract",
        "selected_healthcheck_body_contract_missing",
        "docker_runtime_requires_live_container_safety_plan",
        "candidate_generation_not_implemented",
        "live_harness_not_available",
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence"
    )
    if ($MissingInputOutputBlocker) {
        $deferredBlockers = @($deferredBlockers | Where-Object { $_ -ne "selected_input_output_contract_missing" })
    }

    $indexPath = Join-Path $candidateRoot "selected-candidate-index.json"
    $index = Read-JsonFile -Path $indexPath
    $recordsForIndex = @($index.records)
    Write-JsonFile -Path $indexPath -Value ([ordered]@{
        schema_version = 1
        output_directory = $candidateRoot
        selected_candidate_count = $recordsForIndex.Count
        selected_contract_count = 2
        deferred_candidate_count = 1
        records = $recordsForIndex
        deferred_records = @(
        [ordered]@{
            rank = 250
            repository = "unclecode/crawl4ai"
            selected_contract = $crawlSelectedPath
            status = "deferred_candidate_packet_blocked"
            promotion_state = "blocked"
            blockers = $deferredBlockers
            deferred_reason = "selected_public_contract_lacks_exact_input_output_contract"
            unsafe_promotion_risks = @(
                "README /crawl example accepts HTTP 200 and branches between synchronous results and task_id polling.",
                "Docker healthchecks use curl -f /health and prove liveness only, not an exact QaaS-assertable response body.",
                "Container runtime depends on browser shared memory, Redis, memory limits, and cleanup that are not live-validated."
            )
            required_before_generation = @(
                "Exact public request payload, response status, and response body contract.",
                "Container lifecycle plan with readiness, isolation, resource limits, and cleanup evidence.",
                "Live airgapped weak-model validation transcript."
            )
        }
        )
    })

    $fixture
}

function New-Crawl4AiHealthCandidateFixture {
    param(
        [string]$Root,
        [switch]$UseHttpStatus200,
        [switch]$UseCrawlRoute,
        [switch]$AddBodyAssertion,
        [switch]$MissingCleanupOwnership,
        [switch]$AssertionReadsBody
    )

    $fixture = New-SelectedCandidateFixture -Root $Root
    $selectedRoot = $fixture.SelectedRoot
    $candidateRoot = $fixture.CandidateRoot
    $crawlSelectedDir = Join-Path $selectedRoot "250-unclecode-crawl4ai"
    $crawlFilesDir = Join-Path $crawlSelectedDir "files"
    $deployDockerDir = Join-Path $crawlFilesDir "deploy\docker"
    $candidateDir = Join-Path $candidateRoot "250-unclecode-crawl4ai"
    $requestPayloadsDir = Join-Path $candidateDir "request-payloads"
    $hookDir = Join-Path $candidateDir "assertion-packets\HttpStatusBelow400"
    foreach ($dir in @($crawlFilesDir, $deployDockerDir, $candidateDir, $requestPayloadsDir, $hookDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $readmePath = Join-Path $crawlFilesDir "README.md"
    Write-TextFile -Path $readmePath -Value @'
docker pull unclecode/crawl4ai:latest
docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest
http://localhost:11235/dashboard
response = requests.post(
    "http://localhost:11235/crawl",
    json={"urls": ["https://example.com"], "priority": 10}
)
if response.status_code == 200:
    print("Crawl job submitted successfully.")
if "results" in response.json():
    results = response.json()["results"]
else:
    task_id = response.json()["task_id"]
    result = requests.get(f"http://localhost:11235/task/{task_id}")
'@

    $dockerfilePath = Join-Path $crawlFilesDir "Dockerfile"
    Write-TextFile -Path $dockerfilePath -Value @'
ENV REDIS_PORT=6379
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD bash -c 'MEM=$(free -m | awk "/^Mem:/{print $2}"); if [ $MEM -lt 2048 ]; then exit 1; fi && redis-cli ping > /dev/null && curl -f http://localhost:11235/health || exit 1'
'@

    $composePath = Join-Path $crawlFilesDir "docker-compose.yml"
    Write-TextFile -Path $composePath -Value @'
services:
  crawl4ai:
    ports:
      - "11235:11235"
    volumes:
      - /dev/shm:/dev/shm
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11235/health"]
'@

    $schemasPath = Join-Path $deployDockerDir "schemas.py"
    Write-TextFile -Path $schemasPath -Value @'
from typing import List, Optional, Dict
from pydantic import BaseModel, Field

class CrawlRequest(BaseModel):
    urls: List[str] = Field(min_length=1, max_length=100)
    browser_config: Optional[Dict] = Field(default_factory=dict)
'@

    $selectedRecords = @(
        [ordered]@{ source_path = "README.md"; local_path = $readmePath; sha = "1ab6fd26e9eb8d7125272597df6ac324c3155b6d"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 512; fetched_size = 512; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/1ab6fd26e9eb8d7125272597df6ac324c3155b6d" },
        [ordered]@{ source_path = "Dockerfile"; local_path = $dockerfilePath; sha = "8d7e06f75de4f33b2a8adc25527b5d416567c4df"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 128; fetched_size = 128; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/8d7e06f75de4f33b2a8adc25527b5d416567c4df" },
        [ordered]@{ source_path = "docker-compose.yml"; local_path = $composePath; sha = "cb99c18fee106890ecd3db61c12acfe0402d0fc3"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 128; fetched_size = 128; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/cb99c18fee106890ecd3db61c12acfe0402d0fc3" },
        [ordered]@{ source_path = "deploy/docker/schemas.py"; local_path = $schemasPath; sha = "dd561bb214f82b332e4d42ef8a9c1a840bf7c5e1"; git_blob_sha_verified = $true; content_sha256 = "fixture"; size = 128; fetched_size = 128; reason = "fixture"; github_blob_url = "https://api.github.com/repos/unclecode/crawl4ai/git/blobs/dd561bb214f82b332e4d42ef8a9c1a840bf7c5e1" }
    )
    $crawlSelectedPath = Join-Path $crawlSelectedDir "selected-contract.json"
    Write-JsonFile -Path $crawlSelectedPath -Value ([ordered]@{
        schema_version = 1
        repository = "unclecode/crawl4ai"
        rank = 250
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        selected_public_contracts = $selectedRecords
        public_evidence = @($readmePath, $dockerfilePath, $composePath, $schemasPath)
        candidate_promotion_contracts = @(
            [ordered]@{ supports = "candidate-executable-command"; status = "candidate_evidence_harvested"; evidence_markers = @("docker-run-command") }
        )
    })

    $route = if ($UseCrawlRoute) { "/crawl" } else { "health" }
    $assertionBlock = if ($UseHttpStatus200) {
@'
  - Name: GetHealthReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - Crawl4AiHealth
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetHealth
'@
    } else {
@'
  - Name: GetHealthMatchesDockerCurlF
    Assertion: HttpStatusBelow400
    SessionNames:
      - Crawl4AiHealth
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      MaximumExclusiveStatusCode: 400
      OutputNames:
        - GetHealth
'@
    }
    if ($AddBodyAssertion) {
        $assertionBlock += @'

  - Name: InventedHealthBody
    Assertion: ObjectOutputJsonSchema
    SessionNames:
      - Crawl4AiHealth
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetHealth
'@
    }

    $runnerPath = Join-Path $candidateDir "test.qaas.yaml"
    Write-TextFile -Path $runnerPath -Value @"
# Status: blocked_until_template_live_airgapped_validation
MetaData:
  Team: ZappaDontCry
  System: unclecode-crawl4ai

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetHealthPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-health.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: Crawl4AiHealth
    Transactions:
      - Name: GetHealth
        TimeoutMs: 5000
        DataSourceNames:
          - GetHealthPayload
        DataSourcePatterns:
          - GetHealthPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 11235
          Route: $route
          Method: Get

Assertions:
$assertionBlock
"@

    $requestPayloadPath = Join-Path $requestPayloadsDir "get-health.bin"
    [System.IO.File]::WriteAllBytes($requestPayloadPath, [byte[]]::new(0))

    $assertionBodyLine = if ($AssertionReadsBody) { "        var illegalBodyRead = observed[0].Body;" } else { "" }
    $assertionSourcePath = Join-Path $hookDir "HttpStatusBelow400.cs"
    Write-TextFile -Path $assertionSourcePath -Value @"
using System;
using System.Collections.Immutable;
using System.Linq;
using QaaS.Framework.SDK.DataSourceObjects;
using QaaS.Framework.SDK.Hooks.Assertion;
using QaaS.Framework.SDK.Session.SessionDataObjects;

public sealed record HttpStatusBelow400Config
{
    public string[] OutputNames { get; set; } = Array.Empty<string>();
    public int MaximumExclusiveStatusCode { get; set; } = 400;
}

public sealed class HttpStatusBelow400 : BaseAssertion<HttpStatusBelow400Config>
{
    public override bool Assert(IImmutableList<SessionData> sessionDataList, IImmutableList<DataSource> dataSourceList)
    {
        var observed = sessionDataList.SelectMany(session => session.GetOutputByName(Configuration.OutputNames[0]).Data).ToImmutableList();
$assertionBodyLine
        var statusCode = observed[0].MetaData?.Http?.StatusCode;
        if (statusCode >= Configuration.MaximumExclusiveStatusCode)
        {
            AssertionMessage = "bad status";
            return false;
        }

        AssertionTrace = "required status < 400";
        return true;
    }
}
"@

    $usagePath = Join-Path $hookDir "HttpStatusBelow400.usage.yaml.txt"
    Write-TextFile -Path $usagePath -Value @'
Assertions:
  - Name: GetHealthMatchesDockerCurlF
    Assertion: HttpStatusBelow400
    AssertionConfiguration:
      MaximumExclusiveStatusCode: 400
      OutputNames:
        - GetHealth
'@

    $hookPlanPath = Join-Path $hookDir "custom-status-hook-plan.json"
    $packet = [ordered]@{
        packet_id = "crawl4ai-http-status-below-400"
        assertion_name = "HttpStatusBelow400"
        status = "blocked_until_build_template_live_airgapped_validation"
        promotion_state = "blocked"
        activation = "source_yaml_blocked"
        wired_into_runner_yaml = $true
        source_files = @($assertionSourcePath)
        yaml_fragment = $usagePath
        hook_plan = $hookPlanPath
        output_body_assertion = "unasserted_no_public_body_contract"
        maximum_exclusive_status_code = 400
        comparison = "http_status_less_than"
        validation_records = [ordered]@{ build = "not_run"; schema = "not_run"; template = "not_run"; live = "not_run"; airgapped = "not_run" }
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $hookPlanPath -Value ([ordered]@{
        schema_version = 1
        assertion_type = "HttpStatusBelow400"
        promotion_state = "blocked"
        custom_assertion_packet = $packet
    })

    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $safeCommand = if ($MissingCleanupOwnership) {
        "docker run -d -p 127.0.0.1:11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest"
    } else {
        "docker run -d -p 127.0.0.1:11235:11235 --name zappa-crawl4ai-health-{run_id} --shm-size=1g unclecode/crawl4ai:latest"
    }
    $cleanupStrategy = if ($MissingCleanupOwnership) { "docker_rm_force_container" } else { "docker_rm_force_test_owned_unique_container" }
    $mustNotRemove = if ($MissingCleanupOwnership) { "" } else { "crawl4ai" }
    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "unclecode/crawl4ai"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        public_command = "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest"
        pull_command = "docker pull unclecode/crawl4ai:latest"
        safe_test_command_template = $safeCommand
        image = "unclecode/crawl4ai:latest"
        readiness_probe = [ordered]@{ method = "GET"; url = "http://127.0.0.1:11235/health"; expected_status_semantics = "http_status_less_than_400"; maximum_exclusive_status_code = 400; expected_body = "unasserted_no_public_body_contract" }
        cleanup = [ordered]@{ required = $true; strategy = $cleanupStrategy; must_not_remove_container_name = $mustNotRemove; status = "not_validated" }
        blocked_endpoints = @([ordered]@{ route = "/crawl"; reason = "not deterministic" })
        blockers = @("prove_docker_lifecycle_and_cleanup_without_deleting_user_container", "build_and_template_validate_http_status_below_400_assertion", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation", "run_live_airgapped_weak_model_validation", "run_strong_review_against_selected_contract_evidence")
    })

    $docsEvidence = @(
        "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions.md",
        "D:\QaaS\qaas-docs\docs\assertions\custom-authoring-guide.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $publicEvidence = @($crawlSelectedPath, $readmePath, $dockerfilePath, $composePath, $schemasPath)
    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $artifacts = @($runnerPath, $requestPayloadPath, $assertionSourcePath, $usagePath, $hookPlanPath, $runtimePlanPath, $manifestPath)
    Write-JsonFile -Path $manifestPath -Value ([ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-crawl4ai-health-candidate"
        source_repository = "unclecode/crawl4ai"
        repository_rank = 250
        selected_contract = $crawlSelectedPath
        docs_evidence = $docsEvidence
        public_evidence = $publicEvidence
        artifacts = $artifacts
        artifact_count = $artifacts.Count
        custom_assertion_packets = @($packet)
        source_only_blockers = @(
            [ordered]@{ blocker_id = "crawl4ai-docker-lifecycle-not-proven"; blocker_type = "repository_contract"; description = "blocked"; required_evidence = @("docker"); public_evidence = $publicEvidence; unblock_instruction = "run docker lifecycle" },
            [ordered]@{ blocker_id = "crawl4ai-status-below-400-hook-not-template-validated"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("hook"); public_evidence = $docsEvidence; unblock_instruction = "run hook validation" },
            [ordered]@{ blocker_id = "crawl4ai-health-body-contract-not-selected"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("body contract"); public_evidence = @($dockerfilePath, $composePath); unblock_instruction = "do not assert body" },
            [ordered]@{ blocker_id = "crawl4ai-crawl-endpoint-not-promoted"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("crawl contract"); public_evidence = @($readmePath, $schemasPath); unblock_instruction = "do not promote crawl" },
            [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = $docsEvidence; unblock_instruction = "run qaas" },
            [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("airgapped"); public_evidence = @($readmePath); unblock_instruction = "run weak model" }
        )
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = $publicEvidence; check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-healthcheck-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($dockerfilePath, $composePath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; kind = "runtime"; required = $true; status = "ready"; evidence = $docsEvidence; check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "http-status-below-400-assertion-or-hook"; kind = "qaas-build"; required = $true; status = "blocked"; evidence = @($assertionSourcePath, $usagePath, $hookPlanPath); check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "docker-crawl4ai-container-lifecycle"; kind = "dependency"; required = $true; status = "blocked"; evidence = $publicEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "cleanup-contract"; kind = "cleanup"; required = $true; status = "blocked"; evidence = $publicEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-template"; kind = "qaas-template"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; kind = "qaas-build"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; kind = "airgapped"; required = $true; status = "blocked"; evidence = @(); check_command = ""; blocked_reason = "blocked" }
        )
        airgapped_validation = [ordered]@{ required = $true; status = "not_run_for_this_candidate" }
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
    })

    $jsonServerSelectedPath = Join-Path $selectedRoot "200-typicode-json-server\selected-contract.json"
    Write-JsonFile -Path (Join-Path $selectedRoot "selected-contract-index.json") -Value ([ordered]@{
        schema_version = 1
        selected_repository_count = 2
        records = @(
            [ordered]@{ repository = "typicode/json-server"; rank = 200; record_path = $jsonServerSelectedPath; status = "contract_content_harvested_not_executable"; promotion_state = "blocked" },
            [ordered]@{ repository = "unclecode/crawl4ai"; rank = 250; record_path = $crawlSelectedPath; status = "contract_content_harvested_not_executable"; promotion_state = "blocked" }
        )
    })

    $indexPath = Join-Path $candidateRoot "selected-candidate-index.json"
    $index = Read-JsonFile -Path $indexPath
    $recordsForIndex = @($index.records)
    $recordsForIndex += [ordered]@{
        rank = 250
        repository = "unclecode/crawl4ai"
        directory = $candidateDir
        manifest = $manifestPath
        selected_contract = $crawlSelectedPath
        status = "candidate_packet_blocked_until_template_live_airgapped_validation"
        promotion_state = "blocked"
        artifact_count = $artifacts.Count
    }
    Write-JsonFile -Path $indexPath -Value ([ordered]@{
        schema_version = 1
        output_directory = $candidateRoot
        selected_candidate_count = $recordsForIndex.Count
        selected_contract_count = 2
        deferred_candidate_count = 0
        records = $recordsForIndex
        deferred_records = @()
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        SelectedRoot = $selectedRoot
        CandidateDir = $candidateDir
    }
}

function New-Crawl4AiLifecycleFixture {
    param(
        [string]$Root,
        [switch]$WeakValidationPassed,
        [switch]$QaaSValidationPassed,
        [switch]$WrongStatus,
        [switch]$UnsafeContainerName,
        [switch]$ProtectedContainerChanged,
        [switch]$BadResponseSha
    )

    $fixture = New-Crawl4AiHealthCandidateFixture -Root $Root
    $candidateDir = $fixture.CandidateDir
    $candidateRoot = $fixture.CandidateRoot
    $lifecycleRoot = Join-Path $Root "lifecycle-runs\selected-top-repo-candidates"
    $runDir = Join-Path $lifecycleRoot "20260608-000000-000"
    $evidenceDir = Join-Path $runDir "evidence"
    [System.IO.Directory]::CreateDirectory($evidenceDir) | Out-Null

    $summaryPath = Join-Path $Root "coverage\selected-top-repo-candidate-lifecycle-crawl4ai.json"
    $responsePath = Join-Path $evidenceDir "health-response.txt"
    $transcriptPath = Join-Path $evidenceDir "crawl4ai-lifecycle.transcript.txt"
    $stdoutPath = Join-Path $evidenceDir "docker.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "docker.stderr.txt"
    $pullStdoutPath = Join-Path $evidenceDir "docker-pull.stdout.txt"
    $pullStderrPath = Join-Path $evidenceDir "docker-pull.stderr.txt"
    $runStdoutPath = Join-Path $evidenceDir "docker-run.stdout.txt"
    $runStderrPath = Join-Path $evidenceDir "docker-run.stderr.txt"
    $rmStdoutPath = Join-Path $evidenceDir "docker-rm.stdout.txt"
    $rmStderrPath = Join-Path $evidenceDir "docker-rm.stderr.txt"
    $logsStdoutPath = Join-Path $evidenceDir "docker-logs.stdout.txt"
    $logsStderrPath = Join-Path $evidenceDir "docker-logs.stderr.txt"
    $inspectStartedPath = Join-Path $evidenceDir "docker-inspect-started.json"
    $inspectAfterCleanupPath = Join-Path $evidenceDir "docker-inspect-after-cleanup.txt"
    $containerName = if ($UnsafeContainerName) { "crawl4ai" } else { "zappa-crawl4ai-health-20260608-000000-000" }
    $responseStatus = if ($WrongStatus) { 500 } else { 200 }
    Write-TextFile -Path $responsePath -Value '{"status":"ok"}'
    foreach ($path in @($stdoutPath, $stderrPath, $pullStdoutPath, $pullStderrPath, $runStdoutPath, $runStderrPath, $rmStdoutPath, $rmStderrPath, $logsStdoutPath, $logsStderrPath)) {
        Write-TextFile -Path $path -Value "fixture"
    }
    Write-TextFile -Path $inspectStartedPath -Value (@(
            "{",
            '  "Name": "' + $containerName + '",',
            '  "Image": "unclecode/crawl4ai:latest"',
            "}"
        ) -join [Environment]::NewLine)
    Write-TextFile -Path $inspectAfterCleanupPath -Value ""
    $responseSha = if ($BadResponseSha) { "fixture-sha" } else { Get-FileSha256Hex -Path $responsePath }
    $inspectStartedSha = Get-FileSha256Hex -Path $inspectStartedPath
    $inspectAfterCleanupSha = Get-FileSha256Hex -Path $inspectAfterCleanupPath
    $afterProtected = if ($ProtectedContainerChanged) { @() } else { @("crawl4ai") }

    Write-TextFile -Path $transcriptPath -Value @"
Validation: selected-top-repo-candidate-lifecycle-crawl4ai
Repository: unclecode/crawl4ai
DockerPullCommand: docker pull unclecode/crawl4ai:latest
DockerPullExitCode: 0
DockerRunCommand: docker run -d -p 127.0.0.1:11235:11235 --name $containerName --shm-size=1g unclecode/crawl4ai:latest
DockerRunExitCode: 0
Image: unclecode/crawl4ai:latest
ContainerName: $containerName
ProtectedContainerName: crawl4ai
ProtectedContainerNamesBefore: crawl4ai
ProtectedContainerNamesAfter: $($afterProtected -join ',')
ReadinessUrl: http://127.0.0.1:11235/health
Ready: True
ResponseStatus: $responseStatus
ResponseBodySha256: $responseSha
DockerInspectStartedSha256: $inspectStartedSha
DockerInspectAfterCleanupSha256: $inspectAfterCleanupSha
DockerRmExitCode: 0
CleanupTargetContainerName: $containerName
CleanupPassed: True
ContainerExistsAfterCleanup: False
PortOwnersAfterCleanupCount: 0
ExitCode: 0
"@

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $lifecycleValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "docker pull unclecode/crawl4ai:latest ; docker run ; GET http://127.0.0.1:11235/health ; docker rm -f $containerName"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @()
    }

    $manifest = Read-JsonFile -Path $manifestPath
    Set-JsonProperty -Object $manifest -Name "lifecycle_validation" -Value $lifecycleValidation
    $manifest.source_only_blockers = @($manifest.source_only_blockers | Where-Object { [string]$_.blocker_id -ne "crawl4ai-docker-lifecycle-not-proven" })
    foreach ($gate in @($manifest.dependency_gates)) {
        if ([string]$gate.gate_id -in @("docker-crawl4ai-container-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath, $inspectStartedPath, $inspectAfterCleanupPath)
            $gate.blocked_reason = ""
        }
    }
    if ($QaaSValidationPassed) {
        Set-JsonProperty -Object $manifest -Name "selected_candidate_qaas_validation" -Value ([ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath })
    }
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan = Read-JsonFile -Path $runtimePlanPath
    $runtimePlan.cleanup.status = "passed"
    Set-JsonProperty -Object $runtimePlan.cleanup -Name "evidence" -Value @($summaryPath, $transcriptPath, $inspectAfterCleanupPath)
    Set-JsonProperty -Object $runtimePlan.cleanup -Name "last_validated_container_name" -Value $containerName
    Set-JsonProperty -Object $runtimePlan -Name "lifecycle_validation" -Value $lifecycleValidation
    $runtimePlan.blockers = @($runtimePlan.blockers | Where-Object { [string]$_ -ne "prove_docker_lifecycle_and_cleanup_without_deleting_user_container" })
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = "passed"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "unclecode/crawl4ai"
        validation_kind = "selected_candidate_docker_lifecycle"
        command = "docker run -d -p 127.0.0.1:11235:11235 --name $containerName --shm-size=1g unclecode/crawl4ai:latest"
        pull_command = "docker pull unclecode/crawl4ai:latest"
        image = "unclecode/crawl4ai:latest"
        image_id = "sha256:fixture"
        docker_path = Join-Path $evidenceDir "docker.exe"
        docker_server_version = "29.4.3"
        docker_pull_exit_code = 0
        docker_run_exit_code = 0
        docker_rm_exit_code = 0
        container_name = $containerName
        container_id = "fixture-container-id"
        cleanup_target_container_name = $containerName
        protected_container_name = "crawl4ai"
        protected_container_names_before = @("crawl4ai")
        protected_container_names_after = $afterProtected
        transcript = $transcriptPath
        stdout = $stdoutPath
        stderr = $stderrPath
        response = $responsePath
        response_status = $responseStatus
        response_body_sha256 = $responseSha
        response_contract_passed = $true
        docker_pull_stdout = $pullStdoutPath
        docker_pull_stderr = $pullStderrPath
        docker_run_stdout = $runStdoutPath
        docker_run_stderr = $runStderrPath
        docker_rm_stdout = $rmStdoutPath
        docker_rm_stderr = $rmStderrPath
        docker_logs_stdout = $logsStdoutPath
        docker_logs_stderr = $logsStderrPath
        docker_inspect_started = $inspectStartedPath
        docker_inspect_after_cleanup = $inspectAfterCleanupPath
        docker_inspect_started_sha256 = $inspectStartedSha
        docker_inspect_after_cleanup_sha256 = $inspectAfterCleanupSha
        cleanup_passed = $true
        container_exists_after_cleanup = $false
        cleanup_process_ids = @()
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        run_dir = $runDir
        exit_code = 0
        failure_reason = ""
        manifest_updated = $true
        weak_validation_passed = [bool]$WeakValidationPassed
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        LifecycleRoot = $lifecycleRoot
        SummaryPath = $summaryPath
    }
}

function New-FlaskSelectedCandidateFixture {
    param(
        [string]$Root,
        [switch]$UseActiveCustomAssertion,
        [switch]$LooseContainsHook,
        [switch]$MissingTextBodyBlocker,
        [switch]$WiredIntoRunnerYaml,
        [switch]$BadExpectedBodySha,
        [switch]$SourceOutsideAssertionPackets,
        [switch]$WeakValidationPassed
    )

    $selectedRoot = Join-Path $Root "selected-contracts"
    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $selectedDir = Join-Path $selectedRoot "227-pallets-flask"
    $selectedFilesDir = Join-Path $selectedDir "files"
    $candidateDir = Join-Path $candidateRoot "227-pallets-flask"
    $appDir = Join-Path $candidateDir "app"
    $expectationsDir = Join-Path $candidateDir "expectations"
    $requestPayloadsDir = Join-Path $candidateDir "request-payloads"
    $assertionDir = Join-Path $candidateDir "assertion-packets\ExactHttpTextBody"
    foreach ($dir in @($selectedFilesDir, $appDir, $expectationsDir, $requestPayloadsDir, $assertionDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $readmePath = Join-Path $selectedFilesDir "README.md"
    Write-TextFile -Path $readmePath -Value @'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello_world():
    return "Hello, World!"
'@

    $sha = "58d50e3fd63d9a8ecf8c7f7b19d43ad8748459c4"
    $selectedFileRecord = [ordered]@{
        source_path = "README.md"
        local_path = $readmePath
        sha = $sha
        git_blob_sha_verified = $true
        content_sha256 = "fixture-sha256"
        size = 128
        fetched_size = 128
        reason = "fixture"
        github_blob_url = "https://api.github.com/repos/pallets/flask/git/blobs/$sha"
    }

    $selectedRecordPath = Join-Path $selectedDir "selected-contract.json"
    Write-JsonFile -Path $selectedRecordPath -Value ([ordered]@{
        schema_version = 1
        repository = "pallets/flask"
        rank = 227
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        selected_public_contracts = @($selectedFileRecord)
        candidate_promotion_contracts = @(
            [ordered]@{ supports = "runtime-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("flask-localhost-5000") },
            [ordered]@{ supports = "candidate-executable-command"; status = "candidate_evidence_harvested"; evidence_markers = @("flask-run-command") },
            [ordered]@{ supports = "input-output-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("hello-world-body") }
        )
    })

    $runnerPath = Join-Path $candidateDir "test.qaas.yaml"
    $customAssertionYaml = if ($UseActiveCustomAssertion) {
@'
  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - FlaskReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello, World!
      EncodingName: utf-8
'@
    } else {
        ""
    }
    Write-TextFile -Path $runnerPath -Value @"
# Status: blocked_until_template_live_airgapped_validation
MetaData:
  Team: ZappaDontCry
  System: pallets-flask

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetRootPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-root.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: FlaskReadRoot
    Transactions:
      - Name: GetRoot
        TimeoutMs: 5000
        DataSourceNames:
          - GetRootPayload
        DataSourcePatterns:
          - GetRootPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 5000
          Route: /
          Method: Get

Assertions:
  - Name: GetRootReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - FlaskReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetRoot
$customAssertionYaml
"@

    $appPath = Join-Path $appDir "app.py"
    Write-TextFile -Path $appPath -Value @'
from flask import Flask

app = Flask(__name__)


@app.route("/")
def root():
    return "Hello, World!"
'@

    $expectedBodyPath = Join-Path $expectationsDir "root-body.txt"
    Write-TextFile -Path $expectedBodyPath -Value "Hello, World!"
    $requestPayloadPath = Join-Path $requestPayloadsDir "get-root.bin"
    [System.IO.File]::WriteAllBytes($requestPayloadPath, [byte[]]::new(0))
    $expectedBodySha = Get-Sha256Hex -Bytes ([System.IO.File]::ReadAllBytes($expectedBodyPath))
    if ($BadExpectedBodySha) {
        $expectedBodySha = "bad-sha256"
    }

    $hookPath = Join-Path $assertionDir "ExactHttpTextBody.cs"
    $hookText = @'
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using QaaS.Framework.SDK.DataSourceObjects;
using QaaS.Framework.SDK.Extensions;
using QaaS.Framework.SDK.Hooks.Assertion;
using QaaS.Framework.SDK.Session.SessionDataObjects;

namespace ZappaDontCry.SelectedCandidates.Flask.Assertions;

public sealed record ExactHttpTextBodyConfig
{
    [Description("Transaction output name to inspect.")]
    [Required]
    public string OutputName { get; set; } = string.Empty;

    [Description("Exact expected response body text.")]
    [Required]
    public string ExpectedText { get; set; } = string.Empty;

    [Description("Encoding name used to decode the response Body byte array.")]
    [DefaultValue("utf-8")]
    public string EncodingName { get; set; } = "utf-8";
}

public sealed class ExactHttpTextBody : BaseAssertion<ExactHttpTextBodyConfig>
{
    public override bool Assert(
        IImmutableList<SessionData> sessionDataList,
        IImmutableList<DataSource> dataSourceList)
    {
        if (Configuration is null)
        {
            AssertionMessage = "ExactHttpTextBody configuration was not loaded.";
            return false;
        }

        Encoding encoding = Encoding.GetEncoding(
            string.IsNullOrWhiteSpace(Configuration.EncodingName)
                ? "utf-8"
                : Configuration.EncodingName);

        var observed = sessionDataList
            .SelectMany(session => session.GetOutputByName(Configuration.OutputName).Data)
            .ToImmutableList();

        var failures = new List<string>();
        for (var index = 0; index < observed.Count; index++)
        {
            var item = observed[index];
            if (item.Body is not byte[] body)
            {
                failures.Add("body was not byte array");
                continue;
            }

            var actualText = encoding.GetString(body);
            if (!string.Equals(actualText, Configuration.ExpectedText, StringComparison.Ordinal))
            {
                failures.Add("body mismatch");
            }
        }

        AssertionTrace = $"Observed {observed.Count} output item(s) for '{Configuration.OutputName}'.";
        if (failures.Count > 0)
        {
            AssertionMessage = string.Join("; ", failures);
            return false;
        }

        AssertionMessage = "All observed bodies exactly matched.";
        return true;
    }
}
'@
    if ($LooseContainsHook) {
        $hookText = $hookText.Replace(
            "!string.Equals(actualText, Configuration.ExpectedText, StringComparison.Ordinal)",
            "!actualText.Contains(Configuration.ExpectedText, StringComparison.Ordinal)")
    }
    Write-TextFile -Path $hookPath -Value $hookText

    $usagePath = Join-Path $assertionDir "ExactHttpTextBody.usage.yaml.txt"
    Write-TextFile -Path $usagePath -Value @'
# Non-executable usage snippet.
Assertions:
  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - FlaskReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello, World!
      EncodingName: utf-8
'@

    $docsEvidence = @(
        "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md",
        "D:\QaaS\qaas-docs\docs\generators\availableGenerators\FromFileSystem\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputContentByExpectedCsvResults\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\index.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )

    $planPath = Join-Path $assertionDir "custom-text-body-hook-plan.json"
    Write-JsonFile -Path $planPath -Value ([ordered]@{
        schema_version = 1
        status = "authored_from_public_docs_not_template_validated"
        hook_family = "assertion"
        assertion_type = "ExactHttpTextBody"
        builtins_considered = @(
            [ordered]@{ name = "HttpStatus"; reason_insufficient = "Status-only assertion." },
            [ordered]@{ name = "OutputContentByExpectedCsvResults"; reason_insufficient = "JSON/CSV assertion, not raw plain text." }
        )
        promotion_state = "blocked"
        weak_validation_passed = [bool]$WeakValidationPassed
    })

    $packetSourceFiles = @($hookPath)
    if ($SourceOutsideAssertionPackets) {
        $outsideSourcePath = Join-Path $candidateDir "hook-source\ExactHttpTextBody.cs"
        Write-TextFile -Path $outsideSourcePath -Value $hookText
        $packetSourceFiles = @($outsideSourcePath)
    }

    $customAssertionPacket = [ordered]@{
        packet_id = "flask-exact-http-text-body"
        assertion_name = "ExactHttpTextBody"
        status = "blocked_until_build_template_live_airgapped_validation"
        promotion_state = "blocked"
        activation = "sidecar_only"
        wired_into_runner_yaml = [bool]$WiredIntoRunnerYaml
        source_files = $packetSourceFiles
        yaml_fragment = $usagePath
        hook_plan = $planPath
        expected_body_path = $expectedBodyPath
        expected_body_sha256 = $expectedBodySha
        encoding = "utf-8"
        comparison = "byte_for_byte"
        normalization = "none"
        case_sensitive = $true
        trim = $false
        contains = $false
        docs_evidence = $docsEvidence
        public_evidence = @($selectedRecordPath, $readmePath)
        validation_records = [ordered]@{
            build = "not_run"
            schema = "not_run"
            template = "not_run"
            live = "not_run"
            airgapped = "not_run"
        }
        weak_validation_passed = [bool]$WeakValidationPassed
    }

    Write-JsonFile -Path $planPath -Value ([ordered]@{
        schema_version = 1
        status = "authored_from_public_docs_not_template_validated"
        hook_family = "assertion"
        assertion_type = "ExactHttpTextBody"
        builtins_considered = @(
            [ordered]@{ name = "HttpStatus"; reason_insufficient = "Status-only assertion." },
            [ordered]@{ name = "OutputContentByExpectedCsvResults"; reason_insufficient = "JSON/CSV assertion, not raw plain text." }
        )
        promotion_state = "blocked"
        weak_validation_passed = [bool]$WeakValidationPassed
        custom_assertion_packet = $customAssertionPacket
    })

    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "pallets/flask"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command = "flask run"
        cleanup = [ordered]@{ required = $true; status = "not_validated" }
        blockers = @(
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence",
            "prove_process_lifecycle_and_cleanup_without assuming private source"
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            assertion_type = "ExactHttpTextBody"
            implementation = $hookPath
            usage_snippet = $usagePath
            hook_plan = $planPath
            validation_status = "not_template_validated"
        }
        custom_assertion_packets = @($customAssertionPacket)
    })
    $sourceBlockers = @(
        [ordered]@{ blocker_id = "flask-process-lifecycle-not-proven"; blocker_type = "repository_contract"; description = "blocked"; required_evidence = @("lifecycle"); public_evidence = @($selectedRecordPath, $readmePath); unblock_instruction = "validate lifecycle" },
        [ordered]@{ blocker_id = "flask-text-body-hook-not-template-validated"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = $docsEvidence; unblock_instruction = "template validate hook" },
        [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = $docsEvidence; unblock_instruction = "run qaas" },
        [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @($readmePath); unblock_instruction = "run weak model" },
        [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = $docsEvidence; unblock_instruction = "use schema" }
    )
    if ($MissingTextBodyBlocker) {
        $sourceBlockers = @($sourceBlockers | Where-Object { $_.blocker_id -ne "flask-text-body-hook-not-template-validated" })
    }

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $artifacts = @($runnerPath, $appPath, $expectedBodyPath, $requestPayloadPath, $runtimePlanPath, $manifestPath)
    Write-JsonFile -Path $manifestPath -Value ([ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-flask-candidate"
        source_repository = "pallets/flask"
        repository_rank = 227
        selected_contract = $selectedRecordPath
        docs_evidence = $docsEvidence
        public_evidence = @($selectedRecordPath, $readmePath)
        artifacts = $artifacts
        artifact_count = $artifacts.Count
        airgapped_validation = [ordered]@{ required = $true; status = "not_run_for_this_candidate"; dry_run = $false }
        source_only_blockers = $sourceBlockers
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; kind = "runtime"; required = $true; status = "ready"; evidence = $docsEvidence; check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "python-flask-process-lifecycle"; kind = "dependency"; required = $true; status = "blocked"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "cleanup-contract"; kind = "cleanup"; required = $true; status = "blocked"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "plain-text-body-assertion-or-hook"; kind = "qaas-hook"; required = $true; status = "ready"; evidence = @($hookPath, $usagePath, $planPath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-template"; kind = "qaas-template"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; kind = "qaas-build"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; kind = "airgapped"; required = $true; status = "blocked"; evidence = @(); check_command = ""; blocked_reason = "blocked" }
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            hook_family = "assertion"
            assertion_type = "ExactHttpTextBody"
            implementation = $hookPath
            usage_snippet = $usagePath
            hook_plan = $planPath
            validation_status = "not_template_validated"
            weak_validation_passed = [bool]$WeakValidationPassed
        }
        custom_assertion_packets = @($customAssertionPacket)
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
    })

    Write-JsonFile -Path (Join-Path $candidateRoot "selected-candidate-index.json") -Value ([ordered]@{
        schema_version = 1
        selected_candidate_count = 1
        output_directory = $candidateRoot
        records = @(
            [ordered]@{
                rank = 227
                repository = "pallets/flask"
                directory = $candidateDir
                manifest = $manifestPath
                selected_contract = $selectedRecordPath
                status = "candidate_packet_blocked_until_template_live_airgapped_validation"
                promotion_state = "blocked"
                artifact_count = $artifacts.Count
            }
        )
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        SelectedRoot = $selectedRoot
        CandidateDir = $candidateDir
    }
}

function New-FastApiSelectedCandidateFixture {
    param(
        [string]$Root,
        [switch]$MissingBodyAssertion,
        [switch]$WrongRouteAndPort,
        [switch]$EmbedProcessCommand,
        [switch]$MissingLifecycleBlocker,
        [switch]$LifecyclePassed,
        [switch]$QaaSValidationPassed,
        [switch]$RuntimeQaaSValidationPassed,
        [switch]$BuildValidationPassed,
        [switch]$TemplateValidationPassed,
        [switch]$LiveValidationPassed,
        [switch]$LifecycleSummaryCleanupNotPassed
    )

    $selectedRoot = Join-Path $Root "selected-contracts"
    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $selectedDir = Join-Path $selectedRoot "114-fastapi-fastapi"
    $selectedFilesDir = Join-Path $selectedDir "files"
    $candidateDir = Join-Path $candidateRoot "114-fastapi-fastapi"
    $appDir = Join-Path $candidateDir "app"
    $schemasDir = Join-Path $candidateDir "schemas"
    $requestPayloadsDir = Join-Path $candidateDir "request-payloads"
    foreach ($dir in @($selectedFilesDir, $appDir, $schemasDir, $requestPayloadsDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $readmePath = Join-Path $selectedFilesDir "README.md"
    Write-TextFile -Path $readmePath -Value @'
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def read_root():
    return {"Hello": "World"}

@app.get("/items/{item_id}")
def read_item(item_id: int, q: str | None = None):
    return {"item_id": item_id, "q": q}

$ fastapi dev
http://127.0.0.1:8000
http://127.0.0.1:8000/items/5?q=somequery
{"item_id": 5, "q": "somequery"}
'@

    $sha = "86e75109010e35f1eb284ccbed89cd28028dab7d"
    $selectedFileRecord = [ordered]@{
        source_path = "README.md"
        local_path = $readmePath
        sha = $sha
        git_blob_sha_verified = $true
        content_sha256 = "fixture-sha256"
        size = 256
        fetched_size = 256
        reason = "fixture"
        github_blob_url = "https://api.github.com/repos/fastapi/fastapi/git/blobs/$sha"
    }

    $selectedRecordPath = Join-Path $selectedDir "selected-contract.json"
    Write-JsonFile -Path $selectedRecordPath -Value ([ordered]@{
        schema_version = 1
        repository = "fastapi/fastapi"
        rank = 114
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        selected_public_contracts = @($selectedFileRecord)
        candidate_promotion_contracts = @(
            [ordered]@{ supports = "runtime-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("runtime-url-loopback-8000") },
            [ordered]@{ supports = "http-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("http-route-items-query") },
            [ordered]@{ supports = "candidate-executable-command"; status = "candidate_evidence_harvested"; evidence_markers = @("fastapi-command") }
        )
    })

    $route = if ($WrongRouteAndPort) { "/items/5" } else { "items/5?q=somequery" }
    $port = if ($WrongRouteAndPort) { 8080 } else { 8000 }
    $bodyAssertion = if ($MissingBodyAssertion) {
        ""
    } else {
@'

  - Name: GetItemFiveBodyMatchesReadmeSchema
    Assertion: ObjectOutputJsonSchema
    SessionNames:
      - FastApiReadItem
    DataSourceNames:
      - FastApiReadmeItemResponseSchemas
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetItemFive
'@
    }
    $processComment = if ($EmbedProcessCommand) { "# fastapi dev`n" } else { "" }

    $runnerPath = Join-Path $candidateDir "test.qaas.yaml"
    Write-TextFile -Path $runnerPath -Value @"
$processComment# Status: blocked_until_template_live_airgapped_validation
MetaData:
  Team: ZappaDontCry
  System: fastapi-fastapi

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetItemPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-items-5.bin'
      StorageMetaData: ItemName

  - Name: FastApiReadmeItemResponseSchemas
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './schemas'
        SearchPattern: 'item-response.schema.json'
      StorageMetaData: ItemName

Sessions:
  - Name: FastApiReadItem
    Transactions:
      - Name: GetItemFive
        TimeoutMs: 5000
        DataSourceNames:
          - GetItemPayload
        DataSourcePatterns:
          - GetItemPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: $port
          Route: $route
          Method: Get
        OutputDeserialize:
          Deserializer: Json

Assertions:
  - Name: GetItemFiveReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - FastApiReadItem
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetItemFive
$bodyAssertion
"@

    $appPath = Join-Path $appDir "main.py"
    Write-TextFile -Path $appPath -Value @'
from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def read_root():
    return {"Hello": "World"}


@app.get("/items/{item_id}")
def read_item(item_id: int, q: str | None = None):
    return {"item_id": item_id, "q": q}
'@

    $schemaPath = Join-Path $schemasDir "item-response.schema.json"
    Write-TextFile -Path $schemaPath -Value @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["item_id", "q"],
  "additionalProperties": false,
  "properties": {
    "item_id": { "const": 5 },
    "q": { "const": "somequery" }
  }
}
'@

    $requestPayloadPath = Join-Path $requestPayloadsDir "get-items-5.bin"
    [System.IO.File]::WriteAllBytes($requestPayloadPath, [byte[]]::new(0))

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $coverageDir = Join-Path $Root "coverage"
    $evidenceDir = Join-Path $Root "lifecycle-runs\selected-top-repo-candidates\20260608-000000-000\evidence"
    $summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-fastapi.json"
    $transcriptPath = Join-Path $evidenceDir "fastapi-lifecycle.transcript.txt"
    $stdoutPath = Join-Path $evidenceDir "fastapi.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "fastapi.stderr.txt"
    $responsePath = Join-Path $evidenceDir "items-5-response.json"
    if ($LifecyclePassed) {
        Write-TextFile -Path $responsePath -Value '{"item_id":5,"q":"somequery"}'
        Write-TextFile -Path $stdoutPath -Value "fastapi stdout"
        Write-TextFile -Path $stderrPath -Value "fastapi stderr"
        Write-TextFile -Path $transcriptPath -Value @"
Validation: selected-top-repo-candidate-lifecycle-fastapi
Repository: fastapi/fastapi
Command: fastapi dev
Ready: True
ResponseStatus: 200
CleanupPassed: True
ExitCode: 0
"@
    }

    $cleanupStatus = if ($LifecyclePassed) { "passed" } else { "not_validated" }
    $runtimeBlockers = @(
        "prove_process_lifecycle_and_cleanup_without assuming private source",
        "run_qaaS_template_validation",
        "run_live_qaaS_act_assert_validation",
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence"
    )
    if ($LifecyclePassed) {
        $runtimeBlockers = @($runtimeBlockers | Where-Object { $_ -ne "prove_process_lifecycle_and_cleanup_without assuming private source" })
    }
    $lifecycleValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "fastapi dev ; GET http://127.0.0.1:8000/items/5?q=somequery ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @(12345)
    }
    $runtimePlan = [ordered]@{
        schema_version = 1
        repository = "fastapi/fastapi"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        command = "fastapi dev"
        working_directory = $appDir
        fixture = $appPath
        expected_listen_url = "http://127.0.0.1:8000"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:8000/items/5?q=somequery"
            expected_status = 200
            expected_json = [ordered]@{ item_id = 5; q = "somequery" }
        }
        cleanup = [ordered]@{ required = $true; strategy = "terminate_tracked_process_tree"; status = $cleanupStatus }
        blockers = $runtimeBlockers
    }
    if ($LifecyclePassed) {
        $runtimePlan["cleanup"]["evidence"] = @($summaryPath, $transcriptPath)
        $runtimePlan["lifecycle_validation"] = $lifecycleValidation
    }
    if ($RuntimeQaaSValidationPassed) {
        $runtimePlan["qaas_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

    $docsEvidence = @(
        "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md",
        "D:\QaaS\qaas-docs\docs\generators\availableGenerators\FromFileSystem\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\overview.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $sourceBlockers = @(
        [ordered]@{ blocker_id = "fastapi-process-lifecycle-not-proven"; blocker_type = "repository_contract"; description = "blocked"; required_evidence = @("lifecycle"); public_evidence = @($selectedRecordPath, $readmePath); unblock_instruction = "validate lifecycle" },
        [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = $docsEvidence; unblock_instruction = "run qaas" },
        [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @($readmePath); unblock_instruction = "run weak model" },
        [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = $docsEvidence; unblock_instruction = "use schema" }
    )
    if ($MissingLifecycleBlocker -or $LifecyclePassed) {
        $sourceBlockers = @($sourceBlockers | Where-Object { $_.blocker_id -ne "fastapi-process-lifecycle-not-proven" })
    }

    $lifecycleGateStatus = if ($LifecyclePassed) { "passed" } else { "blocked" }
    $lifecycleGateEvidence = if ($LifecyclePassed) { @($summaryPath, $transcriptPath, $responsePath) } else { @($selectedRecordPath, $readmePath) }
    $lifecycleGateBlockedReason = if ($LifecyclePassed) { "" } else { "blocked" }
    $lifecycleGate = if ($MissingLifecycleBlocker) {
        @()
    } else {
        @([ordered]@{ gate_id = "python-fastapi-process-lifecycle"; kind = "dependency"; required = $true; status = $lifecycleGateStatus; evidence = $lifecycleGateEvidence; check_command = ""; blocked_reason = $lifecycleGateBlockedReason })
    }

    $cleanupGateStatus = if ($LifecyclePassed) { "passed" } else { "blocked" }
    $cleanupGateEvidence = if ($LifecyclePassed) { @($summaryPath, $transcriptPath, $responsePath) } else { @($selectedRecordPath, $readmePath) }
    $cleanupGateBlockedReason = if ($LifecyclePassed) { "" } else { "blocked" }
    $artifacts = @($runnerPath, $appPath, $schemaPath, $requestPayloadPath, $runtimePlanPath, $manifestPath)
    $manifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-fastapi-candidate"
        source_repository = "fastapi/fastapi"
        repository_rank = 114
        selected_contract = $selectedRecordPath
        docs_evidence = $docsEvidence
        public_evidence = @($selectedRecordPath, $readmePath)
        artifacts = $artifacts
        artifact_count = $artifacts.Count
        airgapped_validation = [ordered]@{ required = $true; status = "not_run_for_this_candidate"; dry_run = $false }
        source_only_blockers = $sourceBlockers
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; kind = "runtime"; required = $true; status = "ready"; evidence = $docsEvidence; check_command = ""; blocked_reason = "" }
            $lifecycleGate
            [ordered]@{ gate_id = "cleanup-contract"; kind = "cleanup"; required = $true; status = $cleanupGateStatus; evidence = $cleanupGateEvidence; check_command = ""; blocked_reason = $cleanupGateBlockedReason },
            [ordered]@{ gate_id = "qaas-template"; kind = "qaas-template"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; kind = "qaas-build"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; kind = "airgapped"; required = $true; status = "blocked"; evidence = @(); check_command = ""; blocked_reason = "blocked" }
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
    }
    if ($LifecyclePassed) {
        $manifest["lifecycle_validation"] = $lifecycleValidation
    }
    if ($QaaSValidationPassed) {
        $manifest["selected_candidate_qaas_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    if ($BuildValidationPassed) {
        $manifest["build_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    if ($TemplateValidationPassed) {
        $manifest["template_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    if ($LiveValidationPassed) {
        $manifest["live_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    Write-JsonFile -Path $manifestPath -Value $manifest

    if ($LifecyclePassed) {
        Write-JsonFile -Path $summaryPath -Value ([ordered]@{
            schema_version = 1
            status = "passed"
            promotion_state = "blocked"
            completion_ready = $false
            repository = "fastapi/fastapi"
            validation_kind = "selected_candidate_process_lifecycle"
            command = "fastapi dev"
            transcript = $transcriptPath
            stdout = $stdoutPath
            stderr = $stderrPath
            response = $responsePath
            response_status = 200
            response_contract_passed = $true
            cleanup_passed = (-not [bool]$LifecycleSummaryCleanupNotPassed)
            cleanup_process_ids = @(12345)
            remaining_tracked_process_ids = @()
            port_owners_after_cleanup_count = 0
            manifest = $manifestPath
            runtime_plan = $runtimePlanPath
            run_dir = (Split-Path -Parent $evidenceDir)
            exit_code = 0
            failure_reason = ""
            weak_validation_passed = $false
        })
    }

    Write-JsonFile -Path (Join-Path $candidateRoot "selected-candidate-index.json") -Value ([ordered]@{
        schema_version = 1
        selected_candidate_count = 1
        output_directory = $candidateRoot
        records = @(
            [ordered]@{
                rank = 114
                repository = "fastapi/fastapi"
                directory = $candidateDir
                manifest = $manifestPath
                selected_contract = $selectedRecordPath
                status = "candidate_packet_blocked_until_template_live_airgapped_validation"
                promotion_state = "blocked"
                artifact_count = $artifacts.Count
            }
        )
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        SelectedRoot = $selectedRoot
        CandidateDir = $candidateDir
        CoverageDir = $coverageDir
    }
}

function New-GinSelectedCandidateFixture {
    param(
        [string]$Root,
        [switch]$MissingBodyAssertion,
        [switch]$WrongRouteAndPort,
        [switch]$EmbedProcessCommand,
        [switch]$MissingLifecycleBlocker,
        [switch]$BodySchemaDrift,
        [switch]$LifecyclePassed
    )

    $selectedRoot = Join-Path $Root "selected-contracts"
    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $selectedDir = Join-Path $selectedRoot "138-gin-gonic-gin"
    $selectedFilesDir = Join-Path $selectedDir "files"
    $candidateDir = Join-Path $candidateRoot "138-gin-gonic-gin"
    $appDir = Join-Path $candidateDir "app"
    $schemasDir = Join-Path $candidateDir "schemas"
    $requestPayloadsDir = Join-Path $candidateDir "request-payloads"
    foreach ($dir in @($selectedFilesDir, $appDir, $schemasDir, $requestPayloadsDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $readmePath = Join-Path $selectedFilesDir "README.md"
    Write-TextFile -Path $readmePath -Value @'
Gin requires Go version 1.25 or above.
With Go's module support, simply import Gin in your code and Go will automatically fetch it during build:
import "github.com/gin-gonic/gin"

package main

import (
  "log"
  "net/http"

  "github.com/gin-gonic/gin"
)

func main() {
  r := gin.Default()

  r.GET("/ping", func(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{
      "message": "pong",
    })
  })

  if err := r.Run(); err != nil {
    log.Fatalf("failed to run server: %v", err)
  }
}

go run main.go
http://localhost:8080/ping
{"message":"pong"}
'@

    $sha = "96b0ae3c10204e14099683602217c10541ace230"
    $selectedFileRecord = [ordered]@{
        source_path = "README.md"
        local_path = $readmePath
        sha = $sha
        git_blob_sha_verified = $true
        content_sha256 = "fixture-sha256"
        size = 512
        fetched_size = 512
        reason = "fixture"
        github_blob_url = "https://api.github.com/repos/gin-gonic/gin/git/blobs/$sha"
    }

    $selectedRecordPath = Join-Path $selectedDir "selected-contract.json"
    Write-JsonFile -Path $selectedRecordPath -Value ([ordered]@{
        schema_version = 1
        repository = "gin-gonic/gin"
        rank = 138
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        selected_public_contracts = @($selectedFileRecord)
        candidate_promotion_contracts = @(
            [ordered]@{ supports = "candidate-executable-command"; status = "candidate_evidence_harvested"; evidence_markers = @("go-run-command") },
            [ordered]@{ supports = "input-output-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("expected-json-pong") }
        )
    })

    $route = if ($WrongRouteAndPort) { "/" } else { "/ping" }
    $port = if ($WrongRouteAndPort) { 8000 } else { 8080 }
    $bodyAssertion = if ($MissingBodyAssertion) {
        ""
    } else {
@'

  - Name: GetPingBodyMatchesReadmeSchema
    Assertion: ObjectOutputJsonSchema
    SessionNames:
      - GinReadPing
    DataSourceNames:
      - GinReadmePingResponseSchemas
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetPing
'@
    }
    $processComment = if ($EmbedProcessCommand) { "# go run main.go`n" } else { "" }

    $runnerPath = Join-Path $candidateDir "test.qaas.yaml"
    Write-TextFile -Path $runnerPath -Value @"
$processComment# Status: blocked_until_template_live_airgapped_validation
MetaData:
  Team: ZappaDontCry
  System: gin-gonic-gin

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetPingPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-ping.bin'
      StorageMetaData: ItemName

  - Name: GinReadmePingResponseSchemas
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './schemas'
        SearchPattern: 'ping-response.schema.json'
      StorageMetaData: ItemName

Sessions:
  - Name: GinReadPing
    Transactions:
      - Name: GetPing
        TimeoutMs: 5000
        DataSourceNames:
          - GetPingPayload
        DataSourcePatterns:
          - GetPingPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: $port
          Route: $route
          Method: Get
        OutputDeserialize:
          Deserializer: Json

Assertions:
  - Name: GetPingReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - GinReadPing
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetPing
$bodyAssertion
"@

    $appPath = Join-Path $appDir "main.go"
    Write-TextFile -Path $appPath -Value @'
package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	r.GET("/ping", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"message": "pong",
		})
	})

	if err := r.Run(); err != nil {
		log.Fatalf("failed to run server: %v", err)
	}
}
'@

    $schemaPath = Join-Path $schemasDir "ping-response.schema.json"
    $messageConst = if ($BodySchemaDrift) { "ping" } else { "pong" }
    Write-TextFile -Path $schemaPath -Value @"
{
  "`$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["message"],
  "additionalProperties": false,
  "properties": {
    "message": { "const": "$messageConst" }
  }
}
"@

    $requestPayloadPath = Join-Path $requestPayloadsDir "get-ping.bin"
    [System.IO.File]::WriteAllBytes($requestPayloadPath, [byte[]]::new(0))

    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $cleanupStatus = if ($LifecyclePassed) { "passed" } else { "not_validated" }
    $runtimeBlockers = @(
        "prove_process_lifecycle_and_cleanup_without assuming private source",
        "run_qaaS_template_validation",
        "run_live_qaaS_act_assert_validation",
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence"
    )
    if ($LifecyclePassed) {
        $runtimeBlockers = @($runtimeBlockers | Where-Object { $_ -ne "prove_process_lifecycle_and_cleanup_without assuming private source" })
    }
    $lifecycleValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "go run main.go ; GET http://127.0.0.1:8080/ping ; terminate tracked process tree"
        transcript = "gin-transcript"
        summary = "gin-summary"
        response = "gin-response"
        cleanup_process_ids = @(12345)
    }
    $runtimePlan = [ordered]@{
        schema_version = 1
        repository = "gin-gonic/gin"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        command = "go run main.go"
        working_directory = $appDir
        fixture = $appPath
        expected_listen_url = "http://127.0.0.1:8080"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:8080/ping"
            expected_status = 200
            expected_json = [ordered]@{ message = "pong" }
        }
        cleanup = [ordered]@{ required = $true; strategy = "terminate_tracked_process_tree"; status = $cleanupStatus }
        blockers = $runtimeBlockers
    }
    if ($LifecyclePassed) {
        $runtimePlan["cleanup"]["evidence"] = @("gin-summary", "gin-transcript")
        $runtimePlan["lifecycle_validation"] = $lifecycleValidation
    }
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

    $docsEvidence = @(
        "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md",
        "D:\QaaS\qaas-docs\docs\generators\availableGenerators\FromFileSystem\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\overview.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $sourceBlockers = @(
        [ordered]@{ blocker_id = "gin-process-lifecycle-not-proven"; blocker_type = "repository_contract"; description = "blocked"; required_evidence = @("lifecycle"); public_evidence = @($selectedRecordPath, $readmePath); unblock_instruction = "validate lifecycle" },
        [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = $docsEvidence; unblock_instruction = "run qaas" },
        [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @($readmePath); unblock_instruction = "run weak model" },
        [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = $docsEvidence; unblock_instruction = "use schema" }
    )
    if ($MissingLifecycleBlocker -or $LifecyclePassed) {
        $sourceBlockers = @($sourceBlockers | Where-Object { $_.blocker_id -ne "gin-process-lifecycle-not-proven" })
    }

    $lifecycleGateStatus = if ($LifecyclePassed) { "passed" } else { "blocked" }
    $lifecycleGateEvidence = if ($LifecyclePassed) { @("gin-summary", "gin-transcript", "gin-response") } else { @($selectedRecordPath, $readmePath) }
    $lifecycleGateBlockedReason = if ($LifecyclePassed) { "" } else { "blocked" }
    $lifecycleGate = if ($MissingLifecycleBlocker) {
        @()
    } else {
        @(
            [ordered]@{ gate_id = "go-version-and-module-resolution"; kind = "dependency"; required = $true; status = $lifecycleGateStatus; evidence = $lifecycleGateEvidence; check_command = ""; blocked_reason = $lifecycleGateBlockedReason },
            [ordered]@{ gate_id = "go-gin-process-lifecycle"; kind = "dependency"; required = $true; status = $lifecycleGateStatus; evidence = $lifecycleGateEvidence; check_command = ""; blocked_reason = $lifecycleGateBlockedReason }
        )
    }

    $cleanupGateStatus = if ($LifecyclePassed) { "passed" } else { "blocked" }
    $cleanupGateEvidence = if ($LifecyclePassed) { @("gin-summary", "gin-transcript", "gin-response") } else { @($selectedRecordPath, $readmePath) }
    $cleanupGateBlockedReason = if ($LifecyclePassed) { "" } else { "blocked" }
    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $artifacts = @($runnerPath, $appPath, $schemaPath, $requestPayloadPath, $runtimePlanPath, $manifestPath)
    $manifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-gin-candidate"
        source_repository = "gin-gonic/gin"
        repository_rank = 138
        selected_contract = $selectedRecordPath
        docs_evidence = $docsEvidence
        public_evidence = @($selectedRecordPath, $readmePath)
        artifacts = $artifacts
        artifact_count = $artifacts.Count
        airgapped_validation = [ordered]@{ required = $true; status = "not_run_for_this_candidate"; dry_run = $false }
        source_only_blockers = $sourceBlockers
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; kind = "runtime"; required = $true; status = "ready"; evidence = @($selectedRecordPath, $readmePath); check_command = ""; blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; kind = "runtime"; required = $true; status = "ready"; evidence = $docsEvidence; check_command = ""; blocked_reason = "" }
            $lifecycleGate
            [ordered]@{ gate_id = "cleanup-contract"; kind = "cleanup"; required = $true; status = $cleanupGateStatus; evidence = $cleanupGateEvidence; check_command = ""; blocked_reason = $cleanupGateBlockedReason },
            [ordered]@{ gate_id = "qaas-template"; kind = "qaas-template"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; kind = "qaas-build"; required = $true; status = "blocked"; evidence = $docsEvidence; check_command = ""; blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; kind = "airgapped"; required = $true; status = "blocked"; evidence = @(); check_command = ""; blocked_reason = "blocked" }
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
    }
    if ($LifecyclePassed) {
        $manifest["lifecycle_validation"] = $lifecycleValidation
    }
    Write-JsonFile -Path $manifestPath -Value $manifest

    Write-JsonFile -Path (Join-Path $candidateRoot "selected-candidate-index.json") -Value ([ordered]@{
        schema_version = 1
        selected_candidate_count = 1
        output_directory = $candidateRoot
        records = @(
            [ordered]@{
                rank = 138
                repository = "gin-gonic/gin"
                directory = $candidateDir
                manifest = $manifestPath
                selected_contract = $selectedRecordPath
                status = "candidate_packet_blocked_until_template_live_airgapped_validation"
                promotion_state = "blocked"
                artifact_count = $artifacts.Count
            }
        )
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        SelectedRoot = $selectedRoot
        CandidateDir = $candidateDir
    }
}

function Invoke-SelectedCandidateCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    $coverageDir = Join-Path $OutDir "$Name-coverage"
    if ($Fixture.PSObject.Properties.Name -contains "CoverageDir") {
        $coverageDir = $Fixture.CoverageDir
    }

    Invoke-CapturedCommand -Name $Name -FilePath "python" -Arguments @(
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidates.py"),
        $Fixture.CandidateRoot,
        $Fixture.SelectedRoot,
        $coverageDir
    )
}

function Invoke-SelectedCandidatePromotionReadinessCheck {
    param(
        [string]$Name,
        [object]$Fixture,
        [int]$ExpectedCount = 1,
        [int]$MinDeterministicReady = 0
    )

    $coverageDir = Join-Path $OutDir "$Name-coverage"
    Invoke-CapturedCommand -Name $Name -FilePath "python" -Arguments @(
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidatePromotionReadiness.py"),
        $Fixture.CandidateRoot,
        $coverageDir,
        [string]$ExpectedCount,
        [string]$MinDeterministicReady
    )
}

function Invoke-SelectedCandidateLiveCheck {
    param(
        [string]$Name,
        [string]$CandidateRoot,
        [string]$CandidateDir,
        [string]$SummaryPath,
        [string]$LiveRoot
    )

    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidateLive.ps1"),
        "-CandidateRoot",
        $CandidateRoot,
        "-CandidateDir",
        $CandidateDir,
        "-SummaryPath",
        $SummaryPath,
        "-LiveRoot",
        $LiveRoot
    )
}

function Invoke-FastApiSelectedCandidateLiveCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidateLiveFastApi.ps1"),
        "-CandidateRoot",
        $Fixture.CandidateRoot,
        "-CandidateDir",
        $Fixture.CandidateDir,
        "-SummaryPath",
        $Fixture.SummaryPath,
        "-LiveRoot",
        $Fixture.LiveRoot
    )
}

function Invoke-FlaskSelectedCandidateLiveCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidateLiveFlask.ps1"),
        "-CandidateRoot",
        $Fixture.CandidateRoot,
        "-CandidateDir",
        $Fixture.CandidateDir,
        "-SummaryPath",
        $Fixture.SummaryPath,
        "-LiveRoot",
        $Fixture.LiveRoot
    )
}

function Invoke-ExpressSelectedCandidateLiveCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidateLiveExpress.ps1"),
        "-CandidateRoot",
        $Fixture.CandidateRoot,
        "-CandidateDir",
        $Fixture.CandidateDir,
        "-SummaryPath",
        $Fixture.SummaryPath,
        "-LiveRoot",
        $Fixture.LiveRoot
    )
}

function Invoke-GinSelectedCandidateLiveCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidateLiveGin.ps1"),
        "-CandidateRoot",
        $Fixture.CandidateRoot,
        "-CandidateDir",
        $Fixture.CandidateDir,
        "-SummaryPath",
        $Fixture.SummaryPath,
        "-LiveRoot",
        $Fixture.LiveRoot
    )
}

function New-FastApiLiveFixture {
    param(
        [string]$Root,
        [switch]$FailedSummary,
        [switch]$StaleManifest,
        [switch]$WrongRepo,
        [switch]$WeakValidationPassed,
        [switch]$WrongBody,
        [switch]$MissingObjectSchemaMarker,
        [switch]$DoubleSlashUrl,
        [switch]$FakeHashes,
        [switch]$MixedManifestValidation
    )

    $candidateFixture = New-FastApiSelectedCandidateFixture -Root $Root -LifecyclePassed
    $candidateDir = $candidateFixture.CandidateDir
    $candidateRoot = $candidateFixture.CandidateRoot
    $coverageDir = $candidateFixture.CoverageDir
    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $sourceYamlPath = Join-Path $candidateDir "test.qaas.yaml"
    $sourceSchemaPath = Join-Path $candidateDir "schemas\item-response.schema.json"
    $sourcePayloadPath = Join-Path $candidateDir "request-payloads\get-items-5.bin"
    $sourceAppPath = Join-Path $candidateDir "app\main.py"

    $liveRoot = Join-Path $Root "live-runs\selected-top-repo-candidates"
    $runDir = Join-Path $liveRoot "20260608-000001-000"
    $evidenceDir = Join-Path $runDir "evidence"
    $runnerRoot = Join-Path $runDir "runner\ZappaSelectedFastApi.Runner"
    $stagedSchemaDir = Join-Path $runnerRoot "schemas"
    $stagedPayloadDir = Join-Path $runnerRoot "request-payloads"
    $fastApiWorkDir = Join-Path $runDir "fastapi-work"
    foreach ($dir in @($evidenceDir, $runnerRoot, $stagedSchemaDir, $stagedPayloadDir, $fastApiWorkDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $runnerProjectPath = Join-Path $runnerRoot "ZappaSelectedFastApi.Runner.csproj"
    $stagedYamlPath = Join-Path $runnerRoot "test.qaas.yaml"
    $stagedSchemaPath = Join-Path $stagedSchemaDir "item-response.schema.json"
    $stagedPayloadPath = Join-Path $stagedPayloadDir "get-items-5.bin"
    $stagedAppPath = Join-Path $fastApiWorkDir "main.py"
    Copy-Item -LiteralPath $sourceYamlPath -Destination $stagedYamlPath -Force
    Copy-Item -LiteralPath $sourceSchemaPath -Destination $stagedSchemaPath -Force
    Copy-Item -LiteralPath $sourcePayloadPath -Destination $stagedPayloadPath -Force
    Copy-Item -LiteralPath $sourceAppPath -Destination $stagedAppPath -Force
    Write-TextFile -Path $runnerProjectPath -Value "<Project Sdk=`"Microsoft.NET.Sdk`"></Project>"

    $buildTranscript = Join-Path $evidenceDir "build-runner.transcript.txt"
    $templateTranscript = Join-Path $evidenceDir "template-runner.transcript.txt"
    $liveTranscript = Join-Path $evidenceDir "live-runner-run.transcript.txt"
    $combinedTranscript = Join-Path $evidenceDir "selected-live-fastapi.transcript.txt"
    $responsePath = Join-Path $evidenceDir "items-5-response.json"
    $stdoutPath = Join-Path $evidenceDir "fastapi.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "fastapi.stderr.txt"
    $pipStdoutPath = Join-Path $evidenceDir "pip-install-fastapi-standard.stdout.txt"
    $pipStderrPath = Join-Path $evidenceDir "pip-install-fastapi-standard.stderr.txt"
    $venvStdoutPath = Join-Path $evidenceDir "python-venv.stdout.txt"
    $venvStderrPath = Join-Path $evidenceDir "python-venv.stderr.txt"
    $body = if ($WrongBody) { '{"item_id":5,"q":"drift"}' } else { '{"item_id":5,"q":"somequery"}' }
    Write-TextFile -Path $responsePath -Value $body
    Write-TextFile -Path $stdoutPath -Value "fastapi stdout"
    Write-TextFile -Path $stderrPath -Value "fastapi stderr"
    Write-TextFile -Path $pipStdoutPath -Value "Successfully installed fastapi"
    Write-TextFile -Path $pipStderrPath -Value ""
    Write-TextFile -Path $venvStdoutPath -Value ""
    Write-TextFile -Path $venvStderrPath -Value ""
    Write-TextFile -Path $buildTranscript -Value "Command: dotnet build`nExitCode: 0"
    Write-TextFile -Path $templateTranscript -Value "Command: dotnet run template`nFound IAssertion hook instance ObjectOutputJsonSchema`nRunner completed. ExitCode=0"

    $url = "http://127.0.0.1:8000/items/5?q=somequery"
    $doubleSlashLine = if ($DoubleSlashUrl) { "[00:00:00 INF] HTTP Get request to http://127.0.0.1:8000//items/5?q=somequery completed with status 200.`n" } else { "" }
    $schemaMarker = if ($MissingObjectSchemaMarker) { "" } else { "[00:00:00 INF] Running assertion ObjectOutputJsonSchema GetItemFiveBodyMatchesReadmeSchema`n" }
    Write-TextFile -Path $liveTranscript -Value @"
Command: dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env
ExitCode: 0
[00:00:00 INF] HTTP Get request to $url completed with status 200.
$doubleSlashLine[00:00:00 INF] Running assertion HttpStatus GetItemFiveReturnedOk
$schemaMarker[00:00:00 INF] Runner completed. ExitCode=0
"@
    Write-TextFile -Path $combinedTranscript -Value @"
Validation: selected-top-repo-candidate-live-fastapi
Repository: fastapi/fastapi
RunnerProject: $runnerProjectPath
RunnerYaml: $stagedYamlPath
FastApiCommand: fastapi dev
FastApiWorkDir: $fastApiWorkDir
ManagedVenvPath: $(Join-Path $runDir "venv")
InstallCommand: python -m pip install "fastapi[standard]"
FastApiModuleVersion: 0.136.3
UvicornModuleVersion: 0.49.0
Ready: True
ReadyStatus: HTTP 200 from /items/5?q=somequery with exact README-backed JSON body
ResponseStatus: 200
BuildPassed: True
TemplatePassed: True
LivePassed: True
CleanupPassed: True
CleanupProcessIds: 111,222
RemainingTrackedProcessIds:
PortOwnersAfterCleanupCount: 0
FailureReason:
ExitCode: 0
"@

    $hashes = [ordered]@{
        candidate_yaml_sha256 = Get-FileSha256Hex -Path $sourceYamlPath
        staged_yaml_sha256 = Get-FileSha256Hex -Path $stagedYamlPath
        candidate_schema_sha256 = Get-FileSha256Hex -Path $sourceSchemaPath
        staged_schema_sha256 = Get-FileSha256Hex -Path $stagedSchemaPath
        candidate_request_payload_sha256 = Get-FileSha256Hex -Path $sourcePayloadPath
        staged_request_payload_sha256 = Get-FileSha256Hex -Path $stagedPayloadPath
        candidate_app_sha256 = Get-FileSha256Hex -Path $sourceAppPath
        staged_app_sha256 = Get-FileSha256Hex -Path $stagedAppPath
    }
    if ($FakeHashes) {
        $hashes = [ordered]@{
            candidate_yaml_sha256 = "fake"
            staged_yaml_sha256 = "fake"
            candidate_schema_sha256 = "fake"
            staged_schema_sha256 = "fake"
            candidate_request_payload_sha256 = "fake"
            staged_request_payload_sha256 = "fake"
            candidate_app_sha256 = "fake"
            staged_app_sha256 = "fake"
        }
    }

    $buildValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet build $runnerProjectPath --nologo -clp:ErrorsOnly"; transcript = $buildTranscript }
    $templateValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- template $stagedYamlPath --no-env"; transcript = $templateTranscript }
    $liveValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env"; transcript = $liveTranscript }
    $summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-live-fastapi.json"
    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = if ($FailedSummary) { "failed" } else { "passed" }
        promotion_state = "blocked"
        completion_ready = $false
        repository = if ($WrongRepo) { "typicode/json-server" } else { "fastapi/fastapi" }
        validation_kind = "selected_candidate_qaas_template_live"
        run_dir = $runDir
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        runner_project = $runnerProjectPath
        runner_yaml = $stagedYamlPath
        source_runner_yaml = $sourceYamlPath
        schemas = $stagedSchemaDir
        source_hashes = $hashes
        fastapi_cli_path = Join-Path $runDir "venv\Scripts\fastapi.exe"
        fastapi_module_version = "0.136.3"
        uvicorn_module_version = "0.49.0"
        managed_venv_path = Join-Path $runDir "venv"
        install_command = 'python -m pip install "fastapi[standard]"'
        venv_python_path = Join-Path $runDir "venv\Scripts\python.exe"
        venv_create_stdout = $venvStdoutPath
        venv_create_stderr = $venvStderrPath
        pip_install_stdout = $pipStdoutPath
        pip_install_stderr = $pipStderrPath
        selected_readme_evidence = Join-Path (Split-Path -Parent (Split-Path -Parent $candidateFixture.SelectedRoot)) "selected-contracts\114-fastapi-fastapi\files\README.md"
        build_validation = $buildValidation
        template_validation = $templateValidation
        live_validation = $liveValidation
        response = $responsePath
        response_status = 200
        response_contract_passed = (-not [bool]$WrongBody)
        cleanup_passed = $true
        cleanup_process_ids = @(111, 222)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        transcript = $combinedTranscript
        fastapi_stdout = $stdoutPath
        fastapi_stderr = $stderrPath
        manifest_updated = (-not [bool]$StaleManifest)
        weak_validation_passed = [bool]$WeakValidationPassed
        failure_reason = if ($FailedSummary) { "fixture failure" } else { "" }
        exit_code = if ($FailedSummary) { 1 } else { 0 }
    })

    if (-not $StaleManifest) {
        $manifest = Read-JsonFile -Path $manifestPath
        Set-JsonProperty -Object $manifest -Name "build_validation" -Value $(if ($MixedManifestValidation) { [ordered]@{ status = "passed"; exit_code = 0; command = "wrong"; transcript = $buildTranscript } } else { $buildValidation })
        Set-JsonProperty -Object $manifest -Name "template_validation" -Value $templateValidation
        Set-JsonProperty -Object $manifest -Name "live_validation" -Value $liveValidation
        Set-JsonProperty -Object $manifest -Name "selected_candidate_qaas_validation" -Value ([ordered]@{
            status = "passed"
            exit_code = 0
            command = "dotnet run template ; fastapi dev ; dotnet run live"
            transcript = $combinedTranscript
            summary = $summaryPath
            response = $responsePath
            run_dir = $runDir
        })
        $manifest.source_only_blockers = @($manifest.source_only_blockers | Where-Object { $_.blocker_id -ne "qaas-template-live-not-run" })
        Move-HttpStatusDocsBlockerToAdvisory -Manifest $manifest -SummaryPath $summaryPath
        foreach ($gate in @($manifest.dependency_gates)) {
            if ($gate.gate_id -eq "qaas-template") {
                $gate.status = "passed"
                $gate.evidence = @($summaryPath, $templateTranscript)
                $gate.blocked_reason = ""
            }
            if ($gate.gate_id -eq "qaas-live-act-assert") {
                $gate.status = "passed"
                $gate.evidence = @($summaryPath, $liveTranscript, $responsePath)
                $gate.blocked_reason = ""
            }
        }
        Write-JsonFile -Path $manifestPath -Value $manifest

        $runtimePlan = Read-JsonFile -Path $runtimePlanPath
        Set-JsonProperty -Object $runtimePlan -Name "qaas_validation" -Value ([ordered]@{
            status = "passed"
            exit_code = 0
            command = "dotnet run template ; fastapi dev ; dotnet run live"
            transcript = $combinedTranscript
            summary = $summaryPath
            response = $responsePath
            run_dir = $runDir
        })
        $runtimePlan.blockers = @($runtimePlan.blockers | Where-Object { $_ -notin @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation") })
        Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan
    }

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        SelectedRoot = $candidateFixture.SelectedRoot
        CoverageDir = $coverageDir
        SummaryPath = $summaryPath
        LiveRoot = $liveRoot
    }
}

function New-GinLiveFixture {
    param(
        [string]$Root,
        [switch]$FailedSummary,
        [switch]$StaleManifest,
        [switch]$WrongRepo,
        [switch]$WeakValidationPassed,
        [switch]$WrongBody,
        [switch]$DoubleSlashUrl,
        [switch]$FakeHashes,
        [switch]$MixedManifestValidation,
        [switch]$WrongGoSource,
        [switch]$EnvMismatch
    )

    $candidateFixture = New-GinSelectedCandidateFixture -Root $Root -LifecyclePassed
    $candidateDir = $candidateFixture.CandidateDir
    $candidateRoot = $candidateFixture.CandidateRoot
    $coverageDir = Join-Path $Root "coverage"
    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $sourceYamlPath = Join-Path $candidateDir "test.qaas.yaml"
    $sourceSchemaPath = Join-Path $candidateDir "schemas\ping-response.schema.json"
    $sourcePayloadPath = Join-Path $candidateDir "request-payloads\get-ping.bin"
    $sourceAppPath = Join-Path $candidateDir "app\main.go"

    $liveRoot = Join-Path $Root "live-runs\selected-top-repo-candidates"
    $runDir = Join-Path $liveRoot "20260608-000003-000"
    $evidenceDir = Join-Path $runDir "evidence"
    $runnerRoot = Join-Path $runDir "runner\ZappaSelectedGin.Runner"
    $stagedSchemaDir = Join-Path $runnerRoot "schemas"
    $stagedPayloadDir = Join-Path $runnerRoot "request-payloads"
    $ginWorkDir = Join-Path $runDir "gin-work"
    $goEnvRoot = Join-Path $runDir "go-env"
    $managedGoPathDir = Join-Path $goEnvRoot "gopath"
    $managedGoModCache = Join-Path $goEnvRoot "gomodcache"
    $managedGoCache = Join-Path $goEnvRoot "gocache"
    foreach ($dir in @($coverageDir, $evidenceDir, $runnerRoot, $stagedSchemaDir, $stagedPayloadDir, $ginWorkDir, $managedGoPathDir, $managedGoModCache, $managedGoCache)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $runnerProjectPath = Join-Path $runnerRoot "ZappaSelectedGin.Runner.csproj"
    $stagedYamlPath = Join-Path $runnerRoot "test.qaas.yaml"
    $stagedSchemaPath = Join-Path $stagedSchemaDir "ping-response.schema.json"
    $stagedPayloadPath = Join-Path $stagedPayloadDir "get-ping.bin"
    $stagedAppPath = Join-Path $ginWorkDir "main.go"
    $stagedYamlText = (Get-Content -LiteralPath $sourceYamlPath -Raw) -replace '(?m)^(\s*)Route:\s*/ping\s*$', '${1}Route: ping'
    Write-TextFile -Path $stagedYamlPath -Value $stagedYamlText
    Copy-Item -LiteralPath $sourceSchemaPath -Destination $stagedSchemaPath -Force
    Copy-Item -LiteralPath $sourcePayloadPath -Destination $stagedPayloadPath -Force
    Copy-Item -LiteralPath $sourceAppPath -Destination $stagedAppPath -Force
    Write-TextFile -Path $runnerProjectPath -Value "<Project Sdk=`"Microsoft.NET.Sdk`"></Project>"

    $goVersion = "go version go1.26.4 windows/amd64"
    $goDownloadUrl = "https://go.dev/dl/go1.26.4.windows-amd64.zip"
    $goArchiveSha = "3ca8fb4630b07c419cbdd51f754e31363cfcfb83b3a5354d9e895c90be2cc345"
    $managedToolchainRoot = "D:\QaaS\_tmp\zappa-dont-cry\toolchains\go"
    $managedToolchainPath = Join-Path $managedToolchainRoot "go1.26.4-windows-amd64"
    $goRoot = Join-Path $managedToolchainPath "go"
    $goPath = Join-Path $goRoot "bin\go.exe"
    $goArchivePath = Join-Path $managedToolchainRoot "archives\go1.26.4.windows-amd64.zip"
    if (-not (Test-Path -LiteralPath $goArchivePath -PathType Leaf)) {
        throw "Official Go archive fixture missing: $goArchivePath. Run Gin lifecycle once before harness regression."
    }

    $goEnvJsonPath = Join-Path $evidenceDir "go-env.json"
    Write-JsonFile -Path $goEnvJsonPath -Value ([ordered]@{
        GOROOT = if ($EnvMismatch) { Join-Path $runDir "wrong-goroot" } else { $goRoot }
        GOPATH = $managedGoPathDir
        GOMODCACHE = $managedGoModCache
        GOCACHE = $managedGoCache
    })
    $goModPath = Join-Path $ginWorkDir "go.mod"
    $goSumPath = Join-Path $ginWorkDir "go.sum"
    $goListModulePath = Join-Path $evidenceDir "go-list-gin-module.json"
    Write-TextFile -Path $goModPath -Value "module zappa.local/gin-live`n`nrequire github.com/gin-gonic/gin v1.12.0`n"
    Write-TextFile -Path $goSumPath -Value "github.com/gin-gonic/gin v1.12.0 h1:fixture`n"
    Write-JsonFile -Path $goListModulePath -Value ([ordered]@{ Path = "github.com/gin-gonic/gin"; Version = "v1.12.0" })

    $buildTranscript = Join-Path $evidenceDir "build-runner.transcript.txt"
    $templateTranscript = Join-Path $evidenceDir "template-runner.transcript.txt"
    $liveTranscript = Join-Path $evidenceDir "live-runner-run.transcript.txt"
    $combinedTranscript = Join-Path $evidenceDir "selected-live-gin.transcript.txt"
    $responsePath = Join-Path $evidenceDir "ping-response.json"
    $stdoutPath = Join-Path $evidenceDir "gin.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "gin.stderr.txt"
    $body = if ($WrongBody) { '{"message":"drift"}' } else { '{"message":"pong"}' }
    Write-TextFile -Path $responsePath -Value $body
    Write-TextFile -Path $stdoutPath -Value "gin stdout"
    Write-TextFile -Path $stderrPath -Value "gin stderr"
    Write-TextFile -Path $buildTranscript -Value "Command: dotnet build`nExitCode: 0"
    Write-TextFile -Path $templateTranscript -Value @"
Command: dotnet run template
ExitCode: 0
Found IAssertion hook instance HttpStatus
Found IAssertion hook instance ObjectOutputJsonSchema
Route: ping
Runner completed. ExitCode=0
"@

    $doubleSlashLine = if ($DoubleSlashUrl) { "[00:00:00 INF] HTTP Get request to http://127.0.0.1:8080//ping completed with status 200.`n" } else { "" }
    Write-TextFile -Path $liveTranscript -Value @"
Command: dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env
ExitCode: 0
[00:00:00 INF] HTTP Get request to http://127.0.0.1:8080/ping completed with status 200.
$doubleSlashLine[00:00:00 INF] Running assertion ObjectOutputJsonSchema GetPingBodyMatchesReadmeSchema
[00:00:00 INF] Running assertion HttpStatus GetPingReturnedOk
[00:00:00 INF] Runner completed. ExitCode=0
"@
    Write-TextFile -Path $combinedTranscript -Value @"
Validation: selected-top-repo-candidate-live-gin
Repository: gin-gonic/gin
RunnerProject: $runnerProjectPath
RunnerYaml: $stagedYamlPath
GinCommand: go run -mod=readonly main.go
GinWorkDir: $ginWorkDir
GoSource: managed_go_toolchain
GoPath: $goPath
GoVersion: $goVersion
ManagedGoDownloadUrl: $goDownloadUrl
ManagedGoArchiveSha256: $goArchiveSha
ModulePinCommand: go get github.com/gin-gonic/gin@v1.12.0
ModuleDownloadCommand: go mod download
ModuleListCommand: go list -m -json github.com/gin-gonic/gin
ModuleResolutionPassed: True
Ready: True
ReadyStatus: HTTP 200 from /ping with exact README-backed JSON body
ResponseStatus: 200
BuildPassed: True
TemplatePassed: True
LivePassed: True
CleanupPassed: True
CleanupProcessIds: 111,222
RemainingTrackedProcessIds:
PortOwnersAfterCleanupCount: 0
FailureReason:
ExitCode: 0
"@

    $hashes = [ordered]@{
        candidate_yaml_sha256 = Get-FileSha256Hex -Path $sourceYamlPath
        staged_yaml_sha256 = Get-FileSha256Hex -Path $stagedYamlPath
        candidate_schema_sha256 = Get-FileSha256Hex -Path $sourceSchemaPath
        staged_schema_sha256 = Get-FileSha256Hex -Path $stagedSchemaPath
        candidate_request_payload_sha256 = Get-FileSha256Hex -Path $sourcePayloadPath
        staged_request_payload_sha256 = Get-FileSha256Hex -Path $stagedPayloadPath
        candidate_app_sha256 = Get-FileSha256Hex -Path $sourceAppPath
        staged_app_sha256 = Get-FileSha256Hex -Path $stagedAppPath
    }
    if ($FakeHashes) {
        $hashes = [ordered]@{
            candidate_yaml_sha256 = "fake"
            staged_yaml_sha256 = "fake"
            candidate_schema_sha256 = "fake"
            staged_schema_sha256 = "fake"
            candidate_request_payload_sha256 = "fake"
            staged_request_payload_sha256 = "fake"
            candidate_app_sha256 = "fake"
            staged_app_sha256 = "fake"
        }
    }

    $buildValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet build $runnerProjectPath --nologo -clp:ErrorsOnly"; transcript = $buildTranscript }
    $templateValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- template $stagedYamlPath --no-env"; transcript = $templateTranscript }
    $liveValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env"; transcript = $liveTranscript }
    $summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-live-gin.json"
    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = if ($FailedSummary) { "failed" } else { "passed" }
        promotion_state = "blocked"
        completion_ready = $false
        repository = if ($WrongRepo) { "fastapi/fastapi" } else { "gin-gonic/gin" }
        validation_kind = "selected_candidate_qaas_template_live"
        command = "dotnet run --project $runnerProjectPath -- template $stagedYamlPath --no-env ; go run -mod=readonly main.go ; dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env"
        module_init_command = "go mod init zappa.local/gin-live"
        module_pin_command = "go get github.com/gin-gonic/gin@v1.12.0"
        module_download_command = "go mod download"
        module_list_command = "go list -m -json github.com/gin-gonic/gin"
        module_pin = "github.com/gin-gonic/gin@v1.12.0"
        run_dir = $runDir
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        runner_project = $runnerProjectPath
        runner_yaml = $stagedYamlPath
        source_runner_yaml = $sourceYamlPath
        schemas = $stagedSchemaDir
        source_hashes = $hashes
        go_source = if ($WrongGoSource) { "global_path" } else { "managed_go_toolchain" }
        go_path = $goPath
        go_version = $goVersion
        go_root = $goRoot
        go_env_json = $goEnvJsonPath
        managed_gopath = $managedGoPathDir
        managed_gomodcache = $managedGoModCache
        managed_gocache = $managedGoCache
        managed_toolchain_root = $managedToolchainRoot
        managed_toolchain_path = $managedToolchainPath
        managed_toolchain_archive = $goArchivePath
        managed_toolchain_archive_sha256 = $goArchiveSha
        managed_toolchain_download_url = $goDownloadUrl
        managed_toolchain_downloaded = $false
        module_resolution_passed = $true
        go_mod_path = $goModPath
        go_mod_sha256 = Get-FileSha256Hex -Path $goModPath
        go_sum_path = $goSumPath
        go_sum_sha256 = Get-FileSha256Hex -Path $goSumPath
        go_list_module_json = $goListModulePath
        working_directory = $ginWorkDir
        candidate_app_sha256 = Get-FileSha256Hex -Path $sourceAppPath
        staged_app_sha256 = Get-FileSha256Hex -Path $stagedAppPath
        selected_readme_evidence = Join-Path $candidateFixture.SelectedRoot "138-gin-gonic-gin\files\README.md"
        selected_go_mod_evidence = Join-Path $candidateFixture.SelectedRoot "138-gin-gonic-gin\files\go.mod"
        build_validation = $buildValidation
        template_validation = $templateValidation
        live_validation = $liveValidation
        transcript = $combinedTranscript
        stdout = $stdoutPath
        stderr = $stderrPath
        gin_stdout = $stdoutPath
        gin_stderr = $stderrPath
        response = $responsePath
        response_status = 200
        response_body_sha256 = Get-FileSha256Hex -Path $responsePath
        response_contract_passed = $true
        cleanup_passed = $true
        cleanup_process_ids = @(111, 222)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        exit_code = if ($FailedSummary) { 1 } else { 0 }
        manifest_updated = (-not [bool]$StaleManifest)
        weak_validation_passed = [bool]$WeakValidationPassed
        failure_reason = if ($FailedSummary) { "fixture failure" } else { "" }
    })

    if (-not $StaleManifest) {
        $manifest = Read-JsonFile -Path $manifestPath
        Set-JsonProperty -Object $manifest -Name "build_validation" -Value $(if ($MixedManifestValidation) { [ordered]@{ status = "passed"; exit_code = 0; command = "wrong"; transcript = $buildTranscript } } else { $buildValidation })
        Set-JsonProperty -Object $manifest -Name "template_validation" -Value $templateValidation
        Set-JsonProperty -Object $manifest -Name "live_validation" -Value $liveValidation
        Set-JsonProperty -Object $manifest -Name "selected_candidate_qaas_validation" -Value ([ordered]@{
            status = "passed"
            exit_code = 0
            command = "dotnet run template ; go run -mod=readonly main.go ; dotnet run live"
            transcript = $combinedTranscript
            summary = $summaryPath
            response = $responsePath
            run_dir = $runDir
        })
        $manifest.source_only_blockers = @($manifest.source_only_blockers | Where-Object { $_.blocker_id -ne "qaas-template-live-not-run" })
        Move-HttpStatusDocsBlockerToAdvisory -Manifest $manifest -SummaryPath $summaryPath
        foreach ($gate in @($manifest.dependency_gates)) {
            if ($gate.gate_id -eq "qaas-template") {
                $gate.status = "passed"
                $gate.evidence = @($summaryPath, $templateTranscript)
                $gate.blocked_reason = ""
            }
            if ($gate.gate_id -eq "qaas-live-act-assert") {
                $gate.status = "passed"
                $gate.evidence = @($summaryPath, $liveTranscript, $responsePath)
                $gate.blocked_reason = ""
            }
        }
        Write-JsonFile -Path $manifestPath -Value $manifest

        $runtimePlan = Read-JsonFile -Path $runtimePlanPath
        Set-JsonProperty -Object $runtimePlan -Name "qaas_validation" -Value ([ordered]@{
            status = "passed"
            exit_code = 0
            command = "dotnet run template ; go run -mod=readonly main.go ; dotnet run live"
            transcript = $combinedTranscript
            summary = $summaryPath
            response = $responsePath
            run_dir = $runDir
        })
        $runtimePlan.blockers = @($runtimePlan.blockers | Where-Object { $_ -notin @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation") })
        Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan
    }

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        SelectedRoot = $candidateFixture.SelectedRoot
        CoverageDir = $coverageDir
        SummaryPath = $summaryPath
        LiveRoot = $liveRoot
    }
}

function New-FlaskLiveFixture {
    param(
        [string]$Root,
        [switch]$FailedSummary,
        [switch]$StaleManifest,
        [switch]$WrongRepo,
        [switch]$WeakValidationPassed,
        [switch]$WrongBody,
        [switch]$MissingExactMarker,
        [switch]$DoubleSlashUrl,
        [switch]$FakeHashes,
        [switch]$MixedManifestValidation,
        [switch]$MissingRouteEmpty,
        [switch]$SourceActiveCustomAssertion,
        [switch]$RuntimeHookMismatch,
        [switch]$SkipLifecycleAdoption
    )

    $candidateFixture = New-FlaskSelectedCandidateFixture -Root $Root -UseActiveCustomAssertion:$SourceActiveCustomAssertion
    $candidateDir = $candidateFixture.CandidateDir
    $candidateRoot = $candidateFixture.CandidateRoot
    $coverageDir = Join-Path $Root "coverage"
    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $sourceYamlPath = Join-Path $candidateDir "test.qaas.yaml"
    $sourcePayloadPath = Join-Path $candidateDir "request-payloads\get-root.bin"
    $sourceAppPath = Join-Path $candidateDir "app\app.py"
    $sourceBodyPath = Join-Path $candidateDir "expectations\root-body.txt"
    $sourceAssertionPath = Join-Path $candidateDir "assertion-packets\ExactHttpTextBody\ExactHttpTextBody.cs"

    $liveRoot = Join-Path $Root "live-runs\selected-top-repo-candidates"
    $runDir = Join-Path $liveRoot "20260608-000002-000"
    $evidenceDir = Join-Path $runDir "evidence"
    $runnerRoot = Join-Path $runDir "runner\ZappaSelectedFlask.Runner"
    $assertionRoot = Join-Path $runDir "assertions\ZappaSelectedFlask.Assertions"
    $stagedPayloadDir = Join-Path $runnerRoot "request-payloads"
    $stagedExpectationsDir = Join-Path $runnerRoot "expectations"
    $flaskWorkDir = Join-Path $runDir "flask-work"
    $venvScriptsDir = Join-Path $runDir "venv\Scripts"
    foreach ($dir in @($evidenceDir, $runnerRoot, $assertionRoot, $stagedPayloadDir, $stagedExpectationsDir, $flaskWorkDir, $venvScriptsDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $runnerProjectPath = Join-Path $runnerRoot "ZappaSelectedFlask.Runner.csproj"
    $runnerProgramPath = Join-Path $runnerRoot "Program.cs"
    $stagedYamlPath = Join-Path $runnerRoot "test.qaas.yaml"
    $stagedPayloadPath = Join-Path $stagedPayloadDir "get-root.bin"
    $stagedBodyPath = Join-Path $stagedExpectationsDir "root-body.txt"
    $stagedAppPath = Join-Path $flaskWorkDir "app.py"
    $assertionProjectPath = Join-Path $assertionRoot "ZappaSelectedFlask.Assertions.csproj"
    $stagedAssertionPath = Join-Path $assertionRoot "ExactHttpTextBody.cs"
    Copy-Item -LiteralPath $sourcePayloadPath -Destination $stagedPayloadPath -Force
    Copy-Item -LiteralPath $sourceBodyPath -Destination $stagedBodyPath -Force
    Copy-Item -LiteralPath $sourceAppPath -Destination $stagedAppPath -Force
    Copy-Item -LiteralPath $sourceAssertionPath -Destination $stagedAssertionPath -Force

    $stagedYamlText = Get-Content -LiteralPath $sourceYamlPath -Raw
    if (-not $MissingRouteEmpty) {
        $stagedYamlText = $stagedYamlText.Replace("          Route: /", "          Route: ''")
    }
    $stagedYamlText = "$stagedYamlText
  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - FlaskReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello, World!
      EncodingName: utf-8
"
    Write-TextFile -Path $stagedYamlPath -Value $stagedYamlText
    Write-TextFile -Path $runnerProgramPath -Value @'
using ZappaDontCry.SelectedCandidates.Flask.Assertions;

System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Flask.Assertions.ExactHttpTextBody));
Directory.SetCurrentDirectory(AppContext.BaseDirectory);
QaaS.Runner.Bootstrap.New(args).Run();
'@
    Write-TextFile -Path $runnerProjectPath -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="$assertionProjectPath" />
  </ItemGroup>
</Project>
"@
    Write-TextFile -Path $assertionProjectPath -Value @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="QaaS.Framework.SDK" Version="1.5.1" />
  </ItemGroup>
</Project>
'@

    $assertionBuildTranscript = Join-Path $evidenceDir "build-assertion-library.transcript.txt"
    $buildTranscript = Join-Path $evidenceDir "build-runner.transcript.txt"
    $templateTranscript = Join-Path $evidenceDir "template-runner.transcript.txt"
    $liveTranscript = Join-Path $evidenceDir "live-runner-run.transcript.txt"
    $combinedTranscript = Join-Path $evidenceDir "selected-live-flask.transcript.txt"
    $referenceTranscript = Join-Path $evidenceDir "reference-runner-assertion-project.transcript.txt"
    $responsePath = Join-Path $evidenceDir "root-response.txt"
    $stdoutPath = Join-Path $evidenceDir "flask.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "flask.stderr.txt"
    $pipStdoutPath = Join-Path $evidenceDir "pip-install-flask.stdout.txt"
    $pipStderrPath = Join-Path $evidenceDir "pip-install-flask.stderr.txt"
    $venvStdoutPath = Join-Path $evidenceDir "python-venv.stdout.txt"
    $venvStderrPath = Join-Path $evidenceDir "python-venv.stderr.txt"
    $flaskCliPath = Join-Path $venvScriptsDir "flask.exe"
    $venvPythonPath = Join-Path $venvScriptsDir "python.exe"
    Write-TextFile -Path $responsePath -Value $(if ($WrongBody) { "Hello, world!" } else { "Hello, World!" })
    Write-TextFile -Path $stdoutPath -Value "flask stdout"
    Write-TextFile -Path $stderrPath -Value "flask stderr"
    Write-TextFile -Path $pipStdoutPath -Value "Successfully installed Flask"
    Write-TextFile -Path $pipStderrPath -Value ""
    Write-TextFile -Path $venvStdoutPath -Value "created venv"
    Write-TextFile -Path $venvStderrPath -Value ""
    Write-TextFile -Path $flaskCliPath -Value "fixture flask exe"
    Write-TextFile -Path $venvPythonPath -Value "fixture python exe"
    Write-TextFile -Path $referenceTranscript -Value "Project reference added to $assertionProjectPath"
    Write-TextFile -Path $assertionBuildTranscript -Value "Command: dotnet build`nExitCode: 0"
    Write-TextFile -Path $buildTranscript -Value "Command: dotnet build`nExitCode: 0"

    $exactTemplateMarker = if ($MissingExactMarker) { "" } else { "Found IAssertion hook instance ExactHttpTextBody`n" }
    Write-TextFile -Path $templateTranscript -Value @"
Command: dotnet run --project $runnerProjectPath -- template $stagedYamlPath --no-env
ExitCode: 0
$($exactTemplateMarker)Assertion: ExactHttpTextBody
Runner completed. ExitCode=0
"@
    $exactLiveMarker = if ($MissingExactMarker) { "" } else { "[00:00:00 INF] Found IAssertion hook instance ExactHttpTextBody`n" }
    $doubleSlashLine = if ($DoubleSlashUrl) { "[00:00:00 INF] HTTP Get request to http://127.0.0.1:5000// completed with status 200.`n" } else { "" }
    Write-TextFile -Path $liveTranscript -Value @"
Command: dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env
ExitCode: 0
$($exactLiveMarker)[00:00:00 INF] HTTP Get request to http://127.0.0.1:5000/ completed with status 200.
$($doubleSlashLine)[00:00:00 INF] Running assertion ExactHttpTextBody GetRootBodyMatchesReadme
[00:00:00 INF] Running assertion HttpStatus GetRootReturnedOk
[00:00:00 INF] Runner completed. ExitCode=0
"@
    Write-TextFile -Path $combinedTranscript -Value @"
Validation: selected-top-repo-candidate-live-flask
Repository: pallets/flask
RunnerProject: $runnerProjectPath
RunnerYaml: $stagedYamlPath
AssertionProject: $assertionProjectPath
AssertionProjectReferenceAdded: True
FlaskCommand: flask run --no-reload --host 127.0.0.1 --port 5000
FlaskWorkDir: $flaskWorkDir
ManagedVenvPath: $(Join-Path $runDir "venv")
InstallCommand: python -m pip install Flask
FlaskVersion: 3.1.3
Ready: True
ReadyStatus: HTTP 200 from / with exact README-backed text body
ResponseStatus: 200
AssertionBuildPassed: True
BuildPassed: True
TemplatePassed: True
LivePassed: True
CleanupPassed: True
CleanupProcessIds: 111,222
RemainingTrackedProcessIds:
PortOwnersAfterCleanupCount: 0
FailureReason:
ExitCode: 0
"@

    $hashes = [ordered]@{
        candidate_yaml_sha256 = Get-FileSha256Hex -Path $sourceYamlPath
        staged_yaml_sha256 = Get-FileSha256Hex -Path $stagedYamlPath
        candidate_request_payload_sha256 = Get-FileSha256Hex -Path $sourcePayloadPath
        staged_request_payload_sha256 = Get-FileSha256Hex -Path $stagedPayloadPath
        candidate_app_sha256 = Get-FileSha256Hex -Path $sourceAppPath
        staged_app_sha256 = Get-FileSha256Hex -Path $stagedAppPath
        candidate_expected_body_sha256 = Get-FileSha256Hex -Path $sourceBodyPath
        staged_expected_body_sha256 = Get-FileSha256Hex -Path $stagedBodyPath
        candidate_assertion_sha256 = Get-FileSha256Hex -Path $sourceAssertionPath
        staged_assertion_sha256 = Get-FileSha256Hex -Path $stagedAssertionPath
    }
    if ($FakeHashes) {
        $hashes = [ordered]@{
            candidate_yaml_sha256 = "fake"
            staged_yaml_sha256 = "fake"
            candidate_request_payload_sha256 = "fake"
            staged_request_payload_sha256 = "fake"
            candidate_app_sha256 = "fake"
            staged_app_sha256 = "fake"
            candidate_expected_body_sha256 = "fake"
            staged_expected_body_sha256 = "fake"
            candidate_assertion_sha256 = "fake"
            staged_assertion_sha256 = "fake"
        }
    }

    $assertionBuildValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet build $assertionProjectPath --nologo -clp:ErrorsOnly"; transcript = $assertionBuildTranscript }
    $buildValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet build $runnerProjectPath --nologo -clp:ErrorsOnly"; transcript = $buildTranscript }
    $templateValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- template $stagedYamlPath --no-env"; transcript = $templateTranscript }
    $liveValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env"; transcript = $liveTranscript }
    $summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-live-flask.json"
    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = if ($FailedSummary) { "failed" } else { "passed" }
        promotion_state = "blocked"
        completion_ready = $false
        repository = if ($WrongRepo) { "fastapi/fastapi" } else { "pallets/flask" }
        validation_kind = "selected_candidate_qaas_template_live"
        run_dir = $runDir
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        runner_project = $runnerProjectPath
        runner_program = $runnerProgramPath
        runner_yaml = $stagedYamlPath
        source_runner_yaml = $sourceYamlPath
        assertion_project = $assertionProjectPath
        assertion_source = $stagedAssertionPath
        source_assertion = $sourceAssertionPath
        assertion_project_reference_transcript = $referenceTranscript
        assertion_project_reference_added = $true
        source_hashes = $hashes
        flask_cli_path = $flaskCliPath
        flask_version = "3.1.3"
        managed_venv_path = Join-Path $runDir "venv"
        install_command = "python -m pip install Flask"
        venv_python_path = $venvPythonPath
        venv_create_stdout = $venvStdoutPath
        venv_create_stderr = $venvStderrPath
        venv_ensurepip_retry_stdout = $null
        venv_ensurepip_retry_stderr = $null
        pip_install_stdout = $pipStdoutPath
        pip_install_stderr = $pipStderrPath
        selected_readme_evidence = Join-Path $candidateFixture.SelectedRoot "227-pallets-flask\files\README.md"
        selected_pyproject_evidence = Join-Path $candidateFixture.SelectedRoot "227-pallets-flask\files\pyproject.toml"
        assertion_build_validation = $assertionBuildValidation
        build_validation = $buildValidation
        template_validation = $templateValidation
        live_validation = $liveValidation
        response = $responsePath
        response_status = 200
        response_body_sha256 = Get-FileSha256Hex -Path $responsePath
        response_contract_passed = (-not [bool]$WrongBody)
        cleanup_passed = $true
        cleanup_process_ids = @(111, 222)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        transcript = $combinedTranscript
        flask_stdout = $stdoutPath
        flask_stderr = $stderrPath
        manifest_updated = (-not [bool]$StaleManifest)
        weak_validation_passed = [bool]$WeakValidationPassed
        failure_reason = if ($FailedSummary) { "fixture failure" } else { "" }
        exit_code = if ($FailedSummary) { 1 } else { 0 }
    })

    if (-not $StaleManifest) {
        $qaasValidation = [ordered]@{
            status = "passed"
            exit_code = 0
            command = "dotnet build $assertionProjectPath ; dotnet run template ; flask run ; dotnet run live"
            transcript = $combinedTranscript
            summary = $summaryPath
            response = $responsePath
            run_dir = $runDir
        }
        $manifest = Read-JsonFile -Path $manifestPath
        if (-not $SkipLifecycleAdoption) {
            $lifecycleRoot = Join-Path $Root "lifecycle-runs\selected-top-repo-candidates"
            $lifecycleRunDir = Join-Path $lifecycleRoot "20260608-000001-000"
            $lifecycleEvidenceDir = Join-Path $lifecycleRunDir "evidence"
            [System.IO.Directory]::CreateDirectory($lifecycleEvidenceDir) | Out-Null
            $lifecycleTranscript = Join-Path $lifecycleEvidenceDir "flask-lifecycle.transcript.txt"
            $lifecycleResponse = Join-Path $lifecycleEvidenceDir "root-response.txt"
            $lifecycleSummary = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-flask.json"
            Write-TextFile -Path $lifecycleTranscript -Value "Command: flask run --no-reload --host 127.0.0.1 --port 5000`nReady: True`nCleanupPassed: True`nExitCode: 0`nResponseBodySha256:"
            Write-TextFile -Path $lifecycleResponse -Value "Hello, World!"
            $lifecycleValidation = [ordered]@{
                status = "passed"
                exit_code = 0
                command = "flask run ; GET http://127.0.0.1:5000/ ; terminate tracked process tree"
                transcript = $lifecycleTranscript
                summary = $lifecycleSummary
                response = $lifecycleResponse
                cleanup_process_ids = @(333)
            }
            Write-JsonFile -Path $lifecycleSummary -Value ([ordered]@{
                schema_version = 1
                status = "passed"
                promotion_state = "blocked"
                completion_ready = $false
                repository = "pallets/flask"
                validation_kind = "selected_candidate_process_lifecycle"
                command = "flask run --no-reload --host 127.0.0.1 --port 5000"
                transcript = $lifecycleTranscript
                response = $lifecycleResponse
                response_status = 200
                response_contract_passed = $true
                cleanup_passed = $true
                cleanup_process_ids = @(333)
                remaining_tracked_process_ids = @()
                port_owners_after_cleanup_count = 0
                manifest = $manifestPath
                runtime_plan = $runtimePlanPath
                run_dir = $lifecycleRunDir
                exit_code = 0
                failure_reason = ""
                weak_validation_passed = $false
            })
            Set-JsonProperty -Object $manifest -Name "lifecycle_validation" -Value $lifecycleValidation
            $manifest.source_only_blockers = @($manifest.source_only_blockers | Where-Object { $_.blocker_id -ne "flask-process-lifecycle-not-proven" })
            foreach ($gate in @($manifest.dependency_gates)) {
                if ($gate.gate_id -in @("python-flask-process-lifecycle", "cleanup-contract")) {
                    $gate.status = "passed"
                    $gate.evidence = @($lifecycleSummary, $lifecycleTranscript)
                    $gate.blocked_reason = ""
                }
            }
        }
        Set-JsonProperty -Object $manifest -Name "assertion_build_validation" -Value $(if ($MixedManifestValidation) { [ordered]@{ status = "passed"; exit_code = 0; command = "wrong"; transcript = $assertionBuildTranscript } } else { $assertionBuildValidation })
        Set-JsonProperty -Object $manifest -Name "build_validation" -Value $buildValidation
        Set-JsonProperty -Object $manifest -Name "template_validation" -Value $templateValidation
        Set-JsonProperty -Object $manifest -Name "live_validation" -Value $liveValidation
        Set-JsonProperty -Object $manifest -Name "selected_candidate_qaas_validation" -Value $qaasValidation
        $manifest.custom_text_body_assertion.status = "build_template_live_validated"
        $manifest.custom_text_body_assertion.validation_status = "build_template_live_validated"
        foreach ($packet in @($manifest.custom_assertion_packets)) {
            if ($packet.assertion_name -eq "ExactHttpTextBody") {
                $packet.status = "build_template_live_validated_blocked_until_airgapped"
                $packet.activation = "staged_live_runner_only"
                $packet.wired_into_runner_yaml = $true
                $packet.validation_records.build = "passed"
                $packet.validation_records.schema = "passed"
                $packet.validation_records.template = "passed"
                $packet.validation_records.live = "passed"
            }
        }
        $manifest.source_only_blockers = @($manifest.source_only_blockers | Where-Object { $_.blocker_id -notin @("flask-text-body-hook-not-template-validated", "qaas-template-live-not-run") })
        Move-HttpStatusDocsBlockerToAdvisory -Manifest $manifest -SummaryPath $summaryPath
        foreach ($gate in @($manifest.dependency_gates)) {
            if ($gate.gate_id -eq "plain-text-body-assertion-or-hook") {
                $gate.status = "passed"
                $gate.evidence = @($summaryPath, $assertionBuildTranscript, $liveTranscript)
                $gate.blocked_reason = ""
            }
            if ($gate.gate_id -eq "qaas-template") {
                $gate.status = "passed"
                $gate.evidence = @($summaryPath, $templateTranscript)
                $gate.blocked_reason = ""
            }
            if ($gate.gate_id -eq "qaas-live-act-assert") {
                $gate.status = "passed"
                $gate.evidence = @($summaryPath, $liveTranscript, $responsePath)
                $gate.blocked_reason = ""
            }
        }
        Write-JsonFile -Path $manifestPath -Value $manifest

        $runtimePlan = Read-JsonFile -Path $runtimePlanPath
        if (-not $SkipLifecycleAdoption) {
            Set-JsonProperty -Object $runtimePlan -Name "lifecycle_validation" -Value $lifecycleValidation
            $runtimePlan.cleanup.status = "passed"
            Set-JsonProperty -Object $runtimePlan.cleanup -Name "evidence" -Value @($lifecycleSummary, $lifecycleTranscript)
        }
        Set-JsonProperty -Object $runtimePlan -Name "qaas_validation" -Value $qaasValidation
        $runtimePlan.custom_text_body_assertion.status = $(if ($RuntimeHookMismatch) { "authored_from_public_docs_not_template_validated" } else { "build_template_live_validated" })
        $runtimePlan.custom_text_body_assertion.validation_status = $(if ($RuntimeHookMismatch) { "not_template_validated" } else { "build_template_live_validated" })
        foreach ($packet in @($runtimePlan.custom_assertion_packets)) {
            if ($packet.assertion_name -eq "ExactHttpTextBody") {
                $packet.status = "build_template_live_validated_blocked_until_airgapped"
                $packet.activation = "staged_live_runner_only"
                $packet.wired_into_runner_yaml = $true
                $packet.validation_records.build = "passed"
                $packet.validation_records.schema = "passed"
                $packet.validation_records.template = "passed"
                $packet.validation_records.live = "passed"
            }
        }
        $runtimePlan.blockers = @($runtimePlan.blockers | Where-Object { $_ -notin @("validate_exact_text_body_custom_assertion_schema_template_and_live", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation", "prove_process_lifecycle_and_cleanup_without assuming private source") })
        if ($SkipLifecycleAdoption) {
            $runtimePlan.blockers += "prove_process_lifecycle_and_cleanup_without assuming private source"
        }
        Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan
    }

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        SelectedRoot = $candidateFixture.SelectedRoot
        CoverageDir = $coverageDir
        SummaryPath = $summaryPath
        LiveRoot = $liveRoot
    }
}

function New-ExpressLiveFixture {
    param(
        [string]$Root,
        [switch]$FailedSummary,
        [switch]$WeakValidationPassed,
        [switch]$SourceActiveCustomAssertion,
        [switch]$DoubleSlashUrl,
        [switch]$MissingPackageEvidence,
        [switch]$FakeHashes,
        [switch]$WrongBody
    )

    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $candidateDir = Join-Path $candidateRoot "243-expressjs-express"
    $coverageDir = Join-Path $Root "coverage"
    $selectedDir = Join-Path $Root "top-repos\selected-contracts\243-expressjs-express"
    $selectedFilesDir = Join-Path $selectedDir "files"
    $appDir = Join-Path $candidateDir "app"
    $expectationsDir = Join-Path $candidateDir "expectations"
    $requestPayloadsDir = Join-Path $candidateDir "request-payloads"
    $assertionDir = Join-Path $candidateDir "assertion-packets\ExactHttpTextBody"
    $liveRoot = Join-Path $Root "live-runs\selected-top-repo-candidates"
    $runDir = Join-Path $liveRoot "20260608-000003-000"
    $evidenceDir = Join-Path $runDir "evidence"
    $runnerRoot = Join-Path $runDir "runner\ZappaSelectedExpress.Runner"
    $assertionRoot = Join-Path $runDir "assertions\ZappaSelectedExpress.Assertions"
    $stagedPayloadDir = Join-Path $runnerRoot "request-payloads"
    $stagedExpectationsDir = Join-Path $runnerRoot "expectations"
    $expressWorkDir = Join-Path $runDir "express-work"
    $installedPackageDir = Join-Path $expressWorkDir "node_modules\express"
    foreach ($dir in @($coverageDir, $selectedFilesDir, $appDir, $expectationsDir, $requestPayloadsDir, $assertionDir, $evidenceDir, $runnerRoot, $assertionRoot, $stagedPayloadDir, $stagedExpectationsDir, $expressWorkDir, $installedPackageDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $selectedReadmePath = Join-Path $selectedFilesDir "Readme.md"
    $selectedPackagePath = Join-Path $selectedFilesDir "package.json"
    $selectedExamplePath = Join-Path $selectedFilesDir "examples\hello-world\index.js"
    $selectedAcceptancePath = Join-Path $selectedFilesDir "test\acceptance\hello-world.js"
    Write-TextFile -Path $selectedReadmePath -Value @'
import express from 'express'
const app = express()
app.get('/', (req, res) => {
  res.send('Hello World')
})
app.listen(3000, () => {
  console.log('Server is running on http://localhost:3000')
})

npm install express
'@
    Write-TextFile -Path $selectedPackagePath -Value '{"name":"express","version":"5.2.1"}'
    Write-TextFile -Path $selectedExamplePath -Value "var express = require('../../');`napp.get('/', function(req, res){`n  res.send('Hello World');`n});`napp.listen(3000);"
    Write-TextFile -Path $selectedAcceptancePath -Value "describe('hello-world', function () { it('GET /', function (done) { request(app).get('/').expect(200, 'Hello World', done) }) })"

    $selectedRecordPath = Join-Path $selectedDir "selected-contract.json"
    Write-JsonFile -Path $selectedRecordPath -Value ([ordered]@{
        schema_version = 1
        repository = "expressjs/express"
        rank = 243
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        selected_public_contracts = @(
            [ordered]@{
                source_path = "Readme.md"
                local_path = $selectedReadmePath
                sha = "fixtureexpressreadmesha"
                git_blob_sha_verified = $true
                content_sha256 = Get-FileSha256Hex -Path $selectedReadmePath
                size = 128
                fetched_size = 128
                reason = "fixture"
                github_blob_url = "https://api.github.com/repos/expressjs/express/git/blobs/fixtureexpressreadmesha"
            }
        )
        candidate_promotion_contracts = @(
            [ordered]@{ supports = "runtime-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("localhost-3000") },
            [ordered]@{ supports = "input-output-contract"; status = "candidate_evidence_harvested"; evidence_markers = @("hello-world-body") },
            [ordered]@{ supports = "candidate-executable-command"; status = "candidate_evidence_harvested"; evidence_markers = @("node-app") }
        )
    })

    $sourceYamlPath = Join-Path $candidateDir "test.qaas.yaml"
    $customAssertionYaml = ""
    if ($SourceActiveCustomAssertion) {
        $customAssertionYaml = @'

  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - ExpressReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello World
      EncodingName: utf-8
'@
    }
    Write-TextFile -Path $sourceYamlPath -Value @"
# Status: blocked_until_template_live_airgapped_validation
MetaData:
  Team: ZappaDontCry
  System: expressjs-express

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetRootPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-root.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: ExpressReadRoot
    Transactions:
      - Name: GetRoot
        TimeoutMs: 5000
        DataSourceNames:
          - GetRootPayload
        DataSourcePatterns:
          - GetRootPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 3000
          Route: /
          Method: Get

Assertions:
  - Name: GetRootReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - ExpressReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetRoot
$customAssertionYaml
"@

    $sourceAppPath = Join-Path $appDir "app.mjs"
    Write-TextFile -Path $sourceAppPath -Value @'
import express from 'express'

const app = express()

app.get('/', (req, res) => {
  res.send('Hello World')
})

app.listen(3000, () => {
  console.log('Server is running on http://localhost:3000')
})
'@
    $sourceBodyPath = Join-Path $expectationsDir "root-body.txt"
    Write-TextFile -Path $sourceBodyPath -Value "Hello World"
    $sourcePayloadPath = Join-Path $requestPayloadsDir "get-root.bin"
    [System.IO.File]::WriteAllBytes($sourcePayloadPath, [byte[]]::new(0))

    $sourceAssertionPath = Join-Path $assertionDir "ExactHttpTextBody.cs"
    Write-TextFile -Path $sourceAssertionPath -Value @'
using System;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using QaaS.Framework.SDK.DataSourceObjects;
using QaaS.Framework.SDK.Extensions;
using QaaS.Framework.SDK.Hooks.Assertion;
using QaaS.Framework.SDK.Session.SessionDataObjects;

namespace ZappaDontCry.SelectedCandidates.Express.Assertions;

public sealed record ExactHttpTextBodyConfig
{
    public string OutputName { get; set; } = string.Empty;
    public string ExpectedText { get; set; } = string.Empty;
    public string EncodingName { get; set; } = "utf-8";
}

public sealed class ExactHttpTextBody : BaseAssertion<ExactHttpTextBodyConfig>
{
    public override bool Assert(
        IImmutableList<SessionData> sessionDataList,
        IImmutableList<DataSource> dataSourceList)
    {
        var encoding = Encoding.GetEncoding(Configuration.EncodingName);
        var observed = sessionDataList.SelectMany(session => session.GetOutputByName(Configuration.OutputName).Data).ToImmutableList();
        foreach (var item in observed)
        {
            if (item.Body is not byte[] body)
            {
                return false;
            }

            if (!string.Equals(encoding.GetString(body), Configuration.ExpectedText, StringComparison.Ordinal))
            {
                return false;
            }
        }

        return true;
    }
}
'@
    $usagePath = Join-Path $assertionDir "ExactHttpTextBody.usage.yaml.txt"
    Write-TextFile -Path $usagePath -Value "Assertion: ExactHttpTextBody`nOutputName: GetRoot`nExpectedText: Hello World`nEncodingName: utf-8"
    $planPath = Join-Path $assertionDir "custom-text-body-hook-plan.json"
    Write-JsonFile -Path $planPath -Value ([ordered]@{ schema_version = 1; status = "authored_from_public_docs_not_template_validated"; weak_validation_passed = $false })

    $runnerProjectPath = Join-Path $runnerRoot "ZappaSelectedExpress.Runner.csproj"
    $runnerProgramPath = Join-Path $runnerRoot "Program.cs"
    $stagedYamlPath = Join-Path $runnerRoot "test.qaas.yaml"
    $stagedPayloadPath = Join-Path $stagedPayloadDir "get-root.bin"
    $stagedBodyPath = Join-Path $stagedExpectationsDir "root-body.txt"
    $stagedAppPath = Join-Path $expressWorkDir "app.mjs"
    $assertionProjectPath = Join-Path $assertionRoot "ZappaSelectedExpress.Assertions.csproj"
    $stagedAssertionPath = Join-Path $assertionRoot "ExactHttpTextBody.cs"
    Copy-Item -LiteralPath $sourcePayloadPath -Destination $stagedPayloadPath -Force
    Copy-Item -LiteralPath $sourceBodyPath -Destination $stagedBodyPath -Force
    Copy-Item -LiteralPath $sourceAppPath -Destination $stagedAppPath -Force
    Copy-Item -LiteralPath $sourceAssertionPath -Destination $stagedAssertionPath -Force
    $stagedYamlText = (Get-Content -LiteralPath $sourceYamlPath -Raw).Replace("          Route: /", "          Route: ''")
    $stagedYamlText = "$stagedYamlText
  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - ExpressReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello World
      EncodingName: utf-8
"
    Write-TextFile -Path $stagedYamlPath -Value $stagedYamlText
    Write-TextFile -Path $runnerProgramPath -Value @'
System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Express.Assertions.ExactHttpTextBody));
Directory.SetCurrentDirectory(AppContext.BaseDirectory);
QaaS.Runner.Bootstrap.New(args).Run();
'@
    Write-TextFile -Path $runnerProjectPath -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="$assertionProjectPath" />
  </ItemGroup>
</Project>
"@
    Write-TextFile -Path $assertionProjectPath -Value @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="QaaS.Framework.SDK" Version="1.5.1" />
  </ItemGroup>
</Project>
'@

    $stagedPackageJsonPath = Join-Path $expressWorkDir "package.json"
    $packageLockPath = Join-Path $expressWorkDir "package-lock.json"
    $installedExpressPackagePath = Join-Path $installedPackageDir "package.json"
    Write-TextFile -Path $stagedPackageJsonPath -Value '{"private":true,"type":"module"}'
    Write-TextFile -Path $packageLockPath -Value '{"name":"express-live-fixture","packages":{"node_modules/express":{"version":"5.2.1"}}}'
    Write-TextFile -Path $installedExpressPackagePath -Value '{"name":"express","version":"5.2.1"}'

    $assertionBuildTranscript = Join-Path $evidenceDir "build-assertion-library.transcript.txt"
    $buildTranscript = Join-Path $evidenceDir "build-runner.transcript.txt"
    $templateTranscript = Join-Path $evidenceDir "template-runner.transcript.txt"
    $liveTranscript = Join-Path $evidenceDir "live-runner-run.transcript.txt"
    $combinedTranscript = Join-Path $evidenceDir "selected-live-express.transcript.txt"
    $referenceTranscript = Join-Path $evidenceDir "reference-runner-assertion-project.transcript.txt"
    $responsePath = Join-Path $evidenceDir "root-response.txt"
    $stdoutPath = Join-Path $evidenceDir "express.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "express.stderr.txt"
    $npmStdoutPath = Join-Path $evidenceDir "npm-install.stdout.txt"
    $npmStderrPath = Join-Path $evidenceDir "npm-install.stderr.txt"
    $nodePath = Join-Path $evidenceDir "node.exe"
    $npmPath = Join-Path $evidenceDir "npm.cmd"
    Write-TextFile -Path $responsePath -Value $(if ($WrongBody) { "Hello Drift" } else { "Hello World" })
    Write-TextFile -Path $stdoutPath -Value "Server is running on http://localhost:3000"
    Write-TextFile -Path $stderrPath -Value ""
    Write-TextFile -Path $npmStdoutPath -Value "added express"
    Write-TextFile -Path $npmStderrPath -Value ""
    Write-TextFile -Path $nodePath -Value "fixture node"
    Write-TextFile -Path $npmPath -Value "fixture npm"
    Write-TextFile -Path $referenceTranscript -Value "Project reference added to $assertionProjectPath"
    Write-TextFile -Path $assertionBuildTranscript -Value "Command: dotnet build`nExitCode: 0"
    Write-TextFile -Path $buildTranscript -Value "Command: dotnet build`nExitCode: 0"
    Write-TextFile -Path $templateTranscript -Value @"
Command: dotnet run --project $runnerProjectPath -- template $stagedYamlPath --no-env
ExitCode: 0
Found IAssertion hook instance ExactHttpTextBody
Assertion: ExactHttpTextBody
Runner completed. ExitCode=0
"@
    $doubleSlashLine = ""
    if ($DoubleSlashUrl) {
        $doubleSlashLine = "[00:00:00 INF] HTTP Get request to http://127.0.0.1:3000// completed with status 200.`n"
    }
    Write-TextFile -Path $liveTranscript -Value @"
Command: dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env
ExitCode: 0
Found IAssertion hook instance ExactHttpTextBody
HTTP Get request to http://127.0.0.1:3000/ completed with status 200.
$($doubleSlashLine)Running assertion ExactHttpTextBody GetRootBodyMatchesReadme
Running assertion HttpStatus GetRootReturnedOk
Runner completed. ExitCode=0
"@
    $responseSha256 = Get-FileSha256Hex -Path $responsePath
    Write-TextFile -Path $combinedTranscript -Value @"
Validation: selected-top-repo-candidate-live-express
Repository: expressjs/express
RunnerProject: $runnerProjectPath
RunnerYaml: $stagedYamlPath
AssertionProject: $assertionProjectPath
AssertionSource: $stagedAssertionPath
AssertionProjectReferenceAdded: True
NodeCommand: node app.mjs
ExpressWorkDir: $expressWorkDir
NodePath: $nodePath
NpmPath: $npmPath
NodeVersion: v24.12.0
NpmVersion: 11.6.2
NodeMajorVersionAtLeast18: True
InstallCommand: npm install express
InstallExecutionCommand: npm install express@5.2.1
NpmInstallExitCode: 0
PackageSpec: express@5.2.1
InstalledExpressVersion: 5.2.1
ExpressPackageAvailable: True
Ready: True
ReadyStatus: HTTP 200 from / with exact README-backed body
ResponseStatus: 200
ResponseBodySha256: $responseSha256
AssertionBuildPassed: True
BuildPassed: True
TemplatePassed: True
LivePassed: True
CleanupPassed: True
CleanupProcessIds: 111,222
RemainingTrackedProcessIds:
PortOwnersAfterCleanupCount: 0
FailureReason:
ExitCode: 0
"@

    $hashes = [ordered]@{
        candidate_yaml_sha256 = Get-FileSha256Hex -Path $sourceYamlPath
        staged_yaml_sha256 = Get-FileSha256Hex -Path $stagedYamlPath
        candidate_request_payload_sha256 = Get-FileSha256Hex -Path $sourcePayloadPath
        staged_request_payload_sha256 = Get-FileSha256Hex -Path $stagedPayloadPath
        candidate_app_sha256 = Get-FileSha256Hex -Path $sourceAppPath
        staged_app_sha256 = Get-FileSha256Hex -Path $stagedAppPath
        candidate_expected_body_sha256 = Get-FileSha256Hex -Path $sourceBodyPath
        staged_expected_body_sha256 = Get-FileSha256Hex -Path $stagedBodyPath
        candidate_assertion_sha256 = Get-FileSha256Hex -Path $sourceAssertionPath
        staged_assertion_sha256 = Get-FileSha256Hex -Path $stagedAssertionPath
        selected_readme_sha256 = Get-FileSha256Hex -Path $selectedReadmePath
        selected_package_sha256 = Get-FileSha256Hex -Path $selectedPackagePath
        selected_example_sha256 = Get-FileSha256Hex -Path $selectedExamplePath
        selected_acceptance_sha256 = Get-FileSha256Hex -Path $selectedAcceptancePath
        staged_package_json_sha256 = Get-FileSha256Hex -Path $stagedPackageJsonPath
        package_lock_sha256 = Get-FileSha256Hex -Path $packageLockPath
        installed_express_package_sha256 = Get-FileSha256Hex -Path $installedExpressPackagePath
    }
    if ($FakeHashes) {
        foreach ($name in @($hashes.Keys)) {
            $hashes[$name] = "fake"
        }
    }

    $assertionBuildValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet build $assertionProjectPath --nologo -clp:ErrorsOnly"; transcript = $assertionBuildTranscript }
    $buildValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet build $runnerProjectPath --nologo -clp:ErrorsOnly"; transcript = $buildTranscript }
    $templateValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- template $stagedYamlPath --no-env"; transcript = $templateTranscript }
    $liveValidation = [ordered]@{ status = "passed"; exit_code = 0; command = "dotnet run --project $runnerProjectPath -- run $stagedYamlPath -e --no-env"; transcript = $liveTranscript }
    $summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-live-express.json"
    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $qaasValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "npm install express@5.2.1 ; node app.mjs ; dotnet build ; dotnet run template ; dotnet run live"
        transcript = $combinedTranscript
        summary = $summaryPath
        response = $responsePath
        run_dir = $runDir
    }
    $packet = [ordered]@{
        packet_id = "express-exact-http-text-body"
        assertion_name = "ExactHttpTextBody"
        status = "build_template_live_validated_blocked_until_airgapped"
        promotion_state = "blocked"
        activation = "staged_live_runner_only"
        wired_into_runner_yaml = $true
        source_files = @($sourceAssertionPath)
        yaml_fragment = $usagePath
        hook_plan = $planPath
        expected_body_path = $sourceBodyPath
        expected_body_sha256 = Get-FileSha256Hex -Path $sourceBodyPath
        encoding = "utf-8"
        comparison = "byte_for_byte"
        normalization = "none"
        case_sensitive = $true
        trim = $false
        contains = $false
        validation_records = [ordered]@{ build = "passed"; schema = "passed"; template = "passed"; live = "passed"; airgapped = "not_run" }
        weak_validation_passed = $false
    }

    $artifacts = @($sourceYamlPath, $sourceAppPath, $sourceBodyPath, $sourcePayloadPath, $sourceAssertionPath, $usagePath, $planPath, $runtimePlanPath, $manifestPath)
    Write-JsonFile -Path $manifestPath -Value ([ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-express-candidate"
        source_repository = "expressjs/express"
        repository_rank = 243
        selected_contract = $selectedRecordPath
        docs_evidence = @("D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md")
        public_evidence = @($selectedRecordPath, $selectedReadmePath, $selectedPackagePath)
        artifacts = $artifacts
        artifact_count = $artifacts.Count
        airgapped_validation = [ordered]@{ required = $true; status = "not_run_for_this_candidate"; dry_run = $false }
        source_only_blockers = @(
            [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @($selectedReadmePath); unblock_instruction = "run weak model" }
        )
        validation_advisories = @(
            [ordered]@{ advisory_id = "httpstatus-docs-inconsistency-recorded"; advisory_type = "qaas_docs_contract"; description = "blocked"; public_evidence = @(); resolved_by = "schema-derived StatusCode/OutputNames template and live validation"; validation_summary = $summaryPath; blocking = $false }
        )
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; status = "ready"; evidence = @($selectedRecordPath, $selectedReadmePath); blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; status = "ready"; evidence = @($selectedRecordPath, $selectedReadmePath); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; status = "ready"; evidence = @("docs"); blocked_reason = "" },
            [ordered]@{ gate_id = "node-express-process-lifecycle"; status = "passed"; evidence = @("fixture"); blocked_reason = "" },
            [ordered]@{ gate_id = "cleanup-contract"; status = "passed"; evidence = @("fixture"); blocked_reason = "" },
            [ordered]@{ gate_id = "plain-text-body-assertion-or-hook"; status = "passed"; evidence = @($summaryPath, $assertionBuildTranscript, $liveTranscript); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-template"; status = "passed"; evidence = @($summaryPath, $templateTranscript); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; status = "passed"; evidence = @($summaryPath, $liveTranscript, $responsePath); blocked_reason = "" },
            [ordered]@{ gate_id = "airgapped-validation"; status = "blocked"; evidence = @(); blocked_reason = "blocked" }
        )
        lifecycle_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "npm install express ; node app.mjs"; transcript = $combinedTranscript; summary = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-express.json"; response = $responsePath }
        assertion_build_validation = $assertionBuildValidation
        build_validation = $buildValidation
        template_validation = $templateValidation
        live_validation = $liveValidation
        selected_candidate_qaas_validation = $qaasValidation
        custom_text_body_assertion = [ordered]@{ status = "build_template_live_validated"; hook_family = "assertion"; assertion_type = "ExactHttpTextBody"; implementation = $sourceAssertionPath; usage_snippet = $usagePath; hook_plan = $planPath; validation_status = "build_template_live_validated"; weak_validation_passed = $false }
        custom_assertion_packets = @($packet)
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
    })
    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "expressjs/express"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command = "node app.mjs"
        qaas_validation = $qaasValidation
        cleanup = [ordered]@{ required = $true; status = "passed"; evidence = @("fixture") }
        blockers = @("run_live_airgapped_weak_model_validation", "run_strong_review_against_selected_contract_evidence")
        custom_text_body_assertion = [ordered]@{ status = "build_template_live_validated"; assertion_type = "ExactHttpTextBody"; implementation = $sourceAssertionPath; usage_snippet = $usagePath; hook_plan = $planPath; validation_status = "build_template_live_validated" }
        custom_assertion_packets = @($packet)
    })
    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = if ($FailedSummary) { "failed" } else { "passed" }
        promotion_state = "blocked"
        completion_ready = $false
        repository = "expressjs/express"
        validation_kind = "selected_candidate_qaas_template_live"
        run_dir = $runDir
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        runner_project = $runnerProjectPath
        runner_program = $runnerProgramPath
        runner_yaml = $stagedYamlPath
        source_runner_yaml = $sourceYamlPath
        assertion_project = $assertionProjectPath
        assertion_source = $stagedAssertionPath
        source_assertion = $sourceAssertionPath
        assertion_project_reference_transcript = $referenceTranscript
        assertion_project_reference_added = $true
        source_hashes = $hashes
        node_path = $nodePath
        npm_path = $npmPath
        node_version = "v24.12.0"
        npm_version = "11.6.2"
        node_major_version_at_least_18 = $true
        install_command = "npm install express"
        install_execution_command = "npm install express@5.2.1"
        package_spec = "express@5.2.1"
        installed_express_version = "5.2.1"
        express_package_available = $true
        npm_install_exit_code = 0
        npm_install_timed_out = $false
        npm_install_stdout = $npmStdoutPath
        npm_install_stderr = $npmStderrPath
        staged_package_json = $stagedPackageJsonPath
        package_lock = $packageLockPath
        installed_express_package = if ($MissingPackageEvidence) { Join-Path $expressWorkDir "missing-express-package.json" } else { $installedExpressPackagePath }
        selected_readme_evidence = $selectedReadmePath
        selected_package_evidence = $selectedPackagePath
        selected_example_evidence = $selectedExamplePath
        selected_acceptance_evidence = $selectedAcceptancePath
        assertion_build_validation = $assertionBuildValidation
        build_validation = $buildValidation
        template_validation = $templateValidation
        live_validation = $liveValidation
        response = $responsePath
        response_status = 200
        response_body_sha256 = $responseSha256
        response_contract_passed = (-not [bool]$WrongBody)
        cleanup_passed = $true
        cleanup_process_ids = @(111, 222)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        transcript = $combinedTranscript
        express_stdout = $stdoutPath
        express_stderr = $stderrPath
        manifest_updated = $true
        weak_validation_passed = [bool]$WeakValidationPassed
        failure_reason = if ($FailedSummary) { "fixture failure" } else { "" }
        exit_code = if ($FailedSummary) { 1 } else { 0 }
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        SelectedRoot = Split-Path -Parent $selectedDir
        CoverageDir = $coverageDir
        SummaryPath = $summaryPath
        LiveRoot = $liveRoot
    }
}

function New-FlaskLifecycleFixture {
    param(
        [string]$Root,
        [switch]$WeakValidationPassed,
        [switch]$MissingTextBodyBlocker,
        [switch]$QaaSValidationPassed,
        [switch]$JsonServerSummary,
        [switch]$BadResponseSha,
        [switch]$MissingManagedVenvEvidence
    )

    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $candidateDir = Join-Path $candidateRoot "227-pallets-flask"
    $lifecycleRoot = Join-Path $Root "lifecycle-runs\selected-top-repo-candidates"
    $runDir = Join-Path $lifecycleRoot "20260608-000000-000"
    $evidenceDir = Join-Path $runDir "evidence"
    $managedVenvPath = Join-Path $runDir "venv"
    $venvScriptsDir = Join-Path $managedVenvPath "Scripts"
    $appDir = Join-Path $candidateDir "app"
    $selectedPyprojectEvidence = Join-Path $Root "selected-contracts\227-pallets-flask\files\pyproject.toml"
    foreach ($dir in @($candidateDir, $appDir, $evidenceDir, $venvScriptsDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $summaryPath = Join-Path $Root "coverage\selected-top-repo-candidate-lifecycle-flask.json"
    $responsePath = Join-Path $evidenceDir "root-response.txt"
    $transcriptPath = Join-Path $evidenceDir "flask-lifecycle.transcript.txt"
    $stdoutPath = Join-Path $evidenceDir "flask.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "flask.stderr.txt"
    $venvCreateStdoutPath = Join-Path $evidenceDir "python-venv.stdout.txt"
    $venvCreateStderrPath = Join-Path $evidenceDir "python-venv.stderr.txt"
    $pipInstallStdoutPath = Join-Path $evidenceDir "pip-install-flask.stdout.txt"
    $pipInstallStderrPath = Join-Path $evidenceDir "pip-install-flask.stderr.txt"
    $pythonPath = Join-Path $venvScriptsDir "python.exe"
    $flaskCliPath = Join-Path $venvScriptsDir "flask.exe"
    Write-TextFile -Path $responsePath -Value "Hello, World!"
    Write-TextFile -Path $stdoutPath -Value "flask stdout"
    Write-TextFile -Path $stderrPath -Value "flask stderr"
    Write-TextFile -Path $venvCreateStdoutPath -Value "created venv"
    Write-TextFile -Path $venvCreateStderrPath -Value ""
    if (-not $MissingManagedVenvEvidence) {
        Write-TextFile -Path $pipInstallStdoutPath -Value "installed Flask"
    }
    Write-TextFile -Path $pipInstallStderrPath -Value ""
    Write-TextFile -Path $pythonPath -Value "fixture python executable"
    Write-TextFile -Path $flaskCliPath -Value "fixture flask executable"
    Write-TextFile -Path $selectedPyprojectEvidence -Value @"
name = "Flask"

[project.scripts]
flask = "flask.cli:main"
"@

    $responseBodySha256 = if ($BadResponseSha) { "fixture-sha" } else { Get-FileSha256Hex -Path $responsePath }
    Write-TextFile -Path $transcriptPath -Value @"
Validation: selected-top-repo-candidate-lifecycle-flask
Repository: pallets/flask
Command: flask run --no-reload --host 127.0.0.1 --port 5000
ManagedVenvPath: $managedVenvPath
InstallCommand: python -m pip install Flask
VenvCreateExitCode: 0
PipInstallExitCode: 0
FlaskModuleAvailable: True
FlaskVersion: 3.1.3
FlaskCliPath: $flaskCliPath
Ready: True
ResponseStatus: 200
ResponseBodySha256: $responseBodySha256
CleanupPassed: True
ExitCode: 0
"@

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $sourceBlockers = @(
        [ordered]@{ blocker_id = "flask-text-body-hook-not-template-validated"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("text assertion template validation"); public_evidence = @(); unblock_instruction = "template validate hook" },
        [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = @(); unblock_instruction = "run qaas" },
        [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @(); unblock_instruction = "run weak model" },
        [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = @(); unblock_instruction = "use schema" }
    )
    if ($MissingTextBodyBlocker) {
        $sourceBlockers = @($sourceBlockers | Where-Object { $_.blocker_id -ne "flask-text-body-hook-not-template-validated" })
    }

    $lifecycleValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "flask run ; GET http://127.0.0.1:5000/ ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @(12345)
    }
    $manifest = [ordered]@{
        schema_version = 1
        source_repository = "pallets/flask"
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
        lifecycle_validation = $lifecycleValidation
        source_only_blockers = $sourceBlockers
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; status = "ready"; evidence = @("docs"); blocked_reason = "" },
            [ordered]@{ gate_id = "python-flask-process-lifecycle"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
            [ordered]@{ gate_id = "cleanup-contract"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
            [ordered]@{ gate_id = "plain-text-body-assertion-or-hook"; status = "blocked"; evidence = @(); blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-template"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; status = "blocked"; evidence = @(); blocked_reason = "blocked" }
        )
    }
    if ($QaaSValidationPassed) {
        $manifest["selected_candidate_qaas_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    Write-JsonFile -Path $manifestPath -Value $manifest

    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "pallets/flask"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command = "flask run"
        cleanup = [ordered]@{ required = $true; status = "passed"; evidence = @($summaryPath, $transcriptPath) }
        lifecycle_validation = $lifecycleValidation
        blockers = @(
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
    })

    $summaryRepository = if ($JsonServerSummary) { "typicode/json-server" } else { "pallets/flask" }
    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = "passed"
        promotion_state = "blocked"
        completion_ready = $false
        repository = $summaryRepository
        validation_kind = "selected_candidate_process_lifecycle"
        command = "flask run"
        transcript = $transcriptPath
        stdout = $stdoutPath
        stderr = $stderrPath
        response = $responsePath
        response_status = 200
        response_body_sha256 = $responseBodySha256
        response_contract_passed = $true
        cleanup_passed = $true
        cleanup_process_ids = @(12345)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        python_path = $pythonPath
        flask_version = "3.1.3"
        flask_cli_path = $flaskCliPath
        managed_venv_path = $managedVenvPath
        install_command = "python -m pip install Flask"
        venv_create_stdout = $venvCreateStdoutPath
        venv_create_stderr = $venvCreateStderrPath
        pip_install_stdout = $pipInstallStdoutPath
        pip_install_stderr = $pipInstallStderrPath
        selected_pyproject_evidence = $selectedPyprojectEvidence
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        run_dir = $runDir
        exit_code = 0
        failure_reason = ""
        weak_validation_passed = [bool]$WeakValidationPassed
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        LifecycleRoot = $lifecycleRoot
        SummaryPath = $summaryPath
    }
}

function New-FastApiLifecycleFixture {
    param(
        [string]$Root,
        [switch]$WeakValidationPassed,
        [switch]$QaaSValidationPassed,
        [switch]$WrongBody,
        [switch]$WrongRepo,
        [switch]$WrongSummaryManifestPath
    )

    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $candidateDir = Join-Path $candidateRoot "114-fastapi-fastapi"
    $lifecycleRoot = Join-Path $Root "lifecycle-runs\selected-top-repo-candidates"
    $evidenceDir = Join-Path $lifecycleRoot "20260608-000000-000\evidence"
    $appDir = Join-Path $candidateDir "app"
    foreach ($dir in @($candidateDir, $appDir, $evidenceDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $summaryPath = Join-Path $Root "coverage\selected-top-repo-candidate-lifecycle-fastapi.json"
    $responsePath = Join-Path $evidenceDir "items-5-response.json"
    $transcriptPath = Join-Path $evidenceDir "fastapi-lifecycle.transcript.txt"
    $stdoutPath = Join-Path $evidenceDir "fastapi.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "fastapi.stderr.txt"
    $responseBody = if ($WrongBody) { '{"item_id":5,"q":"drift"}' } else { '{"item_id":5,"q":"somequery"}' }
    Write-TextFile -Path $responsePath -Value $responseBody
    Write-TextFile -Path $stdoutPath -Value "fastapi stdout"
    Write-TextFile -Path $stderrPath -Value "fastapi stderr"
    Write-TextFile -Path $transcriptPath -Value @"
Validation: selected-top-repo-candidate-lifecycle-fastapi
Repository: fastapi/fastapi
Command: fastapi dev
Ready: True
ResponseStatus: 200
CleanupPassed: True
ExitCode: 0
"@

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $summaryManifestPath = if ($WrongSummaryManifestPath) { Join-Path $candidateDir "wrong-manifest.json" } else { $manifestPath }
    $lifecycleValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "fastapi dev ; GET http://127.0.0.1:8000/items/5?q=somequery ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @(12345)
    }
    $manifest = [ordered]@{
        schema_version = 1
        source_repository = "fastapi/fastapi"
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
        lifecycle_validation = $lifecycleValidation
        source_only_blockers = @(
            [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = @(); unblock_instruction = "run qaas" },
            [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @(); unblock_instruction = "run weak model" },
            [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = @(); unblock_instruction = "use schema" }
        )
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; status = "ready"; evidence = @("docs"); blocked_reason = "" },
            [ordered]@{ gate_id = "python-fastapi-process-lifecycle"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
            [ordered]@{ gate_id = "cleanup-contract"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-template"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; status = "blocked"; evidence = @(); blocked_reason = "blocked" }
        )
    }
    if ($QaaSValidationPassed) {
        $manifest["selected_candidate_qaas_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    Write-JsonFile -Path $manifestPath -Value $manifest

    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "fastapi/fastapi"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command = "fastapi dev"
        cleanup = [ordered]@{ required = $true; status = "passed"; evidence = @($summaryPath, $transcriptPath) }
        lifecycle_validation = $lifecycleValidation
        blockers = @(
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
    })

    $summaryRepository = if ($WrongRepo) { "typicode/json-server" } else { "fastapi/fastapi" }
    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = "passed"
        promotion_state = "blocked"
        completion_ready = $false
        repository = $summaryRepository
        validation_kind = "selected_candidate_process_lifecycle"
        command = "fastapi dev"
        transcript = $transcriptPath
        stdout = $stdoutPath
        stderr = $stderrPath
        response = $responsePath
        response_status = 200
        response_body_sha256 = "fixture-sha"
        response_contract_passed = $true
        cleanup_passed = $true
        cleanup_process_ids = @(12345)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        manifest = $summaryManifestPath
        runtime_plan = $runtimePlanPath
        run_dir = (Split-Path -Parent $evidenceDir)
        exit_code = 0
        failure_reason = ""
        weak_validation_passed = [bool]$WeakValidationPassed
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        LifecycleRoot = $lifecycleRoot
        SummaryPath = $summaryPath
    }
}

function New-GinLifecycleFixture {
    param(
        [string]$Root,
        [switch]$WeakValidationPassed,
        [switch]$QaaSValidationPassed,
        [switch]$MissingModuleGate,
        [switch]$WrongBody,
        [switch]$BadGoModSha,
        [switch]$BadGoSumSha,
        [switch]$MissingManagedEnv,
        [switch]$MutableModuleCommand,
        [switch]$WrongGoSource,
        [switch]$WrongGoVersion,
        [switch]$WrongGoArchiveUrl,
        [switch]$BadGoArchiveSha,
        [switch]$EnvMismatch
    )

    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $candidateDir = Join-Path $candidateRoot "138-gin-gonic-gin"
    $lifecycleRoot = Join-Path $Root "lifecycle-runs\selected-top-repo-candidates"
    $runDir = Join-Path $lifecycleRoot "20260608-000000-000"
    $evidenceDir = Join-Path $runDir "evidence"
    $workDir = Join-Path $runDir "work"
    $goEnvRoot = Join-Path $runDir "go-env"
    $managedGoPath = Join-Path $goEnvRoot "gopath"
    $managedGoModCache = Join-Path $goEnvRoot "gomodcache"
    $managedGoCache = Join-Path $goEnvRoot "gocache"
    $toolchainRoot = Join-Path $Root "toolchains\go"
    $toolchainPath = Join-Path $toolchainRoot "go1.26.4-windows-amd64"
    $goRoot = Join-Path $toolchainPath "go"
    $goBinDir = Join-Path $goRoot "bin"
    $appDir = Join-Path $candidateDir "app"
    foreach ($dir in @($candidateDir, $appDir, $evidenceDir, $workDir, $managedGoPath, $managedGoModCache, $managedGoCache, $goBinDir, (Join-Path $toolchainRoot "archives"))) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $summaryPath = Join-Path $Root "coverage\selected-top-repo-candidate-lifecycle-gin.json"
    $responsePath = Join-Path $evidenceDir "ping-response.json"
    $transcriptPath = Join-Path $evidenceDir "gin-lifecycle.transcript.txt"
    $stdoutPath = Join-Path $evidenceDir "gin.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "gin.stderr.txt"
    $goPath = Join-Path $goBinDir "go.exe"
    $archivePath = Join-Path $toolchainRoot "archives\go1.26.4.windows-amd64.zip"
    $goEnvJsonPath = Join-Path $evidenceDir "go-env.json"
    $goModPath = Join-Path $workDir "go.mod"
    $goSumPath = Join-Path $workDir "go.sum"
    $goListModuleJsonPath = Join-Path $evidenceDir "go-list-gin-module.json"
    $responseBody = if ($WrongBody) { '{"message":"ping"}' } else { '{"message":"pong"}' }
    Write-TextFile -Path $responsePath -Value $responseBody
    Write-TextFile -Path $stdoutPath -Value "gin stdout"
    Write-TextFile -Path $stderrPath -Value "gin stderr"
    Write-TextFile -Path $goPath -Value "fixture go exe"
    $officialArchivePath = "D:\QaaS\_tmp\zappa-dont-cry\toolchains\go\archives\go1.26.4.windows-amd64.zip"
    if (-not (Test-Path -LiteralPath $officialArchivePath -PathType Leaf)) {
        throw "Official Go archive fixture missing: $officialArchivePath. Run Gin lifecycle once before harness regression."
    }
    try {
        if (Test-Path -LiteralPath $archivePath -PathType Leaf) {
            Remove-Item -LiteralPath $archivePath -Force
        }
        New-Item -ItemType HardLink -Path $archivePath -Target $officialArchivePath | Out-Null
    } catch {
        Copy-Item -LiteralPath $officialArchivePath -Destination $archivePath -Force
    }
    $goSourceValue = if ($WrongGoSource) { "global_path" } else { "managed_go_toolchain" }
    $goVersionValue = if ($WrongGoVersion) { "go version go1.25.0 windows/amd64" } else { "go version go1.26.4 windows/amd64" }
    $downloadUrlValue = if ($WrongGoArchiveUrl) { "https://go.dev/dl/go1.25.0.windows-amd64.zip" } else { "https://go.dev/dl/go1.26.4.windows-amd64.zip" }
    $archiveShaValue = if ($BadGoArchiveSha) { "fixture-bad-archive-sha" } else { Get-FileSha256Hex -Path $archivePath }
    $goEnvRootValue = if ($EnvMismatch) { Join-Path $Root "wrong-go-root" } else { $goRoot }
    $goEnvPathValue = if ($EnvMismatch) { Join-Path $runDir "wrong-gopath" } else { $managedGoPath }
    $goEnvModCacheValue = if ($EnvMismatch) { Join-Path $runDir "wrong-gomodcache" } else { $managedGoModCache }
    $goEnvCacheValue = if ($EnvMismatch) { Join-Path $runDir "wrong-gocache" } else { $managedGoCache }
    Write-TextFile -Path $goEnvJsonPath -Value (@{
            GOROOT = $goEnvRootValue
            GOPATH = $goEnvPathValue
            GOMODCACHE = $goEnvModCacheValue
            GOCACHE = $goEnvCacheValue
        } | ConvertTo-Json -Depth 4)
    Write-TextFile -Path $goModPath -Value @'
module zappa.local/gin-lifecycle

go 1.26.4

require github.com/gin-gonic/gin v1.12.0
'@
    Write-TextFile -Path $goSumPath -Value "github.com/gin-gonic/gin v1.12.0 h1:fixture"
    Write-TextFile -Path $goListModuleJsonPath -Value @'
{
  "Path": "github.com/gin-gonic/gin",
  "Version": "v1.12.0"
}
'@
    $moduleCommand = if ($MutableModuleCommand) { "ModulePinCommand: go get -u github.com/gin-gonic/gin@latest" } else { "ModulePinCommand: go get github.com/gin-gonic/gin@v1.12.0" }
    Write-TextFile -Path $transcriptPath -Value @"
Validation: selected-top-repo-candidate-lifecycle-gin
Repository: gin-gonic/gin
Command: go run main.go
GoSource: $goSourceValue
GoPath: $goPath
GoVersion: $goVersionValue
ManagedGoToolchainRoot: $toolchainRoot
ManagedGoInstallDir: $toolchainPath
ManagedGoArchive: $archivePath
ManagedGoDownloadUrl: $downloadUrlValue
ManagedGoArchiveSha256: $archiveShaValue
GoRoot: $goRoot
ManagedGoPath: $managedGoPath
ManagedGoModCache: $managedGoModCache
ManagedGoCache: $managedGoCache
GoEnvCommand: go env -json
GoEnvExitCode: 0
ModuleInitCommand: go mod init zappa.local/gin-lifecycle
$moduleCommand
ModuleDownloadCommand: go mod download
ModuleDownloadExitCode: 0
ModuleListCommand: go list -m -json github.com/gin-gonic/gin
ModuleListExitCode: 0
ModuleResolutionPassed: True
RunCommand: go run -mod=readonly main.go
Ready: True
ResponseStatus: 200
CleanupPassed: True
ExitCode: 0
"@

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $lifecycleValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "go run main.go ; GET http://127.0.0.1:8080/ping ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        go_source = $goSourceValue
        go_path = $goPath
        go_version = $goVersionValue
        cleanup_process_ids = @(12345)
    }
    $dependencyGates = @(
        [ordered]@{ gate_id = "selected-public-runtime-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
        [ordered]@{ gate_id = "selected-public-input-output-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
        [ordered]@{ gate_id = "qaas-docs-yaml-shape"; status = "ready"; evidence = @("docs"); blocked_reason = "" }
    )
    if (-not $MissingModuleGate) {
        $dependencyGates += [ordered]@{ gate_id = "go-version-and-module-resolution"; status = "passed"; evidence = @($summaryPath, $transcriptPath); blocked_reason = "" }
    }
    $dependencyGates += @(
        [ordered]@{ gate_id = "go-gin-process-lifecycle"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
        [ordered]@{ gate_id = "cleanup-contract"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
        [ordered]@{ gate_id = "qaas-template"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
        [ordered]@{ gate_id = "qaas-live-act-assert"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
        [ordered]@{ gate_id = "airgapped-validation"; status = "blocked"; evidence = @(); blocked_reason = "blocked" }
    )
    $manifest = [ordered]@{
        schema_version = 1
        source_repository = "gin-gonic/gin"
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
        lifecycle_validation = $lifecycleValidation
        source_only_blockers = @(
            [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = @(); unblock_instruction = "run qaas" },
            [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @(); unblock_instruction = "run weak model" },
            [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = @(); unblock_instruction = "use schema" }
        )
        dependency_gates = $dependencyGates
    }
    if ($QaaSValidationPassed) {
        $manifest["selected_candidate_qaas_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    Write-JsonFile -Path $manifestPath -Value $manifest

    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "gin-gonic/gin"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command = "go run main.go"
        cleanup = [ordered]@{ required = $true; status = "passed"; evidence = @($summaryPath, $transcriptPath) }
        lifecycle_validation = $lifecycleValidation
        blockers = @(
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
    })

    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = "passed"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "gin-gonic/gin"
        validation_kind = "selected_candidate_process_lifecycle"
        command = "go run main.go"
        module_pin_command = "go get github.com/gin-gonic/gin@v1.12.0"
        module_download_command = "go mod download"
        module_list_command = "go list -m -json github.com/gin-gonic/gin"
        module_pin = "github.com/gin-gonic/gin@v1.12.0"
        go_source = $goSourceValue
        go_path = $goPath
        go_version = $goVersionValue
        go_root = $goRoot
        go_env_json = $goEnvJsonPath
        managed_gopath = if ($MissingManagedEnv) { "" } else { $managedGoPath }
        managed_gomodcache = if ($MissingManagedEnv) { "" } else { $managedGoModCache }
        managed_gocache = if ($MissingManagedEnv) { "" } else { $managedGoCache }
        managed_toolchain_root = $toolchainRoot
        managed_toolchain_path = $toolchainPath
        managed_toolchain_archive = $archivePath
        managed_toolchain_archive_sha256 = $archiveShaValue
        managed_toolchain_download_url = $downloadUrlValue
        managed_toolchain_downloaded = $false
        module_resolution_passed = $true
        go_mod_path = $goModPath
        go_mod_sha256 = if ($BadGoModSha) { "fixture-bad-sha" } else { Get-FileSha256Hex -Path $goModPath }
        go_sum_path = $goSumPath
        go_sum_sha256 = if ($BadGoSumSha) { "fixture-bad-sha" } else { Get-FileSha256Hex -Path $goSumPath }
        go_list_module_json = $goListModuleJsonPath
        transcript = $transcriptPath
        stdout = $stdoutPath
        stderr = $stderrPath
        response = $responsePath
        response_status = 200
        response_body_sha256 = Get-FileSha256Hex -Path $responsePath
        response_contract_passed = $true
        cleanup_passed = $true
        cleanup_process_ids = @(12345)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        run_dir = $runDir
        exit_code = 0
        failure_reason = ""
        weak_validation_passed = [bool]$WeakValidationPassed
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        LifecycleRoot = $lifecycleRoot
        SummaryPath = $summaryPath
    }
}

function New-ExpressLifecycleFixture {
    param(
        [string]$Root,
        [switch]$WeakValidationPassed,
        [switch]$QaaSValidationPassed,
        [switch]$WrongBody,
        [switch]$BadResponseSha,
        [switch]$MissingPackageEvidence
    )

    $candidateRoot = Join-Path $Root "generated-tests\selected-top-repo-candidates"
    $candidateDir = Join-Path $candidateRoot "243-expressjs-express"
    $lifecycleRoot = Join-Path $Root "lifecycle-runs\selected-top-repo-candidates"
    $runDir = Join-Path $lifecycleRoot "20260608-000000-000"
    $evidenceDir = Join-Path $runDir "evidence"
    $workDir = Join-Path $runDir "work\app"
    $selectedContractsDir = Join-Path $Root "top-repos\selected-contracts\243-expressjs-express\files"
    foreach ($dir in @($candidateDir, $evidenceDir, $workDir, $selectedContractsDir, (Join-Path $Root "coverage"))) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $summaryPath = Join-Path $Root "coverage\selected-top-repo-candidate-lifecycle-express.json"
    $responsePath = Join-Path $evidenceDir "root-response.txt"
    $transcriptPath = Join-Path $evidenceDir "express-lifecycle.transcript.txt"
    $stdoutPath = Join-Path $evidenceDir "express.stdout.txt"
    $stderrPath = Join-Path $evidenceDir "express.stderr.txt"
    $npmInstallStdoutPath = Join-Path $evidenceDir "npm-install.stdout.txt"
    $npmInstallStderrPath = Join-Path $evidenceDir "npm-install.stderr.txt"
    $appPath = Join-Path $workDir "app.mjs"
    $stagedPackageJsonPath = Join-Path $workDir "package.json"
    $packageLockPath = Join-Path $workDir "package-lock.json"
    $installedExpressPackagePath = Join-Path $workDir "node_modules\express\package.json"
    $selectedPackagePath = Join-Path $selectedContractsDir "package.json"
    $selectedAcceptancePath = Join-Path $selectedContractsDir "test\acceptance\hello-world.js"
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $installedExpressPackagePath)) | Out-Null
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $selectedAcceptancePath)) | Out-Null

    $responseBody = if ($WrongBody) { "Hello Drift" } else { "Hello World" }
    Write-TextFile -Path $responsePath -Value $responseBody
    Write-TextFile -Path $stdoutPath -Value "express stdout"
    Write-TextFile -Path $stderrPath -Value "express stderr"
    Write-TextFile -Path $npmInstallStdoutPath -Value "npm install stdout"
    Write-TextFile -Path $npmInstallStderrPath -Value "npm install stderr"
    Write-TextFile -Path $appPath -Value "import express from 'express'`nconst app = express()`napp.get('/', (req, res) => res.send('Hello World'))`napp.listen(3000)"
    Write-TextFile -Path $stagedPackageJsonPath -Value '{"private":true,"type":"module","dependencies":{"express":"^5.2.1"}}'
    Write-TextFile -Path $packageLockPath -Value '{"name":"express-lifecycle-fixture","packages":{"node_modules/express":{"version":"5.2.1"}}}'
    Write-TextFile -Path $installedExpressPackagePath -Value '{"name":"express","version":"5.2.1"}'
    Write-TextFile -Path $selectedPackagePath -Value '{"name":"express","version":"5.2.1"}'
    Write-TextFile -Path $selectedAcceptancePath -Value "describe('hello-world', function () { it('GET /', function (done) { request(app).get('/').expect(200, 'Hello World', done) }) })"

    $responseBodySha256 = if ($BadResponseSha) { "fixture-bad-response-sha" } else { Get-FileSha256Hex -Path $responsePath }
    $stagedAppSha256 = Get-FileSha256Hex -Path $appPath
    $stagedPackageJsonSha256 = Get-FileSha256Hex -Path $stagedPackageJsonPath
    $packageLockSha256 = Get-FileSha256Hex -Path $packageLockPath
    $installedExpressPackageSha256 = Get-FileSha256Hex -Path $installedExpressPackagePath

    Write-TextFile -Path $transcriptPath -Value @"
Validation: selected-top-repo-candidate-lifecycle-express
Repository: expressjs/express
InstallCommand: npm install express
Command: node app.mjs
WorkingDirectory: $workDir
NodeVersion: v24.12.0
NpmVersion: 11.6.2
NpmPath: C:\fixture\npm.cmd
NodePath: C:\fixture\node.exe
NodeMajorVersionAtLeast18: True
InstallExecutionCommand: npm install express@5.2.1
NpmInstallExitCode: 0
PackageSpec: express@5.2.1
ExpressPackageAvailable: True
InstalledExpressVersion: 5.2.1
InstalledExpressPackage: $installedExpressPackagePath
PackageLockSha256: $packageLockSha256
SelectedExampleEvidence: $selectedAcceptancePath
SelectedAcceptanceEvidence: $selectedAcceptancePath
SelectedPackageEvidence: $selectedPackagePath
Ready: True
ResponseStatus: 200
ResponseBodySha256: $responseBodySha256
CleanupPassed: True
ExitCode: 0
"@

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
    $lifecycleValidation = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "npm install express ; node app.mjs ; GET http://127.0.0.1:3000/ ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @(12345)
    }
    $manifest = [ordered]@{
        schema_version = 1
        source_repository = "expressjs/express"
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "blocked"
        lifecycle_validation = $lifecycleValidation
        source_only_blockers = @(
            [ordered]@{ blocker_id = "express-text-body-hook-not-template-validated"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("hook"); public_evidence = @(); unblock_instruction = "run hook validation" },
            [ordered]@{ blocker_id = "qaas-template-live-not-run"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("template/live"); public_evidence = @(); unblock_instruction = "run qaas" },
            [ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "source_boundary"; description = "blocked"; required_evidence = @("weak"); public_evidence = @(); unblock_instruction = "run weak model" },
            [ordered]@{ blocker_id = "httpstatus-docs-inconsistency-recorded"; blocker_type = "qaas_docs_contract"; description = "blocked"; required_evidence = @("schema"); public_evidence = @(); unblock_instruction = "use schema" }
        )
        dependency_gates = @(
            [ordered]@{ gate_id = "selected-public-runtime-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
            [ordered]@{ gate_id = "selected-public-input-output-contract"; status = "ready"; evidence = @("public"); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-docs-yaml-shape"; status = "ready"; evidence = @("docs"); blocked_reason = "" },
            [ordered]@{ gate_id = "node-express-process-lifecycle"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
            [ordered]@{ gate_id = "cleanup-contract"; status = "passed"; evidence = @($summaryPath, $transcriptPath, $responsePath); blocked_reason = "" },
            [ordered]@{ gate_id = "plain-text-body-assertion-or-hook"; status = "ready"; evidence = @("hook"); blocked_reason = "" },
            [ordered]@{ gate_id = "qaas-template"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
            [ordered]@{ gate_id = "qaas-live-act-assert"; status = "blocked"; evidence = @("docs"); blocked_reason = "blocked" },
            [ordered]@{ gate_id = "airgapped-validation"; status = "blocked"; evidence = @(); blocked_reason = "blocked" }
        )
    }
    if ($QaaSValidationPassed) {
        $manifest["selected_candidate_qaas_validation"] = [ordered]@{ status = "passed"; exit_code = 0; transcript = $transcriptPath }
    }
    Write-JsonFile -Path $manifestPath -Value $manifest

    Write-JsonFile -Path $runtimePlanPath -Value ([ordered]@{
        schema_version = 1
        repository = "expressjs/express"
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command = "node app.mjs"
        cleanup = [ordered]@{ required = $true; status = "passed"; evidence = @($summaryPath, $transcriptPath) }
        lifecycle_validation = $lifecycleValidation
        blockers = @(
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
    })

    Write-JsonFile -Path $summaryPath -Value ([ordered]@{
        schema_version = 1
        status = "passed"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "expressjs/express"
        validation_kind = "selected_candidate_process_lifecycle"
        command = "node app.mjs"
        install_command = "npm install express"
        install_execution_command = "npm install express@5.2.1"
        npm_install_exit_code = 0
        package_spec = "express@5.2.1"
        installed_express_version = "5.2.1"
        express_package_available = $true
        node_version = "v24.12.0"
        npm_version = "11.6.2"
        node_major_version_at_least_18 = $true
        working_directory = $workDir
        candidate_app_sha256 = $stagedAppSha256
        staged_app_sha256 = $stagedAppSha256
        staged_package_json_sha256 = $stagedPackageJsonSha256
        package_lock_sha256 = $packageLockSha256
        installed_express_package_sha256 = $installedExpressPackageSha256
        selected_acceptance_evidence = $selectedAcceptancePath
        selected_package_evidence = $selectedPackagePath
        staged_package_json = $stagedPackageJsonPath
        package_lock = $packageLockPath
        installed_express_package = if ($MissingPackageEvidence) { Join-Path $workDir "missing-express-package.json" } else { $installedExpressPackagePath }
        npm_install_stdout = $npmInstallStdoutPath
        npm_install_stderr = $npmInstallStderrPath
        transcript = $transcriptPath
        stdout = $stdoutPath
        stderr = $stderrPath
        response = $responsePath
        response_status = 200
        response_body_sha256 = $responseBodySha256
        response_contract_passed = $true
        cleanup_passed = $true
        cleanup_process_ids = @(12345)
        remaining_tracked_process_ids = @()
        port_owners_after_cleanup_count = 0
        manifest = $manifestPath
        runtime_plan = $runtimePlanPath
        run_dir = $runDir
        exit_code = 0
        failure_reason = ""
        weak_validation_passed = [bool]$WeakValidationPassed
    })

    [pscustomobject]@{
        CandidateRoot = $candidateRoot
        CandidateDir = $candidateDir
        LifecycleRoot = $lifecycleRoot
        SummaryPath = $summaryPath
    }
}

function Invoke-SelectedCandidateLifecycleCheck {
    param(
        [string]$Name,
        [object]$Fixture
    )

    Invoke-CapturedCommand -Name $Name -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidateLifecycle.ps1"),
        "-CandidateRoot",
        $Fixture.CandidateRoot,
        "-CandidateDir",
        $Fixture.CandidateDir,
        "-SummaryPath",
        $Fixture.SummaryPath,
        "-LifecycleRoot",
        $Fixture.LifecycleRoot
    )
}

$OutDir = [System.IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $OutDir) {
    Remove-Item -LiteralPath $OutDir -Recurse -Force
}
[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null

$fixtureRoot = Join-Path $OutDir "fixtures"
$weakPolicy = Read-WeakEvidencePolicy -Path "D:\QaaS\_tools\weak-model-policy.json"
$preferredModels = @(Get-WeakEvidenceAllowedModels -Policy $weakPolicy -Harness "claude-copilot" -Profile "airgapped" -RequiredEvidenceClass @("preferred_weak"))
if ($preferredModels -contains "id:gpt-3.5-turbo" -and $preferredModels -notcontains "gpt-5.4-mini") {
    Add-Pass "Weak evidence policy exposes only preferred airgapped weak proxy models for promotion"
} else {
    Add-Failure "Weak evidence policy preferred models are not fail-closed: $($preferredModels -join ', ')"
}
$dryRunEligibility = Get-WeakEvidenceEligibility -Policy $weakPolicy -Harness "claude-copilot" -Profile "airgapped" -Model "id:gpt-3.5-turbo" -DryRun:$true -Command "DRY_RUN claude-copilot id:gpt-3.5-turbo" -RequiredEvidenceClass @("preferred_weak")
if (-not [bool]$dryRunEligibility.weak_validation_eligible -and [string]$dryRunEligibility.not_weak_reason -eq "dry-run-is-never-weak-evidence") {
    Add-Pass "Weak evidence policy rejects dry-run preferred route"
} else {
    Add-Failure "Weak evidence policy accepted dry-run preferred route"
}
$codexEligibility = Get-WeakEvidenceEligibility -Policy $weakPolicy -Harness "codex" -Profile "airgapped" -Model "gpt-5.4-mini" -DryRun:$false -Command "codex exec --model gpt-5.4-mini" -RequiredEvidenceClass @("preferred_weak")
if (-not [bool]$codexEligibility.weak_validation_eligible) {
    Add-Pass "Weak evidence policy rejects Codex hosted route"
} else {
    Add-Failure "Weak evidence policy accepted Codex hosted route"
}
$fallbackPromotionEligibility = Get-WeakEvidenceEligibility -Policy $weakPolicy -Harness "copilot" -Profile "airgapped" -Model "mai-code-1-flash" -DryRun:$false -Command "copilot --model mai-code-1-flash" -RequiredEvidenceClass @("preferred_weak")
if (-not [bool]$fallbackPromotionEligibility.weak_validation_eligible -and [string]$fallbackPromotionEligibility.not_weak_reason -eq "evidence-class-not-accepted-for-promotion") {
    Add-Pass "Weak evidence policy keeps Copilot fallback out of promotion evidence"
} else {
    Add-Failure "Weak evidence policy accepted Copilot fallback as promotion evidence"
}

$failingAirgappedValidator = Join-Path $fixtureRoot "failing-weak-model-session.ps1"
Write-TextFile -Path $failingAirgappedValidator -Value @'
param(
    [string]$Prompt,
    [switch]$Airgapped,
    [int]$TimeoutSeconds,
    [string]$OutDir
)

Write-Output "Weak model validation complete."
Write-Output "Synthetic validator failure for regression."
exit 17
'@
$failingAirgappedWrapperResult = Invoke-CapturedCommand -Name "airgapped-wrapper-propagates-validator-exit" -FilePath "powershell" -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $HarnessRoot "scripts\run-airgapped-validation.ps1"),
    "-ValidatorPath",
    $failingAirgappedValidator,
    "-Prompt",
    "synthetic failure",
    "-OutDir",
    (Join-Path $fixtureRoot "failing-airgapped-out")
)
Assert-ExitCode -Name "Airgapped wrapper propagates weak validator failure exit code" -Result $failingAirgappedWrapperResult -ExpectedExitCode 17 -ExpectedText "Synthetic validator failure"

if ($preferredModels.Count -ge 2) {
    $preferredEvidenceRoot = Join-Path $fixtureRoot "preferred-airgapped-partial"
    $preferredBlockersDir = Join-Path $fixtureRoot "preferred-airgapped-blockers"
    [System.IO.Directory]::CreateDirectory($preferredEvidenceRoot) | Out-Null
    $firstPreferredModel = [string]$preferredModels[0]
    $safeFirstPreferredModel = $firstPreferredModel.Replace(":", "_")
    $preferredPrefix = "20260608T000000"
    $preferredSummaryPath = Join-Path $preferredEvidenceRoot "$preferredPrefix-summary.md"
    $preferredTranscriptPath = Join-Path $preferredEvidenceRoot "$preferredPrefix-claude-copilot-$safeFirstPreferredModel.md"
    $stalePrefix = "20260607T000000"
    $staleSummaryPath = Join-Path $preferredEvidenceRoot "$stalePrefix-summary.md"
    $staleSummaryResults = @()
    foreach ($staleModel in @($preferredModels | Select-Object -Skip 1)) {
        $safeStaleModel = ([string]$staleModel).Replace(":", "_")
        $staleTranscriptPath = Join-Path $preferredEvidenceRoot "$stalePrefix-claude-copilot-$safeStaleModel.md"
        Write-TextFile -Path $staleTranscriptPath -Value @"
Harness: claude-copilot
Profile: airgapped
Model: $staleModel
DryRun: False
Command: claude --model $staleModel --print
ExitCode: 0

WEAK_VALIDATOR_READY
"@
        $staleSummaryResults += "- PASS exit 0: $staleTranscriptPath"
    }
    Write-TextFile -Path $staleSummaryPath -Value @"
Harness: claude-copilot
Profile: airgapped
DryRun: False
Airgapped: True
Models: $(@($preferredModels | Select-Object -Skip 1) -join ", ")
$($staleSummaryResults -join "`n")
"@
    (Get-Item -LiteralPath $staleSummaryPath).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-1)
    foreach ($staleTranscript in Get-ChildItem -LiteralPath $preferredEvidenceRoot -File -Filter "$stalePrefix-claude-copilot-*.md") {
        $staleTranscript.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-1)
    }
    Write-TextFile -Path $preferredSummaryPath -Value @"
Harness: claude-copilot
Profile: airgapped
DryRun: False
Airgapped: True
Models: $firstPreferredModel
- FAIL exit 75: quota blocked while running $firstPreferredModel
"@
    Write-TextFile -Path $preferredTranscriptPath -Value @"
Harness: claude-copilot
Profile: airgapped
Model: $firstPreferredModel
Command: claude --model $firstPreferredModel --print
ExitCode: 75

additional_spend_limit_reached
"@
    $preferredPartialResult = Invoke-CapturedCommand -Name "airgapped-live-preferred-partial" -FilePath "powershell" -Arguments @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Join-Path $HarnessRoot "checks\Check-AirgappedLiveEvidence.ps1"),
        "-EvidenceRoot",
        $preferredEvidenceRoot,
        "-BlockersDir",
        $preferredBlockersDir,
        "-PolicyPath",
        "D:\QaaS\_tools\weak-model-policy.json"
    )
    Assert-ExitCode -Name "Airgapped live evidence records partial preferred weak attempts" -Result $preferredPartialResult -ExpectedExitCode 0 -ExpectedText "Airgapped live evidence classified."
    $preferredRecordPath = Join-Path $preferredBlockersDir "airgapped-live-latest.json"
    if (Test-Path -LiteralPath $preferredRecordPath -PathType Leaf) {
        $preferredRecord = Read-JsonFile -Path $preferredRecordPath
        $expectedMissingCount = $preferredModels.Count - 1
        $missingRecords = @($preferredRecord.records | Where-Object { $_.classification -eq "missing_live_attempt" })
        $quotaRecords = @($preferredRecord.records | Where-Object { $_.classification -eq "quota_blocked" })
        if ([int]$preferredRecord.expected_model_count -eq $preferredModels.Count -and
            [int]$preferredRecord.missing_attempt_count -eq $expectedMissingCount -and
            $missingRecords.Count -eq $expectedMissingCount -and
            $quotaRecords.Count -eq 1 -and
            [string]$preferredRecord.classification -eq "quota_blocked" -and
            -not [bool]$preferredRecord.weak_validation_passed) {
            Add-Pass "Airgapped live evidence enumerates all missing preferred weak models"
        } else {
            Add-Failure "Airgapped live evidence did not enumerate partial preferred model attempts correctly: $preferredRecordPath"
        }
    } else {
        Add-Failure "Airgapped live evidence did not write preferred partial record: $preferredRecordPath"
    }
} else {
    Add-Failure "Weak evidence policy must expose at least two preferred models to regression-test missing attempts"
}

$objectiveFallbackRoot = Join-Path $fixtureRoot "objective-fallback-does-not-complete"
$objectiveGeneratedRoot = Join-Path $objectiveFallbackRoot "generated-tests"
$objectiveManifestDir = Join-Path $objectiveGeneratedRoot "blocked-manifest"
$objectiveCoverageDir = Join-Path $objectiveFallbackRoot "coverage"
$objectiveBlockersDir = Join-Path $objectiveFallbackRoot "blockers"
foreach ($dir in @($objectiveManifestDir, $objectiveCoverageDir, $objectiveBlockersDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}
Write-JsonFile -Path (Join-Path $objectiveManifestDir "qaas-artifact-manifest.json") -Value ([ordered]@{
    schema_version = 1
    campaign_id = "objective-fallback-regression"
    source_repository = "qaas-docs"
    status = "blocked_until_contract_review"
    promotion_state = "blocked"
    blocked_reason = "Preferred live weak validation is not passed."
    source_only_blockers = @([ordered]@{ blocker_id = "preferred-live-weak-missing"; blocker_type = "weak_model"; description = "Preferred live weak validation is missing." })
})
Write-JsonFile -Path (Join-Path $objectiveCoverageDir "objective-capability-coverage.json") -Value ([ordered]@{
    schema_version = 1
    objective_completion_status = "not_complete"
    completion_blockers = @("top_250_repositories", "weak_model_validation", "adversarial_weak_model_validation", "fail_closed_completion")
})
Write-JsonFile -Path (Join-Path $objectiveCoverageDir "promotion-candidate-index.json") -Value ([ordered]@{
    schema_version = 1
    promotion_index_status = "blocked"
    completion_ready = $false
    summary = [ordered]@{
        manifest_count = 1
        executable_manifest_count = 0
        promotable_candidate_count = 0
        blocked_by_dependency_gates_count = 0
        blocked_by_source_only_count = 1
        missing_template_validation_count = 1
        missing_build_validation_count = 1
        missing_live_validation_count = 1
        missing_airgapped_validation_count = 1
    }
})
Write-JsonFile -Path (Join-Path $objectiveCoverageDir "promotion-packet-summary.json") -Value ([ordered]@{
    schema_version = 1
    promotion_packet_status = "blocked"
    completion_ready = $false
    manifest_count = 1
    executable_manifest_count = 0
    packet_count = 0
})
Write-JsonFile -Path (Join-Path $objectiveCoverageDir "top-repo-promotion-triage.json") -Value ([ordered]@{
    schema_version = 1
    triage_status = "blocked_until_selected_contracts_are_promoted"
    completion_ready = $false
    contract_count = 250
    manifest_count = 250
    high_potential_count = 1
    contract_review_priority_count = 1
    by_triage_state = [ordered]@{ blocked = 250 }
})
Write-JsonFile -Path (Join-Path $objectiveBlockersDir "airgapped-live-latest.json") -Value ([ordered]@{
    validation_kind = "live_model_execution"
    weak_validation_passed = $false
    dry_run = $false
})
Write-JsonFile -Path (Join-Path $objectiveBlockersDir "copilot-fallback-latest.json") -Value ([ordered]@{
    validation_kind = "fallback_live_model_execution"
    weak_validation_passed = $true
    dry_run = $false
})
Write-JsonFile -Path (Join-Path $objectiveBlockersDir "weak-scenario-output-latest.json") -Value ([ordered]@{
    validation_kind = "live_scenario_model_execution"
    weak_validation_passed = $true
    dry_run = $false
})
Write-JsonFile -Path (Join-Path $objectiveBlockersDir "weak-adversarial-output-latest.json") -Value ([ordered]@{
    validation_kind = "live_adversarial_model_execution"
    weak_validation_passed = $true
    dry_run = $false
})
$objectiveFallbackResult = Invoke-CapturedCommand -Name "objective-fallback-does-not-complete" -FilePath "python" -Arguments @(
    (Join-Path $HarnessRoot "checks\Check-ObjectiveCompletionReadiness.py"),
    $objectiveGeneratedRoot,
    (Join-Path $objectiveCoverageDir "objective-capability-coverage.json"),
    $objectiveBlockersDir
)
Assert-ExitCode -Name "Objective completion keeps fallback weak evidence out of preferred gate" -Result $objectiveFallbackResult -ExpectedExitCode 0 -ExpectedText "completion_readiness=blocked"
$objectiveRecordPath = Join-Path $objectiveBlockersDir "objective-completion-readiness.json"
if (Test-Path -LiteralPath $objectiveRecordPath -PathType Leaf) {
    $objectiveRecord = Read-JsonFile -Path $objectiveRecordPath
    if (-not [bool]$objectiveRecord.live_weak_model_ready -and
        [bool]$objectiveRecord.fallback_weak_model_ready -and
        @($objectiveRecord.completion_blockers) -contains "live_weak_model_validation_not_passed") {
        Add-Pass "Objective completion record treats fallback weak pass as diagnostic only"
    } else {
        Add-Failure "Objective completion record incorrectly treated fallback as preferred readiness: $objectiveRecordPath"
    }
} else {
    Add-Failure "Objective completion fallback regression did not write readiness record: $objectiveRecordPath"
}

$forgedScenarioFixture = New-WeakOutputForgeryFixture -Root (Join-Path $fixtureRoot "forged-scenario-output")
$forgedScenarioResult = Invoke-WeakScenarioOutputCheck -Name "weak-scenario-output-forged-eligibility" -Fixture $forgedScenarioFixture
Assert-ExitCode -Name "Weak scenario output scorer rejects forged weak eligibility" -Result $forgedScenarioResult -ExpectedExitCode 1 -ExpectedText "not policy-eligible weak evidence"

$forgedAdversarialFixture = New-WeakOutputForgeryFixture -Root (Join-Path $fixtureRoot "forged-adversarial-output") -Adversarial
$forgedAdversarialResult = Invoke-WeakScenarioOutputCheck -Name "weak-adversarial-output-forged-eligibility" -Fixture $forgedAdversarialFixture -Adversarial
Assert-ExitCode -Name "Weak adversarial output scorer rejects forged weak eligibility" -Result $forgedAdversarialResult -ExpectedExitCode 1 -ExpectedText "not policy-eligible weak evidence"

$dryRunHeaderScenarioFixture = New-WeakOutputForgeryFixture -Root (Join-Path $fixtureRoot "dry-run-header-scenario-output") -DryRunHeaderSpoof
$dryRunHeaderScenarioIndexResult = Invoke-WeakScenarioLiveIndexCheck -Name "weak-scenario-live-index-dry-run-header-spoof" -Fixture $dryRunHeaderScenarioFixture
Assert-ExitCode -Name "Weak scenario live index rejects dry-run transcript header spoof" -Result $dryRunHeaderScenarioIndexResult -ExpectedExitCode 1 -ExpectedText "runner dry_run does not match transcript"
$dryRunHeaderScenarioResult = Invoke-WeakScenarioOutputCheck -Name "weak-scenario-output-dry-run-header-spoof" -Fixture $dryRunHeaderScenarioFixture
Assert-ExitCode -Name "Weak scenario output scorer rejects dry-run transcript header spoof" -Result $dryRunHeaderScenarioResult -ExpectedExitCode 1 -ExpectedText "header is marked DryRun"

$dryRunHeaderAdversarialFixture = New-WeakOutputForgeryFixture -Root (Join-Path $fixtureRoot "dry-run-header-adversarial-output") -Adversarial -DryRunHeaderSpoof
$dryRunHeaderAdversarialIndexResult = Invoke-WeakScenarioLiveIndexCheck -Name "weak-adversarial-live-index-dry-run-header-spoof" -Fixture $dryRunHeaderAdversarialFixture -Adversarial
Assert-ExitCode -Name "Weak adversarial live index rejects dry-run transcript header spoof" -Result $dryRunHeaderAdversarialIndexResult -ExpectedExitCode 1 -ExpectedText "runner dry_run does not match transcript"
$dryRunHeaderAdversarialResult = Invoke-WeakScenarioOutputCheck -Name "weak-adversarial-output-dry-run-header-spoof" -Fixture $dryRunHeaderAdversarialFixture -Adversarial
Assert-ExitCode -Name "Weak adversarial output scorer rejects dry-run transcript header spoof" -Result $dryRunHeaderAdversarialResult -ExpectedExitCode 1 -ExpectedText "header is marked DryRun"

$validSeed = Join-Path $fixtureRoot "valid-seed"
New-SeedFixture -SeedRoot $validSeed

$validResult = Invoke-SeedLifecycle -Name "valid-seed-lifecycle" -SeedRoot $validSeed
Assert-ExitCode -Name "valid seed lifecycle accepts blocked dry-run seed" -Result $validResult -ExpectedExitCode 0 -ExpectedText "Promotion seed lifecycle check passed."

$siblingRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\promotion-seed-evil"
[System.IO.Directory]::CreateDirectory($siblingRoot) | Out-Null
$sentinel = Join-Path $siblingRoot "sentinel.txt"
"do-not-delete" | Set-Content -LiteralPath $sentinel -Encoding UTF8
$pathGuardResult = Invoke-CapturedCommand -Name "path-prefix-seedroot-rejected" -FilePath "powershell" -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $HarnessRoot "scripts\generate-promotion-seed.ps1"),
    "-SeedRoot",
    $siblingRoot,
    "-HarnessRoot",
    $HarnessRoot
)
Assert-ExitCode -Name "SeedRoot prefix sibling rejected" -Result $pathGuardResult -ExpectedExitCode 1 -ExpectedText "SeedRoot must stay under"
if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf)) {
    Add-Failure "SeedRoot prefix sibling rejection deleted the sentinel: $sentinel"
} else {
    Add-Pass "SeedRoot prefix sibling sentinel preserved"
}

$dotDotSeedRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\promotion-seed\..\promotion-seed-evil\victim"
$dotDotResult = Invoke-CapturedCommand -Name "dotdot-seedroot-rejected" -FilePath "powershell" -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $HarnessRoot "scripts\generate-promotion-seed.ps1"),
    "-SeedRoot",
    $dotDotSeedRoot,
    "-HarnessRoot",
    $HarnessRoot
)
Assert-ExitCode -Name "SeedRoot normalized dotdot escape rejected" -Result $dotDotResult -ExpectedExitCode 1 -ExpectedText "SeedRoot must stay under"
if (-not (Test-Path -LiteralPath $sentinel -PathType Leaf)) {
    Add-Failure "SeedRoot dotdot rejection deleted the sentinel: $sentinel"
} else {
    Add-Pass "SeedRoot dotdot sentinel preserved"
}

$outsideDir = Join-Path $OutDir "outside"
[System.IO.Directory]::CreateDirectory($outsideDir) | Out-Null
$outsideYaml = Join-Path $outsideDir "test.qaas.yaml"
Get-Content -LiteralPath (Join-Path $validSeed "runner\ZappaPromotionSeed.Runner\test.qaas.yaml") -Raw | Set-Content -LiteralPath $outsideYaml -Encoding UTF8
$outsideArtifactSeed = Join-Path $fixtureRoot "outside-artifact-seed"
New-SeedFixture -SeedRoot $outsideArtifactSeed
$outsideManifestPath = Join-Path $outsideArtifactSeed "qaas-artifact-manifest.json"
$outsideManifest = Read-JsonFile -Path $outsideManifestPath
$outsideManifest.artifacts[0] = $outsideYaml
Write-JsonFile -Path $outsideManifestPath -Value $outsideManifest
$outsideResult = Invoke-SeedLifecycle -Name "outside-artifact-lifecycle" -SeedRoot $outsideArtifactSeed
Assert-ExitCode -Name "Lifecycle rejects artifact outside seed root" -Result $outsideResult -ExpectedExitCode 1 -ExpectedText "must stay under"

$dryRunPassedSeed = Join-Path $fixtureRoot "dry-run-passed-seed"
New-SeedFixture -SeedRoot $dryRunPassedSeed
$dryRunManifestPath = Join-Path $dryRunPassedSeed "qaas-artifact-manifest.json"
$dryRunManifest = Read-JsonFile -Path $dryRunManifestPath
$dryRunManifest.airgapped_validation.status = "passed"
$dryRunManifest.airgapped_validation.dry_run = $true
$dryRunManifest.airgapped_validation.exit_code = 0
Write-JsonFile -Path $dryRunManifestPath -Value $dryRunManifest
$dryRunResult = Invoke-SeedLifecycle -Name "dry-run-passed-lifecycle" -SeedRoot $dryRunPassedSeed
Assert-ExitCode -Name "Lifecycle rejects dry-run airgapped pass spoof" -Result $dryRunResult -ExpectedExitCode 1 -ExpectedText "dry_run false"

$singleModelPassedSeed = Join-Path $fixtureRoot "single-model-passed-seed"
New-SeedFixture -SeedRoot $singleModelPassedSeed
$singleModelManifestPath = Join-Path $singleModelPassedSeed "qaas-artifact-manifest.json"
$singleModelManifest = Read-JsonFile -Path $singleModelManifestPath
$singleModelActualTranscript = Join-Path $singleModelPassedSeed "airgapped\single-model-claude-copilot-id_gpt-3.5-turbo.md"
$singleModelSummary = $singleModelManifest.airgapped_validation.summary
$singleModelIndex = $singleModelManifest.airgapped_validation.index
Write-TextFile -Path $singleModelActualTranscript -Value @"
# weak-model-session transcript

Command: C:\Users\eldar\copilot-claude\claude.cmd id:gpt-3.5-turbo -p prompt
ExitCode: 0
ScenarioId: promotion-seed-qaas-docs-hello-world-http
ScenarioKind: scenario
PromptHashSha256: 0000
Harness: claude-copilot
Profile: airgapped
Model: id:gpt-3.5-turbo
DryRun: False

## stdout
intent_assumptions
docs_evidence
artifact_plan
validation_sequence
airgapped_result
strong_review
next_blocker
weak_validation_passed: true
dry_run: false

## stderr
"@
Write-TextFile -Path $singleModelSummary -Value @"
# Weak Model Validation Summary

Harness: claude-copilot
Profile: airgapped
Models: id:gpt-3.5-turbo
DryRun: False
Airgapped: True
- PASS exit 0: $singleModelActualTranscript
"@
Write-TextFile -Path $singleModelManifest.airgapped_validation.transcript -Value @"
Weak model validation complete.
Summary: $singleModelSummary
Transcript: $singleModelActualTranscript
"@
Write-JsonFile -Path $singleModelIndex -Value ([ordered]@{
    schema_version = 1
    validation_kind = "live_scenario_model_execution"
    records = @(
        [ordered]@{
            scenario_id = "promotion-seed-qaas-docs-hello-world-http"
            scenario_kind = "scenario"
            harness = "claude-copilot"
            profile = "airgapped"
            model = "id:gpt-3.5-turbo"
            weak_validation_eligible = $true
            dry_run = $false
            classification = "live_transcript_ready"
            weak_validation_passed = $false
            transcript_exit_code = 0
            summary = $singleModelSummary
            transcript = $singleModelActualTranscript
        }
    )
})
$singleModelManifest.airgapped_validation.status = "passed"
$singleModelManifest.airgapped_validation.dry_run = $false
$singleModelManifest.airgapped_validation.exit_code = 0
Set-JsonProperty -Object $singleModelManifest.airgapped_validation -Name "weak_validation_passed" -Value $true
Write-JsonFile -Path $singleModelManifestPath -Value $singleModelManifest
$singleModelPassedResult = Invoke-SeedLifecycle -Name "single-model-passed-lifecycle" -SeedRoot $singleModelPassedSeed
Assert-ExitCode -Name "Lifecycle rejects single-model passed airgapped seed spoof" -Result $singleModelPassedResult -ExpectedExitCode 1 -ExpectedText "missing preferred weak model"

$missingLiveMarkerSeed = Join-Path $fixtureRoot "missing-live-marker-seed"
New-SeedFixture -SeedRoot $missingLiveMarkerSeed
$missingLiveMarkerManifestPath = Join-Path $missingLiveMarkerSeed "qaas-artifact-manifest.json"
$missingLiveMarkerManifest = Read-JsonFile -Path $missingLiveMarkerManifestPath
$missingLiveMarkerManifest.airgapped_validation.status = "passed"
$missingLiveMarkerManifest.airgapped_validation.dry_run = $false
$missingLiveMarkerManifest.airgapped_validation.exit_code = 0
"DryRun: False`nAirgapped: True`n- FAIL exit 1: model did not satisfy contract" | Set-Content -LiteralPath $missingLiveMarkerManifest.airgapped_validation.summary -Encoding UTF8
"DryRun: False`nWeak model validation complete.`nSummary: $($missingLiveMarkerManifest.airgapped_validation.summary)`nTranscript: live.md" | Set-Content -LiteralPath $missingLiveMarkerManifest.airgapped_validation.transcript -Encoding UTF8
Write-JsonFile -Path $missingLiveMarkerManifestPath -Value $missingLiveMarkerManifest
$missingLiveMarkerResult = Invoke-SeedLifecycle -Name "missing-live-marker-lifecycle" -SeedRoot $missingLiveMarkerSeed
Assert-ExitCode -Name "Lifecycle rejects passed airgapped summary without live PASS marker" -Result $missingLiveMarkerResult -ExpectedExitCode 1 -ExpectedText "missing required live marker"

$outsideTranscriptSeed = Join-Path $fixtureRoot "outside-transcript-seed"
New-SeedFixture -SeedRoot $outsideTranscriptSeed
$outsideTranscriptPath = Join-Path $outsideDir "template-validation.transcript.txt"
"ExitCode: 0" | Set-Content -LiteralPath $outsideTranscriptPath -Encoding UTF8
$outsideTranscriptManifestPath = Join-Path $outsideTranscriptSeed "qaas-artifact-manifest.json"
$outsideTranscriptManifest = Read-JsonFile -Path $outsideTranscriptManifestPath
$outsideTranscriptManifest.template_validation.transcript = $outsideTranscriptPath
Write-JsonFile -Path $outsideTranscriptManifestPath -Value $outsideTranscriptManifest
$outsideTranscriptResult = Invoke-SeedLifecycle -Name "outside-transcript-lifecycle" -SeedRoot $outsideTranscriptSeed
Assert-ExitCode -Name "Lifecycle rejects validation transcript outside evidence root" -Result $outsideTranscriptResult -ExpectedExitCode 1 -ExpectedText "transcript must stay under"

$validPromotionWeakFixture = New-PromotionWeakEvidenceFixture -Root (Join-Path $fixtureRoot "promotion-weak-valid") -CaseName "valid"
$validPromotionIndexResult = Invoke-PromotionCandidateIndexCheck -Name "promotion-weak-valid-index" -Fixture $validPromotionWeakFixture
Assert-ExitCode -Name "Promotion index accepts policy-eligible weak evidence" -Result $validPromotionIndexResult -ExpectedExitCode 0 -ExpectedText "Promotion candidate index check passed"
$validPromotionReadinessResult = Invoke-PromotionReadinessCheck -Name "promotion-weak-valid-readiness" -Fixture $validPromotionWeakFixture
Assert-ExitCode -Name "Promotion readiness accepts policy-eligible weak evidence" -Result $validPromotionReadinessResult -ExpectedExitCode 0 -ExpectedText "Promotion readiness check passed"
$validPromotionPacketResult = Invoke-PromotionPacketCheck -Name "promotion-weak-valid-packet" -Fixture $validPromotionWeakFixture
Assert-ExitCode -Name "Promotion packet accepts policy-eligible weak evidence" -Result $validPromotionPacketResult -ExpectedExitCode 0 -ExpectedText "Promotion packet check passed"

$deterministicWeakFixtureRoot = Join-Path $fixtureRoot "promotion-deterministic-weak-blocked"
$deterministicWeakGeneratedRoot = Join-Path $deterministicWeakFixtureRoot "generated"
$deterministicWeakManifestDir = Join-Path $deterministicWeakGeneratedRoot "selected"
$deterministicWeakCoverageDir = Join-Path $deterministicWeakFixtureRoot "coverage"
foreach ($dir in @($deterministicWeakManifestDir, $deterministicWeakCoverageDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}
$deterministicYaml = Join-Path $deterministicWeakManifestDir "test.qaas.yaml"
$deterministicTemplateTranscript = Join-Path $deterministicWeakManifestDir "template.transcript.txt"
$deterministicBuildTranscript = Join-Path $deterministicWeakManifestDir "build.transcript.txt"
$deterministicLiveTranscript = Join-Path $deterministicWeakManifestDir "live.transcript.txt"
"# Status: blocked_until_template_live_airgapped_validation`nMetaData:`n  Team: Regression`n" | Set-Content -LiteralPath $deterministicYaml -Encoding UTF8
"ExitCode: 0" | Set-Content -LiteralPath $deterministicTemplateTranscript -Encoding UTF8
"ExitCode: 0" | Set-Content -LiteralPath $deterministicBuildTranscript -Encoding UTF8
"ExitCode: 0" | Set-Content -LiteralPath $deterministicLiveTranscript -Encoding UTF8
Write-JsonFile -Path (Join-Path $deterministicWeakManifestDir "qaas-artifact-manifest.json") -Value ([ordered]@{
    schema_version = 1
    campaign_id = "deterministic-weak-blocked-regression"
    source_repository = "selected/example"
    status = "blocked_until_repo_contract_review"
    promotion_state = "blocked"
    blocked_reason = "Deterministic QaaS evidence exists; live weak-model evidence is still missing."
    artifacts = @($deterministicYaml)
    dependency_gates = @(
        [ordered]@{ gate_id = "qaas-template"; required = $true; status = "passed"; evidence = @($deterministicTemplateTranscript); blocked_reason = "" },
        [ordered]@{ gate_id = "qaas-live-act-assert"; required = $true; status = "passed"; evidence = @($deterministicLiveTranscript); blocked_reason = "" },
        [ordered]@{ gate_id = "airgapped-validation"; required = $true; status = "blocked"; evidence = @(); blocked_reason = "Live weak-model validation has not passed." }
    )
    source_only_blockers = @([ordered]@{ blocker_id = "live-airgapped-weak-model-not-passed"; blocker_type = "weak_model"; description = "Live weak-model validation has not passed." })
    promotion_requirements = [ordered]@{
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
    template_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "template"; transcript = $deterministicTemplateTranscript }
    build_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "build"; transcript = $deterministicBuildTranscript }
    live_validation = [ordered]@{ status = "passed"; exit_code = 0; command = "live"; transcript = $deterministicLiveTranscript }
    airgapped_validation = [ordered]@{ required = $true; status = "not_run"; dry_run = $false; weak_validation_passed = $false }
})
$deterministicWeakIndexResult = Invoke-CapturedCommand -Name "promotion-deterministic-weak-blocked-index" -FilePath "python" -Arguments @(
    (Join-Path $HarnessRoot "checks\Check-PromotionCandidateIndex.py"),
    $deterministicWeakGeneratedRoot,
    $deterministicWeakCoverageDir
)
Assert-ExitCode -Name "Promotion index counts deterministic weak-blocked candidates without promotion" -Result $deterministicWeakIndexResult -ExpectedExitCode 0 -ExpectedText "Promotion candidate index check passed"
$deterministicWeakIndex = Read-JsonFile -Path (Join-Path $deterministicWeakCoverageDir "promotion-candidate-index.json")
if ([int]$deterministicWeakIndex.summary.deterministic_executable_candidate_count -eq 1 -and
    [int]$deterministicWeakIndex.summary.weak_blocked_deterministic_candidate_count -eq 1 -and
    [int]$deterministicWeakIndex.summary.executable_manifest_count -eq 0 -and
    [string]$deterministicWeakIndex.records[0].candidate_state -eq "deterministic_executable_weak_blocked") {
    Add-Pass "Promotion index separates deterministic weak-blocked candidates from policy executable manifests"
} else {
    Add-Failure "Promotion index did not classify deterministic weak-blocked candidate correctly: $($deterministicWeakCoverageDir)"
}

$promotionWeakSpoofCases = @(
    [pscustomobject]@{ CaseName = "partial-preferred"; ExpectedText = "missing preferred weak model attempts"; Label = "partial preferred-model promotion spoof" },
    [pscustomobject]@{ CaseName = "dry-run"; ExpectedText = "dry_run must be false"; Label = "dry-run airgapped promotion spoof" },
    [pscustomobject]@{ CaseName = "codex-route"; ExpectedText = "Harness must be claude-copilot"; Label = "Codex-route airgapped promotion spoof" },
    [pscustomobject]@{ CaseName = "missing-marker"; ExpectedText = "missing weak_validation_passed"; Label = "missing weak output marker promotion spoof" },
    [pscustomobject]@{ CaseName = "outside-transcript"; ExpectedText = "actual weak-model transcript must stay under"; Label = "outside weak transcript promotion spoof" }
)

foreach ($spoofCase in $promotionWeakSpoofCases) {
    $fixture = New-PromotionWeakEvidenceFixture -Root (Join-Path $fixtureRoot "promotion-weak-$($spoofCase.CaseName)") -CaseName $spoofCase.CaseName
    $indexResult = Invoke-PromotionCandidateIndexCheck -Name "promotion-weak-$($spoofCase.CaseName)-index" -Fixture $fixture
    Assert-ExitCode -Name "Promotion index rejects $($spoofCase.Label)" -Result $indexResult -ExpectedExitCode 1 -ExpectedText $spoofCase.ExpectedText
    $readinessResult = Invoke-PromotionReadinessCheck -Name "promotion-weak-$($spoofCase.CaseName)-readiness" -Fixture $fixture
    Assert-ExitCode -Name "Promotion readiness rejects $($spoofCase.Label)" -Result $readinessResult -ExpectedExitCode 1 -ExpectedText $spoofCase.ExpectedText
    $packetResult = Invoke-PromotionPacketCheck -Name "promotion-weak-$($spoofCase.CaseName)-packet" -Fixture $fixture
    Assert-ExitCode -Name "Promotion packet rejects $($spoofCase.Label)" -Result $packetResult -ExpectedExitCode 1 -ExpectedText $spoofCase.ExpectedText
}

$missingBlockerSeed = Join-Path $fixtureRoot "missing-blocker-seed"
New-SeedFixture -SeedRoot $missingBlockerSeed
$missingBlockerManifestPath = Join-Path $missingBlockerSeed "qaas-artifact-manifest.json"
$missingBlockerManifest = Read-JsonFile -Path $missingBlockerManifestPath
$missingBlockerManifest.source_only_blockers = @()
Write-JsonFile -Path $missingBlockerManifestPath -Value $missingBlockerManifest
$missingBlockerResult = Invoke-SeedLifecycle -Name "missing-blocker-lifecycle" -SeedRoot $missingBlockerSeed
Assert-ExitCode -Name "Lifecycle rejects blocked seed without source-only blocker" -Result $missingBlockerResult -ExpectedExitCode 1 -ExpectedText "source_only_blockers"

$schemaGeneratedRoot = Join-Path $OutDir "schema-generated"
$schemaSeedRoot = Join-Path $schemaGeneratedRoot "promotion-seed\qaas-docs-hello-world-http"
New-SeedFixture -SeedRoot $schemaSeedRoot
$schemaPassResult = Invoke-CapturedCommand -Name "schema-exact-seed-exception" -FilePath "python" -Arguments @(
    (Join-Path $HarnessRoot "checks\Check-QaaSYamlSchemaEvidence.py"),
    $schemaGeneratedRoot,
    "D:\QaaS\qaas-docs\docs\assets\schemas",
    (Join-Path $OutDir "schema-pass-coverage")
)
Assert-ExitCode -Name "YAML schema allows exact blocked promotion seed exception" -Result $schemaPassResult -ExpectedExitCode 0 -ExpectedText "QaaS YAML schema evidence check passed"

$schemaSpoofRoot = Join-Path $OutDir "schema-spoof-generated"
$schemaSpoofSeed = Join-Path $schemaSpoofRoot "spoofed-seed"
New-SeedFixture -SeedRoot $schemaSpoofSeed
$schemaSpoofResult = Invoke-CapturedCommand -Name "schema-spoofed-seed-rejected" -FilePath "python" -Arguments @(
    (Join-Path $HarnessRoot "checks\Check-QaaSYamlSchemaEvidence.py"),
    $schemaSpoofRoot,
    "D:\QaaS\qaas-docs\docs\assets\schemas",
    (Join-Path $OutDir "schema-spoof-coverage")
)
Assert-ExitCode -Name "YAML schema rejects spoofed promotion seed exception" -Result $schemaSpoofResult -ExpectedExitCode 1 -ExpectedText "blocked YAML lacks explicit blocked/placeholder marker"

$schemaMissingBlockerRoot = Join-Path $OutDir "schema-missing-blocker-generated"
$schemaMissingBlockerSeed = Join-Path $schemaMissingBlockerRoot "promotion-seed\qaas-docs-hello-world-http"
New-SeedFixture -SeedRoot $schemaMissingBlockerSeed
$schemaMissingBlockerManifestPath = Join-Path $schemaMissingBlockerSeed "qaas-artifact-manifest.json"
$schemaMissingBlockerManifest = Read-JsonFile -Path $schemaMissingBlockerManifestPath
$schemaMissingBlockerManifest.source_only_blockers = @()
Write-JsonFile -Path $schemaMissingBlockerManifestPath -Value $schemaMissingBlockerManifest
$schemaMissingBlockerResult = Invoke-CapturedCommand -Name "schema-missing-blocker-rejected" -FilePath "python" -Arguments @(
    (Join-Path $HarnessRoot "checks\Check-QaaSYamlSchemaEvidence.py"),
    $schemaMissingBlockerRoot,
    "D:\QaaS\qaas-docs\docs\assets\schemas",
    (Join-Path $OutDir "schema-missing-blocker-coverage")
)
Assert-ExitCode -Name "YAML schema rejects exact seed exception without blocker id" -Result $schemaMissingBlockerResult -ExpectedExitCode 1 -ExpectedText "blocked YAML lacks explicit blocked/placeholder marker"

$compileRoot = Join-Path $OutDir "compile-generated"
$compileCase = Join-Path $compileRoot "case"
[System.IO.Directory]::CreateDirectory($compileCase) | Out-Null
$declaredCs = Join-Path $compileCase "DeclaredArtifact.cs"
@"
namespace ZappaHarnessRegression;

public sealed class DeclaredArtifact
{
    public string Name => "ok";
}
"@ | Set-Content -LiteralPath $declaredCs -Encoding UTF8
"this is not valid csharp" | Set-Content -LiteralPath (Join-Path $compileCase "UnreferencedBrokenHostFile.cs") -Encoding UTF8
Write-JsonFile -Path (Join-Path $compileCase "qaas-artifact-manifest.json") -Value ([ordered]@{
    schema_version = 1
    artifacts = @($declaredCs)
})
$compilePassResult = Invoke-CapturedCommand -Name "compile-manifest-declared-only" -FilePath "powershell" -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $HarnessRoot "checks\Compile-GeneratedCSharp.ps1"),
    "-Root",
    $compileRoot,
    "-OutDir",
    (Join-Path $OutDir "compile-pass")
)
Assert-ExitCode -Name "Compile check ignores unmanifested generated host files" -Result $compilePassResult -ExpectedExitCode 0 -ExpectedText "manifest-declared files"

$compileMissingRoot = Join-Path $OutDir "compile-missing-generated"
$compileMissingCase = Join-Path $compileMissingRoot "case"
[System.IO.Directory]::CreateDirectory($compileMissingCase) | Out-Null
Write-JsonFile -Path (Join-Path $compileMissingCase "qaas-artifact-manifest.json") -Value ([ordered]@{
    schema_version = 1
    artifacts = @((Join-Path $compileMissingCase "MissingArtifact.cs"))
})
$compileMissingResult = Invoke-CapturedCommand -Name "compile-missing-artifact-rejected" -FilePath "powershell" -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $HarnessRoot "checks\Compile-GeneratedCSharp.ps1"),
    "-Root",
    $compileMissingRoot,
    "-OutDir",
    (Join-Path $OutDir "compile-missing")
)
Assert-ExitCode -Name "Compile check rejects missing manifest C# artifact" -Result $compileMissingResult -ExpectedExitCode 1 -ExpectedText "missing generated C# artifact"

$outsideCs = Join-Path $outsideDir "OutsideArtifact.cs"
"namespace ZappaHarnessRegression; public sealed class OutsideArtifact { }" | Set-Content -LiteralPath $outsideCs -Encoding UTF8
$compileOutsideRoot = Join-Path $OutDir "compile-outside-generated"
$compileOutsideCase = Join-Path $compileOutsideRoot "case"
[System.IO.Directory]::CreateDirectory($compileOutsideCase) | Out-Null
Write-JsonFile -Path (Join-Path $compileOutsideCase "qaas-artifact-manifest.json") -Value ([ordered]@{
    schema_version = 1
    artifacts = @($outsideCs)
})
$compileOutsideResult = Invoke-CapturedCommand -Name "compile-outside-artifact-rejected" -FilePath "powershell" -Arguments @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $HarnessRoot "checks\Compile-GeneratedCSharp.ps1"),
    "-Root",
    $compileOutsideRoot,
    "-OutDir",
    (Join-Path $OutDir "compile-outside")
)
Assert-ExitCode -Name "Compile check rejects manifest C# outside generated root" -Result $compileOutsideResult -ExpectedExitCode 1 -ExpectedText "outside generated root"

$selectedFixture = New-SelectedContractFixture -Root (Join-Path $fixtureRoot "selected-valid")
$selectedValidResult = Invoke-SelectedContractCheck -Name "selected-contract-valid" -Fixture $selectedFixture
Assert-ExitCode -Name "Selected contract checker accepts valid immutable text blob" -Result $selectedValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo contract check passed"

$selectedBadContentFixture = New-SelectedContractFixture -Root (Join-Path $fixtureRoot "selected-bad-content") -BadLocalContent
$selectedBadContentResult = Invoke-SelectedContractCheck -Name "selected-contract-bad-content" -Fixture $selectedBadContentFixture
Assert-ExitCode -Name "Selected contract checker rejects content SHA mismatch" -Result $selectedBadContentResult -ExpectedExitCode 1 -ExpectedText "git blob sha mismatch"

$selectedOutsideFixture = New-SelectedContractFixture -Root (Join-Path $fixtureRoot "selected-outside-output") -LocalPathInGeneratedRoot
$selectedOutsideResult = Invoke-SelectedContractCheck -Name "selected-contract-generated-output" -Fixture $selectedOutsideFixture
Assert-ExitCode -Name "Selected contract checker rejects generated-tests evidence path" -Result $selectedOutsideResult -ExpectedExitCode 1 -ExpectedText "outside allowed root"

$selectedExecutableFixture = New-SelectedContractFixture -Root (Join-Path $fixtureRoot "selected-executable-manifest") -PromotionState "executable"
$selectedExecutableResult = Invoke-SelectedContractCheck -Name "selected-contract-executable-manifest" -Fixture $selectedExecutableFixture
Assert-ExitCode -Name "Selected contract checker rejects executable top-repo manifest" -Result $selectedExecutableResult -ExpectedExitCode 1 -ExpectedText "must not leave top-repo manifest executable"

$candidateFixture = New-SelectedCandidateFixture -Root (Join-Path $fixtureRoot "candidate-valid")
$candidateValidResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-valid" -Fixture $candidateFixture
Assert-ExitCode -Name "Selected candidate checker accepts valid blocked json-server packet" -Result $candidateValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$flaskCandidateFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-valid")
$flaskCandidateValidResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-valid" -Fixture $flaskCandidateFixture
Assert-ExitCode -Name "Selected candidate checker accepts valid blocked Flask sidecar packet" -Result $flaskCandidateValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$fastApiCandidateFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-valid")
$fastApiCandidateValidResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-valid" -Fixture $fastApiCandidateFixture
Assert-ExitCode -Name "Selected candidate checker accepts valid blocked FastAPI JSON schema packet" -Result $fastApiCandidateValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$fastApiCandidateLifecycleFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-lifecycle-adopted") -LifecyclePassed
$fastApiCandidateLifecycleResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-lifecycle-adopted" -Fixture $fastApiCandidateLifecycleFixture
Assert-ExitCode -Name "Selected candidate checker accepts FastAPI lifecycle adoption while blocked" -Result $fastApiCandidateLifecycleResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$fastApiCandidateLifecycleCleanupSpoofFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-lifecycle-cleanup-spoof") -LifecyclePassed -LifecycleSummaryCleanupNotPassed
$fastApiCandidateLifecycleCleanupSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-lifecycle-cleanup-spoof" -Fixture $fastApiCandidateLifecycleCleanupSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI lifecycle cleanup spoof" -Result $fastApiCandidateLifecycleCleanupSpoofResult -ExpectedExitCode 1 -ExpectedText "cleanup_passed true"

$ginCandidateFixture = New-GinSelectedCandidateFixture -Root (Join-Path $fixtureRoot "gin-candidate-valid")
$ginCandidateValidResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-valid" -Fixture $ginCandidateFixture
Assert-ExitCode -Name "Selected candidate checker accepts valid blocked Gin JSON schema packet" -Result $ginCandidateValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$ginCandidateLifecycleFixture = New-GinSelectedCandidateFixture -Root (Join-Path $fixtureRoot "gin-candidate-lifecycle-adopted") -LifecyclePassed
$ginCandidateLifecycleResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-lifecycle-adopted" -Fixture $ginCandidateLifecycleFixture
Assert-ExitCode -Name "Selected candidate checker accepts Gin lifecycle adoption while blocked" -Result $ginCandidateLifecycleResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$fastApiMissingBodyFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-missing-body") -MissingBodyAssertion
$fastApiMissingBodyResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-missing-body" -Fixture $fastApiMissingBodyFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI missing body schema assertion" -Result $fastApiMissingBodyResult -ExpectedExitCode 1 -ExpectedText "Assertion: ObjectOutputJsonSchema"

$fastApiWrongRouteFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-wrong-route") -WrongRouteAndPort
$fastApiWrongRouteResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-wrong-route" -Fixture $fastApiWrongRouteFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI route or port drift" -Result $fastApiWrongRouteResult -ExpectedExitCode 1 -ExpectedText "Port: 8000"

$fastApiEmbeddedProcessFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-embedded-process") -EmbedProcessCommand
$fastApiEmbeddedProcessResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-embedded-process" -Fixture $fastApiEmbeddedProcessFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI process command in YAML" -Result $fastApiEmbeddedProcessResult -ExpectedExitCode 1 -ExpectedText "candidate YAML embeds external process command"

$fastApiMissingLifecycleFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-missing-lifecycle") -MissingLifecycleBlocker
$fastApiMissingLifecycleResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-missing-lifecycle" -Fixture $fastApiMissingLifecycleFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI lifecycle blocker removal" -Result $fastApiMissingLifecycleResult -ExpectedExitCode 1 -ExpectedText "fastapi-process-lifecycle-not-proven"

$fastApiQaaSSpoofFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-qaas-spoof") -QaaSValidationPassed
$fastApiQaaSSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-qaas-spoof" -Fixture $fastApiQaaSSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI manifest QaaS-validation spoof" -Result $fastApiQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "FastAPI candidate must not claim QaaS validation yet"

$fastApiRuntimeQaaSSpoofFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-runtime-qaas-spoof") -RuntimeQaaSValidationPassed
$fastApiRuntimeQaaSSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-runtime-qaas-spoof" -Fixture $fastApiRuntimeQaaSSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI runtime-plan QaaS-validation spoof" -Result $fastApiRuntimeQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "FastAPI candidate must not claim QaaS validation yet"

$fastApiBuildQaaSSpoofFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-build-qaas-spoof") -BuildValidationPassed
$fastApiBuildQaaSSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-build-qaas-spoof" -Fixture $fastApiBuildQaaSSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI build-validation spoof" -Result $fastApiBuildQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "FastAPI candidate must not claim QaaS validation yet"

$fastApiTemplateQaaSSpoofFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-template-qaas-spoof") -TemplateValidationPassed
$fastApiTemplateQaaSSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-template-qaas-spoof" -Fixture $fastApiTemplateQaaSSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI template-validation spoof" -Result $fastApiTemplateQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "FastAPI candidate must not claim QaaS validation yet"

$fastApiLiveQaaSSpoofFixture = New-FastApiSelectedCandidateFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-live-qaas-spoof") -LiveValidationPassed
$fastApiLiveQaaSSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-live-qaas-spoof" -Fixture $fastApiLiveQaaSSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI live-validation spoof" -Result $fastApiLiveQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "FastAPI candidate must not claim QaaS validation yet"

$ginMissingBodyFixture = New-GinSelectedCandidateFixture -Root (Join-Path $fixtureRoot "gin-candidate-missing-body") -MissingBodyAssertion
$ginMissingBodyResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-missing-body" -Fixture $ginMissingBodyFixture
Assert-ExitCode -Name "Selected candidate checker rejects Gin missing body schema assertion" -Result $ginMissingBodyResult -ExpectedExitCode 1 -ExpectedText "Assertion: ObjectOutputJsonSchema"

$ginWrongRouteFixture = New-GinSelectedCandidateFixture -Root (Join-Path $fixtureRoot "gin-candidate-wrong-route") -WrongRouteAndPort
$ginWrongRouteResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-wrong-route" -Fixture $ginWrongRouteFixture
Assert-ExitCode -Name "Selected candidate checker rejects Gin route or port drift" -Result $ginWrongRouteResult -ExpectedExitCode 1 -ExpectedText "Port: 8080"

$ginEmbeddedProcessFixture = New-GinSelectedCandidateFixture -Root (Join-Path $fixtureRoot "gin-candidate-embedded-process") -EmbedProcessCommand
$ginEmbeddedProcessResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-embedded-process" -Fixture $ginEmbeddedProcessFixture
Assert-ExitCode -Name "Selected candidate checker rejects Gin process command in YAML" -Result $ginEmbeddedProcessResult -ExpectedExitCode 1 -ExpectedText "candidate YAML embeds external process command"

$ginMissingLifecycleFixture = New-GinSelectedCandidateFixture -Root (Join-Path $fixtureRoot "gin-candidate-missing-lifecycle") -MissingLifecycleBlocker
$ginMissingLifecycleResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-missing-lifecycle" -Fixture $ginMissingLifecycleFixture
Assert-ExitCode -Name "Selected candidate checker rejects Gin lifecycle blocker removal" -Result $ginMissingLifecycleResult -ExpectedExitCode 1 -ExpectedText "gin-process-lifecycle-not-proven"

$ginBodyDriftFixture = New-GinSelectedCandidateFixture -Root (Join-Path $fixtureRoot "gin-candidate-body-drift") -BodySchemaDrift
$ginBodyDriftResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-body-drift" -Fixture $ginBodyDriftFixture
Assert-ExitCode -Name "Selected candidate checker rejects Gin response schema drift" -Result $ginBodyDriftResult -ExpectedExitCode 1 -ExpectedText "Gin JSON schema does not exactly match README response evidence"

$flaskActiveYamlFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-active-yaml") -UseActiveCustomAssertion
$flaskActiveYamlResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-active-yaml" -Fixture $flaskActiveYamlFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask custom assertion in active YAML" -Result $flaskActiveYamlResult -ExpectedExitCode 1 -ExpectedText "Flask active YAML must not use custom assertion before schema/template/live validation"

$flaskLooseHookFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-loose-hook") -LooseContainsHook
$flaskLooseHookResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-loose-hook" -Fixture $flaskLooseHookFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask loose text-body hook" -Result $flaskLooseHookResult -ExpectedExitCode 1 -ExpectedText "Flask custom hook must preserve exact byte-for-byte text semantics"

$flaskMissingTextBlockerFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-missing-text-blocker") -MissingTextBodyBlocker
$flaskMissingTextBlockerResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-missing-text-blocker" -Fixture $flaskMissingTextBlockerFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask text-body blocker removal" -Result $flaskMissingTextBlockerResult -ExpectedExitCode 1 -ExpectedText "flask-text-body-hook-not-template-validated"

$flaskWiredFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-wired-flag") -WiredIntoRunnerYaml
$flaskWiredResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-wired-flag" -Fixture $flaskWiredFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask sidecar wired flag spoof" -Result $flaskWiredResult -ExpectedExitCode 1 -ExpectedText "wired_into_runner_yaml must be false"

$flaskBadShaFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-bad-sha") -BadExpectedBodySha
$flaskBadShaResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-bad-sha" -Fixture $flaskBadShaFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask expected body SHA drift" -Result $flaskBadShaResult -ExpectedExitCode 1 -ExpectedText "expected_body_sha256 mismatch"

$flaskBadSourceFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-bad-source") -SourceOutsideAssertionPackets
$flaskBadSourceResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-bad-source" -Fixture $flaskBadSourceFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask hook source outside assertion-packets" -Result $flaskBadSourceResult -ExpectedExitCode 1 -ExpectedText "source must live under assertion-packets"

$flaskWeakSpoofFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-weak-spoof") -WeakValidationPassed
$flaskWeakSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-weak-spoof" -Fixture $flaskWeakSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask weak-validation spoof" -Result $flaskWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "Flask custom hook must not claim weak validation passed"

$flaskRuntimePacketSpoofFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-runtime-packet-spoof")
$flaskRuntimePlanPath = Join-Path $flaskRuntimePacketSpoofFixture.CandidateDir "candidate-runtime-plan.json"
$flaskRuntimePlan = Read-JsonFile -Path $flaskRuntimePlanPath
$flaskRuntimePlan.custom_assertion_packets[0].validation_records.live = "passed"
Write-JsonFile -Path $flaskRuntimePlanPath -Value $flaskRuntimePlan
$flaskRuntimePacketSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-runtime-packet-spoof" -Fixture $flaskRuntimePacketSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask runtime-plan packet validation spoof" -Result $flaskRuntimePacketSpoofResult -ExpectedExitCode 1 -ExpectedText "Flask runtime plan custom assertion packet validation live must be not_run"

$flaskHookPlanPacketSpoofFixture = New-FlaskSelectedCandidateFixture -Root (Join-Path $fixtureRoot "flask-candidate-hook-plan-packet-spoof")
$flaskHookPlanPath = Join-Path $flaskHookPlanPacketSpoofFixture.CandidateDir "assertion-packets\ExactHttpTextBody\custom-text-body-hook-plan.json"
$flaskHookPlan = Read-JsonFile -Path $flaskHookPlanPath
$flaskHookPlan.custom_assertion_packet.promotion_state = "executable"
Write-JsonFile -Path $flaskHookPlanPath -Value $flaskHookPlan
$flaskHookPlanPacketSpoofResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-hook-plan-packet-spoof" -Fixture $flaskHookPlanPacketSpoofFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask hook-plan packet promotion spoof" -Result $flaskHookPlanPacketSpoofResult -ExpectedExitCode 1 -ExpectedText "Flask custom hook plan packet promotion_state must be 'blocked'"

$candidateDir = Join-Path $candidateFixture.CandidateRoot "200-typicode-json-server"
$liveRoot = Join-Path $OutDir "selected-live-root"
[System.IO.Directory]::CreateDirectory($liveRoot) | Out-Null
$missingLiveSummary = Join-Path $OutDir "missing-selected-live-summary.json"
$missingLiveResult = Invoke-SelectedCandidateLiveCheck -Name "selected-live-missing-summary" -CandidateRoot $candidateFixture.CandidateRoot -CandidateDir $candidateDir -SummaryPath $missingLiveSummary -LiveRoot $liveRoot
Assert-ExitCode -Name "Selected live checker accepts missing summary as still blocked" -Result $missingLiveResult -ExpectedExitCode 0 -ExpectedText "no live QaaS evidence yet"

$failedLiveSummary = Join-Path $OutDir "failed-selected-live-summary.json"
Write-JsonFile -Path $failedLiveSummary -Value ([ordered]@{
    schema_version = 1
    status = "failed"
    repository = "typicode/json-server"
    promotion_state = "blocked"
    completion_ready = $false
    failure_reason = "fixture live failure"
})
$failedLiveResult = Invoke-SelectedCandidateLiveCheck -Name "selected-live-failed-summary" -CandidateRoot $candidateFixture.CandidateRoot -CandidateDir $candidateDir -SummaryPath $failedLiveSummary -LiveRoot $liveRoot
Assert-ExitCode -Name "Selected live checker rejects failed latest summary" -Result $failedLiveResult -ExpectedExitCode 1 -ExpectedText "Latest selected live validation failed"

$fastApiLiveValidFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-valid")
$fastApiLiveValidResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-valid" -Fixture $fastApiLiveValidFixture
Assert-ExitCode -Name "FastAPI live checker accepts adopted passed QaaS evidence" -Result $fastApiLiveValidResult -ExpectedExitCode 0 -ExpectedText "Selected FastAPI live check passed"

$fastApiCandidateLiveValidFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-live-valid")
$fastApiCandidateLiveValidResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-live-valid" -Fixture $fastApiCandidateLiveValidFixture
Assert-ExitCode -Name "Selected candidate checker accepts adopted FastAPI QaaS evidence" -Result $fastApiCandidateLiveValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$fastApiCandidateLiveFakeHashesFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-live-fake-hashes") -FakeHashes
$fastApiCandidateLiveFakeHashesResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-live-fake-hashes" -Fixture $fastApiCandidateLiveFakeHashesFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI fake equal live hashes" -Result $fastApiCandidateLiveFakeHashesResult -ExpectedExitCode 1 -ExpectedText "does not match actual file"

$fastApiCandidateLiveMixedManifestFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-candidate-live-mixed-manifest") -MixedManifestValidation
$fastApiCandidateLiveMixedManifestResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-fastapi-live-mixed-manifest" -Fixture $fastApiCandidateLiveMixedManifestFixture
Assert-ExitCode -Name "Selected candidate checker rejects FastAPI mixed live manifest records" -Result $fastApiCandidateLiveMixedManifestResult -ExpectedExitCode 1 -ExpectedText "must equal live summary record"

$fastApiLiveFailedFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-failed") -FailedSummary
$fastApiLiveFailedResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-failed" -Fixture $fastApiLiveFailedFixture
Assert-ExitCode -Name "FastAPI live checker rejects failed latest summary" -Result $fastApiLiveFailedResult -ExpectedExitCode 1 -ExpectedText "Latest FastAPI selected live validation failed"

$fastApiLiveStaleFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-stale") -StaleManifest
$fastApiLiveStaleResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-stale" -Fixture $fastApiLiveStaleFixture
Assert-ExitCode -Name "FastAPI live checker rejects stale passed summary without adoption" -Result $fastApiLiveStaleResult -ExpectedExitCode 1 -ExpectedText "manifest_updated true"

$fastApiLiveWrongRepoFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-wrong-repo") -WrongRepo
$fastApiLiveWrongRepoResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-wrong-repo" -Fixture $fastApiLiveWrongRepoFixture
Assert-ExitCode -Name "FastAPI live checker rejects wrong repository summary" -Result $fastApiLiveWrongRepoResult -ExpectedExitCode 1 -ExpectedText "repository mismatch"

$fastApiLiveWeakSpoofFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-weak-spoof") -WeakValidationPassed
$fastApiLiveWeakSpoofResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-weak-spoof" -Fixture $fastApiLiveWeakSpoofFixture
Assert-ExitCode -Name "FastAPI live checker rejects weak-validation spoof" -Result $fastApiLiveWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$fastApiLiveWrongBodyFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-wrong-body") -WrongBody
$fastApiLiveWrongBodyResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-wrong-body" -Fixture $fastApiLiveWrongBodyFixture
Assert-ExitCode -Name "FastAPI live checker rejects response body drift" -Result $fastApiLiveWrongBodyResult -ExpectedExitCode 1 -ExpectedText "must prove HTTP 200 response contract"

$fastApiLiveMissingSchemaMarkerFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-missing-schema-marker") -MissingObjectSchemaMarker
$fastApiLiveMissingSchemaMarkerResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-missing-schema-marker" -Fixture $fastApiLiveMissingSchemaMarkerFixture
Assert-ExitCode -Name "FastAPI live checker rejects missing ObjectOutputJsonSchema marker" -Result $fastApiLiveMissingSchemaMarkerResult -ExpectedExitCode 1 -ExpectedText "ObjectOutputJsonSchema"

$fastApiLiveDoubleSlashFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-double-slash") -DoubleSlashUrl
$fastApiLiveDoubleSlashResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-double-slash" -Fixture $fastApiLiveDoubleSlashFixture
Assert-ExitCode -Name "FastAPI live checker rejects double-slash QaaS URL" -Result $fastApiLiveDoubleSlashResult -ExpectedExitCode 1 -ExpectedText "double-slash route"

$fastApiLiveFakeHashesFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-fake-hashes") -FakeHashes
$fastApiLiveFakeHashesResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-fake-hashes" -Fixture $fastApiLiveFakeHashesFixture
Assert-ExitCode -Name "FastAPI live checker rejects fake equal source hashes" -Result $fastApiLiveFakeHashesResult -ExpectedExitCode 1 -ExpectedText "does not match actual file"

$fastApiLiveMixedManifestFixture = New-FastApiLiveFixture -Root (Join-Path $fixtureRoot "fastapi-live-mixed-manifest") -MixedManifestValidation
$fastApiLiveMixedManifestResult = Invoke-FastApiSelectedCandidateLiveCheck -Name "fastapi-live-mixed-manifest" -Fixture $fastApiLiveMixedManifestFixture
Assert-ExitCode -Name "FastAPI live checker rejects mixed manifest validation records" -Result $fastApiLiveMixedManifestResult -ExpectedExitCode 1 -ExpectedText "must equal live summary record"

$ginLiveValidFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-valid")
$ginLiveValidResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-valid" -Fixture $ginLiveValidFixture
Assert-ExitCode -Name "Gin live checker accepts adopted passed QaaS evidence" -Result $ginLiveValidResult -ExpectedExitCode 0 -ExpectedText "Selected Gin live check passed"

$ginCandidateLiveValidFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-candidate-live-valid")
$ginCandidateLiveValidResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-gin-live-valid" -Fixture $ginCandidateLiveValidFixture
Assert-ExitCode -Name "Selected candidate checker accepts adopted Gin QaaS evidence" -Result $ginCandidateLiveValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$ginLiveFailedFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-failed") -FailedSummary
$ginLiveFailedResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-failed" -Fixture $ginLiveFailedFixture
Assert-ExitCode -Name "Gin live checker rejects failed latest summary" -Result $ginLiveFailedResult -ExpectedExitCode 1 -ExpectedText "Latest Gin selected live validation failed"

$ginLiveStaleFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-stale") -StaleManifest
$ginLiveStaleResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-stale" -Fixture $ginLiveStaleFixture
Assert-ExitCode -Name "Gin live checker rejects stale passed summary without adoption" -Result $ginLiveStaleResult -ExpectedExitCode 1 -ExpectedText "manifest_updated true"

$ginLiveWrongRepoFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-wrong-repo") -WrongRepo
$ginLiveWrongRepoResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-wrong-repo" -Fixture $ginLiveWrongRepoFixture
Assert-ExitCode -Name "Gin live checker rejects wrong repository summary" -Result $ginLiveWrongRepoResult -ExpectedExitCode 1 -ExpectedText "repository mismatch"

$ginLiveWeakSpoofFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-weak-spoof") -WeakValidationPassed
$ginLiveWeakSpoofResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-weak-spoof" -Fixture $ginLiveWeakSpoofFixture
Assert-ExitCode -Name "Gin live checker rejects weak-validation spoof" -Result $ginLiveWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$ginLiveWrongBodyFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-wrong-body") -WrongBody
$ginLiveWrongBodyResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-wrong-body" -Fixture $ginLiveWrongBodyFixture
Assert-ExitCode -Name "Gin live checker rejects response body drift" -Result $ginLiveWrongBodyResult -ExpectedExitCode 1 -ExpectedText "does not match README-backed contract"

$ginLiveDoubleSlashFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-double-slash") -DoubleSlashUrl
$ginLiveDoubleSlashResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-double-slash" -Fixture $ginLiveDoubleSlashFixture
Assert-ExitCode -Name "Gin live checker rejects double-slash QaaS URL" -Result $ginLiveDoubleSlashResult -ExpectedExitCode 1 -ExpectedText "double-slash route"

$ginLiveFakeHashesFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-fake-hashes") -FakeHashes
$ginLiveFakeHashesResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-fake-hashes" -Fixture $ginLiveFakeHashesFixture
Assert-ExitCode -Name "Gin live checker rejects fake source hashes" -Result $ginLiveFakeHashesResult -ExpectedExitCode 1 -ExpectedText "does not match actual file"

$ginLiveMixedManifestFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-mixed-manifest") -MixedManifestValidation
$ginLiveMixedManifestResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-mixed-manifest" -Fixture $ginLiveMixedManifestFixture
Assert-ExitCode -Name "Gin live checker rejects mixed manifest validation records" -Result $ginLiveMixedManifestResult -ExpectedExitCode 1 -ExpectedText "must equal live summary record"

$ginLiveWrongGoSourceFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-wrong-go-source") -WrongGoSource
$ginLiveWrongGoSourceResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-wrong-go-source" -Fixture $ginLiveWrongGoSourceFixture
Assert-ExitCode -Name "Gin live checker rejects ambient Go source spoof" -Result $ginLiveWrongGoSourceResult -ExpectedExitCode 1 -ExpectedText "must use managed_go_toolchain"

$ginLiveEnvMismatchFixture = New-GinLiveFixture -Root (Join-Path $fixtureRoot "gin-live-env-mismatch") -EnvMismatch
$ginLiveEnvMismatchResult = Invoke-GinSelectedCandidateLiveCheck -Name "gin-live-env-mismatch" -Fixture $ginLiveEnvMismatchFixture
Assert-ExitCode -Name "Gin live checker rejects go-env path drift" -Result $ginLiveEnvMismatchResult -ExpectedExitCode 1 -ExpectedText "go-env GOROOT mismatch"

$flaskLiveValidFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-valid")
$flaskLiveValidResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-valid" -Fixture $flaskLiveValidFixture
Assert-ExitCode -Name "Flask live checker accepts adopted passed QaaS evidence" -Result $flaskLiveValidResult -ExpectedExitCode 0 -ExpectedText "Selected Flask live check passed"

$flaskCandidateLiveValidFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-candidate-live-valid")
$flaskCandidateLiveValidResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-live-valid" -Fixture $flaskCandidateLiveValidFixture
Assert-ExitCode -Name "Selected candidate checker accepts adopted Flask QaaS evidence" -Result $flaskCandidateLiveValidResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$flaskCandidateLiveFakeHashesFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-candidate-live-fake-hashes") -FakeHashes
$flaskCandidateLiveFakeHashesResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-live-fake-hashes" -Fixture $flaskCandidateLiveFakeHashesFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask fake live hashes" -Result $flaskCandidateLiveFakeHashesResult -ExpectedExitCode 1 -ExpectedText "does not match actual file"

$flaskCandidateLiveMixedManifestFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-candidate-live-mixed-manifest") -MixedManifestValidation
$flaskCandidateLiveMixedManifestResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-live-mixed-manifest" -Fixture $flaskCandidateLiveMixedManifestFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask mixed live manifest records" -Result $flaskCandidateLiveMixedManifestResult -ExpectedExitCode 1 -ExpectedText "must equal live summary record"

$flaskCandidateLiveRuntimeHookMismatchFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-candidate-live-runtime-hook-mismatch") -RuntimeHookMismatch
$flaskCandidateLiveRuntimeHookMismatchResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-live-runtime-hook-mismatch" -Fixture $flaskCandidateLiveRuntimeHookMismatchFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask runtime hook status mismatch" -Result $flaskCandidateLiveRuntimeHookMismatchResult -ExpectedExitCode 1 -ExpectedText "custom_text_body_assertion status"

$flaskCandidateLiveNoLifecycleFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-candidate-live-no-lifecycle") -SkipLifecycleAdoption
$flaskCandidateLiveNoLifecycleResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-flask-live-no-lifecycle" -Fixture $flaskCandidateLiveNoLifecycleFixture
Assert-ExitCode -Name "Selected candidate checker rejects Flask QaaS live before lifecycle" -Result $flaskCandidateLiveNoLifecycleResult -ExpectedExitCode 1 -ExpectedText "before lifecycle_validation is passed"

$flaskLiveFailedFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-failed") -FailedSummary
$flaskLiveFailedResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-failed" -Fixture $flaskLiveFailedFixture
Assert-ExitCode -Name "Flask live checker rejects failed latest summary" -Result $flaskLiveFailedResult -ExpectedExitCode 1 -ExpectedText "Latest Flask selected live validation failed"

$flaskLiveStaleFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-stale") -StaleManifest
$flaskLiveStaleResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-stale" -Fixture $flaskLiveStaleFixture
Assert-ExitCode -Name "Flask live checker rejects stale passed summary without adoption" -Result $flaskLiveStaleResult -ExpectedExitCode 1 -ExpectedText "manifest_updated true"

$flaskLiveWrongRepoFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-wrong-repo") -WrongRepo
$flaskLiveWrongRepoResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-wrong-repo" -Fixture $flaskLiveWrongRepoFixture
Assert-ExitCode -Name "Flask live checker rejects wrong repository summary" -Result $flaskLiveWrongRepoResult -ExpectedExitCode 1 -ExpectedText "repository mismatch"

$flaskLiveWeakSpoofFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-weak-spoof") -WeakValidationPassed
$flaskLiveWeakSpoofResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-weak-spoof" -Fixture $flaskLiveWeakSpoofFixture
Assert-ExitCode -Name "Flask live checker rejects weak-validation spoof" -Result $flaskLiveWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$flaskLiveWrongBodyFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-wrong-body") -WrongBody
$flaskLiveWrongBodyResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-wrong-body" -Fixture $flaskLiveWrongBodyFixture
Assert-ExitCode -Name "Flask live checker rejects response body drift" -Result $flaskLiveWrongBodyResult -ExpectedExitCode 1 -ExpectedText "must prove HTTP 200 response contract"

$flaskLiveMissingExactFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-missing-exact-marker") -MissingExactMarker
$flaskLiveMissingExactResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-missing-exact-marker" -Fixture $flaskLiveMissingExactFixture
Assert-ExitCode -Name "Flask live checker rejects missing ExactHttpTextBody discovery marker" -Result $flaskLiveMissingExactResult -ExpectedExitCode 1 -ExpectedText "ExactHttpTextBody"

$flaskLiveDoubleSlashFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-double-slash") -DoubleSlashUrl
$flaskLiveDoubleSlashResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-double-slash" -Fixture $flaskLiveDoubleSlashFixture
Assert-ExitCode -Name "Flask live checker rejects double-slash QaaS URL" -Result $flaskLiveDoubleSlashResult -ExpectedExitCode 1 -ExpectedText "double-slash root URL"

$flaskLiveMissingRouteFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-missing-route-empty") -MissingRouteEmpty
$flaskLiveMissingRouteResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-missing-route-empty" -Fixture $flaskLiveMissingRouteFixture
Assert-ExitCode -Name "Flask live checker rejects staged YAML without empty root route" -Result $flaskLiveMissingRouteResult -ExpectedExitCode 1 -ExpectedText "Route: ''"

$flaskLiveSourceActiveFixture = New-FlaskLiveFixture -Root (Join-Path $fixtureRoot "flask-live-source-active") -SourceActiveCustomAssertion
$flaskLiveSourceActiveResult = Invoke-FlaskSelectedCandidateLiveCheck -Name "flask-live-source-active" -Fixture $flaskLiveSourceActiveFixture
Assert-ExitCode -Name "Flask live checker rejects source YAML ExactHttpTextBody activation" -Result $flaskLiveSourceActiveResult -ExpectedExitCode 1 -ExpectedText "source candidate YAML must not activate ExactHttpTextBody"

$flaskLifecycleFixture = New-FlaskLifecycleFixture -Root (Join-Path $fixtureRoot "flask-lifecycle-valid")
$flaskLifecycleResult = Invoke-SelectedCandidateLifecycleCheck -Name "flask-lifecycle-valid" -Fixture $flaskLifecycleFixture
Assert-ExitCode -Name "Selected lifecycle checker accepts blocked Flask lifecycle adoption" -Result $flaskLifecycleResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate lifecycle check passed"

$flaskLifecycleWeakSpoofFixture = New-FlaskLifecycleFixture -Root (Join-Path $fixtureRoot "flask-lifecycle-weak-spoof") -WeakValidationPassed
$flaskLifecycleWeakSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "flask-lifecycle-weak-spoof" -Fixture $flaskLifecycleWeakSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Flask weak-validation spoof" -Result $flaskLifecycleWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$flaskLifecycleMissingTextBlockerFixture = New-FlaskLifecycleFixture -Root (Join-Path $fixtureRoot "flask-lifecycle-missing-text-blocker") -MissingTextBodyBlocker
$flaskLifecycleMissingTextBlockerResult = Invoke-SelectedCandidateLifecycleCheck -Name "flask-lifecycle-missing-text-blocker" -Fixture $flaskLifecycleMissingTextBlockerFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Flask text-body blocker removal" -Result $flaskLifecycleMissingTextBlockerResult -ExpectedExitCode 1 -ExpectedText "flask-text-body-hook-not-template-validated"

$flaskLifecycleQaaSSpoofFixture = New-FlaskLifecycleFixture -Root (Join-Path $fixtureRoot "flask-lifecycle-qaas-spoof") -QaaSValidationPassed
$flaskLifecycleQaaSSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "flask-lifecycle-qaas-spoof" -Fixture $flaskLifecycleQaaSSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Flask QaaS-validation spoof" -Result $flaskLifecycleQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim partial QaaS template/live validation passed"

$flaskLifecycleWrongRepoFixture = New-FlaskLifecycleFixture -Root (Join-Path $fixtureRoot "flask-lifecycle-wrong-repo") -JsonServerSummary
$flaskLifecycleWrongRepoResult = Invoke-SelectedCandidateLifecycleCheck -Name "flask-lifecycle-wrong-repo" -Fixture $flaskLifecycleWrongRepoFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects json-server summary applied to Flask" -Result $flaskLifecycleWrongRepoResult -ExpectedExitCode 1 -ExpectedText "repository mismatch"

$flaskLifecycleBadShaFixture = New-FlaskLifecycleFixture -Root (Join-Path $fixtureRoot "flask-lifecycle-bad-response-sha") -BadResponseSha
$flaskLifecycleBadShaResult = Invoke-SelectedCandidateLifecycleCheck -Name "flask-lifecycle-bad-response-sha" -Fixture $flaskLifecycleBadShaFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Flask forged response hash" -Result $flaskLifecycleBadShaResult -ExpectedExitCode 1 -ExpectedText "response_body_sha256 must match actual response file"

$flaskLifecycleMissingManagedVenvFixture = New-FlaskLifecycleFixture -Root (Join-Path $fixtureRoot "flask-lifecycle-missing-managed-venv") -MissingManagedVenvEvidence
$flaskLifecycleMissingManagedVenvResult = Invoke-SelectedCandidateLifecycleCheck -Name "flask-lifecycle-missing-managed-venv" -Fixture $flaskLifecycleMissingManagedVenvFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Flask missing managed-venv evidence" -Result $flaskLifecycleMissingManagedVenvResult -ExpectedExitCode 1 -ExpectedText "pip_install_stdout"

$expressLifecycleFixture = New-ExpressLifecycleFixture -Root (Join-Path $fixtureRoot "express-lifecycle-valid")
$expressLifecycleResult = Invoke-SelectedCandidateLifecycleCheck -Name "express-lifecycle-valid" -Fixture $expressLifecycleFixture
Assert-ExitCode -Name "Selected lifecycle checker accepts blocked Express lifecycle adoption" -Result $expressLifecycleResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate lifecycle check passed"

$expressLifecycleWeakSpoofFixture = New-ExpressLifecycleFixture -Root (Join-Path $fixtureRoot "express-lifecycle-weak-spoof") -WeakValidationPassed
$expressLifecycleWeakSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "express-lifecycle-weak-spoof" -Fixture $expressLifecycleWeakSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Express weak-validation spoof" -Result $expressLifecycleWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$expressLifecycleQaaSSpoofFixture = New-ExpressLifecycleFixture -Root (Join-Path $fixtureRoot "express-lifecycle-qaas-spoof") -QaaSValidationPassed
$expressLifecycleQaaSSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "express-lifecycle-qaas-spoof" -Fixture $expressLifecycleQaaSSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Express QaaS-validation spoof" -Result $expressLifecycleQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim partial QaaS template/live validation passed"

$expressLifecycleWrongBodyFixture = New-ExpressLifecycleFixture -Root (Join-Path $fixtureRoot "express-lifecycle-wrong-body") -WrongBody
$expressLifecycleWrongBodyResult = Invoke-SelectedCandidateLifecycleCheck -Name "express-lifecycle-wrong-body" -Fixture $expressLifecycleWrongBodyFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Express response body drift" -Result $expressLifecycleWrongBodyResult -ExpectedExitCode 1 -ExpectedText "Express lifecycle response body must match README-backed exact text"

$expressLifecycleBadShaFixture = New-ExpressLifecycleFixture -Root (Join-Path $fixtureRoot "express-lifecycle-bad-response-sha") -BadResponseSha
$expressLifecycleBadShaResult = Invoke-SelectedCandidateLifecycleCheck -Name "express-lifecycle-bad-response-sha" -Fixture $expressLifecycleBadShaFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Express forged response hash" -Result $expressLifecycleBadShaResult -ExpectedExitCode 1 -ExpectedText "response_body_sha256 must match actual response file"

$expressLifecycleMissingPackageFixture = New-ExpressLifecycleFixture -Root (Join-Path $fixtureRoot "express-lifecycle-missing-package") -MissingPackageEvidence
$expressLifecycleMissingPackageResult = Invoke-SelectedCandidateLifecycleCheck -Name "express-lifecycle-missing-package" -Fixture $expressLifecycleMissingPackageFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Express missing package evidence" -Result $expressLifecycleMissingPackageResult -ExpectedExitCode 1 -ExpectedText "installed_express_package"

$expressLiveValidFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-valid")
$expressLiveValidResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-valid" -Fixture $expressLiveValidFixture
Assert-ExitCode -Name "Express live checker accepts adopted passed QaaS evidence" -Result $expressLiveValidResult -ExpectedExitCode 0 -ExpectedText "Selected Express live check passed"

$expressLiveWeakSpoofFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-weak-spoof") -WeakValidationPassed
$expressLiveWeakSpoofResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-weak-spoof" -Fixture $expressLiveWeakSpoofFixture
Assert-ExitCode -Name "Express live checker rejects weak-validation spoof" -Result $expressLiveWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$expressLiveFailedFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-failed") -FailedSummary
$expressLiveFailedResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-failed" -Fixture $expressLiveFailedFixture
Assert-ExitCode -Name "Express live checker rejects failed latest summary" -Result $expressLiveFailedResult -ExpectedExitCode 1 -ExpectedText "Latest Express selected live validation failed"

$expressLiveSourceActiveFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-source-active") -SourceActiveCustomAssertion
$expressLiveSourceActiveResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-source-active" -Fixture $expressLiveSourceActiveFixture
Assert-ExitCode -Name "Express live checker rejects source YAML ExactHttpTextBody activation" -Result $expressLiveSourceActiveResult -ExpectedExitCode 1 -ExpectedText "source candidate YAML must not activate ExactHttpTextBody"

$expressLiveDoubleSlashFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-double-slash") -DoubleSlashUrl
$expressLiveDoubleSlashResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-double-slash" -Fixture $expressLiveDoubleSlashFixture
Assert-ExitCode -Name "Express live checker rejects double-slash QaaS URL" -Result $expressLiveDoubleSlashResult -ExpectedExitCode 1 -ExpectedText "double-slash root URL"

$expressLiveFakeHashesFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-fake-hashes") -FakeHashes
$expressLiveFakeHashesResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-fake-hashes" -Fixture $expressLiveFakeHashesFixture
Assert-ExitCode -Name "Express live checker rejects forged source/package hashes" -Result $expressLiveFakeHashesResult -ExpectedExitCode 1 -ExpectedText "does not match actual file"

$expressLiveMissingPackageFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-missing-package") -MissingPackageEvidence
$expressLiveMissingPackageResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-missing-package" -Fixture $expressLiveMissingPackageFixture
Assert-ExitCode -Name "Express live checker rejects missing installed package evidence" -Result $expressLiveMissingPackageResult -ExpectedExitCode 1 -ExpectedText "installed_express_package"

$expressLiveWrongBodyFixture = New-ExpressLiveFixture -Root (Join-Path $fixtureRoot "express-live-wrong-body") -WrongBody
$expressLiveWrongBodyResult = Invoke-ExpressSelectedCandidateLiveCheck -Name "express-live-wrong-body" -Fixture $expressLiveWrongBodyFixture
Assert-ExitCode -Name "Express live checker rejects response body drift" -Result $expressLiveWrongBodyResult -ExpectedExitCode 1 -ExpectedText "must prove HTTP 200 response contract"

$fastApiLifecycleFixture = New-FastApiLifecycleFixture -Root (Join-Path $fixtureRoot "fastapi-lifecycle-valid")
$fastApiLifecycleResult = Invoke-SelectedCandidateLifecycleCheck -Name "fastapi-lifecycle-valid" -Fixture $fastApiLifecycleFixture
Assert-ExitCode -Name "Selected lifecycle checker accepts blocked FastAPI lifecycle adoption" -Result $fastApiLifecycleResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate lifecycle check passed"

$fastApiLifecycleStaleSummaryFixture = New-FastApiLifecycleFixture -Root (Join-Path $fixtureRoot "fastapi-lifecycle-stale-summary")
$fastApiLifecycleStaleManifestPath = Join-Path $fastApiLifecycleStaleSummaryFixture.CandidateDir "qaas-artifact-manifest.json"
$fastApiLifecycleStaleManifest = Read-JsonFile -Path $fastApiLifecycleStaleManifestPath
$fastApiLifecycleStaleManifest.PSObject.Properties.Remove("lifecycle_validation")
Write-JsonFile -Path $fastApiLifecycleStaleManifestPath -Value $fastApiLifecycleStaleManifest
$fastApiLifecycleStaleSummaryResult = Invoke-SelectedCandidateLifecycleCheck -Name "fastapi-lifecycle-stale-summary" -Fixture $fastApiLifecycleStaleSummaryFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects stale passed FastAPI summary without manifest adoption" -Result $fastApiLifecycleStaleSummaryResult -ExpectedExitCode 1 -ExpectedText "has not been adopted"

$fastApiLifecycleWeakSpoofFixture = New-FastApiLifecycleFixture -Root (Join-Path $fixtureRoot "fastapi-lifecycle-weak-spoof") -WeakValidationPassed
$fastApiLifecycleWeakSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "fastapi-lifecycle-weak-spoof" -Fixture $fastApiLifecycleWeakSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects FastAPI weak-validation spoof" -Result $fastApiLifecycleWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$fastApiLifecycleQaaSSpoofFixture = New-FastApiLifecycleFixture -Root (Join-Path $fixtureRoot "fastapi-lifecycle-qaas-spoof") -QaaSValidationPassed
$fastApiLifecycleQaaSSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "fastapi-lifecycle-qaas-spoof" -Fixture $fastApiLifecycleQaaSSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects FastAPI QaaS-validation spoof" -Result $fastApiLifecycleQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim partial QaaS template/live validation passed"

$fastApiLifecycleWrongBodyFixture = New-FastApiLifecycleFixture -Root (Join-Path $fixtureRoot "fastapi-lifecycle-wrong-body") -WrongBody
$fastApiLifecycleWrongBodyResult = Invoke-SelectedCandidateLifecycleCheck -Name "fastapi-lifecycle-wrong-body" -Fixture $fastApiLifecycleWrongBodyFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects FastAPI response body drift" -Result $fastApiLifecycleWrongBodyResult -ExpectedExitCode 1 -ExpectedText "FastAPI lifecycle response must exactly match README-backed JSON body"

$fastApiLifecycleWrongRepoFixture = New-FastApiLifecycleFixture -Root (Join-Path $fixtureRoot "fastapi-lifecycle-wrong-repo") -WrongRepo
$fastApiLifecycleWrongRepoResult = Invoke-SelectedCandidateLifecycleCheck -Name "fastapi-lifecycle-wrong-repo" -Fixture $fastApiLifecycleWrongRepoFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects wrong repository summary applied to FastAPI" -Result $fastApiLifecycleWrongRepoResult -ExpectedExitCode 1 -ExpectedText "repository mismatch"

$fastApiLifecycleWrongSummaryFixture = New-FastApiLifecycleFixture -Root (Join-Path $fixtureRoot "fastapi-lifecycle-wrong-summary-manifest") -WrongSummaryManifestPath
$fastApiLifecycleWrongSummaryResult = Invoke-SelectedCandidateLifecycleCheck -Name "fastapi-lifecycle-wrong-summary-manifest" -Fixture $fastApiLifecycleWrongSummaryFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects FastAPI summary bound to wrong manifest" -Result $fastApiLifecycleWrongSummaryResult -ExpectedExitCode 1 -ExpectedText "Lifecycle record manifest path"

$ginLifecycleFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-valid")
$ginLifecycleResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-valid" -Fixture $ginLifecycleFixture
Assert-ExitCode -Name "Selected lifecycle checker accepts blocked Gin lifecycle adoption" -Result $ginLifecycleResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate lifecycle check passed"

$ginLifecycleWeakSpoofFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-weak-spoof") -WeakValidationPassed
$ginLifecycleWeakSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-weak-spoof" -Fixture $ginLifecycleWeakSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin weak-validation spoof" -Result $ginLifecycleWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$ginLifecycleQaaSSpoofFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-qaas-spoof") -QaaSValidationPassed
$ginLifecycleQaaSSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-qaas-spoof" -Fixture $ginLifecycleQaaSSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin QaaS-validation spoof" -Result $ginLifecycleQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim partial QaaS template/live validation passed"

$ginLifecycleMissingModuleFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-missing-module-gate") -MissingModuleGate
$ginLifecycleMissingModuleResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-missing-module-gate" -Fixture $ginLifecycleMissingModuleFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin lifecycle without module gate evidence" -Result $ginLifecycleMissingModuleResult -ExpectedExitCode 1 -ExpectedText "go-version-and-module-resolution"

$ginLifecycleWrongBodyFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-wrong-body") -WrongBody
$ginLifecycleWrongBodyResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-wrong-body" -Fixture $ginLifecycleWrongBodyFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin response body drift" -Result $ginLifecycleWrongBodyResult -ExpectedExitCode 1 -ExpectedText "Gin lifecycle response must exactly match README-backed JSON body"

$ginLifecycleBadGoModShaFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-bad-go-mod-sha") -BadGoModSha
$ginLifecycleBadGoModShaResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-bad-go-mod-sha" -Fixture $ginLifecycleBadGoModShaFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin go.mod hash spoof" -Result $ginLifecycleBadGoModShaResult -ExpectedExitCode 1 -ExpectedText "go_mod_sha256 must match actual file"

$ginLifecycleBadGoSumShaFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-bad-go-sum-sha") -BadGoSumSha
$ginLifecycleBadGoSumShaResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-bad-go-sum-sha" -Fixture $ginLifecycleBadGoSumShaFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin go.sum hash spoof" -Result $ginLifecycleBadGoSumShaResult -ExpectedExitCode 1 -ExpectedText "go_sum_sha256 must match actual file"

$ginLifecycleMissingManagedEnvFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-missing-managed-env") -MissingManagedEnv
$ginLifecycleMissingManagedEnvResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-missing-managed-env" -Fixture $ginLifecycleMissingManagedEnvFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin missing managed Go env paths" -Result $ginLifecycleMissingManagedEnvResult -ExpectedExitCode 1 -ExpectedText "managed_gopath must exist"

$ginLifecycleMutableModuleFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-mutable-module") -MutableModuleCommand
$ginLifecycleMutableModuleResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-mutable-module" -Fixture $ginLifecycleMutableModuleFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin mutable module command" -Result $ginLifecycleMutableModuleResult -ExpectedExitCode 1 -ExpectedText "ModulePinCommand: go get github.com/gin-gonic/gin@v1.12.0"

$ginLifecycleWrongGoSourceFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-wrong-go-source") -WrongGoSource
$ginLifecycleWrongGoSourceResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-wrong-go-source" -Fixture $ginLifecycleWrongGoSourceFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin ambient Go source spoof" -Result $ginLifecycleWrongGoSourceResult -ExpectedExitCode 1 -ExpectedText "must use managed_go_toolchain"

$ginLifecycleWrongGoVersionFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-wrong-go-version") -WrongGoVersion
$ginLifecycleWrongGoVersionResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-wrong-go-version" -Fixture $ginLifecycleWrongGoVersionFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin wrong managed Go version" -Result $ginLifecycleWrongGoVersionResult -ExpectedExitCode 1 -ExpectedText "go_version must be go version go1.26.4 windows/amd64"

$ginLifecycleWrongGoArchiveUrlFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-wrong-go-archive-url") -WrongGoArchiveUrl
$ginLifecycleWrongGoArchiveUrlResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-wrong-go-archive-url" -Fixture $ginLifecycleWrongGoArchiveUrlFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin wrong managed Go archive URL" -Result $ginLifecycleWrongGoArchiveUrlResult -ExpectedExitCode 1 -ExpectedText "managed_toolchain_download_url must be https://go.dev/dl/go1.26.4.windows-amd64.zip"

$ginLifecycleBadGoArchiveShaFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-bad-go-archive-sha") -BadGoArchiveSha
$ginLifecycleBadGoArchiveShaResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-bad-go-archive-sha" -Fixture $ginLifecycleBadGoArchiveShaFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin managed Go archive hash spoof" -Result $ginLifecycleBadGoArchiveShaResult -ExpectedExitCode 1 -ExpectedText "managed_toolchain_archive_sha256 must be 3ca8fb4630b07c419cbdd51f754e31363cfcfb83b3a5354d9e895c90be2cc345"

$ginLifecycleEnvMismatchFixture = New-GinLifecycleFixture -Root (Join-Path $fixtureRoot "gin-lifecycle-env-mismatch") -EnvMismatch
$ginLifecycleEnvMismatchResult = Invoke-SelectedCandidateLifecycleCheck -Name "gin-lifecycle-env-mismatch" -Fixture $ginLifecycleEnvMismatchFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Gin go-env path drift" -Result $ginLifecycleEnvMismatchResult -ExpectedExitCode 1 -ExpectedText "go-env GOROOT mismatch"

$candidateExecutableFixture = New-SelectedCandidateFixture -Root (Join-Path $fixtureRoot "candidate-executable") -PromotionState "executable"
$candidateExecutableResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-executable" -Fixture $candidateExecutableFixture
Assert-ExitCode -Name "Selected candidate checker rejects executable leakage" -Result $candidateExecutableResult -ExpectedExitCode 1 -ExpectedText "promotion_state must stay blocked"

$candidatePromotionPacketsFixture = New-SelectedCandidateFixture -Root (Join-Path $fixtureRoot "candidate-promotion-packets") -CandidateRootUnderPromotionPackets
$candidatePromotionPacketsResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-promotion-packets" -Fixture $candidatePromotionPacketsFixture
Assert-ExitCode -Name "Selected candidate checker rejects promotion-packets root" -Result $candidatePromotionPacketsResult -ExpectedExitCode 1 -ExpectedText "must not be under promotion-packets"

$candidateRawUrlFixture = New-SelectedCandidateFixture -Root (Join-Path $fixtureRoot "candidate-raw-url") -RawGitHubUrl
$candidateRawUrlResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-raw-url" -Fixture $candidateRawUrlFixture
Assert-ExitCode -Name "Selected candidate checker rejects mutable GitHub evidence URL" -Result $candidateRawUrlResult -ExpectedExitCode 1 -ExpectedText "immutable Git blob URL"

$candidateUnsafePathFixture = New-SelectedCandidateFixture -Root (Join-Path $fixtureRoot "candidate-unsafe-source-path") -UnsafeSourcePath
$candidateUnsafePathResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-unsafe-source-path" -Fixture $candidateUnsafePathFixture
Assert-ExitCode -Name "Selected candidate checker rejects unsafe selected source path" -Result $candidateUnsafePathResult -ExpectedExitCode 1 -ExpectedText "unsafe source_path"

$candidateGeneratedEvidenceFixture = New-SelectedCandidateFixture -Root (Join-Path $fixtureRoot "candidate-generated-evidence") -PublicEvidenceInGeneratedRoot
$candidateGeneratedEvidenceResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-generated-evidence" -Fixture $candidateGeneratedEvidenceFixture
Assert-ExitCode -Name "Selected candidate checker rejects generated public evidence path" -Result $candidateGeneratedEvidenceResult -ExpectedExitCode 1 -ExpectedText "public_evidence must not point to generated candidate artifacts"

$candidateInventedYamlFixture = New-SelectedCandidateFixture -Root (Join-Path $fixtureRoot "candidate-invented-yaml") -InventedYamlKey
$candidateInventedYamlResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-invented-yaml" -Fixture $candidateInventedYamlFixture
Assert-ExitCode -Name "Selected candidate checker rejects invented QaaS YAML top-level key" -Result $candidateInventedYamlResult -ExpectedExitCode 1 -ExpectedText "invented top-level CandidateContracts"

$crawl4AiDeferredFixture = New-Crawl4AiDeferredCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-deferred-valid")
$crawl4AiDeferredResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-deferred-valid" -Fixture $crawl4AiDeferredFixture
Assert-ExitCode -Name "Selected candidate checker accepts Crawl4AI deferred without input-output contract" -Result $crawl4AiDeferredResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$crawl4AiMissingBlockerFixture = New-Crawl4AiDeferredCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-deferred-missing-input-output-blocker") -MissingInputOutputBlocker
$crawl4AiMissingBlockerResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-missing-input-output-blocker" -Fixture $crawl4AiMissingBlockerFixture
Assert-ExitCode -Name "Selected candidate checker rejects Crawl4AI deferred missing input-output blocker" -Result $crawl4AiMissingBlockerResult -ExpectedExitCode 1 -ExpectedText "selected_input_output_contract_missing"

$crawl4AiHealthFixture = New-Crawl4AiHealthCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-health-valid")
$crawl4AiHealthResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-health-valid" -Fixture $crawl4AiHealthFixture
Assert-ExitCode -Name "Selected candidate checker accepts Crawl4AI healthcheck-only candidate" -Result $crawl4AiHealthResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$crawl4AiReadinessResult = Invoke-SelectedCandidatePromotionReadinessCheck -Name "selected-candidate-crawl4ai-readiness-valid" -Fixture $crawl4AiHealthFixture -ExpectedCount 2
Assert-ExitCode -Name "Selected promotion readiness accepts Crawl4AI custom status hook without built-in HttpStatus advisory" -Result $crawl4AiReadinessResult -ExpectedExitCode 0 -ExpectedText "Selected candidate promotion readiness passed"
$crawl4AiReadinessPath = Join-Path $OutDir "selected-candidate-crawl4ai-readiness-valid-coverage\selected-candidate-promotion-readiness.json"
if (Test-Path -LiteralPath $crawl4AiReadinessPath -PathType Leaf) {
    $crawl4AiReadiness = Read-JsonFile -Path $crawl4AiReadinessPath
    $crawl4AiReadinessRecord = @($crawl4AiReadiness.records | Where-Object { [string]$_.repository -eq "unclecode/crawl4ai" })[0]
    if (-not [bool]$crawl4AiReadinessRecord.uses_builtin_httpstatus_assertion -and
        -not [bool]$crawl4AiReadinessRecord.tracks_httpstatus_docs_contract -and
        [int]$crawl4AiReadiness.docs_advisory_record_count -eq 0) {
        Add-Pass "Selected promotion readiness leaves Crawl4AI custom status hook out of built-in HttpStatus advisory tracking"
    } else {
        Add-Failure "Selected promotion readiness incorrectly tracked Crawl4AI as built-in HttpStatus advisory candidate: $crawl4AiReadinessPath"
    }
} else {
    Add-Failure "Selected promotion readiness did not write Crawl4AI readiness record: $crawl4AiReadinessPath"
}

$crawl4AiExact200Fixture = New-Crawl4AiHealthCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-health-exact-200") -UseHttpStatus200
$crawl4AiExact200Result = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-health-exact-200" -Fixture $crawl4AiExact200Fixture
Assert-ExitCode -Name "Selected candidate checker rejects Crawl4AI exact-200 status invention" -Result $crawl4AiExact200Result -ExpectedExitCode 1 -ExpectedText "Assertion: HttpStatusBelow400"

$crawl4AiCrawlRouteFixture = New-Crawl4AiHealthCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-health-crawl-route") -UseCrawlRoute
$crawl4AiCrawlRouteResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-health-crawl-route" -Fixture $crawl4AiCrawlRouteFixture
Assert-ExitCode -Name "Selected candidate checker rejects Crawl4AI /crawl promotion" -Result $crawl4AiCrawlRouteResult -ExpectedExitCode 1 -ExpectedText "Route: health"

$crawl4AiBodyAssertionFixture = New-Crawl4AiHealthCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-health-body-assertion") -AddBodyAssertion
$crawl4AiBodyAssertionResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-health-body-assertion" -Fixture $crawl4AiBodyAssertionFixture
Assert-ExitCode -Name "Selected candidate checker rejects Crawl4AI body/schema assertion invention" -Result $crawl4AiBodyAssertionResult -ExpectedExitCode 1 -ExpectedText "status-only"

$crawl4AiUnsafeCleanupFixture = New-Crawl4AiHealthCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-health-unsafe-cleanup") -MissingCleanupOwnership
$crawl4AiUnsafeCleanupResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-health-unsafe-cleanup" -Fixture $crawl4AiUnsafeCleanupFixture
Assert-ExitCode -Name "Selected candidate checker rejects Crawl4AI unsafe Docker cleanup ownership" -Result $crawl4AiUnsafeCleanupResult -ExpectedExitCode 1 -ExpectedText "--name zappa-crawl4ai-health-{run_id}"

$crawl4AiBodyReadingHookFixture = New-Crawl4AiHealthCandidateFixture -Root (Join-Path $fixtureRoot "crawl4ai-health-body-reading-hook") -AssertionReadsBody
$crawl4AiBodyReadingHookResult = Invoke-SelectedCandidateCheck -Name "selected-candidate-crawl4ai-health-body-reading-hook" -Fixture $crawl4AiBodyReadingHookFixture
Assert-ExitCode -Name "Selected candidate checker rejects Crawl4AI custom assertion reading response body" -Result $crawl4AiBodyReadingHookResult -ExpectedExitCode 1 -ExpectedText "status metadata only"

$crawl4AiLifecycleFixture = New-Crawl4AiLifecycleFixture -Root (Join-Path $fixtureRoot "crawl4ai-lifecycle-valid")
$crawl4AiLifecycleResult = Invoke-SelectedCandidateLifecycleCheck -Name "crawl4ai-lifecycle-valid" -Fixture $crawl4AiLifecycleFixture
Assert-ExitCode -Name "Selected lifecycle checker accepts blocked Crawl4AI Docker lifecycle adoption" -Result $crawl4AiLifecycleResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate lifecycle check passed"

$crawl4AiLifecycleWeakSpoofFixture = New-Crawl4AiLifecycleFixture -Root (Join-Path $fixtureRoot "crawl4ai-lifecycle-weak-spoof") -WeakValidationPassed
$crawl4AiLifecycleWeakSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "crawl4ai-lifecycle-weak-spoof" -Fixture $crawl4AiLifecycleWeakSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Crawl4AI weak-validation spoof" -Result $crawl4AiLifecycleWeakSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim weak model validation passed"

$crawl4AiLifecycleQaaSSpoofFixture = New-Crawl4AiLifecycleFixture -Root (Join-Path $fixtureRoot "crawl4ai-lifecycle-qaas-spoof") -QaaSValidationPassed
$crawl4AiLifecycleQaaSSpoofResult = Invoke-SelectedCandidateLifecycleCheck -Name "crawl4ai-lifecycle-qaas-spoof" -Fixture $crawl4AiLifecycleQaaSSpoofFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Crawl4AI QaaS-validation spoof" -Result $crawl4AiLifecycleQaaSSpoofResult -ExpectedExitCode 1 -ExpectedText "must not claim partial QaaS template/live validation passed"

$crawl4AiLifecycleWrongStatusFixture = New-Crawl4AiLifecycleFixture -Root (Join-Path $fixtureRoot "crawl4ai-lifecycle-wrong-status") -WrongStatus
$crawl4AiLifecycleWrongStatusResult = Invoke-SelectedCandidateLifecycleCheck -Name "crawl4ai-lifecycle-wrong-status" -Fixture $crawl4AiLifecycleWrongStatusFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Crawl4AI status >= 400" -Result $crawl4AiLifecycleWrongStatusResult -ExpectedExitCode 1 -ExpectedText "response status must be below 400"

$crawl4AiLifecycleUnsafeNameFixture = New-Crawl4AiLifecycleFixture -Root (Join-Path $fixtureRoot "crawl4ai-lifecycle-unsafe-name") -UnsafeContainerName
$crawl4AiLifecycleUnsafeNameResult = Invoke-SelectedCandidateLifecycleCheck -Name "crawl4ai-lifecycle-unsafe-name" -Fixture $crawl4AiLifecycleUnsafeNameFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Crawl4AI user-owned container name" -Result $crawl4AiLifecycleUnsafeNameResult -ExpectedExitCode 1 -ExpectedText "DockerRunCommand: docker run -d -p 127.0.0.1:11235:11235 --name zappa-crawl4ai-health-"

$crawl4AiLifecycleProtectedChangedFixture = New-Crawl4AiLifecycleFixture -Root (Join-Path $fixtureRoot "crawl4ai-lifecycle-protected-changed") -ProtectedContainerChanged
$crawl4AiLifecycleProtectedChangedResult = Invoke-SelectedCandidateLifecycleCheck -Name "crawl4ai-lifecycle-protected-changed" -Fixture $crawl4AiLifecycleProtectedChangedFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects protected Crawl4AI container drift" -Result $crawl4AiLifecycleProtectedChangedResult -ExpectedExitCode 1 -ExpectedText "changed protected crawl4ai container state"

$crawl4AiLifecycleBadShaFixture = New-Crawl4AiLifecycleFixture -Root (Join-Path $fixtureRoot "crawl4ai-lifecycle-bad-response-sha") -BadResponseSha
$crawl4AiLifecycleBadShaResult = Invoke-SelectedCandidateLifecycleCheck -Name "crawl4ai-lifecycle-bad-response-sha" -Fixture $crawl4AiLifecycleBadShaFixture
Assert-ExitCode -Name "Selected lifecycle checker rejects Crawl4AI forged response hash" -Result $crawl4AiLifecycleBadShaResult -ExpectedExitCode 1 -ExpectedText "response_body_sha256 must match actual response file"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    Write-Output "Harness regression tests failed. OutDir: $OutDir"
    exit 1
}

Write-Output "Harness regression tests passed: $($passed.Count)"
$passed | ForEach-Object { Write-Output "- $_" }
Write-Output "OutDir: $OutDir"
