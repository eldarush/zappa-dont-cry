param(
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\harness-regression\spring-boot-selected-candidate"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-UnderRoot {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Description
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $rootWithSeparator = $resolvedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not ($resolvedPath.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $resolvedPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "$Description must stay under $resolvedRoot; got $resolvedPath"
    }

    return $resolvedPath
}

function Read-JsonFile {
    param([string]$Path)

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 64), $script:Utf8NoBom)
}

function Convert-JsonPaths {
    param(
        [AllowNull()]$Value,
        [hashtable]$Replacements
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        $result = [string]$Value
        foreach ($key in $Replacements.Keys) {
            $result = $result.Replace([string]$key, [string]$Replacements[$key])
        }
        return $result
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $output = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $output[$key] = Convert-JsonPaths -Value $Value[$key] -Replacements $Replacements
        }
        return $output
    }

    if ($Value -is [pscustomobject]) {
        $output = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $output[$property.Name] = Convert-JsonPaths -Value $property.Value -Replacements $Replacements
        }
        return $output
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $items.Add((Convert-JsonPaths -Value $item -Replacements $Replacements))
        }
        return ,$items.ToArray()
    }

    return $Value
}

function Rewrite-JsonFiles {
    param(
        [string]$Root,
        [hashtable]$Replacements
    )

    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.json") {
        $json = Read-JsonFile -Path $file.FullName
        $rewritten = Convert-JsonPaths -Value $json -Replacements $Replacements
        Write-JsonFile -Path $file.FullName -Value $rewritten
    }
}

function Invoke-Checker {
    param([object]$Fixture)

    $checker = Join-Path $HarnessRoot "checks\Check-SelectedTopRepoCandidates.py"
    $coverageDir = Join-Path $Fixture.Root "coverage"
    [System.IO.Directory]::CreateDirectory($coverageDir) | Out-Null

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & python $checker $Fixture.CandidateRoot $Fixture.SelectedRoot $coverageDir 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [ordered]@{
        ExitCode = $exitCode
        Text = ($output | Out-String)
    }
}

function Assert-Check {
    param(
        [string]$Name,
        [object]$Result,
        [int]$ExpectedExitCode,
        [string]$ExpectedText
    )

    if ([int]$Result.ExitCode -ne $ExpectedExitCode) {
        throw "$Name expected exit code $ExpectedExitCode, got $($Result.ExitCode): $($Result.Text)"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedText) -and $Result.Text -notmatch [regex]::Escape($ExpectedText)) {
        throw "$Name missing expected text '$ExpectedText': $($Result.Text)"
    }
}

