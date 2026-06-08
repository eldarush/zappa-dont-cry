param(
    [string]$SummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-live-fastapi.json",
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\114-fastapi-fastapi",
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
    Write-Output "Selected FastAPI live check passed: no FastAPI live QaaS evidence yet; candidate remains blocked."
    exit 0
}

Test-NoUtf8Bom -Path $SummaryPath -Description "FastAPI live summary"
Test-NoUtf8Bom -Path $manifestPath -Description "FastAPI candidate manifest"
Test-NoUtf8Bom -Path $runtimePlanPath -Description "FastAPI candidate runtime plan"

$record = if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) { Read-JsonFile -Path $SummaryPath } else { $null }
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-JsonFile -Path $manifestPath } else { $null }
$runtimePlan = if (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf) { Read-JsonFile -Path $runtimePlanPath } else { $null }

if ($null -ne $record) {
    if ($record.repository -ne "fastapi/fastapi") {
        Add-Failure "FastAPI live record repository mismatch: $($record.repository)"
    }
    if ($record.validation_kind -ne "selected_candidate_qaas_template_live") {
        Add-Failure "FastAPI live record validation_kind mismatch: $($record.validation_kind)"
    }
    if ($record.promotion_state -ne "blocked" -or $record.completion_ready -ne $false) {
        Add-Failure "FastAPI live record must remain blocked and not completion-ready: $SummaryPath"
    }
}

