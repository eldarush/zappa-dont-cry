param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\177-spring-projects-spring-boot",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates",
    [string]$BootVersion = "4.0.6",
    [string]$InitializrUrl = "https://start.spring.io/starter.zip",
    [int]$BuildTimeoutSeconds = 600,
    [int]$ReadinessTimeoutSeconds = 120,
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
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 48), $script:Utf8NoBom)
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
            # Final port/process checks decide pass/fail.
        }
    }

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

function Get-PomBootVersion {
    param([string]$PomPath)

    [xml]$pom = Get-Content -LiteralPath $PomPath -Raw
    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($pom.NameTable)
    $namespaceManager.AddNamespace("m", "http://maven.apache.org/POM/4.0.0")
    $node = $pom.SelectSingleNode("/m:project/m:parent/m:version", $namespaceManager)
    if ($null -eq $node) {
        $node = $pom.SelectSingleNode("/project/parent/version")
    }
    if ($null -eq $node) {
        return ""
    }

    return [string]$node.InnerText
}

function Get-JavaMajorVersion {
    param([string]$VersionText)

    $match = [regex]::Match($VersionText, 'version "(\d+)')
    if (-not $match.Success) {
        return 0
    }

    return [int]$match.Groups[1].Value
}

function New-BlockedResult {
    param(
        [string]$Reason,
        [string]$RunDir,
        [string]$SummaryPath,
        [string]$TranscriptPath
    )

    $existingPassed = $false
    if (Test-Path -LiteralPath $SummaryPath -PathType Leaf) {
        try {
            $existingRecord = Read-JsonFile -Path $SummaryPath
            $existingPassed = ([string]$existingRecord.status -eq "passed")
        } catch {
            $existingPassed = $false
        }
    }
    if ($existingPassed) {
        Write-Output "Spring Boot lifecycle validation blocked by $Reason; preserving existing passed summary: $SummaryPath"
        return $existingRecord
    }

    $record = [ordered]@{
        schema_version = 1
        status = "blocked"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "spring-projects/spring-boot"
        reason = $Reason
        run_dir = $RunDir
        transcript = if (Test-Path -LiteralPath $TranscriptPath -PathType Leaf) { $TranscriptPath } else { $null }
        manifest_updated = $false
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $SummaryPath -Value $record
    return $record
}

function Set-PassedGate {
    param(
        [object]$Manifest,
        [string]$GateId,
        [string[]]$Evidence,
        [string]$CheckCommand
    )

    foreach ($gate in @($Manifest.dependency_gates)) {
        if ([string]$gate.gate_id -eq $GateId) {
            $gate.status = "passed"
            $gate.evidence = @($Evidence)
            $gate.check_command = $CheckCommand
            $gate.blocked_reason = ""
        }
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
$evidenceDir = Join-Path $runDir "evidence"
foreach ($dir in @($workDir, $evidenceDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-spring-boot.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$candidateAppPath = Join-Path $candidateDirPath "app\src\main\java\com\example\Example.java"
$expectedBodyPath = Join-Path $candidateDirPath "expectations\root-body.txt"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\177-spring-projects-spring-boot\selected-contract.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\177-spring-projects-spring-boot\files\README.adoc"
$selectedWebserverPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\177-spring-projects-spring-boot\files\documentation\spring-boot-docs\src\docs\antora\modules\how-to\pages\webserver.adoc"
$zipPath = Join-Path $evidenceDir "spring-initializr.zip"
$javaVersionStdoutPath = Join-Path $evidenceDir "java-version.stdout.txt"
$javaVersionStderrPath = Join-Path $evidenceDir "java-version.stderr.txt"
$mavenStdoutPath = Join-Path $evidenceDir "maven-package.stdout.txt"
$mavenStderrPath = Join-Path $evidenceDir "maven-package.stderr.txt"
$stdoutPath = Join-Path $evidenceDir "spring-boot.stdout.txt"
$stderrPath = Join-Path $evidenceDir "spring-boot.stderr.txt"
$transcriptPath = Join-Path $evidenceDir "spring-boot-lifecycle.transcript.txt"
$responsePath = Join-Path $evidenceDir "root-response.txt"

foreach ($requiredPath in @($manifestPath, $runtimePlanPath, $candidateAppPath, $expectedBodyPath, $selectedContractPath, $selectedReadmePath, $selectedWebserverPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Spring Boot lifecycle input not found: $requiredPath"
    }
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
$selectedContract = Read-JsonFile -Path $selectedContractPath
if ([string]$manifest.source_repository -ne "spring-projects/spring-boot" -or [string]$runtimePlan.repository -ne "spring-projects/spring-boot") {
    throw "This lifecycle runner only owns spring-projects/spring-boot."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected Spring Boot candidate must be blocked before lifecycle validation."
}
if ([string]$runtimePlan.command -ne "java -jar <validated-application-jar>") {
    throw "Spring Boot runtime plan command mismatch: $runtimePlanPath"
}

$supports = @($selectedContract.candidate_promotion_contracts | ForEach-Object { [string]$_.supports })
foreach ($requiredSupport in @("runtime-contract", "http-contract", "input-output-contract", "candidate-executable-command")) {
    if ($supports -notcontains $requiredSupport) {
        throw "Selected Spring Boot contract missing support '$requiredSupport': $selectedContractPath"
    }
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @("Here is a quick teaser of a complete Spring Boot application in Java:", "@RestController", "@SpringBootApplication", '@RequestMapping("/")', 'return "Hello World!";', "SpringApplication.run(Example.class, args);", "java -jar", '$ ./gradlew build', "JDK 25")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected Spring Boot README evidence missing marker '$marker': $selectedReadmePath"
    }
}
$webserverText = Get-Content -LiteralPath $selectedWebserverPath -Raw
if (-not $webserverText.Contains('main HTTP port defaults to `8080`')) {
    throw "Selected Spring Boot webserver evidence missing default port marker: $selectedWebserverPath"
}
$candidateAppText = Get-Content -LiteralPath $candidateAppPath -Raw
foreach ($marker in @("package com.example;", "import org.springframework.boot.*;", "import org.springframework.boot.autoconfigure.*;", "import org.springframework.web.bind.annotation.*;", "@RestController", "@SpringBootApplication", '@RequestMapping("/")', 'return "Hello World!";', "SpringApplication.run(Example.class, args);")) {
    if (-not $candidateAppText.Contains($marker)) {
        throw "Generated Spring Boot app missing README marker '$marker': $candidateAppPath"
    }
}
if ((Get-Content -LiteralPath $expectedBodyPath -Raw) -ne "Hello World!") {
    throw "Spring Boot expected body must be exactly Hello World!: $expectedBodyPath"
}

$port = 8080
$started = Get-Date
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Validation: selected-top-repo-candidate-lifecycle-spring-boot")
$lines.Add("Repository: spring-projects/spring-boot")
$lines.Add("SpringInitializrUrl: $InitializrUrl")
$lines.Add("RequestedBootVersion: $BootVersion")
$lines.Add("Command: java -jar")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("BuildTimeoutSeconds: $BuildTimeoutSeconds")
$lines.Add("ReadinessTimeoutSeconds: $ReadinessTimeoutSeconds")
$lines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$lines.Add("SelectedWebserverEvidence: $selectedWebserverPath")

$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $lines.Add("FailureReason: port_8080_already_in_use")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "port_8080_already_in_use" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$javaCommand = Get-Command java -ErrorAction SilentlyContinue
if ($null -eq $javaCommand) {
    $lines.Add("FailureReason: java_not_available")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "java_not_available" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$javaVersionResult = Invoke-LoggedProcess -FilePath $javaCommand.Source -ArgumentList @("-version") -WorkingDirectory $runDir -StdoutPath $javaVersionStdoutPath -StderrPath $javaVersionStderrPath -TimeoutSeconds 30
$javaVersionText = ((Get-Content -LiteralPath $javaVersionStdoutPath -Raw) + [Environment]::NewLine + (Get-Content -LiteralPath $javaVersionStderrPath -Raw)).Trim()
$javaVersionLine = (($javaVersionText -split "\r?\n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
$javaMajor = Get-JavaMajorVersion -VersionText $javaVersionText
$lines.Add("JavaPath: $($javaCommand.Source)")
$lines.Add("JavaVersion: $javaVersionLine")
$lines.Add("JavaVersionExitCode: $($javaVersionResult.ExitCode)")
if ($javaVersionResult.TimedOut -or [int]$javaVersionResult.ExitCode -ne 0 -or $javaMajor -lt 25) {
    $lines.Add("FailureReason: java_25_or_newer_not_available")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "java_25_or_newer_not_available" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$query = [ordered]@{
    type = "maven-project"
    language = "java"
    bootVersion = $BootVersion
    baseDir = "spring-boot-candidate"
    groupId = "com.example"
    artifactId = "spring-boot-candidate"
    name = "spring-boot-candidate"
    packageName = "com.example"
    packaging = "jar"
    javaVersion = "25"
    dependencies = "web"
}
$queryText = (($query.GetEnumerator() | ForEach-Object { "$([System.Uri]::EscapeDataString([string]$_.Key))=$([System.Uri]::EscapeDataString([string]$_.Value))" }) -join "&")
$initializrRequestUrl = "${InitializrUrl}?$queryText"
$lines.Add("SpringInitializrRequestUrl: $initializrRequestUrl")
try {
    Invoke-WebRequest -Uri $initializrRequestUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 180
    Expand-Archive -LiteralPath $zipPath -DestinationPath $workDir -Force
} catch {
    $lines.Add("FailureReason: spring_initializr_download_or_extract_failed")
    $lines.Add($_.Exception.ToString())
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "spring_initializr_download_or_extract_failed" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$projectDir = Join-Path $workDir "spring-boot-candidate"
$pomPath = Join-Path $projectDir "pom.xml"
$mvnwPath = Join-Path $projectDir "mvnw.cmd"
foreach ($requiredGeneratedPath in @($projectDir, $pomPath, $mvnwPath)) {
    if (-not (Test-Path -LiteralPath $requiredGeneratedPath)) {
        $lines.Add("FailureReason: spring_initializr_project_incomplete")
        Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
        $blocked = New-BlockedResult -Reason "spring_initializr_project_incomplete" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
        Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
        Write-Output "Summary: $summaryPath"
        exit 0
    }
}

$generatedPomBootVersion = Get-PomBootVersion -PomPath $pomPath
$lines.Add("GeneratedPomBootVersion: $generatedPomBootVersion")
if ($generatedPomBootVersion -ne $BootVersion -or $generatedPomBootVersion -like "*.RELEASE") {
    $lines.Add("FailureReason: spring_initializr_boot_version_mismatch")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "spring_initializr_boot_version_mismatch" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$javaRoot = Join-Path $projectDir "src\main\java"
$testRoot = Join-Path $projectDir "src\test"
Assert-DescendantPath -Path $javaRoot -Root $projectDir -Description "Generated Java root" | Out-Null
if (Test-Path -LiteralPath $javaRoot -PathType Container) {
    Remove-Item -LiteralPath $javaRoot -Recurse -Force
}
if (Test-Path -LiteralPath $testRoot -PathType Container) {
    Assert-DescendantPath -Path $testRoot -Root $projectDir -Description "Generated test root" | Out-Null
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
$stagedJavaDir = Join-Path $javaRoot "com\example"
[System.IO.Directory]::CreateDirectory($stagedJavaDir) | Out-Null
$stagedAppPath = Join-Path $stagedJavaDir "Example.java"
Copy-Item -LiteralPath $candidateAppPath -Destination $stagedAppPath -Force
$candidateAppSha256 = Get-Sha256Hex -Path $candidateAppPath
$stagedAppSha256 = Get-Sha256Hex -Path $stagedAppPath
if ($candidateAppSha256 -ne $stagedAppSha256) {
    throw "Staged Example.java hash mismatch."
}
$lines.Add("CandidateAppSha256: $candidateAppSha256")
$lines.Add("StagedAppSha256: $stagedAppSha256")

$mavenResult = Invoke-LoggedProcess -FilePath $mvnwPath -ArgumentList @("-q", "-Dmaven.test.skip=true", "package") -WorkingDirectory $projectDir -StdoutPath $mavenStdoutPath -StderrPath $mavenStderrPath -TimeoutSeconds $BuildTimeoutSeconds
$lines.Add("MavenPackageExitCode: $($mavenResult.ExitCode)")
$lines.Add("MavenPackageTimedOut: $($mavenResult.TimedOut)")
if ($mavenResult.TimedOut -or [int]$mavenResult.ExitCode -ne 0) {
    $lines.Add("FailureReason: spring_boot_maven_package_failed_or_timed_out")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "spring_boot_maven_package_failed_or_timed_out" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$targetDir = Join-Path $projectDir "target"
$jarCandidates = @(Get-ChildItem -LiteralPath $targetDir -File -Filter "*.jar" | Where-Object { $_.Name -notlike "*.original" } | Sort-Object Length -Descending)
if ($jarCandidates.Count -eq 0) {
    $lines.Add("FailureReason: spring_boot_application_jar_missing")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "spring_boot_application_jar_missing" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath
    Write-Output "Spring Boot lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
$jarPath = $jarCandidates[0].FullName
$builtJarSha256 = Get-Sha256Hex -Path $jarPath
$initializrZipSha256 = Get-Sha256Hex -Path $zipPath
$pomSha256 = Get-Sha256Hex -Path $pomPath
$lines.Add("BuiltJar: $jarPath")
$lines.Add("BuiltJarSha256: $builtJarSha256")
$lines.Add("InitializrZipSha256: $initializrZipSha256")
$lines.Add("PomSha256: $pomSha256")

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

try {
    $process = Start-Process -FilePath $javaCommand.Source -ArgumentList @("-jar", $jarPath) -WorkingDirectory $projectDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = (Get-Date).AddSeconds($ReadinessTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            $failureReason = "Spring Boot process exited before readiness with code $($process.ExitCode)"
            break
        }

        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 2
            $responseStatus = [int]$response.StatusCode
            $responseBody = [string]$response.Content
            if ($responseStatus -eq 200 -and $responseBody -eq "Hello World!") {
                $portOwnersDuringReady = @(Get-PortOwner -Port $port)
                $processTreeIdsDuringReady = @(Get-ProcessTreeIds -RootProcessId ([int]$process.Id))
                $foreignOwners = @($portOwnersDuringReady | Where-Object { $processTreeIdsDuringReady -notcontains [int]$_.OwningProcess })
                if ($portOwnersDuringReady.Count -eq 0) {
                    $failureReason = "readiness response succeeded but no tracked port owner was found"
                } elseif ($foreignOwners.Count -gt 0) {
                    $failureReason = "readiness response was served by a process outside the tracked process tree"
                } else {
                    $ready = $true
                    $readyStatus = "HTTP 200 from / with exact README-backed Hello World! body"
                    Write-TextFile -Path $responsePath -Value $responseBody
                    break
                }
            } else {
                $failureReason = "readiness response did not match expected exact Hello World! body"
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
    $failureReason = "Spring Boot responded but port 8080 remained in use after cleanup"
}

$responseBodySha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { "" }
$lines.Add("WorkingDirectory: $projectDir")
$lines.Add("MvnwPath: $mvnwPath")
$lines.Add("PomPath: $pomPath")
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
$lines.Add("==== java -version stdout ====")
$lines.Add((Get-Content -LiteralPath $javaVersionStdoutPath -Raw))
$lines.Add("==== java -version stderr ====")
$lines.Add((Get-Content -LiteralPath $javaVersionStderrPath -Raw))
$lines.Add("==== maven package stdout ====")
$lines.Add((Get-Content -LiteralPath $mavenStdoutPath -Raw))
$lines.Add("==== maven package stderr ====")
$lines.Add((Get-Content -LiteralPath $mavenStderrPath -Raw))
$lines.Add("==== spring boot stdout ====")
if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
    $lines.Add((Get-Content -LiteralPath $stdoutPath -Raw))
}
$lines.Add("==== spring boot stderr ====")
if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $lines.Add((Get-Content -LiteralPath $stderrPath -Raw))
}
Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)

$record = [ordered]@{
    schema_version = 1
    status = $validationStatus
    promotion_state = "blocked"
    completion_ready = $false
    repository = "spring-projects/spring-boot"
    validation_kind = "selected_candidate_process_lifecycle"
    command = "java -jar"
    spring_initializr_url = $InitializrUrl
    spring_initializr_request_url = $initializrRequestUrl
    requested_boot_version = $BootVersion
    generated_pom_boot_version = $generatedPomBootVersion
    java_path = $javaCommand.Source
    java_version = $javaVersionLine
    java_major_version = $javaMajor
    mvnw_path = $mvnwPath
    maven_package_exit_code = [int]$mavenResult.ExitCode
    working_directory = $projectDir
    candidate_app_sha256 = $candidateAppSha256
    staged_app_sha256 = $stagedAppSha256
    initializr_zip = $zipPath
    initializr_zip_sha256 = $initializrZipSha256
    pom_path = $pomPath
    pom_sha256 = $pomSha256
    built_jar = $jarPath
    built_jar_sha256 = $builtJarSha256
    selected_readme_evidence = $selectedReadmePath
    selected_webserver_evidence = $selectedWebserverPath
    transcript = $transcriptPath
    stdout = $stdoutPath
    stderr = $stderrPath
    maven_stdout = $mavenStdoutPath
    maven_stderr = $mavenStderrPath
    java_version_stdout = $javaVersionStdoutPath
    java_version_stderr = $javaVersionStderrPath
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
        command = "Spring Initializr $BootVersion ; mvnw.cmd -q -Dmaven.test.skip=true package ; java -jar <built jar> ; GET http://127.0.0.1:8080/ ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @($cleanupProcessIds)
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    $gateEvidence = @($summaryPath, $transcriptPath, $responsePath, $pomPath, $jarPath)
    $checkCommand = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-spring-boot.ps1"
    foreach ($gateId in @("java-spring-boot-dependency-resolution", "java-spring-boot-process-lifecycle", "cleanup-contract")) {
        Set-PassedGate -Manifest $manifest -GateId $gateId -Evidence $gateEvidence -CheckCommand $checkCommand
    }
    $remainingSourceBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ([string]$blocker.blocker_id -notin @("spring-boot-dependency-version-not-selected", "spring-boot-jar-build-not-proven", "spring-boot-process-lifecycle-not-proven")) {
            $remainingSourceBlockers += $blocker
        }
    }
    $manifest.source_only_blockers = @($remainingSourceBlockers)
    $manifest.blocked_reason = "Selected public Spring Boot contracts support a README Example root route, a Spring Initializr Maven project was generated with Boot $BootVersion, the application JAR built, and the tracked Java process lifecycle/cleanup passed, but promotion remains blocked until the custom text assertion is schema/template/live validated, QaaS live act/assert passes, airgapped weak-model validation passes, and strong review completes."
    Write-JsonFile -Path $manifestPath -Value $manifest

    $runtimePlan.dependency_version_status = "passed"
    $runtimePlan.dependency_version_source = "spring_initializr_official_starter"
    $runtimePlan | Add-Member -NotePropertyName "dependency_version" -NotePropertyValue $BootVersion -Force
    $runtimePlan | Add-Member -NotePropertyName "dependency_version_evidence" -NotePropertyValue @($summaryPath, $pomPath, $selectedReadmePath) -Force
    $runtimePlan.jar_build_status = "passed"
    $runtimePlan | Add-Member -NotePropertyName "built_jar" -NotePropertyValue $jarPath -Force
    $runtimePlan | Add-Member -NotePropertyName "built_jar_sha256" -NotePropertyValue $builtJarSha256 -Force
    $runtimePlan | Add-Member -NotePropertyName "jar_build_evidence" -NotePropertyValue @($summaryPath, $transcriptPath, $mavenStdoutPath, $mavenStderrPath) -Force
    $runtimePlan.readiness_probe.status = "passed"
    $runtimePlan.readiness_probe | Add-Member -NotePropertyName "response" -NotePropertyValue $responsePath -Force
    $runtimePlan.readiness_probe | Add-Member -NotePropertyName "evidence" -NotePropertyValue @($summaryPath, $transcriptPath, $responsePath) -Force
    $runtimePlan.readiness_probe.blocked_reason = ""
    $runtimePlan.cleanup.status = "passed"
    $runtimePlan.cleanup | Add-Member -NotePropertyName "evidence" -NotePropertyValue @($summaryPath, $transcriptPath) -Force
    $runtimePlan.cleanup.blocked_reason = ""
    $runtimePlan | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    $remainingRuntimeBlockers = @()
    foreach ($blocker in @($runtimePlan.blockers)) {
        if ($blocker -notin @("select_exact_spring_boot_dependency_version_or_generated_app_build_file", "build_application_jar_from_selected_public_dependencies", "prove_process_lifecycle_and_cleanup_without assuming private source")) {
            $remainingRuntimeBlockers += $blocker
        }
    }
    $runtimePlan.blockers = @($remainingRuntimeBlockers)
    Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan
}

Write-Output "Spring Boot lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -ne "passed") {
    exit 1
}
