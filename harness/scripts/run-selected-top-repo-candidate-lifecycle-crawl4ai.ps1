param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\250-unclecode-crawl4ai",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates",
    [int]$PullTimeoutSeconds = 900,
    [int]$ReadinessTimeoutSeconds = 240,
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
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32), $script:Utf8NoBom)
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

function Get-PortOwner {
    param([int]$Port)

    try {
        $connections = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @("127.0.0.1", "::1", "0.0.0.0", "::") })
        if ($connections.Count -eq 0) {
            return @()
        }

        return @($connections | Select-Object LocalAddress, LocalPort, State, OwningProcess)
    } catch {
        return @()
    }
}

function Invoke-LoggedProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSeconds,
        [string]$WorkingDirectory = $PWD.Path
    )

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $StdoutPath)) | Out-Null
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $StderrPath)) | Out-Null
    if (-not (Test-Path -LiteralPath $StdoutPath -PathType Leaf)) {
        Write-TextFile -Path $StdoutPath -Value ""
    }
    if (-not (Test-Path -LiteralPath $StderrPath -PathType Leaf)) {
        Write-TextFile -Path $StderrPath -Value ""
    }

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -PassThru -WindowStyle Hidden -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        } catch {
            # The result record captures the timeout; final validation decides pass/fail.
        }
        Start-Sleep -Milliseconds 300
    }

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { -1 } else { [int]$process.ExitCode }
        TimedOut = $timedOut
        Command = "$FilePath $($ArgumentList -join ' ')"
        Stdout = $StdoutPath
        Stderr = $StderrPath
    }
}

