param(
    [string]$ContractsDir = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts",
    [string[]]$Repositories = @(
        "typicode/json-server",
        "fastapi/fastapi",
        "pallets/flask",
        "gin-gonic/gin",
        "denoland/deno",
        "unclecode/crawl4ai",
        "expressjs/express",
        "spring-projects/spring-boot"
    ),
    [int]$MaxRepositories = 8,
    [int]$MaxFileBytes = 65536,
    [int]$MaxFilesPerRepository = 8,
    [int]$MaxTotalBytes = 524288,
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ContractsDir)) {
    throw "Contracts directory not found: $ContractsDir"
}

$gh = Get-Command gh -ErrorAction Stop
[System.IO.Directory]::CreateDirectory($OutDir) | Out-Null

$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
$allowedRoot = [System.IO.Path]::GetFullPath("D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts")
if ($Clean) {
    if (-not $resolvedOutDir.Equals($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "-Clean is only allowed for the managed selected-contracts directory: $allowedRoot"
    }

    Get-ChildItem -LiteralPath $resolvedOutDir -Force | Remove-Item -Recurse -Force
}

function New-SafeName {
    param([string]$Value)

    $safe = ($Value -replace '[^A-Za-z0-9_.-]', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "unnamed"
    }

    if ($safe.Length -gt 96) {
        return $safe.Substring(0, 96).Trim('-')
    }

    return $safe
}

function Test-RelativeGitPath {
    param([string]$Path)

    return (
        -not [string]::IsNullOrWhiteSpace($Path) -and
        -not [System.IO.Path]::IsPathRooted($Path) -and
        $Path -notmatch ':' -and
        $Path -notmatch '(^|/)\.\.(/|$)' -and
        $Path -notmatch '\\' -and
        $Path -notmatch '[\x00-\x1f\x7f]'
    )
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($Bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha256.Dispose()
    }
}

function Get-GitBlobSha {
    param([byte[]]$Bytes)

    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
    $payload = New-Object byte[] ($header.Length + $Bytes.Length)
    [System.Buffer]::BlockCopy($header, 0, $payload, 0, $header.Length)
    [System.Buffer]::BlockCopy($Bytes, 0, $payload, $header.Length, $Bytes.Length)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha1.ComputeHash($payload)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha1.Dispose()
    }
}

function Get-GhBlobBytes {
    param([string]$Url)

    $output = & $gh.Source api $Url 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "gh api failed for ${Url}: $output"
    }

    $blob = $output | Out-String | ConvertFrom-Json
    if ([string]$blob.encoding -ne "base64") {
        throw "GitHub blob was not base64 encoded: $Url"
    }

    $content = ([string]$blob.content) -replace '\s', ''
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "GitHub blob content was empty: $Url"
    }

    return [System.Convert]::FromBase64String($content)
}

function Test-Utf8Text {
    param([byte[]]$Bytes)

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        [void]$utf8.GetString($Bytes)
        return $true
    } catch {
        return $false
    }
}

function Test-LfsPointer {
    param([byte[]]$Bytes)

    if ($Bytes.Length -gt 2048) {
        return $false
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false, $false)
    $text = $utf8.GetString($Bytes)
    return $text.StartsWith("version https://git-lfs.github.com/spec/v1", [System.StringComparison]::Ordinal)
}

function Add-CandidatePath {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$Path,
        [string]$Reason,
        [int]$Priority
    )

    if (-not (Test-RelativeGitPath -Path $Path)) {
        return
    }

    foreach ($candidate in $Candidates) {
        if ([string]::Equals([string]$candidate.path, $Path, [System.StringComparison]::Ordinal)) {
            return
        }
    }

    $Candidates.Add([ordered]@{
        path = $Path
        reason = $Reason
        priority = $Priority
    })
}

function Get-TreeItemByPath {
    param(
        [object[]]$Tree,
        [string]$Path
    )

    $matches = @($Tree | Where-Object { $_.type -eq "blob" -and [string]::Equals([string]$_.path, $Path, [System.StringComparison]::Ordinal) } | Select-Object -First 1)
    if ($matches.Count -eq 0) {
        return $null
    }

    return $matches[0]
}

