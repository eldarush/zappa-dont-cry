param(
    [string]$Prompt = "",

    [string]$Workspace = "D:\QaaS",

    [ValidateSet("codex", "copilot", "claude-copilot", "agy")]
    [string]$Harness = "",

    [ValidateSet("minimax-proxy", "weaker-than-minimax", "airgapped", "flash", "haiku", "single")]
    [string]$Profile = "",

    [string]$Model = "",

    [string[]]$Skill = @(),

    [string[]]$SkillPath = @(),

    [string[]]$ExpectPattern = @(),

    [string[]]$RejectPattern = @(),

    [string]$ScenarioId = "",

    [ValidateSet("", "scenario", "adversarial")]
    [string]$ScenarioKind = "",

    [string]$IndexPath = "",

    [switch]$All,

    [switch]$Airgapped,

    [switch]$ListProfiles,

    [switch]$DryRun,

    [string]$OutDir = "D:\QaaS\_tmp\weak-model-validation",

    [string]$PolicyPath = "D:\QaaS\_tools\weak-model-policy.json",

    [ValidateSet("none", "low", "medium", "high", "xhigh", "max")]
    [string]$ReasoningEffort = "low",

    [switch]$UseCustomInstructions,

    [int]$MaxSkillChars = 20000,

    [int]$TimeoutSeconds = 600
)

if ($PSVersionTable.PSVersion.Major -lt 6 -and -not $env:ZAPPA_WEAK_MODEL_SESSION_PS7_REEXEC) {
    $pwsh = Get-Command -Name "pwsh" -ErrorAction SilentlyContinue
    if ($pwsh) {
        $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $scriptPath
        )

        foreach ($entry in $PSBoundParameters.GetEnumerator()) {
            $name = [string]$entry.Key
            $value = $entry.Value
            if ($value -is [System.Management.Automation.SwitchParameter]) {
                if ($value.IsPresent) {
                    $arguments += "-$name"
                }
            } elseif ($value -is [array]) {
                if ($value.Count -gt 0) {
                    $arguments += "-$name"
                    foreach ($item in $value) {
                        $arguments += [string]$item
                    }
                }
            } else {
                $arguments += "-$name"
                $arguments += [string]$value
            }
        }

        $env:ZAPPA_WEAK_MODEL_SESSION_PS7_REEXEC = "1"
        & $pwsh.Source @arguments
        exit $LASTEXITCODE
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "zappa-harness\lib\WeakEvidence.Policy.psm1") -Force

function Get-ModelPolicy {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Model policy file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-PolicyMapValue {
    param(
        [object]$Map,
        [string]$Name
    )

    $property = $Map.PSObject.Properties[$Name]
    if (-not $property) {
        return $null
    }

    return $property.Value
}

function Write-PolicyProfiles {
    param([object]$Policy)

    Write-Output "Weak model policy updated: $($Policy.updated)"
    Write-Output "Target: $($Policy.target.model)"
    Write-Output "Default harness: $($Policy.defaults.harness)"
    Write-Output "Default profile: $($Policy.defaults.profile)"
    Write-Output "Airgapped harness: $($Policy.defaults.airgappedHarness)"
    Write-Output "Airgapped profile: $($Policy.defaults.airgappedProfile)"
    Write-Output ""

    foreach ($harnessProperty in $Policy.harnesses.PSObject.Properties) {
        $harnessName = $harnessProperty.Name
        $harnessPolicy = $harnessProperty.Value

        Write-Output "[$harnessName] $($harnessPolicy.role)"
        Write-Output "Confidence: $($harnessPolicy.confidence)"
        Write-Output "Caveat: $($harnessPolicy.caveat)"

        foreach ($profileProperty in $harnessPolicy.profiles.PSObject.Properties) {
            Write-Output "  $($profileProperty.Name): $($profileProperty.Value -join ', ')"
        }

        Write-Output ""
    }
}

function Resolve-Models {
    param(
        [object]$Policy,
        [string]$HarnessName,
        [string]$ProfileName,
        [string]$ExplicitModel,
        [bool]$RunAll
    )

    if ($ExplicitModel) {
        return @($ExplicitModel)
    }

    $harnessPolicy = Get-PolicyMapValue -Map $Policy.harnesses -Name $HarnessName
    if (-not $harnessPolicy) {
        throw "No profiles configured for harness '$HarnessName'."
    }

    $modelValue = Get-PolicyMapValue -Map $harnessPolicy.profiles -Name $ProfileName
    if ($null -eq $modelValue) {
        throw "No models configured for harness '$HarnessName' profile '$ProfileName'."
    }

    $models = @($modelValue)
    if ($models.Count -eq 0) {
        throw "No models configured for harness '$HarnessName' profile '$ProfileName'."
    }

    if ($RunAll) {
        return $models
    }

    return @($models[0])
}

function New-SafeFileName {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9_.-]', '_')
}

