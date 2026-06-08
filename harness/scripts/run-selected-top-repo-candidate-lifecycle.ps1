param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\200-typicode-json-server",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates",
    [int]$TimeoutSeconds = 90,
    [switch]$NoManifestUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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

    $fullPath = Get-NormalizedPath -Path $Path
    $rootPath = Get-NormalizedPath -Path $Root
    if ([string]::Equals($fullPath, $rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootPrefix = "$rootPath$([System.IO.Path]::DirectorySeparatorChar)"
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-DescendantPath {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Description
    )

    $fullPath = Get-NormalizedPath -Path $Path
    if (-not (Test-PathUnderRoot -Path $fullPath -Root $Root)) {
        throw "$Description must stay under $(Get-NormalizedPath -Path $Root); got $fullPath"
    }

    return $fullPath
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 24), $script:Utf8NoBom)
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

function Get-PortOwner {
    param([int]$Port)

    try {
        $connections = @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @("127.0.0.1", "::1", "0.0.0.0", "::") })
        if ($connections.Count -eq 0) {
            return @()
        }

        return @($connections | Select-Object LocalAddress, LocalPort, State, OwningProcess)
    } catch {
        return @()
    }
}

function Get-ProcessTreeIds {
    param([int]$RootProcessId)

    $ids = New-Object System.Collections.Generic.List[int]
    if (-not $ids.Contains($RootProcessId)) {
        $ids.Add($RootProcessId)
    }
    foreach ($childId in @(Get-ChildProcessIds -ParentId $RootProcessId)) {
        if (-not $ids.Contains([int]$childId)) {
            $ids.Add([int]$childId)
        }
    }

    return @($ids.ToArray())
}

function Get-ChildProcessIds {
    param([int]$ParentId)

    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ParentId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        [int]$child.ProcessId
        foreach ($grandChild in @(Get-ChildProcessIds -ParentId ([int]$child.ProcessId))) {
            [int]$grandChild
        }
    }
}

