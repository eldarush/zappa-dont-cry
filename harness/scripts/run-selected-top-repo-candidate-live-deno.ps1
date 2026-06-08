param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\098-denoland-deno",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates",
    [string]$LocalPackageSource = "D:\QaaS\_localfeed\packages",
    [string]$LifecycleSummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\selected-top-repo-candidate-lifecycle-deno.json",
    [int]$TimeoutSeconds = 120,
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
            # Best-effort cleanup; final checks decide pass/fail.
        }
    }

    Start-Sleep -Milliseconds 500
    return @($ids)
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
        repository = "denoland/deno"
        reason = $Reason
        run_dir = $RunDir
        manifest_updated = $false
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $SummaryPath -Value $record
    return $record
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

$allowedOutRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates"
$outRootPath = Get-NormalizedPath -Path $OutRoot
if (-not [string]::Equals($outRootPath, (Get-NormalizedPath -Path $allowedOutRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "OutRoot must be the managed selected-candidate live root: $allowedOutRoot"
}

$runDir = Join-Path $outRootPath (Get-Date -Format "yyyyMMdd-HHmmss-fff")
$runnerRoot = Join-Path $runDir "runner"
$assertionProjectRoot = Join-Path $runDir "assertions\ZappaSelectedDeno.Assertions"
$denoWorkDir = Join-Path $runDir "deno-work"
$denoDir = Join-Path $runDir "deno-dir"
$evidenceDir = Join-Path $runDir "evidence"
foreach ($dir in @($runnerRoot, $assertionProjectRoot, $denoWorkDir, $denoDir, $evidenceDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-live-deno.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$runnerYamlSource = Join-Path $candidateDirPath "test.qaas.yaml"
$requestPayloadsSource = Join-Path $candidateDirPath "request-payloads"
$requestPayloadSource = Join-Path $requestPayloadsSource "get-root.bin"
$serverSource = Join-Path $candidateDirPath "app\server.ts"
$expectedBodySource = Join-Path $candidateDirPath "expectations\root-body.txt"
$assertionSource = Join-Path $candidateDirPath "assertion-packets\ExactHttpTextBody\ExactHttpTextBody.cs"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\098-denoland-deno\files\README.md"
$denoStdoutPath = Join-Path $evidenceDir "deno.stdout.txt"
$denoStderrPath = Join-Path $evidenceDir "deno.stderr.txt"
$denoVersionStdoutPath = Join-Path $evidenceDir "deno-version.stdout.txt"
$denoVersionStderrPath = Join-Path $evidenceDir "deno-version.stderr.txt"
$responsePath = Join-Path $evidenceDir "root-response.txt"
$combinedTranscriptPath = Join-Path $evidenceDir "selected-live-deno.transcript.txt"

foreach ($path in @($manifestPath, $runtimePlanPath, $runnerYamlSource, $requestPayloadSource, $serverSource, $expectedBodySource, $assertionSource, $selectedReadmePath, $LifecycleSummaryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required selected-candidate Deno live input missing: $path"
    }
}
if (-not (Test-Path -LiteralPath $LocalPackageSource -PathType Container)) {
    throw "Local QaaS package source missing: $LocalPackageSource"
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
$lifecycleSummary = Read-JsonFile -Path $LifecycleSummaryPath
if ([string]$manifest.source_repository -ne "denoland/deno" -or [string]$runtimePlan.repository -ne "denoland/deno" -or [string]$lifecycleSummary.repository -ne "denoland/deno") {
    throw "This live runner only owns denoland/deno."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected Deno candidate must be blocked before live validation."
}
if ([string]$lifecycleSummary.status -ne "passed" -or [string]$manifest.lifecycle_validation.status -ne "passed" -or [string]$runtimePlan.lifecycle_validation.status -ne "passed") {
    $blocked = New-BlockedRecord -Reason "lifecycle_validation_must_pass_first" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Deno selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
if ([string]$runtimePlan.cleanup.status -ne "passed") {
    $blocked = New-BlockedRecord -Reason "cleanup_lifecycle_must_pass_first" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Deno selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$denoPath = [string]$lifecycleSummary.deno_path
if ([string]::IsNullOrWhiteSpace($denoPath) -or -not (Test-Path -LiteralPath $denoPath -PathType Leaf)) {
    throw "Deno lifecycle summary does not cite an existing managed deno.exe: $LifecycleSummaryPath"
}
if (-not (Test-PathUnderRoot -Path $denoPath -Root "D:\QaaS\_tmp\zappa-dont-cry\toolchains\deno")) {
    throw "Deno live runner refuses non-managed deno.exe: $denoPath"
}
if ([string]$lifecycleSummary.managed_toolchain_release_tag -ne "v2.8.2" -or [string]$lifecycleSummary.managed_toolchain_archive_sha256 -ne "6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9") {
    throw "Deno lifecycle summary managed toolchain metadata mismatch: $LifecycleSummaryPath"
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @("Deno.serve((_req: Request) => {", 'return new Response("Hello, world!");', "deno run --allow-net server.ts", "http://localhost:8000")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected Deno README evidence missing marker '$marker': $selectedReadmePath"
    }
}
$serverText = Get-Content -LiteralPath $serverSource -Raw
foreach ($marker in @("Deno.serve((_req: Request) => {", 'return new Response("Hello, world!");')) {
    if (-not $serverText.Contains($marker)) {
        throw "Generated Deno server missing README marker '$marker': $serverSource"
    }
}
$expectedBody = Get-Content -LiteralPath $expectedBodySource -Raw
if ($expectedBody -ne "Hello, world!") {
    throw "Deno expected body must exactly match public README evidence: $expectedBodySource"
}
if ([System.IO.File]::ReadAllBytes($requestPayloadSource).Length -ne 0) {
    throw "Deno GET payload must be empty: $requestPayloadSource"
}

$port = 8000
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $blocked = New-BlockedRecord -Reason "port_8000_already_in_use" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Deno selected live validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$versionStart = [System.Diagnostics.ProcessStartInfo]::new()
$versionStart.FileName = $denoPath
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
Write-TextFile -Path $denoVersionStdoutPath -Value $denoVersionOutput
Write-TextFile -Path $denoVersionStderrPath -Value ([string]$versionStderrTask.Result)
if ($versionProcess.ExitCode -ne 0 -or -not $denoVersionOutput.StartsWith("deno 2.8.2", [System.StringComparison]::Ordinal)) {
    throw "Managed Deno version check failed. Expected deno 2.8.2, got: $denoVersionOutput"
}
$denoVersionLine = ($denoVersionOutput -split "\r?\n" | Select-Object -First 1)

$newRunner = Invoke-DotnetCommand -Name "dotnet-new-runner" -WorkingDirectory $runDir -ArgumentList @("new", "qaas-runner", "-n", "ZappaSelectedDeno.Runner", "-o", $runnerRoot) -EvidenceDir $evidenceDir
$newAssertion = Invoke-DotnetCommand -Name "dotnet-new-assertion-library" -WorkingDirectory $runDir -ArgumentList @("new", "classlib", "-n", "ZappaSelectedDeno.Assertions", "-o", $assertionProjectRoot) -EvidenceDir $evidenceDir
$runnerProjectRoot = Join-Path $runnerRoot "ZappaSelectedDeno.Runner"
$runnerProject = Join-Path $runnerProjectRoot "ZappaSelectedDeno.Runner.csproj"
$runnerProgram = Join-Path $runnerProjectRoot "Program.cs"
$runnerYamlStaged = Join-Path $runnerProjectRoot "test.qaas.yaml"
$requestPayloadsStaged = Join-Path $runnerProjectRoot "request-payloads"
$serverStaged = Join-Path $denoWorkDir "server.ts"
$expectedBodyStaged = Join-Path $runnerProjectRoot "expectations\root-body.txt"
$assertionProject = Join-Path $assertionProjectRoot "ZappaSelectedDeno.Assertions.csproj"
$assertionStaged = Join-Path $assertionProjectRoot "ExactHttpTextBody.cs"
$class1 = Join-Path $assertionProjectRoot "Class1.cs"

$packageResults = @()
$projectReferenceResult = $null
$assertionBuildResult = $null
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

if ([int]$newRunner.exit_code -eq 0 -and [int]$newAssertion.exit_code -eq 0 -and (Test-Path -LiteralPath $runnerProject -PathType Leaf) -and (Test-Path -LiteralPath $assertionProject -PathType Leaf)) {
    Copy-Item -LiteralPath $requestPayloadsSource -Destination $requestPayloadsStaged -Recurse -Force
    Copy-Item -LiteralPath $serverSource -Destination $serverStaged -Force
    Copy-Item -LiteralPath $assertionSource -Destination $assertionStaged -Force
    if (Test-Path -LiteralPath $class1 -PathType Leaf) {
        Remove-Item -LiteralPath $class1 -Force
    }
    Write-TextFile -Path $expectedBodyStaged -Value $expectedBody
    Write-TextFile -Path $runnerYamlStaged -Value @"
# Staged live-only YAML generated from immutable public Deno README evidence.
# The source candidate YAML remains blocked until this staged custom assertion passes build/template/live validation.

MetaData:
  Team: ZappaDontCry
  System: denoland-deno

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetRootPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-root.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: DenoReadRoot
    Transactions:
      - Name: GetRoot
        TimeoutMs: 5000
        DataSourceNames:
          - GetRootPayload
        DataSourcePatterns:
          - GetRootPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 8000
          Route: ''
          Method: Get

Assertions:
  - Name: GetRootReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - DenoReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetRoot

  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - DenoReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello, world!
      EncodingName: utf-8
"@

    $runnerProjectText = Get-Content -LiteralPath $runnerProject -Raw
    if ($runnerProjectText -notmatch "request-payloads\\\*\\\*\\\*" -or $runnerProjectText -notmatch "expectations\\\*\\\*\\\*") {
        $runnerProjectText = $runnerProjectText -replace "</Project>", @"
  <ItemGroup>
    <None Update="request-payloads\**\*">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
    <None Update="expectations\**\*">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
  </ItemGroup>

</Project>
"@
        Write-TextFile -Path $runnerProject -Value $runnerProjectText
    }
    Write-TextFile -Path $runnerProgram -Value @"
System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Deno.Assertions.ExactHttpTextBody));
Directory.SetCurrentDirectory(AppContext.BaseDirectory);
QaaS.Runner.Bootstrap.New(args).Run();
"@

    $packageResults += Invoke-DotnetCommand -Name "package-assertion-sdk" -WorkingDirectory $assertionProjectRoot -ArgumentList @("add", $assertionProject, "package", "QaaS.Framework.SDK", "--version", "1.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Runner", "--version", "4.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner-assertions" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Assertions", "--version", "3.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $packageResults += Invoke-DotnetCommand -Name "package-runner-generators" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Generators", "--version", "3.5.1", "--source", $LocalPackageSource) -EvidenceDir $evidenceDir
    $projectReferenceResult = Invoke-DotnetCommand -Name "reference-runner-assertion-project" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "reference", $assertionProject) -EvidenceDir $evidenceDir

    if (Test-Path -LiteralPath $runnerProject -PathType Leaf) {
        Write-TextFile -Path $runnerProject -Value (Get-Content -LiteralPath $runnerProject -Raw)
    }
    if (Test-Path -LiteralPath $assertionProject -PathType Leaf) {
        Write-TextFile -Path $assertionProject -Value (Get-Content -LiteralPath $assertionProject -Raw)
    }

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
        $process = Start-ProcessWithEnvironment -FilePath $denoPath -Arguments @("run", "--allow-net", "server.ts") -WorkingDirectory $denoWorkDir -StdoutPath $denoStdoutPath -StderrPath $denoStderrPath -Environment @{ DENO_DIR = $denoDir }
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
                    $failureReason = "readiness response did not match expected text body"
                }
            } catch {
                Start-Sleep -Milliseconds 500
            }
        }

        if (-not $ready -and [string]::IsNullOrWhiteSpace($failureReason)) {
            $failureReason = "timed out waiting for /"
        }

        if ($ready) {
            $liveResult = Invoke-DotnetCommand -Name "live-runner-run" -WorkingDirectory $runnerProjectRoot -ArgumentList @("run", "--project", $runnerProject, "--", "run", $runnerYamlStaged, "-e", "--no-env") -EvidenceDir $evidenceDir
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

        $cleanupDeadline = (Get-Date).AddSeconds(10)
        do {
            $remainingTrackedProcessIds = @()
            foreach ($processId in @($cleanupProcessIds)) {
                if ($null -ne (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
                    $remainingTrackedProcessIds += [int]$processId
                }
            }

            $portOwnersAfterCleanup = @(Get-PortOwner -Port $port)
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
    staged_request_payload_sha256 = if (Test-Path -LiteralPath (Join-Path $requestPayloadsStaged "get-root.bin") -PathType Leaf) { Get-Sha256Hex -Path (Join-Path $requestPayloadsStaged "get-root.bin") } else { "" }
    candidate_server_sha256 = Get-Sha256Hex -Path $serverSource
    staged_server_sha256 = if (Test-Path -LiteralPath $serverStaged -PathType Leaf) { Get-Sha256Hex -Path $serverStaged } else { "" }
    candidate_expected_body_sha256 = Get-Sha256Hex -Path $expectedBodySource
    staged_expected_body_sha256 = if (Test-Path -LiteralPath $expectedBodyStaged -PathType Leaf) { Get-Sha256Hex -Path $expectedBodyStaged } else { "" }
    candidate_assertion_sha256 = Get-Sha256Hex -Path $assertionSource
    staged_assertion_sha256 = if (Test-Path -LiteralPath $assertionStaged -PathType Leaf) { Get-Sha256Hex -Path $assertionStaged } else { "" }
    selected_readme_sha256 = Get-Sha256Hex -Path $selectedReadmePath
}

$responseSha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { "" }
$portOwnerDescriptions = @($portOwnersDuringReady | ForEach-Object { "$($_.LocalAddress):$($_.LocalPort)/pid=$($_.OwningProcess)/state=$($_.State)" })
$combinedLines = New-Object System.Collections.Generic.List[string]
$combinedLines.Add("Validation: selected-top-repo-candidate-live-deno")
$combinedLines.Add("Repository: denoland/deno")
$combinedLines.Add("RunnerProject: $runnerProject")
$combinedLines.Add("RunnerYaml: $runnerYamlStaged")
$combinedLines.Add("AssertionProject: $assertionProject")
$combinedLines.Add("AssertionSource: $assertionStaged")
$combinedLines.Add("AssertionProjectReferenceAdded: $($null -ne $projectReferenceResult -and [int]$projectReferenceResult.exit_code -eq 0)")
$combinedLines.Add("DenoCommand: deno run --allow-net server.ts")
$combinedLines.Add("DenoPath: $denoPath")
$combinedLines.Add("DenoVersion: $denoVersionLine")
$combinedLines.Add("DenoDir: $denoDir")
$combinedLines.Add("DenoWorkDir: $denoWorkDir")
$combinedLines.Add("LifecycleSummary: $LifecycleSummaryPath")
$combinedLines.Add("ManagedToolchainArchiveSha256: $($lifecycleSummary.managed_toolchain_archive_sha256)")
$combinedLines.Add("Ready: $ready")
$combinedLines.Add("ReadyStatus: $readyStatus")
$combinedLines.Add("ResponseStatus: $responseStatus")
$combinedLines.Add("ResponseBodySha256: $responseSha256")
$combinedLines.Add("PortOwnersDuringReady: $($portOwnerDescriptions -join ',')")
$combinedLines.Add("ProcessTreeIdsDuringReady: $($processTreeIdsDuringReady -join ',')")
$combinedLines.Add("AssertionBuildPassed: $assertionBuildPassed")
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
$combinedLines.Add("==== deno --version stdout ====")
if (Test-Path -LiteralPath $denoVersionStdoutPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $denoVersionStdoutPath -Raw)) }
$combinedLines.Add("==== deno stdout ====")
if (Test-Path -LiteralPath $denoStdoutPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $denoStdoutPath -Raw)) }
$combinedLines.Add("==== deno stderr ====")
if (Test-Path -LiteralPath $denoStderrPath -PathType Leaf) { $combinedLines.Add((Get-Content -LiteralPath $denoStderrPath -Raw)) }
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
    repository = "denoland/deno"
    validation_kind = "selected_candidate_qaas_template_live"
    run_dir = $runDir
    manifest = $manifestPath
    runtime_plan = $runtimePlanPath
    lifecycle_summary = $LifecycleSummaryPath
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
    deno_path = $denoPath
    deno_version = $denoVersionLine
    deno_version_stdout = $denoVersionStdoutPath
    deno_version_stderr = $denoVersionStderrPath
    managed_toolchain_release_tag = $lifecycleSummary.managed_toolchain_release_tag
    managed_toolchain_download_url = $lifecycleSummary.managed_toolchain_download_url
    managed_toolchain_archive_sha256 = $lifecycleSummary.managed_toolchain_archive_sha256
    deno_dir = $denoDir
    deno_work_dir = $denoWorkDir
    selected_readme_evidence = $selectedReadmePath
    assertion_build_validation = $assertionBuildValidation
    build_validation = $buildValidation
    template_validation = $templateValidation
    live_validation = $liveValidation
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_body_sha256 = $responseSha256
    response_contract_passed = $ready
    cleanup_passed = $cleanupPassed
    cleanup_process_ids = @($cleanupProcessIds)
    remaining_tracked_process_ids = @($remainingTrackedProcessIds)
    port_owners_after_cleanup_count = $portOwnersAfterCleanup.Count
    transcript = $combinedTranscriptPath
    deno_stdout = $denoStdoutPath
    deno_stderr = $denoStderrPath
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
        command = "managed deno v2.8.2 ; dotnet build $assertionProject ; dotnet run --project $runnerProject -- template $runnerYamlStaged --no-env ; deno run --allow-net server.ts ; dotnet run --project $runnerProject -- run $runnerYamlStaged -e --no-env"
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
    $manifest.custom_text_body_assertion.status = "build_template_live_validated"
    $manifest.custom_text_body_assertion.validation_status = "build_template_live_validated"
    foreach ($packet in @($manifest.custom_assertion_packets)) {
        if ($packet.assertion_name -eq "ExactHttpTextBody") {
            $packet.status = "build_template_live_validated_blocked_until_airgapped"
            $packet.activation = "staged_live_runner_only"
            $packet.wired_into_runner_yaml = $true
            $packet.validation_records.build = "passed"
            $packet.validation_records.schema = "passed"
            $packet.validation_records.template = "passed"
            $packet.validation_records.live = "passed"
        }
    }
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -eq "plain-text-body-assertion-or-hook") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $assertionBuildValidation.transcript, $liveValidation.transcript)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-deno.ps1"
            $gate.blocked_reason = ""
        }
        if ($gate.gate_id -eq "qaas-template") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $templateValidation.transcript)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-deno.ps1"
            $gate.blocked_reason = ""
        }
        if ($gate.gate_id -eq "qaas-live-act-assert") {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $liveValidation.transcript, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-deno.ps1"
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
        } elseif ($blocker.blocker_id -notin @("deno-text-body-hook-not-template-validated", "qaas-template-live-not-run")) {
            $remainingBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingBlockers)
    $manifest | Add-Member -NotePropertyName "validation_advisories" -NotePropertyValue @($validationAdvisories) -Force
    $manifest.blocked_reason = "Selected Deno candidate passed managed lifecycle, custom ExactHttpTextBody build/template/live validation, and QaaS template/live validation, but executable promotion remains blocked until live airgapped weak-model validation and strong review pass."
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan | Add-Member -NotePropertyName "qaas_validation" -NotePropertyValue $validationEnvelope -Force
    if ($runtimePlan.PSObject.Properties.Name -contains "custom_text_body_assertion") {
        $runtimePlan.custom_text_body_assertion.status = "build_template_live_validated"
        $runtimePlan.custom_text_body_assertion.validation_status = "build_template_live_validated"
    }
    foreach ($packet in @($runtimePlan.custom_assertion_packets)) {
        if ($packet.assertion_name -eq "ExactHttpTextBody") {
            $packet.status = "build_template_live_validated_blocked_until_airgapped"
            $packet.activation = "staged_live_runner_only"
            $packet.wired_into_runner_yaml = $true
            $packet.validation_records.build = "passed"
            $packet.validation_records.schema = "passed"
            $packet.validation_records.template = "passed"
            $packet.validation_records.live = "passed"
        }
    }
    $runtimeBlockers = @()
    foreach ($blocker in @($runtimePlan.blockers)) {
        if ($blocker -notin @("validate_exact_text_body_custom_assertion_schema_template_and_live", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation")) {
            $runtimeBlockers += $blocker
        }
    }
    $runtimePlan.blockers = @($runtimeBlockers)
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

    $record["manifest_updated"] = $true
    Write-JsonFile -Path $summaryPath -Value $record
}

Write-Output "Deno selected live validation status: $($record["status"])"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $combinedTranscriptPath"

if (-not $validationPassed) {
    exit 1
}