function New-SpringBootFixture {
    param([string]$Name)

    $root = Join-Path $resolvedOutDir $Name
    $candidateRoot = Join-Path $root "selected-top-repo-candidates"
    $selectedRoot = Join-Path $root "selected-contracts"
    $coverageRoot = Join-Path $root "coverage"
    $lifecycleRoot = Join-Path $root "lifecycle-runs\selected-top-repo-candidates"
    $liveRoot = Join-Path $root "live-runs\selected-top-repo-candidates"
    $candidateDir = Join-Path $candidateRoot "177-spring-projects-spring-boot"
    $selectedDir = Join-Path $selectedRoot "177-spring-projects-spring-boot"

    if (Test-Path -LiteralPath $root) {
        $resolvedRoot = Assert-UnderRoot -Path $root -Root $resolvedOutDir -Description "Regression fixture"
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }

    [System.IO.Directory]::CreateDirectory($candidateRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($selectedRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($coverageRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($lifecycleRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($liveRoot) | Out-Null
    Copy-Item -LiteralPath (Join-Path $originalCandidateRoot "177-spring-projects-spring-boot") -Destination $candidateDir -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $originalSelectedRoot "177-spring-projects-spring-boot") -Destination $selectedDir -Recurse -Force

    $originalManifestPath = Join-Path $originalCandidateRoot "177-spring-projects-spring-boot\qaas-artifact-manifest.json"
    $originalManifest = Read-JsonFile -Path $originalManifestPath
    if (
        ($originalManifest.PSObject.Properties.Name -contains "lifecycle_validation") -and
        [string]$originalManifest.lifecycle_validation.status -eq "passed"
    ) {
        $originalSummaryPath = [string]$originalManifest.lifecycle_validation.summary
        if (Test-Path -LiteralPath $originalSummaryPath -PathType Leaf) {
            Copy-Item -LiteralPath $originalSummaryPath -Destination (Join-Path $coverageRoot (Split-Path -Leaf $originalSummaryPath)) -Force
            $originalSummary = Read-JsonFile -Path $originalSummaryPath
            $originalRunDir = [string]$originalSummary.run_dir
            if (Test-Path -LiteralPath $originalRunDir -PathType Container) {
                Copy-Item -LiteralPath $originalRunDir -Destination (Join-Path $lifecycleRoot (Split-Path -Leaf $originalRunDir)) -Recurse -Force
            }
        }
    }
    if (
        ($originalManifest.PSObject.Properties.Name -contains "selected_candidate_qaas_validation") -and
        [string]$originalManifest.selected_candidate_qaas_validation.status -eq "passed"
    ) {
        $originalSummaryPath = [string]$originalManifest.selected_candidate_qaas_validation.summary
        if (Test-Path -LiteralPath $originalSummaryPath -PathType Leaf) {
            Copy-Item -LiteralPath $originalSummaryPath -Destination (Join-Path $coverageRoot (Split-Path -Leaf $originalSummaryPath)) -Force
            $originalSummary = Read-JsonFile -Path $originalSummaryPath
            $originalRunDir = [string]$originalSummary.run_dir
            if (Test-Path -LiteralPath $originalRunDir -PathType Container) {
                Copy-Item -LiteralPath $originalRunDir -Destination (Join-Path $liveRoot (Split-Path -Leaf $originalRunDir)) -Recurse -Force
            }
        }
    }

    $replacements = @{
        $originalCandidateRoot = $candidateRoot
        $originalSelectedRoot = $selectedRoot
        $originalCoverageRoot = $coverageRoot
        $originalLifecycleRoot = $lifecycleRoot
        $originalLiveRoot = $liveRoot
    }
    Rewrite-JsonFiles -Root $candidateRoot -Replacements $replacements
    Rewrite-JsonFiles -Root $selectedRoot -Replacements $replacements
    Rewrite-JsonFiles -Root $coverageRoot -Replacements $replacements
    Rewrite-JsonFiles -Root $lifecycleRoot -Replacements $replacements
    Rewrite-JsonFiles -Root $liveRoot -Replacements $replacements

    $manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"
    $manifest = Read-JsonFile -Path $manifestPath
    $selectedPath = Join-Path $selectedDir "selected-contract.json"
    $selected = Read-JsonFile -Path $selectedPath

    Write-JsonFile -Path (Join-Path $candidateRoot "selected-candidate-index.json") -Value ([ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        source_selected_contracts_directory = $selectedRoot
        output_directory = $candidateRoot
        selected_candidate_count = 1
        selected_contract_count = 1
        deferred_candidate_count = 0
        policy = "Spring Boot selected-candidate regression fixture"
        records = @(
            [ordered]@{
                rank = 177
                repository = "spring-projects/spring-boot"
                directory = $candidateDir
                manifest = $manifestPath
                selected_contract = $selectedPath
                status = "candidate_packet_blocked_until_template_live_airgapped_validation"
                promotion_state = "blocked"
                artifact_count = [int]$manifest.artifact_count
            }
        )
        deferred_records = @()
    })

    $markerCount = 0
    if ($selected.PSObject.Properties.Name -contains "readme_markers") {
        $markerCount = @($selected.readme_markers).Count
    } elseif ($selected.PSObject.Properties.Name -contains "candidate_promotion_contracts") {
        $markerCount = @($selected.candidate_promotion_contracts).Count
    }

    Write-JsonFile -Path (Join-Path $selectedRoot "selected-contract-index.json") -Value ([ordered]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        source_contracts_directory = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts"
        output_directory = $selectedRoot
        selected_repository_count = 1
        max_repositories = 1
        max_file_bytes = 65536
        max_files_per_repository = 8
        max_total_bytes = 524288
        total_fetched_bytes = 0
        policy = "Spring Boot selected-candidate regression fixture"
        records = @(
            [ordered]@{
                repository = "spring-projects/spring-boot"
                rank = 177
                record_path = $selectedPath
                fetched_file_count = @($selected.selected_public_contracts).Count
                marker_count = $markerCount
                status = "contract_content_harvested_not_executable"
                promotion_state = "blocked"
            }
        )
    })

    return [ordered]@{
        Root = $root
        CandidateRoot = $candidateRoot
        SelectedRoot = $selectedRoot
        CandidateDir = $candidateDir
        SelectedContract = $selectedPath
        Manifest = $manifestPath
        RuntimePlan = Join-Path $candidateDir "candidate-runtime-plan.json"
        Yaml = Join-Path $candidateDir "test.qaas.yaml"
    }
}

$resolvedHarnessRoot = Assert-UnderRoot -Path $HarnessRoot -Root "D:\QaaS\_tools\zappa-harness" -Description "HarnessRoot"
$resolvedOutDir = Assert-UnderRoot -Path $OutDir -Root "D:\QaaS\_tmp\zappa-dont-cry" -Description "OutDir"
[System.IO.Directory]::CreateDirectory($resolvedOutDir) | Out-Null

$originalCandidateRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates"
$originalSelectedRoot = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts"
$originalCoverageRoot = "D:\QaaS\_tmp\zappa-dont-cry\coverage"
$originalLifecycleRoot = "D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates"
$originalLiveRoot = "D:\QaaS\_tmp\zappa-dont-cry\live-runs\selected-top-repo-candidates"
foreach ($requiredPath in @(
        (Join-Path $originalCandidateRoot "177-spring-projects-spring-boot\qaas-artifact-manifest.json"),
        (Join-Path $originalSelectedRoot "177-spring-projects-spring-boot\selected-contract.json")
    )) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Spring Boot selected-candidate regression requires generated baseline: $requiredPath"
    }
}

