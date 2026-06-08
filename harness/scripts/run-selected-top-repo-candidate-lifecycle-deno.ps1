param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\098-denoland-deno",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates",
    [string]$ManagedToolchainRoot = "D:\QaaS\_tmp\zappa-dont-cry\toolchains\deno",
    [string]$DenoReleaseTag = "v2.8.2",
    [string]$DenoDownloadUrl = "https://github.com/denoland/deno/releases/download/v2.8.2/deno-x86_64-pc-windows-msvc.zip",
    [string]$DenoArchiveSha256 = "6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9",
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

    return $fullPath.StartsWith("$rootPath$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)
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

function New-BlockedResult {
    param(
        [string]$Reason,
        [string]$RunDir,
        [string]$SummaryPath,
        [string]$TranscriptPath
    )

    $record = [ordered]@{
        schema_version = 1
        status = "blocked"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "denoland/deno"
        reason = $Reason
        run_dir = $RunDir
        transcript = $TranscriptPath
        manifest_updated = $false
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $SummaryPath -Value $record
    return $record
}

function Get-ManagedDenoToolchain {
    param(
        [string]$ToolchainRoot,
        [string]$ReleaseTag,
        [string]$DownloadUrl,
        [string]$ExpectedSha256,
        [string]$RunDir
    )

    $rootPath = Assert-DescendantPath -Path $ToolchainRoot -Root "D:\QaaS\_tmp\zappa-dont-cry\toolchains" -Description "ManagedToolchainRoot"
    [System.IO.Directory]::CreateDirectory($rootPath) | Out-Null

    $fileName = [System.IO.Path]::GetFileName(([System.Uri]$DownloadUrl).AbsolutePath)
    if ($fileName -ne "deno-x86_64-pc-windows-msvc.zip") {
        throw "DenoDownloadUrl must use the Windows x64 Deno zip asset: $DownloadUrl"
    }
    if (-not $DownloadUrl.Contains("/releases/download/$ReleaseTag/")) {
        throw "DenoDownloadUrl must contain release tag ${ReleaseTag}: $DownloadUrl"
    }

    $archiveDir = Join-Path $rootPath "archives"
    [System.IO.Directory]::CreateDirectory($archiveDir) | Out-Null
    $archivePath = Join-Path $archiveDir "$ReleaseTag-$fileName"
    $installDir = Join-Path $rootPath "$ReleaseTag-windows-amd64"
    $denoPath = Join-Path $installDir "deno.exe"
    $downloaded = $false

    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $archivePath -UseBasicParsing -TimeoutSec 180
        $downloaded = $true
    }

    $actualSha256 = Get-Sha256Hex -Path $archivePath
    if (-not [string]::Equals($actualSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed Deno archive SHA-256 mismatch for $archivePath. Expected $ExpectedSha256, got $actualSha256."
    }

    if (-not (Test-Path -LiteralPath $denoPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $installDir -PathType Container) {
            throw "Managed Deno install directory exists without deno.exe: $installDir"
        }

        $extractRoot = Join-Path $RunDir "deno-extract"
        [System.IO.Directory]::CreateDirectory($extractRoot) | Out-Null
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
        $extractedDeno = Join-Path $extractRoot "deno.exe"
        if (-not (Test-Path -LiteralPath $extractedDeno -PathType Leaf)) {
            throw "Deno archive did not extract deno.exe: $archivePath"
        }

        [System.IO.Directory]::CreateDirectory($installDir) | Out-Null
        Copy-Item -LiteralPath $extractedDeno -Destination $denoPath -Force
    }

    [pscustomobject]@{
        DenoPath = $denoPath
        ArchivePath = $archivePath
        InstallDir = $installDir
        ArchiveSha256 = $actualSha256
        Downloaded = $downloaded
    }
}

function Start-ProcessWithEnvironment {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath,
        [hashtable]$Environment
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($Arguments -join " ")
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) {
        $startInfo.Environment[$key] = [string]$Environment[$key]
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process | Add-Member -NotePropertyName ZappaStdoutTask -NotePropertyValue $stdoutTask -Force
    $process | Add-Member -NotePropertyName ZappaStderrTask -NotePropertyValue $stderrTask -Force
    $process | Add-Member -NotePropertyName ZappaStdoutPath -NotePropertyValue $StdoutPath -Force
    $process | Add-Member -NotePropertyName ZappaStderrPath -NotePropertyValue $StderrPath -Force
    return $process
}

function Save-ProcessOutput {
    param([object]$Process)

    try {
        Write-TextFile -Path ([string]$Process.ZappaStdoutPath) -Value ([string]$Process.ZappaStdoutTask.Result)
        Write-TextFile -Path ([string]$Process.ZappaStderrPath) -Value ([string]$Process.ZappaStderrTask.Result)
    } catch {
        Write-TextFile -Path ([string]$Process.ZappaStderrPath) -Value $_.Exception.ToString()
    }
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
$appWorkDir = Join-Path $workDir "app"
$evidenceDir = Join-Path $runDir "evidence"
$denoDir = Join-Path $runDir "deno-dir"
foreach ($dir in @($appWorkDir, $evidenceDir, $denoDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-deno.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$serverPath = Join-Path $candidateDirPath "app\server.ts"
$expectedBodyPath = Join-Path $candidateDirPath "expectations\root-body.txt"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\098-denoland-deno\selected-contract.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\098-denoland-deno\files\README.md"
$stagedServerPath = Join-Path $appWorkDir "server.ts"
$stdoutPath = Join-Path $evidenceDir "deno.stdout.txt"
$stderrPath = Join-Path $evidenceDir "deno.stderr.txt"
$versionStdoutPath = Join-Path $evidenceDir "deno-version.stdout.txt"
$versionStderrPath = Join-Path $evidenceDir "deno-version.stderr.txt"
$transcriptPath = Join-Path $evidenceDir "deno-lifecycle.transcript.txt"
$responsePath = Join-Path $evidenceDir "root-response.txt"

foreach ($requiredPath in @($manifestPath, $runtimePlanPath, $serverPath, $expectedBodyPath, $selectedContractPath, $selectedReadmePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Deno lifecycle input not found: $requiredPath"
    }
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
if ([string]$manifest.source_repository -ne "denoland/deno" -or [string]$runtimePlan.repository -ne "denoland/deno") {
    throw "This lifecycle runner only owns denoland/deno."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected Deno candidate must be blocked before lifecycle validation."
}
if ([string]$runtimePlan.command -ne "deno run --allow-net server.ts") {
    throw "Deno runtime plan command mismatch: $runtimePlanPath"
}

$managedPlan = $runtimePlan.managed_toolchain
if ([string]$managedPlan.release_tag -ne $DenoReleaseTag -or [string]$managedPlan.download_url -ne $DenoDownloadUrl -or [string]$managedPlan.archive_sha256 -ne $DenoArchiveSha256) {
    throw "Deno runtime plan managed toolchain metadata does not match lifecycle runner parameters."
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @("Deno.serve((_req: Request) => {", 'return new Response("Hello, world!");', "deno run --allow-net server.ts", "http://localhost:8000")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected Deno README evidence missing marker '$marker': $selectedReadmePath"
    }
}
$serverText = Get-Content -LiteralPath $serverPath -Raw
foreach ($marker in @("Deno.serve((_req: Request) => {", 'return new Response("Hello, world!");')) {
    if (-not $serverText.Contains($marker)) {
        throw "Generated Deno server missing README marker '$marker': $serverPath"
    }
}
if ((Get-Content -LiteralPath $expectedBodyPath -Raw) -ne "Hello, world!") {
    throw "Deno expected body must be exactly Hello, world!: $expectedBodyPath"
}

$port = 8000
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $blocked = New-BlockedResult -Reason "port_8000_already_in_use" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Deno lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$toolchain = $null
try {
    $toolchain = Get-ManagedDenoToolchain -ToolchainRoot $ManagedToolchainRoot -ReleaseTag $DenoReleaseTag -DownloadUrl $DenoDownloadUrl -ExpectedSha256 $DenoArchiveSha256 -RunDir $runDir
} catch {
    Write-TextFile -Path $transcriptPath -Value $_.Exception.ToString()
    $blocked = New-BlockedResult -Reason "managed_deno_toolchain_unavailable" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Deno lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$versionStart = [System.Diagnostics.ProcessStartInfo]::new()
$versionStart.FileName = $toolchain.DenoPath
$versionStart.Arguments = "--version"
$versionStart.UseShellExecute = $false
$versionStart.CreateNoWindow = $true
$versionStart.RedirectStandardOutput = $true
$versionStart.RedirectStandardError = $true
$versionProcess = [System.Diagnostics.Process]::new()
$versionProcess.StartInfo = $versionStart
[void]$versionProcess.Start()
$versionStdoutTask = $versionProcess.StandardOutput.ReadToEndAsync()
$versionStderrTask = $versionProcess.StandardError.ReadToEndAsync()
$versionProcess.WaitForExit(30000) | Out-Null
$denoVersionOutput = [string]$versionStdoutTask.Result
Write-TextFile -Path $versionStdoutPath -Value $denoVersionOutput
Write-TextFile -Path $versionStderrPath -Value ([string]$versionStderrTask.Result)
if ($versionProcess.ExitCode -ne 0 -or -not $denoVersionOutput.StartsWith("deno 2.8.2", [System.StringComparison]::Ordinal)) {
    throw "Managed Deno version check failed. Expected deno 2.8.2, got: $denoVersionOutput"
}
$denoVersionLine = ($denoVersionOutput -split "\r?\n" | Select-Object -First 1)

Copy-Item -LiteralPath $serverPath -Destination $stagedServerPath -Force
$candidateServerSha256 = Get-Sha256Hex -Path $serverPath
$stagedServerSha256 = Get-Sha256Hex -Path $stagedServerPath
if ($candidateServerSha256 -ne $stagedServerSha256) {
    throw "Staged server.ts hash mismatch."
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
    $process = Start-ProcessWithEnvironment -FilePath $toolchain.DenoPath -Arguments @("run", "--allow-net", "server.ts") -WorkingDirectory $appWorkDir -StdoutPath $stdoutPath -StderrPath $stderrPath -Environment @{ DENO_DIR = $denoDir }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            $failureReason = "Deno process exited before readiness with code $($process.ExitCode)"
            break
        }

        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 2
            $responseStatus = [int]$response.StatusCode
            $responseBody = [string]$response.Content
            if ($responseStatus -eq 200 -and $responseBody -eq "Hello, world!") {
                $portOwnersDuringReady = @(Get-PortOwner -Port $port)
                $processTreeIdsDuringReady = @(Get-ProcessTreeIds -RootProcessId ([int]$process.Id))
                $foreignOwners = @($portOwnersDuringReady | Where-Object { $processTreeIdsDuringReady -notcontains [int]$_.OwningProcess })
                if ($portOwnersDuringReady.Count -eq 0) {
                    $failureReason = "readiness response succeeded but no tracked port owner was found"
                } elseif ($foreignOwners.Count -gt 0) {
                    $failureReason = "readiness response was served by a process outside the tracked process tree"
                } else {
                    $ready = $true
                    $readyStatus = "HTTP 200 from / with README-backed exact Hello, world! body"
                    Write-TextFile -Path $responsePath -Value $responseBody
                    break
                }
            } else {
                $failureReason = "readiness response did not match expected exact Hello, world! body"
            }
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $ready -and [string]::IsNullOrWhiteSpace($failureReason)) {
        $failureReason = "timed out waiting for /"
    }
} finally {
    if ($null -ne $process) {
        $cleanupProcessIds = @(Stop-ProcessTree -RootProcessId ([int]$process.Id))
        try {
            $process.WaitForExit(5000) | Out-Null
        } catch {
            # ignored
        }
        Save-ProcessOutput -Process $process
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
    $failureReason = "Deno responded but port 8000 remained in use after cleanup"
}

$responseBodySha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { "" }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Validation: selected-top-repo-candidate-lifecycle-deno")
$lines.Add("Repository: denoland/deno")
$lines.Add("DownloadUrl: $DenoDownloadUrl")
$lines.Add("DenoReleaseTag: $DenoReleaseTag")
$lines.Add("DenoArchivePath: $($toolchain.ArchivePath)")
$lines.Add("DenoArchiveSha256: $($toolchain.ArchiveSha256)")
$lines.Add("DenoDownloaded: $($toolchain.Downloaded)")
$lines.Add("DenoPath: $($toolchain.DenoPath)")
$lines.Add("DenoVersion: $denoVersionLine")
$lines.Add("DenoDir: $denoDir")
$lines.Add("Command: deno run --allow-net server.ts")
$lines.Add("WorkingDirectory: $appWorkDir")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("TimeoutSeconds: $TimeoutSeconds")
$lines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$lines.Add("CandidateServerSha256: $candidateServerSha256")
$lines.Add("StagedServerSha256: $stagedServerSha256")
$lines.Add("Ready: $ready")
$lines.Add("ReadyStatus: $readyStatus")
$lines.Add("ResponseStatus: $responseStatus")
$lines.Add("ResponseBodySha256: $responseBodySha256")
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
$lines.Add("==== deno --version stdout ====")
$lines.Add($denoVersionOutput)
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
    repository = "denoland/deno"
    validation_kind = "selected_candidate_process_lifecycle"
    command = "deno run --allow-net server.ts"
    managed_toolchain_release_tag = $DenoReleaseTag
    managed_toolchain_download_url = $DenoDownloadUrl
    managed_toolchain_archive = $toolchain.ArchivePath
    managed_toolchain_archive_sha256 = $toolchain.ArchiveSha256
    managed_toolchain_path = $toolchain.InstallDir
    deno_path = $toolchain.DenoPath
    deno_version = $denoVersionLine
    deno_dir = $denoDir
    working_directory = $appWorkDir
    candidate_server_sha256 = $candidateServerSha256
    staged_server_sha256 = $stagedServerSha256
    selected_readme_evidence = $selectedReadmePath
    transcript = $transcriptPath
    stdout = $stdoutPath
    stderr = $stderrPath
    deno_version_stdout = $versionStdoutPath
    deno_version_stderr = $versionStderrPath
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_body_sha256 = $responseBodySha256
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
        command = "managed deno $DenoReleaseTag ; deno run --allow-net server.ts ; GET http://127.0.0.1:8000/ ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @($cleanupProcessIds)
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -in @("managed-deno-toolchain", "deno-process-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-deno.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -notin @("deno-toolchain-not-proven", "deno-process-lifecycle-not-proven")) {
            $remainingBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingBlockers)
    $manifest.blocked_reason = "Selected public contracts support a concrete Deno README server candidate, the managed Deno toolchain/process lifecycle and cleanup have passed, and a docs-derived exact text-body assertion hook is present, but executable promotion is blocked until hook schema/template/build/live, QaaS live, airgapped, and strong-review evidence pass."
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan.managed_toolchain.status = "passed"
    $runtimePlan.managed_toolchain | Add-Member -NotePropertyName "evidence" -NotePropertyValue @($summaryPath, $transcriptPath, $versionStdoutPath) -Force
    $runtimePlan.cleanup.status = "passed"
    $runtimePlan.cleanup | Add-Member -NotePropertyName "evidence" -NotePropertyValue @($summaryPath, $transcriptPath) -Force
    $runtimePlan | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    $runtimeBlockers = @()
    foreach ($blocker in @($runtimePlan.blockers)) {
        if ($blocker -notin @("prove_managed_deno_toolchain_without_using_ambient_path", "prove_process_lifecycle_and_cleanup_without assuming private source")) {
            $runtimeBlockers += $blocker
        }
    }
    $runtimePlan.blockers = @($runtimeBlockers)
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan
}

Write-Output "Deno lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -ne "passed") {
    exit 1
}
