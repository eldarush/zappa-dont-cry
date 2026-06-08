param(
    [string]$SeedRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\promotion-seed\qaas-docs-hello-world-http",
    [string]$HarnessRoot = "D:\QaaS\_tools\zappa-harness",
    [string]$DocsRoot = "D:\QaaS\qaas-docs\docs",
    [string]$LocalPackageSource = "D:\QaaS\_localfeed\packages",
    [int]$PreferredPort = 18080,
    [switch]$AttemptLiveAirgapped
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedPath {
    param([string]$Path)

    $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
}

function Assert-DescendantPath {
    param(
        [string]$Path,
        [string]$Root,
        [string]$Description
    )

    $fullPath = Get-NormalizedPath -Path $Path
    $rootPath = Get-NormalizedPath -Path $Root
    $rootPrefix = "$rootPath$([System.IO.Path]::DirectorySeparatorChar)"
    if (
        [string]::Equals($fullPath, $rootPath, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
        throw "$Description must stay under $rootPath; got $fullPath"
    }

    return $fullPath
}

$allowedRoot = Get-NormalizedPath -Path "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\promotion-seed"
$seedRootPath = Assert-DescendantPath -Path $SeedRoot -Root $allowedRoot -Description "SeedRoot"

if (Test-Path -LiteralPath $seedRootPath) {
    $resolved = Get-NormalizedPath -Path (Resolve-Path -LiteralPath $seedRootPath).Path
    [void](Assert-DescendantPath -Path $resolved -Root $allowedRoot -Description "Resolved SeedRoot")
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

$runnerRoot = Join-Path $seedRootPath "runner"
$mockerRoot = Join-Path $seedRootPath "mocker"
$evidenceRoot = Join-Path $seedRootPath "evidence"
[System.IO.Directory]::CreateDirectory($runnerRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($mockerRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($evidenceRoot) | Out-Null

function ConvertTo-SafeFileName {
    param([string]$Value)
    return ($Value -replace '[^A-Za-z0-9_.-]', '_')
}

function Invoke-ExternalCommand {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string[]]$ArgumentList,
        [switch]$FailOnError
    )

    $transcript = Join-Path $evidenceRoot "$($Name).transcript.txt"
    $command = "dotnet $($ArgumentList -join ' ')"
    $started = Get-Date
    $global:LASTEXITCODE = 0
    try {
        $output = & dotnet @ArgumentList 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    } catch {
        $output = @($_.Exception.ToString())
        $exitCode = 1
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Command: $command")
    $lines.Add("WorkingDirectory: $WorkingDirectory")
    $lines.Add("Started: $($started.ToString('o'))")
    $lines.Add("ExitCode: $exitCode")
    $lines.Add("")
    foreach ($line in @($output)) {
        $lines.Add([string]$line)
    }
    $lines | Set-Content -LiteralPath $transcript -Encoding UTF8

    if ($FailOnError -and $exitCode -ne 0) {
        throw "Command failed: $command. See $transcript"
    }

    [pscustomobject]@{
        name = $Name
        command = $command
        exit_code = $exitCode
        transcript = $transcript
        status = if ($exitCode -eq 0) { "passed" } else { "failed" }
    }
}

function Join-ValidationTranscripts {
    param(
        [string]$Name,
        [object[]]$Results
    )

    $combined = Join-Path $evidenceRoot "$Name.transcript.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($result in $Results) {
        $lines.Add("==== $($result.name) ====")
        $lines.Add("Command: $($result.command)")
        $lines.Add("ExitCode: $($result.exit_code)")
        $lines.Add("Transcript: $($result.transcript)")
        $lines.Add("")
        if (Test-Path -LiteralPath $result.transcript -PathType Leaf) {
            $lines.Add((Get-Content -LiteralPath $result.transcript -Raw))
        }
        $lines.Add("")
    }
    $lines | Set-Content -LiteralPath $combined -Encoding UTF8
    return $combined
}

function New-ValidationRecord {
    param(
        [string]$Name,
        [object[]]$Results
    )

    $combined = Join-ValidationTranscripts -Name $Name -Results $Results
    $failed = @($Results | Where-Object { [int]$_.exit_code -ne 0 })
    [ordered]@{
        status = if ($failed.Count -eq 0) { "passed" } else { "failed" }
        exit_code = if ($failed.Count -eq 0) { 0 } else { 1 }
        command = (($Results | ForEach-Object { $_.command }) -join " ; ")
        transcript = $combined
    }
}

function Get-FreeTcpPort {
    param([int]$Preferred)

    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $connect = $client.BeginConnect("127.0.0.1", $Preferred, $null, $null)
            $connected = $connect.AsyncWaitHandle.WaitOne(200)
            if (-not $connected -or -not $client.Connected) {
                return $Preferred
            }
        } finally {
            $client.Dispose()
        }
    } catch {
        return $Preferred
    }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

function Invoke-LiveValidation {
    param(
        [string]$RunnerProject,
        [string]$RunnerYaml,
        [string]$MockerProject,
        [string]$MockerYaml,
        [int]$Port
    )

    $stdoutPath = Join-Path $evidenceRoot "mocker-live.stdout.txt"
    $stderrPath = Join-Path $evidenceRoot "mocker-live.stderr.txt"
    $runnerTranscript = $null
    $mockerProcess = $null
    $ready = $false
    $readyStatus = ""
    try {
        $arguments = @(
            "run",
            "--project",
            $MockerProject,
            "--",
            "run",
            $MockerYaml,
            "--no-env"
        )
        $mockerProcess = Start-Process -FilePath "dotnet" -ArgumentList $arguments -WorkingDirectory $mockerRoot -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

        $deadline = (Get-Date).AddSeconds(45)
        while ((Get-Date) -lt $deadline) {
            if ($mockerProcess.HasExited) {
                $readyStatus = "mocker process exited with code $($mockerProcess.ExitCode)"
                break
            }
            try {
                $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/hello" -UseBasicParsing -TimeoutSec 2
                if ([int]$response.StatusCode -eq 200) {
                    $ready = $true
                    $readyStatus = "HTTP 200 from /hello"
                    break
                }
            } catch {
                Start-Sleep -Milliseconds 500
            }
        }

        if ($ready) {
            $runnerResult = Invoke-ExternalCommand -Name "live-runner-run" -WorkingDirectory $runnerRoot -ArgumentList @(
                "run",
                "--project",
                $RunnerProject,
                "--",
                "run",
                $RunnerYaml,
                "-e",
                "--no-env"
            )
            $runnerTranscript = $runnerResult.transcript
            $exitCode = [int]$runnerResult.exit_code
        } else {
            $exitCode = 1
        }
    } finally {
        if ($null -ne $mockerProcess -and -not $mockerProcess.HasExited) {
            Stop-Process -Id $mockerProcess.Id -Force
            $mockerProcess.WaitForExit(5000) | Out-Null
        }
    }

    $transcript = Join-Path $evidenceRoot "live-validation.transcript.txt"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Command: start mocker, wait for /hello, run runner")
    $lines.Add("Port: $Port")
    $lines.Add("Ready: $ready")
    $lines.Add("ReadyStatus: $readyStatus")
    $lines.Add("ExitCode: $exitCode")
    $lines.Add("")
    $lines.Add("==== mocker stdout ====")
    if (Test-Path -LiteralPath $stdoutPath) {
        $lines.Add((Get-Content -LiteralPath $stdoutPath -Raw))
    }
    $lines.Add("==== mocker stderr ====")
    if (Test-Path -LiteralPath $stderrPath) {
        $lines.Add((Get-Content -LiteralPath $stderrPath -Raw))
    }
    if ($runnerTranscript) {
        $lines.Add("==== runner transcript ====")
        $lines.Add((Get-Content -LiteralPath $runnerTranscript -Raw))
    }
    $lines | Set-Content -LiteralPath $transcript -Encoding UTF8

    [ordered]@{
        status = if ($ready -and $exitCode -eq 0) { "passed" } else { "failed" }
        exit_code = $exitCode
        command = "dotnet run --project $MockerProject -- run $MockerYaml --no-env ; dotnet run --project $RunnerProject -- run $RunnerYaml -e --no-env"
        transcript = $transcript
    }
}

$port = Get-FreeTcpPort -Preferred $PreferredPort

$newRunner = Invoke-ExternalCommand -Name "dotnet-new-runner" -WorkingDirectory $seedRootPath -ArgumentList @("new", "qaas-runner", "-n", "ZappaPromotionSeed.Runner", "-o", $runnerRoot) -FailOnError
$newMocker = Invoke-ExternalCommand -Name "dotnet-new-mocker" -WorkingDirectory $seedRootPath -ArgumentList @("new", "qaas-mocker", "-n", "ZappaPromotionSeed.Mocker", "-o", $mockerRoot) -FailOnError

$runnerProjectRoot = Join-Path $runnerRoot "ZappaPromotionSeed.Runner"
$mockerProjectRoot = Join-Path $mockerRoot "ZappaPromotionSeed.Mocker"
$runnerProject = Join-Path $runnerProjectRoot "ZappaPromotionSeed.Runner.csproj"
$mockerProject = Join-Path $mockerProjectRoot "ZappaPromotionSeed.Mocker.csproj"
$runnerYaml = Join-Path $runnerProjectRoot "test.qaas.yaml"
$mockerYaml = Join-Path $mockerProjectRoot "mocker.qaas.yaml"
$sessionDataRoot = Join-Path $runnerProjectRoot "session-data"
[System.IO.Directory]::CreateDirectory($sessionDataRoot) | Out-Null

$packageResults = @(
    Invoke-ExternalCommand -Name "package-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Runner", "--version", "4.5.1", "--source", $LocalPackageSource) -FailOnError
    Invoke-ExternalCommand -Name "package-runner-assertions" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Assertions", "--version", "3.5.1", "--source", $LocalPackageSource) -FailOnError
    Invoke-ExternalCommand -Name "package-runner-generators" -WorkingDirectory $runnerProjectRoot -ArgumentList @("add", $runnerProject, "package", "QaaS.Common.Generators", "--version", "3.5.1", "--source", $LocalPackageSource) -FailOnError
    Invoke-ExternalCommand -Name "package-mocker" -WorkingDirectory $mockerProjectRoot -ArgumentList @("add", $mockerProject, "package", "QaaS.Mocker", "--version", "2.4.1", "--source", $LocalPackageSource) -FailOnError
    Invoke-ExternalCommand -Name "package-mocker-processors" -WorkingDirectory $mockerProjectRoot -ArgumentList @("add", $mockerProject, "package", "QaaS.Common.Processors", "--version", "1.5.1", "--source", $LocalPackageSource) -FailOnError
)

$testDataRoot = Join-Path $runnerProjectRoot "TestData"
[System.IO.Directory]::CreateDirectory($testDataRoot) | Out-Null
@"
[
  {
    "id": 1,
    "message": "hello from zappa promotion seed"
  }
]
"@ | Set-Content -LiteralPath (Join-Path $testDataRoot "input.json") -Encoding UTF8

$runnerProjectText = Get-Content -LiteralPath $runnerProject -Raw
if ($runnerProjectText -notmatch "TestData\\\*\\\*\\\*") {
    $runnerProjectText = $runnerProjectText -replace "</Project>", @"
  <ItemGroup>
    <None Update="TestData\**\*">
      <CopyToOutputDirectory>Always</CopyToOutputDirectory>
    </None>
  </ItemGroup>

</Project>
"@
    $runnerProjectText | Set-Content -LiteralPath $runnerProject -Encoding UTF8
}

$runnerYamlText = @"
MetaData:
  Team: Zappa
  System: QaaSHelloWorldHttp

DataSources:
  - Name: HelloInputs
    Generator: FromFileSystem
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: TestData

Storages:
  - JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

Sessions:
  - Name: HelloSession
    Transactions:
      - Name: CallHello
        TimeoutMs: 5000
        DataSourceNames: [HelloInputs]
        Http:
          BaseAddress: http://127.0.0.1
          Port: $port
          Route: hello
          Method: Get

Assertions:
  - Name: ReturnedOk
    Assertion: HttpStatus
    SessionNames: [HelloSession]
    AssertionConfiguration:
      StatusCode: 200
      OutputNames: [CallHello]
"@
$runnerYamlText | Set-Content -LiteralPath $runnerYaml -Encoding UTF8

$mockerYamlText = @"
Stubs:
  - Name: HelloStub
    Processor: StaticResponseProcessor
    ProcessorConfiguration:
      Body: hello
      StatusCode: 200
      ContentType: text/plain; charset=utf-8
      ResponseHeaders: {}

Servers:
  - Http:
      Port: $port
      IsLocalhost: true
      Endpoints:
        - Path: /hello
          Actions:
            - Name: HelloOk
              Method: Get
              TransactionStubName: HelloStub
"@
$mockerYamlText | Set-Content -LiteralPath $mockerYaml -Encoding UTF8

$buildResults = @(
    Invoke-ExternalCommand -Name "build-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("build", $runnerProject, "--nologo", "-clp:ErrorsOnly")
    Invoke-ExternalCommand -Name "build-mocker" -WorkingDirectory $mockerProjectRoot -ArgumentList @("build", $mockerProject, "--nologo", "-clp:ErrorsOnly")
)
$buildValidation = New-ValidationRecord -Name "build-validation" -Results $buildResults

$templateResults = @(
    Invoke-ExternalCommand -Name "template-runner" -WorkingDirectory $runnerProjectRoot -ArgumentList @("run", "--project", $runnerProject, "--", "template", $runnerYaml, "--no-env")
    Invoke-ExternalCommand -Name "template-mocker" -WorkingDirectory $mockerProjectRoot -ArgumentList @("run", "--project", $mockerProject, "--", "template", $mockerYaml, "--no-env")
)
$templateValidation = New-ValidationRecord -Name "template-validation" -Results $templateResults

$liveValidation = Invoke-LiveValidation -RunnerProject $runnerProject -RunnerYaml $runnerYaml -MockerProject $mockerProject -MockerYaml $mockerYaml -Port $port

$airgappedOut = Join-Path $seedRootPath "airgapped"
$airgappedIndex = Join-Path $airgappedOut "promotion-seed-airgapped-index.json"
$airgappedExpectedPatterns = @(
    "intent_assumptions",
    "docs_evidence",
    "artifact_plan",
    "validation_sequence",
    "airgapped_result",
    "strong_review",
    "next_blocker",
    "weak_validation_passed:\s*true",
    "dry_run:\s*false"
)
$airgappedPrompt = @"
Review the generated QaaS promotion seed against public QaaS docs only.

Seed root: $seedRootPath
Runner YAML: $runnerYaml
Mocker YAML: $mockerYaml

Return intent_assumptions, docs_evidence, artifact_plan, validation_sequence, airgapped_result, strong_review, and next_blocker. Do not claim executable promotion unless live weak-model behavior, template validation, build validation, and live QaaS run evidence are all present.

For a passing live weak-model result, include these exact lines in the response:
weak_validation_passed: true
dry_run: false
"@
$airgappedArgs = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $HarnessRoot "scripts\run-airgapped-validation.ps1"),
    "-Prompt",
    $airgappedPrompt,
    "-SkillPath",
    "C:\Users\eldar\.codex\skills\zappa-dont-cry\zappa-qaas-test-author\SKILL.md",
    "-OutDir",
    $airgappedOut,
    "-ScenarioId",
    "promotion-seed-qaas-docs-hello-world-http",
    "-ScenarioKind",
    "scenario",
    "-IndexPath",
    $airgappedIndex,
    "-ReasoningEffort",
    "none",
    "-TimeoutSeconds",
    "180"
)
if (-not $AttemptLiveAirgapped) {
    $airgappedArgs += "-DryRun"
} else {
    $airgappedArgs += "-All"
}
$airgappedArgs += @("-ExpectPattern") + $airgappedExpectedPatterns

