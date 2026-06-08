param(
    [string]$SummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle.json",
    [string]$CandidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates",
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\200-typicode-json-server",
    [string]$LifecycleRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]
$GinManagedGoVersion = "go version go1.26.4 windows/amd64"
$GinManagedGoDownloadUrl = "https://go.dev/dl/go1.26.4.windows-amd64.zip"
$GinManagedGoArchiveSha256 = "3ca8fb4630b07c419cbdd51f754e31363cfcfb83b3a5354d9e895c90be2cc345"
$GinManagedGoInstallLeaf = "go1.26.4-windows-amd64"

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

function Test-SamePathValue {
    param(
        [string]$Actual,
        [string]$Expected,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Actual)) {
        Add-Failure "$Description is blank."
        return $false
    }

    $actualPath = Get-NormalizedPath -Path $Actual
    $expectedPath = Get-NormalizedPath -Path $Expected
    if (-not [string]::Equals($actualPath, $expectedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-Failure "$Description mismatch: $actualPath vs $expectedPath"
        return $false
    }

    return $true
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
            Where-Object {
                $_.LocalAddress -in @("127.0.0.1", "::1", "0.0.0.0", "::") -and
                [string]$_.State -eq "Listen"
            }).Count
    } catch {
        return 0
    }
}

function Get-Sha256Hex {
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

function Get-BlockerIds {
    param([object]$Manifest)

    $ids = New-Object System.Collections.Generic.HashSet[string]
    foreach ($blocker in @($Manifest.source_only_blockers)) {
        if ($null -ne $blocker.blocker_id) {
            [void]$ids.Add([string]$blocker.blocker_id)
        }
    }
    return $ids
}

function Get-ValidationAdvisory {
    param(
        [object]$Manifest,
        [string]$AdvisoryId
    )

    if (-not ($Manifest.PSObject.Properties.Name -contains "validation_advisories")) {
        return $null
    }
    foreach ($advisory in @($Manifest.validation_advisories)) {
        if ($null -ne $advisory.advisory_id -and [string]$advisory.advisory_id -eq $AdvisoryId) {
            return $advisory
        }
    }
    return $null
}

function Get-GateMap {
    param([object]$Manifest)

    $map = @{}
    foreach ($gate in @($Manifest.dependency_gates)) {
        $map[[string]$gate.gate_id] = $gate
    }
    return $map
}

function Test-PassedValidation {
    param([object]$Value)

    return (
        $null -ne $Value -and
        ($Value.PSObject.Properties.Name -contains "status") -and
        [string]$Value.status -eq "passed" -and
        (
            -not ($Value.PSObject.Properties.Name -contains "exit_code") -or
            [int]$Value.exit_code -eq 0
        )
    )
}

function Get-ValidationValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }

    return $null
}

