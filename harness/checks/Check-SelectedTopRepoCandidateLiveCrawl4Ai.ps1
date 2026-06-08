param(
    [string]$SummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-live-crawl4ai.json",
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\250-unclecode-crawl4ai",
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
    Write-Output "Selected Crawl4AI live check passed: no Crawl4AI live QaaS evidence yet; candidate remains blocked."
    exit 0
}

Test-NoUtf8Bom -Path $SummaryPath -Description "Crawl4AI live summary"
Test-NoUtf8Bom -Path $manifestPath -Description "Crawl4AI candidate manifest"
Test-NoUtf8Bom -Path $runtimePlanPath -Description "Crawl4AI candidate runtime plan"

$record = if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) { Read-JsonFile -Path $SummaryPath } else { $null }
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-JsonFile -Path $manifestPath } else { $null }
$runtimePlan = if (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf) { Read-JsonFile -Path $runtimePlanPath } else { $null }

if ($null -ne $record) {
    if ($record.repository -ne "unclecode/crawl4ai") {
        Add-Failure "Crawl4AI live record repository mismatch: $($record.repository)"
    }
    $validationKind = [string](Get-PropertyValue -Object $record -Name "validation_kind")
    if ($validationKind -ne "selected_candidate_qaas_template_live" -and $record.status -ne "blocked") {
        Add-Failure "Crawl4AI live record validation_kind mismatch: $validationKind"
    }
    if ($record.promotion_state -ne "blocked" -or $record.completion_ready -ne $false) {
        Add-Failure "Crawl4AI live record must remain blocked and not completion-ready: $SummaryPath"
    }
}