function Get-ReadmeMarkers {
    param(
        [string]$Repository,
        [string]$Readme
    )

    $markers = New-Object System.Collections.Generic.List[object]

    function Add-Marker {
        param(
            [string]$Id,
            [string]$Value,
            [string]$Supports
        )

        if ($Readme.Contains($Value)) {
            $markers.Add([ordered]@{
                marker_id = $Id
                value = $Value
                supports = $Supports
                evidence = "README.snapshot.md"
            })
        }
    }

    Add-Marker -Id "runtime-url-localhost-3000" -Value "http://localhost:3000" -Supports "runtime-contract"
    Add-Marker -Id "runtime-url-loopback-8000" -Value "http://127.0.0.1:8000" -Supports "runtime-contract"
    Add-Marker -Id "runtime-url-localhost-8000" -Value "http://localhost:8000" -Supports "runtime-contract"
    Add-Marker -Id "runtime-url-localhost-5000" -Value "http://127.0.0.1:5000" -Supports "runtime-contract"
    Add-Marker -Id "http-route-posts-one" -Value "/posts/1" -Supports "http-contract"
    Add-Marker -Id "http-route-items-query" -Value "/items/5?q=somequery" -Supports "http-contract"
    Add-Marker -Id "http-route-root" -Value "Hello, World!" -Supports "input-output-contract"
    Add-Marker -Id "http-route-root-hello-world-no-comma" -Value "Hello World" -Supports "input-output-contract"
    Add-Marker -Id "json-server-command" -Value "npx json-server db.json" -Supports "candidate-executable-command"
    Add-Marker -Id "fastapi-command" -Value "fastapi dev" -Supports "candidate-executable-command"
    Add-Marker -Id "flask-command" -Value "flask run" -Supports "candidate-executable-command"
    Add-Marker -Id "go-run-command" -Value "go run main.go" -Supports "candidate-executable-command"
    Add-Marker -Id "deno-run-command" -Value "deno run --allow-net server.ts" -Supports "candidate-executable-command"
    Add-Marker -Id "docker-run-command" -Value "docker run" -Supports "candidate-executable-command"
    Add-Marker -Id "express-import-example" -Value "import express from 'express'" -Supports "runtime-contract"
    Add-Marker -Id "express-listen-port-3000" -Value "app.listen(3000" -Supports "runtime-contract"
    Add-Marker -Id "deno-serve-example" -Value "Deno.serve" -Supports "runtime-contract"
    Add-Marker -Id "deno-server-ts-fixture" -Value "server.ts" -Supports "runtime-contract"
    Add-Marker -Id "deno-root-hello-world" -Value "Hello, world!" -Supports "input-output-contract"
    Add-Marker -Id "spring-boot-restcontroller-example" -Value "@RestController" -Supports "runtime-contract"
    Add-Marker -Id "spring-boot-application-example" -Value "@SpringBootApplication" -Supports "runtime-contract"
    Add-Marker -Id "spring-boot-root-request-mapping" -Value '@RequestMapping("/")' -Supports "http-contract"
    Add-Marker -Id "spring-boot-root-hello-world" -Value 'return "Hello World!";' -Supports "input-output-contract"
    Add-Marker -Id "spring-boot-java-jar" -Value "java -jar" -Supports "candidate-executable-command"
    Add-Marker -Id "spring-boot-default-http-port-8080" -Value 'main HTTP port defaults to `8080`' -Supports "http-contract"
    Add-Marker -Id "expected-json-id-one" -Value '"id": "1"' -Supports "input-output-contract"
    Add-Marker -Id "expected-json-title" -Value '"title": "a title"' -Supports "input-output-contract"
    Add-Marker -Id "expected-json-views" -Value '"views": 100' -Supports "input-output-contract"
    Add-Marker -Id "expected-json-pong" -Value '"message": "pong"' -Supports "input-output-contract"

    return $markers.ToArray()
}

function Get-CandidatePromotionContracts {
    param([object[]]$Markers)

    $supports = @($Markers | ForEach-Object { [string]$_.supports } | Select-Object -Unique)
    $contracts = New-Object System.Collections.Generic.List[object]

    foreach ($support in $supports) {
        if ([string]::IsNullOrWhiteSpace($support)) {
            continue
        }

        $contracts.Add([ordered]@{
            supports = $support
            status = "candidate_evidence_harvested"
            evidence_markers = @($Markers | Where-Object { [string]$_.supports -eq $support } | ForEach-Object { [string]$_.marker_id })
        })
    }

    return $contracts.ToArray()
}