if ($null -eq $record) {
    Add-Failure "FastAPI live summary missing: $SummaryPath"
} elseif ($record.status -eq "blocked") {
    if ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
        Add-Failure "Blocked FastAPI live record must include a reason: $SummaryPath"
    }
} elseif ($record.status -eq "failed") {
    Add-Failure "Latest FastAPI selected live validation failed: $SummaryPath"
} elseif ($record.status -eq "passed") {
    if ($record.manifest_updated -ne $true) {
        Add-Failure "Passed FastAPI live record must prove manifest_updated true: $SummaryPath"
    }
    if ([int]$record.exit_code -ne 0) {
        Add-Failure "Passed FastAPI live record must have exit_code 0: $SummaryPath"
    }
    if ($record.response_contract_passed -ne $true -or [int]$record.response_status -ne 200) {
        Add-Failure "Passed FastAPI live record must prove HTTP 200 response contract: $SummaryPath"
    }
    if ($record.cleanup_passed -ne $true) {
        Add-Failure "Passed FastAPI live record must prove cleanup: $SummaryPath"
    }
    if ([int]$record.port_owners_after_cleanup_count -ne 0) {
        Add-Failure "Passed FastAPI live record must have zero port owners after cleanup: $SummaryPath"
    }
    if (@($record.remaining_tracked_process_ids).Count -ne 0) {
        Add-Failure "Passed FastAPI live record must have no remaining tracked process ids: $SummaryPath"
    }
    if ((Get-PortOwnerCount -Port 8000) -ne 0) {
        Add-Failure "Port 8000 is currently still owned after FastAPI live validation."
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "FastAPI live validation must not claim weak model validation passed: $SummaryPath"
    }
    if ($record.install_command -ne 'python -m pip install "fastapi[standard]"') {
        Add-Failure "FastAPI live record install_command mismatch: $SummaryPath"
    }
    if ([string]::IsNullOrWhiteSpace([string]$record.fastapi_module_version) -or [string]::IsNullOrWhiteSpace([string]$record.uvicorn_module_version)) {
        Add-Failure "FastAPI live record must include fastapi_module_version and uvicorn_module_version: $SummaryPath"
    }

    foreach ($field in @("transcript", "fastapi_stdout", "fastapi_stderr", "response", "runner_yaml", "source_runner_yaml", "pip_install_stdout", "pip_install_stderr", "venv_create_stdout", "venv_create_stderr")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        $root = if ($field -eq "source_runner_yaml") { $CandidateRoot } else { $LiveRoot }
        [void](Test-ExistingFileUnderRoot -Path $value -Root $root -Description "FastAPI live ${field}")
    }
    $runDir = [string]$record.run_dir
    if (-not (Test-Path -LiteralPath $runDir -PathType Container) -or -not (Test-PathUnderRoot -Path $runDir -Root $LiveRoot)) {
        Add-Failure "FastAPI live run_dir must exist under ${LiveRoot}: $runDir"
    }
    if (-not (Test-PathEquals -Actual ([string]$record.manifest) -Expected $manifestPath)) {
        Add-Failure "FastAPI live record manifest path mismatch: $SummaryPath"
    }
    if (-not (Test-PathEquals -Actual ([string]$record.runtime_plan) -Expected $runtimePlanPath)) {
        Add-Failure "FastAPI live record runtime_plan path mismatch: $SummaryPath"
    }

    foreach ($validationField in @("build_validation", "template_validation", "live_validation")) {
        $validation = Get-PropertyValue -Object $record -Name $validationField
        if (-not (Test-PassedValidation -Value $validation)) {
            Add-Failure "FastAPI live record missing passed ${validationField}: $SummaryPath"
        } else {
            $transcriptPath = [string](Get-PropertyValue -Object $validation -Name "transcript")
            if (-not (Test-PathUnderRoot -Path $transcriptPath -Root $LiveRoot)) {
                Add-Failure "FastAPI live ${validationField} transcript must stay under ${LiveRoot}: $transcriptPath"
            }
            Test-NoUtf8Bom -Path $transcriptPath -Description "FastAPI live ${validationField} transcript"
        }
    }

    $hashes = $record.source_hashes
    $sourceYamlPath = Join-Path $CandidateDir "test.qaas.yaml"
    $sourceSchemaPath = Join-Path $CandidateDir "schemas\item-response.schema.json"
    $sourcePayloadPath = Join-Path $CandidateDir "request-payloads\get-items-5.bin"
    $sourceAppPath = Join-Path $CandidateDir "app\main.py"
    $stagedYamlPath = [string]$record.runner_yaml
    $stagedRunnerRoot = Split-Path -Parent $stagedYamlPath
    $stagedSchemaPath = Join-Path $stagedRunnerRoot "schemas\item-response.schema.json"
    $stagedPayloadPath = Join-Path $stagedRunnerRoot "request-payloads\get-items-5.bin"
    $stagedAppPath = Join-Path ([string]$record.run_dir) "fastapi-work\main.py"
    foreach ($hashSpec in @(
        @("candidate_yaml_sha256", $sourceYamlPath),
        @("staged_yaml_sha256", $stagedYamlPath),
        @("candidate_schema_sha256", $sourceSchemaPath),
        @("staged_schema_sha256", $stagedSchemaPath),
        @("candidate_request_payload_sha256", $sourcePayloadPath),
        @("staged_request_payload_sha256", $stagedPayloadPath),
        @("candidate_app_sha256", $sourceAppPath),
        @("staged_app_sha256", $stagedAppPath)
    )) {
        $hashField = [string]$hashSpec[0]
        $hashPath = [string]$hashSpec[1]
        $root = if ($hashField.StartsWith("staged_", [System.StringComparison]::Ordinal)) { $LiveRoot } else { $CandidateDir }
        if (-not (Test-PathUnderRoot -Path $hashPath -Root $root)) {
            Add-Failure "FastAPI ${hashField} file must stay under ${root}: $hashPath"
            continue
        }
        $actualHash = Get-Sha256Hex -Path $hashPath
        if ([string](Get-PropertyValue -Object $hashes -Name $hashField) -ne $actualHash) {
            Add-Failure "FastAPI live source hash ${hashField} does not match actual file: $hashPath"
        }
    }
    foreach ($pair in @(
        @("candidate_yaml_sha256", "staged_yaml_sha256"),
        @("candidate_schema_sha256", "staged_schema_sha256"),
        @("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        @("candidate_app_sha256", "staged_app_sha256")
    )) {
        if ([string](Get-PropertyValue -Object $hashes -Name $pair[0]) -ne [string](Get-PropertyValue -Object $hashes -Name $pair[1])) {
            Add-Failure "FastAPI live source hash mismatch $($pair[0])/$($pair[1]): $SummaryPath"
        }
    }

    $response = Read-JsonFile -Path ([string]$record.response)
    if ([int]$response.item_id -ne 5 -or [string]$response.q -ne "somequery" -or @($response.PSObject.Properties).Count -ne 2) {
        Add-Failure "FastAPI live response does not match README-backed contract: $($record.response)"
    }

    $runnerYamlText = Get-Content -LiteralPath ([string]$record.runner_yaml) -Raw
    if ($runnerYamlText -notmatch [regex]::Escape("Route: items/5?q=somequery")) {
        Add-Failure "FastAPI staged runner YAML must omit leading slash route: $($record.runner_yaml)"
    }
    if ($runnerYamlText -match [regex]::Escape("Route: /items/5?q=somequery")) {
        Add-Failure "FastAPI staged runner YAML must not use leading slash route: $($record.runner_yaml)"
    }

    $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
    foreach ($requiredText in @(
        "FastApiCommand: fastapi dev",
        'InstallCommand: python -m pip install "fastapi[standard]"',
        "Ready: True",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "ExitCode: 0"
    )) {
        if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "FastAPI live transcript missing required text '$requiredText': $($record.transcript)"
        }
    }

    $liveTranscriptText = Get-Content -LiteralPath ([string]$record.live_validation.transcript) -Raw
    foreach ($requiredText in @(
        "HTTP Get request to http://127.0.0.1:8000/items/5?q=somequery completed with status 200.",
        "Running assertion HttpStatus GetItemFiveReturnedOk",
        "Running assertion ObjectOutputJsonSchema GetItemFiveBodyMatchesReadmeSchema",
        "Runner completed. ExitCode=0"
    )) {
        if ($liveTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "FastAPI live Runner transcript missing required text '$requiredText': $($record.live_validation.transcript)"
        }
    }
    if ($liveTranscriptText.Contains("http://127.0.0.1:8000//items/5")) {
        Add-Failure "FastAPI live Runner transcript must not contain double-slash route: $($record.live_validation.transcript)"
    }

    if ($null -eq $manifest) {
        Add-Failure "Passed FastAPI live validation requires candidate manifest."
    } else {
        $manifestHasQaaSValidation = (
            ($manifest.PSObject.Properties.Name -contains "selected_candidate_qaas_validation") -and
            $manifest.selected_candidate_qaas_validation.status -eq "passed" -and
            $manifest.selected_candidate_qaas_validation.summary -eq $SummaryPath
        )
        if (-not $manifestHasQaaSValidation) {
            Add-Failure "Passed FastAPI live evidence has not been adopted by current manifest: $manifestPath"
        }
        if ($manifest.promotion_state -ne "blocked" -or $manifest.status -ne "blocked_until_repo_contract_review") {
            Add-Failure "FastAPI live validation must not promote candidate manifest: $manifestPath"
        }
        foreach ($validationField in @("build_validation", "template_validation", "live_validation")) {
            $manifestValidation = Get-PropertyValue -Object $manifest -Name $validationField
            $summaryValidation = Get-PropertyValue -Object $record -Name $validationField
            if (-not (Test-PassedValidation -Value $manifestValidation)) {
                Add-Failure "FastAPI candidate manifest missing passed ${validationField}: $manifestPath"
            } elseif (-not (Test-SameValidationRecord -Left $manifestValidation -Right $summaryValidation)) {
                Add-Failure "FastAPI candidate manifest ${validationField} must equal live summary record: $manifestPath"
            }
        }
        $gateMap = @{}
        foreach ($gate in @($manifest.dependency_gates)) {
            $gateMap[[string]$gate.gate_id] = $gate
        }
        foreach ($gateId in @("qaas-template", "qaas-live-act-assert")) {
            if (-not $gateMap.ContainsKey($gateId)) {
                Add-Failure "FastAPI candidate manifest missing QaaS gate ${gateId}: $manifestPath"
                continue
            }
            $gate = $gateMap[$gateId]
            if ($gate.status -ne "passed") {
                Add-Failure "FastAPI candidate QaaS gate ${gateId} must be passed when live evidence passed: $manifestPath"
            }
            if (-not (@($gate.evidence) -contains $SummaryPath)) {
                Add-Failure "FastAPI candidate QaaS gate ${gateId} must cite live summary: $manifestPath"
            }
        }
        $airgappedGate = $gateMap["airgapped-validation"]
        if ($null -eq $airgappedGate -or $airgappedGate.status -ne "blocked" -or [string]::IsNullOrWhiteSpace([string]$airgappedGate.blocked_reason)) {
            Add-Failure "FastAPI candidate airgapped gate must remain blocked: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "qaas-template-live-not-run" }).Count -ne 0) {
            Add-Failure "Passed FastAPI live validation should remove qaas-template-live-not-run blocker: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "httpstatus-docs-inconsistency-recorded" }).Count -ne 0) {
            Add-Failure "Passed FastAPI live validation should move httpstatus-docs-inconsistency-recorded to validation_advisories: $manifestPath"
        }
        $validationAdvisories = @(Get-PropertyValue -Object $manifest -Name "validation_advisories" | Where-Object { $null -ne $_ })
        if (@($validationAdvisories | Where-Object { $_.advisory_id -eq "httpstatus-docs-inconsistency-recorded" -and $_.blocking -eq $false }).Count -eq 0) {
            Add-Failure "Passed FastAPI live validation must retain non-blocking HttpStatus docs advisory: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "live-airgapped-weak-model-not-passed" }).Count -eq 0) {
            Add-Failure "FastAPI candidate must keep live-airgapped-weak-model-not-passed blocker: $manifestPath"
        }
        if ($manifest.airgapped_validation.status -eq "passed") {
            Add-Failure "FastAPI candidate airgapped validation must not be passed after live QaaS only: $manifestPath"
        }
    }

    if ($null -eq $runtimePlan) {
        Add-Failure "Passed FastAPI live validation requires candidate runtime plan."
    } else {
        if ($runtimePlan.promotion_state -ne "blocked") {
            Add-Failure "FastAPI runtime plan must remain blocked after live pass: $runtimePlanPath"
        }
        $runtimeQaaSValidation = Get-PropertyValue -Object $runtimePlan -Name "qaas_validation"
        if ($null -eq $runtimeQaaSValidation -or $runtimeQaaSValidation.status -ne "passed" -or $runtimeQaaSValidation.summary -ne $SummaryPath) {
            Add-Failure "FastAPI runtime plan missing passed qaas_validation: $runtimePlanPath"
        }
        foreach ($removedBlocker in @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            if (@($runtimePlan.blockers) -contains $removedBlocker) {
                Add-Failure "FastAPI runtime plan still contains satisfied blocker ${removedBlocker}: $runtimePlanPath"
            }
        }
        foreach ($keptBlocker in @("run_live_airgapped_weak_model_validation", "run_strong_review_against_selected_contract_evidence")) {
            if (-not (@($runtimePlan.blockers) -contains $keptBlocker)) {
                Add-Failure "FastAPI runtime plan must keep blocker ${keptBlocker}: $runtimePlanPath"
            }
        }
    }
} else {
    Add-Failure "Unexpected FastAPI live record status '$($record.status)': $SummaryPath"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Selected FastAPI live check passed with status $($record.status)."
