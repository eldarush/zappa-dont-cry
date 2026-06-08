param(
    [string]$CandidateDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates\138-gin-gonic-gin",
    [string]$OutRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates",
    [string]$ManagedToolchainRoot = "D:\QaaS\_tmp\zappa-dont-cry\toolchains\go",
    [string]$GoVersion = "go1.26.4",
    [string]$GoArchiveSha256 = "3ca8fb4630b07c419cbdd51f754e31363cfcfb83b3a5354d9e895c90be2cc345",
    [string]$GoDownloadUrl = "https://go.dev/dl/go1.26.4.windows-amd64.zip",
    [string]$GinModulePin = "github.com/gin-gonic/gin@v1.12.0",
    [int]$TimeoutSeconds = 240,
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

function Get-OfficialGoFileName {
    param(
        [string]$Version,
        [string]$DownloadUrl
    )

    $fileName = [System.IO.Path]::GetFileName(([System.Uri]$DownloadUrl).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($fileName) -or -not $fileName.StartsWith($Version, [System.StringComparison]::Ordinal)) {
        throw "GoDownloadUrl filename must start with ${Version}: $DownloadUrl"
    }

    return $fileName
}

function Get-ManagedGoToolchain {
    param(
        [string]$ToolchainRoot,
        [string]$Version,
        [string]$DownloadUrl,
        [string]$ExpectedSha256,
        [string]$RunDir
    )

    $allowedToolchainRoot = "D:\QaaS\_tmp\zappa-dont-cry\toolchains"
    $rootPath = Assert-DescendantPath -Path $ToolchainRoot -Root $allowedToolchainRoot -Description "ManagedToolchainRoot"
    [System.IO.Directory]::CreateDirectory($rootPath) | Out-Null

    $fileName = Get-OfficialGoFileName -Version $Version -DownloadUrl $DownloadUrl
    $archiveDir = Join-Path $rootPath "archives"
    [System.IO.Directory]::CreateDirectory($archiveDir) | Out-Null
    $archivePath = Join-Path $archiveDir $fileName
    $installDir = Join-Path $rootPath "$Version-windows-amd64"
    $goPath = Join-Path $installDir "go\bin\go.exe"

    $downloaded = $false
    if (-not (Test-Path -LiteralPath $goPath -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $archivePath -UseBasicParsing -TimeoutSec 120
            $downloaded = $true
        }

        $actualSha256 = Get-Sha256Hex -Path $archivePath
        if (-not [string]::Equals($actualSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Managed Go archive SHA-256 mismatch for $archivePath. Expected $ExpectedSha256, got $actualSha256."
        }

        if (Test-Path -LiteralPath $installDir -PathType Container) {
            throw "Managed Go install directory exists without go.exe: $installDir"
        }

        $extractRoot = Join-Path $RunDir "go-extract"
        [System.IO.Directory]::CreateDirectory($extractRoot) | Out-Null
        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        if ($null -ne $tar) {
            & $tar.Source -xf $archivePath -C $extractRoot
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe failed to extract managed Go archive $archivePath with exit code $LASTEXITCODE."
            }
        } else {
            Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
        }
        $extractedGoDir = Join-Path $extractRoot "go"
        if (-not (Test-Path -LiteralPath (Join-Path $extractedGoDir "bin\go.exe") -PathType Leaf)) {
            throw "Expanded Go archive did not contain go\bin\go.exe: $archivePath"
        }
        [System.IO.Directory]::CreateDirectory($installDir) | Out-Null
        Move-Item -LiteralPath $extractedGoDir -Destination $installDir
    }

    $archiveSha256 = Get-Sha256Hex -Path $archivePath
    if (-not [string]::Equals($archiveSha256, $ExpectedSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed Go archive SHA-256 mismatch for $archivePath. Expected $ExpectedSha256, got $archiveSha256."
    }
    if (-not (Test-Path -LiteralPath $goPath -PathType Leaf)) {
        throw "Managed Go executable not found after setup: $goPath"
    }

    return [pscustomobject]@{
        GoPath = $goPath
        Source = "managed_go_toolchain"
        ToolchainRoot = $rootPath
        InstallDir = $installDir
        ArchivePath = $archivePath
        DownloadUrl = $DownloadUrl
        Version = $Version
        ArchiveSha256 = $archiveSha256
        Downloaded = $downloaded
    }
}

function Test-GoVersionAtLeast {
    param(
        [string]$GoVersionOutput,
        [int]$Major,
        [int]$Minor,
        [int]$Patch
    )

    $match = [regex]::Match($GoVersionOutput, 'go(?<major>\d+)\.(?<minor>\d+)(\.(?<patch>\d+))?')
    if (-not $match.Success) {
        return $false
    }

    $actualMajor = [int]$match.Groups["major"].Value
    $actualMinor = [int]$match.Groups["minor"].Value
    $actualPatch = if ($match.Groups["patch"].Success) { [int]$match.Groups["patch"].Value } else { 0 }
    if ($actualMajor -gt $Major) { return $true }
    if ($actualMajor -lt $Major) { return $false }
    if ($actualMinor -gt $Minor) { return $true }
    if ($actualMinor -lt $Minor) { return $false }
    return ($actualPatch -ge $Patch)
}

function Invoke-CapturedProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath,
        [int]$TimeoutSeconds
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -PassThru -WindowStyle Hidden -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $exited = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $exited) {
        Stop-ProcessTree -RootProcessId ([int]$process.Id) | Out-Null
        return [pscustomobject]@{
            ExitCode = -1
            TimedOut = $true
            ProcessId = [int]$process.Id
        }
    }

    return [pscustomobject]@{
        ExitCode = [int]$process.ExitCode
        TimedOut = $false
        ProcessId = [int]$process.Id
    }
}

