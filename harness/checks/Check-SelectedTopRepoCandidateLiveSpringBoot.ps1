param(
    [string]$SummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-live-spring-boot.json",
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\177-spring-projects-spring-boot",
    [string]$CandidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates",
    [string]$SelectedContractsRoot = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts",
    [string]$CoverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage",
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

$candidateRootPath = [System.IO.Path]::GetFullPath($CandidateRoot)
if (-not (Test-PathUnderRoot -Path $CandidateDir -Root $candidateRootPath)) {
    Add-Failure "CandidateDir must stay under $candidateRootPath; got $CandidateDir"
}

$manifestPath = Join-Path $CandidateDir "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $CandidateDir "candidate-runtime-plan.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Add-Failure "Missing Spring Boot candidate manifest: $manifestPath"
}
if (-not (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf)) {
    Add-Failure "Missing Spring Boot candidate runtime plan: $runtimePlanPath"
}

if ($failures.Count -eq 0 -and -not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    Write-Output "Selected Spring Boot live check passed: no Spring Boot live QaaS evidence yet; candidate remains blocked."
    exit 0
}

Test-NoUtf8Bom -Path $SummaryPath -Description "Spring Boot live summary"
Test-NoUtf8Bom -Path $manifestPath -Description "Spring Boot candidate manifest"
Test-NoUtf8Bom -Path $runtimePlanPath -Description "Spring Boot candidate runtime plan"

$record = if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) { Read-JsonFile -Path $SummaryPath } else { $null }
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-JsonFile -Path $manifestPath } else { $null }
$runtimePlan = if (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf) { Read-JsonFile -Path $runtimePlanPath } else { $null }

