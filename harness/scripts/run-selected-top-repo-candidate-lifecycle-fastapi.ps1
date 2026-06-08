param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\114-fastapi-fastapi",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates",
    [int]$TimeoutSeconds = 90,
    [int]$SetupTimeoutSeconds = 300,
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
            Where-Object {
                $_.LocalAddress -in @("127.0.0.1", "::1", "0.0.0.0", "::") -and
                [string]$_.State -eq "Listen"
            })
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

function Get-PythonModuleVersion {
    param(
        [string]$ModuleName,
        [string]$PythonPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($PythonPath)) {
        $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
        if ($null -ne $pythonCommand) {
            $PythonPath = $pythonCommand.Source
        }
    }
    if ([string]::IsNullOrWhiteSpace($PythonPath) -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        return [pscustomobject]@{ Available = $false; Version = ""; Error = "python_not_available" }
    }

    try {
        $snippet = "import $ModuleName; print(getattr($ModuleName, '__version__', 'unknown'))"
        $global:LASTEXITCODE = 0
        $outputLines = & $PythonPath -c $snippet 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        $output = ($outputLines | Out-String).Trim()
        if ($exitCode -ne 0) {
            return [pscustomobject]@{ Available = $false; Version = ""; Error = $output }
        }

        return [pscustomobject]@{ Available = $true; Version = $output; Error = "" }
    } catch {
        return [pscustomobject]@{ Available = $false; Version = ""; Error = $_.Exception.Message }
    }
}

function Invoke-LoggedProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSeconds
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -PassThru -WindowStyle Hidden -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        Stop-ProcessTree -RootProcessId ([int]$process.Id) | Out-Null
        return [pscustomobject]@{ ExitCode = -1; TimedOut = $true }
    }

    return [pscustomobject]@{ ExitCode = [int]$process.ExitCode; TimedOut = $false }
}

