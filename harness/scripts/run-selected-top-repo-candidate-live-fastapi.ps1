param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\114-fastapi-fastapi",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates",
    [string]$LocalPackageSource = "D:\QaaS\_localfeed\packages",
    [int]$TimeoutSeconds = 120,
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

function Get-PortListener {
    param([int]$Port)
    return @(Get-PortOwner -Port $Port | Where-Object { [string]$_.State -eq "Listen" })
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
            # Cleanup is best effort here; final checks decide pass/fail.
        }
    }

    Start-Sleep -Milliseconds 500
    return @($ids)
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

function Invoke-DotnetCommand {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string[]]$ArgumentList,
        [string]$EvidenceDir
    )

    $transcript = Join-Path $EvidenceDir "$Name.transcript.txt"
    $command = "dotnet $($ArgumentList -join ' ')"
    $started = Get-Date
    $global:LASTEXITCODE = 0

    Push-Location $WorkingDirectory
    try {
        try {
            $output = & dotnet @ArgumentList 2>&1
            $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        } catch {
            $output = @($_.Exception.ToString())
            $exitCode = 1
        }
    } finally {
        Pop-Location
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Command: $command")
    $lines.Add("WorkingDirectory: $WorkingDirectory")
    $lines.Add("Started: $($started.ToString('o'))")
    $lines.Add("ExitCode: $exitCode")
    $lines.Add("")
    foreach ($line in @($output)) {
        $lines.Add([string]$line)
    }
    Write-TextFile -Path $transcript -Value ($lines -join [Environment]::NewLine)

    [ordered]@{
        name = $Name
        status = if ($exitCode -eq 0) { "passed" } else { "failed" }
        exit_code = $exitCode
        command = $command
        working_directory = $WorkingDirectory
        transcript = $transcript
    }
}

function New-ValidationRecord {
    param(
        [string]$Status,
        [int]$ExitCode,
        [string]$Command,
        [string]$Transcript
    )

    [ordered]@{
        status = $Status
        exit_code = $ExitCode
        command = $Command
        transcript = $Transcript
    }
}

function New-BlockedRecord {
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
        repository = "fastapi/fastapi"
        reason = $Reason
        run_dir = $RunDir
        manifest_updated = $false
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $SummaryPath -Value $record
    return $record
}

