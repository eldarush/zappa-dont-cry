param(
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-regression\deno-selected-candidate"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32), $script:Utf8NoBom)
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Convert-GeneratedCandidatePaths {
    param(
        [object]$Value,
        [string]$FromRoot,
        [string]$ToRoot
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        return ([string]$Value).Replace($FromRoot, $ToRoot)
    }

    if ($Value -is [System.Array]) {
        return ,@($Value | ForEach-Object { Convert-GeneratedCandidatePaths -Value $_ -FromRoot $FromRoot -ToRoot $ToRoot })
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = Convert-GeneratedCandidatePaths -Value $property.Value -FromRoot $FromRoot -ToRoot $ToRoot
        }
        return $result
    }

    return $Value
}

function Rewrite-CandidateJsonPaths {
    param(
        [string]$CandidateRoot,
        [string]$OriginalCandidateRoot
    )

    foreach ($jsonFile in @(Get-ChildItem -LiteralPath $CandidateRoot -Recurse -File -Filter "*.json")) {
        $json = Read-JsonFile -Path $jsonFile.FullName
        $rewritten = Convert-GeneratedCandidatePaths -Value $json -FromRoot $OriginalCandidateRoot -ToRoot $CandidateRoot
        Write-JsonFile -Path $jsonFile.FullName -Value $rewritten
    }
}

function Add-SourceBlockerIfMissing {
    param(
        [object]$Manifest,
        [string]$BlockerId
    )

    $existing = @($Manifest.source_only_blockers | Where-Object { [string]$_.blocker_id -eq $BlockerId })
    if ($existing.Count -gt 0) {
        return
    }

    $Manifest.source_only_blockers = @($Manifest.source_only_blockers) + [ordered]@{
        blocker_id = $BlockerId
        blocker_type = "regression_fixture"
        description = "blocked"
        required_evidence = @("live evidence")
        public_evidence = @()
        unblock_instruction = "run the real harness"
    }
}

function Remove-ValidationAdvisory {
    param(
        [object]$Manifest,
        [string]$AdvisoryId
    )

    if (-not ($Manifest.PSObject.Properties.Name -contains "validation_advisories")) {
        return
    }
    $Manifest.validation_advisories = @($Manifest.validation_advisories | Where-Object { [string]$_.advisory_id -ne $AdvisoryId })
}