if ($null -eq $record) {
    Add-Failure "Crawl4AI live summary missing: $SummaryPath"
} elseif ($record.status -eq "blocked") {
    if ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
        Add-Failure "Blocked Crawl4AI live record must include a reason: $SummaryPath"
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "Blocked Crawl4AI live record must not claim weak validation passed: $SummaryPath"
    }
} elseif ($record.status -eq "failed") {
    Add-Failure "Latest Crawl4AI selected live validation failed: $SummaryPath"
} elseif ($record.status -eq "passed") {
    if ($record.manifest_updated -ne $true) {
        Add-Failure "Passed Crawl4AI live record must prove manifest_updated true: $SummaryPath"
    }
    if ([int]$record.exit_code -ne 0) {
        Add-Failure "Passed Crawl4AI live record must have exit_code 0: $SummaryPath"
    }
    if ($record.response_contract_passed -ne $true -or [int]$record.response_status -ge 400) {
        Add-Failure "Passed Crawl4AI live record must prove HTTP status below 400: $SummaryPath"
    }
    if ([string]$record.response_contract -ne "http_status_less_than_400_body_unasserted") {
        Add-Failure "Crawl4AI live record must keep body unasserted status contract: $SummaryPath"
    }
    if ($record.cleanup_passed -ne $true) {
        Add-Failure "Passed Crawl4AI live record must prove Docker cleanup: $SummaryPath"
    }
    if ($record.container_exists_after_cleanup -ne $false) {
        Add-Failure "Crawl4AI test-owned container must not exist after cleanup: $SummaryPath"
    }
    if ([int]$record.port_owners_after_cleanup_count -ne 0) {
        Add-Failure "Passed Crawl4AI live record must have zero port owners after cleanup: $SummaryPath"
    }
    if ((Get-PortOwnerCount -Port 11235) -ne 0) {
        Add-Failure "Port 11235 is currently still owned after Crawl4AI live validation."
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "Crawl4AI live validation must not claim weak model validation passed: $SummaryPath"
    }
    if ($record.assertion_project_reference_added -ne $true) {
        Add-Failure "Crawl4AI live record must prove assertion_project_reference_added true: $SummaryPath"
    }
    if ([string]$record.image -ne "unclecode/crawl4ai:latest") {
        Add-Failure "Crawl4AI live image mismatch: $SummaryPath"
    }
    $containerName = [string]$record.container_name
    if ([string]::IsNullOrWhiteSpace($containerName) -or -not $containerName.StartsWith("zappa-crawl4ai-health-live-", [System.StringComparison]::Ordinal) -or $containerName -eq "crawl4ai") {
        Add-Failure "Crawl4AI live must use a unique zappa-crawl4ai-health-live-* container name: $SummaryPath"
    }
    if ([string]$record.cleanup_target_container_name -ne $containerName) {
        Add-Failure "Crawl4AI cleanup target must be the test-owned unique container: $SummaryPath"
    }
    if ([string]$record.protected_container_name -ne "crawl4ai") {
        Add-Failure "Crawl4AI live must record crawl4ai as protected user-owned container name: $SummaryPath"
    }
    if ((@($record.protected_container_names_before) -join "`n") -ne (@($record.protected_container_names_after) -join "`n")) {
        Add-Failure "Crawl4AI live changed protected crawl4ai container state: $SummaryPath"
    }

    foreach ($field in @("transcript", "response", "runner_yaml", "runner_program", "runner_project", "assertion_project", "assertion_source", "assertion_project_reference_transcript", "docker_pull_stdout", "docker_pull_stderr", "docker_run_stdout", "docker_run_stderr", "docker_rm_stdout", "docker_rm_stderr", "docker_logs_stdout", "docker_logs_stderr")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        [void](Test-ExistingFileUnderRoot -Path $value -Root $LiveRoot -Description "Crawl4AI live ${field}")
    }
    foreach ($field in @("source_runner_yaml", "source_assertion")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        [void](Test-ExistingFileUnderRoot -Path $value -Root $CandidateDir -Description "Crawl4AI live ${field}")
    }
    [void](Test-ExistingDirectoryUnderRoot -Path ([string]$record.run_dir) -Root $LiveRoot -Description "Crawl4AI live run_dir")
    if (-not (Test-PathEquals -Actual ([string]$record.manifest) -Expected $manifestPath)) {
        Add-Failure "Crawl4AI live record manifest path mismatch: $SummaryPath"
    }
    if (-not (Test-PathEquals -Actual ([string]$record.runtime_plan) -Expected $runtimePlanPath)) {
        Add-Failure "Crawl4AI live record runtime_plan path mismatch: $SummaryPath"
    }

    foreach ($validationField in @("assertion_build_validation", "build_validation", "template_validation", "live_validation")) {
        $validation = Get-PropertyValue -Object $record -Name $validationField
        if (-not (Test-PassedValidation -Value $validation)) {
            Add-Failure "Crawl4AI live record missing passed ${validationField}: $SummaryPath"
        } else {
            $transcriptPath = [string](Get-PropertyValue -Object $validation -Name "transcript")
            if (-not (Test-PathUnderRoot -Path $transcriptPath -Root $LiveRoot)) {
                Add-Failure "Crawl4AI live ${validationField} transcript must stay under ${LiveRoot}: $transcriptPath"
            }
            Test-NoUtf8Bom -Path $transcriptPath -Description "Crawl4AI live ${validationField} transcript"
        }
    }

    $hashes = $record.source_hashes
    $sourceYamlPath = Join-Path $CandidateDir "test.qaas.yaml"
    $sourcePayloadPath = Join-Path $CandidateDir "request-payloads\get-health.bin"
    $sourceAssertionPath = Join-Path $CandidateDir "assertion-packets\HttpStatusBelow400\HttpStatusBelow400.cs"
    $stagedYamlPath = [string]$record.runner_yaml
    $stagedRunnerRoot = Split-Path -Parent $stagedYamlPath
    $stagedPayloadPath = Join-Path $stagedRunnerRoot "request-payloads\get-health.bin"
    $stagedAssertionPath = [string]$record.assertion_source
    foreach ($hashSpec in @(
        @("candidate_yaml_sha256", $sourceYamlPath, $CandidateDir),
        @("staged_yaml_sha256", $stagedYamlPath, $LiveRoot),
        @("candidate_request_payload_sha256", $sourcePayloadPath, $CandidateDir),
        @("staged_request_payload_sha256", $stagedPayloadPath, $LiveRoot),
        @("candidate_assertion_sha256", $sourceAssertionPath, $CandidateDir),
        @("staged_assertion_sha256", $stagedAssertionPath, $LiveRoot)
    )) {
        $hashField = [string]$hashSpec[0]
        $hashPath = [string]$hashSpec[1]
        $root = [string]$hashSpec[2]
        if (-not (Test-PathUnderRoot -Path $hashPath -Root $root)) {
            Add-Failure "Crawl4AI ${hashField} file must stay under ${root}: $hashPath"
            continue
        }
        $actualHash = Get-Sha256Hex -Path $hashPath
        if ([string](Get-PropertyValue -Object $hashes -Name $hashField) -ne $actualHash) {
            Add-Failure "Crawl4AI live source hash ${hashField} does not match actual file: $hashPath"
        }
    }
    foreach ($pair in @(
        @("candidate_yaml_sha256", "staged_yaml_sha256"),
        @("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        @("candidate_assertion_sha256", "staged_assertion_sha256")
    )) {
        if ([string](Get-PropertyValue -Object $hashes -Name $pair[0]) -ne [string](Get-PropertyValue -Object $hashes -Name $pair[1])) {
            Add-Failure "Crawl4AI live source hash mismatch $($pair[0])/$($pair[1]): $SummaryPath"
        }
    }

    $runnerYamlText = Get-Content -LiteralPath ([string]$record.runner_yaml) -Raw
    foreach ($requiredText in @("Assertion: HttpStatusBelow400", "MaximumExclusiveStatusCode: 400", "OutputNames:", "Route: health", "Port: 11235")) {
        if ($runnerYamlText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Crawl4AI staged runner YAML missing '$requiredText': $($record.runner_yaml)"
        }
    }
    foreach ($forbiddenText in @("Assertion: HttpStatus`r`n", "StatusCode: 200", "ExpectedText:", "Route: crawl", "Route: /crawl")) {
        if ($runnerYamlText -match [regex]::Escape($forbiddenText)) {
            Add-Failure "Crawl4AI staged runner YAML must not promote unsafe or invented contract '$forbiddenText': $($record.runner_yaml)"
        }
    }

    $runnerProgramText = Get-Content -LiteralPath ([string]$record.runner_program) -Raw
    if ($runnerProgramText -notmatch [regex]::Escape("System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Crawl4Ai.Assertions.HttpStatusBelow400));")) {
        Add-Failure "Crawl4AI runner Program.cs must force-load HttpStatusBelow400 assembly: $($record.runner_program)"
    }
    $runnerProjectText = Get-Content -LiteralPath ([string]$record.runner_project) -Raw
    if ($runnerProjectText -notmatch "ProjectReference" -or $runnerProjectText -notmatch "ZappaSelectedCrawl4Ai.Assertions.csproj") {
        Add-Failure "Crawl4AI runner project must reference assertion project: $($record.runner_project)"
    }
    $assertionProjectText = Get-Content -LiteralPath ([string]$record.assertion_project) -Raw
    if ($assertionProjectText -notmatch [regex]::Escape('PackageReference Include="QaaS.Framework.SDK" Version="1.5.1"')) {
        Add-Failure "Crawl4AI assertion project must reference QaaS.Framework.SDK 1.5.1: $($record.assertion_project)"
    }
    $assertionText = Get-Content -LiteralPath ([string]$record.assertion_source) -Raw
    foreach ($requiredText in @("BaseAssertion<HttpStatusBelow400Config>", "MaximumExclusiveStatusCode", "MetaData?.Http?.StatusCode", "statusCode >= Configuration.MaximumExclusiveStatusCode")) {
        if ($assertionText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Crawl4AI staged assertion source missing '$requiredText': $($record.assertion_source)"
        }
    }

    $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
    foreach ($requiredText in @(
        "DockerPullCommand: docker pull unclecode/crawl4ai:latest",
        "DockerRunCommand: docker run -d -p 127.0.0.1:11235:11235 --name zappa-crawl4ai-health-live-",
        "ReadinessUrl: http://127.0.0.1:11235/health",
        "Ready: True",
        "AssertionBuildPassed: True",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "ContainerExistsAfterCleanup: False",
        "PortOwnersAfterCleanupCount: 0",
        "ExitCode: 0"
    )) {
        if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Crawl4AI live transcript missing required text '$requiredText': $($record.transcript)"
        }
    }
    foreach ($forbiddenText in @("--name crawl4ai", "Route: /crawl", "ExpectedText:", "StatusCode: 200")) {
        if ($transcriptText -match [regex]::Escape($forbiddenText)) {
            Add-Failure "Crawl4AI live transcript must not promote unsafe or invented contract text '$forbiddenText': $($record.transcript)"
        }
    }

    $templateTranscriptText = Get-Content -LiteralPath ([string]$record.template_validation.transcript) -Raw
    foreach ($requiredText in @("Found IAssertion hook instance HttpStatusBelow400", "Assertion: HttpStatusBelow400", "Runner completed. ExitCode=0")) {
        if ($templateTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Crawl4AI template Runner transcript missing '$requiredText': $($record.template_validation.transcript)"
        }
    }

    $liveTranscriptText = Get-Content -LiteralPath ([string]$record.live_validation.transcript) -Raw
    foreach ($requiredText in @("Found IAssertion hook instance HttpStatusBelow400", "Running assertion HttpStatusBelow400 GetHealthMatchesDockerCurlF", "Runner completed. ExitCode=0")) {
        if ($liveTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Crawl4AI live Runner transcript missing required text '$requiredText': $($record.live_validation.transcript)"
        }
    }
    if ($liveTranscriptText -notmatch "HTTP Get request to http://127\.0\.0\.1:11235/health completed with status [1-3][0-9][0-9]\.") {
        Add-Failure "Crawl4AI live Runner transcript must prove /health status below 400: $($record.live_validation.transcript)"
    }
    foreach ($forbiddenText in @("http://127.0.0.1:11235/crawl", "ExpectedText:", "Running assertion HttpStatus ")) {
        if ($liveTranscriptText -match [regex]::Escape($forbiddenText)) {
            Add-Failure "Crawl4AI live Runner transcript must not promote unsafe or invented contract '$forbiddenText': $($record.live_validation.transcript)"
        }
    }

    if ($null -eq $manifest) {
        Add-Failure "Passed Crawl4AI live validation requires candidate manifest."
    } else {
        $manifestHasQaaSValidation = (
            ($manifest.PSObject.Properties.Name -contains "selected_candidate_qaas_validation") -and
            $manifest.selected_candidate_qaas_validation.status -eq "passed" -and
            $manifest.selected_candidate_qaas_validation.summary -eq $SummaryPath
        )
        if (-not $manifestHasQaaSValidation) {
            Add-Failure "Passed Crawl4AI live evidence has not been adopted by current manifest: $manifestPath"
        }
        if ($manifest.promotion_state -ne "blocked" -or $manifest.status -ne "blocked_until_repo_contract_review") {
            Add-Failure "Crawl4AI live validation must not promote candidate manifest: $manifestPath"
        }
        foreach ($validationField in @("assertion_build_validation", "build_validation", "template_validation", "live_validation")) {
            $manifestValidation = Get-PropertyValue -Object $manifest -Name $validationField
            $summaryValidation = Get-PropertyValue -Object $record -Name $validationField
            if (-not (Test-PassedValidation -Value $manifestValidation)) {
                Add-Failure "Crawl4AI candidate manifest missing passed ${validationField}: $manifestPath"
            } elseif (-not (Test-SameValidationRecord -Left $manifestValidation -Right $summaryValidation)) {
                Add-Failure "Crawl4AI candidate manifest ${validationField} must equal live summary record: $manifestPath"
            }
        }
        $gateMap = @{}
        foreach ($gate in @($manifest.dependency_gates)) {
            $gateMap[[string]$gate.gate_id] = $gate
        }
        foreach ($gateId in @("http-status-below-400-assertion-or-hook", "docker-crawl4ai-container-lifecycle", "cleanup-contract", "qaas-template", "qaas-live-act-assert")) {
            if (-not $gateMap.ContainsKey($gateId)) {
                Add-Failure "Crawl4AI candidate manifest missing QaaS gate ${gateId}: $manifestPath"
                continue
            }
            $gate = $gateMap[$gateId]
            if ($gate.status -ne "passed") {
                Add-Failure "Crawl4AI candidate QaaS gate ${gateId} must be passed when live evidence passed: $manifestPath"
            }
            if (-not (@($gate.evidence) -contains $SummaryPath) -and $gateId -in @("http-status-below-400-assertion-or-hook", "qaas-template", "qaas-live-act-assert")) {
                Add-Failure "Crawl4AI candidate QaaS gate ${gateId} must cite live summary: $manifestPath"
            }
        }
        $airgappedGate = $gateMap["airgapped-validation"]
        if ($null -eq $airgappedGate -or $airgappedGate.status -ne "blocked" -or [string]::IsNullOrWhiteSpace([string]$airgappedGate.blocked_reason)) {
            Add-Failure "Crawl4AI candidate airgapped gate must remain blocked: $manifestPath"
        }
        foreach ($removedBlocker in @("crawl4ai-docker-lifecycle-not-proven", "crawl4ai-status-below-400-hook-not-template-validated", "qaas-template-live-not-run")) {
            if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq $removedBlocker }).Count -ne 0) {
                Add-Failure "Passed Crawl4AI live/lifecycle validation should remove ${removedBlocker} blocker: $manifestPath"
            }
        }
        foreach ($keptBlocker in @("crawl4ai-health-body-contract-not-selected", "crawl4ai-crawl-endpoint-not-promoted", "live-airgapped-weak-model-not-passed")) {
            if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq $keptBlocker }).Count -eq 0) {
                Add-Failure "Crawl4AI candidate must keep blocker ${keptBlocker}: $manifestPath"
            }
        }
        if ($manifest.airgapped_validation.status -eq "passed") {
            Add-Failure "Crawl4AI candidate airgapped validation must not be passed after live QaaS only: $manifestPath"
        }
        $packet = @($manifest.custom_assertion_packets | Where-Object { $_.assertion_name -eq "HttpStatusBelow400" }) | Select-Object -First 1
        if ($null -eq $packet) {
            Add-Failure "Crawl4AI manifest missing HttpStatusBelow400 packet after live validation: $manifestPath"
        } else {
            if ($packet.status -ne "build_template_live_validated_blocked_until_airgapped" -or $packet.activation -ne "source_yaml_validated" -or $packet.wired_into_runner_yaml -ne $true) {
                Add-Failure "Crawl4AI manifest HttpStatusBelow400 packet not marked as source YAML live validated: $manifestPath"
            }
            foreach ($field in @("build", "schema", "template", "live")) {
                if ($packet.validation_records.$field -ne "passed") {
                    Add-Failure "Crawl4AI manifest HttpStatusBelow400 packet validation ${field} must be passed: $manifestPath"
                }
            }
            if ($packet.validation_records.airgapped -ne "not_run" -or $packet.weak_validation_passed -ne $false) {
                Add-Failure "Crawl4AI manifest HttpStatusBelow400 packet must keep airgapped not_run and weak false: $manifestPath"
            }
            if ($packet.output_body_assertion -ne "unasserted_no_public_body_contract" -or [int]$packet.maximum_exclusive_status_code -ne 400) {
                Add-Failure "Crawl4AI manifest HttpStatusBelow400 packet must keep status < 400 and body-unasserted contract: $manifestPath"
            }
        }
    }

    if ($null -eq $runtimePlan) {
        Add-Failure "Passed Crawl4AI live validation requires candidate runtime plan."
    } else {
        if ($runtimePlan.promotion_state -ne "blocked") {
            Add-Failure "Crawl4AI runtime plan must remain blocked after live pass: $runtimePlanPath"
        }
        $runtimeQaaSValidation = Get-PropertyValue -Object $runtimePlan -Name "qaas_validation"
        if ($null -eq $runtimeQaaSValidation -or $runtimeQaaSValidation.status -ne "passed" -or $runtimeQaaSValidation.summary -ne $SummaryPath) {
            Add-Failure "Crawl4AI runtime plan missing passed qaas_validation: $runtimePlanPath"
        }
        $assertionValidation = Get-PropertyValue -Object $runtimePlan -Name "http_status_below_400_assertion"
        if ($null -eq $assertionValidation -or $assertionValidation.status -ne "build_template_live_validated") {
            Add-Failure "Crawl4AI runtime plan missing validated HttpStatusBelow400 assertion record: $runtimePlanPath"
        }
        foreach ($removedBlocker in @("prove_docker_lifecycle_and_cleanup_without_deleting_user_container", "build_and_template_validate_http_status_below_400_assertion", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            if (@($runtimePlan.blockers) -contains $removedBlocker) {
                Add-Failure "Crawl4AI runtime plan still contains satisfied blocker ${removedBlocker}: $runtimePlanPath"
            }
        }
        foreach ($keptBlocker in @("run_live_airgapped_weak_model_validation", "run_strong_review_against_selected_contract_evidence")) {
            if (-not (@($runtimePlan.blockers) -contains $keptBlocker)) {
                Add-Failure "Crawl4AI runtime plan must keep blocker ${keptBlocker}: $runtimePlanPath"
            }
        }
    }
} else {
    Add-Failure "Unexpected Crawl4AI live record status '$($record.status)': $SummaryPath"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Selected Crawl4AI live check passed with status $($record.status)."