function Get-PythonModuleVersion {
    param(
        [string]$ModuleName,
        [string]$PythonPath
    )

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

$candidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates"
$candidateDirPath = Assert-DescendantPath -Path $CandidateDir -Root $candidateRoot -Description "CandidateDir"
if (-not (Test-Path -LiteralPath $candidateDirPath -PathType Container)) {
    throw "Candidate directory not found: $candidateDirPath"
}

$allowedOutRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates"
$outRootPath = Get-NormalizedPath -Path $OutRoot
if (-not [string]::Equals($outRootPath, (Get-NormalizedPath -Path $allowedOutRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutRoot must be the managed selected-candidate live root: $allowedOutRoot"
}

$runDir = Join-Path $outRootPath (Get-Date -Format "yyyyMMdd-HHmmss-fff")
$runnerRoot = Join-Path $runDir "runner"
$fastApiWorkDir = Join-Path $runDir "fastapi-work"
$evidenceDir = Join-Path $runDir "evidence"
foreach ($dir in @($runnerRoot, $fastApiWorkDir, $evidenceDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-live-fastapi.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$runnerYamlSource = Join-Path $candidateDirPath "test.qaas.yaml"
$schemasSource = Join-Path $candidateDirPath "schemas"
$schemaSource = Join-Path $schemasSource "item-response.schema.json"
$requestPayloadsSource = Join-Path $candidateDirPath "request-payloads"
$requestPayloadSource = Join-Path $requestPayloadsSource "get-items-5.bin"
$appSource = Join-Path $candidateDirPath "app\main.py"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\114-fastapi-fastapi\files\README.md"
$fastApiStdoutPath = Join-Path $evidenceDir "fastapi.stdout.txt"
$fastApiStderrPath = Join-Path $evidenceDir "fastapi.stderr.txt"
$venvStdoutPath = Join-Path $evidenceDir "python-venv.stdout.txt"
$venvStderrPath = Join-Path $evidenceDir "python-venv.stderr.txt"
$pipStdoutPath = Join-Path $evidenceDir "pip-install-fastapi-standard.stdout.txt"
$pipStderrPath = Join-Path $evidenceDir "pip-install-fastapi-standard.stderr.txt"
$responsePath = Join-Path $evidenceDir "items-5-response.json"
$combinedTranscriptPath = Join-Path $evidenceDir "selected-live-fastapi.transcript.txt"

foreach ($path in @($manifestPath, $runtimePlanPath, $runnerYamlSource, $schemaSource, $requestPayloadSource, $appSource, $selectedReadmePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required selected-candidate FastAPI live input missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $LocalPackageSource -PathType Container)) {
    throw "Local QaaS package source missing: $LocalPackageSource"
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
if ([string]$manifest.source_repository -ne "fastapi/fastapi" -or [string]$runtimePlan.repository -ne "fastapi/fastapi") {
    throw "This live runner only owns fastapi/fastapi."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected FastAPI candidate must be blocked before live validation."
}
$manifestHasLifecycleValidation = (
    ($manifest.PSObject.Properties.Name -contains "lifecycle_validation") -and
    $null -ne $manifest.lifecycle_validation -and
    [string]$manifest.lifecycle_validation.status -eq "passed"
)
if (-not $manifestHasLifecycleValidation) {
    $blocked = New-BlockedRecord -Reason "lifecycle_validation_must_pass_first" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "FastAPI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
$runtimePlanHasPassedCleanup = (
    ($runtimePlan.PSObject.Properties.Name -contains "cleanup") -and
    $null -ne $runtimePlan.cleanup -and
    [string]$runtimePlan.cleanup.status -eq "passed"
)
if (-not $runtimePlanHasPassedCleanup) {
    $blocked = New-BlockedRecord -Reason "cleanup_lifecycle_must_pass_first" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "FastAPI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @('pip install "fastapi[standard]"', "fastapi-cli[standard]", "fastapi dev", "http://127.0.0.1:8000", "/items/5?q=somequery", '"item_id": 5', '"q": "somequery"', "from fastapi import FastAPI")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected FastAPI README evidence missing marker '$marker': $selectedReadmePath"
    }
}

$schema = Read-JsonFile -Path $schemaSource
if (@($schema.required).Count -ne 2 -or @($schema.required) -notcontains "item_id" -or @($schema.required) -notcontains "q" -or $schema.additionalProperties -ne $false -or [int]$schema.properties.item_id.const -ne 5 -or [string]$schema.properties.q.const -ne "somequery") {
    throw "FastAPI response schema must match README-backed item_id/q contract: $schemaSource"
}
$payloadBytes = [System.IO.File]::ReadAllBytes($requestPayloadSource)
if ($payloadBytes.Length -ne 0) {
    throw "FastAPI GET payload must be empty: $requestPayloadSource"
}
$runnerYamlText = Get-Content -LiteralPath $runnerYamlSource -Raw
if ($runnerYamlText -notmatch "(?m)^\s*Route:\s*items/5\?q=somequery\s*$") {
    throw "FastAPI QaaS Route must omit leading slash and use exact route items/5?q=somequery: $runnerYamlSource"
}
if ($runnerYamlText -match "(?m)^\s*Route:\s*/items/5\?q=somequery\s*$") {
    throw "FastAPI QaaS Route would create a double-slash request: $runnerYamlSource"
}

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $pythonCommand) {
    $blocked = New-BlockedRecord -Reason "python_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "FastAPI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 8000
$preExistingPortOwners = @(Get-PortListener -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $blocked = New-BlockedRecord -Reason "port_8000_already_in_use" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "FastAPI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$venvDir = Join-Path $runDir "venv"
$venvPythonPath = Join-Path $venvDir "Scripts\python.exe"
$fastApiCliPath = Join-Path $venvDir "Scripts\fastapi.exe"
$installCommand = 'python -m pip install "fastapi[standard]"'
$venvResult = Invoke-LoggedProcess -FilePath $pythonCommand.Source -ArgumentList @("-m", "venv", $venvDir) -WorkingDirectory $runDir -StdoutPath $venvStdoutPath -StderrPath $venvStderrPath -TimeoutSeconds $SetupTimeoutSeconds
if ($venvResult.TimedOut -or [int]$venvResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $venvPythonPath -PathType Leaf)) {
    $blocked = New-BlockedRecord -Reason "fastapi_managed_venv_create_failed" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "FastAPI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
$pipResult = Invoke-LoggedProcess -FilePath $venvPythonPath -ArgumentList @("-m", "pip", "install", "--disable-pip-version-check", "fastapi[standard]") -WorkingDirectory $runDir -StdoutPath $pipStdoutPath -StderrPath $pipStderrPath -TimeoutSeconds $SetupTimeoutSeconds
$fastApiInfo = Get-PythonModuleVersion -ModuleName "fastapi" -PythonPath $venvPythonPath
$uvicornInfo = Get-PythonModuleVersion -ModuleName "uvicorn" -PythonPath $venvPythonPath
if ($pipResult.TimedOut -or [int]$pipResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $fastApiCliPath -PathType Leaf)) {
    $blocked = New-BlockedRecord -Reason "fastapi_standard_install_failed" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "FastAPI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$newRunner = Invoke-DotnetCommand -Name "dotnet-new-runner" -WorkingDirectory $runDir -ArgumentList @("new", "qaas-runner", "-n", "ZappaSelectedFastApi.Runner", "-o", $runnerRoot) -EvidenceDir $evidenceDir
$runnerProjectRoot = Join-Path $runnerRoot "ZappaSelectedFastApi.Runner"
$runnerProject = Join-Path $runnerProjectRoot "ZappaSelectedFastApi.Runner.csproj"
$runnerYamlStaged = Join-Path $runnerProjectRoot "test.qaas.yaml"
$schemasStaged = Join-Path $runnerProjectRoot "schemas"
$requestPayloadsStaged = Join-Path $runnerProjectRoot "request-payloads"
$appStaged = Join-Path $fastApiWorkDir "main.py"

$packageResults = @()
$buildResult = $null
$templateResult = $null
$liveResult = $null
$process = $null
$ready = $false
$readyStatus = ""
$responseStatus = $null
$responseBody = ""
$portOwnersDuringReady = @()
$processTreeIdsDuringReady = @()
$cleanupProcessIds = @()
$remainingTrackedProcessIds = @()
$portOwnersAfterCleanup = @()
$failureReason = ""

if ([int]$newRunner.exit_code -eq 0 -and (Test-Path -LiteralPath $runnerProject -PathType Leaf)) {
    Copy-Item -LiteralPath $runnerYamlSource -Destination $runnerYamlStaged -Force
    Copy-Item -LiteralPath $schemasSource -Destination $schemasStaged -Recurse -Force
    Copy-Item -LiteralPath $requestPayloadsSource -Destination $requestPayloadsStaged -Recurse -Force
    Copy-Item -LiteralPath $appSource -Destination $appStaged -Force

    $runnerProjectText = Get-Content -LiteralPath $runnerProject -Raw
    if ($runnerProjectText -notmatch "schemas\\\*\\\*\\\*" -or $runnerProjectText -notmatch "request-payloads\\\*\\\*\\\*") {
        $runnerProjectText = $runnerProjectText -replace "</Project>", @"
  <ItemGroup>
    <None Update="schemas\**\*">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
    <None Update="request-payloads\**\*">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
  </ItemGroup>

</Project>
"@
        Write-TextFile -Path $runnerProject -Value $runnerProjectText
    }

    $packageResults += Invoke-DotnetCommand -Name "package-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Runner", "--version", "4.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner-assertions" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Assertions", "--version", "3.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner-generators" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Generators", "--version", "3.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir

    if (@($packageResults | Where-Object { [int]$_["exit_code"] -ne 0 }).Count -eq 0) {
        $buildResult = Invoke-DotnetCommand -Name "build-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("build", $runnerProject, "--nologo", "-clp:ErrorsOnly") -EvidenceDir $evidenceDir
        if ([int]$buildResult.exit_code -eq 0) {
            $templateResult = Invoke-DotnetCommand -Name "template-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("run", "--project", $runnerProject, "--", "template", $runnerYamlStaged, "--no-env") -EvidenceDir $evidenceDir
        }
    }
} else {
    $failureReason = "dotnet new qaas-runner failed or project was not created"
}

$templatePassed = ($null -ne $templateResult -and [int]$templateResult.exit_code -eq 0)
if ($templatePassed) {
    try {
        $fastApiProcessEnvironment = [ordered]@{
            PYTHONUTF8 = "1"
            PYTHONIOENCODING = "utf-8"
            PYTHONUNBUFFERED = "1"
            NO_COLOR = "1"
            TERM = "dumb"
        }
        $previousEnvironment = @{}
        foreach ($entry in $fastApiProcessEnvironment.GetEnumerator()) {
            $previousEnvironment[$entry.Key] = [System.Environment]::GetEnvironmentVariable($entry.Key, "Process")
            [System.Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, "Process")
        }
        $process = Start-Process -FilePath $fastApiCliPath -ArgumentList @("dev") -WorkingDirectory $fastApiWorkDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $fastApiStdoutPath -RedirectStandardError $fastApiStderrPath
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
                } else {
                    $failureReason = "readiness response did not match expected item_id/q"
                }
            } catch {
                Start-Sleep -Milliseconds 500
            }
        }

        if (-not $ready -and [string]::IsNullOrWhiteSpace($failureReason)) {
            $failureReason = "timed out waiting for /items/5?q=somequery"
        }

        if ($ready) {
            $liveResult = Invoke-DotnetCommand -Name "live-runner-run" -WorkingDirectory $runnerProjectRoot -ArgumentList @("run", "--project", $runnerProject, "--", "run", $runnerYamlStaged, "-e", "--no-env") -EvidenceDir $evidenceDir
        }
    } finally {
        if ($null -ne $process) {
            $cleanupProcessIds = @(Stop-ProcessTree -RootProcessId ([int]$process.Id))
        }

        $cleanupDeadline = (Get-Date).AddSeconds(10)
        do {
            $remainingTrackedProcessIds = @()
            foreach ($processId in @($cleanupProcessIds)) {
                if ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
                    $remainingTrackedProcessIds += [int]$processId
                }
            }

            $portOwnersAfterCleanup = @(Get-PortListener -Port $port)
            if ($remainingTrackedProcessIds.Count -eq 0 -and $portOwnersAfterCleanup.Count -eq 0) {
                break
            }

            Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $cleanupDeadline)
    }
} elseif ([string]::IsNullOrWhiteSpace($failureReason)) {
    $failureReason = "runner template validation did not pass"
}

$cleanupPassed = ($portOwnersAfterCleanup.Count -eq 0 -and @($remainingTrackedProcessIds).Count -eq 0)
if ($null -eq $process) {
    $cleanupPassed = $true
}
$buildPassed = ($null -ne $buildResult -and [int]$buildResult.exit_code -eq 0)
$livePassed = ($null -ne $liveResult -and [int]$liveResult.exit_code -eq 0)
$validationPassed = ($buildPassed -and $templatePassed -and $ready -and $livePassed -and $cleanupPassed)
if (-not $validationPassed -and [string]::IsNullOrWhiteSpace($failureReason)) {
    $failureReason = "build_template_live_or_cleanup_failed"
}

$sourceHashes = [ordered]@{
    candidate_yaml_sha256 = Get-Sha256Hex -Path $runnerYamlSource
    staged_yaml_sha256 = if (Test-Path -LiteralPath $runnerYamlStaged -PathType Leaf) { Get-Sha256Hex -Path $runnerYamlStaged } else { "" }
    candidate_schema_sha256 = Get-Sha256Hex -Path $schemaSource
    staged_schema_sha256 = if (Test-Path -LiteralPath (Join-Path $schemasStaged "item-response.schema.json") -PathType Leaf) { Get-Sha256Hex -Path (Join-Path $schemasStaged "item-response.schema.json") } else { "" }
    candidate_request_payload_sha256 = Get-Sha256Hex -Path $requestPayloadSource
    staged_request_payload_sha256 = if (Test-Path -LiteralPath (Join-Path $requestPayloadsStaged "get-items-5.bin") -PathType Leaf) { Get-Sha256Hex -Path (Join-Path $requestPayloadsStaged "get-items-5.bin") } else { "" }
    candidate_app_sha256 = Get-Sha256Hex -Path $appSource
    staged_app_sha256 = if (Test-Path -LiteralPath $appStaged -PathType Leaf) { Get-Sha256Hex -Path $appStaged } else { "" }
}

$portOwnerDescriptions = @($portOwnersDuringReady | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)/pid=$($_.OwningProcess)/state=$($_.State)" })
$combinedLines = New-Object System.Collections.Generic.List[string]
$combinedLines.Add("Validation: selected-top-repo-candidate-live-fastapi")
$combinedLines.Add("Repository: fastapi/fastapi")
$combinedLines.Add("RunnerProject: $runnerProject")
$combinedLines.Add("RunnerYaml: $runnerYamlStaged")
$combinedLines.Add("FastApiCommand: fastapi dev")
$combinedLines.Add("FastApiWorkDir: $fastApiWorkDir")
$combinedLines.Add("ManagedVenvPath: $venvDir")
$combinedLines.Add("InstallCommand: $installCommand")
$combinedLines.Add("FastApiModuleVersion: $($fastApiInfo.Version)")
$combinedLines.Add("UvicornModuleVersion: $($uvicornInfo.Version)")
$combinedLines.Add("Ready: $ready")
$combinedLines.Add("ReadyStatus: $readyStatus")
$combinedLines.Add("ResponseStatus: $responseStatus")
$combinedLines.Add("PortOwnersDuringReady: $($portOwnerDescriptions -join ',')")
$combinedLines.Add("ProcessTreeIdsDuringReady: $($processTreeIdsDuringReady -join ',')")
$combinedLines.Add("BuildPassed: $buildPassed")
$combinedLines.Add("TemplatePassed: $templatePassed")
$combinedLines.Add("LivePassed: $livePassed")
$combinedLines.Add("CleanupPassed: $cleanupPassed")
$combinedLines.Add("CleanupProcessIds: $($cleanupProcessIds -join ',')")
$combinedLines.Add("RemainingTrackedProcessIds: $($remainingTrackedProcessIds -join ',')")
$combinedLines.Add("PortOwnersAfterCleanupCount: $($portOwnersAfterCleanup.Count)")
$combinedLines.Add("FailureReason: $failureReason")
$combinedLines.Add("ExitCode: $(if ($validationPassed) { 0 } else { 1 })")
$combinedLines.Add("")
foreach ($result in @($newRunner) + @($packageResults) + @($buildResult, $templateResult, $liveResult)) {
    if ($null -eq $result) {
        continue
    }
    $combinedLines.Add("==== $($result.name) ====")
    $combinedLines.Add("Command: $($result.command)")
    $combinedLines.Add("ExitCode: $($result.exit_code)")
    $combinedLines.Add("Transcript: $($result.transcript)")
    if (Test-Path -LiteralPath $result.transcript -PathType Leaf) {
        $combinedLines.Add((Get-Content -LiteralPath $result.transcript -Raw))
    }
}
$combinedLines.Add("==== python venv stdout ====")
if (Test-Path -LiteralPath $venvStdoutPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $venvStdoutPath -Raw)) }
$combinedLines.Add("==== python venv stderr ====")
if (Test-Path -LiteralPath $venvStderrPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $venvStderrPath -Raw)) }
$combinedLines.Add("==== pip install stdout ====")
if (Test-Path -LiteralPath $pipStdoutPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $pipStdoutPath -Raw)) }
$combinedLines.Add("==== pip install stderr ====")
if (Test-Path -LiteralPath $pipStderrPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $pipStderrPath -Raw)) }
$combinedLines.Add("==== fastapi stdout ====")
if (Test-Path -LiteralPath $fastApiStdoutPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $fastApiStdoutPath -Raw)) }
$combinedLines.Add("==== fastapi stderr ====")
if (Test-Path -LiteralPath $fastApiStderrPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $fastApiStderrPath -Raw)) }
Write-TextFile -Path $combinedTranscriptPath -Value ($combinedLines -join [Environment]::NewLine)