function Get-DockerNames {
    param(
        [string]$DockerPath,
        [string]$NameRegex
    )

    $output = @(& $DockerPath ps -a --filter "name=$NameRegex" --format "{{.Names}}" 2>$null)
    return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
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
        repository = "unclecode/crawl4ai"
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

$runId = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$runDir = Join-Path $outRootPath $runId
$evidenceDir = Join-Path $runDir "evidence"
[System.IO.Directory]::CreateDirectory($evidenceDir) | Out-Null

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-crawl4ai.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\250-unclecode-crawl4ai\selected-contract.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\250-unclecode-crawl4ai\files\README.md"
$selectedDockerfilePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\250-unclecode-crawl4ai\files\Dockerfile"
$selectedComposePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\250-unclecode-crawl4ai\files\docker-compose.yml"
$responsePath = Join-Path $evidenceDir "health-response.txt"
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
$transcriptPath = Join-Path $evidenceDir "crawl4ai-lifecycle.transcript.txt"

foreach ($requiredPath in @($manifestPath, $runtimePlanPath, $selectedContractPath, $selectedReadmePath, $selectedDockerfilePath, $selectedComposePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Crawl4AI lifecycle input not found: $requiredPath"
    }
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
if ([string]$manifest.source_repository -ne "unclecode/crawl4ai" -or [string]$runtimePlan.repository -ne "unclecode/crawl4ai") {
    throw "This lifecycle runner only owns unclecode/crawl4ai."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected candidate must be blocked before lifecycle validation."
}
if ([string]$runtimePlan.image -ne "unclecode/crawl4ai:latest") {
    throw "Crawl4AI runtime plan image mismatch: $runtimePlanPath"
}
if ([string]$runtimePlan.cleanup.strategy -ne "docker_rm_force_test_owned_unique_container" -or [string]$runtimePlan.cleanup.must_not_remove_container_name -ne "crawl4ai") {
    throw "Crawl4AI runtime plan does not preserve the user-owned crawl4ai container name: $runtimePlanPath"
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @("docker pull unclecode/crawl4ai:latest", "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest", "http://localhost:11235/crawl")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected README evidence missing marker '$marker': $selectedReadmePath"
    }
}
$dockerfileText = Get-Content -LiteralPath $selectedDockerfilePath -Raw
foreach ($marker in @("curl -f http://localhost:11235/health || exit 1", "redis-cli ping", 'MEM=$(free -m')) {
    if (-not $dockerfileText.Contains($marker)) {
        throw "Selected Dockerfile evidence missing marker '$marker': $selectedDockerfilePath"
    }
}
$composeText = Get-Content -LiteralPath $selectedComposePath -Raw
foreach ($marker in @('test: ["CMD", "curl", "-f", "http://localhost:11235/health"]', "memory: 4G", "memory: 1G")) {
    if (-not $composeText.Contains($marker)) {
        throw "Selected docker-compose evidence missing marker '$marker': $selectedComposePath"
    }
}

$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $dockerCommand) {
    $blocked = New-BlockedResult -Reason "docker_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$dockerVersionText = ""
try {
    $dockerVersionText = (& $dockerCommand.Source version --format "{{.Server.Version}}" 2>$null | Out-String).Trim()
} catch {
    $blocked = New-BlockedResult -Reason "docker_daemon_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
if ([string]::IsNullOrWhiteSpace($dockerVersionText)) {
    $blocked = New-BlockedResult -Reason "docker_daemon_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 11235
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $blocked = New-BlockedResult -Reason "port_11235_already_in_use" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$protectedContainerName = "crawl4ai"
$protectedContainerNamesBefore = @(Get-DockerNames -DockerPath $dockerCommand.Source -NameRegex "^/$protectedContainerName$")
$containerName = "zappa-crawl4ai-health-$runId"
if ($containerName -eq $protectedContainerName -or -not $containerName.StartsWith("zappa-crawl4ai-health-", [System.StringComparison]::Ordinal)) {
    throw "Unsafe Crawl4AI test container name: $containerName"
}

$image = "unclecode/crawl4ai:latest"
$pullCommand = "docker pull $image"
$dockerRunArguments = @("run", "-d", "-p", "127.0.0.1:11235:11235", "--name", $containerName, "--shm-size=1g", $image)
$dockerRunCommand = "docker $($dockerRunArguments -join ' ')"
$pullResult = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList @("pull", $image) -StdoutPath $pullStdoutPath -StderrPath $pullStderrPath -TimeoutSeconds $PullTimeoutSeconds
if ($pullResult.ExitCode -ne 0) {
    $blocked = New-BlockedResult -Reason "docker_pull_crawl4ai_failed_or_timed_out" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$imageId = ""
try {
    $imageId = (& $dockerCommand.Source image inspect $image --format "{{.Id}}" 2>$null | Out-String).Trim()
} catch {
    $blocked = New-BlockedResult -Reason "docker_image_inspect_crawl4ai_failed_after_pull" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
if ([string]::IsNullOrWhiteSpace($imageId)) {
    $blocked = New-BlockedResult -Reason "docker_image_inspect_crawl4ai_returned_no_image_id" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
$containerId = ""
$ready = $false
$responseStatus = $null
$responseBody = ""
$failureReason = ""
$cleanupPassed = $false
$containerExistsAfterCleanup = $true
$dockerRunExitCode = 1
$dockerRmExitCode = 1
$portOwnersAfterCleanup = @()
$started = Get-Date

try {
    $runResult = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList $dockerRunArguments -StdoutPath $runStdoutPath -StderrPath $runStderrPath -TimeoutSeconds 60
    $dockerRunExitCode = $runResult.ExitCode
    if ($runResult.ExitCode -ne 0) {
        $failureReason = "docker run failed with exit code $($runResult.ExitCode)"
    } else {
        $containerId = (Get-Content -LiteralPath $runStdoutPath -Raw).Trim()
        $deadline = (Get-Date).AddSeconds($ReadinessTimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            try {
                $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 5
                $responseStatus = [int]$response.StatusCode
                $responseBody = [string]$response.Content
                if ($responseStatus -lt 400) {
                    Write-TextFile -Path $responsePath -Value $responseBody
                    $ready = $true
                    break
                }
                $failureReason = "readiness returned HTTP $responseStatus"
            } catch {
                $failureReason = "waiting for /health: $($_.Exception.Message)"
                Start-Sleep -Seconds 2
            }
        }
        if (-not $ready -and [string]::IsNullOrWhiteSpace($failureReason)) {
            $failureReason = "timed out waiting for /health"
        }

        $inspectStarted = @(& $dockerCommand.Source inspect $containerName 2>&1)
        Write-TextFile -Path $inspectStartedPath -Value (($inspectStarted | Out-String).Trim())
        $null = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList @("logs", $containerName) -StdoutPath $logsStdoutPath -StderrPath $logsStderrPath -TimeoutSeconds 30
    }
} finally {
    if (-not [string]::IsNullOrWhiteSpace($containerName)) {
        $rmResult = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList @("rm", "-f", $containerName) -StdoutPath $rmStdoutPath -StderrPath $rmStderrPath -TimeoutSeconds 60
        $dockerRmExitCode = $rmResult.ExitCode
        $inspectAfterCleanup = @(& $dockerCommand.Source ps -a --filter "name=^/$containerName$" --format "{{.Names}}" 2>&1)
        Write-TextFile -Path $inspectAfterCleanupPath -Value (($inspectAfterCleanup | Out-String).Trim())
        $containerExistsAfterCleanup = (@($inspectAfterCleanup | Where-Object { [string]$_ -eq $containerName }).Count -gt 0)
    }
    $portOwnersAfterCleanup = @(Get-PortOwner -Port $port)
}

$protectedContainerNamesAfter = @(Get-DockerNames -DockerPath $dockerCommand.Source -NameRegex "^/$protectedContainerName$")
$protectedContainerNamesBeforeText = @($protectedContainerNamesBefore) -join "`n"
$protectedContainerNamesAfterText = @($protectedContainerNamesAfter) -join "`n"
$cleanupPassed = (
    $dockerRmExitCode -eq 0 -and
    -not $containerExistsAfterCleanup -and
    $portOwnersAfterCleanup.Count -eq 0 -and
    $protectedContainerNamesBeforeText -eq $protectedContainerNamesAfterText
)
$dockerRunStderrText = if (Test-Path -LiteralPath $runStderrPath -PathType Leaf) { Get-Content -LiteralPath $runStderrPath -Raw } else { "" }
$dockerLogsStderrText = if (Test-Path -LiteralPath $logsStderrPath -PathType Leaf) { Get-Content -LiteralPath $logsStderrPath -Raw } else { "" }
$blockedReason = ""
if (-not $ready -and $cleanupPassed) {
    $startupErrorText = "$dockerRunStderrText`n$dockerLogsStderrText"
    if ($startupErrorText -match "unable to find user appuser") {
        $blockedReason = "crawl4ai_upstream_image_user_appuser_missing"
    }
}
$validationStatus = if ($ready -and $cleanupPassed) { "passed" } elseif (-not [string]::IsNullOrWhiteSpace($blockedReason)) { "blocked" } else { "failed" }
$exitCode = if ($validationStatus -eq "failed") { 1 } else { 0 }
if ($ready -and -not $cleanupPassed -and [string]::IsNullOrWhiteSpace($failureReason)) {
    $failureReason = "Crawl4AI responded but cleanup did not prove test-owned container removal"
}

$responseBodySha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { "" }
$inspectStartedSha256 = if (Test-Path -LiteralPath $inspectStartedPath -PathType Leaf) { Get-Sha256Hex -Path $inspectStartedPath } else { "" }
$inspectAfterCleanupSha256 = if (Test-Path -LiteralPath $inspectAfterCleanupPath -PathType Leaf) { Get-Sha256Hex -Path $inspectAfterCleanupPath } else { "" }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Validation: selected-top-repo-candidate-lifecycle-crawl4ai")
$lines.Add("Repository: unclecode/crawl4ai")
$lines.Add("DockerPath: $($dockerCommand.Source)")
$lines.Add("DockerServerVersion: $dockerVersionText")
$lines.Add("DockerPullCommand: $pullCommand")
$lines.Add("DockerPullExitCode: $($pullResult.ExitCode)")
$lines.Add("DockerRunCommand: $dockerRunCommand")
$lines.Add("DockerRunExitCode: $dockerRunExitCode")
$lines.Add("Image: $image")
$lines.Add("ImageId: $imageId")
$lines.Add("ContainerName: $containerName")
$lines.Add("ContainerId: $containerId")
$lines.Add("ProtectedContainerName: $protectedContainerName")
$lines.Add("ProtectedContainerNamesBefore: $($protectedContainerNamesBefore -join ',')")
$lines.Add("ProtectedContainerNamesAfter: $($protectedContainerNamesAfter -join ',')")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("ReadinessUrl: http://127.0.0.1:11235/health")
$lines.Add("Ready: $ready")
$lines.Add("ResponseStatus: $responseStatus")
$lines.Add("ResponseBodySha256: $responseBodySha256")
$lines.Add("DockerInspectStartedSha256: $inspectStartedSha256")
$lines.Add("DockerInspectAfterCleanupSha256: $inspectAfterCleanupSha256")
$lines.Add("DockerRmExitCode: $dockerRmExitCode")
$lines.Add("CleanupTargetContainerName: $containerName")
$lines.Add("CleanupPassed: $cleanupPassed")
$lines.Add("ContainerExistsAfterCleanup: $containerExistsAfterCleanup")
$lines.Add("PortOwnersAfterCleanupCount: $($portOwnersAfterCleanup.Count)")
$lines.Add("ExitCode: $exitCode")
$lines.Add("BlockedReason: $blockedReason")
$lines.Add("FailureReason: $failureReason")
$lines.Add("")
$lines.Add("==== docker pull stdout ====")
$lines.Add((Get-Content -LiteralPath $pullStdoutPath -Raw))
$lines.Add("==== docker pull stderr ====")
$lines.Add((Get-Content -LiteralPath $pullStderrPath -Raw))
$lines.Add("==== docker run stdout ====")
if (Test-Path -LiteralPath $runStdoutPath -PathType Leaf) { $lines.Add((Get-Content -LiteralPath $runStdoutPath -Raw)) }
$lines.Add("==== docker run stderr ====")
if (Test-Path -LiteralPath $runStderrPath -PathType Leaf) { $lines.Add((Get-Content -LiteralPath $runStderrPath -Raw)) }
$lines.Add("==== docker logs stdout ====")
if (Test-Path -LiteralPath $logsStdoutPath -PathType Leaf) { $lines.Add((Get-Content -LiteralPath $logsStdoutPath -Raw)) }
$lines.Add("==== docker logs stderr ====")
if (Test-Path -LiteralPath $logsStderrPath -PathType Leaf) { $lines.Add((Get-Content -LiteralPath $logsStderrPath -Raw)) }
$lines.Add("==== docker rm stdout ====")
if (Test-Path -LiteralPath $rmStdoutPath -PathType Leaf) { $lines.Add((Get-Content -LiteralPath $rmStdoutPath -Raw)) }
$lines.Add("==== docker rm stderr ====")
if (Test-Path -LiteralPath $rmStderrPath -PathType Leaf) { $lines.Add((Get-Content -LiteralPath $rmStderrPath -Raw)) }
Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
Write-TextFile -Path $stdoutPath -Value (@(
        "docker pull stdout: $pullStdoutPath",
        "docker run stdout: $runStdoutPath",
        "docker logs stdout: $logsStdoutPath",
        "docker rm stdout: $rmStdoutPath",
        "transcript: $transcriptPath"
    ) -join [Environment]::NewLine)
Write-TextFile -Path $stderrPath -Value (@(
        "docker pull stderr: $pullStderrPath",
        "docker run stderr: $runStderrPath",
        "docker logs stderr: $logsStderrPath",
        "docker rm stderr: $rmStderrPath",
        "failure_reason: $failureReason"
    ) -join [Environment]::NewLine)

$record = [ordered]@{
    schema_version = 1
    status = $validationStatus
    promotion_state = "blocked"
    completion_ready = $false
    repository = "unclecode/crawl4ai"
    validation_kind = "selected_candidate_docker_lifecycle"
    reason = if ([string]::IsNullOrWhiteSpace($blockedReason)) { $null } else { $blockedReason }
    command = $dockerRunCommand
    pull_command = $pullCommand
    image = $image
    image_id = $imageId
    docker_path = $dockerCommand.Source
    docker_server_version = $dockerVersionText
    docker_pull_exit_code = $pullResult.ExitCode
    docker_run_exit_code = $dockerRunExitCode
    docker_rm_exit_code = $dockerRmExitCode
    container_name = $containerName
    container_id = $containerId
    cleanup_target_container_name = $containerName
    protected_container_name = $protectedContainerName
    protected_container_names_before = @($protectedContainerNamesBefore)
    protected_container_names_after = @($protectedContainerNamesAfter)
    transcript = $transcriptPath
    stdout = $stdoutPath
    stderr = $stderrPath
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_body_sha256 = $responseBodySha256
    response_contract_passed = $ready
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
    docker_inspect_started_sha256 = $inspectStartedSha256
    docker_inspect_after_cleanup_sha256 = $inspectAfterCleanupSha256
    cleanup_passed = $cleanupPassed
    container_exists_after_cleanup = $containerExistsAfterCleanup
    cleanup_process_ids = @()
    remaining_tracked_process_ids = @()
    port_owners_after_cleanup_count = $portOwnersAfterCleanup.Count
    manifest = $manifestPath
    runtime_plan = $runtimePlanPath
    run_dir = $runDir
    exit_code = $exitCode
    failure_reason = $failureReason
    manifest_updated = $false
    weak_validation_passed = $false
}
Write-JsonFile -Path $summaryPath -Value $record

if ($validationStatus -eq "passed" -and -not $NoManifestUpdate) {
    $validationRecord = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "$pullCommand ; $dockerRunCommand ; GET http://127.0.0.1:11235/health ; docker rm -f $containerName"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @()
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -in @("docker-crawl4ai-container-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath, $inspectStartedPath, $inspectAfterCleanupPath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-crawl4ai.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -ne "crawl4ai-docker-lifecycle-not-proven") {
            $remainingBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingBlockers)
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan.cleanup.status = "passed"
    $runtimePlan.cleanup | Add-Member -NotePropertyName "evidence" -NotePropertyValue @($summaryPath, $transcriptPath, $inspectAfterCleanupPath) -Force
    $runtimePlan.cleanup | Add-Member -NotePropertyName "last_validated_container_name" -NotePropertyValue $containerName -Force
    $runtimePlan | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    $runtimeBlockers = @()
    foreach ($blocker in @($runtimePlan.blockers)) {
        if ($blocker -ne "prove_docker_lifecycle_and_cleanup_without_deleting_user_container") {
            $runtimeBlockers += $blocker
        }
    }
    $runtimePlan.blockers = @($runtimeBlockers)
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

    $record["manifest_updated"] = $true
    Write-JsonFile -Path $summaryPath -Value $record
}

Write-Output "Crawl4AI lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -eq "failed") {
    exit 1
}