function New-BlockedResult {
    param(
        [string]$Reason,
        [string]$RunDir,
        [string]$SummaryPath,
        [string]$TranscriptPath,
        [string]$FastApiCliPath,
        [object]$FastApiInfo,
        [object]$UvicornInfo,
        [string]$ManagedVenvPath = "",
        [string]$InstallCommand = ""
    )

    $record = [ordered]@{
        schema_version = 1
        status = "blocked"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "fastapi/fastapi"
        reason = $Reason
        fastapi_cli_path = $FastApiCliPath
        fastapi_module_available = if ($null -ne $FastApiInfo) { [bool]$FastApiInfo.Available } else { $false }
        fastapi_module_version = if ($null -ne $FastApiInfo) { [string]$FastApiInfo.Version } else { "" }
        uvicorn_module_available = if ($null -ne $UvicornInfo) { [bool]$UvicornInfo.Available } else { $false }
        uvicorn_module_version = if ($null -ne $UvicornInfo) { [string]$UvicornInfo.Version } else { "" }
        managed_venv_path = $ManagedVenvPath
        install_command = $InstallCommand
        run_dir = $RunDir
        transcript = if (Test-Path -LiteralPath $TranscriptPath -PathType Leaf) { $TranscriptPath } else { $null }
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
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-fastapi.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$candidateAppPath = Join-Path $candidateDirPath "app\main.py"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\114-fastapi-fastapi\selected-contract.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\114-fastapi-fastapi\files\README.md"
$stdoutPath = Join-Path $evidenceDir "fastapi.stdout.txt"
$stderrPath = Join-Path $evidenceDir "fastapi.stderr.txt"
$venvStdoutPath = Join-Path $evidenceDir "python-venv.stdout.txt"
$venvStderrPath = Join-Path $evidenceDir "python-venv.stderr.txt"
$pipStdoutPath = Join-Path $evidenceDir "pip-install-fastapi-standard.stdout.txt"
$pipStderrPath = Join-Path $evidenceDir "pip-install-fastapi-standard.stderr.txt"
$transcriptPath = Join-Path $evidenceDir "fastapi-lifecycle.transcript.txt"
$responsePath = Join-Path $evidenceDir "items-5-response.json"

foreach ($requiredPath in @($manifestPath, $runtimePlanPath, $candidateAppPath, $selectedContractPath, $selectedReadmePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required FastAPI lifecycle input not found: $requiredPath"
    }
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
$selectedContract = Read-JsonFile -Path $selectedContractPath
if ([string]$manifest.source_repository -ne "fastapi/fastapi" -or [string]$runtimePlan.repository -ne "fastapi/fastapi") {
    throw "This lifecycle runner only owns fastapi/fastapi."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected FastAPI candidate must be blocked before lifecycle validation."
}

$supports = @($selectedContract.candidate_promotion_contracts | ForEach-Object { [string]$_.supports })
foreach ($requiredSupport in @("runtime-contract", "http-contract", "candidate-executable-command")) {
    if ($supports -notcontains $requiredSupport) {
        throw "Selected FastAPI contract missing support '$requiredSupport': $selectedContractPath"
    }
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @('pip install "fastapi[standard]"', "fastapi-cli[standard]", "fastapi dev", "http://127.0.0.1:8000", "/items/5?q=somequery", '"item_id": 5', '"q": "somequery"', "from fastapi import FastAPI")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected FastAPI README evidence missing marker '$marker': $selectedReadmePath"
    }
}

$appText = Get-Content -LiteralPath $candidateAppPath -Raw
foreach ($marker in @("from fastapi import FastAPI", "app = FastAPI()", '@app.get("/items/{item_id}")', "return {`"item_id`": item_id, `"q`": q}")) {
    if (-not $appText.Contains($marker)) {
        throw "Generated FastAPI app missing README marker '$marker': $candidateAppPath"
    }
}

$stagedAppPath = Join-Path $workDir "main.py"
Copy-Item -LiteralPath $candidateAppPath -Destination $stagedAppPath -Force
$candidateAppSha256 = Get-Sha256Hex -Path $candidateAppPath
$stagedAppSha256 = Get-Sha256Hex -Path $stagedAppPath
if ($candidateAppSha256 -ne $stagedAppSha256) {
    throw "Staged main.py hash mismatch."
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$venvDir = Join-Path $runDir "venv"
$venvPythonPath = Join-Path $venvDir "Scripts\python.exe"
$fastApiCliPath = Join-Path $venvDir "Scripts\fastapi.exe"
$installCommand = 'python -m pip install "fastapi[standard]"'
$fastApiInfo = $null
$uvicornInfo = $null
$started = Get-Date
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Validation: selected-top-repo-candidate-lifecycle-fastapi")
$lines.Add("Repository: fastapi/fastapi")
$lines.Add("Command: fastapi dev")
$lines.Add("WorkingDirectory: $workDir")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("TimeoutSeconds: $TimeoutSeconds")
$lines.Add("SetupTimeoutSeconds: $SetupTimeoutSeconds")
$lines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$lines.Add("CandidateAppSha256: $candidateAppSha256")
$lines.Add("StagedAppSha256: $stagedAppSha256")
$lines.Add("ManagedVenvPath: $venvDir")
$lines.Add("InstallCommand: $installCommand")

if ($null -eq $pythonCommand) {
    $lines.Add("FailureReason: python_not_available")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "python_not_available" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -FastApiCliPath "" -FastApiInfo $fastApiInfo -UvicornInfo $uvicornInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "FastAPI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$venvResult = Invoke-LoggedProcess -FilePath $pythonCommand.Source -ArgumentList @("-m", "venv", $venvDir) -WorkingDirectory $runDir -StdoutPath $venvStdoutPath -StderrPath $venvStderrPath -TimeoutSeconds $SetupTimeoutSeconds
$lines.Add("PythonPath: $($pythonCommand.Source)")
$lines.Add("VenvCreateExitCode: $($venvResult.ExitCode)")
$lines.Add("VenvCreateTimedOut: $($venvResult.TimedOut)")
if ($venvResult.TimedOut -or [int]$venvResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $venvPythonPath -PathType Leaf)) {
    $lines.Add("FailureReason: fastapi_managed_venv_create_failed")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "fastapi_managed_venv_create_failed" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -FastApiCliPath "" -FastApiInfo $fastApiInfo -UvicornInfo $uvicornInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "FastAPI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$pipResult = Invoke-LoggedProcess -FilePath $venvPythonPath -ArgumentList @("-m", "pip", "install", "--disable-pip-version-check", "fastapi[standard]") -WorkingDirectory $runDir -StdoutPath $pipStdoutPath -StderrPath $pipStderrPath -TimeoutSeconds $SetupTimeoutSeconds
$lines.Add("PipInstallExitCode: $($pipResult.ExitCode)")
$lines.Add("PipInstallTimedOut: $($pipResult.TimedOut)")
$fastApiInfo = Get-PythonModuleVersion -ModuleName "fastapi" -PythonPath $venvPythonPath
$uvicornInfo = Get-PythonModuleVersion -ModuleName "uvicorn" -PythonPath $venvPythonPath
$lines.Add("FastApiModuleAvailable: $($fastApiInfo.Available)")
$lines.Add("FastApiModuleVersion: $($fastApiInfo.Version)")
$lines.Add("UvicornModuleAvailable: $($uvicornInfo.Available)")
$lines.Add("UvicornModuleVersion: $($uvicornInfo.Version)")
$lines.Add("FastApiCliPath: $fastApiCliPath")
if ($pipResult.TimedOut -or [int]$pipResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $fastApiCliPath -PathType Leaf)) {
    $lines.Add("FailureReason: fastapi_standard_install_failed")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "fastapi_standard_install_failed" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -FastApiCliPath $fastApiCliPath -FastApiInfo $fastApiInfo -UvicornInfo $uvicornInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "FastAPI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 8000
$fastApiProcessEnvironment = [ordered]@{
    PYTHONUTF8 = "1"
    PYTHONIOENCODING = "utf-8"
    PYTHONUNBUFFERED = "1"
    NO_COLOR = "1"
    TERM = "dumb"
}
$lines.Add("FastApiProcessEnvironment: $(($fastApiProcessEnvironment.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';')")
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $lines.Add("FailureReason: port_8000_already_in_use")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "port_8000_already_in_use" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -FastApiCliPath $fastApiCliPath -FastApiInfo $fastApiInfo -UvicornInfo $uvicornInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "FastAPI lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$process = $null
$ready = $false
$readyStatus = ""
$responseStatus = $null
$responseBody = ""
$cleanupProcessIds = @()
$portOwnersAfterCleanup = @()
$remainingTrackedProcessIds = @()
$portOwnersDuringReady = @()
$processTreeIdsDuringReady = @()
$exitCode = 1
$validationStatus = "failed"
$failureReason = ""
$previousEnvironment = $null

try {
    $previousEnvironment = @{}
    foreach ($entry in $fastApiProcessEnvironment.GetEnumerator()) {
        $previousEnvironment[$entry.Key] = [System.Environment]::GetEnvironmentVariable($entry.Key, "Process")
        [System.Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, "Process")
    }
    $process = Start-Process -FilePath $fastApiCliPath -ArgumentList @("dev") -WorkingDirectory $workDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    foreach ($entry in $fastApiProcessEnvironment.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($entry.Key, $previousEnvironment[$entry.Key], "Process")
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            $failureReason = "FastAPI process exited before readiness with code $($process.ExitCode)"
            break
        }

        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/items/5?q=somequery" -UseBasicParsing -TimeoutSec 2
            $responseStatus = [int]$response.StatusCode
            $responseBody = [string]$response.Content
            $json = $responseBody | ConvertFrom-Json
            $propertyNames = @($json.PSObject.Properties.Name)
            if ($responseStatus -eq 200 -and $propertyNames.Count -eq 2 -and ($propertyNames -contains "item_id") -and ($propertyNames -contains "q") -and [int]$json.item_id -eq 5 -and [string]$json.q -eq "somequery") {
                $portOwnersDuringReady = @(Get-PortOwner -Port $port)
                $processTreeIdsDuringReady = @(Get-ProcessTreeIds -RootProcessId ([int]$process.Id))
                $foreignOwners = @($portOwnersDuringReady | Where-Object { $processTreeIdsDuringReady -notcontains [int]$_.OwningProcess })
                if ($portOwnersDuringReady.Count -eq 0) {
                    $failureReason = "readiness response succeeded but no tracked port owner was found"
                } elseif ($foreignOwners.Count -gt 0) {
                    $failureReason = "readiness response was served by a process outside the tracked process tree"
                } else {
                    $ready = $true
                    $readyStatus = "HTTP 200 from /items/5?q=somequery with exact README-backed JSON body"
                    Write-TextFile -Path $responsePath -Value $responseBody
                    break
                }
            }

            $failureReason = "readiness response did not match expected status/body"
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not $ready -and [string]::IsNullOrWhiteSpace($failureReason)) {
        $failureReason = "timed out waiting for /items/5?q=somequery"
    }
} finally {
    if ($null -ne $previousEnvironment) {
        foreach ($key in @($previousEnvironment.Keys)) {
            [System.Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key], "Process")
        }
    }
    if ($null -ne $process) {
        $cleanupProcessIds = @(Stop-ProcessTree -RootProcessId ([int]$process.Id))
    }
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $remaining = @()
        foreach ($processId in @($cleanupProcessIds)) {
            if ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
                $remaining += [int]$processId
            }
        }
        $owners = @(Get-PortOwner -Port $port)
        if ($remaining.Count -eq 0 -and $owners.Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 500
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
    $failureReason = "FastAPI responded but port 8000 remained in use after cleanup"
}

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
    repository = "fastapi/fastapi"
    validation_kind = "selected_candidate_process_lifecycle"
    command = "fastapi dev"
    fastapi_cli_path = $fastApiCliPath
    fastapi_module_version = $fastApiInfo.Version
    uvicorn_module_version = $uvicornInfo.Version
    managed_venv_path = $venvDir
    install_command = $installCommand
    venv_python_path = $venvPythonPath
    venv_create_stdout = $venvStdoutPath
    venv_create_stderr = $venvStderrPath
    pip_install_stdout = $pipStdoutPath
    pip_install_stderr = $pipStderrPath
    working_directory = $workDir
    candidate_app_sha256 = $candidateAppSha256
    staged_app_sha256 = $stagedAppSha256
    selected_readme_evidence = $selectedReadmePath
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
        command = "fastapi dev ; GET http://127.0.0.1:8000/items/5?q=somequery ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @($cleanupProcessIds)
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -in @("python-fastapi-process-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-fastapi.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -ne "fastapi-process-lifecycle-not-proven") {
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

Write-Output "FastAPI lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -ne "passed") {
    exit 1
}