function Reset-DenoLifecycleAdoption {
    param([object]$Fixture)

    $manifest = Read-JsonFile -Path $Fixture.DenoManifest
    $runtimePlan = Read-JsonFile -Path $Fixture.DenoRuntimePlan

    $manifest.PSObject.Properties.Remove("lifecycle_validation")
    foreach ($field in @("assertion_build_validation", "build_validation", "template_validation", "live_validation", "selected_candidate_qaas_validation")) {
        if ($manifest.PSObject.Properties.Name -contains $field) {
            $manifest.PSObject.Properties.Remove($field)
        }
    }
    $runtimePlan.PSObject.Properties.Remove("lifecycle_validation")
    if ($runtimePlan.PSObject.Properties.Name -contains "qaas_validation") {
        $runtimePlan.PSObject.Properties.Remove("qaas_validation")
    }
    if ($runtimePlan.managed_toolchain.PSObject.Properties.Name -contains "evidence") {
        $runtimePlan.managed_toolchain.PSObject.Properties.Remove("evidence")
    }
    if ($runtimePlan.cleanup.PSObject.Properties.Name -contains "evidence") {
        $runtimePlan.cleanup.PSObject.Properties.Remove("evidence")
    }

    foreach ($gate in @($manifest.dependency_gates)) {
        if ([string]$gate.gate_id -eq "managed-deno-toolchain") {
            $gate.status = "blocked"
            $gate.evidence = @()
            $gate.check_command = ""
            $gate.blocked_reason = "The managed Deno release asset has not been downloaded, hash-verified, and version-checked by the harness."
        }
        if ([string]$gate.gate_id -eq "deno-process-lifecycle") {
            $gate.status = "blocked"
            $gate.evidence = @()
            $gate.check_command = ""
            $gate.blocked_reason = "The external Deno process has not been started, tracked, readiness-checked, and cleaned up by the harness."
        }
        if ([string]$gate.gate_id -eq "cleanup-contract") {
            $gate.status = "blocked"
            $gate.evidence = @()
            $gate.check_command = ""
            $gate.blocked_reason = "Tracked process tree cleanup and session-data cleanup are not live-validated."
        }
        if ([string]$gate.gate_id -eq "plain-text-body-assertion-or-hook") {
            $gate.status = "ready"
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates"
            $gate.blocked_reason = ""
        }
        if ([string]$gate.gate_id -eq "qaas-template") {
            $gate.status = "blocked"
            $gate.evidence = @()
            $gate.check_command = ""
            $gate.blocked_reason = "QaaS template validation has not run for this candidate."
        }
        if ([string]$gate.gate_id -eq "qaas-live-act-assert") {
            $gate.status = "blocked"
            $gate.evidence = @()
            $gate.check_command = ""
            $gate.blocked_reason = "Live QaaS run/act/assert has not run against a tracked Deno process."
        }
    }

    Add-SourceBlockerIfMissing -Manifest $manifest -BlockerId "deno-toolchain-not-proven"
    Add-SourceBlockerIfMissing -Manifest $manifest -BlockerId "deno-process-lifecycle-not-proven"
    Add-SourceBlockerIfMissing -Manifest $manifest -BlockerId "deno-text-body-hook-not-template-validated"
    Add-SourceBlockerIfMissing -Manifest $manifest -BlockerId "qaas-template-live-not-run"
    Add-SourceBlockerIfMissing -Manifest $manifest -BlockerId "httpstatus-docs-inconsistency-recorded"
    Remove-ValidationAdvisory -Manifest $manifest -AdvisoryId "httpstatus-docs-inconsistency-recorded"
    $runtimePlan.managed_toolchain.status = "not_validated"
    $runtimePlan.cleanup.status = "not_validated"
    $manifest.custom_text_body_assertion.status = "authored_from_public_docs_not_template_validated"
    $manifest.custom_text_body_assertion.validation_status = "not_template_validated"
    foreach ($packet in @($manifest.custom_assertion_packets)) {
        if ([string]$packet.assertion_name -eq "ExactHttpTextBody") {
            $packet.status = "blocked_until_build_template_live_airgapped_validation"
            $packet.activation = "sidecar_only"
            $packet.wired_into_runner_yaml = $false
            $packet.validation_records.build = "not_run"
            $packet.validation_records.schema = "not_run"
            $packet.validation_records.template = "not_run"
            $packet.validation_records.live = "not_run"
            $packet.validation_records.airgapped = "not_run"
            $packet.weak_validation_passed = $false
        }
    }
    $runtimePlan.custom_text_body_assertion.status = "authored_from_public_docs_not_template_validated"
    $runtimePlan.custom_text_body_assertion.validation_status = "not_template_validated"
    foreach ($packet in @($runtimePlan.custom_assertion_packets)) {
        if ([string]$packet.assertion_name -eq "ExactHttpTextBody") {
            $packet.status = "blocked_until_build_template_live_airgapped_validation"
            $packet.activation = "sidecar_only"
            $packet.wired_into_runner_yaml = $false
            $packet.validation_records.build = "not_run"
            $packet.validation_records.schema = "not_run"
            $packet.validation_records.template = "not_run"
            $packet.validation_records.live = "not_run"
            $packet.validation_records.airgapped = "not_run"
            $packet.weak_validation_passed = $false
        }
    }
    foreach ($requiredBlocker in @("prove_managed_deno_toolchain_without_using_ambient_path", "prove_process_lifecycle_and_cleanup_without assuming private source", "validate_exact_text_body_custom_assertion_schema_template_and_live", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
        if (-not (@($runtimePlan.blockers) -contains $requiredBlocker)) {
            $runtimePlan.blockers = @($requiredBlocker) + @($runtimePlan.blockers)
        }
    }

    Write-JsonFile -Path $Fixture.DenoManifest -Value $manifest
    Write-JsonFile -Path $Fixture.DenoRuntimePlan -Value $runtimePlan
}

function New-Fixture {
    param([string]$Name)

    $originalCandidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates"
    $originalSelectedRoot = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts"
    $root = Join-Path $OutDir $Name
    $selectedRoot = Join-Path $root "selected-contracts"
    $candidateRoot = Join-Path $root "selected-top-repo-candidates"
    $coverageRoot = Join-Path $root "coverage"
    [System.IO.Directory]::CreateDirectory($root) | Out-Null

    [System.IO.Directory]::CreateDirectory($selectedRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($candidateRoot) | Out-Null
    Copy-Item -LiteralPath (Join-Path $originalSelectedRoot "098-denoland-deno") -Destination (Join-Path $selectedRoot "098-denoland-deno") -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $originalCandidateRoot "098-denoland-deno") -Destination (Join-Path $candidateRoot "098-denoland-deno") -Recurse -Force

    Rewrite-CandidateJsonPaths -CandidateRoot $candidateRoot -OriginalCandidateRoot $originalCandidateRoot
    $selectedContractPath = Join-Path $selectedRoot "098-denoland-deno\selected-contract.json"
    $candidateDir = Join-Path $candidateRoot "098-denoland-deno"
    $candidateManifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $candidateRuntimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"

    $manifest = Read-JsonFile -Path $candidateManifestPath
    $manifest.selected_contract = $selectedContractPath
    Write-JsonFile -Path $candidateManifestPath -Value $manifest

    Write-JsonFile -Path (Join-Path $selectedRoot "selected-contract-index.json") -Value ([ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        selected_repository_count = 1
        records = @(
            [ordered]@{
                rank = 98
                repository = "denoland/deno"
                record_path = $selectedContractPath
            }
        )
    })

    Write-JsonFile -Path (Join-Path $candidateRoot "selected-candidate-index.json") -Value ([ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        source_selected_contracts_directory = $selectedRoot
        output_directory = $candidateRoot
        selected_candidate_count = 1
        selected_contract_count = 1
        deferred_candidate_count = 0
        policy = "Deno regression fixture"
        records = @(
            [ordered]@{
                rank = 98
                repository = "denoland/deno"
                directory = $candidateDir
                manifest = $candidateManifestPath
                selected_contract = $selectedContractPath
                status = "candidate_packet_blocked_until_template_live_airgapped_validation"
                promotion_state = "blocked"
                readiness_state = "qaaS_candidate_authored_from_selected_contract"
                artifact_count = 6
            }
        )
        deferred_records = @()
    })

    $fixture = [pscustomobject]@{
        Root = $root
        SelectedRoot = $selectedRoot
        CandidateRoot = $candidateRoot
        CoverageRoot = $coverageRoot
        DenoCandidateDir = $candidateDir
        DenoManifest = $candidateManifestPath
        DenoRuntimePlan = $candidateRuntimePlanPath
        DenoYaml = Join-Path $candidateDir "test.qaas.yaml"
        DenoServer = Join-Path $candidateDir "app\server.ts"
    }
    Reset-DenoLifecycleAdoption -Fixture $fixture
    return $fixture
}

function Invoke-CandidateCheck {
    param([object]$Fixture)

    $checker = Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidates.py"
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & python $checker $Fixture.CandidateRoot $Fixture.SelectedRoot $Fixture.CoverageRoot 2>&1
        $exitCode = [int]$LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | Out-String)
    }
}

