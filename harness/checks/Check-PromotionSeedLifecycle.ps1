param(
    [string]$SeedRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\promotion-seed\qaas-docs-hello-world-http",
    [string]$ExpectedSeedRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\promotion-seed\qaas-docs-hello-world-http"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) "lib\WeakEvidence.Policy.psm1") -Force
$failures = New-Object System.Collections.Generic.List[string]
$weakPolicy = Read-WeakEvidencePolicy -Path "D:\QaaS\_tools\weak-model-policy.json"
$preferredWeakModels = @(Get-WeakEvidenceAllowedModels -Policy $weakPolicy -Harness "claude-copilot" -Profile "airgapped" -RequiredEvidenceClass @("preferred_weak"))

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

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

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $fullPath = Get-NormalizedPath -Path $Path
    $rootPath = Get-NormalizedPath -Path $Root
    if ([string]::Equals($fullPath, $rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $rootPrefix = "$rootPath$([System.IO.Path]::DirectorySeparatorChar)"
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-ExistingFileUnderRoot {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Add-Failure "$Description is blank."
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Failure "$Description missing: $Path"
        return $false
    }

    $resolved = Get-NormalizedPath -Path (Resolve-Path -LiteralPath $Path).Path
    if (-not (Test-PathUnderRoot -Path $resolved -Root $Root)) {
        Add-Failure "$Description must stay under $Root; got $resolved"
        return $false
    }

    return $true
}

function Test-PassedValidation {
    param(
        [object]$Validation,
        [string]$TranscriptRoot,
        [string]$Name
    )

    if ($null -eq $Validation) {
        return $false
    }
    if ($Validation.status -ne "passed" -or [int]$Validation.exit_code -ne 0) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Validation.command)) {
        return $false
    }
    if (-not (Test-ExistingFileUnderRoot -Path $Validation.transcript -Root $TranscriptRoot -Description "Promotion seed ${Name} transcript")) {
        return $false
    }

    return (
        (Test-PathUnderRoot -Path $Validation.transcript -Root $TranscriptRoot)
    )
}

function Test-TranscriptIsDryRun {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $text = Get-Content -LiteralPath $Path -Raw
    return ($text -match "DryRun:\s*True" -or $text -match "dry_run_")
}

function Test-PassedAirgappedIndexAllPreferred {
    param(
        [string]$IndexPath,
        [string]$AirgappedRoot,
        [string[]]$ExpectedModels
    )

    if (-not (Test-ExistingFileUnderRoot -Path $IndexPath -Root $AirgappedRoot -Description "Passed airgapped seed validation index")) {
        return $false
    }

    $index = Read-JsonFile -Path $IndexPath
    $records = @($index.records)
    if ($records.Count -eq 0) {
        Add-Failure "Passed airgapped seed validation index has no records."
        return $false
    }

    $allPreferredPresent = $true
    foreach ($expectedModel in $ExpectedModels) {
        $matching = @($records | Where-Object {
            [string]$_.harness -eq "claude-copilot" -and
            [string]$_.profile -eq "airgapped" -and
            [string]$_.model -eq $expectedModel
        })
        if ($matching.Count -eq 0) {
            Add-Failure "Passed airgapped seed validation index missing preferred weak model: $expectedModel"
            $allPreferredPresent = $false
            continue
        }
        if ($matching.Count -gt 1) {
            Add-Failure "Passed airgapped seed validation index has duplicate preferred weak model: $expectedModel"
            $allPreferredPresent = $false
            continue
        }

        $record = $matching[0]
        if ($record.dry_run -ne $false) {
            Add-Failure "Passed airgapped seed validation index record for $expectedModel must be dry_run false."
            $allPreferredPresent = $false
        }
        if ([int]$record.transcript_exit_code -ne 0) {
            Add-Failure "Passed airgapped seed validation index record for $expectedModel must have transcript_exit_code 0."
            $allPreferredPresent = $false
        }
        if ([string]$record.classification -ne "live_transcript_ready" -and [string]$record.classification -ne "live_model_execution_passed") {
            Add-Failure "Passed airgapped seed validation index record for $expectedModel must be live evidence."
            $allPreferredPresent = $false
        }
        if ($record.PSObject.Properties.Name -contains "weak_validation_eligible" -and $record.weak_validation_eligible -ne $true) {
            Add-Failure "Passed airgapped seed validation index record for $expectedModel must be weak-validation eligible."
            $allPreferredPresent = $false
        }
        if (-not (Test-ExistingFileUnderRoot -Path $record.transcript -Root $AirgappedRoot -Description "Passed airgapped seed transcript for $expectedModel")) {
            $allPreferredPresent = $false
        } else {
            $transcriptText = Get-Content -LiteralPath $record.transcript -Raw
            foreach ($required in @("Harness: claude-copilot", "Profile: airgapped", "Model: $expectedModel", "DryRun: False", "weak_validation_passed: true", "dry_run: false")) {
                if ($transcriptText -notmatch [regex]::Escape($required)) {
                    Add-Failure "Passed airgapped seed transcript for $expectedModel missing '$required'."
                    $allPreferredPresent = $false
                }
            }
        }
    }

    return $allPreferredPresent
}

