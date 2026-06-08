param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\227-pallets-flask",
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

function Get-PythonPackageVersion {
    param(
        [string]$PackageName,
        [string]$PythonPath
    )

    if ([string]::IsNullOrWhiteSpace($PythonPath) -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        return [pscustomobject]@{ Available = $false; Version = ""; Error = "python_not_available" }
    }

    try {
        $snippet = "import importlib.metadata; print(importlib.metadata.version('$PackageName'))"
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
        [string]$PythonPath,
        [string]$FlaskCliPath,
        [object]$FlaskInfo,
        [string]$ManagedVenvPath = "",
        [string]$InstallCommand = ""
    )

    $record = [ordered]@{
        schema_version = 1
        status = "blocked"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "pallets/flask"
        reason = $Reason
        python_path = $PythonPath
        flask_module_available = if ($null -ne $FlaskInfo) { [bool]$FlaskInfo.Available } else { $false }
        flask_version = if ($null -ne $FlaskInfo) { [string]$FlaskInfo.Version } else { "" }
        flask_import_error = if ($null -ne $FlaskInfo) { [string]$FlaskInfo.Error } else { "" }
        flask_cli_path = $FlaskCliPath
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
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-flask.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$candidateAppPath = Join-Path $candidateDirPath "app\app.py"
$expectedBodyPath = Join-Path $candidateDirPath "expectations\root-body.txt"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\227-pallets-flask\selected-contract.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\227-pallets-flask\files\README.md"
$selectedPyprojectPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\227-pallets-flask\files\pyproject.toml"
$stdoutPath = Join-Path $evidenceDir "flask.stdout.txt"
$stderrPath = Join-Path $evidenceDir "flask.stderr.txt"
$venvStdoutPath = Join-Path $evidenceDir "python-venv.stdout.txt"
$venvStderrPath = Join-Path $evidenceDir "python-venv.stderr.txt"
$pipStdoutPath = Join-Path $evidenceDir "pip-install-flask.stdout.txt"
$pipStderrPath = Join-Path $evidenceDir "pip-install-flask.stderr.txt"
$transcriptPath = Join-Path $evidenceDir "flask-lifecycle.transcript.txt"
$responsePath = Join-Path $evidenceDir "root-response.txt"

foreach ($requiredPath in @($manifestPath, $runtimePlanPath, $candidateAppPath, $expectedBodyPath, $selectedContractPath, $selectedReadmePath, $selectedPyprojectPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Flask lifecycle input not found: $requiredPath"
    }
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
if ([string]$manifest.source_repository -ne "pallets/flask" -or [string]$runtimePlan.repository -ne "pallets/flask") {
    throw "This lifecycle runner only owns pallets/flask."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected Flask candidate must be blocked before lifecycle validation."
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @('# save this as app.py', 'from flask import Flask', '@app.route("/")', 'return "Hello, World!"', '$ flask run', 'http://127.0.0.1:5000/')) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected Flask README evidence missing marker '$marker': $selectedReadmePath"
    }
}

$pyprojectText = Get-Content -LiteralPath $selectedPyprojectPath -Raw
foreach ($marker in @('name = "Flask"', '[project.scripts]', 'flask =')) {
    if (-not $pyprojectText.Contains($marker)) {
        throw "Selected Flask pyproject evidence missing marker '$marker': $selectedPyprojectPath"
    }
}

$appText = Get-Content -LiteralPath $candidateAppPath -Raw
foreach ($marker in @('from flask import Flask', 'app = Flask(__name__)', '@app.route("/")', 'return "Hello, World!"')) {
    if (-not $appText.Contains($marker)) {
        throw "Generated Flask app missing README marker '$marker': $candidateAppPath"
    }
}
$expectedBody = Get-Content -LiteralPath $expectedBodyPath -Raw
if ($expectedBody -ne "Hello, World!") {
    throw "Generated Flask expected body must exactly match public README evidence: $expectedBodyPath"
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$venvDir = Join-Path $runDir "venv"
$venvPythonPath = Join-Path $venvDir "Scripts\python.exe"
$flaskCliPath = Join-Path $venvDir "Scripts\flask.exe"
$installCommand = "python -m pip install Flask"
$flaskInfo = $null
$setupStarted = Get-Date
$setupLines = New-Object System.Collections.Generic.List[string]
$setupLines.Add("Validation: selected-top-repo-candidate-lifecycle-flask")
$setupLines.Add("Repository: pallets/flask")
$setupLines.Add("Command: flask run --no-reload --host 127.0.0.1 --port 5000")
$setupLines.Add("SetupStarted: $($setupStarted.ToString('o'))")
$setupLines.Add("SetupTimeoutSeconds: $SetupTimeoutSeconds")
$setupLines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$setupLines.Add("SelectedPyprojectEvidence: $selectedPyprojectPath")
$setupLines.Add("ManagedVenvPath: $venvDir")
$setupLines.Add("InstallCommand: $installCommand")

if ($null -eq $pythonCommand) {
    $setupLines.Add("FailureReason: python_not_available")
    Write-TextFile -Path $transcriptPath -Value ($setupLines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "python_not_available" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -PythonPath "" -FlaskCliPath "" -FlaskInfo $flaskInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "Flask lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$venvResult = Invoke-LoggedProcess -FilePath $pythonCommand.Source -ArgumentList @("-m", "venv", $venvDir) -WorkingDirectory $runDir -StdoutPath $venvStdoutPath -StderrPath $venvStderrPath -TimeoutSeconds $SetupTimeoutSeconds
$setupLines.Add("PythonPath: $($pythonCommand.Source)")
$setupLines.Add("VenvCreateExitCode: $($venvResult.ExitCode)")
$setupLines.Add("VenvCreateTimedOut: $($venvResult.TimedOut)")
if ($venvResult.TimedOut -or [int]$venvResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $venvPythonPath -PathType Leaf)) {
    $setupLines.Add("FailureReason: flask_managed_venv_create_failed")
    Write-TextFile -Path $transcriptPath -Value ($setupLines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "flask_managed_venv_create_failed" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -PythonPath $pythonCommand.Source -FlaskCliPath "" -FlaskInfo $flaskInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "Flask lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$pipResult = Invoke-LoggedProcess -FilePath $venvPythonPath -ArgumentList @("-m", "pip", "install", "--disable-pip-version-check", "Flask") -WorkingDirectory $runDir -StdoutPath $pipStdoutPath -StderrPath $pipStderrPath -TimeoutSeconds $SetupTimeoutSeconds
$setupLines.Add("PipInstallExitCode: $($pipResult.ExitCode)")
$setupLines.Add("PipInstallTimedOut: $($pipResult.TimedOut)")
$flaskInfo = Get-PythonPackageVersion -PackageName "Flask" -PythonPath $venvPythonPath
$setupLines.Add("FlaskModuleAvailable: $($flaskInfo.Available)")
$setupLines.Add("FlaskVersion: $($flaskInfo.Version)")
$setupLines.Add("FlaskCliPath: $flaskCliPath")
if ($pipResult.TimedOut -or [int]$pipResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $flaskCliPath -PathType Leaf) -or $flaskInfo.Available -ne $true) {
    $setupLines.Add("FailureReason: flask_install_failed")
    Write-TextFile -Path $transcriptPath -Value ($setupLines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "flask_install_failed" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -PythonPath $venvPythonPath -FlaskCliPath $flaskCliPath -FlaskInfo $flaskInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "Flask lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 5000
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $setupLines.Add("FailureReason: port_5000_already_in_use")
    Write-TextFile -Path $transcriptPath -Value ($setupLines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "port_5000_already_in_use" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -PythonPath $venvPythonPath -FlaskCliPath $flaskCliPath -FlaskInfo $flaskInfo -ManagedVenvPath $venvDir -InstallCommand $installCommand
    Write-Output "Flask lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$stagedAppPath = Join-Path $workDir "app.py"
Copy-Item -LiteralPath $candidateAppPath -Destination $stagedAppPath -Force
$candidateAppSha256 = Get-Sha256Hex -Path $candidateAppPath
$stagedAppSha256 = Get-Sha256Hex -Path $stagedAppPath
if ($candidateAppSha256 -ne $stagedAppSha256) {
    throw "Staged app.py hash mismatch."
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
$oldFlaskApp = $env:FLASK_APP
$oldFlaskDebug = $env:FLASK_DEBUG
$oldPythonUnbuffered = $env:PYTHONUNBUFFERED

try {
    $env:FLASK_APP = "app"
    $env:FLASK_DEBUG = "0"
    $env:PYTHONUNBUFFERED = "1"
    $arguments = @("run", "--no-reload", "--host", "127.0.0.1", "--port", "$port")
    $process = Start-Process -FilePath $flaskCliPath -ArgumentList $arguments -WorkingDirectory $workDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            $failureReason = "Flask process exited before readiness with code $($process.ExitCode)"
            break
        }

        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 2
            $responseStatus = [int]$response.StatusCode
            $responseBody = [string]$response.Content
            if ($responseStatus -eq 200 -and $responseBody -eq "Hello, World!") {
                $portOwnersDuringReady = @(Get-PortOwner -Port $port)
                $processTreeIdsDuringReady = @(Get-ProcessTreeIds -RootProcessId ([int]$process.Id))
                $foreignOwners = @($portOwnersDuringReady | Where-Object { $processTreeIdsDuringReady -notcontains [int]$_.OwningProcess })
                if ($portOwnersDuringReady.Count -eq 0) {
                    $failureReason = "readiness response succeeded but no tracked port owner was found"
                } elseif ($foreignOwners.Count -gt 0) {
                    $failureReason = "readiness response was served by a process outside the tracked process tree"
                } else {
                    $ready = $true
                    $readyStatus = "HTTP 200 from / with exact README-backed body"
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
        $failureReason = "timed out waiting for /"
    }
} finally {
    $env:FLASK_APP = $oldFlaskApp
    $env:FLASK_DEBUG = $oldFlaskDebug
    $env:PYTHONUNBUFFERED = $oldPythonUnbuffered
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
    $failureReason = "Flask responded but port 5000 remained in use after cleanup"
}

$responseSha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { $null }
$lines = New-Object System.Collections.Generic.List[string]
foreach ($line in $setupLines) {
    $lines.Add($line)
}
$lines.Add("WorkingDirectory: $workDir")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("TimeoutSeconds: $TimeoutSeconds")
$lines.Add("PythonPath: $venvPythonPath")
$lines.Add("FlaskVersion: $($flaskInfo.Version)")
$lines.Add("FlaskCliPath: $flaskCliPath")
$lines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$lines.Add("SelectedPyprojectEvidence: $selectedPyprojectPath")
$lines.Add("CandidateAppSha256: $candidateAppSha256")
$lines.Add("StagedAppSha256: $stagedAppSha256")
$lines.Add("Ready: $ready")
$lines.Add("ReadyStatus: $readyStatus")
$lines.Add("ResponseStatus: $responseStatus")
$lines.Add("ResponseBodySha256: $responseSha256")
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
    repository = "pallets/flask"
    validation_kind = "selected_candidate_process_lifecycle"
    command = "flask run"
    command_arguments = @("run", "--no-reload", "--host", "127.0.0.1", "--port", "$port")
    python_path = $venvPythonPath
    flask_version = $flaskInfo.Version
    flask_cli_path = $flaskCliPath
    managed_venv_path = $venvDir
    install_command = $installCommand
    venv_create_stdout = $venvStdoutPath
    venv_create_stderr = $venvStderrPath
    pip_install_stdout = $pipStdoutPath
    pip_install_stderr = $pipStderrPath
    working_directory = $workDir
    candidate_app_sha256 = $candidateAppSha256
    staged_app_sha256 = $stagedAppSha256
    selected_readme_evidence = $selectedReadmePath
    selected_pyproject_evidence = $selectedPyprojectPath
    transcript = $transcriptPath
    stdout = $stdoutPath
    stderr = $stderrPath
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_body_sha256 = $responseSha256
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
        command = "flask run ; GET http://127.0.0.1:5000/ ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @($cleanupProcessIds)
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -in @("python-flask-process-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-flask.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -ne "flask-process-lifecycle-not-proven") {
            $remainingBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingBlockers)
    $manifest.blocked_reason = "Selected public contracts support a concrete Flask candidate packet, the managed Flask process lifecycle and cleanup have passed, and a docs-derived exact text-body assertion hook is present, but executable promotion is blocked until hook schema/template/build/live, QaaS live, airgapped, and strong-review evidence pass."
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

Write-Output "Flask lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -ne "passed") {
    exit 1
}
