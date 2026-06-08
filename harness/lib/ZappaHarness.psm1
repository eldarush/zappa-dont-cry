Set-StrictMode -Version Latest

function New-ZappaHarnessRun {
    param(
        [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs"
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $runDir = Join-Path $Root $timestamp
    [System.IO.Directory]::CreateDirectory($runDir) | Out-Null
    return $runDir
}

function Invoke-ZappaCheck {
    param(
        [string]$Name,
        [string]$Command,
        [string]$RunDir
    )

    $logPath = Join-Path $RunDir "$Name.log"
    $output = Invoke-Expression $Command 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath $logPath -Encoding UTF8

    return [ordered]@{
        name = $Name
        command = $Command
        exit_code = $exitCode
        log = $logPath
        status = if ($exitCode -eq 0) { "passed" } else { "failed" }
    }
}

Export-ModuleMember -Function New-ZappaHarnessRun, Invoke-ZappaCheck
