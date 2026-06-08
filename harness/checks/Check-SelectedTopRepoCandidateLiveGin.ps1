param(
    [string]$SummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-live-gin.json",
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\138-gin-gonic-gin",
    [string]$CandidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates",
    [string]$LiveRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

$GinManagedGoVersion = "go version go1.26.4 windows/amd64"
$GinManagedGoDownloadUrl = "https://go.dev/dl/go1.26.4.windows-amd64.zip"
$GinManagedGoArchiveSha256 = "3ca8fb4630b07c419cbdd51f754e31363cfcfb83b3a5354d9e895c90be2cc345"
$GinManagedGoInstallLeaf = "go1.26.4-windows-amd64"
$GinModulePin = "github.com/gin-gonic/gin@v1.12.0"

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
    Write-Output "Selected Gin live check passed: no Gin live QaaS evidence yet; candidate remains blocked."
    exit 0
}

Test-NoUtf8Bom -Path $SummaryPath -Description "Gin live summary"
Test-NoUtf8Bom -Path $manifestPath -Description "Gin candidate manifest"
Test-NoUtf8Bom -Path $runtimePlanPath -Description "Gin candidate runtime plan"

$record = if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) { Read-JsonFile -Path $SummaryPath } else { $null }
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-JsonFile -Path $manifestPath } else { $null }
$runtimePlan = if (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf) { Read-JsonFile -Path $runtimePlanPath } else { $null }

if ($null -ne $record) {
    if ($record.repository -ne "gin-gonic/gin") {
        Add-Failure "Gin live record repository mismatch: $($record.repository)"
    }
    if ($record.validation_kind -ne "selected_candidate_qaas_template_live") {
        Add-Failure "Gin live record validation_kind mismatch: $($record.validation_kind)"
    }
    if ($record.promotion_state -ne "blocked" -or $record.completion_ready -ne $false) {
        Add-Failure "Gin live record must remain blocked and not completion-ready: $SummaryPath"
    }
}