function Add-GenericCandidates {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [object]$Contract
    )

    Add-CandidatePath -Candidates $Candidates -Path "README.md" -Reason "canonical-readme-contract" -Priority 10
    Add-CandidatePath -Candidates $Candidates -Path "schema.json" -Reason "schema-contract" -Priority 20
    Add-CandidatePath -Candidates $Candidates -Path "fixtures/db.json" -Reason "fixture-input-contract" -Priority 30
    Add-CandidatePath -Candidates $Candidates -Path "package.json" -Reason "node-runtime-contract" -Priority 40
    Add-CandidatePath -Candidates $Candidates -Path "pyproject.toml" -Reason "python-runtime-contract" -Priority 40
    Add-CandidatePath -Candidates $Candidates -Path "go.mod" -Reason "go-runtime-contract" -Priority 40
    Add-CandidatePath -Candidates $Candidates -Path "Dockerfile" -Reason "container-runtime-contract" -Priority 50
    Add-CandidatePath -Candidates $Candidates -Path "docker-compose.yml" -Reason "container-runtime-contract" -Priority 55

    $matches = $Contract.path_matches
    if ($matches) {
        foreach ($path in @($matches.api_contracts | Select-Object -First 3)) {
            Add-CandidatePath -Candidates $Candidates -Path ([string]$path) -Reason "api-contract-match" -Priority 60
        }
        foreach ($path in @($matches.containers | Select-Object -First 2)) {
            Add-CandidatePath -Candidates $Candidates -Path ([string]$path) -Reason "container-contract-match" -Priority 70
        }
        foreach ($path in @($matches.ci | Select-Object -First 2)) {
            Add-CandidatePath -Candidates $Candidates -Path ([string]$path) -Reason "ci-runtime-command-contract" -Priority 80
        }
        foreach ($path in @($matches.tests | Select-Object -First 2)) {
            Add-CandidatePath -Candidates $Candidates -Path ([string]$path) -Reason "public-test-contract" -Priority 90
        }
    }
}

function Add-RepositorySpecificCandidates {
    param(
        [System.Collections.Generic.List[object]]$Candidates,
        [string]$Repository
    )

    switch ($Repository) {
        "typicode/json-server" {
            Add-CandidatePath -Candidates $Candidates -Path "fixtures/db.json" -Reason "readme-fixture-input" -Priority 5
            Add-CandidatePath -Candidates $Candidates -Path "schema.json" -Reason "readme-schema-reference" -Priority 6
            Add-CandidatePath -Candidates $Candidates -Path ".github/workflows/node.js.yml" -Reason "ci-runtime-command-contract" -Priority 75
        }
        "fastapi/fastapi" {
            Add-CandidatePath -Candidates $Candidates -Path "pyproject.toml" -Reason "python-runtime-contract" -Priority 20
            Add-CandidatePath -Candidates $Candidates -Path "docs_src/first_steps/tutorial001.py" -Reason "readme-tutorial-runtime" -Priority 25
        }
        "pallets/flask" {
            Add-CandidatePath -Candidates $Candidates -Path "pyproject.toml" -Reason "python-runtime-contract" -Priority 20
            Add-CandidatePath -Candidates $Candidates -Path "examples/tutorial/flaskr/__init__.py" -Reason "public-runtime-example" -Priority 35
        }
        "gin-gonic/gin" {
            Add-CandidatePath -Candidates $Candidates -Path "go.mod" -Reason "go-runtime-contract" -Priority 20
            Add-CandidatePath -Candidates $Candidates -Path "examples/basic/main.go" -Reason "public-runtime-example" -Priority 25
        }
        "denoland/deno" {
            Add-CandidatePath -Candidates $Candidates -Path "README.md" -Reason "canonical-readme-contract" -Priority 5
            Add-CandidatePath -Candidates $Candidates -Path "cli/schemas/config-file.v1.json" -Reason "public-schema-contract" -Priority 30
            Add-CandidatePath -Candidates $Candidates -Path "cli/schemas/permission-audit.v1.json" -Reason "public-schema-contract" -Priority 31
        }
        "unclecode/crawl4ai" {
            Add-CandidatePath -Candidates $Candidates -Path "Dockerfile" -Reason "container-runtime-contract" -Priority 20
            Add-CandidatePath -Candidates $Candidates -Path "docker-compose.yml" -Reason "container-runtime-contract" -Priority 25
        }
        "expressjs/express" {
            Add-CandidatePath -Candidates $Candidates -Path "Readme.md" -Reason "canonical-readme-contract" -Priority 9
            Add-CandidatePath -Candidates $Candidates -Path "package.json" -Reason "node-runtime-contract" -Priority 20
            Add-CandidatePath -Candidates $Candidates -Path "examples/hello-world/index.js" -Reason "public-runtime-example" -Priority 25
            Add-CandidatePath -Candidates $Candidates -Path "test/acceptance/hello-world.js" -Reason "public-test-contract" -Priority 35
        }
        "spring-projects/spring-boot" {
            Add-CandidatePath -Candidates $Candidates -Path "README.adoc" -Reason "canonical-readme-contract" -Priority 5
            Add-CandidatePath -Candidates $Candidates -Path "documentation/spring-boot-docs/src/docs/antora/modules/how-to/pages/webserver.adoc" -Reason "default-http-port-contract" -Priority 6
            Add-CandidatePath -Candidates $Candidates -Path "build.gradle" -Reason "repo-build-contract" -Priority 20
            Add-CandidatePath -Candidates $Candidates -Path "gradlew" -Reason "repo-build-command-contract" -Priority 25
        }
    }
}