$buildValidation = if ($null -ne $buildResult) {
    New-ValidationRecord -Status ([string]$buildResult.status) -ExitCode ([int]$buildResult.exit_code) -Command ([string]$buildResult.command) -Transcript ([string]$buildResult.transcript)
} else {
    New-ValidationRecord -Status "not_run" -ExitCode 1 -Command "dotnet build $runnerProject --nologo -clp:ErrorsOnly" -Transcript $combinedTranscriptPath
}
$templateValidation = if ($null -ne $templateResult) {
    New-ValidationRecord -Status ([string]$templateResult.status) -ExitCode ([int]$templateResult.exit_code) -Command ([string]$templateResult.command) -Transcript ([string]$templateResult.transcript)
} else {
    New-ValidationRecord -Status "not_run" -ExitCode 1 -Command "dotnet run --project $runnerProject -- template $runnerYamlStaged --no-env" -Transcript $combinedTranscriptPath
}
$liveValidation = if ($null -ne $liveResult) {
    New-ValidationRecord -Status ([string]$liveResult.status) -ExitCode ([int]$liveResult.exit_code) -Command ([string]$liveResult.command) -Transcript ([string]$liveResult.transcript)
} else {
    New-ValidationRecord -Status "not_run" -ExitCode 1 -Command "dotnet run --project $runnerProject -- run $runnerYamlStaged -e --no-env" -Transcript $combinedTranscriptPath
}