if ($null -eq $record) {
    Add-Failure "Spring Boot live summary missing: $SummaryPath"
} else {
    if ($record.repository -ne "spring-projects/spring-boot") {
        Add-Failure "Spring Boot live record repository mismatch: $($record.repository)"
    }
    if ($record.promotion_state -ne "blocked" -or $record.completion_ready -ne $false) {
        Add-Failure "Spring Boot live record must remain blocked and not completion-ready: $SummaryPath"
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "Spring Boot live validation must not claim weak model validation passed: $SummaryPath"
    }
    if ($record.status -eq "blocked") {
        if ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
            Add-Failure "Blocked Spring Boot live record must include a reason: $SummaryPath"
        }
    } elseif ($record.status -eq "failed") {
        Add-Failure "Latest Spring Boot selected live validation failed: $SummaryPath"
    } elseif ($record.status -eq "passed") {
        if ($record.validation_kind -ne "selected_candidate_qaas_template_live") {
            Add-Failure "Spring Boot live record validation_kind mismatch: $SummaryPath"
        }
        if ($record.manifest_updated -ne $true) {
            Add-Failure "Passed Spring Boot live record must prove manifest_updated true: $SummaryPath"
        }
        if ([int]$record.exit_code -ne 0) {
            Add-Failure "Passed Spring Boot live record must have exit_code 0: $SummaryPath"
        }
        if ($record.response_contract_passed -ne $true -or [int]$record.response_status -ne 200) {
            Add-Failure "Passed Spring Boot live record must prove HTTP 200 response contract: $SummaryPath"
        }
        if ($record.cleanup_passed -ne $true -or [int]$record.port_owners_after_cleanup_count -ne 0) {
            Add-Failure "Passed Spring Boot live record must prove cleanup and zero port owners: $SummaryPath"
        }
        if (@($record.remaining_tracked_process_ids).Count -ne 0) {
            Add-Failure "Passed Spring Boot live record must have no remaining tracked process ids: $SummaryPath"
        }
        if ($record.assertion_project_reference_added -ne $true) {
            Add-Failure "Spring Boot live record must prove assertion_project_reference_added true: $SummaryPath"
        }
        if ($record.spring_initializr_url -ne "https://start.spring.io/starter.zip" -or $record.requested_boot_version -ne "4.0.6" -or $record.generated_pom_boot_version -ne "4.0.6") {
            Add-Failure "Spring Boot live record must retain lifecycle Spring Initializr 4.0.6 evidence: $SummaryPath"
        }
        if ([int]$record.java_major_version -lt 25) {
            Add-Failure "Spring Boot live record must prove Java 25 or newer: $SummaryPath"
        }
        foreach ($field in @("transcript", "stdout", "stderr", "response", "runner_yaml", "runner_program", "runner_project", "assertion_project", "assertion_source", "assertion_project_reference_transcript")) {
            [void](Test-ExistingFileUnderRoot -Path ([string](Get-PropertyValue -Object $record -Name $field)) -Root $LiveRoot -Description "Spring Boot live ${field}")
        }
        foreach ($field in @("source_runner_yaml", "source_assertion")) {
            [void](Test-ExistingFileUnderRoot -Path ([string](Get-PropertyValue -Object $record -Name $field)) -Root $CandidateDir -Description "Spring Boot live ${field}")
        }
        [void](Test-ExistingDirectoryUnderRoot -Path ([string]$record.run_dir) -Root $LiveRoot -Description "Spring Boot live run_dir")
        foreach ($validationField in @("assertion_build_validation", "build_validation", "template_validation", "live_validation")) {
            $validation = Get-PropertyValue -Object $record -Name $validationField
            if (-not (Test-PassedValidation -Value $validation)) {
                Add-Failure "Spring Boot live record missing passed ${validationField}: $SummaryPath"
                continue
            }
            $transcriptPath = [string](Get-PropertyValue -Object $validation -Name "transcript")
            [void](Test-ExistingFileUnderRoot -Path $transcriptPath -Root $LiveRoot -Description "Spring Boot live ${validationField} transcript")
        }
        if ((Get-Content -LiteralPath ([string]$record.response) -Raw) -ne "Hello World!") {
            Add-Failure "Spring Boot live response must exactly match README-backed text body: $($record.response)"
        }
        $liveTranscriptText = Get-Content -LiteralPath ([string]$record.live_validation.transcript) -Raw
        foreach ($requiredText in @(
            "Found IAssertion hook instance ExactHttpTextBody",
            "HTTP Get request to http://127.0.0.1:8080/ completed with status 200.",
            "Running assertion ExactHttpTextBody GetRootBodyMatchesReadme",
            "Running assertion HttpStatus GetRootReturnedOk",
            "Runner completed. ExitCode=0"
        )) {
            if ($liveTranscriptText -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Spring Boot live Runner transcript missing required text '$requiredText': $($record.live_validation.transcript)"
            }
        }
        if ($liveTranscriptText.Contains("http://127.0.0.1:8080//")) {
            Add-Failure "Spring Boot live Runner transcript must not contain double-slash root URL: $($record.live_validation.transcript)"
        }
        $manifestValidation = Get-PropertyValue -Object $manifest -Name "selected_candidate_qaas_validation"
        if ($null -eq $manifestValidation -or $manifestValidation.status -ne "passed" -or $manifestValidation.summary -ne $SummaryPath) {
            Add-Failure "Passed Spring Boot live evidence has not been adopted by current manifest: $manifestPath"
        }
        $runtimeValidation = Get-PropertyValue -Object $runtimePlan -Name "qaas_validation"
        if ($null -eq $runtimeValidation -or $runtimeValidation.status -ne "passed" -or $runtimeValidation.summary -ne $SummaryPath) {
            Add-Failure "Passed Spring Boot live evidence has not been adopted by current runtime plan: $runtimePlanPath"
        }
        foreach ($blockerId in @("spring-boot-text-body-hook-not-template-validated", "qaas-template-live-not-run")) {
            if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq $blockerId }).Count -ne 0) {
                Add-Failure "Passed Spring Boot live validation should remove ${blockerId}: $manifestPath"
            }
        }
        foreach ($blockerId in @("spring-boot-broad-runtime-coverage-not-selected", "live-airgapped-weak-model-not-passed")) {
            if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq $blockerId }).Count -eq 0) {
                Add-Failure "Spring Boot candidate must keep blocker ${blockerId}: $manifestPath"
            }
        }
        $checker = Join-Path $PSScriptRoot "Check-SelectedTopRepoCandidates.py"
        & python $checker $CandidateRoot $SelectedContractsRoot $CoverageDir
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "Spring Boot selected candidate checker rejected adopted live evidence."
        }
    } else {
        Add-Failure "Unexpected Spring Boot live record status '$($record.status)': $SummaryPath"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Selected Spring Boot live check passed with status $($record.status)."