function Stop-ProcessTree {
    param([int]$RootProcessId)

    $ids = @(Get-ProcessTreeIds -RootProcessId $RootProcessId)

    foreach ($processId in @($ids | Sort-Object -Descending)) {
        try {
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($null -ne $process) {
                Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Best-effort cleanup; final port/process checks decide pass/fail.
        }
    }

    Start-Sleep -Milliseconds 500
    return @($ids)
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

function Test-NodeVersionAtLeast {
    param(
        [string]$ActualVersion,
        [int]$Major,
        [int]$Minor,
        [int]$Patch
    )

    $normalized = $ActualVersion.Trim().TrimStart("v")
    $parts = @($normalized.Split(".") | ForEach-Object { [int]$_ })
    if ($parts[0] -gt $Major) { return $true }
    if ($parts[0] -lt $Major) { return $false }
    if ($parts[1] -gt $Minor) { return $true }
    if ($parts[1] -lt $Minor) { return $false }
    return ($parts[2] -ge $Patch)
}

function New-BlockedResult {
    param(
        [string]$Reason,
        [string]$RunDir,
        [string]$SummaryPath
    )

    $record = [ordered]@{
        schema_version = 1
        status = "blocked"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "typicode/json-server"
        reason = $Reason
        run_dir = $RunDir
        transcript = $null
        manifest_updated = $false
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $SummaryPath -Value $record
    return $record
}

$candidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates"
$candidateDirPath = Assert-DescendantPath -Path $CandidateDir -Root $candidateRoot -Description "CandidateDir"
if (-not (Test-Path -LiteralPath $candidateDirPath -PathType Container)) {
    throw "Candidate directory not found: $candidateDirPath"
}

$allowedOutRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates"
$outRootPath = Get-NormalizedPath -Path $OutRoot
if (-not [string]::Equals($outRootPath, (Get-NormalizedPath -Path $allowedOutRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutRoot must be the managed selected-candidate lifecycle root: $allowedOutRoot"
}

$runDir = Join-Path $outRootPath (Get-Date -Format "yyyyMMdd-HHmmss-fff")
$workDir = Join-Path $runDir "work"
$evidenceDir = Join-Path $runDir "evidence"
foreach ($dir in @($workDir, $evidenceDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$fixturePath = Join-Path $candidateDirPath "fixtures\db.json"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\200-typicode-json-server\selected-contract.json"
$selectedPackagePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\200-typicode-json-server\files\package.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\200-typicode-json-server\files\README.md"
$stdoutPath = Join-Path $evidenceDir "json-server.stdout.txt"
$stderrPath = Join-Path $evidenceDir "json-server.stderr.txt"
$transcriptPath = Join-Path $evidenceDir "lifecycle.transcript.txt"
$responsePath = Join-Path $evidenceDir "posts-1-response.json"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Candidate manifest not found: $manifestPath"
}
if (-not (Test-Path -LiteralPath $runtimePlanPath -PathType Leaf)) {
    throw "Candidate runtime plan not found: $runtimePlanPath"
}
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
    throw "Candidate fixture not found: $fixturePath"
}
if (-not (Test-Path -LiteralPath $selectedContractPath -PathType Leaf)) {
    throw "Selected contract not found: $selectedContractPath"
}
if (-not (Test-Path -LiteralPath $selectedPackagePath -PathType Leaf)) {
    throw "Selected package evidence not found: $selectedPackagePath"
}
if (-not (Test-Path -LiteralPath $selectedReadmePath -PathType Leaf)) {
    throw "Selected README evidence not found: $selectedReadmePath"
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
$selectedContract = Read-JsonFile -Path $selectedContractPath
$selectedPackage = Read-JsonFile -Path $selectedPackagePath
if ([string]$manifest.source_repository -ne "typicode/json-server" -or [string]$runtimePlan.repository -ne "typicode/json-server") {
    throw "This lifecycle runner only owns typicode/json-server."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected candidate must be blocked before lifecycle validation."
}

$packageVersion = [string]$selectedPackage.version
if ([string]::IsNullOrWhiteSpace($packageVersion)) {
    throw "Selected package evidence lacks version: $selectedPackagePath"
}
$packageSpec = "json-server@$packageVersion"
$selectedPackageVersionEvidence = @($selectedContract.selected_public_contracts | Where-Object { [string]$_.source_path -eq "package.json" } | Select-Object -First 1)
if ($selectedPackageVersionEvidence.Count -eq 0 -or [string]$selectedPackageVersionEvidence[0].local_path -ne $selectedPackagePath) {
    throw "Selected contract package evidence mismatch: $selectedContractPath"
}

$fixtureJson = Read-JsonFile -Path $fixturePath
if ([string]$fixtureJson.posts[0].id -ne "1" -or [string]$fixtureJson.posts[0].title -ne "a title" -or [int]$fixtureJson.posts[0].views -ne 100) {
    throw "Candidate runtime fixture must match README-backed id/title/views contract: $fixturePath"
}
$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @('"id": "1"', '"title": "a title"', '"views": 100', "npx json-server db.json")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected README evidence missing marker '$marker': $selectedReadmePath"
    }
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$npmCommand = Get-Command npm -ErrorAction SilentlyContinue
$npxCommand = Get-Command npx.cmd -ErrorAction SilentlyContinue
if ($null -eq $npxCommand) {
    $npxCommand = Get-Command npx -ErrorAction SilentlyContinue
}
if ($null -eq $nodeCommand -or $null -eq $npmCommand -or $null -eq $npxCommand) {
    $blocked = New-BlockedResult -Reason "node_npm_or_npx_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
$nodeVersion = & node --version
$npmVersion = & npm --version
if (-not (Test-NodeVersionAtLeast -ActualVersion $nodeVersion -Major 22 -Minor 12 -Patch 0)) {
    $blocked = New-BlockedResult -Reason "node_version_below_selected_package_engine" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 3000
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $blocked = New-BlockedResult -Reason "port_3000_already_in_use" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$stagedFixturePath = Join-Path $workDir "db.json"
Copy-Item -LiteralPath $fixturePath -Destination $stagedFixturePath -Force
$candidateFixtureSha256 = Get-Sha256Hex -Path $fixturePath
$stagedFixtureSha256 = Get-Sha256Hex -Path $stagedFixturePath
if ($candidateFixtureSha256 -ne $stagedFixtureSha256) {
    throw "Staged db.json hash mismatch."
}

$process = $null
$started = Get-Date
$ready = $false
$readyStatus = ""
$responseBody = ""
$responseStatus = $null
$cleanupProcessIds = @()
$portOwnersAfterCleanup = @()
$remainingTrackedProcessIds = @()
$portOwnersDuringReady = @()
$processTreeIdsDuringReady = @()
$exitCode = 1
$validationStatus = "failed"
$failureReason = ""

try {
    $arguments = @("--yes", "--package", $packageSpec, "json-server", "db.json")
    $process = Start-Process -FilePath $npxCommand.Source -ArgumentList $arguments -WorkingDirectory $workDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            $failureReason = "json-server process exited before readiness with code $($process.ExitCode)"
            break
        }

        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/posts/1" -UseBasicParsing -TimeoutSec 2
            $responseStatus = [int]$response.StatusCode
            $responseBody = [string]$response.Content
            $json = $responseBody | ConvertFrom-Json
            if ($responseStatus -eq 200 -and [string]$json.id -eq "1" -and [string]$json.title -eq "a title" -and [int]$json.views -eq 100) {
                $portOwnersDuringReady = @(Get-PortOwner -Port $port)
                $processTreeIdsDuringReady = @(Get-ProcessTreeIds -RootProcessId ([int]$process.Id))
                $foreignOwners = @($portOwnersDuringReady | Where-Object { $processTreeIdsDuringReady -notcontains [int]$_.OwningProcess })
                if ($portOwnersDuringReady.Count -eq 0) {
                    $failureReason = "readiness response succeeded but no tracked port owner was found"
                } elseif ($foreignOwners.Count -gt 0) {
                    $failureReason = "readiness response was served by a process outside the tracked process tree"
                } else {
                    $ready = $true
                    $readyStatus = "HTTP 200 from /posts/1 with README-backed id/title/views"
                    Write-TextFile -Path $responsePath -Value $responseBody
                    break
                }
            }

            $failureReason = "readiness response did not match expected id/title/views"
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $ready -and [string]::IsNullOrWhiteSpace($failureReason)) {
        $failureReason = "timed out waiting for /posts/1"
    }
} finally {
    if ($null -ne $process) {
        $cleanupProcessIds = @(Stop-ProcessTree -RootProcessId ([int]$process.Id))
    }
    foreach ($processId in @($cleanupProcessIds)) {
        if ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
            $remainingTrackedProcessIds += [int]$processId
        }
    }
    $portOwnersAfterCleanup = @(Get-PortOwner -Port $port)
}

$cleanupPassed = ($portOwnersAfterCleanup.Count -eq 0 -and @($remainingTrackedProcessIds).Count -eq 0)
if ($ready -and $cleanupPassed) {
    $exitCode = 0
    $validationStatus = "passed"
} elseif ($ready -and -not $cleanupPassed) {
    $failureReason = "json-server responded but port 3000 remained in use after cleanup"
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Validation: selected-top-repo-candidate-lifecycle")
$lines.Add("Repository: typicode/json-server")
$lines.Add("Command: npx --yes json-server db.json")
$lines.Add("WorkingDirectory: $workDir")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("TimeoutSeconds: $TimeoutSeconds")
$lines.Add("NodeVersion: $nodeVersion")
$lines.Add("NpmVersion: $npmVersion")
$lines.Add("NpxPath: $($npxCommand.Source)")
$lines.Add("PackageSpec: $packageSpec")
$lines.Add("SelectedPackageEvidence: $selectedPackagePath")
$lines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$lines.Add("CandidateFixtureSha256: $candidateFixtureSha256")
$lines.Add("StagedFixtureSha256: $stagedFixtureSha256")
$lines.Add("Ready: $ready")
$lines.Add("ReadyStatus: $readyStatus")
$lines.Add("ResponseStatus: $responseStatus")
$portOwnerDescriptions = @($portOwnersDuringReady | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)/pid=$($_.OwningProcess)/state=$($_.State)" })
$lines.Add("PortOwnersDuringReady: $($portOwnerDescriptions -join ',')")
$lines.Add("ProcessTreeIdsDuringReady: $($processTreeIdsDuringReady -join ',')")
$lines.Add("CleanupPassed: $cleanupPassed")
$lines.Add("CleanupProcessIds: $($cleanupProcessIds -join ',')")
$lines.Add("RemainingTrackedProcessIds: $($remainingTrackedProcessIds -join ',')")
$lines.Add("PortOwnersAfterCleanupCount: $($portOwnersAfterCleanup.Count)")
$lines.Add("ExitCode: $exitCode")
$lines.Add("FailureReason: $failureReason")
$lines.Add("")
$lines.Add("==== stdout ====")
if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
    $lines.Add((Get-Content -LiteralPath $stdoutPath -Raw))
}
$lines.Add("==== stderr ====")
if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $lines.Add((Get-Content -LiteralPath $stderrPath -Raw))
}
Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)

$record = [ordered]@{
    schema_version = 1
    status = $validationStatus
    promotion_state = "blocked"
    completion_ready = $false
    repository = "typicode/json-server"
    validation_kind = "selected_candidate_process_lifecycle"
    command = "npx --yes --package $packageSpec json-server db.json"
    package_spec = $packageSpec
    node_version = $nodeVersion
    npm_version = $npmVersion
    npx_path = $npxCommand.Source
    working_directory = $workDir
    candidate_fixture_sha256 = $candidateFixtureSha256
    staged_fixture_sha256 = $stagedFixtureSha256
    selected_readme_evidence = $selectedReadmePath
    selected_package_evidence = $selectedPackagePath
    transcript = $transcriptPath
    stdout = $stdoutPath
    stderr = $stderrPath
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_contract_passed = $ready
    cleanup_passed = $cleanupPassed
    cleanup_process_ids = @($cleanupProcessIds)
    remaining_tracked_process_ids = @($remainingTrackedProcessIds)
    port_owners_after_cleanup_count = $portOwnersAfterCleanup.Count
    manifest = $manifestPath
    runtime_plan = $runtimePlanPath
    run_dir = $runDir
    exit_code = $exitCode
    failure_reason = $failureReason
    weak_validation_passed = $false
}
Write-JsonFile -Path $summaryPath -Value $record

if ($validationStatus -eq "passed" -and -not $NoManifestUpdate) {
    $validationRecord = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "npx --yes --package $packageSpec json-server db.json ; GET http://127.0.0.1:3000/posts/1 ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @($cleanupProcessIds)
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -in @("node-json-server-process-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -ne "json-server-process-lifecycle-not-proven") {
            $remainingBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingBlockers)
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan.cleanup.status = "passed"
    $runtimePlan.cleanup | Add-Member -NotePropertyName "evidence" -NotePropertyValue @($summaryPath, $transcriptPath) -Force
    $runtimePlan | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    $runtimeBlockers = @()
    foreach ($blocker in @($runtimePlan.blockers)) {
        if ($blocker -ne "prove_process_lifecycle_and_cleanup_without assuming private source") {
            $runtimeBlockers += $blocker
        }
    }
    $runtimePlan.blockers = @($runtimeBlockers)
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan
}

Write-Output "Lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -ne "passed") {
    exit 1
}