$record = [ordered]@{
    schema_version = 1
    status = if ($validationPassed) { "passed" } else { "failed" }
    promotion_state = "blocked"
    completion_ready = $false
    repository = "fastapi/fastapi"
    validation_kind = "selected_candidate_qaas_template_live"
    run_dir = $runDir
    manifest = $manifestPath
    runtime_plan = $runtimePlanPath
    runner_project = $runnerProject
    runner_yaml = $runnerYamlStaged
    source_runner_yaml = $runnerYamlSource
    schemas = $schemasStaged
    source_hashes = $sourceHashes
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
    selected_readme_evidence = $selectedReadmePath
    build_validation = $buildValidation
    template_validation = $templateValidation
    live_validation = $liveValidation
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_contract_passed = $ready
    cleanup_passed = $cleanupPassed
    cleanup_process_ids = @($cleanupProcessIds)
    remaining_tracked_process_ids = @($remainingTrackedProcessIds)
    port_owners_after_cleanup_count = $portOwnersAfterCleanup.Count
    transcript = $combinedTranscriptPath
    fastapi_stdout = $fastApiStdoutPath
    fastapi_stderr = $fastApiStderrPath
    manifest_updated = $false
    weak_validation_passed = $false
    failure_reason = $failureReason
    exit_code = if ($validationPassed) { 0 } else { 1 }
}
Write-JsonFile -Path $summaryPath -Value $record