if ($null -eq $record) {
    Add-Failure "Gin live summary missing: $SummaryPath"
} elseif ($record.status -eq "blocked") {
    if ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
        Add-Failure "Blocked Gin live record must include a reason: $SummaryPath"
    }
} elseif ($record.status -eq "failed") {
    Add-Failure "Latest Gin selected live validation failed: $SummaryPath"
} elseif ($record.status -eq "passed") {
    if ($record.manifest_updated -ne $true) {
        Add-Failure "Passed Gin live record must prove manifest_updated true: $SummaryPath"
    }
    if ([int]$record.exit_code -ne 0) {
        Add-Failure "Passed Gin live record must have exit_code 0: $SummaryPath"
    }
    if ($record.response_contract_passed -ne $true -or [int]$record.response_status -ne 200) {
        Add-Failure "Passed Gin live record must prove HTTP 200 response contract: $SummaryPath"
    }
    if ($record.cleanup_passed -ne $true -or [int]$record.port_owners_after_cleanup_count -ne 0) {
        Add-Failure "Passed Gin live record must prove zero-owner cleanup: $SummaryPath"
    }
    if (@($record.remaining_tracked_process_ids).Count -ne 0) {
        Add-Failure "Passed Gin live record must have no remaining tracked process ids: $SummaryPath"
    }
    if ((Get-PortOwnerCount -Port 8080) -ne 0) {
        Add-Failure "Port 8080 is currently still owned after Gin live validation."
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "Gin live validation must not claim weak model validation passed: $SummaryPath"
    }

    if ($record.go_source -ne "managed_go_toolchain") {
        Add-Failure "Gin live record must use managed_go_toolchain; got $($record.go_source)"
    }
    if ($record.go_version -ne $GinManagedGoVersion) {
        Add-Failure "Gin live go_version must be $GinManagedGoVersion; got $($record.go_version)"
    }
    if ($record.managed_toolchain_download_url -ne $GinManagedGoDownloadUrl) {
        Add-Failure "Gin live managed_toolchain_download_url must be $GinManagedGoDownloadUrl"
    }
    if ($record.managed_toolchain_archive_sha256 -ne $GinManagedGoArchiveSha256) {
        Add-Failure "Gin live managed_toolchain_archive_sha256 must be $GinManagedGoArchiveSha256"
    }
    if ($record.module_pin -ne $GinModulePin -or $record.module_pin_command -ne "go get $GinModulePin") {
        Add-Failure "Gin live module pin must be exact ${GinModulePin}: $SummaryPath"
    }
    if ($record.module_init_command -ne "go mod init zappa.local/gin-live") {
        Add-Failure "Gin live module_init_command must use zappa.local/gin-live: $SummaryPath"
    }
    if ($record.module_resolution_passed -ne $true) {
        Add-Failure "Gin live record must prove module_resolution_passed true: $SummaryPath"
    }

    $managedToolchainPath = [string]$record.managed_toolchain_path
    if ([string]::IsNullOrWhiteSpace($managedToolchainPath) -or (Split-Path -Leaf $managedToolchainPath) -ne $GinManagedGoInstallLeaf) {
        Add-Failure "Gin live managed_toolchain_path must end with ${GinManagedGoInstallLeaf}: $managedToolchainPath"
    }
    $expectedGoPath = if (-not [string]::IsNullOrWhiteSpace($managedToolchainPath)) { Join-Path $managedToolchainPath "go\bin\go.exe" } else { "" }
    if (-not (Test-PathEquals -Actual ([string]$record.go_path) -Expected $expectedGoPath)) {
        Add-Failure "Gin live go_path must be inside managed toolchain path: $($record.go_path)"
    }
    if (Test-ExistingFileUnderRoot -Path ([string]$record.managed_toolchain_archive) -Root "D:\QaaS\_tmp\zappa-dont-cry\toolchains" -Description "Gin managed Go archive") {
        $actualArchiveSha = Get-Sha256Hex -Path ([string]$record.managed_toolchain_archive)
        if ($actualArchiveSha -ne $GinManagedGoArchiveSha256) {
            Add-Failure "Gin managed Go archive hash mismatch: $($record.managed_toolchain_archive)"
        }
    }

    foreach ($field in @("transcript", "gin_stdout", "gin_stderr", "response", "runner_yaml", "source_runner_yaml", "go_env_json", "go_mod_path", "go_sum_path", "go_list_module_json")) {
        $value = [string](Get-PropertyValue -Object $record -Name $field)
        $root = if ($field -eq "source_runner_yaml") { $CandidateRoot } elseif ($field -eq "managed_toolchain_archive") { "D:\QaaS\_tmp\zappa-dont-cry\toolchains" } else { $LiveRoot }
        [void](Test-ExistingFileUnderRoot -Path $value -Root $root -Description "Gin live ${field}")
    }
    $runDir = [string]$record.run_dir
    if (-not (Test-Path -LiteralPath $runDir -PathType Container) -or -not (Test-PathUnderRoot -Path $runDir -Root $LiveRoot)) {
        Add-Failure "Gin live run_dir must exist under ${LiveRoot}: $runDir"
    }
    foreach ($dirField in @("managed_gopath", "managed_gomodcache", "managed_gocache")) {
        $dirValue = [string](Get-PropertyValue -Object $record -Name $dirField)
        if (-not (Test-Path -LiteralPath $dirValue -PathType Container) -or -not (Test-PathUnderRoot -Path $dirValue -Root $runDir)) {
            Add-Failure "Gin live ${dirField} must exist under run_dir: $dirValue"
        }
    }
    if (-not (Test-PathEquals -Actual ([string]$record.manifest) -Expected $manifestPath)) {
        Add-Failure "Gin live record manifest path mismatch: $SummaryPath"
    }
    if (-not (Test-PathEquals -Actual ([string]$record.runtime_plan) -Expected $runtimePlanPath)) {
        Add-Failure "Gin live record runtime_plan path mismatch: $SummaryPath"
    }

    $goEnv = Read-JsonFile -Path ([string]$record.go_env_json)
    foreach ($pair in @(
        @("GOROOT", "go_root"),
        @("GOPATH", "managed_gopath"),
        @("GOMODCACHE", "managed_gomodcache"),
        @("GOCACHE", "managed_gocache")
    )) {
        $envField = [string]$pair[0]
        $recordField = [string]$pair[1]
        if (-not (Test-PathEquals -Actual ([string](Get-PropertyValue -Object $goEnv -Name $envField)) -Expected ([string](Get-PropertyValue -Object $record -Name $recordField)))) {
            Add-Failure "Gin live go-env ${envField} mismatch with record ${recordField}: $SummaryPath"
        }
    }

    foreach ($validationField in @("build_validation", "template_validation", "live_validation")) {
        $validation = Get-PropertyValue -Object $record -Name $validationField
        if (-not (Test-PassedValidation -Value $validation)) {
            Add-Failure "Gin live record missing passed ${validationField}: $SummaryPath"
        } else {
            $validationTranscript = [string](Get-PropertyValue -Object $validation -Name "transcript")
            if (-not (Test-PathUnderRoot -Path $validationTranscript -Root $LiveRoot)) {
                Add-Failure "Gin live ${validationField} transcript must stay under ${LiveRoot}: $validationTranscript"
            }
            Test-NoUtf8Bom -Path $validationTranscript -Description "Gin live ${validationField} transcript"
        }
    }

    $hashes = $record.source_hashes
    $sourceYamlPath = Join-Path $CandidateDir "test.qaas.yaml"
    $sourceSchemaPath = Join-Path $CandidateDir "schemas\ping-response.schema.json"
    $sourcePayloadPath = Join-Path $CandidateDir "request-payloads\get-ping.bin"
    $sourceAppPath = Join-Path $CandidateDir "app\main.go"
    $stagedYamlPath = [string]$record.runner_yaml
    $stagedRunnerRoot = Split-Path -Parent $stagedYamlPath
    $stagedSchemaPath = Join-Path $stagedRunnerRoot "schemas\ping-response.schema.json"
    $stagedPayloadPath = Join-Path $stagedRunnerRoot "request-payloads\get-ping.bin"
    $stagedAppPath = Join-Path ([string]$record.run_dir) "gin-work\main.go"
    foreach ($hashSpec in @(
        @("candidate_yaml_sha256", $sourceYamlPath, $CandidateDir),
        @("staged_yaml_sha256", $stagedYamlPath, $LiveRoot),
        @("candidate_schema_sha256", $sourceSchemaPath, $CandidateDir),
        @("staged_schema_sha256", $stagedSchemaPath, $LiveRoot),
        @("candidate_request_payload_sha256", $sourcePayloadPath, $CandidateDir),
        @("staged_request_payload_sha256", $stagedPayloadPath, $LiveRoot),
        @("candidate_app_sha256", $sourceAppPath, $CandidateDir),
        @("staged_app_sha256", $stagedAppPath, $LiveRoot)
    )) {
        $hashField = [string]$hashSpec[0]
        $hashPath = [string]$hashSpec[1]
        $root = [string]$hashSpec[2]
        if (-not (Test-PathUnderRoot -Path $hashPath -Root $root)) {
            Add-Failure "Gin ${hashField} file must stay under ${root}: $hashPath"
            continue
        }
        $actualHash = Get-Sha256Hex -Path $hashPath
        if ([string](Get-PropertyValue -Object $hashes -Name $hashField) -ne $actualHash) {
            Add-Failure "Gin live source hash ${hashField} does not match actual file: $hashPath"
        }
    }
    foreach ($pair in @(
        @("candidate_schema_sha256", "staged_schema_sha256"),
        @("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        @("candidate_app_sha256", "staged_app_sha256")
    )) {
        if ([string](Get-PropertyValue -Object $hashes -Name $pair[0]) -ne [string](Get-PropertyValue -Object $hashes -Name $pair[1])) {
            Add-Failure "Gin live source hash mismatch $($pair[0])/$($pair[1]): $SummaryPath"
        }
    }
    if ([string](Get-PropertyValue -Object $hashes -Name "candidate_yaml_sha256") -eq [string](Get-PropertyValue -Object $hashes -Name "staged_yaml_sha256")) {
        Add-Failure "Gin staged live YAML must differ from source YAML because live staging normalizes /ping to ping: $SummaryPath"
    }

    $sourceYamlText = Get-Content -LiteralPath $sourceYamlPath -Raw
    if ($sourceYamlText -notmatch [regex]::Escape("Route: /ping")) {
        Add-Failure "Gin source candidate YAML must preserve README route /ping: $sourceYamlPath"
    }
    $runnerYamlText = Get-Content -LiteralPath ([string]$record.runner_yaml) -Raw
    foreach ($requiredText in @("BaseAddress: http://127.0.0.1", "Port: 8080", "Route: ping", "Assertion: HttpStatus", "Assertion: ObjectOutputJsonSchema", "OutputName: GetPing")) {
        if ($runnerYamlText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Gin staged runner YAML missing '$requiredText': $($record.runner_yaml)"
        }
    }
    if ($runnerYamlText -match [regex]::Escape("Route: /ping")) {
        Add-Failure "Gin staged runner YAML must normalize /ping to ping to avoid double slash: $($record.runner_yaml)"
    }

    $response = Read-JsonFile -Path ([string]$record.response)
    if ([string]$response.message -ne "pong" -or @($response.PSObject.Properties).Count -ne 1) {
        Add-Failure "Gin live response does not match README-backed contract: $($record.response)"
    }
    $actualResponseSha = Get-Sha256Hex -Path ([string]$record.response)
    if ([string]$record.response_body_sha256 -ne $actualResponseSha) {
        Add-Failure "Gin live response_body_sha256 must match actual response file: $($record.response)"
    }

    $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
    foreach ($requiredText in @(
        "Validation: selected-top-repo-candidate-live-gin",
        "Repository: gin-gonic/gin",
        "GinCommand: go run -mod=readonly main.go",
        "GoSource: managed_go_toolchain",
        "GoVersion: $GinManagedGoVersion",
        "ManagedGoDownloadUrl: $GinManagedGoDownloadUrl",
        "ManagedGoArchiveSha256: $GinManagedGoArchiveSha256",
        "ModulePinCommand: go get $GinModulePin",
        "ModuleDownloadCommand: go mod download",
        "ModuleListCommand: go list -m -json github.com/gin-gonic/gin",
        "ModuleResolutionPassed: True",
        "Ready: True",
        "ReadyStatus: HTTP 200 from /ping with exact README-backed JSON body",
        "ResponseStatus: 200",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "PortOwnersAfterCleanupCount: 0",
        "ExitCode: 0"
    )) {
        if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Gin live transcript missing required text '$requiredText': $($record.transcript)"
        }
    }

    $templateTranscriptText = Get-Content -LiteralPath ([string]$record.template_validation.transcript) -Raw
    foreach ($requiredText in @(
        "Found IAssertion hook instance HttpStatus",
        "Found IAssertion hook instance ObjectOutputJsonSchema",
        "Route: ping",
        "Runner completed. ExitCode=0"
    )) {
        if ($templateTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Gin template Runner transcript missing '$requiredText': $($record.template_validation.transcript)"
        }
    }

    $liveTranscriptText = Get-Content -LiteralPath ([string]$record.live_validation.transcript) -Raw
    foreach ($requiredText in @(
        "HTTP Get request to http://127.0.0.1:8080/ping completed with status 200.",
        "Running assertion HttpStatus GetPingReturnedOk",
        "Running assertion ObjectOutputJsonSchema GetPingBodyMatchesReadmeSchema",
        "Runner completed. ExitCode=0"
    )) {
        if ($liveTranscriptText -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Gin live Runner transcript missing required text '$requiredText': $($record.live_validation.transcript)"
        }
    }
    if ($liveTranscriptText.Contains("http://127.0.0.1:8080//ping")) {
        Add-Failure "Gin live Runner transcript must not contain double-slash route: $($record.live_validation.transcript)"
    }

    if ($null -eq $manifest) {
        Add-Failure "Passed Gin live validation requires candidate manifest."
    } else {
        $manifestHasQaaSValidation = (
            ($manifest.PSObject.Properties.Name -contains "selected_candidate_qaas_validation") -and
            $manifest.selected_candidate_qaas_validation.status -eq "passed" -and
            $manifest.selected_candidate_qaas_validation.summary -eq $SummaryPath
        )
        if (-not $manifestHasQaaSValidation) {
            Add-Failure "Passed Gin live evidence has not been adopted by current manifest: $manifestPath"
        }
        if ($manifest.promotion_state -ne "blocked" -or $manifest.status -ne "blocked_until_repo_contract_review") {
            Add-Failure "Gin live validation must not promote candidate manifest: $manifestPath"
        }
        foreach ($validationField in @("build_validation", "template_validation", "live_validation")) {
            $manifestValidation = Get-PropertyValue -Object $manifest -Name $validationField
            $summaryValidation = Get-PropertyValue -Object $record -Name $validationField
            if (-not (Test-PassedValidation -Value $manifestValidation)) {
                Add-Failure "Gin candidate manifest missing passed ${validationField}: $manifestPath"
            } elseif (-not (Test-SameValidationRecord -Left $manifestValidation -Right $summaryValidation)) {
                Add-Failure "Gin candidate manifest ${validationField} must equal live summary record: $manifestPath"
            }
        }
        $gateMap = @{}
        foreach ($gate in @($manifest.dependency_gates)) {
            $gateMap[[string]$gate.gate_id] = $gate
        }
        foreach ($gateId in @("qaas-template", "qaas-live-act-assert")) {
            if (-not $gateMap.ContainsKey($gateId)) {
                Add-Failure "Gin candidate manifest missing QaaS gate ${gateId}: $manifestPath"
                continue
            }
            $gate = $gateMap[$gateId]
            if ($gate.status -ne "passed") {
                Add-Failure "Gin candidate QaaS gate ${gateId} must be passed when live evidence passed: $manifestPath"
            }
            if (-not (@($gate.evidence) -contains $SummaryPath)) {
                Add-Failure "Gin candidate QaaS gate ${gateId} must cite live summary: $manifestPath"
            }
        }
        $airgappedGate = $gateMap["airgapped-validation"]
        if ($null -eq $airgappedGate -or $airgappedGate.status -ne "blocked" -or [string]::IsNullOrWhiteSpace([string]$airgappedGate.blocked_reason)) {
            Add-Failure "Gin candidate airgapped gate must remain blocked: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "qaas-template-live-not-run" }).Count -ne 0) {
            Add-Failure "Passed Gin live validation should remove qaas-template-live-not-run blocker: $manifestPath"
        }
        if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq "httpstatus-docs-inconsistency-recorded" }).Count -ne 0) {
            Add-Failure "Passed Gin live validation should move httpstatus-docs-inconsistency-recorded to validation_advisories: $manifestPath"
        }
        $validationAdvisories = @(Get-PropertyValue -Object $manifest -Name "validation_advisories" | Where-Object { $null -ne $_ })
        if (@($validationAdvisories | Where-Object { $_.advisory_id -eq "httpstatus-docs-inconsistency-recorded" -and $_.blocking -eq $false }).Count -eq 0) {
            Add-Failure "Passed Gin live validation must retain non-blocking HttpStatus docs advisory: $manifestPath"
        }
        foreach ($keptBlocker in @("live-airgapped-weak-model-not-passed")) {
            if (@($manifest.source_only_blockers | Where-Object { $_.blocker_id -eq $keptBlocker }).Count -eq 0) {
                Add-Failure "Gin candidate must keep ${keptBlocker} blocker: $manifestPath"
            }
        }
        if ($manifest.airgapped_validation.status -eq "passed") {
            Add-Failure "Gin candidate airgapped validation must not be passed after live QaaS only: $manifestPath"
        }
    }

    if ($null -eq $runtimePlan) {
        Add-Failure "Passed Gin live validation requires candidate runtime plan."
    } else {
        if ($runtimePlan.promotion_state -ne "blocked") {
            Add-Failure "Gin runtime plan must remain blocked after live pass: $runtimePlanPath"
        }
        $runtimeQaaSValidation = Get-PropertyValue -Object $runtimePlan -Name "qaas_validation"
        if ($null -eq $runtimeQaaSValidation -or $runtimeQaaSValidation.status -ne "passed" -or $runtimeQaaSValidation.summary -ne $SummaryPath) {
            Add-Failure "Gin runtime plan missing passed qaas_validation: $runtimePlanPath"
        }
        foreach ($removedBlocker in @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            if (@($runtimePlan.blockers) -contains $removedBlocker) {
                Add-Failure "Gin runtime plan still contains satisfied blocker ${removedBlocker}: $runtimePlanPath"
            }
        }
        foreach ($keptBlocker in @("run_live_airgapped_weak_model_validation", "run_strong_review_against_selected_contract_evidence")) {
            if (-not (@($runtimePlan.blockers) -contains $keptBlocker)) {
                Add-Failure "Gin runtime plan must keep blocker ${keptBlocker}: $runtimePlanPath"
            }
        }
    }
} else {
    Add-Failure "Unexpected Gin live record status '$($record.status)': $SummaryPath"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Selected Gin live check passed with status $($record.status)."
