param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\243-expressjs-express",
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
        [int]$Major
    )

    $normalized = $ActualVersion.Trim().TrimStart("v")
    $parts = @($normalized.Split(".") | ForEach-Object { [int]$_ })
    return ($parts.Count -ge 1 -and $parts[0] -ge $Major)
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
        repository = "expressjs/express"
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
$appWorkDir = Join-Path $workDir "app"
$evidenceDir = Join-Path $runDir "evidence"
foreach ($dir in @($appWorkDir, $evidenceDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$coverageDir = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-express.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$appPath = Join-Path $candidateDirPath "app\app.mjs"
$expectedBodyPath = Join-Path $candidateDirPath "expectations\root-body.txt"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\243-expressjs-express\selected-contract.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\243-expressjs-express\files\Readme.md"
$selectedExamplePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\243-expressjs-express\files\examples\hello-world\index.js"
$selectedAcceptancePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\243-expressjs-express\files\test\acceptance\hello-world.js"
$selectedPackagePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\243-expressjs-express\files\package.json"
$stagedAppPath = Join-Path $appWorkDir "app.mjs"
$stagedPackageJsonPath = Join-Path $appWorkDir "package.json"
$packageLockPath = Join-Path $appWorkDir "package-lock.json"
$installedExpressPackagePath = Join-Path $appWorkDir "node_modules\express\package.json"
$npmInstallStdoutPath = Join-Path $evidenceDir "npm-install.stdout.txt"
$npmInstallStderrPath = Join-Path $evidenceDir "npm-install.stderr.txt"
$stdoutPath = Join-Path $evidenceDir "express.stdout.txt"
$stderrPath = Join-Path $evidenceDir "express.stderr.txt"
$transcriptPath = Join-Path $evidenceDir "express-lifecycle.transcript.txt"
$responsePath = Join-Path $evidenceDir "root-response.txt"

foreach ($requiredPath in @($manifestPath, $runtimePlanPath, $appPath, $expectedBodyPath, $selectedContractPath, $selectedReadmePath, $selectedExamplePath, $selectedAcceptancePath, $selectedPackagePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Express lifecycle input not found: $requiredPath"
    }
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
$selectedContract = Read-JsonFile -Path $selectedContractPath
$selectedPackage = Read-JsonFile -Path $selectedPackagePath
if ([string]$manifest.source_repository -ne "expressjs/express" -or [string]$runtimePlan.repository -ne "expressjs/express") {
    throw "This lifecycle runner only owns expressjs/express."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected candidate must be blocked before lifecycle validation."
}
if ([string]$runtimePlan.command -ne "node app.mjs" -or [string]$runtimePlan.install_command -ne "npm install express") {
    throw "Express runtime plan command/install command mismatch: $runtimePlanPath"
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @("import express from 'express'", "const app = express()", "app.get('/', (req, res) => {", "res.send('Hello World')", "app.listen(3000", "http://localhost:3000", "npm install express")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected README evidence missing marker '$marker': $selectedReadmePath"
    }
}
$exampleText = Get-Content -LiteralPath $selectedExamplePath -Raw
foreach ($marker in @("var express = require('../../');", "app.get('/', function(req, res){", "res.send('Hello World');", "app.listen(3000);")) {
if (-not $exampleText.Contains($marker)) {
        throw "Selected hello-world example evidence missing marker '$marker': $selectedExamplePath"
    }
}
$acceptanceText = Get-Content -LiteralPath $selectedAcceptancePath -Raw
foreach ($marker in @("describe('hello-world'", "GET /", ".expect(200, 'Hello World', done)")) {
    if (-not $acceptanceText.Contains($marker)) {
        throw "Selected hello-world acceptance evidence missing marker '$marker': $selectedAcceptancePath"
    }
}
$selectedPackageEvidence = @($selectedContract.selected_public_contracts | Where-Object { [string]$_.source_path -eq "package.json" } | Select-Object -First 1)
if ($selectedPackageEvidence.Count -eq 0 -or [string]$selectedPackageEvidence[0].local_path -ne $selectedPackagePath) {
    throw "Selected contract package evidence mismatch: $selectedContractPath"
}
$packageVersion = [string]$selectedPackage.version
if ([string]::IsNullOrWhiteSpace($packageVersion)) {
    throw "Selected package evidence lacks version: $selectedPackagePath"
}
$packageSpec = "express@$packageVersion"
$expectedBody = Get-Content -LiteralPath $expectedBodyPath -Raw
if ($expectedBody -ne "Hello World") {
    throw "Express expected body must be exactly Hello World: $expectedBodyPath"
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
if ($null -eq $npmCommand) {
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
}
if ($null -eq $nodeCommand -or $null -eq $npmCommand) {
    $blocked = New-BlockedResult -Reason "node_or_npm_not_available" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Express lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}
$nodeVersion = & node --version
$npmVersion = & npm --version
$nodeMajorVersionAtLeast18 = Test-NodeVersionAtLeast -ActualVersion $nodeVersion -Major 18
if (-not $nodeMajorVersionAtLeast18) {
    $blocked = New-BlockedResult -Reason "node_version_below_express_readme_runtime_floor" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Express lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 3000
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $blocked = New-BlockedResult -Reason "port_3000_already_in_use" -RunDir $runDir -SummaryPath $summaryPath
    Write-Output "Express lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

Copy-Item -LiteralPath $appPath -Destination $stagedAppPath -Force
$candidateAppSha256 = Get-Sha256Hex -Path $appPath
$stagedAppSha256 = Get-Sha256Hex -Path $stagedAppPath
if ($candidateAppSha256 -ne $stagedAppSha256) {
    throw "Staged app.mjs hash mismatch."
}
Write-TextFile -Path $stagedPackageJsonPath -Value (@(
        "{",
        '  "private": true,',
        '  "type": "module"',
        "}"
    ) -join [Environment]::NewLine)

$npmInstall = Start-Process -FilePath $npmCommand.Source -ArgumentList @("install", $packageSpec) -WorkingDirectory $appWorkDir -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $npmInstallStdoutPath -RedirectStandardError $npmInstallStderrPath
if ($npmInstall.ExitCode -ne 0) {
    throw "npm install $packageSpec failed with exit code $($npmInstall.ExitCode); see $npmInstallStdoutPath and $npmInstallStderrPath"
}
if (-not (Test-Path -LiteralPath $packageLockPath -PathType Leaf)) {
    throw "npm install express did not create package-lock.json: $packageLockPath"
}
if (-not (Test-Path -LiteralPath $installedExpressPackagePath -PathType Leaf)) {
    throw "npm install express did not create installed Express package evidence: $installedExpressPackagePath"
}
$stagedPackage = Read-JsonFile -Path $stagedPackageJsonPath
$installedExpressPackage = Read-JsonFile -Path $installedExpressPackagePath
$installedExpressName = [string]$installedExpressPackage.name
$installedExpressVersion = [string]$installedExpressPackage.version
if ([string]::IsNullOrWhiteSpace($installedExpressVersion)) {
    throw "Installed Express package evidence lacks version: $installedExpressPackagePath"
}
if ($installedExpressName -ne "express" -or $installedExpressVersion -ne $packageVersion) {
    throw "Installed Express package mismatch; expected $packageSpec, got ${installedExpressName}@$installedExpressVersion"
}
$expressPackageAvailable = $true
$packageLockSha256 = Get-Sha256Hex -Path $packageLockPath
$stagedPackageJsonSha256 = Get-Sha256Hex -Path $stagedPackageJsonPath
$installedExpressPackageSha256 = Get-Sha256Hex -Path $installedExpressPackagePath
$stagedDependencyValue = [string]$stagedPackage.dependencies.express
if ([string]::IsNullOrWhiteSpace($stagedDependencyValue)) {
    throw "npm install express did not record express dependency in staged package.json: $stagedPackageJsonPath"
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
    $process = Start-Process -FilePath $nodeCommand.Source -ArgumentList @("app.mjs") -WorkingDirectory $appWorkDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            $failureReason = "Express process exited before readiness with code $($process.ExitCode)"
            break
        }

        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 2
            $responseStatus = [int]$response.StatusCode
            $responseBody = [string]$response.Content
            if ($responseStatus -eq 200 -and $responseBody -eq "Hello World") {
                $portOwnersDuringReady = @(Get-PortOwner -Port $port)
                $processTreeIdsDuringReady = @(Get-ProcessTreeIds -RootProcessId ([int]$process.Id))
                $foreignOwners = @($portOwnersDuringReady | Where-Object { $processTreeIdsDuringReady -notcontains [int]$_.OwningProcess })
                if ($portOwnersDuringReady.Count -eq 0) {
                    $failureReason = "readiness response succeeded but no tracked port owner was found"
                } elseif ($foreignOwners.Count -gt 0) {
                    $failureReason = "readiness response was served by a process outside the tracked process tree"
                } else {
                    $ready = $true
                    $readyStatus = "HTTP 200 from / with README-backed exact Hello World body"
                    Write-TextFile -Path $responsePath -Value $responseBody
                    break
                }
            }

            $failureReason = "readiness response did not match expected exact Hello World body"
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
    $failureReason = "Express responded but port 3000 remained in use after cleanup"
}

$responseBodySha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { "" }
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Validation: selected-top-repo-candidate-lifecycle-express")
$lines.Add("Repository: expressjs/express")
$lines.Add("InstallCommand: npm install express")
$lines.Add("Command: node app.mjs")
$lines.Add("WorkingDirectory: $appWorkDir")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("TimeoutSeconds: $TimeoutSeconds")
$lines.Add("NodeVersion: $nodeVersion")
$lines.Add("NpmVersion: $npmVersion")
$lines.Add("NpmPath: $($npmCommand.Source)")
$lines.Add("NodePath: $($nodeCommand.Source)")
$lines.Add("NodeMajorVersionAtLeast18: $nodeMajorVersionAtLeast18")
$lines.Add("InstallExecutionCommand: npm install $packageSpec")
$lines.Add("NpmInstallExitCode: $($npmInstall.ExitCode)")
$lines.Add("PackageSpec: $packageSpec")
$lines.Add("ExpressPackageAvailable: $expressPackageAvailable")
$lines.Add("InstalledExpressVersion: $installedExpressVersion")
$lines.Add("InstalledExpressPackage: $installedExpressPackagePath")
$lines.Add("StagedPackageDependencyValue: $stagedDependencyValue")
$lines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$lines.Add("SelectedExampleEvidence: $selectedExamplePath")
$lines.Add("SelectedAcceptanceEvidence: $selectedAcceptancePath")
$lines.Add("SelectedPackageEvidence: $selectedPackagePath")
$lines.Add("CandidateAppSha256: $candidateAppSha256")
$lines.Add("StagedAppSha256: $stagedAppSha256")
$lines.Add("StagedPackageJsonSha256: $stagedPackageJsonSha256")
$lines.Add("PackageLockSha256: $packageLockSha256")
$lines.Add("InstalledExpressPackageSha256: $installedExpressPackageSha256")
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
$lines.Add("==== npm install stdout ====")
if (Test-Path -LiteralPath $npmInstallStdoutPath -PathType Leaf) {
    $lines.Add((Get-Content -LiteralPath $npmInstallStdoutPath -Raw))
}
$lines.Add("==== npm install stderr ====")
if (Test-Path -LiteralPath $npmInstallStderrPath -PathType Leaf) {
    $lines.Add((Get-Content -LiteralPath $npmInstallStderrPath -Raw))
}
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
    repository = "expressjs/express"
    validation_kind = "selected_candidate_process_lifecycle"
    command = "node app.mjs"
    install_command = "npm install express"
    install_execution_command = "npm install $packageSpec"
    npm_install_exit_code = $npmInstall.ExitCode
    package_spec = $packageSpec
    installed_express_version = $installedExpressVersion
    express_package_available = $expressPackageAvailable
    node_version = $nodeVersion
    npm_version = $npmVersion
    node_path = $nodeCommand.Source
    npm_path = $npmCommand.Source
    node_major_version_at_least_18 = $nodeMajorVersionAtLeast18
    working_directory = $appWorkDir
    candidate_app_sha256 = $candidateAppSha256
    staged_app_sha256 = $stagedAppSha256
    staged_package_json_sha256 = $stagedPackageJsonSha256
    package_lock_sha256 = $packageLockSha256
    installed_express_package_sha256 = $installedExpressPackageSha256
    selected_readme_evidence = $selectedReadmePath
    selected_example_evidence = $selectedExamplePath
    selected_acceptance_evidence = $selectedAcceptancePath
    selected_package_evidence = $selectedPackagePath
    staged_package_json = $stagedPackageJsonPath
    package_lock = $packageLockPath
    installed_express_package = $installedExpressPackagePath
    npm_install_stdout = $npmInstallStdoutPath
    npm_install_stderr = $npmInstallStderrPath
    transcript = $transcriptPath
    stdout = $stdoutPath
    stderr = $stderrPath
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
        command = "npm install express ; node app.mjs ; GET http://127.0.0.1:3000/ ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        cleanup_process_ids = @($cleanupProcessIds)
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -in @("node-express-process-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-express.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -ne "express-process-lifecycle-not-proven") {
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

Write-Output "Express lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -ne "passed") {
    exit 1
}
