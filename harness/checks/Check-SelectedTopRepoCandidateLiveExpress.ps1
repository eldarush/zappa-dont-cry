param(
    [string]$SummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-live-express.json",
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\243-expressjs-express",
    [string]$CandidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates",
    [string]$LiveRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-NormalizedPath {
    param([string]$Path)

    $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
}

function Test-PathUnderRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $fullPath = Get-NormalizedPath -Path $Path
    $rootPath = Get-NormalizedPath -Path $Root
    if ([string]::Equals($fullPath, $rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootPrefix = "$rootPath$([System.IO.Path]::DirectorySeparatorChar)"
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathEquals {
    param(
        [string]$Actual,
        [string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Actual) -or [string]::IsNullOrWhiteSpace($Expected)) {
        return $false
    }

    return [string]::Equals((Get-NormalizedPath -Path $Actual), (Get-NormalizedPath -Path $Expected), [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-NoUtf8Bom {
    param(
        [string]$Path,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-Failure "$Description must be UTF-8 without BOM: $Path"
    }
}

function Test-ExistingFileUnderRoot {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Add-Failure "$Description is blank."
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "$Description missing: $Path"
        return $false
    }
    if (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $Path).Path -Root $Root)) {
        Add-Failure "$Description must stay under $Root; got $Path"
        return $false
    }

    Test-NoUtf8Bom -Path $Path -Description $Description
    return $true
}

function Test-ExistingDirectoryUnderRoot {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Add-Failure "$Description is blank."
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Add-Failure "$Description missing: $Path"
        return $false
    }
    if (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $Path).Path -Root $Root)) {
        Add-Failure "$Description must stay under $Root; got $Path"
        return $false
    }

    return $true
}

function Test-PassedValidation {
    param([object]$Value)

    $status = Get-PropertyValue -Object $Value -Name "status"
    $exitCode = Get-PropertyValue -Object $Value -Name "exit_code"
    $command = [string](Get-PropertyValue -Object $Value -Name "command")
    $transcript = [string](Get-PropertyValue -Object $Value -Name "transcript")
    return (
        $null -ne $Value -and
        [string]$status -eq "passed" -and
        [int]$exitCode -eq 0 -and
        -not [string]::IsNullOrWhiteSpace($command) -and
        -not [string]::IsNullOrWhiteSpace($transcript) -and
        (Test-Path -LiteralPath $transcript -PathType Leaf)
    )
}

function Test-SameValidationRecord {
    param(
        [object]$Left,
        [object]$Right
    )

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    foreach ($field in @("status", "exit_code", "command", "transcript")) {
        if ([string](Get-PropertyValue -Object $Left -Name $field) -ne [string](Get-PropertyValue -Object $Right -Name $field)) {
            return $false
        }
    }

    return $true
}

function Get-Sha256Hex {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "Hash input missing: $Path"
        return ""
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha.Dispose()
    }
}

function Get-PortOwnerCount {
    param([int]$Port)

    try {
        return @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @("127.0.0.1", "::1", "0.0.0.0", "::") -and [string]$_.State -eq "Listen" }).Count
    } catch {
        return 0
    }
}

$candidateRootPath = [System.IO.Path]::GetFullPath($CandidateRoot)
if (-not (Test-PathUnderRoot -Path $CandidateDir -Root $candidateRootPath)) {
    Add-Failure "CandidateDir must stay under $candidateRootPath; got $CandidateDir"
}

$manifestPath = Join-Path $CandidateDir "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $CandidateDir "candidate-runtime-plan.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Add-Failure "Missing candidate manifest: $manifestPath"
}
if (-not (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf)) {
    Add-Failure "Missing candidate runtime plan: $runtimePlanPath"
}

if ($failures.Count -eq 0 -and -not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    Write-Output "Selected Express live check passed: no Express live QaaS evidence yet; candidate remains blocked."
    exit 0
}