$baseline = New-SpringBootFixture -Name "baseline"
$baselineResult = Invoke-Checker -Fixture $baseline
Assert-Check -Name "Spring Boot selected candidate baseline" -Result $baselineResult -ExpectedExitCode 0 -ExpectedText "Selected top-repo candidate check passed"

$hookSpoof = New-SpringBootFixture -Name "source-yaml-hook-spoof"
Add-Content -LiteralPath $hookSpoof.Yaml -Value "`n# spoof`nAssertion: ExactHttpTextBody`n" -Encoding UTF8
$hookSpoofResult = Invoke-Checker -Fixture $hookSpoof
Assert-Check -Name "Spring Boot checker rejects source YAML hook activation" -Result $hookSpoofResult -ExpectedExitCode 1 -ExpectedText "active YAML must not use custom assertion"

$portEvidenceMissing = New-SpringBootFixture -Name "missing-default-port-evidence"
$selected = Read-JsonFile -Path $portEvidenceMissing.SelectedContract
$selected.selected_public_contracts = @($selected.selected_public_contracts | Where-Object { [string]$_.source_path -ne "documentation/spring-boot-docs/src/docs/antora/modules/how-to/pages/webserver.adoc" })
Write-JsonFile -Path $portEvidenceMissing.SelectedContract -Value $selected
$portEvidenceResult = Invoke-Checker -Fixture $portEvidenceMissing
Assert-Check -Name "Spring Boot checker requires immutable default-port evidence" -Result $portEvidenceResult -ExpectedExitCode 1 -ExpectedText "default-port evidence"

$commandSpoof = New-SpringBootFixture -Name "runtime-command-spoof"
$runtimePlan = Read-JsonFile -Path $commandSpoof.RuntimePlan
$runtimePlan.command_support = "candidate-executable-command"
Write-JsonFile -Path $commandSpoof.RuntimePlan -Value $runtimePlan
$commandSpoofResult = Invoke-Checker -Fixture $commandSpoof
Assert-Check -Name "Spring Boot checker rejects runnable command spoof" -Result $commandSpoofResult -ExpectedExitCode 1 -ExpectedText "partial and not runnable"

$weakSpoof = New-SpringBootFixture -Name "weak-validation-spoof"
$manifest = Read-JsonFile -Path $weakSpoof.Manifest
$manifest.airgapped_validation.status = "passed"
Write-JsonFile -Path $weakSpoof.Manifest -Value $manifest
$weakSpoofResult = Invoke-Checker -Fixture $weakSpoof
Assert-Check -Name "Spring Boot checker rejects airgapped validation spoof" -Result $weakSpoofResult -ExpectedExitCode 1 -ExpectedText "airgapped validation"

$lifecycleVersionSpoof = New-SpringBootFixture -Name "lifecycle-version-spoof"
$manifest = Read-JsonFile -Path $lifecycleVersionSpoof.Manifest
if (
    ($manifest.PSObject.Properties.Name -contains "lifecycle_validation") -and
    [string]$manifest.lifecycle_validation.status -eq "passed"
) {
    $summaryPath = [string]$manifest.lifecycle_validation.summary
    $summary = Read-JsonFile -Path $summaryPath
    $summary.generated_pom_boot_version = "4.0.6.RELEASE"
    Write-JsonFile -Path $summaryPath -Value $summary
    $lifecycleVersionSpoofResult = Invoke-Checker -Fixture $lifecycleVersionSpoof
    Assert-Check -Name "Spring Boot checker rejects lifecycle version spoof" -Result $lifecycleVersionSpoofResult -ExpectedExitCode 1 -ExpectedText "RELEASE-suffixed"
}

Write-Output "Spring Boot selected-candidate regression checks passed."