$expectedSeedRoot = Get-NormalizedPath -Path $ExpectedSeedRoot
$seedRootPath = Get-NormalizedPath -Path $SeedRoot
$evidenceRootPath = Join-Path $seedRootPath "evidence"
$airgappedRootPath = Join-Path $seedRootPath "airgapped"
$runnerRootPath = Join-Path $seedRootPath "runner"
$mockerRootPath = Join-Path $seedRootPath "mocker"

if (-not [string]::Equals($seedRootPath, $expectedSeedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Add-Failure "Promotion seed lifecycle must validate the canonical seed root $expectedSeedRoot, got $seedRootPath"
}

$manifestPath = Join-Path $seedRootPath "qaas-artifact-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Add-Failure "Missing promotion seed manifest: $manifestPath"
} else {
    $manifest = Read-JsonFile -Path $manifestPath

    if ($manifest.campaign_id -ne "promotion-seed-qaas-docs-hello-world-http") {
        Add-Failure "Unexpected promotion seed campaign_id: $($manifest.campaign_id)"
    }
    if ($manifest.source_repository -ne "qaas-docs") {
        Add-Failure "Promotion seed source_repository must be qaas-docs: $manifestPath"
    }

    $docsEvidence = @($manifest.docs_evidence)
    if ($docsEvidence.Count -lt 5) {
        Add-Failure "Promotion seed must include structured docs evidence for docs and schemas."
    }
    foreach ($item in $docsEvidence) {
        if ($null -eq $item -or -not ($item.PSObject.Properties.Name -contains "path")) {
            Add-Failure "Promotion seed docs_evidence item is not structured with path."
            continue
        }
        if (-not (Test-Path -LiteralPath $item.path -PathType Leaf)) {
            Add-Failure "Promotion seed docs_evidence path does not exist: $($item.path)"
        }
        foreach ($field in @("claim", "supports")) {
            if (-not ($item.PSObject.Properties.Name -contains $field)) {
                Add-Failure "Promotion seed docs_evidence item missing ${field}: $($item.path)"
            }
        }
    }

    foreach ($artifact in @($manifest.artifacts)) {
        if (-not (Test-ExistingFileUnderRoot -Path $artifact -Root $seedRootPath -Description "Promotion seed artifact")) {
            continue
        }
        if ([System.IO.Path]::GetExtension($artifact).ToLowerInvariant() -in @(".yaml", ".yml", ".cs")) {
            $text = Get-Content -LiteralPath $artifact -Raw
            foreach ($marker in @("__DOCUMENTED_", "__PUBLIC_", "__REPLACE_", "__QAAS_", "blocked_until_", "Sessions: []", "Stubs: []", "Links: []")) {
                if ($text -match [regex]::Escape($marker)) {
                    Add-Failure "Promotion seed artifact contains blocked marker '$marker': $artifact"
                }
            }
        }
    }

    $runnerYaml = @($manifest.artifacts | Where-Object { [System.IO.Path]::GetFileName($_) -eq "test.qaas.yaml" }) | Select-Object -First 1
    $mockerYaml = @($manifest.artifacts | Where-Object { [System.IO.Path]::GetFileName($_) -eq "mocker.qaas.yaml" }) | Select-Object -First 1
    if (-not $runnerYaml) {
        Add-Failure "Promotion seed missing runner test.qaas.yaml artifact."
    } elseif (-not (Test-ExistingFileUnderRoot -Path $runnerYaml -Root $runnerRootPath -Description "Promotion seed runner YAML")) {
        Add-Failure "Promotion seed runner YAML is not under the seed runner directory: $runnerYaml"
    } else {
        $runnerText = Get-Content -LiteralPath $runnerYaml -Raw
        foreach ($requiredText in @("Transactions:", "Route: hello", "Assertion: HttpStatus", "StatusCode: 200", "OutputNames: [CallHello]")) {
            if ($runnerText -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Runner seed YAML missing required text '$requiredText': $runnerYaml"
            }
        }
    }
    if (-not $mockerYaml) {
        Add-Failure "Promotion seed missing mocker.qaas.yaml artifact."
    } elseif (-not (Test-ExistingFileUnderRoot -Path $mockerYaml -Root $mockerRootPath -Description "Promotion seed mocker YAML")) {
        Add-Failure "Promotion seed mocker YAML is not under the seed mocker directory: $mockerYaml"
    } else {
        $mockerText = Get-Content -LiteralPath $mockerYaml -Raw
        foreach ($requiredText in @("Processor: StaticResponseProcessor", "StatusCode: 200", "ContentType: text/plain; charset=utf-8", "Path: /hello", "Method: Get")) {
            if ($mockerText -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Mocker seed YAML missing required text '$requiredText': $mockerYaml"
            }
        }
    }

    foreach ($field in @("template_validation", "build_validation", "live_validation")) {
        if (-not (Test-PassedValidation -Validation $manifest.$field -TranscriptRoot $evidenceRootPath -Name $field)) {
            Add-Failure "Promotion seed missing passed ${field} with concrete transcript: $manifestPath"
        }
    }

    $airgapped = $manifest.airgapped_validation
    if ($null -eq $airgapped -or $airgapped.required -ne $true) {
        Add-Failure "Promotion seed must require airgapped validation."
    } elseif ($airgapped.status -eq "passed") {
        if ($airgapped.dry_run -ne $false) {
            Add-Failure "Passed airgapped seed validation must record dry_run false."
        }
        if ([int]$airgapped.exit_code -ne 0) {
            Add-Failure "Passed airgapped seed validation must have exit_code 0."
        }
        if (-not (Test-ExistingFileUnderRoot -Path $airgapped.transcript -Root $evidenceRootPath -Description "Passed airgapped seed validation transcript")) {
            Add-Failure "Passed airgapped seed validation lacks seed-local transcript."
        } elseif (Test-TranscriptIsDryRun -Path $airgapped.transcript) {
            Add-Failure "Passed airgapped seed validation uses dry-run transcript: $($airgapped.transcript)"
        }
        if (-not (Test-ExistingFileUnderRoot -Path $airgapped.summary -Root $airgappedRootPath -Description "Passed airgapped seed validation summary")) {
            Add-Failure "Passed airgapped seed validation lacks airgapped summary."
        } else {
            $summaryText = Get-Content -LiteralPath $airgapped.summary -Raw
            foreach ($requiredPattern in @("DryRun:\s*False", "Airgapped:\s*True", "(?m)^- PASS exit 0:")) {
                if ($summaryText -notmatch $requiredPattern) {
                    Add-Failure "Passed airgapped summary missing required live marker '$requiredPattern': $($airgapped.summary)"
                }
            }
            if ($summaryText -match "(?m)^- FAIL ") {
                Add-Failure "Passed airgapped summary contains FAIL result: $($airgapped.summary)"
            }
        }
        Test-PassedAirgappedIndexAllPreferred -IndexPath $airgapped.index -AirgappedRoot $airgappedRootPath -ExpectedModels $preferredWeakModels | Out-Null
        $expectedPatterns = @($airgapped.expected_patterns)
        foreach ($pattern in @("weak_validation_passed:\s*true", "dry_run:\s*false", "intent_assumptions", "docs_evidence", "artifact_plan", "validation_sequence", "airgapped_result", "strong_review", "next_blocker")) {
            if ($expectedPatterns -notcontains $pattern) {
                Add-Failure "Passed airgapped validation missing expected pattern contract '$pattern'."
            }
        }
    } else {
        if ($manifest.promotion_state -ne "blocked") {
            Add-Failure "Seed without passed airgapped validation must remain blocked."
        }
        if ($manifest.status -ne "blocked_until_contract_review") {
            Add-Failure "Blocked promotion seed must use status blocked_until_contract_review."
        }
        if (-not @($manifest.source_only_blockers).Count) {
            Add-Failure "Blocked promotion seed must include source_only_blockers."
        } elseif (-not (@($manifest.source_only_blockers) | Where-Object { $_.blocker_id -eq "promotion-seed-live-airgapped-not-passed" })) {
            Add-Failure "Blocked promotion seed must include promotion-seed-live-airgapped-not-passed blocker."
        }
    }

    if ($manifest.promotion_state -eq "executable") {
        if ($manifest.status -ne "executable") {
            Add-Failure "Executable seed must use status executable."
        }
        if (@($manifest.source_only_blockers).Count -ne 0) {
            Add-Failure "Executable seed must have empty source_only_blockers."
        }
        foreach ($key in @("template", "build", "live", "airgapped")) {
            $value = $manifest.validation_evidence.$key
            if (-not (Test-ExistingFileUnderRoot -Path $value -Root $evidenceRootPath -Description "Executable seed validation_evidence.${key}")) {
                Add-Failure "Executable seed missing validation_evidence.${key}: $manifestPath"
            }
        }
    } elseif ($manifest.promotion_state -ne "blocked") {
        Add-Failure "Promotion seed must be blocked or executable, got: $($manifest.promotion_state)"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Promotion seed lifecycle check passed."
Write-Output "Manifest: $manifestPath"