function Get-Sha256 {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-SkillSearchRoots {
    param([string]$WorkspacePath)

    $candidateRoots = @(
        (Join-Path $WorkspacePath ".agents\skills"),
        (Join-Path $env:USERPROFILE ".codex\skills"),
        (Join-Path $env:USERPROFILE ".agents\skills"),
        (Join-Path $env:USERPROFILE ".codex\plugins\cache")
    )

    $seen = @{}
    foreach ($root in $candidateRoots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) {
            continue
        }

        $resolved = (Resolve-Path -LiteralPath $root).Path
        if (-not $seen.ContainsKey($resolved)) {
            $seen[$resolved] = $true
            $resolved
        }
    }
}

function Get-RelativeDirectory {
    param(
        [string]$Root,
        [string]$Directory
    )

    return [System.IO.Path]::GetRelativePath($Root, $Directory).Replace("\", "/")
}

function Find-SkillFile {
    param(
        [string]$SkillName,
        [string[]]$Roots
    )

    if (Test-Path -LiteralPath $SkillName) {
        $resolved = (Resolve-Path -LiteralPath $SkillName).Path
        if ((Split-Path -Leaf $resolved) -ne "SKILL.md") {
            $candidate = Join-Path $resolved "SKILL.md"
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }

        return $resolved
    }

    $normalized = $SkillName.Trim().Replace("\", "/").ToLowerInvariant()
    if (-not $normalized) {
        throw "Skill name cannot be empty."
    }

    foreach ($root in $Roots) {
        $files = Get-ChildItem -LiteralPath $root -Recurse -Filter "SKILL.md" -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $parentName = $file.Directory.Name.ToLowerInvariant()
            $relativeDir = (Get-RelativeDirectory -Root $root -Directory $file.Directory.FullName).ToLowerInvariant()

            $frontMatterName = $null
            $nameLine = Select-String -LiteralPath $file.FullName -Pattern '^name:\s*(.+)\s*$' -List -ErrorAction SilentlyContinue
            if ($nameLine) {
                $frontMatterName = $nameLine.Matches[0].Groups[1].Value.Trim().ToLowerInvariant()
            }

            if ($parentName -eq $normalized -or
                $relativeDir -eq $normalized -or
                $relativeDir.EndsWith("/$normalized") -or
                $frontMatterName -eq $normalized) {
                return $file.FullName
            }
        }
    }

    throw "Skill not found: $SkillName"
}

function Resolve-SkillFiles {
    param(
        [string[]]$SkillNames,
        [string[]]$ExplicitSkillPaths,
        [string]$WorkspacePath
    )

    $roots = @(Get-SkillSearchRoots -WorkspacePath $WorkspacePath)
    $resolvedSkills = [ordered]@{}

    foreach ($path in $ExplicitSkillPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "SkillPath not found: $path"
        }

        $resolved = (Resolve-Path -LiteralPath $path).Path
        if ((Split-Path -Leaf $resolved) -ne "SKILL.md") {
            $resolved = Join-Path $resolved "SKILL.md"
        }

        if (-not (Test-Path -LiteralPath $resolved)) {
            throw "SKILL.md not found for SkillPath: $path"
        }

        $resolvedSkills[$resolved] = $resolved
    }

    foreach ($name in $SkillNames) {
        $resolved = Find-SkillFile -SkillName $name -Roots $roots
        $resolvedSkills[$resolved] = $resolved
    }

    return @($resolvedSkills.Values)
}