function Get-LifecycleProfile {
    param([string]$Repository)

    switch ($Repository) {
        "typicode/json-server" {
            return [pscustomobject]@{
                Repository = "typicode/json-server"
                Port = 3000
                LifecycleGates = @("node-json-server-process-lifecycle")
                LifecycleBlocker = "json-server-process-lifecycle-not-proven"
                ResponseKind = "json"
                RequiredTranscriptText = @("Command: npx --yes json-server db.json", "Ready: True", "CleanupPassed: True", "ExitCode: 0")
                RequiredRemainingBlockers = @("live-airgapped-weak-model-not-passed")
                RequiredRuntimeBlockers = @()
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        "pallets/flask" {
            return [pscustomobject]@{
                Repository = "pallets/flask"
                Port = 5000
                LifecycleGates = @("python-flask-process-lifecycle")
                LifecycleBlocker = "flask-process-lifecycle-not-proven"
                ResponseKind = "text"
                RequiredTranscriptText = @("Command: flask run --no-reload --host 127.0.0.1 --port 5000", "Ready: True", "CleanupPassed: True", "ExitCode: 0", "ResponseBodySha256:")
                RequiredRemainingBlockers = @("flask-text-body-hook-not-template-validated", "qaas-template-live-not-run", "live-airgapped-weak-model-not-passed", "httpstatus-docs-inconsistency-recorded")
                RequiredRuntimeBlockers = @(
                    "validate_exact_text_body_custom_assertion_schema_template_and_live",
                    "run_qaaS_template_validation",
                    "run_live_qaaS_act_assert_validation",
                    "run_live_airgapped_weak_model_validation",
                    "run_strong_review_against_selected_contract_evidence"
                )
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        "expressjs/express" {
            return [pscustomobject]@{
                Repository = "expressjs/express"
                Port = 3000
                LifecycleGates = @("node-express-process-lifecycle")
                LifecycleBlocker = "express-process-lifecycle-not-proven"
                ResponseKind = "express-text"
                RequiredTranscriptText = @("InstallCommand: npm install express", "Command: node app.mjs", "NpmInstallExitCode: 0", "PackageSpec: express@", "ExpressPackageAvailable: True", "NodeMajorVersionAtLeast18: True", "Ready: True", "ResponseBodySha256:", "CleanupPassed: True", "ExitCode: 0")
                RequiredRemainingBlockers = @("express-text-body-hook-not-template-validated", "qaas-template-live-not-run", "live-airgapped-weak-model-not-passed", "httpstatus-docs-inconsistency-recorded")
                RequiredRuntimeBlockers = @(
                    "validate_exact_text_body_custom_assertion_schema_template_and_live",
                    "run_qaaS_template_validation",
                    "run_live_qaaS_act_assert_validation",
                    "run_live_airgapped_weak_model_validation",
                    "run_strong_review_against_selected_contract_evidence"
                )
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        "fastapi/fastapi" {
            return [pscustomobject]@{
                Repository = "fastapi/fastapi"
                Port = 8000
                LifecycleGates = @("python-fastapi-process-lifecycle")
                LifecycleBlocker = "fastapi-process-lifecycle-not-proven"
                ResponseKind = "fastapi-json"
                RequiredTranscriptText = @("Command: fastapi dev", "Ready: True", "CleanupPassed: True", "ExitCode: 0")
                RequiredRemainingBlockers = @("qaas-template-live-not-run", "live-airgapped-weak-model-not-passed", "httpstatus-docs-inconsistency-recorded")
                RequiredRuntimeBlockers = @(
                    "run_qaaS_template_validation",
                    "run_live_qaaS_act_assert_validation",
                    "run_live_airgapped_weak_model_validation",
                    "run_strong_review_against_selected_contract_evidence"
                )
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        "gin-gonic/gin" {
            return [pscustomobject]@{
                Repository = "gin-gonic/gin"
                Port = 8080
                LifecycleGates = @("go-version-and-module-resolution", "go-gin-process-lifecycle")
                LifecycleBlocker = "gin-process-lifecycle-not-proven"
                ResponseKind = "gin-json"
                RequiredTranscriptText = @("Command: go run main.go", "ModulePinCommand: go get github.com/gin-gonic/gin@v1.12.0", "ModuleDownloadCommand: go mod download", "ModuleListCommand: go list -m -json github.com/gin-gonic/gin", "ModuleResolutionPassed: True", "RunCommand: go run -mod=readonly main.go", "Ready: True", "CleanupPassed: True", "ExitCode: 0")
                RequiredRemainingBlockers = @("qaas-template-live-not-run", "live-airgapped-weak-model-not-passed", "httpstatus-docs-inconsistency-recorded")
                RequiredRuntimeBlockers = @(
                    "run_qaaS_template_validation",
                    "run_live_qaaS_act_assert_validation",
                    "run_live_airgapped_weak_model_validation",
                    "run_strong_review_against_selected_contract_evidence"
                )
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        "denoland/deno" {
            return [pscustomobject]@{
                Repository = "denoland/deno"
                Port = 8000
                LifecycleGates = @("managed-deno-toolchain", "deno-process-lifecycle")
                LifecycleBlocker = "deno-process-lifecycle-not-proven"
                ResponseKind = "deno-text"
                RequiredTranscriptText = @("DownloadUrl: https://github.com/denoland/deno/releases/download/v2.8.2/deno-x86_64-pc-windows-msvc.zip", "DenoArchiveSha256: 6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9", "DenoVersion: deno 2.8.2", "Command: deno run --allow-net server.ts", "DenoDir:", "Ready: True", "ResponseBodySha256:", "CleanupPassed: True", "ExitCode: 0")
                RequiredRemainingBlockers = @("deno-text-body-hook-not-template-validated", "deno-broad-runtime-coverage-not-selected", "qaas-template-live-not-run", "live-airgapped-weak-model-not-passed", "httpstatus-docs-inconsistency-recorded")
                RequiredRuntimeBlockers = @(
                    "validate_exact_text_body_custom_assertion_schema_template_and_live",
                    "run_qaaS_template_validation",
                    "run_live_qaaS_act_assert_validation",
                    "run_live_airgapped_weak_model_validation",
                    "run_strong_review_against_selected_contract_evidence"
                )
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        "spring-projects/spring-boot" {
            return [pscustomobject]@{
                Repository = "spring-projects/spring-boot"
                Port = 8080
                LifecycleGates = @("java-spring-boot-dependency-resolution", "java-spring-boot-process-lifecycle")
                LifecycleBlocker = "spring-boot-process-lifecycle-not-proven"
                ResponseKind = "spring-boot-text"
                RequiredTranscriptText = @("SpringInitializrUrl: https://start.spring.io/starter.zip", "RequestedBootVersion: 4.0.6", "GeneratedPomBootVersion: 4.0.6", "MavenPackageExitCode: 0", "Command: java -jar", "Ready: True", "ResponseBodySha256:", "CleanupPassed: True", "ExitCode: 0")
                RequiredRemainingBlockers = @("spring-boot-text-body-hook-not-template-validated", "spring-boot-broad-runtime-coverage-not-selected", "qaas-template-live-not-run", "live-airgapped-weak-model-not-passed", "httpstatus-docs-inconsistency-recorded")
                RequiredRuntimeBlockers = @(
                    "run_qaaS_template_validation",
                    "run_live_qaaS_act_assert_validation",
                    "run_live_airgapped_weak_model_validation",
                    "run_strong_review_against_selected_contract_evidence"
                )
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        "unclecode/crawl4ai" {
            return [pscustomobject]@{
                Repository = "unclecode/crawl4ai"
                Port = 11235
                LifecycleGates = @("docker-crawl4ai-container-lifecycle")
                LifecycleBlocker = "crawl4ai-docker-lifecycle-not-proven"
                ResponseKind = "crawl4ai-health-status"
                RequiredTranscriptText = @("DockerPullCommand: docker pull unclecode/crawl4ai:latest", "DockerRunCommand: docker run -d -p 127.0.0.1:11235:11235 --name zappa-crawl4ai-health-", "--shm-size=1g unclecode/crawl4ai:latest", "ReadinessUrl: http://127.0.0.1:11235/health", "Ready: True", "CleanupPassed: True", "ContainerExistsAfterCleanup: False", "PortOwnersAfterCleanupCount: 0", "ExitCode: 0")
                RequiredRemainingBlockers = @("crawl4ai-status-below-400-hook-not-template-validated", "crawl4ai-health-body-contract-not-selected", "crawl4ai-crawl-endpoint-not-promoted", "qaas-template-live-not-run", "live-airgapped-weak-model-not-passed")
                RequiredRuntimeBlockers = @(
                    "build_and_template_validate_http_status_below_400_assertion",
                    "run_qaaS_template_validation",
                    "run_live_qaaS_act_assert_validation",
                    "run_live_airgapped_weak_model_validation",
                    "run_strong_review_against_selected_contract_evidence"
                )
                QaaSTemplateBlocker = "qaas-template-live-not-run"
            }
        }
        default {
            Add-Failure "Unsupported selected lifecycle repository '$Repository'."
            return $null
        }
    }
}

if (-not (Test-PathUnderRoot -Path $CandidateDir -Root $CandidateRoot)) {
    Add-Failure "CandidateDir must stay under $CandidateRoot; got $CandidateDir"
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
    if ($failures.Count -gt 0) {
        $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
        exit 1
    }
    Write-Output "Selected top-repo candidate lifecycle check passed: no lifecycle evidence yet; candidate remains blocked."
    exit 0
}

Test-NoUtf8Bom -Path $SummaryPath -Description "Lifecycle summary"
Test-NoUtf8Bom -Path $manifestPath -Description "Candidate manifest"
Test-NoUtf8Bom -Path $runtimePlanPath -Description "Candidate runtime plan"

$record = Read-JsonFile -Path $SummaryPath
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Read-JsonFile -Path $manifestPath } else { $null }
$runtimePlan = if (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf) { Read-JsonFile -Path $runtimePlanPath } else { $null }

$profile = Get-LifecycleProfile -Repository ([string]$record.repository)
if ($null -ne $manifest -and $record.repository -ne $manifest.source_repository) {
    Add-Failure "Lifecycle record repository mismatch for candidate manifest: $($record.repository) vs $($manifest.source_repository)"
}
if ($null -ne $runtimePlan -and $record.repository -ne $runtimePlan.repository) {
    Add-Failure "Lifecycle record repository mismatch for runtime plan: $($record.repository) vs $($runtimePlan.repository)"
}
if ($record.promotion_state -ne "blocked" -or $record.completion_ready -ne $false) {
    Add-Failure "Lifecycle record must remain blocked and not completion-ready: $SummaryPath"
}

if ($record.status -eq "blocked") {
    if ([string]::IsNullOrWhiteSpace([string]$record.reason)) {
        Add-Failure "Blocked lifecycle record must include a reason: $SummaryPath"
    }
    if ($record.weak_validation_passed -ne $false) {
        Add-Failure "Blocked lifecycle validation must not claim weak model validation passed: $SummaryPath"
    }
} elseif ($record.status -eq "passed") {
    if ($null -eq $profile) {
        # Already recorded as unsupported.
    } elseif ($null -eq $manifest -or $null -eq $runtimePlan) {
        Add-Failure "Passed lifecycle requires candidate manifest and runtime plan."
    } else {
        $manifestHasLifecycleValidation = (
            ($manifest.PSObject.Properties.Name -contains "lifecycle_validation") -and
            $manifest.lifecycle_validation.status -eq "passed"
        )
        if (-not $manifestHasLifecycleValidation) {
            Test-SamePathValue -Actual ([string]$record.manifest) -Expected $manifestPath -Description "Lifecycle record manifest path" | Out-Null
            Test-SamePathValue -Actual ([string]$record.runtime_plan) -Expected $runtimePlanPath -Description "Lifecycle record runtime plan path" | Out-Null
            Add-Failure "Passed lifecycle summary has not been adopted by the current candidate manifest: $manifestPath"
            $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
            exit 1
        }

        Test-SamePathValue -Actual ([string]$record.manifest) -Expected $manifestPath -Description "Lifecycle record manifest path" | Out-Null
        Test-SamePathValue -Actual ([string]$record.runtime_plan) -Expected $runtimePlanPath -Description "Lifecycle record runtime plan path" | Out-Null

        foreach ($field in @("transcript", "stdout", "stderr", "response")) {
            $value = [string]$record.$field
            if (Test-ExistingFileUnderRoot -Path $value -Root $LifecycleRoot -Description "Lifecycle ${field}") {
                Test-NoUtf8Bom -Path $value -Description "Lifecycle ${field}"
            }
        }
        if ([int]$record.exit_code -ne 0) {
            Add-Failure "Passed lifecycle record must have exit_code 0: $SummaryPath"
        }
        if ($record.response_contract_passed -ne $true) {
            Add-Failure "Passed lifecycle record must prove response contract: $SummaryPath"
        }
        if ($record.cleanup_passed -ne $true) {
            Add-Failure "Passed lifecycle record must prove cleanup: $SummaryPath"
        }
        if ([int]$record.port_owners_after_cleanup_count -ne 0) {
            Add-Failure "Passed lifecycle record must have zero port owners after cleanup: $SummaryPath"
        }
        if (@($record.remaining_tracked_process_ids).Count -ne 0) {
            Add-Failure "Passed lifecycle record must leave no tracked process ids: $SummaryPath"
        }
        if ((Get-PortOwnerCount -Port ([int]$profile.Port)) -ne 0) {
            Add-Failure "Port $($profile.Port) is currently still owned after lifecycle validation."
        }
        if ($record.weak_validation_passed -ne $false) {
            Add-Failure "Lifecycle validation must not claim weak model validation passed: $SummaryPath"
        }

        if (Test-Path -LiteralPath ([string]$record.response) -PathType Leaf) {
            if ($profile.ResponseKind -eq "json") {
                try {
                    $response = Read-JsonFile -Path ([string]$record.response)
                    if ([string]$response.id -ne "1" -or [string]$response.title -ne "a title" -or [int]$response.views -ne 100) {
                        Add-Failure "Lifecycle response does not match README-backed contract: $($record.response)"
                    }
                } catch {
                    Add-Failure "Lifecycle JSON response could not be parsed: $($record.response): $($_.Exception.Message)"
                }
            } elseif ($profile.ResponseKind -eq "text") {
                $responseText = Get-Content -LiteralPath ([string]$record.response) -Raw
                if ($responseText -ne "Hello, World!") {
                    Add-Failure "Flask lifecycle response body must match README-backed exact text: $($record.response)"
                }
                if ([int]$record.response_status -ne 200) {
                    Add-Failure "Flask lifecycle response status must be 200: $SummaryPath"
                }
                $actualResponseSha256 = Get-Sha256Hex -Path ([string]$record.response)
                if ([string]$record.response_body_sha256 -ne $actualResponseSha256) {
                    Add-Failure "Flask lifecycle response_body_sha256 must match actual response file: $($record.response)"
                }
            } elseif ($profile.ResponseKind -eq "fastapi-json") {
                try {
                    $response = Read-JsonFile -Path ([string]$record.response)
                    $propertyNames = @($response.PSObject.Properties.Name)
                    if ($propertyNames.Count -ne 2 -or -not ($propertyNames -contains "item_id") -or -not ($propertyNames -contains "q") -or [int]$response.item_id -ne 5 -or [string]$response.q -ne "somequery") {
                        Add-Failure "FastAPI lifecycle response must exactly match README-backed JSON body: $($record.response)"
                    }
                    if ([int]$record.response_status -ne 200) {
                        Add-Failure "FastAPI lifecycle response status must be 200: $SummaryPath"
                    }
                } catch {
                    Add-Failure "FastAPI lifecycle JSON response could not be parsed: $($record.response): $($_.Exception.Message)"
                }
            } elseif ($profile.ResponseKind -eq "gin-json") {
                try {
                    $response = Read-JsonFile -Path ([string]$record.response)
                    $propertyNames = @($response.PSObject.Properties.Name)
                    if ($propertyNames.Count -ne 1 -or -not ($propertyNames -contains "message") -or [string]$response.message -ne "pong") {
                        Add-Failure "Gin lifecycle response must exactly match README-backed JSON body: $($record.response)"
                    }
                    if ([int]$record.response_status -ne 200) {
                        Add-Failure "Gin lifecycle response status must be 200: $SummaryPath"
                    }
                } catch {
                    Add-Failure "Gin lifecycle JSON response could not be parsed: $($record.response): $($_.Exception.Message)"
                }
            } elseif ($profile.ResponseKind -eq "express-text") {
                $responseText = Get-Content -LiteralPath ([string]$record.response) -Raw
                if ($responseText -ne "Hello World") {
                    Add-Failure "Express lifecycle response body must match README-backed exact text: $($record.response)"
                }
                if ([int]$record.response_status -ne 200) {
                    Add-Failure "Express lifecycle response status must be 200: $SummaryPath"
                }
                $actualResponseSha256 = Get-Sha256Hex -Path ([string]$record.response)
                if ([string]$record.response_body_sha256 -ne $actualResponseSha256) {
                    Add-Failure "Express lifecycle response_body_sha256 must match actual response file: $($record.response)"
                }
            } elseif ($profile.ResponseKind -eq "deno-text") {
                $responseText = Get-Content -LiteralPath ([string]$record.response) -Raw
                if ($responseText -ne "Hello, world!") {
                    Add-Failure "Deno lifecycle response body must match README-backed exact text: $($record.response)"
                }
                if ([int]$record.response_status -ne 200) {
                    Add-Failure "Deno lifecycle response status must be 200: $SummaryPath"
                }
                $actualResponseSha256 = Get-Sha256Hex -Path ([string]$record.response)
                if ([string]$record.response_body_sha256 -ne $actualResponseSha256) {
                    Add-Failure "Deno lifecycle response_body_sha256 must match actual response file: $($record.response)"
                }
            } elseif ($profile.ResponseKind -eq "spring-boot-text") {
                $responseText = Get-Content -LiteralPath ([string]$record.response) -Raw
                if ($responseText -ne "Hello World!") {
                    Add-Failure "Spring Boot lifecycle response body must match README-backed exact text: $($record.response)"
                }
                if ([int]$record.response_status -ne 200) {
                    Add-Failure "Spring Boot lifecycle response status must be 200: $SummaryPath"
                }
                $actualResponseSha256 = Get-Sha256Hex -Path ([string]$record.response)
                if ([string]$record.response_body_sha256 -ne $actualResponseSha256) {
                    Add-Failure "Spring Boot lifecycle response_body_sha256 must match actual response file: $($record.response)"
                }
            } elseif ($profile.ResponseKind -eq "crawl4ai-health-status") {
                if ([int]$record.response_status -ge 400) {
                    Add-Failure "Crawl4AI lifecycle response status must be below 400: $SummaryPath"
                }
                $actualResponseSha256 = Get-Sha256Hex -Path ([string]$record.response)
                if ([string]$record.response_body_sha256 -ne $actualResponseSha256) {
                    Add-Failure "Crawl4AI lifecycle response_body_sha256 must match actual response file: $($record.response)"
                }
            }
        }

        if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
            $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
            foreach ($requiredText in @($profile.RequiredTranscriptText)) {
                if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
                    Add-Failure "Lifecycle transcript missing required text '$requiredText': $($record.transcript)"
                }
            }
        }

        if ($profile.Repository -eq "pallets/flask") {
            if ([string]$record.install_command -ne "python -m pip install Flask") {
                Add-Failure "Flask lifecycle install_command must record managed dependency setup: $SummaryPath"
            }
            if ([string]::IsNullOrWhiteSpace([string]$record.flask_version)) {
                Add-Failure "Flask lifecycle must record flask_version: $SummaryPath"
            }
            foreach ($fileField in @("venv_create_stdout", "venv_create_stderr", "pip_install_stdout", "pip_install_stderr", "flask_cli_path", "python_path")) {
                $value = [string]$record.$fileField
                Test-ExistingFileUnderRoot -Path $value -Root $LifecycleRoot -Description "Flask lifecycle ${fileField}" | Out-Null
            }
            $managedVenvPath = [string]$record.managed_venv_path
            if ([string]::IsNullOrWhiteSpace($managedVenvPath) -or -not (Test-Path -LiteralPath $managedVenvPath -PathType Container)) {
                Add-Failure "Flask lifecycle managed_venv_path must exist: $managedVenvPath"
            } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $managedVenvPath).Path -Root $LifecycleRoot)) {
                Add-Failure "Flask lifecycle managed_venv_path must stay under $LifecycleRoot; got $managedVenvPath"
            }
            $selectedPyprojectEvidence = [string]$record.selected_pyproject_evidence
            if ([string]::IsNullOrWhiteSpace($selectedPyprojectEvidence) -or -not (Test-Path -LiteralPath $selectedPyprojectEvidence -PathType Leaf)) {
                Add-Failure "Flask lifecycle must cite selected_pyproject_evidence: $SummaryPath"
            }
            if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
                $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
                foreach ($requiredText in @("ManagedVenvPath:", "InstallCommand: python -m pip install Flask", "PipInstallExitCode: 0", "FlaskModuleAvailable: True", "FlaskCliPath:")) {
                    if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
                        Add-Failure "Flask lifecycle transcript missing managed-venv text '$requiredText': $($record.transcript)"
                    }
                }
            }
        }
        if ($profile.Repository -eq "expressjs/express") {
            if ([string]$record.install_command -ne "npm install express") {
                Add-Failure "Express lifecycle install_command must record managed dependency setup: $SummaryPath"
            }
            if ([string]$record.command -ne "node app.mjs") {
                Add-Failure "Express lifecycle command must be node app.mjs: $SummaryPath"
            }
            if ([int]$record.npm_install_exit_code -ne 0) {
                Add-Failure "Express lifecycle npm_install_exit_code must be 0: $SummaryPath"
            }
            if ($record.express_package_available -ne $true) {
                Add-Failure "Express lifecycle must prove express_package_available true: $SummaryPath"
            }
            if ($record.node_major_version_at_least_18 -ne $true) {
                Add-Failure "Express lifecycle must prove Node major version at least 18: $SummaryPath"
            }
            if ([string]::IsNullOrWhiteSpace([string]$record.installed_express_version)) {
                Add-Failure "Express lifecycle must record installed_express_version: $SummaryPath"
            }
            $workingDirectory = [string]$record.working_directory
            if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
                Add-Failure "Express lifecycle working_directory must exist: $workingDirectory"
            } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $workingDirectory).Path -Root $LifecycleRoot)) {
                Add-Failure "Express lifecycle working_directory must stay under $LifecycleRoot; got $workingDirectory"
            }
            foreach ($fileField in @("staged_package_json", "package_lock", "installed_express_package", "npm_install_stdout", "npm_install_stderr")) {
                $value = [string]$record.$fileField
                Test-ExistingFileUnderRoot -Path $value -Root $LifecycleRoot -Description "Express lifecycle ${fileField}" | Out-Null
            }
            $selectedPackageEvidence = [string]$record.selected_package_evidence
            if ([string]::IsNullOrWhiteSpace($selectedPackageEvidence) -or -not (Test-Path -LiteralPath $selectedPackageEvidence -PathType Leaf)) {
                Add-Failure "Express lifecycle must cite selected_package_evidence: $SummaryPath"
            } else {
                try {
                    $selectedPackageRecord = Read-JsonFile -Path $selectedPackageEvidence
                    $selectedExpressVersion = [string]$selectedPackageRecord.version
                    $expectedPackageSpec = "express@$selectedExpressVersion"
                    if ([string]$record.package_spec -ne $expectedPackageSpec) {
                        Add-Failure "Express lifecycle package_spec must be ${expectedPackageSpec}: $SummaryPath"
                    }
                    if ([string]$record.install_execution_command -ne "npm install $expectedPackageSpec") {
                        Add-Failure "Express lifecycle install_execution_command must pin selected package version: $SummaryPath"
                    }
                    if ([string]$record.installed_express_version -ne $selectedExpressVersion) {
                        Add-Failure "Express lifecycle installed_express_version must match selected package version ${selectedExpressVersion}: $SummaryPath"
                    }
                } catch {
                    Add-Failure "Express selected package evidence could not be parsed: ${selectedPackageEvidence}: $($_.Exception.Message)"
                }
            }
            $selectedAcceptanceEvidence = [string]$record.selected_acceptance_evidence
            if ([string]::IsNullOrWhiteSpace($selectedAcceptanceEvidence) -or -not (Test-Path -LiteralPath $selectedAcceptanceEvidence -PathType Leaf)) {
                Add-Failure "Express lifecycle must cite selected_acceptance_evidence: $SummaryPath"
            }
            if (Test-Path -LiteralPath ([string]$record.installed_express_package) -PathType Leaf) {
                try {
                    $installedExpressPackage = Read-JsonFile -Path ([string]$record.installed_express_package)
                    if ([string]$installedExpressPackage.name -ne "express" -or [string]$installedExpressPackage.version -ne [string]$record.installed_express_version) {
                        Add-Failure "Express installed package JSON must prove express@$($record.installed_express_version): $($record.installed_express_package)"
                    }
                } catch {
                    Add-Failure "Express installed package JSON could not be parsed: $($record.installed_express_package): $($_.Exception.Message)"
                }
            }
            foreach ($hashSpec in @(
                    [pscustomobject]@{ Field = "staged_app_sha256"; Path = [string](Join-Path ([string]$record.working_directory) "app.mjs") },
                    [pscustomobject]@{ Field = "staged_package_json_sha256"; Path = [string]$record.staged_package_json },
                    [pscustomobject]@{ Field = "package_lock_sha256"; Path = [string]$record.package_lock },
                    [pscustomobject]@{ Field = "installed_express_package_sha256"; Path = [string]$record.installed_express_package },
                    [pscustomobject]@{ Field = "response_body_sha256"; Path = [string]$record.response }
                )) {
                if ([string]::IsNullOrWhiteSpace($hashSpec.Path) -or -not (Test-Path -LiteralPath $hashSpec.Path -PathType Leaf)) {
                    Add-Failure "Express lifecycle $($hashSpec.Field) source file missing: $($hashSpec.Path)"
                    continue
                }
                $actualHash = Get-Sha256Hex -Path $hashSpec.Path
                $actualValue = [string]$record.PSObject.Properties[$hashSpec.Field].Value
                if ($actualValue -ne $actualHash) {
                    Add-Failure "Express lifecycle $($hashSpec.Field) must match actual file: $($hashSpec.Path)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
                $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
                foreach ($requiredText in @("NpmPath:", "NodePath:", "InstallExecutionCommand: npm install express@", "InstalledExpressVersion:", "InstalledExpressPackage:", "PackageLockSha256:", "SelectedExampleEvidence:", "SelectedAcceptanceEvidence:", "SelectedPackageEvidence:")) {
                    if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
                        Add-Failure "Express lifecycle transcript missing managed-node text '$requiredText': $($record.transcript)"
                    }
                }
            }
        }
        if ($profile.Repository -eq "gin-gonic/gin") {
            if ([string]$record.module_pin -ne "github.com/gin-gonic/gin@v1.12.0") {
                Add-Failure "Gin lifecycle module_pin must be github.com/gin-gonic/gin@v1.12.0: $SummaryPath"
            }
            foreach ($fileField in @("go_env_json", "go_mod_path", "go_sum_path", "go_list_module_json")) {
                $value = [string]$record.$fileField
                Test-ExistingFileUnderRoot -Path $value -Root $LifecycleRoot -Description "Gin lifecycle ${fileField}" | Out-Null
            }
            foreach ($dirField in @("managed_gopath", "managed_gomodcache", "managed_gocache")) {
                $value = [string]$record.$dirField
                if ([string]::IsNullOrWhiteSpace($value) -or -not (Test-Path -LiteralPath $value -PathType Container)) {
                    Add-Failure "Gin lifecycle ${dirField} must exist: $value"
                } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $value).Path -Root $LifecycleRoot)) {
                    Add-Failure "Gin lifecycle ${dirField} must stay under lifecycle run root: $value"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.go_env_json) -PathType Leaf) {
                try {
                    $goEnvRecord = Read-JsonFile -Path ([string]$record.go_env_json)
                    Test-SamePathValue -Actual ([string]$goEnvRecord.GOROOT) -Expected ([string]$record.go_root) -Description "Gin lifecycle go-env GOROOT" | Out-Null
                    Test-SamePathValue -Actual ([string]$goEnvRecord.GOPATH) -Expected ([string]$record.managed_gopath) -Description "Gin lifecycle go-env GOPATH" | Out-Null
                    Test-SamePathValue -Actual ([string]$goEnvRecord.GOMODCACHE) -Expected ([string]$record.managed_gomodcache) -Description "Gin lifecycle go-env GOMODCACHE" | Out-Null
                    Test-SamePathValue -Actual ([string]$goEnvRecord.GOCACHE) -Expected ([string]$record.managed_gocache) -Description "Gin lifecycle go-env GOCACHE" | Out-Null
                } catch {
                    Add-Failure "Gin lifecycle go_env_json could not be parsed: $($record.go_env_json): $($_.Exception.Message)"
                }
            }
            foreach ($hashSpec in @(
                    [pscustomobject]@{ Field = "go_mod_sha256"; Path = [string]$record.go_mod_path },
                    [pscustomobject]@{ Field = "go_sum_sha256"; Path = [string]$record.go_sum_path },
                    [pscustomobject]@{ Field = "response_body_sha256"; Path = [string]$record.response }
                )) {
                $actualHash = Get-Sha256Hex -Path $hashSpec.Path
                $actualValue = [string]$record.PSObject.Properties[$hashSpec.Field].Value
                if ($actualValue -ne $actualHash) {
                    Add-Failure "Gin lifecycle $($hashSpec.Field) must match actual file: $($hashSpec.Path)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.go_list_module_json) -PathType Leaf) {
                try {
                    $moduleRecord = Read-JsonFile -Path ([string]$record.go_list_module_json)
                    if ([string]$moduleRecord.Path -ne "github.com/gin-gonic/gin" -or [string]$moduleRecord.Version -ne "v1.12.0") {
                        Add-Failure "Gin lifecycle go_list_module_json must prove github.com/gin-gonic/gin v1.12.0: $($record.go_list_module_json)"
                    }
                } catch {
                    Add-Failure "Gin lifecycle go_list_module_json could not be parsed: $($record.go_list_module_json): $($_.Exception.Message)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
                $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
                foreach ($forbiddenText in @("go get -u", "@latest")) {
                    if ($transcriptText -match [regex]::Escape($forbiddenText)) {
                        Add-Failure "Gin lifecycle transcript must not use mutable module command '$forbiddenText': $($record.transcript)"
                    }
                }
            }
            if ([string]$record.go_source -ne "managed_go_toolchain") {
                Add-Failure "Gin lifecycle must use managed_go_toolchain; got '$([string]$record.go_source)': $SummaryPath"
            } else {
                if ([string]$record.go_version -ne $GinManagedGoVersion) {
                    Add-Failure "Gin lifecycle go_version must be ${GinManagedGoVersion}: $SummaryPath"
                }
                foreach ($fileField in @("go_path", "managed_toolchain_archive")) {
                    $value = [string]$record.$fileField
                    Test-ExistingFileUnderRoot -Path $value -Root "D:\QaaS\_tmp\zappa-dont-cry" -Description "Gin lifecycle ${fileField}" | Out-Null
                }
                $managedToolchainPath = [string]$record.managed_toolchain_path
                if ([string]::IsNullOrWhiteSpace($managedToolchainPath) -or -not (Test-Path -LiteralPath $managedToolchainPath -PathType Container)) {
                    Add-Failure "Gin lifecycle managed_toolchain_path must exist: $managedToolchainPath"
                } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $managedToolchainPath).Path -Root "D:\QaaS\_tmp\zappa-dont-cry") -or $managedToolchainPath -notmatch [regex]::Escape("\toolchains\go\") -or (Split-Path -Leaf $managedToolchainPath) -ne $GinManagedGoInstallLeaf) {
                    Add-Failure "Gin lifecycle managed_toolchain_path must stay under managed Go toolchains: $managedToolchainPath"
                }
                if ((Test-Path -LiteralPath ([string]$record.go_path) -PathType Leaf) -and (Test-Path -LiteralPath $managedToolchainPath -PathType Container)) {
                    if (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath ([string]$record.go_path)).Path -Root $managedToolchainPath)) {
                        Add-Failure "Gin lifecycle go_path must stay under managed_toolchain_path: $($record.go_path)"
                    }
                }
                $downloadUrl = [string]$record.managed_toolchain_download_url
                if ($downloadUrl -ne $GinManagedGoDownloadUrl) {
                    Add-Failure "Gin lifecycle managed_toolchain_download_url must be ${GinManagedGoDownloadUrl}: $SummaryPath"
                }
                if ((Split-Path -Leaf ([string]$record.managed_toolchain_archive)) -ne "go1.26.4.windows-amd64.zip") {
                    Add-Failure "Gin lifecycle managed_toolchain_archive must use go1.26.4.windows-amd64.zip: $($record.managed_toolchain_archive)"
                }
                if ([string]::IsNullOrWhiteSpace([string]$record.managed_toolchain_archive_sha256)) {
                    Add-Failure "Gin lifecycle managed_toolchain_archive_sha256 must be recorded: $SummaryPath"
                } else {
                    if ([string]$record.managed_toolchain_archive_sha256 -ne $GinManagedGoArchiveSha256) {
                        Add-Failure "Gin lifecycle managed_toolchain_archive_sha256 must be ${GinManagedGoArchiveSha256}: $($record.managed_toolchain_archive)"
                    }
                    $actualArchiveSha256 = Get-Sha256Hex -Path ([string]$record.managed_toolchain_archive)
                    if ([string]$record.managed_toolchain_archive_sha256 -ne $actualArchiveSha256) {
                        Add-Failure "Gin lifecycle managed_toolchain_archive_sha256 must match actual archive: $($record.managed_toolchain_archive)"
                    }
                }
                if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
                    $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
                    foreach ($requiredText in @("GoSource: managed_go_toolchain", "GoVersion: $GinManagedGoVersion", "ManagedGoDownloadUrl: $GinManagedGoDownloadUrl", "ManagedGoArchiveSha256: $GinManagedGoArchiveSha256")) {
                        if ($transcriptText -notmatch [regex]::Escape($requiredText)) {
                            Add-Failure "Gin lifecycle transcript missing managed Go text '$requiredText': $($record.transcript)"
                        }
                    }
                }
            }
        }
        if ($profile.Repository -eq "denoland/deno") {
            if ([string]$record.command -ne "deno run --allow-net server.ts") {
                Add-Failure "Deno lifecycle command must be deno run --allow-net server.ts: $SummaryPath"
            }
            if ([string]$record.managed_toolchain_release_tag -ne "v2.8.2") {
                Add-Failure "Deno lifecycle managed_toolchain_release_tag must be v2.8.2: $SummaryPath"
            }
            if ([string]$record.managed_toolchain_download_url -ne "https://github.com/denoland/deno/releases/download/v2.8.2/deno-x86_64-pc-windows-msvc.zip") {
                Add-Failure "Deno lifecycle managed_toolchain_download_url mismatch: $SummaryPath"
            }
            if ([string]$record.managed_toolchain_archive_sha256 -ne "6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9") {
                Add-Failure "Deno lifecycle managed_toolchain_archive_sha256 mismatch: $SummaryPath"
            }
            if (-not ([string]$record.deno_version).StartsWith("deno 2.8.2", [System.StringComparison]::Ordinal)) {
                Add-Failure "Deno lifecycle deno_version must start with deno 2.8.2: $SummaryPath"
            }
            foreach ($fileField in @("managed_toolchain_archive", "deno_path", "deno_version_stdout", "deno_version_stderr")) {
                $value = [string]$record.$fileField
                Test-ExistingFileUnderRoot -Path $value -Root "D:\QaaS\_tmp\zappa-dont-cry" -Description "Deno lifecycle ${fileField}" | Out-Null
            }
            $managedToolchainPath = [string]$record.managed_toolchain_path
            if ([string]::IsNullOrWhiteSpace($managedToolchainPath) -or -not (Test-Path -LiteralPath $managedToolchainPath -PathType Container)) {
                Add-Failure "Deno lifecycle managed_toolchain_path must exist: $managedToolchainPath"
            } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $managedToolchainPath).Path -Root "D:\QaaS\_tmp\zappa-dont-cry\toolchains\deno")) {
                Add-Failure "Deno lifecycle managed_toolchain_path must stay under managed Deno toolchains: $managedToolchainPath"
            }
            $denoDir = [string]$record.deno_dir
            if ([string]::IsNullOrWhiteSpace($denoDir) -or -not (Test-Path -LiteralPath $denoDir -PathType Container)) {
                Add-Failure "Deno lifecycle deno_dir must exist: $denoDir"
            } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $denoDir).Path -Root $LifecycleRoot)) {
                Add-Failure "Deno lifecycle deno_dir must stay under lifecycle run root: $denoDir"
            }
            $workingDirectory = [string]$record.working_directory
            if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
                Add-Failure "Deno lifecycle working_directory must exist: $workingDirectory"
            } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $workingDirectory).Path -Root $LifecycleRoot)) {
                Add-Failure "Deno lifecycle working_directory must stay under lifecycle run root: $workingDirectory"
            }
            foreach ($hashSpec in @(
                    [pscustomobject]@{ Field = "managed_toolchain_archive_sha256"; Path = [string]$record.managed_toolchain_archive },
                    [pscustomobject]@{ Field = "staged_server_sha256"; Path = [string](Join-Path ([string]$record.working_directory) "server.ts") },
                    [pscustomobject]@{ Field = "response_body_sha256"; Path = [string]$record.response }
                )) {
                if ([string]::IsNullOrWhiteSpace($hashSpec.Path) -or -not (Test-Path -LiteralPath $hashSpec.Path -PathType Leaf)) {
                    Add-Failure "Deno lifecycle $($hashSpec.Field) source file missing: $($hashSpec.Path)"
                    continue
                }
                $actualHash = Get-Sha256Hex -Path $hashSpec.Path
                $actualValue = [string]$record.PSObject.Properties[$hashSpec.Field].Value
                if ($actualValue -ne $actualHash) {
                    Add-Failure "Deno lifecycle $($hashSpec.Field) must match actual file: $($hashSpec.Path)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.deno_version_stdout) -PathType Leaf) {
                $versionText = Get-Content -LiteralPath ([string]$record.deno_version_stdout) -Raw
                if (-not $versionText.StartsWith("deno 2.8.2", [System.StringComparison]::Ordinal)) {
                    Add-Failure "Deno lifecycle version transcript must prove deno 2.8.2: $($record.deno_version_stdout)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
                $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
                foreach ($forbiddenText in @("ambient deno", "Get-Command deno", "npm", "node app", "flask run", "Route: /crawl")) {
                    if ($transcriptText -match [regex]::Escape($forbiddenText)) {
                        Add-Failure "Deno lifecycle transcript must not contain spoofing or wrong-runtime text '$forbiddenText': $($record.transcript)"
                    }
                }
            }
            $runtimeManaged = Get-ValidationValue -Object $runtimePlan -Name "managed_toolchain"
            if ($null -eq $runtimeManaged -or $runtimeManaged.status -ne "passed") {
                Add-Failure "Deno runtime plan managed_toolchain must be passed after lifecycle validation: $runtimePlanPath"
            }
        }
        if ($profile.Repository -eq "spring-projects/spring-boot") {
            if ([string]$record.command -ne "java -jar") {
                Add-Failure "Spring Boot lifecycle command must be java -jar: $SummaryPath"
            }
            if ([string]$record.spring_initializr_url -ne "https://start.spring.io/starter.zip") {
                Add-Failure "Spring Boot lifecycle spring_initializr_url mismatch: $SummaryPath"
            }
            if ([string]$record.requested_boot_version -ne "4.0.6" -or [string]$record.generated_pom_boot_version -ne "4.0.6") {
                Add-Failure "Spring Boot lifecycle must prove Spring Boot 4.0.6 from generated POM: $SummaryPath"
            }
            if ([string]$record.generated_pom_boot_version -like "*.RELEASE") {
                Add-Failure "Spring Boot lifecycle must normalize Initializr version without RELEASE suffix: $SummaryPath"
            }
            if ([int]$record.java_major_version -lt 25) {
                Add-Failure "Spring Boot lifecycle must use Java 25 or newer: $SummaryPath"
            }
            if ([int]$record.maven_package_exit_code -ne 0) {
                Add-Failure "Spring Boot lifecycle Maven package exit code must be 0: $SummaryPath"
            }
            foreach ($fileField in @("initializr_zip", "pom_path", "built_jar", "maven_stdout", "maven_stderr", "java_version_stdout", "java_version_stderr")) {
                $value = [string]$record.$fileField
                Test-ExistingFileUnderRoot -Path $value -Root $LifecycleRoot -Description "Spring Boot lifecycle ${fileField}" | Out-Null
            }
            foreach ($evidenceField in @("selected_readme_evidence", "selected_webserver_evidence")) {
                $value = [string]$record.$evidenceField
                if ([string]::IsNullOrWhiteSpace($value) -or -not (Test-Path -LiteralPath $value -PathType Leaf)) {
                    Add-Failure "Spring Boot lifecycle must cite ${evidenceField}: $SummaryPath"
                }
            }
            if ([string]::IsNullOrWhiteSpace([string]$record.java_path) -or -not (Test-Path -LiteralPath ([string]$record.java_path) -PathType Leaf)) {
                Add-Failure "Spring Boot lifecycle java_path must exist: $($record.java_path)"
            }
            $workingDirectory = [string]$record.working_directory
            if ([string]::IsNullOrWhiteSpace($workingDirectory) -or -not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
                Add-Failure "Spring Boot lifecycle working_directory must exist: $workingDirectory"
            } elseif (-not (Test-PathUnderRoot -Path (Resolve-Path -LiteralPath $workingDirectory).Path -Root $LifecycleRoot)) {
                Add-Failure "Spring Boot lifecycle working_directory must stay under lifecycle run root: $workingDirectory"
            }
            foreach ($hashSpec in @(
                    [pscustomobject]@{ Field = "initializr_zip_sha256"; Path = [string]$record.initializr_zip },
                    [pscustomobject]@{ Field = "pom_sha256"; Path = [string]$record.pom_path },
                    [pscustomobject]@{ Field = "built_jar_sha256"; Path = [string]$record.built_jar },
                    [pscustomobject]@{ Field = "staged_app_sha256"; Path = [string](Join-Path ([string]$record.working_directory) "src\main\java\com\example\Example.java") },
                    [pscustomobject]@{ Field = "response_body_sha256"; Path = [string]$record.response }
                )) {
                if ([string]::IsNullOrWhiteSpace($hashSpec.Path) -or -not (Test-Path -LiteralPath $hashSpec.Path -PathType Leaf)) {
                    Add-Failure "Spring Boot lifecycle $($hashSpec.Field) source file missing: $($hashSpec.Path)"
                    continue
                }
                $actualHash = Get-Sha256Hex -Path $hashSpec.Path
                $actualValue = [string]$record.PSObject.Properties[$hashSpec.Field].Value
                if ($actualValue -ne $actualHash) {
                    Add-Failure "Spring Boot lifecycle $($hashSpec.Field) must match actual file: $($hashSpec.Path)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.pom_path) -PathType Leaf) {
                $pomText = Get-Content -LiteralPath ([string]$record.pom_path) -Raw
                if ($pomText -notmatch "<version>4\.0\.6</version>") {
                    Add-Failure "Spring Boot lifecycle POM must contain parent version 4.0.6: $($record.pom_path)"
                }
                if ($pomText -match "4\.0\.6\.RELEASE") {
                    Add-Failure "Spring Boot lifecycle POM must not use 4.0.6.RELEASE: $($record.pom_path)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
                $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
                foreach ($forbiddenText in @("4.0.6.RELEASE", "mvn spring-boot:run", "bootRun", "/health", "actuator")) {
                    if ($transcriptText -match [regex]::Escape($forbiddenText)) {
                        Add-Failure "Spring Boot lifecycle transcript must not contain spoofing or wrong-runtime text '$forbiddenText': $($record.transcript)"
                    }
                }
            }
            if ([string]$runtimePlan.dependency_version_status -ne "passed" -or [string]$runtimePlan.jar_build_status -ne "passed") {
                Add-Failure "Spring Boot runtime plan dependency and JAR build status must be passed after lifecycle validation: $runtimePlanPath"
            }
            if ([string]$runtimePlan.dependency_version -ne "4.0.6") {
                Add-Failure "Spring Boot runtime plan dependency_version must be 4.0.6 after lifecycle validation: $runtimePlanPath"
            }
            if ([string]$runtimePlan.built_jar -ne [string]$record.built_jar -or [string]$runtimePlan.built_jar_sha256 -ne [string]$record.built_jar_sha256) {
                Add-Failure "Spring Boot runtime plan built_jar evidence must match lifecycle record: $runtimePlanPath"
            }
            if ($runtimePlan.readiness_probe.status -ne "passed") {
                Add-Failure "Spring Boot runtime plan readiness_probe must be passed after lifecycle validation: $runtimePlanPath"
            }
            foreach ($satisfiedRuntimeBlocker in @("select_exact_spring_boot_dependency_version_or_generated_app_build_file", "build_application_jar_from_selected_public_dependencies")) {
                if (@($runtimePlan.blockers) -contains $satisfiedRuntimeBlocker) {
                    Add-Failure "Spring Boot runtime plan still contains satisfied blocker ${satisfiedRuntimeBlocker}: $runtimePlanPath"
                }
            }
            $blockersAfterLifecycle = Get-BlockerIds -Manifest $manifest
            foreach ($satisfiedSourceBlocker in @("spring-boot-dependency-version-not-selected", "spring-boot-jar-build-not-proven")) {
                if ($blockersAfterLifecycle.Contains($satisfiedSourceBlocker)) {
                    Add-Failure "Spring Boot candidate manifest still contains satisfied blocker ${satisfiedSourceBlocker}: $manifestPath"
                }
            }
        }
        if ($profile.Repository -eq "unclecode/crawl4ai") {
            if ([string]$record.image -ne "unclecode/crawl4ai:latest") {
                Add-Failure "Crawl4AI lifecycle image must be unclecode/crawl4ai:latest: $SummaryPath"
            }
            if ([string]$record.pull_command -ne "docker pull unclecode/crawl4ai:latest") {
                Add-Failure "Crawl4AI lifecycle pull_command must record selected README Docker pull: $SummaryPath"
            }
            if ([int]$record.docker_pull_exit_code -ne 0 -or [int]$record.docker_run_exit_code -ne 0 -or [int]$record.docker_rm_exit_code -ne 0) {
                Add-Failure "Crawl4AI lifecycle Docker pull/run/rm exit codes must be 0: $SummaryPath"
            }
            $containerName = [string]$record.container_name
            if ([string]::IsNullOrWhiteSpace($containerName) -or -not $containerName.StartsWith("zappa-crawl4ai-health-", [System.StringComparison]::Ordinal)) {
                Add-Failure "Crawl4AI lifecycle must use a unique zappa-crawl4ai-health-* container name: $SummaryPath"
            }
            if ($containerName -eq "crawl4ai") {
                Add-Failure "Crawl4AI lifecycle must not use the public user-owned crawl4ai container name: $SummaryPath"
            }
            if ([string]$record.cleanup_target_container_name -ne $containerName) {
                Add-Failure "Crawl4AI cleanup target must be the test-owned unique container: $SummaryPath"
            }
            if ([string]$record.protected_container_name -ne "crawl4ai") {
                Add-Failure "Crawl4AI lifecycle must record crawl4ai as protected user-owned container name: $SummaryPath"
            }
            $beforeProtected = @($record.protected_container_names_before)
            $afterProtected = @($record.protected_container_names_after)
            if (($beforeProtected -join "`n") -ne ($afterProtected -join "`n")) {
                Add-Failure "Crawl4AI lifecycle changed protected crawl4ai container state: $SummaryPath"
            }
            if ($record.container_exists_after_cleanup -ne $false) {
                Add-Failure "Crawl4AI lifecycle test-owned container must not exist after cleanup: $SummaryPath"
            }
            foreach ($fileField in @("docker_pull_stdout", "docker_pull_stderr", "docker_run_stdout", "docker_run_stderr", "docker_rm_stdout", "docker_rm_stderr", "docker_logs_stdout", "docker_logs_stderr", "docker_inspect_started", "docker_inspect_after_cleanup")) {
                $value = [string]$record.$fileField
                Test-ExistingFileUnderRoot -Path $value -Root $LifecycleRoot -Description "Crawl4AI lifecycle ${fileField}" | Out-Null
            }
            foreach ($hashSpec in @(
                    [pscustomobject]@{ Field = "response_body_sha256"; Path = [string]$record.response },
                    [pscustomobject]@{ Field = "docker_inspect_started_sha256"; Path = [string]$record.docker_inspect_started },
                    [pscustomobject]@{ Field = "docker_inspect_after_cleanup_sha256"; Path = [string]$record.docker_inspect_after_cleanup }
                )) {
                if ([string]::IsNullOrWhiteSpace($hashSpec.Path) -or -not (Test-Path -LiteralPath $hashSpec.Path -PathType Leaf)) {
                    Add-Failure "Crawl4AI lifecycle $($hashSpec.Field) source file missing: $($hashSpec.Path)"
                    continue
                }
                $actualHash = Get-Sha256Hex -Path $hashSpec.Path
                $actualValue = [string]$record.PSObject.Properties[$hashSpec.Field].Value
                if ($actualValue -ne $actualHash) {
                    Add-Failure "Crawl4AI lifecycle $($hashSpec.Field) must match actual file: $($hashSpec.Path)"
                }
            }
            if (Test-Path -LiteralPath ([string]$record.transcript) -PathType Leaf) {
                $transcriptText = Get-Content -LiteralPath ([string]$record.transcript) -Raw
                foreach ($forbiddenText in @("--name crawl4ai", "Route: /crawl", "ExpectedBody", "StatusCode: 200")) {
                    if ($transcriptText -match [regex]::Escape($forbiddenText)) {
                        Add-Failure "Crawl4AI lifecycle transcript must not promote unsafe or invented contract text '$forbiddenText': $($record.transcript)"
                    }
                }
            }
        }

        $qaaSValidationFields = @("build_validation", "template_validation", "live_validation", "selected_candidate_qaas_validation")
        if ($profile.Repository -eq "pallets/flask") {
            $qaaSValidationFields = @("assertion_build_validation") + $qaaSValidationFields
        }
        if ($profile.Repository -eq "expressjs/express") {
            $qaaSValidationFields = @("assertion_build_validation") + $qaaSValidationFields
        }
        if ($profile.Repository -eq "denoland/deno") {
            $qaaSValidationFields = @("assertion_build_validation") + $qaaSValidationFields
        }
        if ($profile.Repository -eq "spring-projects/spring-boot") {
            $qaaSValidationFields = @("assertion_build_validation") + $qaaSValidationFields
        }
        if ($profile.Repository -eq "unclecode/crawl4ai") {
            $qaaSValidationFields = @("assertion_build_validation") + $qaaSValidationFields
        }
        $qaasValidationValues = @()
        foreach ($field in $qaaSValidationFields) {
            $qaasValidationValues += ,(Get-ValidationValue -Object $manifest -Name $field)
        }
        $qaasValidationValues += ,(Get-ValidationValue -Object $runtimePlan -Name "qaas_validation")
        $qaasPassed = $false
        $qaasFullyPassed = $true
        foreach ($value in @($qaasValidationValues)) {
            $isPassed = Test-PassedValidation -Value $value
            if ($isPassed) {
                $qaasPassed = $true
            } else {
                $qaasFullyPassed = $false
            }
        }
        if ($profile.Repository -in @("pallets/flask", "expressjs/express", "denoland/deno", "fastapi/fastapi", "gin-gonic/gin", "spring-projects/spring-boot", "unclecode/crawl4ai") -and $qaasPassed -and -not $qaasFullyPassed) {
            Add-Failure "$($profile.Repository) lifecycle evidence must not claim partial QaaS template/live validation passed: $manifestPath"
        }

        if ($manifest.promotion_state -ne "blocked" -or $manifest.status -ne "blocked_until_repo_contract_review") {
            Add-Failure "Lifecycle must not promote candidate manifest: $manifestPath"
        }
        if ($manifest.lifecycle_validation.status -ne "passed") {
            Add-Failure "Candidate manifest missing passed lifecycle_validation: $manifestPath"
        }
        if (-not (
                ($runtimePlan.PSObject.Properties.Name -contains "lifecycle_validation") -and
                $runtimePlan.lifecycle_validation.status -eq "passed"
            )) {
            Add-Failure "Runtime plan missing passed lifecycle_validation: $runtimePlanPath"
        }
        foreach ($validationRecord in @(
                [pscustomobject]@{ Name = "manifest"; Value = $manifest.lifecycle_validation },
                [pscustomobject]@{ Name = "runtime plan"; Value = (Get-ValidationValue -Object $runtimePlan -Name "lifecycle_validation") }
            )) {
            if ($null -eq $validationRecord.Value) {
                Add-Failure "Candidate $($validationRecord.Name) missing lifecycle_validation record."
                continue
            }
            Test-SamePathValue -Actual ([string]$validationRecord.Value.summary) -Expected $SummaryPath -Description "Candidate $($validationRecord.Name) lifecycle summary" | Out-Null
            Test-SamePathValue -Actual ([string]$validationRecord.Value.transcript) -Expected ([string]$record.transcript) -Description "Candidate $($validationRecord.Name) lifecycle transcript" | Out-Null
            Test-SamePathValue -Actual ([string]$validationRecord.Value.response) -Expected ([string]$record.response) -Description "Candidate $($validationRecord.Name) lifecycle response" | Out-Null
        }
        $gateMap = Get-GateMap -Manifest $manifest
        foreach ($gateId in @(@($profile.LifecycleGates) + @("cleanup-contract"))) {
            if (-not $gateMap.ContainsKey($gateId)) {
                Add-Failure "Candidate manifest missing lifecycle gate ${gateId}: $manifestPath"
                continue
            }
            $gate = $gateMap[$gateId]
            if ($gate.status -ne "passed") {
                Add-Failure "Candidate lifecycle gate ${gateId} must be passed when lifecycle evidence passed: $manifestPath"
            }
            if (-not (@($gate.evidence) -contains $SummaryPath)) {
                Add-Failure "Candidate lifecycle gate ${gateId} must cite lifecycle summary: $manifestPath"
            }
        }
        $blockers = Get-BlockerIds -Manifest $manifest
        if ($blockers.Contains($profile.LifecycleBlocker)) {
            Add-Failure "Passed lifecycle should remove $($profile.LifecycleBlocker) blocker: $manifestPath"
        }
        $textBodyQaaSSatisfiedSourceBlockers = @()
        if ($profile.Repository -eq "pallets/flask") {
            $textBodyQaaSSatisfiedSourceBlockers = @("flask-text-body-hook-not-template-validated", "qaas-template-live-not-run")
        }
        if ($profile.Repository -eq "expressjs/express") {
            $textBodyQaaSSatisfiedSourceBlockers = @("express-text-body-hook-not-template-validated", "qaas-template-live-not-run")
        }
        if ($profile.Repository -eq "denoland/deno") {
            $textBodyQaaSSatisfiedSourceBlockers = @("deno-text-body-hook-not-template-validated", "qaas-template-live-not-run")
        }
        if ($profile.Repository -eq "spring-projects/spring-boot") {
            $textBodyQaaSSatisfiedSourceBlockers = @("spring-boot-text-body-hook-not-template-validated", "qaas-template-live-not-run")
        }
        foreach ($blockerId in @($profile.RequiredRemainingBlockers)) {
            if ($qaasFullyPassed -and $blockerId -eq $profile.QaaSTemplateBlocker) {
                continue
            }
            if ($qaasFullyPassed -and $blockerId -in $textBodyQaaSSatisfiedSourceBlockers) {
                continue
            }
            if ($qaasFullyPassed -and $blockerId -eq "httpstatus-docs-inconsistency-recorded") {
                continue
            }
            if (-not $blockers.Contains($blockerId)) {
                Add-Failure "Candidate must keep blocker ${blockerId}: $manifestPath"
            }
        }
        if ($qaasFullyPassed) {
            if ($blockers.Contains($profile.QaaSTemplateBlocker)) {
                Add-Failure "Candidate should remove qaas-template-live-not-run after live QaaS validation passes: $manifestPath"
            }
            if ($profile.Repository -eq "pallets/flask" -and $blockers.Contains("flask-text-body-hook-not-template-validated")) {
                Add-Failure "Candidate should remove flask-text-body-hook-not-template-validated after Flask live QaaS validation passes: $manifestPath"
            }
            if ($profile.Repository -eq "expressjs/express" -and $blockers.Contains("express-text-body-hook-not-template-validated")) {
                Add-Failure "Candidate should remove express-text-body-hook-not-template-validated after Express live QaaS validation passes: $manifestPath"
            }
            if ($profile.Repository -eq "denoland/deno" -and $blockers.Contains("deno-text-body-hook-not-template-validated")) {
                Add-Failure "Candidate should remove deno-text-body-hook-not-template-validated after Deno live QaaS validation passes: $manifestPath"
            }
            if ($profile.Repository -eq "spring-projects/spring-boot" -and $blockers.Contains("spring-boot-text-body-hook-not-template-validated")) {
                Add-Failure "Candidate should remove spring-boot-text-body-hook-not-template-validated after Spring Boot live QaaS validation passes: $manifestPath"
            }
            if ($blockers.Contains("httpstatus-docs-inconsistency-recorded")) {
                Add-Failure "Candidate should move httpstatus-docs-inconsistency-recorded to validation_advisories after live QaaS validation passes: $manifestPath"
            }
            $httpStatusAdvisory = Get-ValidationAdvisory -Manifest $manifest -AdvisoryId "httpstatus-docs-inconsistency-recorded"
            if ($null -eq $httpStatusAdvisory) {
                Add-Failure "Candidate must keep nonblocking httpstatus-docs-inconsistency-recorded validation advisory after live QaaS validation passes: $manifestPath"
            } elseif (($httpStatusAdvisory.PSObject.Properties.Name -contains "blocking") -and [bool]$httpStatusAdvisory.blocking) {
                Add-Failure "Candidate httpstatus-docs-inconsistency-recorded validation advisory must be nonblocking: $manifestPath"
            }
        } elseif (-not $blockers.Contains($profile.QaaSTemplateBlocker)) {
            Add-Failure "Candidate must keep blocker qaas-template-live-not-run before live QaaS validation passes: $manifestPath"
        }

        if ($runtimePlan.promotion_state -ne "blocked") {
            Add-Failure "Runtime plan must remain blocked after lifecycle pass: $runtimePlanPath"
        }
        if ($runtimePlan.cleanup.status -ne "passed") {
            Add-Failure "Runtime plan cleanup must be passed after lifecycle pass: $runtimePlanPath"
        }
        if (@($runtimePlan.blockers) -contains "prove_process_lifecycle_and_cleanup_without assuming private source") {
            Add-Failure "Runtime plan still contains satisfied lifecycle blocker: $runtimePlanPath"
        }
        if ($profile.Repository -eq "denoland/deno" -and @($runtimePlan.blockers) -contains "prove_managed_deno_toolchain_without_using_ambient_path") {
            Add-Failure "Deno runtime plan still contains satisfied managed toolchain blocker: $runtimePlanPath"
        }
        foreach ($runtimeBlocker in @($profile.RequiredRuntimeBlockers)) {
            if ($qaasFullyPassed -and $runtimeBlocker -in @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
                continue
            }
            if ($qaasFullyPassed -and $profile.Repository -in @("pallets/flask", "expressjs/express", "denoland/deno") -and $runtimeBlocker -eq "validate_exact_text_body_custom_assertion_schema_template_and_live") {
                continue
            }
            if (-not (@($runtimePlan.blockers) -contains $runtimeBlocker)) {
                Add-Failure "$($profile.Repository) runtime plan must keep blocker ${runtimeBlocker}: $runtimePlanPath"
            }
        }
        if ($qaasFullyPassed -and $profile.Repository -in @("pallets/flask", "expressjs/express", "denoland/deno")) {
            foreach ($satisfiedRuntimeBlocker in @("validate_exact_text_body_custom_assertion_schema_template_and_live", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
                if (@($runtimePlan.blockers) -contains $satisfiedRuntimeBlocker) {
                    Add-Failure "$($profile.Repository) runtime plan should remove satisfied blocker ${satisfiedRuntimeBlocker}: $runtimePlanPath"
                }
            }
            if (
                -not ($runtimePlan.PSObject.Properties.Name -contains "custom_text_body_assertion") -or
                $runtimePlan.custom_text_body_assertion.status -ne "build_template_live_validated" -or
                $runtimePlan.custom_text_body_assertion.validation_status -ne "build_template_live_validated"
            ) {
                Add-Failure "$($profile.Repository) runtime plan custom_text_body_assertion must be marked build_template_live_validated after live QaaS validation passes: $runtimePlanPath"
            }
        }
    }
} else {
    Add-Failure "Unexpected lifecycle record status '$($record.status)': $SummaryPath"
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Selected top-repo candidate lifecycle check passed with status $($record.status)."