Test-NoUtf8Bom -Path $SummaryPath -Description "Express live summary"
Test-NoUtf8Bom -Path $manifestPath -Description "Express candidate manifest"
Test-NoUtf8Bom -Path $runtimePlanPath -Description "Express candidate runtime plan"

$record = if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) { Read-JsonFile -Path $SummaryPath } else { $null }
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-JsonFile -Path $manifestPath } else { $null }
$runtimePlan = if (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf) { Read-JsonFile -Path $runtimePlanPath } else { $null }

if ($null -ne $record) {
    if ($record.repository -ne "expressjs/express") {
        Add-Failure "Express live record repository mismatch: $($record.repository)"
    }
    if ($record.validation_kind -ne "selected_candidate_qaas_template_live") {
        Add-Failure "Express live record validation_kind mismatch: $($record.validation_kind)"
    }
    if ($record.promotion_state -ne "blocked" -or $record.completion_ready -ne $false) {
        Add-Failure "Express live record must remain blocked and not completion-ready: $SummaryPath"
    }
}

if ($null -eq $record) {
    Add-Failure "Express live summary missing: $SummaryPath"
} elseif ($record.status -eq "blocked") {
    if ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
        Add-Failure "Blocked Express live record must include a reason: $SummaryPath"
    }
} elseif ($record.status -eq "failed") {
    Add-Failure "Latest Express selected live validation failed: $SummaryPath"
} elseif ($record.status -eq "passed") {
    if ($record.manifest_updated -ne $true) {
        Add-Failure "Passed Express live record must prove manifest_updated true: $SummaryPath"
    }
    if ([int]$record.exit_code -ne 0) {
        Add-Failure "Passed Express live record must have exit_code 0: $SummaryPath"
    }
    if ($record.response_contract_passed -ne $true -or [int]$record.response_status -ne 200) {
        Add-Failure "Passed Express live record must prove HTTP 200 response contract: $SummaryPath"
    }
    if ($record.cleanup_passed -ne $true) {
        Add-Failure "Passed Express live record must prove cleanup: $SummaryPath"
    }
    if ([int]$record.port_owners_after_cleanup_count -ne 0) {
        Add-Failure "Passed Express live record must have zero port owners after cleanup: $SummaryPath"
    }
    if (@($record.remaining_tracked_process_ids).Count -ne 0) {
        Add-Failure "Passed Express live record must have no remaining tracked process ids: $SummaryPath"
    }
    if ((Get-PortOwnerCount -Port 3000) -ne 0) {
        Add-Failure "Port 3000 is currently still owned after Express live validation."
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "Express live validation must not claim weak model validation passed: $SummaryPath"
    }
    if ($record.install_command -ne "npm install express") {
        Add-Failure "Express live record install_command mismatch: $SummaryPath"
    }
    if ($record.install_execution_command -ne "npm install express@5.2.1" -or $record.package_spec -ne "express@5.2.1") {
        Add-Failure "Express live record must cite the pinned selected package install: $SummaryPath"
    }
    if ([int]$record.npm_install_exit_code -ne 0 -or $record.npm_install_timed_out -ne $false) {
        Add-Failure "Express live record must prove npm install completed successfully: $SummaryPath"
    }
    if ($record.node_major_version_at_least_18 -ne $true) {
        Add-Failure "Express live record must prove Node major version is at least 18: $SummaryPath"
    }
    if ($record.express_package_available -ne $true -or [string]$record.installed_express_version -ne "5.2.1") {
        Add-Failure "Express live record must prove installed Express 5.2.1 is available: $SummaryPath"
    }
    if ($record.assertion_project_reference_added -ne $true) {
        Add-Failure "Express live record must prove assertion_project_reference_added true: $SummaryPath"
    }

    foreach ($field in @("transcript", "express_stdout", "express_stderr", "response", "runner_yaml", "runner_program", "runner_project", "assertion_project", "assertion_source", "assertion_project_reference_transcript", "npm_install_stdout", "npm_install_stderr", "staged_package_json", "package_lock", "installed_express_package")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        [void](Test-ExistingFileUnderRoot -Path $value -Root $LiveRoot -Description "Express live ${field}")
    }
    foreach ($field in @("node_path", "npm_path")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        if ([string]::IsNullOrWhiteSpace($value) -or -not (Test-Path -LiteralPath $value -PathType Leaf)) {
            Add-Failure "Express live ${field} must point to an installed executable: $SummaryPath"
        }
    }
    foreach ($field in @("source_runner_yaml", "source_assertion")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        [void](Test-ExistingFileUnderRoot -Path $value -Root $CandidateDir -Description "Express live ${field}")
    }
    [void](Test-ExistingDirectoryUnderRoot -Path ([string]$record.run_dir) -Root $LiveRoot -Description "Express live run_dir")
    $selectedReadmeEvidence = [string](Get-PropertyValue -Object $record -Name "selected_readme_evidence")
    $selectedContractDir = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\243-expressjs-express"
    if (-not [string]::IsNullOrWhiteSpace($selectedReadmeEvidence) -and (Test-Path -LiteralPath $selectedReadmeEvidence -PathType Leaf)) {
        $selectedFilesDir = Split-Path -Parent $selectedReadmeEvidence
        $selectedContractDir = Split-Path -Parent $selectedFilesDir
    }
    foreach ($field in @("selected_readme_evidence", "selected_package_evidence", "selected_example_evidence", "selected_acceptance_evidence")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        [void](Test-ExistingFileUnderRoot -Path $value -Root $selectedContractDir -Description "Express live ${field}")
    }

    if (-not (Test-PathEquals -Actual ([string]$record.manifest) -Expected $manifestPath)) {
        Add-Failure "Express live record manifest path mismatch: $SummaryPath"
    }
    if (-not (Test-PathEquals -Actual ([string]$record.runtime_plan) -Expected $runtimePlanPath)) {
        Add-Failure "Express live record runtime_plan path mismatch: $SummaryPath"
    }

    foreach ($validationField in @("assertion_build_validation", "build_validation", "template_validation", "live_validation")) {
        $validation = Get-PropertyValue -Object $record -Name $validationField
        if (-not (Test-PassedValidation -Value $validation)) {
            Add-Failure "Express live record missing passed ${validationField}: $SummaryPath"
        } else {
            $transcriptPath = [string](Get-PropertyValue -Object $validation -Name "transcript")
            if (-not (Test-PathUnderRoot -Path $transcriptPath -Root $LiveRoot)) {
                Add-Failure "Express live ${validationField} transcript must stay under ${LiveRoot}: $transcriptPath"
            }
            Test-NoUtf8Bom -Path $transcriptPath -Description "Express live ${validationField} transcript"
        }
    }

    $responseText = Get-Content -LiteralPath ([string]$record.response) -Raw
    if ($responseText -ne "Hello World") {
        Add-Failure "Express live response must exactly match README-backed text body: $($record.response)"
    }
    $actualResponseSha = Get-Sha256Hex -Path ([string]$record.response)
    if ([string]$record.response_body_sha256 -ne $actualResponseSha) {
        Add-Failure "Express live response_body_sha256 must match actual response file: $($record.response)"
    }

    $hashes = $record.source_hashes
    $sourceYamlPath = Join-Path $CandidateDir "test.qaas.yaml"
    $sourcePayloadPath = Join-Path $CandidateDir "request-payloads\get-root.bin"
    $sourceAppPath = Join-Path $CandidateDir "app\app.mjs"
    $sourceBodyPath = Join-Path $CandidateDir "expectations\root-body.txt"
    $sourceAssertionPath = Join-Path $CandidateDir "assertion-packets\ExactHttpTextBody\ExactHttpTextBody.cs"
    $stagedYamlPath = [string]$record.runner_yaml
    $stagedRunnerRoot = Split-Path -Parent $stagedYamlPath
    $stagedPayloadPath = Join-Path $stagedRunnerRoot "request-payloads\get-root.bin"
    $stagedAppPath = Join-Path ([string]$record.run_dir) "express-work\app.mjs"
    $stagedBodyPath = Join-Path $stagedRunnerRoot "expectations\root-body.txt"
    $stagedAssertionPath = [string]$record.assertion_source
    $selectedReadmePath = [string]$record.selected_readme_evidence
    $selectedPackagePath = [string]$record.selected_package_evidence
    $selectedExamplePath = [string]$record.selected_example_evidence
    $selectedAcceptancePath = [string]$record.selected_acceptance_evidence
    $stagedPackageJsonPath = [string]$record.staged_package_json
    $packageLockPath = [string]$record.package_lock
    $installedExpressPackagePath = [string]$record.installed_express_package
    $selectedPackage = $null
    $installedPackage = $null
    if (Test-Path -LiteralPath $selectedPackagePath -PathType Leaf) {
        $selectedPackage = Read-JsonFile -Path $selectedPackagePath
        if ([string]$selectedPackage.name -ne "express" -or [string]$selectedPackage.version -ne "5.2.1") {
            Add-Failure "Express selected package evidence must identify express 5.2.1: $selectedPackagePath"
        }
    }
    if (Test-Path -LiteralPath $installedExpressPackagePath -PathType Leaf) {
        $installedPackage = Read-JsonFile -Path $installedExpressPackagePath
        if ($null -eq $selectedPackage -or [string]$installedPackage.name -ne "express" -or [string]$installedPackage.version -ne [string]$selectedPackage.version) {
            Add-Failure "Express installed package evidence must match selected package version: $installedExpressPackagePath"
        }
    }
    foreach ($hashSpec in @(
        @("candidate_yaml_sha256", $sourceYamlPath, $CandidateDir),
        @("staged_yaml_sha256", $stagedYamlPath, $LiveRoot),
        @("candidate_request_payload_sha256", $sourcePayloadPath, $CandidateDir),
        @("staged_request_payload_sha256", $stagedPayloadPath, $LiveRoot),
        @("candidate_app_sha256", $sourceAppPath, $CandidateDir),
        @("staged_app_sha256", $stagedAppPath, $LiveRoot),
        @("candidate_expected_body_sha256", $sourceBodyPath, $CandidateDir),
        @("staged_expected_body_sha256", $stagedBodyPath, $LiveRoot),
        @("candidate_assertion_sha256", $sourceAssertionPath, $CandidateDir),
        @("staged_assertion_sha256", $stagedAssertionPath, $LiveRoot),
        @("selected_readme_sha256", $selectedReadmePath, $selectedContractDir),
        @("selected_package_sha256", $selectedPackagePath, $selectedContractDir),
        @("selected_example_sha256", $selectedExamplePath, $selectedContractDir),
        @("selected_acceptance_sha256", $selectedAcceptancePath, $selectedContractDir),
        @("staged_package_json_sha256", $stagedPackageJsonPath, $LiveRoot),
        @("package_lock_sha256", $packageLockPath, $LiveRoot),
        @("installed_express_package_sha256", $installedExpressPackagePath, $LiveRoot)
    )) {
        $hashField = [string]$hashSpec[0]
        $hashPath = [string]$hashSpec[1]
        $root = [string]$hashSpec[2]
        if (-not (Test-PathUnderRoot -Path $hashPath -Root $root)) {
            Add-Failure "Express ${hashField} file must stay under ${root}: $hashPath"
            continue
        }
        $actualHash = Get-Sha256Hex -Path $hashPath
        if ([string](Get-PropertyValue -Object $hashes -Name $hashField) -ne $actualHash) {
            Add-Failure "Express live source hash ${hashField} does not match actual file: $hashPath"
        }
    }
    foreach ($pair in @(
        @("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        @("candidate_app_sha256", "staged_app_sha256"),
        @("candidate_expected_body_sha256", "staged_expected_body_sha256"),
        @("candidate_assertion_sha256", "staged_assertion_sha256")
    )) {
        if ([string](Get-PropertyValue -Object $hashes -Name $pair[0]) -ne [string](Get-PropertyValue -Object $hashes -Name $pair[1])) {
            Add-Failure "Express live source hash mismatch $($pair[0])/$($pair[1]): $SummaryPath"
        }
    }
    if ([string](Get-PropertyValue -Object $hashes -Name "candidate_yaml_sha256") -eq [string](Get-PropertyValue -Object $hashes -Name "staged_yaml_sha256")) {
        Add-Failure "Express staged live YAML must differ from source YAML because it activates ExactHttpTextBody only in run dir: $SummaryPath"
    }

    $sourceYamlText = Get-Content -LiteralPath $sourceYamlPath -Raw
    if ($sourceYamlText -match [regex]::Escape("Assertion: ExactHttpTextBody")) {
        Add-Failure "Express source candidate YAML must not activate ExactHttpTextBody: $sourceYamlPath"
    }
    $runnerYamlText = Get-Content -LiteralPath ([string]$record.runner_yaml) -Raw
    foreach ($requiredText in @("Assertion: ExactHttpTextBody", "OutputName: GetRoot", "ExpectedText: Hello World", "EncodingName: utf-8", "Route: ''")) {
        if ($runnerYamlText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Express staged runner YAML missing '$requiredText': $($record.runner_yaml)"
        }
    }
    if ($runnerYamlText -match "(?m)^\s*Route:\s*/\s*$") {
        Add-Failure "Express staged runner YAML must use empty root route to avoid double-slash URL: $($record.runner_yaml)"
    }

    $runnerProgramText = Get-Content -LiteralPath ([string]$record.runner_program) -Raw
    if ($runnerProgramText -notmatch [regex]::Escape("System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Express.Assertions.ExactHttpTextBody));")) {
        Add-Failure "Express runner Program.cs must force-load ExactHttpTextBody assembly: $($record.runner_program)"
    }
    $runnerProjectText = Get-Content -LiteralPath ([string]$record.runner_project) -Raw
    if ($runnerProjectText -notmatch "ProjectReference" -or $runnerProjectText -notmatch "ZappaSelectedExpress.Assertions.csproj") {
        Add-Failure "Express runner project must reference assertion project: $($record.runner_project)"
    }
    $assertionProjectText = Get-Content -LiteralPath ([string]$record.assertion_project) -Raw
    if ($assertionProjectText -notmatch [regex]::Escape('PackageReference Include="QaaS.Framework.SDK" Version="1.5.1"')) {
        Add-Failure "Express assertion project must reference QaaS.Framework.SDK 1.5.1: $($record.assertion_project)"
    }
    $assertionText = Get-Content -LiteralPath ([string]$record.assertion_source) -Raw
    foreach ($requiredText in @("BaseAssertion<ExactHttpTextBodyConfig>", "using QaaS.Framework.SDK.Extensions;", "GetOutputByName(Configuration.OutputName).Data", "StringComparison.Ordinal")) {
        if ($assertionText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Express staged assertion source missing '$requiredText': $($record.assertion_source)"
        }
    }

    $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
    foreach ($requiredText in @(
        "NodeCommand: node app.mjs",
        "InstallCommand: npm install express",
        "InstallExecutionCommand: npm install express@5.2.1",
        "NpmInstallExitCode: 0",
        "PackageSpec: express@5.2.1",
        "InstalledExpressVersion: 5.2.1",
        "ExpressPackageAvailable: True",
        "NodeMajorVersionAtLeast18: True",
        "AssertionProjectReferenceAdded: True",
        "Ready: True",
        "AssertionBuildPassed: True",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "ExitCode: 0"
    )) {
        if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Express live transcript missing required text '$requiredText': $($record.transcript)"
        }
    }

    $templateTranscriptText = Get-Content -LiteralPath ([string]$record.template_validation.transcript) -Raw
    foreach ($requiredText in @(
        "Found IAssertion hook instance ExactHttpTextBody",
        "Assertion: ExactHttpTextBody",
        "Runner completed. ExitCode=0"
    )) {
        if ($templateTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Express template Runner transcript missing '$requiredText': $($record.template_validation.transcript)"
        }
    }

    $liveTranscriptText = Get-Content -LiteralPath ([string]$record.live_validation.transcript) -Raw
    foreach ($requiredText in @(
        "Found IAssertion hook instance ExactHttpTextBody",
        "HTTP Get request to http://127.0.0.1:3000/ completed with status 200.",
        "Running assertion ExactHttpTextBody GetRootBodyMatchesReadme",
        "Running assertion HttpStatus GetRootReturnedOk",
        "Runner completed. ExitCode=0"
    )) {
        if ($liveTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Express live Runner transcript missing required text '$requiredText': $($record.live_validation.transcript)"
        }
    }
    if ($liveTranscriptText.Contains("http://127.0.0.1:3000//")) {
        Add-Failure "Express live Runner transcript must not contain double-slash root URL: $($record.live_validation.transcript)"
    }

    if ($null -eq $manifest) {
        Add-Failure "Passed Express live validation requires candidate manifest."
    } else {
        $manifestHasQaaSValidation = (
            ($manifest.PSObject.Properties.Name -contains "selected_candidate_qaas_validation") -and
            $manifest.selected_candidate_qaas_validation.status -eq "passed" -and
            $manifest.selected_candidate_qaas_validation.summary -eq $SummaryPath
        )
        if (-not $manifestHasQaaSValidation) {
            Add-Failure "Passed Express live evidence has not been adopted by current manifest: $manifestPath"
        }
        if ($manifest.promotion_state -ne "blocked" -or $manifest.status -ne "blocked_until_repo_contract_review") {
            Add-Failure "Express live validation must not promote candidate manifest: $manifestPath"
        }
        foreach ($validationField in @("assertion_build_validation", "build_validation", "template_validation", "live_validation")) {
            $manifestValidation = Get-PropertyValue -Object $manifest -Name $validationField
            $summaryValidation = Get-PropertyValue -Object $record -Name $validationField
            if (-not (Test-PassedValidation -Value $manifestValidation)) {
                Add-Failure "Express candidate manifest missing passed ${validationField}: $manifestPath"
            } elseif (-not (Test-SameValidationRecord -Left $manifestValidation -Right $summaryValidation)) {
                Add-Failure "Express candidate manifest ${validationField} must equal live summary record: $manifestPath"
            }
        }
        $gateMap = @{}
        foreach ($gate in @($manifest.dependency_gates)) {
            $gateMap[[string]$gate.gate_id] = $gate
        }
        foreach ($gateId in @("plain-text-body-assertion-or-hook", "qaas-template", "qaas-live-act-assert")) {
            if (-not $gateMap.ContainsKey($gateId)) {
                Add-Failure "Express candidate manifest missing QaaS gate ${gateId}: $manifestPath"
                continue
            }
            $gate = $gateMap[$gateId]
            if ($gate.status -ne "passed") {
                Add-Failure "Express candidate QaaS gate ${gateId} must be passed when live evidence passed: $manifestPath"
            }
            if (-not (@($gate.evidence) -contains $SummaryPath)) {
                Add-Failure "Express candidate QaaS gate ${gateId} must cite live summary: $manifestPath"
            }
        }
        $airgappedGate = $gateMap["airgapped-validation"]
        if ($null -eq $airgappedGate -or $airgappedGate.status -ne "blocked" -or [string]::IsNullOrWhiteSpace([string]$airgappedGate.blocked_reason)) {
            Add-Failure "Express candidate airgapped gate must remain blocked: $manifestPath"
        }
        foreach ($removedBlocker in @("express-text-body-hook-not-template-validated", "qaas-template-live-not-run")) {
            if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq $removedBlocker }).Count -ne 0) {
                Add-Failure "Passed Express live validation should remove ${removedBlocker} blocker: $manifestPath"
            }
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "httpstatus-docs-inconsistency-recorded" }).Count -ne 0) {
            Add-Failure "Passed Express live validation should move httpstatus-docs-inconsistency-recorded to validation_advisories: $manifestPath"
        }
        $validationAdvisories = @(Get-PropertyValue -Object $manifest -Name "validation_advisories" | Where-Object { $null -ne $_ })
        if (@($validationAdvisories | Where-Object { $_.advisory_id -eq "httpstatus-docs-inconsistency-recorded" -and $_.blocking -eq $false }).Count -eq 0) {
            Add-Failure "Passed Express live validation must retain non-blocking HttpStatus docs advisory: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "live-airgapped-weak-model-not-passed" }).Count -eq 0) {
            Add-Failure "Express candidate must keep live-airgapped-weak-model-not-passed blocker: $manifestPath"
        }
        if ($manifest.airgapped_validation.status -eq "passed") {
            Add-Failure "Express candidate airgapped validation must not be passed after live QaaS only: $manifestPath"
        }
        $packet = @($manifest.custom_assertion_packets | Where-Object { $_.assertion_name -eq "ExactHttpTextBody" }) | Select-Object -First 1
        if ($null -eq $packet) {
            Add-Failure "Express manifest missing ExactHttpTextBody packet after live validation: $manifestPath"
        } else {
            if ($packet.status -ne "build_template_live_validated_blocked_until_airgapped" -or $packet.activation -ne "staged_live_runner_only" -or $packet.wired_into_runner_yaml -ne $true) {
                Add-Failure "Express manifest ExactHttpTextBody packet not marked as staged live validated: $manifestPath"
            }
            foreach ($field in @("build", "schema", "template", "live")) {
                if ($packet.validation_records.$field -ne "passed") {
                    Add-Failure "Express manifest ExactHttpTextBody packet validation ${field} must be passed: $manifestPath"
                }
            }
            if ($packet.validation_records.airgapped -ne "not_run" -or $packet.weak_validation_passed -ne $false) {
                Add-Failure "Express manifest ExactHttpTextBody packet must keep airgapped not_run and weak false: $manifestPath"
            }
        }
    }

    if ($null -eq $runtimePlan) {
        Add-Failure "Passed Express live validation requires candidate runtime plan."
    } else {
        if ($runtimePlan.promotion_state -ne "blocked") {
            Add-Failure "Express runtime plan must remain blocked after live pass: $runtimePlanPath"
        }
        $runtimeQaaSValidation = Get-PropertyValue -Object $runtimePlan -Name "qaas_validation"
        if ($null -eq $runtimeQaaSValidation -or $runtimeQaaSValidation.status -ne "passed" -or $runtimeQaaSValidation.summary -ne $SummaryPath) {
            Add-Failure "Express runtime plan missing passed qaas_validation: $runtimePlanPath"
        }
        foreach ($removedBlocker in @("validate_exact_text_body_custom_assertion_schema_template_and_live", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            if (@($runtimePlan.blockers) -contains $removedBlocker) {
                Add-Failure "Express runtime plan still contains satisfied blocker ${removedBlocker}: $runtimePlanPath"
            }
        }
        foreach ($keptBlocker in @("run_live_airgapped_weak_model_validation", "run_strong_review_against_selected_contract_evidence")) {
            if (-not (@($runtimePlan.blockers) -contains $keptBlocker)) {
                Add-Failure "Express runtime plan must keep blocker ${keptBlocker}: $runtimePlanPath"
            }
        }
    }
} else {
    Add-Failure "Unexpected Express live record status '$($record.status)': $SummaryPath"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Selected Express live check passed with status $($record.status)."