function New-SkillInstructionBlock {
    param(
        [string[]]$SkillFiles,
        [int]$MaxChars
    )

    if (-not $SkillFiles -or $SkillFiles.Count -eq 0) {
        return ""
    }

    $blocks = @(
        "Injected Codex skills:"
        "Follow these SKILL.md instructions exactly when the task names or implies the skill."
        "If the task conflicts with the skill, say so briefly and continue with the closest safe interpretation."
    )

    foreach ($skillFile in $SkillFiles) {
        $content = Get-Content -LiteralPath $skillFile -Raw
        if ($content.Length -gt $MaxChars) {
            throw "Skill file exceeds MaxSkillChars ($MaxChars): $skillFile"
        }

        $skillName = Split-Path -Leaf (Split-Path -Parent $skillFile)
        $blocks += ""
        $blocks += "## Skill: $skillName"
        $blocks += "Path: $skillFile"
        $blocks += '```markdown'
        $blocks += $content.Trim()
        $blocks += '```'
    }

    return ($blocks -join [Environment]::NewLine)
}

function New-DryRunCapture {
    param(
        [string]$OutputPath,
        [string]$HarnessName,
        [string]$ModelId,
        [string]$PromptText,
        [string]$CommandPreview,
        [string]$ScenarioId,
        [string]$ScenarioKind,
        [string]$PromptHash
    )

    $content = @(
        "# weak-model-session transcript"
        ""
        "Command: DRY_RUN $HarnessName $ModelId"
        "CommandPreview: $CommandPreview"
        "ExitCode: 0"
        "ScenarioId: $ScenarioId"
        "ScenarioKind: $ScenarioKind"
        "PromptHashSha256: $PromptHash"
        "Harness: $HarnessName"
        "Model: $ModelId"
        "DryRun: True"
        ""
        "## prompt"
        $PromptText
    ) -join [Environment]::NewLine

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
    [System.IO.File]::WriteAllText($OutputPath, $content)

    return [pscustomobject]@{
        ExitCode = 0
        StdOut = "DRY_RUN"
        StdErr = ""
        OutputPath = $OutputPath
        Harness = $HarnessName
        ModelId = $ModelId
    }
}

function Get-CodexReasoningEffort {
    param([string]$Effort)

    switch ($Effort) {
        "none" { return "low" }
        "max" { return "xhigh" }
        default { return $Effort }
    }
}

function Invoke-ProcessCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$OutputPath,
        [int]$TimeoutSec,
        [string]$StandardInputText = "",
        [string]$ScenarioId = "",
        [string]$ScenarioKind = "",
        [string]$PromptHash = "",
        [string]$HarnessName = "",
        [string]$ModelId = "",
        [string]$ProfileName = ""
    )

    $resolved = Get-Command -Name $FilePath -ErrorAction Stop
    $actualFilePath = $resolved.Source
    $actualArguments = $Arguments

    if ($resolved.CommandType -eq "ExternalScript" -or [System.IO.Path]::GetExtension($actualFilePath) -eq ".ps1") {
        $pwsh = Get-Command -Name "pwsh" -ErrorAction SilentlyContinue
        if (-not $pwsh) {
            $pwsh = Get-Command -Name "powershell" -ErrorAction Stop
        }

        $actualFilePath = $pwsh.Source
        $actualArguments = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $resolved.Source
        ) + $Arguments
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $actualFilePath
    foreach ($arg in $actualArguments) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = ($StandardInputText.Length -gt 0)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    [void]$process.Start()
    if ($StandardInputText.Length -gt 0) {
        $process.StandardInput.Write($StandardInputText)
        $process.StandardInput.Close()
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSec * 1000)) {
        try {
            $process.Kill($true)
        } catch {
            $process.Kill()
        }
        throw "Timed out after $TimeoutSec seconds: $actualFilePath $($actualArguments -join ' ')"
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    $content = @(
        "# weak-model-session transcript"
        ""
        "Command: $actualFilePath $($actualArguments -join ' ')"
        "ExitCode: $($process.ExitCode)"
        "ScenarioId: $ScenarioId"
        "ScenarioKind: $ScenarioKind"
        "PromptHashSha256: $PromptHash"
        "Harness: $HarnessName"
        "Profile: $ProfileName"
        "Model: $ModelId"
        "DryRun: False"
        ""
        "## stdout"
        $stdout
        ""
        "## stderr"
        $stderr
    ) -join [Environment]::NewLine

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
    [System.IO.File]::WriteAllText($OutputPath, $content)

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
        OutputPath = $OutputPath
        Harness = $HarnessName
        ModelId = $ModelId
    }
}