$airgappedTranscript = Join-Path $evidenceRoot "airgapped-validation.transcript.txt"
$global:LASTEXITCODE = 0
try {
    $airgappedOutput = & powershell @airgappedArgs 2>&1
    $airgappedExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
} catch {
    $airgappedOutput = @($_.Exception.ToString())
    $airgappedExitCode = 1
}
$airgappedOutput | Set-Content -LiteralPath $airgappedTranscript -Encoding UTF8
$summaryMatch = [regex]::Match(($airgappedOutput | Out-String), "Summary:\s*(?<path>.+)")
$airgappedSummary = if ($summaryMatch.Success) { $summaryMatch.Groups["path"].Value.Trim() } else { $airgappedTranscript }

function Test-LiveAirgappedPass {
    param(
        [bool]$Attempted,
        [int]$ExitCode,
        [string]$SummaryPath,
        [string]$WrapperTranscript
    )

    if (-not $Attempted -or $ExitCode -ne 0) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
        return $false
    }
    if (-not (Test-Path -LiteralPath $WrapperTranscript -PathType Leaf)) {
        return $false
    }

    $summaryText = Get-Content -LiteralPath $SummaryPath -Raw
    $wrapperText = Get-Content -LiteralPath $WrapperTranscript -Raw
    return (
        $summaryText -match "DryRun:\s*False" -and
        $summaryText -match "Airgapped:\s*True" -and
        $summaryText -match "(?m)^- PASS exit 0:" -and
        $summaryText -notmatch "(?m)^- FAIL " -and
        $wrapperText -match "Weak model validation complete\." -and
        $wrapperText -match "Summary:\s*" -and
        $wrapperText -match "Transcript:\s*"
    )
}

