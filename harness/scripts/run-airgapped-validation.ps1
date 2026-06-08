param(
    [string]$Prompt = "Say exactly WEAK_VALIDATOR_READY.",
    [string]$SkillPath = "",
    [ValidateSet("", "codex", "copilot", "claude-copilot", "agy")]
    [string]$Harness = "",
    [ValidateSet("", "minimax-proxy", "weaker-than-minimax", "airgapped", "flash", "haiku", "single")]
    [string]$Profile = "",
    [string]$Model = "",
    [switch]$DryRun,
    [string[]]$ExpectPattern = @(),
    [string[]]$RejectPattern = @("SKILL_NOT_FOUND"),
    [string]$ScenarioId = "",
    [ValidateSet("", "scenario", "adversarial")]
    [string]$ScenarioKind = "",
    [string]$IndexPath = "",
    [switch]$All,
    [ValidateSet("", "none", "low", "medium", "high", "xhigh", "max")]
    [string]$ReasoningEffort = "",
    [string]$PolicyPath = "",
    [string]$ValidatorPath = "D:\QaaS\_tools\weak-model-session.ps1",
    [int]$TimeoutSeconds = 180,
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\airgapped-runs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$validator = $ValidatorPath
if (-not (Test-Path -LiteralPath $validator)) {
    throw "Weak-model validator not found: $validator"
}

$validatorParams = @{
    Prompt = $Prompt
    Airgapped = $true
    TimeoutSeconds = $TimeoutSeconds
    OutDir = $OutDir
}

if ($SkillPath) {
    $validatorParams.SkillPath = $SkillPath
}

if ($Harness) {
    $validatorParams.Harness = $Harness
}

if ($Profile) {
    $validatorParams.Profile = $Profile
}

if ($Model) {
    $validatorParams.Model = $Model
}

if ($ReasoningEffort) {
    $validatorParams.ReasoningEffort = $ReasoningEffort
}

if ($PolicyPath) {
    $validatorParams.PolicyPath = $PolicyPath
}

if ($ExpectPattern.Count -gt 0) {
    $validatorParams.ExpectPattern = $ExpectPattern
}

if ($RejectPattern.Count -gt 0) {
    $validatorParams.RejectPattern = $RejectPattern
}

if ($ScenarioId) {
    $validatorParams.ScenarioId = $ScenarioId
}

if ($ScenarioKind) {
    $validatorParams.ScenarioKind = $ScenarioKind
}

if ($IndexPath) {
    $validatorParams.IndexPath = $IndexPath
}

if ($All) {
    $validatorParams.All = $true
}

if ($DryRun) {
    $validatorParams.DryRun = $true
}

& $validator @validatorParams
$validatorExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { if ($?) { 0 } else { 1 } }
exit $validatorExitCode