function New-BlockedResult {
    param(
        [string]$Reason,
        [string]$RunDir,
        [string]$SummaryPath,
        [string]$TranscriptPath,
        [string]$GoPath,
        [string]$GoVersionOutput
    )

    $record = [ordered]@{
        schema_version = 1
        status = "blocked"
        promotion_state = "blocked"
        completion_ready = $false
        repository = "gin-gonic/gin"
        reason = $Reason
        go_path = $GoPath
        go_version = $GoVersionOutput
        module_resolution_passed = $false
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
$summaryPath = Join-Path $coverageDir "selected-top-repo-candidate-lifecycle-gin.json"
$manifestPath = Join-Path $candidateDirPath "qaas-artifact-manifest.json"
$runtimePlanPath = Join-Path $candidateDirPath "candidate-runtime-plan.json"
$candidateAppPath = Join-Path $candidateDirPath "app\main.go"
$selectedContractPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\138-gin-gonic-gin\selected-contract.json"
$selectedReadmePath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\138-gin-gonic-gin\files\README.md"
$selectedGoModPath = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts\138-gin-gonic-gin\files\go.mod"
$stdoutPath = Join-Path $evidenceDir "gin.stdout.txt"
$stderrPath = Join-Path $evidenceDir "gin.stderr.txt"
$goEnvJsonPath = Join-Path $evidenceDir "go-env.json"
$goEnvStderrPath = Join-Path $evidenceDir "go-env.stderr.txt"
$goModInitStdoutPath = Join-Path $evidenceDir "go-mod-init.stdout.txt"
$goModInitStderrPath = Join-Path $evidenceDir "go-mod-init.stderr.txt"
$goModulePinStdoutPath = Join-Path $evidenceDir "go-module-pin.stdout.txt"
$goModulePinStderrPath = Join-Path $evidenceDir "go-module-pin.stderr.txt"
$goModDownloadStdoutPath = Join-Path $evidenceDir "go-mod-download.stdout.txt"
$goModDownloadStderrPath = Join-Path $evidenceDir "go-mod-download.stderr.txt"
$goListModuleJsonPath = Join-Path $evidenceDir "go-list-gin-module.json"
$goListModuleStderrPath = Join-Path $evidenceDir "go-list-gin-module.stderr.txt"
$transcriptPath = Join-Path $evidenceDir "gin-lifecycle.transcript.txt"
$responsePath = Join-Path $evidenceDir "ping-response.json"

foreach ($requiredPath in @($manifestPath, $runtimePlanPath, $candidateAppPath, $selectedContractPath, $selectedReadmePath, $selectedGoModPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Gin lifecycle input not found: $requiredPath"
    }
}

$manifest = Read-JsonFile -Path $manifestPath
$runtimePlan = Read-JsonFile -Path $runtimePlanPath
if ([string]$manifest.source_repository -ne "gin-gonic/gin" -or [string]$runtimePlan.repository -ne "gin-gonic/gin") {
    throw "This lifecycle runner only owns gin-gonic/gin."
}
if ([string]$manifest.promotion_state -ne "blocked" -or [string]$runtimePlan.promotion_state -ne "blocked") {
    throw "Selected Gin candidate must be blocked before lifecycle validation."
}

$readmeText = Get-Content -LiteralPath $selectedReadmePath -Raw
foreach ($marker in @("Go version", "go run main.go", "http://localhost:8080/ping", '"message": "pong"', 'r.GET("/ping"', "github.com/gin-gonic/gin")) {
    if (-not $readmeText.Contains($marker)) {
        throw "Selected Gin README evidence missing marker '$marker': $selectedReadmePath"
    }
}

$goModText = Get-Content -LiteralPath $selectedGoModPath -Raw
foreach ($marker in @("module github.com/gin-gonic/gin", "go 1.25.0")) {
    if (-not $goModText.Contains($marker)) {
        throw "Selected Gin go.mod evidence missing marker '$marker': $selectedGoModPath"
    }
}

$appText = Get-Content -LiteralPath $candidateAppPath -Raw
foreach ($marker in @("package main", "github.com/gin-gonic/gin", 'r.GET("/ping"', '"message": "pong"', "r.Run()")) {
    if (-not $appText.Contains($marker)) {
        throw "Generated Gin app missing README marker '$marker': $candidateAppPath"
    }
}

$stagedAppPath = Join-Path $workDir "main.go"
Copy-Item -LiteralPath $candidateAppPath -Destination $stagedAppPath -Force
$candidateAppSha256 = Get-Sha256Hex -Path $candidateAppPath
$stagedAppSha256 = Get-Sha256Hex -Path $stagedAppPath
if ($candidateAppSha256 -ne $stagedAppSha256) {
    throw "Staged main.go hash mismatch."
}

$goCommand = Get-Command go -ErrorAction SilentlyContinue
$goPath = if ($null -ne $goCommand) { $goCommand.Source } else { $null }
$goSource = if ($null -ne $goCommand) { "global_path" } else { "not_found" }
$managedGo = $null
$goVersionOutput = ""
$moduleInit = $null
$moduleGet = $null
$moduleDownload = $null
$moduleList = $null
$moduleResolutionPassed = $false
$started = Get-Date
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Validation: selected-top-repo-candidate-lifecycle-gin")
$lines.Add("Repository: gin-gonic/gin")
$lines.Add("Command: go run main.go")
$lines.Add("WorkingDirectory: $workDir")
$lines.Add("Started: $($started.ToString('o'))")
$lines.Add("TimeoutSeconds: $TimeoutSeconds")
$lines.Add("SelectedReadmeEvidence: $selectedReadmePath")
$lines.Add("SelectedGoModEvidence: $selectedGoModPath")
$lines.Add("CandidateAppSha256: $candidateAppSha256")
$lines.Add("StagedAppSha256: $stagedAppSha256")
$lines.Add("GinModulePin: $GinModulePin")

if ($null -ne $goCommand) {
    $goVersionOutput = (& $goCommand.Source version | Out-String).Trim()
}

if ($null -eq $goCommand -or -not (Test-GoVersionAtLeast -GoVersionOutput $goVersionOutput -Major 1 -Minor 25 -Patch 0)) {
    try {
        if ($null -eq $goCommand) {
            $lines.Add("GlobalGoPath: not found")
            $lines.Add("GlobalGoVersion: ")
        } else {
            $lines.Add("GlobalGoPath: $($goCommand.Source)")
            $lines.Add("GlobalGoVersion: $goVersionOutput")
        }
        $managedGo = Get-ManagedGoToolchain -ToolchainRoot $ManagedToolchainRoot -Version $GoVersion -DownloadUrl $GoDownloadUrl -ExpectedSha256 $GoArchiveSha256 -RunDir $runDir
        $goPath = [string]$managedGo.GoPath
        $goSource = [string]$managedGo.Source
        $goVersionOutput = (& $goPath version | Out-String).Trim()
    } catch {
        $lines.Add("ManagedGoToolchainSetup: failed")
        $lines.Add("ManagedGoToolchainError: $($_.Exception.Message)")
        $lines.Add("FailureReason: managed_go_toolchain_not_available")
        Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
        $blocked = New-BlockedResult -Reason "managed_go_toolchain_not_available" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -GoPath $goPath -GoVersionOutput $goVersionOutput
        Write-Output "Gin lifecycle validation blocked: $($blocked.reason)"
        Write-Output "Summary: $summaryPath"
        exit 0
    }
}

$lines.Add("GoSource: $goSource")
$lines.Add("GoPath: $goPath")
$lines.Add("GoVersion: $goVersionOutput")
if ($null -ne $managedGo) {
    $lines.Add("ManagedGoToolchainRoot: $($managedGo.ToolchainRoot)")
    $lines.Add("ManagedGoInstallDir: $($managedGo.InstallDir)")
    $lines.Add("ManagedGoArchive: $($managedGo.ArchivePath)")
    $lines.Add("ManagedGoDownloadUrl: $($managedGo.DownloadUrl)")
    $lines.Add("ManagedGoArchiveSha256: $($managedGo.ArchiveSha256)")
    $lines.Add("ManagedGoDownloaded: $($managedGo.Downloaded)")
}
if (-not (Test-GoVersionAtLeast -GoVersionOutput $goVersionOutput -Major 1 -Minor 25 -Patch 0)) {
    $lines.Add("FailureReason: go_version_below_selected_go_mod")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "go_version_below_selected_go_mod" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -GoPath $goPath -GoVersionOutput $goVersionOutput
    Write-Output "Gin lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$goRoot = if ($null -ne $managedGo) { Join-Path ([string]$managedGo.InstallDir) "go" } else { (& $goPath env GOROOT | Out-String).Trim() }
$goEnvRoot = Join-Path $runDir "go-env"
$managedGoPath = Join-Path $goEnvRoot "gopath"
$managedGoModCache = Join-Path $goEnvRoot "gomodcache"
$managedGoCache = Join-Path $goEnvRoot "gocache"
foreach ($dir in @($managedGoPath, $managedGoModCache, $managedGoCache)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}
$env:GOROOT = $goRoot
$env:GOPATH = $managedGoPath
$env:GOMODCACHE = $managedGoModCache
$env:GOCACHE = $managedGoCache
$lines.Add("GoRoot: $goRoot")
$lines.Add("ManagedGoPath: $managedGoPath")
$lines.Add("ManagedGoModCache: $managedGoModCache")
$lines.Add("ManagedGoCache: $managedGoCache")

$goEnv = Invoke-CapturedProcess -FilePath $goPath -Arguments @("env", "-json") -WorkingDirectory $workDir -StdoutPath $goEnvJsonPath -StderrPath $goEnvStderrPath -TimeoutSeconds $TimeoutSeconds
$lines.Add("GoEnvCommand: go env -json")
$lines.Add("GoEnvExitCode: $($goEnv.ExitCode)")
if ($goEnv.ExitCode -ne 0) {
    $lines.Add("FailureReason: go_env_not_available")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "go_env_not_available" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -GoPath $goPath -GoVersionOutput $goVersionOutput
    Write-Output "Gin lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$moduleInit = Invoke-CapturedProcess -FilePath $goPath -Arguments @("mod", "init", "zappa.local/gin-lifecycle") -WorkingDirectory $workDir -StdoutPath $goModInitStdoutPath -StderrPath $goModInitStderrPath -TimeoutSeconds $TimeoutSeconds
$lines.Add("ModuleInitCommand: go mod init zappa.local/gin-lifecycle")
$lines.Add("ModuleInitExitCode: $($moduleInit.ExitCode)")
$moduleGet = Invoke-CapturedProcess -FilePath $goPath -Arguments @("get", $GinModulePin) -WorkingDirectory $workDir -StdoutPath $goModulePinStdoutPath -StderrPath $goModulePinStderrPath -TimeoutSeconds $TimeoutSeconds
$lines.Add("ModulePinCommand: go get $GinModulePin")
$lines.Add("ModulePinExitCode: $($moduleGet.ExitCode)")
$moduleDownload = Invoke-CapturedProcess -FilePath $goPath -Arguments @("mod", "download") -WorkingDirectory $workDir -StdoutPath $goModDownloadStdoutPath -StderrPath $goModDownloadStderrPath -TimeoutSeconds $TimeoutSeconds
$lines.Add("ModuleDownloadCommand: go mod download")
$lines.Add("ModuleDownloadExitCode: $($moduleDownload.ExitCode)")
$moduleList = Invoke-CapturedProcess -FilePath $goPath -Arguments @("list", "-m", "-json", "github.com/gin-gonic/gin") -WorkingDirectory $workDir -StdoutPath $goListModuleJsonPath -StderrPath $goListModuleStderrPath -TimeoutSeconds $TimeoutSeconds
$lines.Add("ModuleListCommand: go list -m -json github.com/gin-gonic/gin")
$lines.Add("ModuleListExitCode: $($moduleList.ExitCode)")
$moduleResolutionPassed = ($moduleInit.ExitCode -eq 0 -and $moduleGet.ExitCode -eq 0 -and $moduleDownload.ExitCode -eq 0 -and $moduleList.ExitCode -eq 0)
$lines.Add("ModuleResolutionPassed: $moduleResolutionPassed")
if (-not $moduleResolutionPassed) {
    $lines.Add("FailureReason: go_module_resolution_not_available")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "go_module_resolution_not_available" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -GoPath $goPath -GoVersionOutput $goVersionOutput
    Write-Output "Gin lifecycle validation blocked: $($blocked.reason)"
    Write-Output "Summary: $summaryPath"
    exit 0
}

$port = 8080
$preExistingPortOwners = @(Get-PortOwner -Port $port)
if ($preExistingPortOwners.Count -gt 0) {
    $lines.Add("FailureReason: port_8080_already_in_use")
    Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)
    $blocked = New-BlockedResult -Reason "port_8080_already_in_use" -RunDir $runDir -SummaryPath $summaryPath -TranscriptPath $transcriptPath -GoPath $goPath -GoVersionOutput $goVersionOutput
    Write-Output "Gin lifecycle validation blocked: $($blocked.reason)"
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

try {
    $lines.Add("RunCommand: go run -mod=readonly main.go")
    $process = Start-Process -FilePath $goPath -ArgumentList @("run", "-mod=readonly", "main.go") -WorkingDirectory $workDir -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            $failureReason = "Gin go run process exited before readiness with code $($process.ExitCode)"
            break
        }

        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/ping" -UseBasicParsing -TimeoutSec 2
            $responseStatus = [int]$response.StatusCode
            $responseBody = [string]$response.Content
            $json = $responseBody | ConvertFrom-Json
            $propertyNames = @($json.PSObject.Properties.Name)
            if ($responseStatus -eq 200 -and $propertyNames.Count -eq 1 -and ($propertyNames -contains "message") -and [string]$json.message -eq "pong") {
                $portOwnersDuringReady = @(Get-PortOwner -Port $port)
                $processTreeIdsDuringReady = @(Get-ProcessTreeIds -RootProcessId ([int]$process.Id))
                $foreignOwners = @($portOwnersDuringReady | Where-Object { $processTreeIdsDuringReady -notcontains [int]$_.OwningProcess })
                if ($portOwnersDuringReady.Count -eq 0) {
                    $failureReason = "readiness response succeeded but no tracked port owner was found"
                } elseif ($foreignOwners.Count -gt 0) {
                    $failureReason = "readiness response was served by a process outside the tracked process tree"
                } else {
                    $ready = $true
                    $readyStatus = "HTTP 200 from /ping with exact README-backed JSON body"
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
        $failureReason = "timed out waiting for /ping"
    }
} finally {
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
    $failureReason = "Gin responded but port 8080 remained in use after cleanup"
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
$lines.Add("==== go mod init stdout ====")
$lines.Add((Get-Content -LiteralPath $goModInitStdoutPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== go mod init stderr ====")
$lines.Add((Get-Content -LiteralPath $goModInitStderrPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== go module pin stdout ====")
$lines.Add((Get-Content -LiteralPath $goModulePinStdoutPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== go module pin stderr ====")
$lines.Add((Get-Content -LiteralPath $goModulePinStderrPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== go mod download stdout ====")
$lines.Add((Get-Content -LiteralPath $goModDownloadStdoutPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== go mod download stderr ====")
$lines.Add((Get-Content -LiteralPath $goModDownloadStderrPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== go list module json ====")
$lines.Add((Get-Content -LiteralPath $goListModuleJsonPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== go list module stderr ====")
$lines.Add((Get-Content -LiteralPath $goListModuleStderrPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== stdout ====")
$lines.Add((Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue))
$lines.Add("==== stderr ====")
$lines.Add((Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue))
Write-TextFile -Path $transcriptPath -Value ($lines -join [Environment]::NewLine)

$goModPath = Join-Path $workDir "go.mod"
$goSumPath = Join-Path $workDir "go.sum"
$goModSha256 = if (Test-Path -LiteralPath $goModPath -PathType Leaf) { Get-Sha256Hex -Path $goModPath } else { "" }
$goSumSha256 = if (Test-Path -LiteralPath $goSumPath -PathType Leaf) { Get-Sha256Hex -Path $goSumPath } else { "" }

$record = [ordered]@{
    schema_version = 1
    status = $validationStatus
    promotion_state = "blocked"
    completion_ready = $false
    repository = "gin-gonic/gin"
    validation_kind = "selected_candidate_process_lifecycle"
    command = "go run main.go"
    module_init_command = "go mod init zappa.local/gin-lifecycle"
    module_pin_command = "go get $GinModulePin"
    module_download_command = "go mod download"
    module_list_command = "go list -m -json github.com/gin-gonic/gin"
    module_pin = $GinModulePin
    go_source = $goSource
    go_path = $goPath
    go_version = $goVersionOutput
    go_root = $goRoot
    go_env_json = $goEnvJsonPath
    managed_gopath = $managedGoPath
    managed_gomodcache = $managedGoModCache
    managed_gocache = $managedGoCache
    managed_toolchain_root = if ($null -ne $managedGo) { $managedGo.ToolchainRoot } else { $null }
    managed_toolchain_path = if ($null -ne $managedGo) { $managedGo.InstallDir } else { $null }
    managed_toolchain_archive = if ($null -ne $managedGo) { $managedGo.ArchivePath } else { $null }
    managed_toolchain_archive_sha256 = if ($null -ne $managedGo) { $managedGo.ArchiveSha256 } else { $null }
    managed_toolchain_download_url = if ($null -ne $managedGo) { $managedGo.DownloadUrl } else { $null }
    managed_toolchain_downloaded = if ($null -ne $managedGo) { [bool]$managedGo.Downloaded } else { $false }
    module_resolution_passed = $moduleResolutionPassed
    go_mod_path = if (Test-Path -LiteralPath $goModPath -PathType Leaf) { $goModPath } else { $null }
    go_mod_sha256 = $goModSha256
    go_sum_path = if (Test-Path -LiteralPath $goSumPath -PathType Leaf) { $goSumPath } else { $null }
    go_sum_sha256 = $goSumSha256
    go_list_module_json = if (Test-Path -LiteralPath $goListModuleJsonPath -PathType Leaf) { $goListModuleJsonPath } else { $null }
    working_directory = $workDir
    candidate_app_sha256 = $candidateAppSha256
    staged_app_sha256 = $stagedAppSha256
    selected_readme_evidence = $selectedReadmePath
    selected_go_mod_evidence = $selectedGoModPath
    transcript = $transcriptPath
    stdout = $stdoutPath
    stderr = $stderrPath
    response = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { $responsePath } else { $null }
    response_status = $responseStatus
    response_body_sha256 = if (Test-Path -LiteralPath $responsePath -PathType Leaf) { Get-Sha256Hex -Path $responsePath } else { "" }
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
        command = "go run main.go ; GET http://127.0.0.1:8080/ping ; terminate tracked process tree"
        transcript = $transcriptPath
        summary = $summaryPath
        response = $responsePath
        go_source = $goSource
        go_path = $goPath
        go_version = $goVersionOutput
        cleanup_process_ids = @($cleanupProcessIds)
    }
    $manifest | Add-Member -NotePropertyName "lifecycle_validation" -NotePropertyValue $validationRecord -Force
    foreach ($gate in @($manifest.dependency_gates)) {
        if ($gate.gate_id -in @("go-version-and-module-resolution", "go-gin-process-lifecycle", "cleanup-contract")) {
            $gate.status = "passed"
            $gate.evidence = @($summaryPath, $transcriptPath, $responsePath)
            $gate.check_command = "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-gin.ps1"
            $gate.blocked_reason = ""
        }
    }
    $remainingBlockers = @()
    foreach ($blocker in @($manifest.source_only_blockers)) {
        if ($blocker.blocker_id -ne "gin-process-lifecycle-not-proven") {
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

Write-Output "Gin lifecycle validation status: $validationStatus"
Write-Output "Summary: $summaryPath"
Write-Output "Transcript: $transcriptPath"

if ($validationStatus -ne "passed") {
    exit 1
}