$airgappedLivePassed = Test-LiveAirgappedPass -Attempted:$AttemptLiveAirgapped.IsPresent -ExitCode $airgappedExitCode -SummaryPath $airgappedSummary -WrapperTranscript $airgappedTranscript
$airgappedStatus = if ($airgappedLivePassed) { "passed" } elseif ($AttemptLiveAirgapped) { "blocked" } else { "dry_run_prompt_assembly" }

$allValidationsPassed = (
    $templateValidation.status -eq "passed" -and
    $buildValidation.status -eq "passed" -and
    $liveValidation.status -eq "passed" -and
    $airgappedStatus -eq "passed"
)

$docsEvidence = @(
    [ordered]@{
        path = (Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md")
        claim = "Documents the smallest end-to-end Runner plus Mocker HTTP smoke test."
        supports = @("runner-mocker-http-seed", "live_validation.command")
    },
    [ordered]@{
        path = (Join-Path $DocsRoot "processors\availableProcessors\StaticResponseProcessor\overview.md")
        claim = "Documents StaticResponseProcessor and the /hello HTTP stub shape."
        supports = @("mocker.qaas.yaml", "StaticResponseProcessor")
    },
    [ordered]@{
        path = (Join-Path $DocsRoot "assertions\availableAssertions\HttpStatus\overview.md")
        claim = "Documents HttpStatus assertion semantics."
        supports = @("test.qaas.yaml", "HttpStatus")
    },
    [ordered]@{
        path = (Join-Path $DocsRoot "assets\schemas\runner-family-schema.json")
        claim = "Schema evidence for Runner YAML top-level sections and HttpStatus fields."
        supports = @("runner-family-schema", "template_validation.command")
    },
    [ordered]@{
        path = (Join-Path $DocsRoot "assets\schemas\mocker-family-schema.json")
        claim = "Schema evidence for Mocker YAML top-level sections and StaticResponseProcessor fields."
        supports = @("mocker-family-schema", "template_validation.command")
    }
)

$intentQuestions = @(
    [ordered]@{
        question_id = "behavior"
        question = "What behavior must be proven?"
        self_answer = "An HTTP Runner transaction must call a Mocker /hello endpoint and the HttpStatus assertion must observe HTTP 200."
        answer_source = "public_docs"
        risk_if_wrong = "The seed would prove only process startup instead of QaaS act/assert behavior."
        how_to_override = "Provide a different public docs-backed behavior and update the seed YAML plus manifest evidence."
        public_evidence = @((Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md"))
    },
    [ordered]@{
        question_id = "boundary"
        question = "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?"
        self_answer = "The boundary is a Runner host plus a local Mocker dependency; no top-repo code and no private QaaS source are required."
        answer_source = "public_docs"
        risk_if_wrong = "A broader boundary would need repository-specific contracts and more dependency gates."
        how_to_override = "Add explicit repo/component contracts before broadening the seed."
        public_evidence = @((Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md"))
    },
    [ordered]@{
        question_id = "docs_schema_evidence"
        question = "What public docs/schema path proves the capability exists?"
        self_answer = "The hello-world HTTP guide, StaticResponseProcessor docs, HttpStatus docs, and runner/mocker schema assets prove the YAML shape."
        answer_source = "public_docs"
        risk_if_wrong = "Unsupported YAML fields could be generated for weak models."
        how_to_override = "Update docs evidence and rerun template validation."
        public_evidence = @(
            (Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md"),
            (Join-Path $DocsRoot "processors\availableProcessors\StaticResponseProcessor\overview.md"),
            (Join-Path $DocsRoot "assertions\availableAssertions\HttpStatus\overview.md"),
            (Join-Path $DocsRoot "assets\schemas\runner-family-schema.json"),
            (Join-Path $DocsRoot "assets\schemas\mocker-family-schema.json")
        )
    },
    [ordered]@{
        question_id = "inputs_outputs_side_effects"
        question = "What inputs, outputs, and side effects prove success?"
        self_answer = "Input is the Runner HTTP GET; output is a saved transaction with HTTP status 200; side effects are local session data and Allure results."
        answer_source = "public_docs"
        risk_if_wrong = "The assertion could pass against the wrong output name or stale session data."
        how_to_override = "Change OutputNames and clear storage through the live validation command."
        public_evidence = @((Join-Path $DocsRoot "assertions\availableAssertions\HttpStatus\overview.md"))
    },
    [ordered]@{
        question_id = "negative_cases"
        question = "Which negative, malformed, outage, retry, cleanup, and observability cases matter?"
        self_answer = "The seed covers only the positive HTTP 200 path; outage and wrong-status cases remain future negative coverage."
        answer_source = "blocked"
        risk_if_wrong = "The seed may be overinterpreted as broad HTTP coverage."
        how_to_override = "Add negative seed cases after the positive lifecycle is promotable."
        public_evidence = @((Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md"))
    },
    [ordered]@{
        question_id = "dependencies"
        question = "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?"
        self_answer = "Only .NET SDK, local QaaS NuGet packages, and an available localhost HTTP port are required."
        answer_source = "assumption"
        risk_if_wrong = "Port conflicts or missing local packages will block template/build/live evidence."
        how_to_override = "Pass a different PreferredPort or restore package source, then regenerate the seed."
        public_evidence = @((Join-Path $DocsRoot "qaas\quickStart\installation.md"))
    },
    [ordered]@{
        question_id = "runnability"
        question = "What can run now, and what must be deferred?"
        self_answer = "Template, build, and local live Runner/Mocker validation can run now; executable promotion is deferred until live airgapped weak validation passes."
        answer_source = "blocked"
        risk_if_wrong = "Dry-run weak validation could be mistaken for live weak-model behavior."
        how_to_override = "Rerun with AttemptLiveAirgapped when hosted weak-model quota is available."
        public_evidence = @((Join-Path $HarnessRoot "references\airgapped-validation.md"))
    }
)

$intentAssumptions = @(
    [ordered]@{ assumption = "The local dotnet templates represent the public QaaS Runner and Mocker host pattern."; why_safe = "The public docs invoke dotnet new qaas-runner and qaas-mocker for these hosts."; risk_if_wrong = "Generated hosts may not match published package behavior."; how_to_override = "Use an explicitly provided public host template or package version."; public_evidence = @((Join-Path $DocsRoot "qaas\quickStart\installation.md")) },
    [ordered]@{ assumption = "A localhost port can be allocated for the Mocker HTTP server."; why_safe = "The generator probes for an available port before writing YAML."; risk_if_wrong = "A race could still occupy the port before live validation."; how_to_override = "Rerun with a different PreferredPort."; public_evidence = @((Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md")) },
    [ordered]@{ assumption = "The positive HTTP 200 seed is a lifecycle seed, not full HTTP coverage."; why_safe = "The manifest stays blocked and records missing negative coverage."; risk_if_wrong = "Users may overgeneralize the seed."; how_to_override = "Add separate negative cases and assertions."; public_evidence = @((Join-Path $DocsRoot "assertions\availableAssertions\HttpStatus\overview.md")) },
    [ordered]@{ assumption = "StaticResponseProcessor is available through the local QaaS.Common.Processors package."; why_safe = "The local package source contains QaaS.Common.Processors and the docs document StaticResponseProcessor."; risk_if_wrong = "Mocker template validation or live startup will fail."; how_to_override = "Provide a package source with the documented processor package."; public_evidence = @((Join-Path $DocsRoot "processors\availableProcessors\StaticResponseProcessor\overview.md")) },
    [ordered]@{ assumption = "HttpStatus uses StatusCode and OutputNames despite helloWorldHttp prose showing ExpectedStatus."; why_safe = "The schema and HttpStatus reference page agree on StatusCode and OutputNames."; risk_if_wrong = "The Runner template command would reject the assertion configuration."; how_to_override = "Regenerate from updated schema if the public schema changes."; public_evidence = @((Join-Path $DocsRoot "assets\schemas\runner-family-schema.json"), (Join-Path $DocsRoot "assertions\availableAssertions\HttpStatus\overview.md")) },
    [ordered]@{ assumption = "Airgapped dry-run output is useful prompt assembly evidence only."; why_safe = "The weak-model gate forbids accepting dry-run weak validation as behavior."; risk_if_wrong = "The seed could be promoted without a weak model actually following the skill."; how_to_override = "Rerun live airgapped validation and require status passed."; public_evidence = @((Join-Path $HarnessRoot "references\airgapped-validation.md")) },
    [ordered]@{ assumption = "No top-repo contract is needed for this docs-owned seed."; why_safe = "The seed's source_repository is qaas-docs rather than a target repo."; risk_if_wrong = "The seed would not prove top-250 repo readiness."; how_to_override = "Keep top-repo promotion separate and require repo contracts."; public_evidence = @((Join-Path $HarnessRoot "references\artifact-contract.md")) }
)

$dependencyGates = @(
    [ordered]@{
        gate_id = "local-dotnet-sdk"
        kind = "runtime"
        required = $true
        status = "passed"
        evidence = @($newRunner.transcript, $newMocker.transcript)
        check_command = "dotnet new qaas-runner and dotnet new qaas-mocker"
        blocked_reason = ""
    },
    [ordered]@{
        gate_id = "qaas-template"
        kind = "qaas-template"
        required = $true
        status = $templateValidation.status
        evidence = @($templateValidation.transcript)
        check_command = $templateValidation.command
        blocked_reason = if ($templateValidation.status -eq "passed") { "" } else { "Runner or Mocker template command failed." }
    },
    [ordered]@{
        gate_id = "qaas-build"
        kind = "qaas-build"
        required = $true
        status = $buildValidation.status
        evidence = @($buildValidation.transcript)
        check_command = $buildValidation.command
        blocked_reason = if ($buildValidation.status -eq "passed") { "" } else { "Runner or Mocker build failed." }
    },
    [ordered]@{
        gate_id = "local-live-run"
        kind = "runtime"
        required = $true
        status = $liveValidation.status
        evidence = @($liveValidation.transcript)
        check_command = $liveValidation.command
        blocked_reason = if ($liveValidation.status -eq "passed") { "" } else { "Local Runner/Mocker live validation failed." }
    },
    [ordered]@{
        gate_id = "live-airgapped-weak-model"
        kind = "airgapped"
        required = $true
        status = if ($airgappedStatus -eq "passed") { "passed" } else { "blocked" }
        evidence = @($airgappedTranscript, $airgappedSummary)
        check_command = "run-airgapped-validation.ps1 for zappa-qaas-test-author"
        blocked_reason = if ($airgappedStatus -eq "passed") { "" } elseif ($AttemptLiveAirgapped) { "Hosted weak-model validation did not pass." } else { "Only dry-run prompt assembly was executed; live weak-model behavior is still required." }
    }
)

$sourceOnlyBlockers = if ($allValidationsPassed) {
    @()
} else {
    @(
        [ordered]@{
            blocker_id = "promotion-seed-live-airgapped-not-passed"
            blocker_type = "qaas_docs_contract"
            description = "The docs-backed seed cannot be promoted until live airgapped weak-model validation passes."
            required_evidence = @("Live weak-model transcript for this seed with weak_validation_passed: true and dry_run: false.")
            public_evidence = @((Join-Path $HarnessRoot "references\airgapped-validation.md"))
            unblock_instruction = "Rerun generate-promotion-seed.ps1 with -AttemptLiveAirgapped after hosted weak-model quota is available."
        }
    )
}

$promotionState = if ($allValidationsPassed) { "executable" } else { "blocked" }
$status = if ($allValidationsPassed) { "executable" } else { "blocked_until_contract_review" }
$blockedReason = if ($allValidationsPassed) { "" } else { "Template/build/local live validation is recorded, but live airgapped weak-model validation has not passed." }

$manifest = [ordered]@{
    schema_version = 1
    campaign_id = "promotion-seed-qaas-docs-hello-world-http"
    source_repository = "qaas-docs"
    source_document = Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md"
    docs_evidence = $docsEvidence
    intent_questions = $intentQuestions
    intent_assumptions = $intentAssumptions
    artifacts = @($runnerYaml, $mockerYaml)
    artifact_count = 2
    artifact_types = @("runner-yaml", "mocker-yaml")
    cases = @(
        [ordered]@{
            case_id = "hello-world-http-runner"
            scenario = "Runner calls the Mocker /hello endpoint and asserts HTTP 200."
            artifact_type = "runner-yaml"
            public_evidence = @((Join-Path $DocsRoot "qaas\quickStart\helloWorldHttp.md"), (Join-Path $DocsRoot "assertions\availableAssertions\HttpStatus\overview.md"))
            setup = @("Start the generated Mocker host on localhost port $port.")
            action = @("Run dotnet run --project runner -- run test.qaas.yaml -e --no-env.")
            assertions = @("HttpStatus checks OutputNames [CallHello] for StatusCode 200.")
            cleanup = @("Stop the Mocker process.", "Clear generated session-data and allure-results on the next regeneration.")
            blocked_reason = $blockedReason
            artifact_paths = @($runnerYaml)
        },
        [ordered]@{
            case_id = "hello-world-http-mocker"
            scenario = "Mocker exposes /hello using StaticResponseProcessor."
            artifact_type = "mocker-yaml"
            public_evidence = @((Join-Path $DocsRoot "processors\availableProcessors\StaticResponseProcessor\overview.md"))
            setup = @("Build the generated Mocker host with QaaS.Common.Processors.")
            action = @("Run dotnet run --project mocker -- run mocker.qaas.yaml --no-env.")
            assertions = @("Readiness probe receives HTTP 200 from /hello before Runner starts.")
            cleanup = @("Stop the Mocker process after Runner validation.")
            blocked_reason = $blockedReason
            artifact_paths = @($mockerYaml)
        }
    )
    assertions = @("HttpStatus StatusCode=200 for output CallHello")
    dependency_gates = $dependencyGates
    cleanup = @("Stop background Mocker process", "Regeneration removes prior promotion seed directory after path guard validation")
    status = $status
    promotion_state = $promotionState
    promotion_requirements = [ordered]@{
        current_state = $promotionState
        required_evidence = @(
            "Public API, CLI, or runtime contract",
            "Public input and expected-output contract",
            "Public dependency/stub contract",
            "Cleanup contract",
            "QaaS template validation result",
            "C# build result when code artifacts exist",
            "Live QaaS run/act/assert result when dependency gates are ready",
            "Airgapped weak-model validation transcript"
        )
    }
    validation_sequence = @(
        "Generate Runner and Mocker hosts with dotnet new.",
        "Pin local QaaS packages from $LocalPackageSource.",
        "Write schema-backed Runner and Mocker YAML from public docs.",
        "Run dotnet build for both generated hosts.",
        "Run dotnet run -- template for both YAML files.",
        "Start Mocker, wait for /hello, and run Runner with -e.",
        "Run airgapped weak-model validation; dry-run evidence is not promotion evidence."
    )
    template_validation = $templateValidation
    build_validation = $buildValidation
    live_validation = $liveValidation
    airgapped_validation = [ordered]@{
        required = $true
        status = $airgappedStatus
        dry_run = -not $AttemptLiveAirgapped
        weak_validation_passed = $airgappedLivePassed
        exit_code = $airgappedExitCode
        command = "run-airgapped-validation.ps1"
        transcript = $airgappedTranscript
        summary = $airgappedSummary
        index = $airgappedIndex
        expected_patterns = $airgappedExpectedPatterns
    }
    source_only_blockers = @($sourceOnlyBlockers)
    blocked_reason = $blockedReason
    validation_evidence = if ($allValidationsPassed) {
        [ordered]@{
            template = $templateValidation.transcript
            build = $buildValidation.transcript
            live = $liveValidation.transcript
            airgapped = $airgappedTranscript
        }
    } else {
        [ordered]@{}
    }
}

$manifestPath = Join-Path $seedRootPath "qaas-artifact-manifest.json"
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Output "Promotion seed generated."
Write-Output "SeedRoot: $seedRootPath"
Write-Output "Manifest: $manifestPath"
Write-Output "TemplateValidation: $($templateValidation.status)"
Write-Output "BuildValidation: $($buildValidation.status)"
Write-Output "LiveValidation: $($liveValidation.status)"
Write-Output "AirgappedValidation: $airgappedStatus"
Write-Output "PromotionState: $promotionState"
