param(
    [string]$Root = "D:\QaaS\_tmp\zappa-dont-cry",
    [string]$SkillRoot = "C:\Users\eldar\.codex\skills\zappa-dont-cry",
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "scripts\bootstrap-zappa-env.ps1") -Root $Root -SkillRoot $SkillRoot -HarnessRoot $HarnessRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Default environment bootstrap failed with exit code $LASTEXITCODE"
    exit 1
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HarnessRoot "checks\Check-ZappaEnvironment.ps1") -Root $Root -SkillRoot $SkillRoot -HarnessRoot $HarnessRoot
if ($LASTEXITCODE -ne 0) {
    Write-Error "Default environment contract check failed with exit code $LASTEXITCODE"
    exit 1
}

Write-Output "Default Zappa environment check passed: $Root"