function Assert-Check {
    param(
        [string]$Name,
        [object]$Result,
        [int]$ExpectedExitCode,
        [string]$ExpectedText
    )

    if ([int]$Result.ExitCode -ne $ExpectedExitCode) {
        Add-Failure "$Name exit code expected $ExpectedExitCode, got $($Result.ExitCode). Output: $($Result.Output)"
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedText) -and -not $Result.Output.Contains($ExpectedText)) {
        Add-Failure "$Name output missing expected text '$ExpectedText'. Output: $($Result.Output)"
    }
}

$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
$allowedRegressionRoot = [System.IO.Path]::GetFullPath("D:\QaaS\_tmp\zappa-dont-cry")
$allowedPrefix = $allowedRegressionRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (
    -not ($resolvedOutDir.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) -or
    $resolvedOutDir.Equals($allowedRegressionRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    $resolvedOutDir.Equals("D:\QaaS", [System.StringComparison]::OrdinalIgnoreCase)
) {
    throw "OutDir must stay under $allowedRegressionRoot; got $resolvedOutDir"
}

if (Test-Path -LiteralPath $resolvedOutDir -PathType Container) {
    Remove-Item -LiteralPath $resolvedOutDir -Recurse -Force
}
[System.IO.Directory]::CreateDirectory($resolvedOutDir) | Out-Null
$OutDir = $resolvedOutDir

$baseline = New-Fixture -Name "baseline"
$baselineResult = Invoke-CandidateCheck -Fixture $baseline
Assert-Check -Name "Deno selected candidate baseline" -Result $baselineResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$yamlCommandSpoof = New-Fixture -Name "yaml-command-spoof"
Add-Content -LiteralPath $yamlCommandSpoof.DenoYaml -Value "`n# spoof`nStartCommand: deno run --allow-net server.ts`n" -Encoding UTF8
$yamlCommandSpoofResult = Invoke-CandidateCheck -Fixture $yamlCommandSpoof
Assert-Check -Name "Deno checker rejects lifecycle command in YAML" -Result $yamlCommandSpoofResult -ExpectedExitCode 1 -ExpectedText "candidate YAML embeds external process command"

$weakSpoof = New-Fixture -Name "weak-spoof"
$weakManifest = Read-JsonFile -Path $weakSpoof.DenoManifest
$weakManifest.custom_assertion_packets[0].weak_validation_passed = $true
$weakManifest.custom_text_body_assertion.weak_validation_passed = $true
Write-JsonFile -Path $weakSpoof.DenoManifest -Value $weakManifest
$weakSpoofResult = Invoke-CandidateCheck -Fixture $weakSpoof
Assert-Check -Name "Deno checker rejects weak-validation spoof" -Result $weakSpoofResult -ExpectedExitCode 1 -ExpectedText "weak_validation_passed"

$missingAirgapped = New-Fixture -Name "missing-airgapped-blocker"
$airManifest = Read-JsonFile -Path $missingAirgapped.DenoManifest
$airManifest.source_only_blockers = @($airManifest.source_only_blockers | Where-Object { [string]$_.blocker_id -ne "live-airgapped-weak-model-not-passed" })
Write-JsonFile -Path $missingAirgapped.DenoManifest -Value $airManifest
$missingAirgappedResult = Invoke-CandidateCheck -Fixture $missingAirgapped
Assert-Check -Name "Deno checker preserves airgapped blocker" -Result $missingAirgappedResult -ExpectedExitCode 1 -ExpectedText "live-airgapped-weak-model-not-passed"

$badToolchain = New-Fixture -Name "bad-toolchain-sha"
$runtimePlan = Read-JsonFile -Path $badToolchain.DenoRuntimePlan
$runtimePlan.managed_toolchain.archive_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
Write-JsonFile -Path $badToolchain.DenoRuntimePlan -Value $runtimePlan
$badToolchainResult = Invoke-CandidateCheck -Fixture $badToolchain
Assert-Check -Name "Deno checker rejects managed toolchain hash drift" -Result $badToolchainResult -ExpectedExitCode 1 -ExpectedText "managed_toolchain archive_sha256 mismatch"

$wrongRuntime = New-Fixture -Name "wrong-runtime-server"
Set-Content -LiteralPath $wrongRuntime.DenoServer -Value "console.log('Hello, world!')" -Encoding UTF8
$wrongRuntimeResult = Invoke-CandidateCheck -Fixture $wrongRuntime
Assert-Check -Name "Deno checker rejects non-Deno server fixture" -Result $wrongRuntimeResult -ExpectedExitCode 1 -ExpectedText "missing marker 'Deno.serve"

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Deno selected-candidate regression checks passed."
