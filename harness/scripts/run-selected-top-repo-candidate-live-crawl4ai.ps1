param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\250-unclecode-crawl4ai",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates",
    [string]$LocalPackageSource = "D:\QaaS\_localfeed\packages",
    [int]$TimeoutSeconds = 240,
    [int]$PullTimeoutSeconds = 900,
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
        return @($connections | Select-Object LocalAddress, LocalPort, State, OwningProcess)
    } catch {
        return @()
    }
}

function Get-PortListener {
    param([int]$Port)
    return @(Get-PortOwner -Port $Port | Where-Object { [string]$_.State -eq "Listen" })
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
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
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

function Get-DockerNames {
    param(
        [string]$DockerPath,
        [string]$NameRegex
    )

    $output = @(& $DockerPath ps -a --filter "name=$NameRegex" --format "{{.Names}}" 2>$null)
    return @($output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
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
        repository = "unclecode/crawl4ai"
        reason = $Reason
        run_dir = $RunDir
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

$allowedOutRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates"
$outRootPath = Get-NormalizedPath -Path $OutRoot
if (-not [string]::Equals($outRootPath, (Get-NormalizedPath -Path $allowedOutRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutRoot must be the managed selected-candidate live root: $allowedOutRoot"
}

$runId = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$runDir = Join-Path $outRootPath $runId
$runnerRoot = Join-Path $runDir "runner"
$assertionProjectRoot = Join-Path $runDir "assertions\ZappaSelectedCrawl4Ai.Assertions"
$evidenceDir = Join-Path $runDir "evidence"
foreach ($dir in @($runnerRoot, $assertionProjectRoot, $evidenceDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-live-crawl4ai.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$runnerYamlSource = Join-Path $candidateDirPath "test.qaas.yaml"
$requestPayloadsSource = Join-Path $candidateDirPath "request-payloads"
$requestPayloadSource = Join-Path $requestPayloadsSource "get-health.bin"
$assertionSource = Join-Path $candidateDirPath "assertion-packets\HttpStatusBelow400\HttpStatusBelow400.cs"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\250-unclecode-crawl4ai\files\README.md"
$selectedDockerfilePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\250-unclecode-crawl4ai\files\Dockerfile"
$selectedComposePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\250-unclecode-crawl4ai\files\docker-compose.yml"
$responsePath = Join-Path $evidenceDir "health-response.txt"
$dockerPullStdoutPath = Join-Path $evidenceDir "docker-pull.stdout.txt"
$dockerPullStderrPath = Join-Path $evidenceDir "docker-pull.stderr.txt"
$dockerRunStdoutPath = Join-Path $evidenceDir "docker-run.stdout.txt"
$dockerRunStderrPath = Join-Path $evidenceDir "docker-run.stderr.txt"
$dockerRmStdoutPath = Join-Path $evidenceDir "docker-rm.stdout.txt"
$dockerRmStderrPath = Join-Path $evidenceDir "docker-rm.stderr.txt"
$dockerLogsStdoutPath = Join-Path $evidenceDir "docker-logs.stdout.txt"
$dockerLogsStderrPath = Join-Path $evidenceDir "docker-logs.stderr.txt"
$combinedTranscriptPath = Join-Path $evidenceDir "selected-live-crawl4ai.transcript.txt"

foreach ($path in @($manifestPath, $runtimePlanPath, $runnerYamlSource, $requestPayloadSource, $assertionSource, $selectedReadmePath, $selectedDockerfilePath, $selectedComposePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required selected-candidate Crawl4AI live input missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $LocalPackageSource -PathType Container)) {
    throw "Local QaaS package source missing: $LocalPackageSource"
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
if ([string]$manifest.source_repository -ne "unclecode/crawl4ai" -or [string]$runtimePlan.repository -ne "unclecode/crawl4ai") {
    throw "This live runner only owns unclecode/crawl4ai."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected Crawl4AI candidate must be blocked before live validation."
}

$manifestHasLifecycleValidation = (
    ($manifest.PSObject.Properties.Name -contains "lifecycle_validation") -and
    $null -ne $manifest.lifecycle_validation -and
    [string]$manifest.lifecycle_validation.status -eq "passed"
)
if (-not $manifestHasLifecycleValidation) {
    $blocked = New-BlockedRecord -Reason "lifecycle_validation_must_pass_first" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI selected live validation blocked: $($blocked.reason)"
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
    Write-Output "Crawl4AI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @("docker pull unclecode/crawl4ai:latest", "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected Crawl4AI README evidence missing marker '$marker': $selectedReadmePath"
    }
}
$dockerfileText = Get-Content -LiteralPath $selectedDockerfilePath -Raw
if (-not $dockerfileText.Contains("curl -f http://localhost:11235/health || exit 1")) {
    throw "Selected Crawl4AI Dockerfile evidence missing health curl -f marker: $selectedDockerfilePath"
}
$composeText = Get-Content -LiteralPath $selectedComposePath -Raw
if (-not $composeText.Contains('test: ["CMD", "curl", "-f", "http://localhost:11235/health"]')) {
    throw "Selected Crawl4AI compose evidence missing health curl -f marker: $selectedComposePath"
}

$runnerYamlSourceText = Get-Content -LiteralPath $runnerYamlSource -Raw
foreach ($requiredText in @("Assertion: HttpStatusBelow400", "MaximumExclusiveStatusCode: 400", "OutputNames:", "Route: health", "Port: 11235")) {
    if ($runnerYamlSourceText -notmatch [regex]::Escape($requiredText)) {
        throw "Crawl4AI source YAML missing required docs-derived status range contract '$requiredText': $runnerYamlSource"
    }
}
foreach ($forbiddenText in @("Assertion: HttpStatus`r`n", "StatusCode: 200", "ExpectedText:", "Route: crawl", "Route: /crawl")) {
    if ($runnerYamlSourceText -match [regex]::Escape($forbiddenText)) {
        throw "Crawl4AI source YAML must not promote unsafe or invented contract '$forbiddenText': $runnerYamlSource"
    }
}
$assertionText = Get-Content -LiteralPath $assertionSource -Raw
foreach ($requiredText in @("BaseAssertion<HttpStatusBelow400Config>", "MaximumExclusiveStatusCode", "MetaData?.Http?.StatusCode", "statusCode >= Configuration.MaximumExclusiveStatusCode")) {
    if ($assertionText -notmatch [regex]::Escape($requiredText)) {
        throw "Crawl4AI assertion source missing required status range implementation '$requiredText': $assertionSource"
    }
}
if ([System.IO.File]::ReadAllBytes($requestPayloadSource).Length -ne 0) {
    throw "Crawl4AI GET payload must be empty: $requestPayloadSource"
}

$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $dockerCommand) {
    $blocked = New-BlockedRecord -Reason "docker_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
try {
    $dockerVersionText = (& $dockerCommand.Source version --format "{{.Server.Version}}" 2>$null | Out-String).Trim()
} catch {
    $blocked = New-BlockedRecord -Reason "docker_daemon_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
if ([string]::IsNullOrWhiteSpace($dockerVersionText)) {
    $blocked = New-BlockedRecord -Reason "docker_daemon_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 11235
$preExistingPortOwners = @(Get-PortListener -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $blocked = New-BlockedRecord -Reason "port_11235_already_in_use" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Crawl4AI selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$newRunner = Invoke-DotnetCommand -Name "dotnet-new-runner" -WorkingDirectory $runDir -ArgumentList @("new", "qaas-runner", "-n", "ZappaSelectedCrawl4Ai.Runner", "-o", $runnerRoot) -EvidenceDir $evidenceDir
$newAssertion = Invoke-DotnetCommand -Name "dotnet-new-assertion-library" -WorkingDirectory $runDir -ArgumentList @("new", "classlib", "-n", "ZappaSelectedCrawl4Ai.Assertions", "-o", $assertionProjectRoot) -EvidenceDir $evidenceDir
$runnerProjectRoot = Join-Path $runnerRoot "ZappaSelectedCrawl4Ai.Runner"
$runnerProject = Join-Path $runnerProjectRoot "ZappaSelectedCrawl4Ai.Runner.csproj"
$runnerProgram = Join-Path $runnerProjectRoot "Program.cs"
$runnerYamlStaged = Join-Path $runnerProjectRoot "test.qaas.yaml"
$requestPayloadsStaged = Join-Path $runnerProjectRoot "request-payloads"
$assertionProject = Join-Path $assertionProjectRoot "ZappaSelectedCrawl4Ai.Assertions.csproj"
$assertionStaged = Join-Path $assertionProjectRoot "HttpStatusBelow400.cs"
$class1 = Join-Path $assertionProjectRoot "Class1.cs"

$packageResults = @()
$projectReferenceResult = $null
$assertionBuildResult = $null
$buildResult = $null
$templateResult = $null
$liveResult = $null
$pullResult = $null
$runResult = $null
$rmResult = $null
$containerId = ""
$containerName = "zappa-crawl4ai-health-live-$runId"
$protectedContainerName = "crawl4ai"
$protectedContainerNamesBefore = @(Get-DockerNames -DockerPath $dockerCommand.Source -NameRegex "^/$protectedContainerName$")
$protectedContainerNamesAfter = @()
$ready = $false
$readyStatus = ""
$responseStatus = $null
$responseBody = ""
$cleanupPassed = $false
$containerExistsAfterCleanup = $true
$portOwnersAfterCleanup = @()
$failureReason = ""
$image = "unclecode/crawl4ai:latest"

if ($containerName -eq $protectedContainerName -or -not $containerName.StartsWith("zappa-crawl4ai-health-live-", [System.StringComparison]::Ordinal)) {
    throw "Unsafe Crawl4AI live test container name: $containerName"
}

if ([int]$newRunner.exit_code -eq 0 -and [int]$newAssertion.exit_code -eq 0 -and (Test-Path -LiteralPath $runnerProject -PathType Leaf) -and (Test-Path -LiteralPath $assertionProject -PathType Leaf)) {
    Copy-Item -LiteralPath $runnerYamlSource -Destination $runnerYamlStaged -Force
    Copy-Item -LiteralPath $requestPayloadsSource -Destination $requestPayloadsStaged -Recurse -Force
    Copy-Item -LiteralPath $assertionSource -Destination $assertionStaged -Force
    if (Test-Path -LiteralPath $class1 -PathType Leaf) {
        Remove-Item -LiteralPath $class1 -Force
    }
    Write-TextFile -Path $runnerProgram -Value @"
System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Crawl4Ai.Assertions.HttpStatusBelow400));
Directory.SetCurrentDirectory(AppContext.BaseDirectory);
QaaS.Runner.Bootstrap.New(args).Run();
"@

    $packageResults += Invoke-DotnetCommand -Name "package-assertion-sdk" -WorkingDirectory $assertionProjectRoot -ArgumentList @("add", $assertionProject, "package", "QaaS.Framework.SDK", "--version", "1.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Runner", "--version", "4.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner-assertions" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Assertions", "--version", "3.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner-generators" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Generators", "--version", "3.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $projectReferenceResult = Invoke-DotnetCommand -Name "reference-runner-assertion-project" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "reference", $assertionProject) -EvidenceDir $evidenceDir

    if (@($packageResults | Where-Object { [int]$_["exit_code"] -ne 0 }).Count -eq 0 -and [int]$projectReferenceResult.exit_code -eq 0) {
        $assertionBuildResult = Invoke-DotnetCommand -Name "build-assertion-library" -WorkingDirectory $assertionProjectRoot -ArgumentList @("build", $assertionProject, "--nologo", "-clp:ErrorsOnly") -EvidenceDir $evidenceDir
        if ([int]$assertionBuildResult.exit_code -eq 0) {
            $buildResult = Invoke-DotnetCommand -Name "build-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("build", $runnerProject, "--nologo", "-clp:ErrorsOnly") -EvidenceDir $evidenceDir
            if ([int]$buildResult.exit_code -eq 0) {
                $templateResult = Invoke-DotnetCommand -Name "template-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("run", "--project", $runnerProject, "--", "template", $runnerYamlStaged, "--no-env") -EvidenceDir $evidenceDir
            }
        }
    }
} else {
    $failureReason = "dotnet new qaas-runner/classlib failed or projects were not created"
}

$templatePassed = ($null -ne $templateResult -and [int]$templateResult.exit_code -eq 0)
if ($templatePassed) {
    try {
        $pullResult = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList @("pull", $image) -StdoutPath $dockerPullStdoutPath -StderrPath $dockerPullStderrPath -TimeoutSeconds $PullTimeoutSeconds
        if ([int]$pullResult.ExitCode -ne 0) {
            $failureReason = "docker pull failed with exit code $($pullResult.ExitCode)"
        } else {
            $dockerRunArguments = @("run", "-d", "-p", "127.0.0.1:11235:11235", "--name", $containerName, "--shm-size=1g", $image)
            $runResult = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList $dockerRunArguments -StdoutPath $dockerRunStdoutPath -StderrPath $dockerRunStderrPath -TimeoutSeconds 60
            if ([int]$runResult.ExitCode -ne 0) {
                $failureReason = "docker run failed with exit code $($runResult.ExitCode)"
            } else {
                $containerId = (Get-Content -LiteralPath $dockerRunStdoutPath -Raw).Trim()
                $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
                while ((Get-Date) -lt $deadline) {
                    try {
                        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 5
                        $responseStatus = [int]$response.StatusCode
                        $responseBody = [string]$response.Content
                        if ($responseStatus -lt 400) {
                            $ready = $true
                            $readyStatus = "HTTP $responseStatus from /health satisfied Docker curl -f status < 400 semantics"
                            Write-TextFile -Path $responsePath -Value $responseBody
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

                if ($ready) {
                    $liveResult = Invoke-DotnetCommand -Name "live-runner-run" -WorkingDirectory $runnerProjectRoot -ArgumentList @("run", "--project", $runnerProject, "--", "run", $runnerYamlStaged, "-e", "--no-env") -EvidenceDir $evidenceDir
                }
            }
        }
    } finally {
        if (-not [string]::IsNullOrWhiteSpace($containerName)) {
            $null = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList @("logs", $containerName) -StdoutPath $dockerLogsStdoutPath -StderrPath $dockerLogsStderrPath -TimeoutSeconds 30
            $rmResult = Invoke-LoggedProcess -FilePath $dockerCommand.Source -ArgumentList @("rm", "-f", $containerName) -StdoutPath $dockerRmStdoutPath -StderrPath $dockerRmStderrPath -TimeoutSeconds 60
        }
        $containerNamesAfterCleanup = @(Get-DockerNames -DockerPath $dockerCommand.Source -NameRegex "^/$containerName$")
        $containerExistsAfterCleanup = (@($containerNamesAfterCleanup | Where-Object { [string]$_ -eq $containerName }).Count -gt 0)
        $portOwnersAfterCleanup = @(Get-PortListener -Port $port)
        $protectedContainerNamesAfter = @(Get-DockerNames -DockerPath $dockerCommand.Source -NameRegex "^/$protectedContainerName$")
        $cleanupPassed = (
            $null -ne $rmResult -and
            [int]$rmResult.ExitCode -eq 0 -and
            -not $containerExistsAfterCleanup -and
            $portOwnersAfterCleanup.Count -eq 0 -and
            ((@($protectedContainerNamesBefore) -join "`n") -eq (@($protectedContainerNamesAfter) -join "`n"))
        )
    }
} elseif ([string]::IsNullOrWhiteSpace($failureReason)) {
    $failureReason = "runner template validation did not pass"
}

$assertionBuildPassed = ($null -ne $assertionBuildResult -and [int]$assertionBuildResult.exit_code -eq 0)
$buildPassed = ($null -ne $buildResult -and [int]$buildResult.exit_code -eq 0)
$livePassed = ($null -ne $liveResult -and [int]$liveResult.exit_code -eq 0)
$validationPassed = ($assertionBuildPassed -and $buildPassed -and $templatePassed -and $ready -and $livePassed -and $cleanupPassed)
if (-not $validationPassed -and [string]::IsNullOrWhiteSpace($failureReason)) {
    $failureReason = "assertion_build_runner_build_template_live_or_cleanup_failed"
}

$sourceHashes = [ordered]@{
    candidate_yaml_sha256 = Get-Sha256Hex -Path $runnerYamlSource
    staged_yaml_sha256 = if (Test-Path -LiteralPath $runnerYamlStaged -PathType Leaf) { Get-Sha256Hex -Path $runnerYamlStaged } else { "" }
    candidate_request_payload_sha256 = Get-Sha256Hex -Path $requestPayloadSource
    staged_request_payload_sha256 = if (Test-Path -LiteralPath (Join-Path $requestPayloadsStaged "get-health.bin") -PathType Leaf) { Get-Sha256Hex -Path (Join-Path $requestPayloadsStaged "get-health.bin") } else { "" }
    candidate_assertion_sha256 = Get-Sha256Hex -Path $assertionSource
    staged_assertion_sha256 = if (Test-Path -LiteralPath $assertionStaged -PathType Leaf) { Get-Sha256Hex -Path $assertionStaged } else { "" }
}

$responseSha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { "" }
$combinedLines = New-Object System.Collections.Generic.List[string]
$combinedLines.Add("Validation: selected-top-repo-candidate-live-crawl4ai")
$combinedLines.Add("Repository: unclecode/crawl4ai")
$combinedLines.Add("RunnerProject: $runnerProject")
$combinedLines.Add("RunnerYaml: $runnerYamlStaged")
$combinedLines.Add("AssertionProject: $assertionProject")
$combinedLines.Add("AssertionSource: $assertionStaged")
$combinedLines.Add("AssertionProjectReferenceAdded: $($null -ne $projectReferenceResult -and [int]$projectReferenceResult.exit_code -eq 0)")
$combinedLines.Add("DockerPullCommand: docker pull $image")
$combinedLines.Add("DockerRunCommand: docker run -d -p 127.0.0.1:11235:11235 --name $containerName --shm-size=1g $image")
$combinedLines.Add("DockerServerVersion: $dockerVersionText")
$combinedLines.Add("ContainerName: $containerName")
$combinedLines.Add("ContainerId: $containerId")
$combinedLines.Add("ProtectedContainerName: $protectedContainerName")
$combinedLines.Add("ProtectedContainerNamesBefore: $($protectedContainerNamesBefore -join ',')")
$combinedLines.Add("ProtectedContainerNamesAfter: $($protectedContainerNamesAfter -join ',')")
$combinedLines.Add("ReadinessUrl: http://127.0.0.1:11235/health")
$combinedLines.Add("Ready: $ready")
$combinedLines.Add("ReadyStatus: $readyStatus")
$combinedLines.Add("ResponseStatus: $responseStatus")
$combinedLines.Add("ResponseBodySha256: $responseSha256")
$combinedLines.Add("AssertionBuildPassed: $assertionBuildPassed")
$combinedLines.Add("BuildPassed: $buildPassed")
$combinedLines.Add("TemplatePassed: $templatePassed")
$combinedLines.Add("LivePassed: $livePassed")
$combinedLines.Add("CleanupPassed: $cleanupPassed")
$combinedLines.Add("ContainerExistsAfterCleanup: $containerExistsAfterCleanup")
$combinedLines.Add("PortOwnersAfterCleanupCount: $($portOwnersAfterCleanup.Count)")
$combinedLines.Add("FailureReason: $failureReason")
$combinedLines.Add("ExitCode: $(if ($validationPassed) { 0 } else { 1 })")
$combinedLines.Add("")
foreach ($result in @($newRunner, $newAssertion) + @($packageResults) + @($projectReferenceResult, $assertionBuildResult, $buildResult, $templateResult, $liveResult)) {
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
foreach ($dockerLog in @(
    [pscustomobject]@{ Label = "docker pull stdout"; Path = $dockerPullStdoutPath },
    [pscustomobject]@{ Label = "docker pull stderr"; Path = $dockerPullStderrPath },
    [pscustomobject]@{ Label = "docker run stdout"; Path = $dockerRunStdoutPath },
    [pscustomobject]@{ Label = "docker run stderr"; Path = $dockerRunStderrPath },
    [pscustomobject]@{ Label = "docker logs stdout"; Path = $dockerLogsStdoutPath },
    [pscustomobject]@{ Label = "docker logs stderr"; Path = $dockerLogsStderrPath },
    [pscustomobject]@{ Label = "docker rm stdout"; Path = $dockerRmStdoutPath },
    [pscustomobject]@{ Label = "docker rm stderr"; Path = $dockerRmStderrPath }
)) {
    $combinedLines.Add("==== $($dockerLog.Label) ====")
    if (Test-Path -LiteralPath $dockerLog.Path -PathType Leaf) {
        $combinedLines.Add((Get-Content -LiteralPath $dockerLog.Path -Raw))
    }
}
Write-TextFile -Path $combinedTranscriptPath -Value ($combinedLines -join [Environment]::NewLine)

$assertionBuildValidation = if ($null -ne $assertionBuildResult) {
    New-ValidationRecord -Status ([string]$assertionBuildResult.status) -ExitCode ([int]$assertionBuildResult.exit_code) -Command ([string]$assertionBuildResult.command) -Transcript ([string]$assertionBuildResult.transcript)
} else {
    New-ValidationRecord -Status "not_run" -ExitCode 1 -Command "dotnet build $assertionProject --nologo -clp:ErrorsOnly" -Transcript $combinedTranscriptPath
}
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
    repository = "unclecode/crawl4ai"
    validation_kind = "selected_candidate_qaas_template_live"
    run_dir = $runDir
    manifest = $manifestPath
    runtime_plan = $runtimePlanPath
    runner_project = $runnerProject
    runner_program = $runnerProgram
    runner_yaml = $runnerYamlStaged
    source_runner_yaml = $runnerYamlSource
    assertion_project = $assertionProject
    assertion_source = $assertionStaged
    source_assertion = $assertionSource
    assertion_project_reference_transcript = if ($null -ne $projectReferenceResult) { $projectReferenceResult.transcript } else { $null }
    assertion_project_reference_added = ($null -ne $projectReferenceResult -and [int]$projectReferenceResult.exit_code -eq 0)
    source_hashes = $sourceHashes
    image = $image
    docker_path = $dockerCommand.Source
    docker_server_version = $dockerVersionText
    docker_pull_exit_code = if ($null -ne $pullResult) { [int]$pullResult.ExitCode } else { $null }
    docker_run_exit_code = if ($null -ne $runResult) { [int]$runResult.ExitCode } else { $null }
    docker_rm_exit_code = if ($null -ne $rmResult) { [int]$rmResult.ExitCode } else { $null }
    container_name = $containerName
    container_id = $containerId
    cleanup_target_container_name = $containerName
    protected_container_name = $protectedContainerName
    protected_container_names_before = @($protectedContainerNamesBefore)
    protected_container_names_after = @($protectedContainerNamesAfter)
    docker_pull_stdout = $dockerPullStdoutPath
    docker_pull_stderr = $dockerPullStderrPath
    docker_run_stdout = $dockerRunStdoutPath
    docker_run_stderr = $dockerRunStderrPath
    docker_rm_stdout = $dockerRmStdoutPath
    docker_rm_stderr = $dockerRmStderrPath
    docker_logs_stdout = $dockerLogsStdoutPath
    docker_logs_stderr = $dockerLogsStderrPath
    selected_readme_evidence = $selectedReadmePath
    selected_dockerfile_evidence = $selectedDockerfilePath
    selected_compose_evidence = $selectedComposePath
    assertion_build_validation = $assertionBuildValidation
    build_validation = $buildValidation
    template_validation = $templateValidation
    live_validation = $liveValidation
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_body_sha256 = $responseSha256
    response_contract = "http_status_less_than_400_body_unasserted"
    response_contract_passed = $ready
    cleanup_passed = $cleanupPassed
    container_exists_after_cleanup = $containerExistsAfterCleanup
    port_owners_after_cleanup_count = $portOwnersAfterCleanup.Count
    transcript = $combinedTranscriptPath
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
        command = "dotnet build $assertionProject ; dotnet run --project $runnerProject -- template $runnerYamlStaged --no-env ; docker run -d -p 127.0.0.1:11235:11235 --name $containerName --shm-size=1g $image ; dotnet run --project $runnerProject -- run $runnerYamlStaged -e --no-env ; docker rm -f $containerName"
        transcript = $combinedTranscriptPath
        summary = $summaryPath
        response = $responsePath
        run_dir = $runDir
    }

    $manifest | Add-Member -NotePropertyName "assertion_build_validation" -NotePropertyValue $assertionBuildValidation -Force
    $manifest | Add-Member -NotePropertyName "build_validation" -NotePropertyValue $buildValidation -Force
    $manifest | Add-Member -NotePropertyName "template_validation" -NotePropertyValue $templateValidation -Force
    $manifest | Add-Member -NotePropertyName "live_validation" -NotePropertyValue $liveValidation -Force
    $manifest | Add-Member -NotePropertyName "selected_candidate_qaas_validation" -NotePropertyValue $validationEnvelope -Force
    foreach ($packet in @($manifest.custom_assertion_packets)) {
        if ($packet.assertion_name -eq "HttpStatusBelow400") {
            $packet.status = "build_template_live_validated_blocked_until_airgapped"
            $packet.activation = "source_yaml_validated"
            $packet.wired_into_runner_yaml = $true
            $packet.validation_records.build = "passed"
            $packet.validation_records.schema = "passed"
            $packet.validation_records.template = "passed"
            $packet.validation_records.live = "passed"
            $packet.validation_records.airgapped = "not_run"
            $packet.weak_validation_passed = $false
        }
    }
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -eq "http-status-below-400-assertion-or-hook") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $assertionBuildValidation.transcript, $templateValidation.transcript, $liveValidation.transcript)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-crawl4ai.ps1"
            $gate.blocked_reason = ""
        }
        if ($gate.gate_id -eq "qaas-template") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $templateValidation.transcript)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-crawl4ai.ps1"
            $gate.blocked_reason = ""
        }
        if ($gate.gate_id -eq "qaas-live-act-assert") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $liveValidation.transcript, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-crawl4ai.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -notin @("crawl4ai-status-below-400-hook-not-template-validated", "qaas-template-live-not-run")) {
            $remainingBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingBlockers)
    $manifest.blocked_reason = "Selected Crawl4AI candidate passed Docker lifecycle, custom HttpStatusBelow400 build/template/live validation, and QaaS template/live validation, but executable promotion remains blocked until selected body/crawl scope decisions, live airgapped weak-model validation, and strong review pass."
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan | Add-Member -NotePropertyName "qaas_validation" -NotePropertyValue $validationEnvelope -Force
    $runtimePlan | Add-Member -NotePropertyName "http_status_below_400_assertion" -NotePropertyValue ([ordered]@{
        status = "build_template_live_validated"
        validation_status = "build_template_live_validated"
        summary = $summaryPath
        assertion_project = $assertionProject
        assertion_source = $assertionStaged
    }) -Force
    $runtimeBlockers = @()
    foreach ($blocker in @($runtimePlan.blockers)) {
        if ($blocker -notin @("build_and_template_validate_http_status_below_400_assertion", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            $runtimeBlockers += $blocker
        }
    }
    $runtimePlan.blockers = @($runtimeBlockers)
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

    $record["manifest_updated"] = $true
    Write-JsonFile -Path $summaryPath -Value $record
}

Write-Output "Crawl4AI selected live validation status: $($record["status"])"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $combinedTranscriptPath"

if (-not $validationPassed) {
    exit 1
}