if ($validationPassed -and -not $NoManifestUpdate) {
    $validationEnvelope = [ordered]@{
        status = "passed"
        exit_code = 0
        command = "dotnet run --project $runnerProject -- template $runnerYamlStaged --no-env ; fastapi dev ; dotnet run --project $runnerProject -- run $runnerYamlStaged -e --no-env"
        transcript = $combinedTranscriptPath
        summary = $summaryPath
        response = $responsePath
        run_dir = $runDir
    }

    $manifest | Add-Member -NotePropertyName "build_validation" -NotePropertyValue $buildValidation -Force
    $manifest | Add-Member -NotePropertyName "template_validation" -NotePropertyValue $templateValidation -Force
    $manifest | Add-Member -NotePropertyName "live_validation" -NotePropertyValue $liveValidation -Force
    $manifest | Add-Member -NotePropertyName "selected_candidate_qaas_validation" -NotePropertyValue $validationEnvelope -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -eq "qaas-template") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $templateValidation.transcript)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-fastapi.ps1"
            $gate.blocked_reason = ""
        }
        if ($gate.gate_id -eq "qaas-live-act-assert") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $liveValidation.transcript, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-fastapi.ps1"
            $gate.blocked_reason = ""
        }
    }
    $validationAdvisories = @()
    if ($manifest.PSObject.Properties.Name -contains "validation_advisories") {
        $validationAdvisories = @($manifest.validation_advisories)
    }
    $httpStatusAdvisoryFound = (@($validationAdvisories | Where-Object { $_.advisory_id -eq "httpstatus-docs-inconsistency-recorded" }).Count -ne 0)
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -eq "httpstatus-docs-inconsistency-recorded") {
            if (-not $httpStatusAdvisoryFound) {
                $validationAdvisories += [ordered]@{
                advisory_id = "httpstatus-docs-inconsistency-recorded"
                advisory_type = "qaas_docs_contract"
                description = [string]$blocker.description
                public_evidence = @($blocker.public_evidence)
                resolved_by = "schema-derived StatusCode/OutputNames template and live validation"
                validation_summary = $summaryPath
                blocking = $false
                }
                $httpStatusAdvisoryFound = $true
            }
        } elseif ($blocker.blocker_id -ne "qaas-template-live-not-run") {
            $remainingBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingBlockers)
    $manifest | Add-Member -NotePropertyName "validation_advisories" -NotePropertyValue @($validationAdvisories) -Force
    $manifest.blocked_reason = "Selected FastAPI candidate passed lifecycle and QaaS template/live validation, but executable promotion remains blocked until live airgapped weak-model validation and strong review pass."
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan | Add-Member -NotePropertyName "qaas_validation" -NotePropertyValue $validationEnvelope -Force
    $runtimeBlockers = @()
    foreach ($blocker in @($runtimePlan.blockers)) {
        if ($blocker -notin @("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            $runtimeBlockers += $blocker
        }
    }
    $runtimePlan.blockers = @($runtimeBlockers)
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

    $record["manifest_updated"] = $true
    Write-JsonFile -Path $summaryPath -Value $record
}

Write-Output "FastAPI selected live validation status: $($record["status"])"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $combinedTranscriptPath"

if (-not $validationPassed) {
    exit 1
}
