param(
    [string]$SummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-live.json",
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\200-typicode-json-server",
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

    return $true
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

if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    Write-Output "Selected top-repo candidate live check passed: no live QaaS evidence yet; candidate remains blocked."
    exit 0
}

Test-NoUtf8Bom -Path $SummaryPath -Description "Live summary"
Test-NoUtf8Bom -Path $manifestPath -Description "Candidate manifest"
Test-NoUtf8Bom -Path $runtimePlanPath -Description "Candidate runtime plan"

$record = Read-JsonFile -Path $SummaryPath
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-JsonFile -Path $manifestPath } else { $null }
$runtimePlan = if (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf) { Read-JsonFile -Path $runtimePlanPath } else { $null }

if ($record.repository -ne "typicode/json-server") {
    Add-Failure "Live record repository mismatch: $($record.repository)"
}
if ($record.promotion_state -ne "blocked" -or $record.completion_ready -ne $false) {
    Add-Failure "Live record must remain blocked and not completion-ready: $SummaryPath"
}

if ($record.status -eq "blocked") {
    if ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
        Add-Failure "Blocked live record must include a reason: $SummaryPath"
    }
} elseif ($record.status -eq "passed") {
    $manifestHasQaaSValidation = (
        $null -ne $manifest -and
        ($manifest.PSObject.Properties.Name -contains "selected_candidate_qaas_validation") -and
        $manifest.selected_candidate_qaas_validation.status -eq "passed"
    )
    if (-not $manifestHasQaaSValidation) {
        Write-Output "Selected top-repo candidate live check passed: stale live evidence exists but current manifest has not adopted it; candidate remains blocked."
        exit 0
    }

    foreach ($field in @("transcript", "json_server_stdout", "json_server_stderr", "response")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        [void](Test-ExistingFileUnderRoot -Path $value -Root $LiveRoot -Description "Live ${field}")
        Test-NoUtf8Bom -Path $value -Description "Live ${field}"
    }
    foreach ($validationField in @("build_validation", "template_validation", "live_validation")) {
        $validation = Get-PropertyValue -Object $record -Name $validationField
        if (-not (Test-PassedValidation -Value $validation)) {
            Add-Failure "Live record missing passed ${validationField}: $SummaryPath"
        } else {
            $transcriptPath = [string](Get-PropertyValue -Object $validation -Name "transcript")
            if (-not (Test-PathUnderRoot -Path $transcriptPath -Root $LiveRoot)) {
                Add-Failure "Live ${validationField} transcript must stay under ${LiveRoot}: $transcriptPath"
            }
            Test-NoUtf8Bom -Path $transcriptPath -Description "Live ${validationField} transcript"
        }
    }

    if ($record.package_spec -ne "json-server@1.0.0-beta.15") {
        Add-Failure "Live record must pin selected json-server package, got $($record.package_spec)"
    }
    if ([int]$record.exit_code -ne 0) {
        Add-Failure "Passed live record must have exit_code 0: $SummaryPath"
    }
    if ($record.response_contract_passed -ne $true -or [int]$record.response_status -ne 200) {
        Add-Failure "Passed live record must prove HTTP 200 response contract: $SummaryPath"
    }
    if ($record.cleanup_passed -ne $true) {
        Add-Failure "Passed live record must prove cleanup: $SummaryPath"
    }
    if ([int]$record.port_owners_after_cleanup_count -ne 0) {
        Add-Failure "Passed live record must have zero port owners after cleanup: $SummaryPath"
    }
    if ((Get-PortOwnerCount -Port 3000) -ne 0) {
        Add-Failure "Port 3000 is currently still owned after live validation."
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "Live QaaS validation must not claim weak model validation passed: $SummaryPath"
    }

    $hashes = $record.source_hashes
    foreach ($pair in @(
        @("candidate_yaml_sha256", "staged_yaml_sha256"),
        @("candidate_csv_sha256", "staged_csv_sha256"),
        @("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        @("candidate_db_sha256", "staged_db_sha256")
    )) {
        if ([string](Get-PropertyValue -Object $hashes -Name $pair[0]) -ne [string](Get-PropertyValue -Object $hashes -Name $pair[1])) {
            Add-Failure "Live source hash mismatch $($pair[0])/$($pair[1]): $SummaryPath"
        }
    }

    $response = Read-JsonFile -Path ([string]$record.response)
    if ([string]$response.id -ne "1" -or [string]$response.title -ne "a title" -or [int]$response.views -ne 100) {
        Add-Failure "Live response does not match README-backed contract: $($record.response)"
    }

    $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
    foreach ($requiredText in @("PackageSpec: json-server@1.0.0-beta.15", "Ready: True", "BuildPassed: True", "TemplatePassed: True", "LivePassed: True", "CleanupPassed: True", "ExitCode: 0")) {
        if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Live transcript missing required text '$requiredText': $($record.transcript)"
        }
    }

    $liveTranscriptText = Get-Content -LiteralPath ([string]$record.live_validation.transcript) -Raw
    foreach ($requiredText in @("HTTP Get request to http://127.0.0.1:3000//posts/1 completed with status 200.", "Running assertion HttpStatus GetPostOneReturnedOk", "Running assertion OutputContentByExpectedCsvResults GetPostOneBodyMatchesReadme", "Runner completed. ExitCode=0")) {
        if ($liveTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Live Runner transcript missing required text '$requiredText': $($record.live_validation.transcript)"
        }
    }

    if ($null -eq $manifest) {
        Add-Failure "Passed live validation requires candidate manifest."
    } else {
        if ($manifest.promotion_state -ne "blocked" -or $manifest.status -ne "blocked_until_repo_contract_review") {
            Add-Failure "Live validation must not promote candidate manifest: $manifestPath"
        }
        foreach ($validationField in @("build_validation", "template_validation", "live_validation")) {
            if (-not (Test-PassedValidation -Value (Get-PropertyValue -Object $manifest -Name $validationField))) {
                Add-Failure "Candidate manifest missing passed ${validationField}: $manifestPath"
            }
        }
        if ($manifest.selected_candidate_qaas_validation.summary -ne $SummaryPath) {
            Add-Failure "Candidate manifest selected_candidate_qaas_validation must cite latest summary: $manifestPath"
        }
        $gateMap = @{}
        foreach ($gate in @($manifest.dependency_gates)) {
            $gateMap[[string]$gate.gate_id] = $gate
        }
        foreach ($gateId in @("qaas-template", "qaas-live-act-assert")) {
            if (-not $gateMap.ContainsKey($gateId)) {
                Add-Failure "Candidate manifest missing QaaS gate ${gateId}: $manifestPath"
                continue
            }
            $gate = $gateMap[$gateId]
            if ($gate.status -ne "passed") {
                Add-Failure "Candidate QaaS gate ${gateId} must be passed when live evidence passed: $manifestPath"
            }
            if (-not (@($gate.evidence) -contains $SummaryPath)) {
                Add-Failure "Candidate QaaS gate ${gateId} must cite live summary: $manifestPath"
            }
        }
        $airgappedGate = $gateMap["airgapped-validation"]
        if ($null -eq $airgappedGate -or $airgappedGate.status -ne "blocked" -or [string]::IsNullOrWhiteSpace([string]$airgappedGate.blocked_reason)) {
            Add-Failure "Candidate airgapped gate must remain blocked: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "qaas-template-live-not-run" }).Count -ne 0) {
            Add-Failure "Passed live validation should remove qaas-template-live-not-run blocker: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "httpstatus-docs-inconsistency-recorded" }).Count -ne 0) {
            Add-Failure "Passed live validation should move httpstatus-docs-inconsistency-recorded to validation_advisories: $manifestPath"
        }
        $validationAdvisories = @(Get-PropertyValue -Object $manifest -Name "validation_advisories" | Where-Object { $null -ne $_ })
        if (@($validationAdvisories | Where-Object { $_.advisory_id -eq "httpstatus-docs-inconsistency-recorded" -and $_.blocking -eq $false }).Count -eq 0) {
            Add-Failure "Passed live validation must retain non-blocking HttpStatus docs advisory: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "live-airgapped-weak-model-not-passed" }).Count -eq 0) {
            Add-Failure "Candidate must keep live-airgapped-weak-model-not-passed blocker: $manifestPath"
        }
        if ($manifest.airgapped_validation.status -eq "passed") {
            Add-Failure "Candidate airgapped validation must not be passed after live QaaS only: $manifestPath"
        }
        if ($record.weak_validation_passed -ne $false) {
            Add-Failure "Live record weak_validation_passed must remain false until live airgapped candidate validation passes: $SummaryPath"
        }
    }

    if ($null -eq $runtimePlan) {
        Add-Failure "Passed live validation requires candidate runtime plan."
    } else {
        if ($runtimePlan.promotion_state -ne "blocked") {
            Add-Failure "Runtime plan must remain blocked after live pass: $runtimePlanPath"
        }
        if ($null -eq $runtimePlan.qaas_validation -or $runtimePlan.qaas_validation.status -ne "passed") {
            Add-Failure "Runtime plan missing passed qaas_validation: $runtimePlanPath"
        }
        foreach ($removedBlocker in @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            if (@($runtimePlan.blockers) -contains $removedBlocker) {
                Add-Failure "Runtime plan still contains satisfied blocker ${removedBlocker}: $runtimePlanPath"
            }
        }
        if (-not (@($runtimePlan.blockers) -contains "run_live_airgapped_weak_model_validation")) {
            Add-Failure "Runtime plan must keep live weak-model blocker: $runtimePlanPath"
        }
    }
} elseif ($record.status -eq "failed") {
    Add-Failure "Latest selected live validation failed: $SummaryPath"
} else {
    Add-Failure "Unexpected live record status '$($record.status)': $SummaryPath"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Selected top-repo candidate live check passed with status $($record.status)."