function Get-ScenarioClassification {
    param(
        [object]$Result,
        [bool]$DryRun
    )

    if ($DryRun) {
        return "dry_run_assembly"
    }

    $text = "$($Result.StdOut)`n$($Result.StdErr)"
    if ($text -match "additional_spend_limit_reached" -or
        $text -match "additional usage limit" -or
        $text -match "user_weekly_rate_limited" -or
        $text -match "rate-limiting chat requests" -or
        $text -match "retry-after" -or
        $text -match "\b402\b" -or
        ([int]$Result.ExitCode -eq 75)) {
        return "quota_blocked"
    }
    if ($text -match "Model `"[^`"]+`" from --model flag is not available" -or $text -match "model .* is not available") {
        return "model_unavailable"
    }
    if ([int]$Result.ExitCode -eq 0) {
        return "live_transcript_ready"
    }
    return "unknown_failure"
}

function Get-WeakValidationEligibility {
    param(
        [object]$Policy,
        [string]$HarnessName,
        [string]$ProfileName,
        [string]$ModelId,
        [bool]$DryRun = $false
    )

    $eligibility = Get-WeakEvidenceEligibility -Policy $Policy -Harness $HarnessName -Profile $ProfileName -Model $ModelId -DryRun:$DryRun
    return [pscustomobject]@{
        Eligible = [bool]$eligibility.weak_validation_eligible
        Reason = if ($eligibility.weak_validation_eligible) { "eligible-policy-weak-proxy" } else { [string]$eligibility.not_weak_reason }
    }
}

function Update-ScenarioIndex {
    param(
        [string]$Path,
        [string]$ScenarioId,
        [string]$ScenarioKind,
        [string]$PromptHash,
        [string]$PromptText,
        [string]$HarnessName,
        [string]$ProfileName,
        [string]$ModelId,
        [bool]$DryRun,
        [string]$SummaryPath,
        [object[]]$Results
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($ScenarioId)) {
        throw "ScenarioId is required when IndexPath is provided."
    }

    $existingRecords = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existing = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ($existing.PSObject.Properties.Name -contains "records") {
            $existingRecords = @($existing.records)
        }
    }

    $attempt = 0
    $newRecords = foreach ($result in $Results) {
        $attempt++
        $resultModelId = if ($result.PSObject.Properties.Name -contains "ModelId" -and -not [string]::IsNullOrWhiteSpace([string]$result.ModelId)) { [string]$result.ModelId } else { $ModelId }
        $resultHarness = if ($result.PSObject.Properties.Name -contains "Harness" -and -not [string]::IsNullOrWhiteSpace([string]$result.Harness)) { [string]$result.Harness } else { $HarnessName }
        $eligibility = Get-WeakValidationEligibility -Policy $Policy -HarnessName $resultHarness -ProfileName $ProfileName -ModelId $resultModelId -DryRun:$DryRun
        [ordered]@{
            scenario_id = $ScenarioId
            scenario_kind = $ScenarioKind
            prompt_hash_sha256 = $PromptHash
            prompt_length = $PromptText.Length
            attempt_order = $attempt
            match_status = "runner_recorded"
            harness = $resultHarness
            profile = $ProfileName
            model = $resultModelId
            weak_validation_eligible = $eligibility.Eligible
            not_weak_reason = if ($eligibility.Eligible) { $null } else { $eligibility.Reason }
            dry_run = $DryRun
            classification = Get-ScenarioClassification -Result $result -DryRun $DryRun
            weak_validation_passed = $false
            transcript_exit_code = [int]$result.ExitCode
            summary = $SummaryPath
            transcript = $result.OutputPath
        }
    }

    $records = @($existingRecords + $newRecords)
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        validation_kind = if ($ScenarioKind -eq "adversarial") { "live_adversarial_model_execution" } else { "live_scenario_model_execution" }
        index_status = if (@($records | Where-Object { $_.classification -eq "quota_blocked" }).Count -gt 0) { "quota_blocked" } else { "runner_recorded" }
        records = $records
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$policy = Get-ModelPolicy -Path $PolicyPath

if ($ListProfiles) {
    Write-PolicyProfiles -Policy $policy
    exit 0
}

if ($Airgapped) {
    if (-not $PSBoundParameters.ContainsKey("Harness")) {
        $Harness = $policy.defaults.airgappedHarness
    }

    if (-not $PSBoundParameters.ContainsKey("Profile")) {
        $Profile = $policy.defaults.airgappedProfile
    }

    if (-not $PSBoundParameters.ContainsKey("ReasoningEffort")) {
        $ReasoningEffort = "none"
    }
} else {
    if (-not $Harness) {
        $Harness = $policy.defaults.harness
    }

    if (-not $Profile) {
        $Profile = $policy.defaults.profile
    }

    if (-not $ReasoningEffort) {
        $ReasoningEffort = $policy.defaults.reasoningEffort
    }
}

if (-not $Prompt) {
    throw "Prompt is required unless -ListProfiles is used."
}
if ($IndexPath -and -not $ScenarioId) {
    throw "ScenarioId is required when IndexPath is provided."
}

if (-not (Test-Path -LiteralPath $Workspace)) {
    throw "Workspace not found: $Workspace"
}

[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
$timestamp = "$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$([System.Guid]::NewGuid().ToString('N').Substring(0, 8))"
$harnessPolicy = Get-PolicyMapValue -Map $policy.harnesses -Name $Harness
if (-not $harnessPolicy) {
    throw "Harness '$Harness' is not present in policy: $PolicyPath"
}

$modelsToRun = Resolve-Models -Policy $policy -HarnessName $Harness -ProfileName $Profile -ExplicitModel $Model -RunAll:$All.IsPresent
$skillFiles = @(Resolve-SkillFiles -SkillNames $Skill -ExplicitSkillPaths $SkillPath -WorkspacePath $Workspace)
$skillInstructionBlock = New-SkillInstructionBlock -SkillFiles $skillFiles -MaxChars $MaxSkillChars
$promptHash = Get-Sha256 -Text $Prompt

$guardedPrompt = @"
You are validating a Codex/GitHub Copilot/Gemini-compatible SKILL.md workflow under a weaker model.

Constraints:
- Do not edit files.
- Do not run destructive commands.
- Use any explicitly requested skill if the harness exposes it.
- Prefer direct task output over explanation.
- Use modest reasoning; do not compensate with exhaustive analysis.
- If the skill is unavailable, say SKILL_NOT_FOUND and list what skills you can see.

$skillInstructionBlock

Task:
$Prompt
"@

if (-not $DryRun -and $guardedPrompt.Length -gt 26000) {
    throw "Prompt is $($guardedPrompt.Length) characters, which is too long for reliable Windows CLI invocation. Reduce injected skill size or run with -DryRun to inspect the prompt."
}

$results = @()

foreach ($modelId in $modelsToRun) {
    $safeModel = New-SafeFileName $modelId
    $outputPath = Join-Path $OutDir "$timestamp-$Harness-$safeModel.md"

    if ($Harness -eq "claude-copilot" -and $modelId.Contains(".") -and -not $modelId.StartsWith("id:")) {
        Write-Warning "Claude-over-Copilot may route dotted model ID '$modelId' through the Opus slot. Prefer -Model id:$modelId for exact ID routing."
    }

    switch ($Harness) {
        "codex" {
            $codexReasoningEffort = Get-CodexReasoningEffort -Effort $ReasoningEffort
            $args = @(
                "--ask-for-approval", "never",
                "exec",
                "-C", $Workspace,
                "--model", $modelId,
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--ephemeral",
                "--ignore-rules",
                "--color", "never",
                "-c", "model_reasoning_effort=`"$codexReasoningEffort`""
            )

            if (-not $UseCustomInstructions) {
                $args += "--ignore-user-config"
            }

            $args += "-"

            if ($DryRun) {
                $results += New-DryRunCapture -OutputPath $outputPath -HarnessName $Harness -ModelId $modelId -PromptText $guardedPrompt -CommandPreview "codex $($args -join ' ')" -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash
                continue
            }

            $results += Invoke-ProcessCapture -FilePath "codex" -Arguments $args -OutputPath $outputPath -TimeoutSec $TimeoutSeconds -StandardInputText $guardedPrompt -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash -HarnessName $Harness -ModelId $modelId -ProfileName $Profile
        }
        "copilot" {
            $args = @(
                "-C", $Workspace,
                "--model", $modelId,
                "--effort", $ReasoningEffort,
                "--allow-all-tools",
                "--deny-tool", "write"
            )

            if (-not $UseCustomInstructions) {
                $args += "--no-custom-instructions"
            }

            $args += @(
                "--silent",
                "--output-format", "text",
                "-p", $guardedPrompt
            )

            if ($DryRun) {
                $results += New-DryRunCapture -OutputPath $outputPath -HarnessName $Harness -ModelId $modelId -PromptText $guardedPrompt -CommandPreview "copilot $($args -join ' ')" -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash
                continue
            }

            $results += Invoke-ProcessCapture -FilePath "copilot" -Arguments $args -OutputPath $outputPath -TimeoutSec $TimeoutSeconds -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash -HarnessName $Harness -ModelId $modelId -ProfileName $Profile
        }
        "claude-copilot" {
            $args = @($modelId, "-p", $guardedPrompt)

            if ($DryRun) {
                $results += New-DryRunCapture -OutputPath $outputPath -HarnessName $Harness -ModelId $modelId -PromptText $guardedPrompt -CommandPreview "claude $($args -join ' ')" -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash
                continue
            }

            $results += Invoke-ProcessCapture -FilePath "claude" -Arguments $args -OutputPath $outputPath -TimeoutSec $TimeoutSeconds -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash -HarnessName $Harness -ModelId $modelId -ProfileName $Profile
        }
        "agy" {
            $args = @(
                "--add-dir", $Workspace,
                "--print",
                $guardedPrompt
            )

            if ($DryRun) {
                $results += New-DryRunCapture -OutputPath $outputPath -HarnessName $Harness -ModelId $modelId -PromptText $guardedPrompt -CommandPreview "agy $($args -join ' ')" -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash
                continue
            }

            $results += Invoke-ProcessCapture -FilePath "agy" -Arguments $args -OutputPath $outputPath -TimeoutSec $TimeoutSeconds -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash -HarnessName $Harness -ModelId $modelId -ProfileName $Profile
        }
    }
}

$summaryPath = Join-Path $OutDir "$timestamp-summary.md"
$summary = @(
    "# Weak Model Validation Summary"
    ""
    "Workspace: $Workspace"
    "Harness: $Harness"
    "Profile: $Profile"
    "ReasoningEffort: $ReasoningEffort"
    "Models: $($modelsToRun -join ', ')"
    "DryRun: $($DryRun.IsPresent)"
    "Airgapped: $($Airgapped.IsPresent)"
    "PolicyPath: $PolicyPath"
    "HarnessRole: $($harnessPolicy.role)"
    "HarnessConfidence: $($harnessPolicy.confidence)"
    "HarnessCaveat: $($harnessPolicy.caveat)"
    "ScenarioId: $ScenarioId"
    "ScenarioKind: $ScenarioKind"
    "PromptHashSha256: $promptHash"
    "InjectedSkills: $($skillFiles -join ', ')"
    ""
    "## Results"
)

foreach ($result in $results) {
    $status = if ($result.ExitCode -eq 0) { "PASS" } else { "FAIL" }
    $notes = @()

    if (-not $DryRun) {
        foreach ($pattern in $ExpectPattern) {
            if ($result.StdOut -notmatch $pattern) {
                $status = "FAIL"
                $notes += "missing expected pattern: $pattern"
            }
        }

        foreach ($pattern in $RejectPattern) {
            if ($result.StdOut -match $pattern) {
                $status = "FAIL"
                $notes += "matched rejected pattern: $pattern"
            }
        }
    }

    $line = "- $status exit $($result.ExitCode): $($result.OutputPath)"
    if ($notes.Count -gt 0) {
        $line += " ($($notes -join '; '))"
    }

    $summary += $line
}

[System.IO.File]::WriteAllText($summaryPath, ($summary -join [Environment]::NewLine))
Update-ScenarioIndex -Path $IndexPath -ScenarioId $ScenarioId -ScenarioKind $ScenarioKind -PromptHash $promptHash -PromptText $Prompt -HarnessName $Harness -ProfileName $Profile -ModelId ($modelsToRun -join ", ") -DryRun:$DryRun.IsPresent -SummaryPath $summaryPath -Results $results

Write-Output "Weak model validation complete."
Write-Output "Summary: $summaryPath"
foreach ($result in $results) {
    Write-Output "Transcript: $($result.OutputPath)"
}

if ($results | Where-Object { $_.ExitCode -ne 0 }) {
    Write-Error "One or more weak-model validation runs failed. See transcript paths above."
    exit 1
}

if ((Get-Content -Raw -LiteralPath $summaryPath) -match '^- FAIL ' -or (Get-Content -Raw -LiteralPath $summaryPath) -match "`n- FAIL ") {
    Write-Error "One or more weak-model validation checks failed. See summary and transcript paths above."
    exit 1
}