$contractFiles = @(Get-ChildItem -LiteralPath $ContractsDir -Recurse -File -Filter "repo-contract.json")
$contractsByRepo = @{}
foreach ($contractFile in $contractFiles) {
    $contract = Get-Content -LiteralPath $contractFile.FullName -Raw | ConvertFrom-Json
    $contractsByRepo[[string]$contract.repository] = [ordered]@{
        path = $contractFile.FullName
        contract = $contract
    }
}

$records = New-Object System.Collections.Generic.List[object]
$selectedRepositories = @($Repositories | Select-Object -First $MaxRepositories)
$totalFetchedBytes = 0

foreach ($repository in $selectedRepositories) {
    if (-not $contractsByRepo.ContainsKey($repository)) {
        throw "No harvested contract found for selected repository: $repository"
    }

    $entry = $contractsByRepo[$repository]
    $contract = $entry.contract
    $treePath = [string]$contract.tree_snapshot
    $readmePath = [string]$contract.readme_snapshot
    if (-not (Test-Path -LiteralPath $treePath)) {
        throw "Tree snapshot missing for ${repository}: $treePath"
    }
    if (-not (Test-Path -LiteralPath $readmePath)) {
        throw "README snapshot missing for ${repository}: $readmePath"
    }

    $safeRepo = "{0:D3}-{1}" -f [int]$contract.rank, (New-SafeName $repository.Replace("/", "-"))
    $repoOutDir = Join-Path $OutDir $safeRepo
    $filesDir = Join-Path $repoOutDir "files"
    [System.IO.Directory]::CreateDirectory($filesDir) | Out-Null

    $treeResponse = Get-Content -LiteralPath $treePath -Raw | ConvertFrom-Json
    $tree = @($treeResponse.tree)
    $readme = Get-Content -LiteralPath $readmePath -Raw

    $candidates = New-Object System.Collections.Generic.List[object]
    Add-GenericCandidates -Candidates $candidates -Contract $contract
    Add-RepositorySpecificCandidates -Candidates $candidates -Repository $repository
    $orderedCandidates = @($candidates | Sort-Object @{ Expression = { [int]$_.priority }; Ascending = $true }, @{ Expression = { [string]$_.path }; Ascending = $true })

    $fetchedFiles = New-Object System.Collections.Generic.List[object]
    $skippedFiles = New-Object System.Collections.Generic.List[object]
    $seenSourcePaths = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::Ordinal)

    foreach ($candidate in $orderedCandidates) {
        if ($fetchedFiles.Count -ge $MaxFilesPerRepository) {
            break
        }

        $sourcePath = [string]$candidate.path
        if (-not $seenSourcePaths.Add($sourcePath)) {
            $skippedFiles.Add([ordered]@{
                source_path = $sourcePath
                reason = "duplicate_selected_path"
            })
            continue
        }

        $treeItem = Get-TreeItemByPath -Tree $tree -Path $sourcePath
        if (-not $treeItem) {
            $skippedFiles.Add([ordered]@{
                source_path = $sourcePath
                reason = "path_not_found_in_tree_snapshot"
            })
            continue
        }

        $size = [int]$treeItem.size
        if ($size -gt $MaxFileBytes) {
            $skippedFiles.Add([ordered]@{
                source_path = $sourcePath
                size = $size
                reason = "file_exceeds_max_file_bytes"
            })
            continue
        }

        $destPath = [System.IO.Path]::GetFullPath((Join-Path $filesDir ($sourcePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
        $resolvedFilesDir = [System.IO.Path]::GetFullPath($filesDir)
        if (-not $destPath.StartsWith($resolvedFilesDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Resolved selected file path escaped output directory: $sourcePath"
        }

        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $destPath)) | Out-Null
        $bytes = Get-GhBlobBytes -Url ([string]$treeItem.url)
        if ($bytes.Length -ne $size) {
            throw "GitHub blob byte length mismatch for ${repository}:${sourcePath}. tree=$size fetched=$($bytes.Length)"
        }
        if (($totalFetchedBytes + $bytes.Length) -gt $MaxTotalBytes) {
            throw "Selected public contract harvest exceeded MaxTotalBytes=$MaxTotalBytes before ${repository}:${sourcePath}"
        }

        $gitBlobSha = Get-GitBlobSha -Bytes $bytes
        if (-not $gitBlobSha.Equals([string]$treeItem.sha, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "GitHub blob sha mismatch for ${repository}:${sourcePath}. tree=$($treeItem.sha) fetched=$gitBlobSha"
        }

        if (-not (Test-Utf8Text -Bytes $bytes)) {
            throw "Selected public contract blob is not valid UTF-8 text: ${repository}:${sourcePath}"
        }

        if (Test-LfsPointer -Bytes $bytes) {
            throw "Selected public contract blob is a Git LFS pointer, not contract content: ${repository}:${sourcePath}"
        }

        [System.IO.File]::WriteAllBytes($destPath, $bytes)
        $contentSha256 = Get-Sha256Hex -Bytes $bytes
        $totalFetchedBytes += $bytes.Length

        $fetchedFiles.Add([ordered]@{
            source_path = $sourcePath
            local_path = $destPath
            sha = [string]$treeItem.sha
            git_blob_sha_verified = $true
            content_sha256 = $contentSha256
            size = $size
            fetched_size = $bytes.Length
            reason = [string]$candidate.reason
            github_blob_url = [string]$treeItem.url
        })
    }

    $markers = @(Get-ReadmeMarkers -Repository $repository -Readme $readme)
    $candidatePromotionContracts = @(Get-CandidatePromotionContracts -Markers $markers)
    $recordPath = Join-Path $repoOutDir "selected-contract.json"

    $selectedContract = [ordered]@{
        schema_version = 1
        harvested_at = (Get-Date).ToString("o")
        repository = $repository
        rank = [int]$contract.rank
        source_contract = [string]$entry.path
        readme_snapshot = $readmePath
        tree_snapshot = $treePath
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
        readiness_state = "selected_public_contract_content_harvested"
        policy = "Exact small public GitHub blob contents only; no cloning, no repository execution, no executable QaaS promotion."
        max_file_bytes = $MaxFileBytes
        fetched_files = $fetchedFiles.ToArray()
        selected_public_contracts = $fetchedFiles.ToArray()
        skipped_files = $skippedFiles.ToArray()
        evidence_markers = $markers
        candidate_promotion_contracts = $candidatePromotionContracts
        docs_evidence = @(
            "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md",
            "D:\QaaS\qaas-docs\docs\qaas\quickStart\actionSelectionPlaybook.md",
            "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
        )
        public_evidence = @(
            [string]$entry.path
            $readmePath
            $treePath
            @($fetchedFiles | ForEach-Object { [string]$_.local_path })
        )
        remaining_blockers = @(
            "generate_candidate_runner_yaml_from_exact_public_contract",
            "prove_process_lifecycle_and_cleanup_without assuming private source",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
    }

    $selectedContract | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $recordPath -Encoding UTF8
    $records.Add([ordered]@{
        repository = $repository
        rank = [int]$contract.rank
        record_path = $recordPath
        fetched_file_count = $fetchedFiles.Count
        marker_count = $markers.Count
        status = "contract_content_harvested_not_executable"
        promotion_state = "blocked"
    })
}

$index = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    source_contracts_directory = $ContractsDir
    output_directory = $OutDir
    selected_repository_count = $records.Count
    max_repositories = $MaxRepositories
    max_file_bytes = $MaxFileBytes
    max_files_per_repository = $MaxFilesPerRepository
    max_total_bytes = $MaxTotalBytes
    total_fetched_bytes = $totalFetchedBytes
    policy = "Selected contract harvest fetches exact public blob contents only and does not promote QaaS artifacts."
    records = $records.ToArray()
}

$indexPath = Join-Path $OutDir "selected-contract-index.json"
$index | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $indexPath -Encoding UTF8
Write-Output "Harvested selected public contract files for $($records.Count) repositories."
Write-Output "Index: $indexPath"
