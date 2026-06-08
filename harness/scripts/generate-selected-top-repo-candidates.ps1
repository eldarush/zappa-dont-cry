param(
    [string]$SelectedContractsDir = "D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts",
    [string]$OutDir = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates",
    [switch]$Clean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

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

function ConvertTo-YamlSingleQuoted {
    param([string]$Value)

    $escaped = $Value -replace "'", "''"
    return "'$escaped'"
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
        throw "$Description must stay under $resolvedRoot, got $resolvedPath"
    }

    return $resolvedPath
}

function New-IntentQuestion {
    param(
        [string]$QuestionId,
        [string]$Question,
        [string]$SelfAnswer,
        [string]$AnswerSource,
        [string]$RiskIfWrong,
        [string]$HowToOverride,
        [string[]]$PublicEvidence
    )

    [ordered]@{
        question_id = $QuestionId
        question = $Question
        self_answer = $SelfAnswer
        answer_source = $AnswerSource
        risk_if_wrong = $RiskIfWrong
        how_to_override = $HowToOverride
        public_evidence = @($PublicEvidence)
    }
}

function New-IntentAssumption {
    param(
        [string]$Assumption,
        [string]$WhySafe,
        [string]$RiskIfWrong,
        [string]$HowToOverride,
        [string[]]$PublicEvidence
    )

    [ordered]@{
        assumption = $Assumption
        why_safe = $WhySafe
        risk_if_wrong = $RiskIfWrong
        how_to_override = $HowToOverride
        public_evidence = @($PublicEvidence)
    }
}

function New-SourceOnlyBlocker {
    param(
        [string]$BlockerId,
        [string]$BlockerType,
        [string]$Description,
        [string[]]$RequiredEvidence,
        [string[]]$PublicEvidence,
        [string]$UnblockInstruction
    )

    [ordered]@{
        blocker_id = $BlockerId
        blocker_type = $BlockerType
        description = $Description
        required_evidence = @($RequiredEvidence)
        public_evidence = @($PublicEvidence)
        unblock_instruction = $UnblockInstruction
    }
}

function New-DependencyGate {
    param(
        [string]$GateId,
        [string]$Kind,
        [bool]$Required,
        [string]$Status,
        [string[]]$Evidence,
        [string]$CheckCommand,
        [string]$BlockedReason
    )

    [ordered]@{
        gate_id = $GateId
        kind = $Kind
        required = $Required
        status = $Status
        evidence = @($Evidence)
        check_command = $CheckCommand
        blocked_reason = $BlockedReason
    }
}

function New-JsonServerRunnerYaml {
    param([string]$ExpectationsPath)

    $expectations = ConvertTo-YamlSingleQuoted "./expectations"
    return @"
# Candidate QaaS Runner YAML generated from immutable public json-server README evidence.
# Status: blocked_until_template_live_airgapped_validation
# Runtime startup stays in candidate-runtime-plan.json; QaaS YAML does not own process lifecycle.

MetaData:
  Team: ZappaDontCry
  System: typicode-json-server

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetPostOnePayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-post-one.bin'
      StorageMetaData: ItemName

  - Name: ExpectedPostOneCsv
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: $expectations
        SearchPattern: 'posts-1.csv'
      StorageMetaData: ItemName

Sessions:
  - Name: JsonServerReadPost
    Transactions:
      - Name: GetPostOne
        TimeoutMs: 5000
        DataSourceNames:
          - GetPostOnePayload
        DataSourcePatterns:
          - GetPostOnePayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 3000
          Route: /posts/1
          Method: Get
        OutputDeserialize:
          Deserializer: Json

Assertions:
  - Name: GetPostOneReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - JsonServerReadPost
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetPostOne

  - Name: GetPostOneBodyMatchesReadme
    Assertion: OutputContentByExpectedCsvResults
    SessionNames:
      - JsonServerReadPost
    DataSourceNames:
      - ExpectedPostOneCsv
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetPostOne
      DataSourceName: ExpectedPostOneCsv
      JsonConverterType: Json
      CompareRowsNotInOrder: false
      ColumnNameToFieldPathMap:
        id:
          Path: $.id
          FieldValidationConfig:
            Type: ExactValue
        title:
          Path: $.title
          FieldValidationConfig:
            Type: ExactValue
        views:
          Path: $.views
          FieldValidationConfig:
            Type: ExactValue
"@
}

function New-FlaskRunnerYaml {
    return @"
# Candidate QaaS Runner YAML generated from immutable public Flask README evidence.
# Status: blocked_until_template_live_airgapped_validation
# Runtime startup stays in candidate-runtime-plan.json; QaaS YAML does not own process lifecycle.

MetaData:
  Team: ZappaDontCry
  System: pallets-flask

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetRootPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-root.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: FlaskReadRoot
    Transactions:
      - Name: GetRoot
        TimeoutMs: 5000
        DataSourceNames:
          - GetRootPayload
        DataSourcePatterns:
          - GetRootPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 5000
          Route: /
          Method: Get

Assertions:
  - Name: GetRootReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - FlaskReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetRoot
"@
}

function New-ExpressRunnerYaml {
    return @"
# Candidate QaaS Runner YAML generated from immutable public Express README evidence.
# Status: blocked_until_template_live_airgapped_validation
# Runtime startup stays in candidate-runtime-plan.json; QaaS YAML does not own process lifecycle.

MetaData:
  Team: ZappaDontCry
  System: expressjs-express

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetRootPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-root.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: ExpressReadRoot
    Transactions:
      - Name: GetRoot
        TimeoutMs: 5000
        DataSourceNames:
          - GetRootPayload
        DataSourcePatterns:
          - GetRootPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 3000
          Route: /
          Method: Get

Assertions:
  - Name: GetRootReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - ExpressReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetRoot
"@
}

function New-FastApiRunnerYaml {
    return @"
# Candidate QaaS Runner YAML generated from immutable public FastAPI README evidence.
# Status: blocked_until_template_live_airgapped_validation
# Runtime startup stays in candidate-runtime-plan.json; QaaS YAML does not own process lifecycle.

MetaData:
  Team: ZappaDontCry
  System: fastapi-fastapi

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetItemPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-items-5.bin'
      StorageMetaData: ItemName

  - Name: FastApiReadmeItemResponseSchemas
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './schemas'
        SearchPattern: 'item-response.schema.json'
      StorageMetaData: ItemName

Sessions:
  - Name: FastApiReadItem
    Transactions:
      - Name: GetItemFive
        TimeoutMs: 5000
        DataSourceNames:
          - GetItemPayload
        DataSourcePatterns:
          - GetItemPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 8000
          Route: items/5?q=somequery
          Method: Get
        OutputDeserialize:
          Deserializer: Json

Assertions:
  - Name: GetItemFiveReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - FastApiReadItem
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetItemFive

  - Name: GetItemFiveBodyMatchesReadmeSchema
    Assertion: ObjectOutputJsonSchema
    SessionNames:
      - FastApiReadItem
    DataSourceNames:
      - FastApiReadmeItemResponseSchemas
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetItemFive
"@
}

function New-GinRunnerYaml {
    return @"
# Candidate QaaS Runner YAML generated from immutable public Gin README evidence.
# Status: blocked_until_template_live_airgapped_validation
# Runtime startup stays in candidate-runtime-plan.json; QaaS YAML does not own process lifecycle.

MetaData:
  Team: ZappaDontCry
  System: gin-gonic-gin

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetPingPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-ping.bin'
      StorageMetaData: ItemName

  - Name: GinReadmePingResponseSchemas
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './schemas'
        SearchPattern: 'ping-response.schema.json'
      StorageMetaData: ItemName

Sessions:
  - Name: GinReadPing
    Transactions:
      - Name: GetPing
        TimeoutMs: 5000
        DataSourceNames:
          - GetPingPayload
        DataSourcePatterns:
          - GetPingPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 8080
          Route: /ping
          Method: Get
        OutputDeserialize:
          Deserializer: Json

Assertions:
  - Name: GetPingReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - GinReadPing
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetPing

  - Name: GetPingBodyMatchesReadmeSchema
    Assertion: ObjectOutputJsonSchema
    SessionNames:
      - GinReadPing
    DataSourceNames:
      - GinReadmePingResponseSchemas
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetPing
"@
}

function New-FlaskExactTextBodyAssertionCode {
    return @"
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using QaaS.Framework.SDK.DataSourceObjects;
using QaaS.Framework.SDK.Extensions;
using QaaS.Framework.SDK.Hooks.Assertion;
using QaaS.Framework.SDK.Session.SessionDataObjects;

namespace ZappaDontCry.SelectedCandidates.Flask.Assertions;

public sealed record ExactHttpTextBodyConfig
{
    [Description("Transaction output name to inspect.")]
    [Required]
    public string OutputName { get; set; } = string.Empty;

    [Description("Exact expected response body text.")]
    [Required]
    public string ExpectedText { get; set; } = string.Empty;

    [Description("Encoding name used to decode the response Body byte array.")]
    [DefaultValue("utf-8")]
    public string EncodingName { get; set; } = "utf-8";
}

public sealed class ExactHttpTextBody : BaseAssertion<ExactHttpTextBodyConfig>
{
    public override bool Assert(
        IImmutableList<SessionData> sessionDataList,
        IImmutableList<DataSource> dataSourceList)
    {
        if (Configuration is null)
        {
            AssertionMessage = "ExactHttpTextBody configuration was not loaded.";
            return false;
        }

        if (string.IsNullOrWhiteSpace(Configuration.OutputName))
        {
            AssertionMessage = "OutputName is required.";
            return false;
        }

        Encoding encoding;
        try
        {
            encoding = Encoding.GetEncoding(
                string.IsNullOrWhiteSpace(Configuration.EncodingName)
                    ? "utf-8"
                    : Configuration.EncodingName);
        }
        catch (ArgumentException exception)
        {
            AssertionMessage = `$"Encoding '{Configuration.EncodingName}' is not supported: {exception.Message}";
            return false;
        }

        var observed = sessionDataList
            .SelectMany(session => session.GetOutputByName(Configuration.OutputName).Data)
            .ToImmutableList();

        if (observed.Count == 0)
        {
            AssertionMessage = `$"No output data observed for '{Configuration.OutputName}'.";
            return false;
        }

        var failures = new List<string>();
        for (var index = 0; index < observed.Count; index++)
        {
            var item = observed[index];
            if (item.Body is not byte[] body)
            {
                failures.Add(`$"item {index} body was {item.Body?.GetType().Name ?? "null"}, expected byte[].");
                continue;
            }

            var actualText = encoding.GetString(body);
            if (!string.Equals(actualText, Configuration.ExpectedText, StringComparison.Ordinal))
            {
                failures.Add(`$"item {index} body mismatch: expected {Configuration.ExpectedText.Length} chars, actual {actualText.Length} chars.");
            }
        }

        AssertionTrace = `$"Observed {observed.Count} output item(s) for '{Configuration.OutputName}'.";
        if (failures.Count > 0)
        {
            AssertionMessage = string.Join("; ", failures);
            return false;
        }

        AssertionMessage = `$"All observed bodies exactly matched {Configuration.ExpectedText.Length} expected character(s).";
        return true;
    }
}
"@
}

function New-FlaskExactTextBodyUsageSnippet {
    return @"
# Non-executable usage snippet.
# Do not rename this file to test.qaas.yaml or treat it as schema-valid until:
# 1. the assertion assembly is referenced by the Runner host,
# 2. the Runner schema has been regenerated and the bin cache cleaned,
# 3. Runner template validation passes,
# 4. live QaaS act/assert passes against the tracked Flask process.

Assertions:
  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - FlaskReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello, World!
      EncodingName: utf-8
"@
}

function New-ExpressExactTextBodyAssertionCode {
    return (New-FlaskExactTextBodyAssertionCode) -replace 'namespace ZappaDontCry\.SelectedCandidates\.Flask\.Assertions;', 'namespace ZappaDontCry.SelectedCandidates.Express.Assertions;'
}

function New-ExpressExactTextBodyUsageSnippet {
    return @"
# Non-executable usage snippet.
# Do not rename this file to test.qaas.yaml or treat it as schema-valid until:
# 1. the assertion assembly is referenced by the Runner host,
# 2. the Runner schema has been regenerated and the bin cache cleaned,
# 3. Runner template validation passes,
# 4. live QaaS act/assert passes against the tracked Express process.

Assertions:
  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - ExpressReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello World
      EncodingName: utf-8
"@
}

function New-DenoRunnerYaml {
    return @"
# Candidate QaaS Runner YAML generated from immutable public Deno README evidence.
# Status: blocked_until_template_live_airgapped_validation
# Runtime startup stays in candidate-runtime-plan.json; QaaS YAML does not own process lifecycle.

MetaData:
  Team: ZappaDontCry
  System: denoland-deno

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetRootPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-root.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: DenoReadRoot
    Transactions:
      - Name: GetRoot
        TimeoutMs: 5000
        DataSourceNames:
          - GetRootPayload
        DataSourcePatterns:
          - GetRootPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 8000
          Route: /
          Method: Get

Assertions:
  - Name: GetRootReturnedOk
    Assertion: HttpStatus
    SessionNames:
      - DenoReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      StatusCode: 200
      OutputNames:
        - GetRoot
"@
}

function New-DenoExactTextBodyAssertionCode {
    return (New-FlaskExactTextBodyAssertionCode) -replace 'namespace ZappaDontCry\.SelectedCandidates\.Flask\.Assertions;', 'namespace ZappaDontCry.SelectedCandidates.Deno.Assertions;'
}

function New-DenoExactTextBodyUsageSnippet {
    return @"
# Non-executable usage snippet.
# Do not rename this file to test.qaas.yaml or treat it as schema-valid until:
# 1. the assertion assembly is referenced by the Runner host,
# 2. the Runner schema has been regenerated and the bin cache cleaned,
# 3. Runner template validation passes,
# 4. live QaaS act/assert passes against the tracked Deno process.

Assertions:
  - Name: GetRootBodyMatchesReadme
    Assertion: ExactHttpTextBody
    SessionNames:
      - DenoReadRoot
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      OutputName: GetRoot
      ExpectedText: Hello, world!
      EncodingName: utf-8
"@
}

function New-Crawl4AiRunnerYaml {
    return @'
# Candidate QaaS Runner YAML generated from immutable public Crawl4AI Docker healthcheck evidence.
# Status: blocked_until_template_live_airgapped_validation
# Docker startup and cleanup stay in candidate-runtime-plan.json; QaaS YAML does not own container lifecycle.
# The public contract is Docker curl -f /health semantics: HTTP status must be below 400. Body is intentionally unasserted.

MetaData:
  Team: ZappaDontCry
  System: unclecode-crawl4ai

Storages:
  -
    JsonStorageFormat: Indented
    FileSystem:
      Path: ./session-data

DataSources:
  - Name: GetHealthPayload
    Generator: FromFileSystem
    DataSourceNames: []
    DataSourcePatterns: []
    GeneratorConfiguration:
      DataArrangeOrder: AsciiAsc
      FileSystem:
        Path: './request-payloads'
        SearchPattern: 'get-health.bin'
      StorageMetaData: ItemName

Sessions:
  - Name: Crawl4AiHealth
    Transactions:
      - Name: GetHealth
        TimeoutMs: 5000
        DataSourceNames:
          - GetHealthPayload
        DataSourcePatterns:
          - GetHealthPayload
        Http:
          BaseAddress: http://127.0.0.1
          Port: 11235
          Route: health
          Method: Get

Assertions:
  - Name: GetHealthMatchesDockerCurlF
    Assertion: HttpStatusBelow400
    SessionNames:
      - Crawl4AiHealth
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      MaximumExclusiveStatusCode: 400
      OutputNames:
        - GetHealth
'@
}

function New-Crawl4AiHttpStatusBelow400AssertionCode {
    return @'
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using QaaS.Framework.SDK.DataSourceObjects;
using QaaS.Framework.SDK.Hooks.Assertion;
using QaaS.Framework.SDK.Session.SessionDataObjects;

namespace ZappaDontCry.SelectedCandidates.Crawl4Ai.Assertions;

public sealed record HttpStatusBelow400Config
{
    [Description("Transaction output names to inspect.")]
    [Required]
    public string[] OutputNames { get; set; } = Array.Empty<string>();

    [Description("Exclusive maximum HTTP status code accepted by Docker curl -f semantics.")]
    [Range(100, 600)]
    public int MaximumExclusiveStatusCode { get; set; } = 400;
}

public sealed class HttpStatusBelow400 : BaseAssertion<HttpStatusBelow400Config>
{
    public override bool Assert(
        IImmutableList<SessionData> sessionDataList,
        IImmutableList<DataSource> dataSourceList)
    {
        if (Configuration is null)
        {
            AssertionMessage = "HttpStatusBelow400 configuration was not loaded.";
            return false;
        }

        var outputNames = (Configuration.OutputNames ?? Array.Empty<string>())
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.Ordinal)
            .ToImmutableArray();
        if (outputNames.Length == 0)
        {
            AssertionMessage = "At least one OutputNames value is required.";
            return false;
        }

        var failures = new List<string>();
        var observedCount = 0;
        foreach (var outputName in outputNames)
        {
            var observed = sessionDataList
                .SelectMany(session => session.GetOutputByName(outputName).Data)
                .ToImmutableList();

            if (observed.Count == 0)
            {
                failures.Add($"No output data observed for '{outputName}'.");
                continue;
            }

            observedCount += observed.Count;
            for (var index = 0; index < observed.Count; index++)
            {
                var statusCode = observed[index].MetaData?.Http?.StatusCode;
                if (statusCode is null)
                {
                    failures.Add($"Output '{outputName}' item {index} has no HTTP status metadata.");
                    continue;
                }

                if (statusCode >= Configuration.MaximumExclusiveStatusCode)
                {
                    failures.Add($"Output '{outputName}' item {index} status {statusCode} >= {Configuration.MaximumExclusiveStatusCode}.");
                }
            }
        }

        AssertionTrace = $"Observed {observedCount} output item(s); required status < {Configuration.MaximumExclusiveStatusCode}.";
        if (failures.Count > 0)
        {
            AssertionMessage = string.Join("; ", failures);
            return false;
        }

        AssertionMessage = $"All observed HTTP statuses were below {Configuration.MaximumExclusiveStatusCode}.";
        return true;
    }
}
'@
}

function New-Crawl4AiHttpStatusBelow400UsageSnippet {
    return @'
# Usage snippet for the Crawl4AI Docker healthcheck candidate.
# This is backed only by Docker curl -f /health semantics. Do not add body/schema assertions unless public response evidence is harvested.

Assertions:
  - Name: GetHealthMatchesDockerCurlF
    Assertion: HttpStatusBelow400
    SessionNames:
      - Crawl4AiHealth
    DataSourceNames: []
    DataSourcePatterns: []
    AssertionConfiguration:
      MaximumExclusiveStatusCode: 400
      OutputNames:
        - GetHealth
'@
}

$allowedOutRoot = "D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates"
$resolvedOutDir = Assert-UnderRoot -Path $OutDir -Root $allowedOutRoot -Description "OutDir"
if (-not $resolvedOutDir.Equals([System.IO.Path]::GetFullPath($allowedOutRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "This generator owns only the selected top-repo candidate root: $allowedOutRoot"
}

if (-not (Test-Path -LiteralPath $SelectedContractsDir -PathType Container)) {
    throw "Selected contracts directory not found: $SelectedContractsDir"
}

if ($Clean -and (Test-Path -LiteralPath $resolvedOutDir)) {
    Get-ChildItem -LiteralPath $resolvedOutDir -Force | Remove-Item -Recurse -Force
}
[System.IO.Directory]::CreateDirectory($resolvedOutDir) | Out-Null

$selectedRecordPath = Join-Path $SelectedContractsDir "200-typicode-json-server\selected-contract.json"
if (-not (Test-Path -LiteralPath $selectedRecordPath -PathType Leaf)) {
    throw "Selected json-server contract not found: $selectedRecordPath"
}

$selected = Get-Content -LiteralPath $selectedRecordPath -Raw | ConvertFrom-Json
if ([string]$selected.repository -ne "typicode/json-server") {
    throw "Expected typicode/json-server selected contract, got $($selected.repository)"
}
if ([string]$selected.status -ne "contract_content_harvested_not_executable" -or [string]$selected.promotion_state -ne "blocked") {
    throw "Selected contract must be harvested and blocked: $selectedRecordPath"
}

$selectedPublicContracts = @($selected.selected_public_contracts)
$readmeRecord = $selectedPublicContracts | Where-Object { [string]$_.source_path -eq "README.md" } | Select-Object -First 1
if ($null -eq $readmeRecord) {
    throw "Selected json-server contract lacks README.md evidence."
}
$readmePath = Assert-UnderRoot -Path ([string]$readmeRecord.local_path) -Root $SelectedContractsDir -Description "README evidence"
$readmeText = Get-Content -LiteralPath $readmePath -Raw

$requiredReadmeMarkers = @(
    "npx json-server db.json",
    "http://localhost:3000",
    "curl http://localhost:3000/posts/1",
    '"id": "1"',
    '"title": "a title"',
    '"views": 100'
)
foreach ($marker in $requiredReadmeMarkers) {
    if (-not $readmeText.Contains($marker)) {
        throw "README evidence missing marker '$marker': $readmePath"
    }
}

$safeRepo = "{0:D3}-{1}" -f [int]$selected.rank, (New-SafeName ([string]$selected.repository).Replace("/", "-"))
$candidateDir = Join-Path $resolvedOutDir $safeRepo
$fixturesDir = Join-Path $candidateDir "fixtures"
$expectationsDir = Join-Path $candidateDir "expectations"
$requestPayloadsDir = Join-Path $candidateDir "request-payloads"
foreach ($dir in @($candidateDir, $fixturesDir, $expectationsDir, $requestPayloadsDir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$runnerPath = Join-Path $candidateDir "test.qaas.yaml"
$dbPath = Join-Path $fixturesDir "db.json"
$expectationPath = Join-Path $expectationsDir "posts-1.csv"
$requestPayloadPath = Join-Path $requestPayloadsDir "get-post-one.bin"
$runtimePlanPath = Join-Path $candidateDir "candidate-runtime-plan.json"
$manifestPath = Join-Path $candidateDir "qaas-artifact-manifest.json"

Write-TextFile -Path $runnerPath -Value (New-JsonServerRunnerYaml -ExpectationsPath $expectationsDir)
$dbJson = @"
{
  "posts": [
    { "id": "1", "title": "a title", "views": 100 },
    { "id": "2", "title": "another title", "views": 200 }
  ],
  "comments": [
    { "id": "1", "text": "a comment about post 1", "postId": "1" },
    { "id": "2", "text": "another comment about post 1", "postId": "1" }
  ],
  "profile": {
    "name": "typicode"
  }
}
"@
[System.IO.File]::WriteAllText($dbPath, $dbJson, $script:Utf8NoBom)
$expectedCsv = @"
id,title,views
1,a title,100
1,a title,100
"@
[System.IO.File]::WriteAllText($expectationPath, $expectedCsv, $script:Utf8NoBom)
[System.IO.File]::WriteAllBytes($requestPayloadPath, [byte[]]::new(0))

$publicEvidence = @(
    [string]$selectedRecordPath
    @($selected.public_evidence)
    @($selectedPublicContracts | ForEach-Object { [string]$_.local_path })
) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

$docsEvidence = @(
    "D:\QaaS\qaas-docs\docs\qaas\quickStart\helloWorldHttp.md",
    "D:\QaaS\qaas-docs\docs\qaas\quickStart\actionSelectionPlaybook.md",
    "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions.md",
    "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions-yamlView.md",
    "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\storages\configurations\yamlView.md",
    "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\dataSources\configurations\yamlView.md",
    "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\assertions\configurations\yamlView.md",
    "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\commands\run.md",
    "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
    "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\configuration\yamlView.md",
    "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputContentByExpectedCsvResults\overview.md",
    "D:\QaaS\qaas-docs\docs\generators\availableGenerators\FromFileSystem\overview.md",
    "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
)

$runtimePlan = [ordered]@{
    schema_version = 1
    repository = "typicode/json-server"
    rank = [int]$selected.rank
    status = "candidate_runtime_plan_blocked"
    promotion_state = "blocked"
    lifecycle_owner = "external_harness_not_qaas_yaml"
    command_support = "candidate-executable-command"
    command = "npx json-server db.json"
    working_directory = $candidateDir
    fixture = $dbPath
    expected_listen_url = "http://localhost:3000"
    readiness_probe = [ordered]@{
        method = "GET"
        url = "http://127.0.0.1:3000/posts/1"
        expected_status = 200
    }
    cleanup = [ordered]@{
        required = $true
        strategy = "terminate_tracked_process_tree"
        status = "not_validated"
    }
    blockers = @(
        "prove_process_lifecycle_and_cleanup_without assuming private source",
        "run_qaaS_template_validation",
        "run_live_qaaS_act_assert_validation",
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence"
    )
    public_evidence = $publicEvidence
}
Write-JsonFile -Path $runtimePlanPath -Value $runtimePlan

$intentQuestions = @(
    (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "GET /posts/1 from json-server should return HTTP 200 and the README example post body with id 1, title a title, and views 100." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may test the wrong route or assert fields not present in the README contract." -HowToOverride "Replace the route and expected output only with exact public repository evidence." -PublicEvidence $publicEvidence)
    (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "The Runner target is an externally-started json-server HTTP process on 127.0.0.1:3000; QaaS YAML does not start or clean that process." -AnswerSource "public_repo_contract" -RiskIfWrong "Process lifecycle could be incorrectly encoded as undocumented QaaS YAML." -HowToOverride "Provide documented QaaS lifecycle support or keep startup in an external harness plan." -PublicEvidence $publicEvidence)
    (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "QaaS public docs/schema support HTTP Transactions, FromFileSystem data sources for payload and expected CSV bytes, HttpStatus assertions, and OutputContentByExpectedCsvResults assertions." -AnswerSource "public_docs" -RiskIfWrong "The YAML could cite fields from stale examples instead of generated schemas." -HowToOverride "Update docs evidence and rerun the selected candidate checker." -PublicEvidence $docsEvidence)
    (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Input is a GET request to /posts/1. Outputs are HTTP status 200 and JSON fields id=1, title=a title, views=100. Side effects should be read-only for this GET." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may over-assert mutations, persistence, or unrelated endpoints." -HowToOverride "Provide public side-effect evidence for any additional assertion." -PublicEvidence $publicEvidence)
    (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, malformed, retry, and observability cases remain blocked; this candidate covers only one README-backed happy path and cleanup planning." -AnswerSource "blocked" -RiskIfWrong "A weak model may claim broad API coverage from one happy-path route." -HowToOverride "Add exact public negative-case and observability contracts before expanding assertions." -PublicEvidence $publicEvidence)
    (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Dependencies are Node/npm access, an externally-started json-server process, db.json in the runtime working directory, and port 3000 availability; those dependencies are identified from public evidence but not live-validated." -AnswerSource "blocked" -RiskIfWrong "The candidate may be promoted where node/npm, port, or fixture placement is not available." -HowToOverride "Provide validated dependency transcripts for the target environment." -PublicEvidence $publicEvidence)
    (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Static candidate validation can run now. QaaS template validation, live act/assert execution, cleanup proof, and live weak-model validation are deferred and block promotion." -AnswerSource "blocked" -RiskIfWrong "A weak model may confuse a candidate packet with an executable test." -HowToOverride "Attach passing template, live, cleanup, airgapped, and strong-review evidence." -PublicEvidence $publicEvidence)
)

$intentAssumptions = @(
    (New-IntentAssumption -Assumption "The README quick-start example is the public behavior contract for this candidate." -WhySafe "It contains exact command, URL, route, and response body markers harvested from an immutable Git blob." -RiskIfWrong "The candidate may not match another json-server version or fixture." -HowToOverride "Replace the selected contract with another immutable public blob." -PublicEvidence $publicEvidence)
    (New-IntentAssumption -Assumption "Process lifecycle belongs to the external harness until QaaS docs prove otherwise." -WhySafe "The public QaaS Runner docs describe HTTP transactions but not starting arbitrary Node processes." -RiskIfWrong "Startup or cleanup may be missed if a future QaaS lifecycle feature exists." -HowToOverride "Provide public QaaS lifecycle docs and update the checker." -PublicEvidence $docsEvidence)
    (New-IntentAssumption -Assumption "Generated schema evidence overrides stale quick-start assertion field names." -WhySafe "The generated HttpStatus schema requires StatusCode and OutputNames." -RiskIfWrong "If runtime accepts aliases, the candidate remains conservative but still schema-aligned." -HowToOverride "Provide updated generated schema or runtime validation transcript." -PublicEvidence $docsEvidence)
)

$artifacts = @($runnerPath, $dbPath, $expectationPath, $requestPayloadPath, $runtimePlanPath, $manifestPath)
$cases = @(
    [ordered]@{
        case_id = "json-server-read-post-one"
        scenario = "Call README-backed json-server GET /posts/1 and assert the documented 200 response body."
        artifact_type = "runner-yaml"
        public_evidence = $publicEvidence
        setup = @("Start json-server externally with the candidate db.json using the README command.", "Ensure port 3000 is free.", "Use get-post-one.bin as the byte payload driver for the GET transaction.")
        action = @("Run QaaS Runner against test.qaas.yaml after template validation is available.")
        assertions = @("HttpStatus StatusCode 200 for GetPostOne.", "OutputContentByExpectedCsvResults maps id, title, and views from posts-1.csv.")
        cleanup = @("Terminate the tracked json-server process tree.", "Remove candidate session-data after live validation.")
        blocked_reason = "QaaS template, live act/assert, cleanup, and live weak-model validation have not passed."
        artifact_paths = @($runnerPath, $dbPath, $expectationPath, $requestPayloadPath)
    },
    [ordered]@{
        case_id = "json-server-runtime-plan"
        scenario = "Keep Node process startup and cleanup outside QaaS YAML until public QaaS docs prove lifecycle support."
        artifact_type = "dependency-gate"
        public_evidence = $publicEvidence
        setup = @("Use candidate-runtime-plan.json as an external harness plan only.")
        action = @("Start and stop json-server through a tracked process runner, not through undocumented QaaS YAML fields.")
        assertions = @("Runtime plan remains blocked and never counts as executable promotion evidence by itself.")
        cleanup = @("Tracked process tree termination must be validated before promotion.")
        blocked_reason = "Process lifecycle and cleanup are planned but not validated."
        artifact_paths = @($runtimePlanPath)
    },
    [ordered]@{
        case_id = "json-server-contract-evidence"
        scenario = "Tie every candidate field to immutable selected public contract evidence and QaaS public docs."
        artifact_type = "documentation"
        public_evidence = @($publicEvidence + $docsEvidence)
        setup = @("Review selected-contract.json, README blob, and QaaS schema docs.")
        action = @("Run selected top-repo candidate checker.")
        assertions = @("Candidate stays blocked until executable evidence exists.", "No undocumented QaaS fields are introduced.")
        cleanup = @("No external resources are created by static candidate validation.")
        blocked_reason = "Static evidence does not prove live behavior."
        artifact_paths = @($manifestPath)
    }
)

$manifest = [ordered]@{
    schema_version = 1
    campaign_id = "selected-top-repo-json-server-candidate"
    source_repository = "typicode/json-server"
    repository_rank = [int]$selected.rank
    selected_contract = $selectedRecordPath
    docs_evidence = $docsEvidence
    public_evidence = $publicEvidence
    intent_questions = $intentQuestions
    intent_assumptions = $intentAssumptions
    artifacts = $artifacts
    artifact_count = $artifacts.Count
    artifact_types = @("runner-yaml", "dependency-gate", "documentation")
    cases = $cases
    assertions = @(
        "Candidate Runner YAML uses schema-derived HttpStatus StatusCode/OutputNames.",
        "Candidate body assertion uses documented FromFileSystem input bytes and OutputContentByExpectedCsvResults fields.",
        "Candidate remains blocked until template, live QaaS, cleanup, airgapped, and strong-review evidence pass."
    )
    dependency_gates = @(
        (New-DependencyGate -GateId "selected-public-runtime-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $publicEvidence -CheckCommand "" -BlockedReason "")
        (New-DependencyGate -GateId "selected-public-input-output-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $publicEvidence -CheckCommand "" -BlockedReason "")
        (New-DependencyGate -GateId "qaas-docs-yaml-shape" -Kind "runtime" -Required $true -Status "ready" -Evidence $docsEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
        (New-DependencyGate -GateId "node-json-server-process-lifecycle" -Kind "dependency" -Required $true -Status "blocked" -Evidence $publicEvidence -CheckCommand "" -BlockedReason "The external json-server process has not been started, tracked, readiness-checked, and cleaned up by the harness.")
        (New-DependencyGate -GateId "cleanup-contract" -Kind "cleanup" -Required $true -Status "blocked" -Evidence $publicEvidence -CheckCommand "" -BlockedReason "Tracked process tree cleanup and session-data cleanup are not live-validated.")
        (New-DependencyGate -GateId "qaas-template" -Kind "qaas-template" -Required $true -Status "blocked" -Evidence $docsEvidence -CheckCommand "" -BlockedReason "QaaS template validation has not run for this candidate.")
        (New-DependencyGate -GateId "qaas-live-act-assert" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence $docsEvidence -CheckCommand "" -BlockedReason "Live QaaS run/act/assert has not run against a tracked json-server process.")
        (New-DependencyGate -GateId "airgapped-validation" -Kind "airgapped" -Required $true -Status "blocked" -Evidence @() -CheckCommand "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none" -BlockedReason "Live weak-model validation has not passed.")
    )
    promotion_requirements = [ordered]@{
        current_state = "blocked"
        target_state = "executable_ready"
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
    cleanup = @("No live cleanup was performed during static candidate generation.")
    validation_sequence = @(
        "Validate selected immutable public contract evidence.",
        "Validate QaaS public docs/schema fields.",
        "Run selected top-repo candidate checker.",
        "Run QaaS template validation when a Runner host is available.",
        "Run live QaaS act/assert against tracked json-server process.",
        "Run live airgapped weak-model validation and strong review before promotion."
    )
    airgapped_validation = [ordered]@{
        required = $true
        status = "not_run_for_this_candidate"
        dry_run = $false
    }
    source_only_blockers = @(
        (New-SourceOnlyBlocker -BlockerId "json-server-process-lifecycle-not-proven" -BlockerType "repository_contract" -Description "The README command is public evidence for a candidate command, but process startup, readiness, and cleanup have not been executed and verified." -RequiredEvidence @("Tracked process start transcript", "Readiness probe transcript", "Tracked process cleanup transcript") -PublicEvidence $publicEvidence -UnblockInstruction "Run the external harness lifecycle and attach the transcripts before promotion.")
        (New-SourceOnlyBlocker -BlockerId "qaas-template-live-not-run" -BlockerType "qaas_docs_contract" -Description "The Runner YAML is schema-derived but has not passed QaaS template or live act/assert validation." -RequiredEvidence @("QaaS template validation transcript", "Live QaaS run/act/assert transcript") -PublicEvidence $docsEvidence -UnblockInstruction "Run documented QaaS validation commands in an environment with Runner host and json-server process.")
        (New-SourceOnlyBlocker -BlockerId "live-airgapped-weak-model-not-passed" -BlockerType "source_boundary" -Description "Live weak-model validation has not passed for this candidate packet." -RequiredEvidence @("Airgapped transcript with dry_run false and expected output contract preserved") -PublicEvidence @((Join-Path "D:\QaaS\_tools\zappa-harness" "references\airgapped-validation.md")) -UnblockInstruction "Run D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none when quota/routing is available.")
        (New-SourceOnlyBlocker -BlockerId "httpstatus-docs-inconsistency-recorded" -BlockerType "qaas_docs_contract" -Description "The quick-start example uses stale HttpStatus field names, while generated schema docs require StatusCode and OutputNames." -RequiredEvidence @("Runtime/template validation confirming schema-derived field names") -PublicEvidence $docsEvidence -UnblockInstruction "Keep schema-derived StatusCode/OutputNames unless public docs/schema are updated and revalidated.")
    )
    status = "blocked_until_repo_contract_review"
    promotion_state = "blocked"
    blocked_reason = "Selected public contracts support a concrete candidate packet, but executable promotion is blocked until process lifecycle, QaaS template/live, cleanup, airgapped, and strong-review evidence pass."
}
Write-JsonFile -Path $manifestPath -Value $manifest

$record = [ordered]@{
    rank = [int]$selected.rank
    repository = "typicode/json-server"
    directory = $candidateDir
    manifest = $manifestPath
    selected_contract = $selectedRecordPath
    status = "candidate_packet_blocked_until_template_live_airgapped_validation"
    promotion_state = "blocked"
    readiness_state = "qaaS_candidate_authored_from_selected_contract"
    artifact_count = $artifacts.Count
}

$records = @($record)

$flaskRecordPath = Join-Path $SelectedContractsDir "227-pallets-flask\selected-contract.json"
if (Test-Path -LiteralPath $flaskRecordPath -PathType Leaf) {
    $flaskSelected = Get-Content -LiteralPath $flaskRecordPath -Raw | ConvertFrom-Json
    if ([string]$flaskSelected.repository -ne "pallets/flask") {
        throw "Expected pallets/flask selected contract, got $($flaskSelected.repository)"
    }
    if ([string]$flaskSelected.status -ne "contract_content_harvested_not_executable" -or [string]$flaskSelected.promotion_state -ne "blocked") {
        throw "Selected Flask contract must be harvested and blocked: $flaskRecordPath"
    }

    $flaskSelectedPublicContracts = @($flaskSelected.selected_public_contracts)
    $flaskReadmeRecord = $flaskSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "README.md" } | Select-Object -First 1
    if ($null -eq $flaskReadmeRecord) {
        throw "Selected Flask contract lacks README.md evidence."
    }
    $flaskReadmePath = Assert-UnderRoot -Path ([string]$flaskReadmeRecord.local_path) -Root $SelectedContractsDir -Description "Flask README evidence"
    $flaskReadmeText = Get-Content -LiteralPath $flaskReadmePath -Raw
    $requiredFlaskReadmeMarkers = @(
        "# save this as app.py",
        "from flask import Flask",
        '@app.route("/")',
        'return "Hello, World!"',
        '$ flask run',
        "http://127.0.0.1:5000/"
    )
    foreach ($marker in $requiredFlaskReadmeMarkers) {
        if (-not $flaskReadmeText.Contains($marker)) {
            throw "Flask README evidence missing marker '$marker': $flaskReadmePath"
        }
    }

    $flaskSafeRepo = "{0:D3}-{1}" -f [int]$flaskSelected.rank, (New-SafeName ([string]$flaskSelected.repository).Replace("/", "-"))
    $flaskCandidateDir = Join-Path $resolvedOutDir $flaskSafeRepo
    $flaskAppDir = Join-Path $flaskCandidateDir "app"
    $flaskExpectationsDir = Join-Path $flaskCandidateDir "expectations"
    $flaskRequestPayloadsDir = Join-Path $flaskCandidateDir "request-payloads"
    $flaskHookDir = Join-Path $flaskCandidateDir "assertion-packets\ExactHttpTextBody"
    foreach ($dir in @($flaskCandidateDir, $flaskAppDir, $flaskExpectationsDir, $flaskRequestPayloadsDir, $flaskHookDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $flaskRunnerPath = Join-Path $flaskCandidateDir "test.qaas.yaml"
    $flaskAppPath = Join-Path $flaskAppDir "app.py"
    $flaskExpectedBodyPath = Join-Path $flaskExpectationsDir "root-body.txt"
    $flaskRequestPayloadPath = Join-Path $flaskRequestPayloadsDir "get-root.bin"
    $flaskRuntimePlanPath = Join-Path $flaskCandidateDir "candidate-runtime-plan.json"
    $flaskManifestPath = Join-Path $flaskCandidateDir "qaas-artifact-manifest.json"
    $flaskHookCodePath = Join-Path $flaskHookDir "ExactHttpTextBody.cs"
    $flaskHookUsagePath = Join-Path $flaskHookDir "ExactHttpTextBody.usage.yaml.txt"
    $flaskHookPlanPath = Join-Path $flaskHookDir "custom-text-body-hook-plan.json"

    Write-TextFile -Path $flaskRunnerPath -Value (New-FlaskRunnerYaml)
    $flaskApp = @"
# Generated from immutable public Flask README evidence.
from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello, World!"
"@
    Write-TextFile -Path $flaskAppPath -Value $flaskApp
    Write-TextFile -Path $flaskExpectedBodyPath -Value "Hello, World!"
    [System.IO.File]::WriteAllBytes($flaskRequestPayloadPath, [byte[]]::new(0))
    Write-TextFile -Path $flaskHookCodePath -Value (New-FlaskExactTextBodyAssertionCode)
    Write-TextFile -Path $flaskHookUsagePath -Value (New-FlaskExactTextBodyUsageSnippet)

    $flaskHookDocsEvidence = @(
        "D:\QaaS\qaas-docs\docs\assertions\index.md",
        "D:\QaaS\qaas-docs\docs\assertions\custom-authoring-guide.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputContentByExpectedCsvResults\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputDeserializableTo\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\overview.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\schema-extensions.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $flaskDocsEvidence = @($docsEvidence + $flaskHookDocsEvidence) | Select-Object -Unique
    $flaskExpectedBodySha256 = Get-Sha256Hex -Path $flaskExpectedBodyPath
    $flaskHookBuiltins = @(
        [ordered]@{ name = "HttpStatus"; reason_insufficient = "Status-only assertion; does not compare response body bytes." },
        [ordered]@{ name = "OutputContentByExpectedCsvResults"; reason_insufficient = "JSON/CSV field mapping assertion; not exact raw/plain-text body equality." },
        [ordered]@{ name = "OutputDeserializableTo"; reason_insufficient = "Checks deserialization success, not equality with exact public README text." },
        [ordered]@{ name = "ObjectOutputJsonSchema"; reason_insufficient = "Checks JSON schema compatibility, not exact raw/plain-text body equality." }
    )

    $flaskPublicEvidence = @(
        [string]$flaskRecordPath
        @($flaskSelected.public_evidence)
        @($flaskSelectedPublicContracts | ForEach-Object { [string]$_.local_path })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $flaskCustomAssertionPacket = [ordered]@{
        packet_id = "flask-exact-http-text-body"
        assertion_name = "ExactHttpTextBody"
        status = "blocked_until_build_template_live_airgapped_validation"
        promotion_state = "blocked"
        activation = "sidecar_only"
        wired_into_runner_yaml = $false
        source_files = @($flaskHookCodePath)
        yaml_fragment = $flaskHookUsagePath
        hook_plan = $flaskHookPlanPath
        expected_body_path = $flaskExpectedBodyPath
        expected_body_sha256 = $flaskExpectedBodySha256
        encoding = "utf-8"
        comparison = "byte_for_byte"
        normalization = "none"
        case_sensitive = $true
        trim = $false
        contains = $false
        docs_evidence = $flaskHookDocsEvidence
        public_evidence = $flaskPublicEvidence
        validation_records = [ordered]@{
            build = "not_run"
            schema = "not_run"
            template = "not_run"
            live = "not_run"
            airgapped = "not_run"
        }
        weak_validation_passed = $false
    }

    $flaskHookPlan = [ordered]@{
        schema_version = 1
        status = "authored_from_public_docs_not_template_validated"
        hook_family = "assertion"
        assertion_type = "ExactHttpTextBody"
        configuration_contract = [ordered]@{
            OutputName = "Required transaction output name, backed by custom assertion docs and the Flask transaction name GetRoot."
            ExpectedText = "Required exact expected text, backed by Flask README output evidence."
            EncodingName = "Optional text encoding name; defaults to utf-8."
        }
        builtins_considered = $flaskHookBuiltins
        docs_evidence = $flaskHookDocsEvidence
        files = [ordered]@{
            implementation = $flaskHookCodePath
            usage_snippet = $flaskHookUsagePath
        }
        validation_sequence = @(
            "Reference the assertion assembly from the Runner host project.",
            "Regenerate Runner schema and clean bin cache so Assertion: ExactHttpTextBody is discoverable.",
            "Run Runner template validation against the Flask candidate YAML with the assertion enabled.",
            "Run live QaaS act/assert against a tracked Flask process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        custom_assertion_packet = $flaskCustomAssertionPacket
        promotion_state = "blocked"
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $flaskHookPlanPath -Value $flaskHookPlan

    $flaskRuntimePlan = [ordered]@{
        schema_version = 1
        repository = "pallets/flask"
        rank = [int]$flaskSelected.rank
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        command = "flask run"
        working_directory = $flaskAppDir
        fixture = $flaskAppPath
        expected_listen_url = "http://127.0.0.1:5000/"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:5000/"
            expected_status = 200
            expected_body = "Hello, World!"
        }
        cleanup = [ordered]@{
            required = $true
            strategy = "terminate_tracked_process_tree"
            status = "not_validated"
        }
        blockers = @(
            "prove_process_lifecycle_and_cleanup_without assuming private source",
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            assertion_type = "ExactHttpTextBody"
            implementation = $flaskHookCodePath
            usage_snippet = $flaskHookUsagePath
            hook_plan = $flaskHookPlanPath
            validation_status = "not_template_validated"
        }
        custom_assertion_packets = @($flaskCustomAssertionPacket)
        public_evidence = $flaskPublicEvidence
    }
    Write-JsonFile -Path $flaskRuntimePlanPath -Value $flaskRuntimePlan

    $flaskIntentQuestions = @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "GET / from the README Flask app should return HTTP 200 and the exact body Hello, World!." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may test a different route, add HTML wrappers, or skip the body contract." -HowToOverride "Replace the route and body only with exact public repository evidence." -PublicEvidence $flaskPublicEvidence)
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "The Runner target is an externally-started Flask HTTP process on 127.0.0.1:5000; QaaS YAML does not start or clean that process." -AnswerSource "public_repo_contract" -RiskIfWrong "Process lifecycle could be incorrectly encoded as undocumented QaaS YAML." -HowToOverride "Provide documented QaaS lifecycle support or keep startup in an external harness plan." -PublicEvidence $flaskPublicEvidence)
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "QaaS public docs/schema support HTTP Transactions, FromFileSystem data-source payload bytes, HttpStatus assertions, and custom assertions by short type name; the ExactHttpTextBody hook is authored but not schema/template/live validated." -AnswerSource "public_docs" -RiskIfWrong "A weak model may invent a built-in text body assertion or treat sidecar hook code as executable validation." -HowToOverride "Provide template/build/live validation for the custom assertion packet." -PublicEvidence $flaskDocsEvidence)
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Input is a GET request to /. Outputs are HTTP status 200 and body Hello, World!. Side effects should be read-only for this GET." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may over-assert mutations, persistence, or unrelated endpoints." -HowToOverride "Provide public side-effect evidence for any additional assertion." -PublicEvidence $flaskPublicEvidence)
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, malformed, retry, and observability cases remain blocked; this candidate covers only one README-backed happy path and cleanup planning." -AnswerSource "blocked" -RiskIfWrong "A weak model may claim broad framework or application coverage from one happy-path route." -HowToOverride "Add exact public negative-case and observability contracts before expanding assertions." -PublicEvidence $flaskPublicEvidence)
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Dependencies are Python, Flask CLI/runtime access, app.py in the runtime working directory, and port 5000 availability; those dependencies are identified from public evidence but not live-validated." -AnswerSource "blocked" -RiskIfWrong "The candidate may be promoted where Python, Flask, port, or fixture placement is not available." -HowToOverride "Provide validated dependency transcripts for the target environment." -PublicEvidence $flaskPublicEvidence)
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Static candidate validation can run now. Process lifecycle, custom assertion build/schema/template validation, live act/assert execution, cleanup proof, and live weak-model validation are deferred and block promotion." -AnswerSource "blocked" -RiskIfWrong "A weak model may confuse a candidate packet with an executable test." -HowToOverride "Attach passing lifecycle, custom assertion build/schema/template, live, cleanup, airgapped, and strong-review evidence." -PublicEvidence $flaskPublicEvidence)
    )

    $flaskIntentAssumptions = @(
        (New-IntentAssumption -Assumption "The README simple example is the public behavior contract for this candidate." -WhySafe "It contains exact app.py code, command, URL, and body markers harvested from an immutable Git blob." -RiskIfWrong "The candidate may not match another Flask app or route." -HowToOverride "Replace the selected contract with another immutable public blob." -PublicEvidence $flaskPublicEvidence)
        (New-IntentAssumption -Assumption "Process lifecycle belongs to the external harness until QaaS docs prove otherwise." -WhySafe "The public QaaS Runner docs describe HTTP transactions but not starting arbitrary Python processes." -RiskIfWrong "Startup or cleanup may be missed if a future QaaS lifecycle feature exists." -HowToOverride "Provide public QaaS lifecycle docs and update the checker." -PublicEvidence $docsEvidence)
        (New-IntentAssumption -Assumption "Plain-text body comparison is represented by a custom assertion sidecar, but remains blocked until build/schema/template/live validation passes." -WhySafe "The available built-ins do not prove exact raw text equality, while public custom assertion docs support sidecar authoring by short type name." -RiskIfWrong "A weak model may treat authored code as runtime validation." -HowToOverride "Provide passing custom assertion build, schema, template, and live QaaS evidence." -PublicEvidence $flaskDocsEvidence)
    )

    $flaskArtifacts = @($flaskRunnerPath, $flaskAppPath, $flaskExpectedBodyPath, $flaskRequestPayloadPath, $flaskRuntimePlanPath, $flaskManifestPath)
    $flaskCases = @(
        [ordered]@{
            case_id = "flask-read-root"
            scenario = "Call README-backed Flask GET / and assert documented HTTP success while the sidecar exact text-body assertion remains build/schema/template/live blocked."
            artifact_type = "runner-yaml"
            public_evidence = $flaskPublicEvidence
            setup = @("Start Flask externally with the README app.py using the README command.", "Ensure port 5000 is free.", "Use get-root.bin as the byte payload driver for the GET transaction.")
            action = @("Run QaaS Runner against test.qaas.yaml after template validation is available.")
            assertions = @("HttpStatus StatusCode 200 for GetRoot.", "Exact body Hello, World! is preserved as expected-response evidence but blocked from YAML until a documented text assertion or hook is selected.")
            cleanup = @("Terminate the tracked Flask process tree.", "Remove candidate session-data after live validation.")
            blocked_reason = "QaaS template, live act/assert, exact plain-text body assertion build/schema/template validation, cleanup, and live weak-model validation have not passed."
            artifact_paths = @($flaskRunnerPath, $flaskRequestPayloadPath, $flaskExpectedBodyPath)
        },
        [ordered]@{
            case_id = "flask-runtime-plan"
            scenario = "Keep Python process startup and cleanup outside QaaS YAML until public QaaS docs prove lifecycle support."
            artifact_type = "dependency-gate"
            public_evidence = $flaskPublicEvidence
            setup = @("Use candidate-runtime-plan.json as an external harness plan only.")
            action = @("Start and stop Flask through a tracked process runner, not through undocumented QaaS YAML fields.")
            assertions = @("Runtime plan remains blocked and never counts as executable promotion evidence by itself.")
            cleanup = @("Tracked process tree termination must be validated before promotion.")
            blocked_reason = "Process lifecycle and cleanup are planned but not validated."
            artifact_paths = @($flaskRuntimePlanPath, $flaskAppPath)
        },
        [ordered]@{
            case_id = "flask-contract-evidence"
            scenario = "Tie every candidate field to immutable selected public contract evidence and QaaS public docs."
            artifact_type = "documentation"
            public_evidence = @($flaskPublicEvidence + $flaskDocsEvidence)
            setup = @("Review selected-contract.json, README blob, and QaaS schema docs.")
            action = @("Run selected top-repo candidate checker.")
            assertions = @("Candidate stays blocked until executable evidence exists.", "No undocumented QaaS fields are introduced.")
            cleanup = @("No external resources are created by static candidate validation.")
            blocked_reason = "Static evidence does not prove live behavior."
            artifact_paths = @($flaskManifestPath)
        }
    )

    $flaskManifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-flask-candidate"
        source_repository = "pallets/flask"
        repository_rank = [int]$flaskSelected.rank
        selected_contract = $flaskRecordPath
        docs_evidence = $flaskDocsEvidence
        public_evidence = $flaskPublicEvidence
        intent_questions = $flaskIntentQuestions
        intent_assumptions = $flaskIntentAssumptions
        artifacts = $flaskArtifacts
        artifact_count = $flaskArtifacts.Count
        artifact_types = @("runner-yaml", "dependency-gate", "documentation", "hook")
        cases = $flaskCases
        assertions = @(
            "Candidate Runner YAML uses schema-derived HttpStatus StatusCode/OutputNames.",
            "Candidate preserves README-backed plain-text body evidence and includes a sidecar ExactHttpTextBody custom assertion packet that is not wired into active YAML before validation.",
            "Candidate remains blocked until lifecycle, template, live QaaS, cleanup, airgapped, and strong-review evidence pass."
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            hook_family = "assertion"
            assertion_type = "ExactHttpTextBody"
            implementation = $flaskHookCodePath
            usage_snippet = $flaskHookUsagePath
            hook_plan = $flaskHookPlanPath
            configuration_contract = [ordered]@{
                OutputName = "Required transaction output name to inspect."
                ExpectedText = "Required exact expected response body text."
                EncodingName = "Optional encoding name; defaults to utf-8."
            }
            builtins_considered = $flaskHookBuiltins
            docs_evidence = $flaskHookDocsEvidence
            validation_status = "not_template_validated"
            weak_validation_passed = $false
        }
        custom_assertion_packets = @($flaskCustomAssertionPacket)
        dependency_gates = @(
            (New-DependencyGate -GateId "selected-public-runtime-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $flaskPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "selected-public-input-output-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $flaskPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "qaas-docs-yaml-shape" -Kind "runtime" -Required $true -Status "ready" -Evidence $flaskDocsEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "python-flask-process-lifecycle" -Kind "dependency" -Required $true -Status "blocked" -Evidence $flaskPublicEvidence -CheckCommand "" -BlockedReason "The external Flask process has not been started, tracked, readiness-checked, and cleaned up by the harness.")
            (New-DependencyGate -GateId "plain-text-body-assertion-or-hook" -Kind "qaas-build" -Required $true -Status "ready" -Evidence @($flaskHookDocsEvidence + @($flaskHookCodePath, $flaskHookUsagePath, $flaskHookPlanPath, $flaskExpectedBodyPath)) -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "cleanup-contract" -Kind "cleanup" -Required $true -Status "blocked" -Evidence $flaskPublicEvidence -CheckCommand "" -BlockedReason "Tracked process tree cleanup and session-data cleanup are not live-validated.")
            (New-DependencyGate -GateId "qaas-template" -Kind "qaas-template" -Required $true -Status "blocked" -Evidence $flaskDocsEvidence -CheckCommand "" -BlockedReason "QaaS template validation has not run for this candidate.")
            (New-DependencyGate -GateId "qaas-live-act-assert" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence $flaskDocsEvidence -CheckCommand "" -BlockedReason "Live QaaS run/act/assert has not run against a tracked Flask process.")
            (New-DependencyGate -GateId "airgapped-validation" -Kind "airgapped" -Required $true -Status "blocked" -Evidence @() -CheckCommand "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none" -BlockedReason "Live weak-model validation has not passed.")
        )
        promotion_requirements = [ordered]@{
            current_state = "blocked"
            target_state = "executable_ready"
            required_evidence = @(
                "Public API, CLI, or runtime contract",
                "Public input and expected-output contract",
                "Public dependency/stub contract",
                "Cleanup contract",
                "Documented QaaS body assertion or custom hook for plain text",
                "QaaS template validation result",
                "C# build result when code artifacts exist",
                "Live QaaS run/act/assert result when dependency gates are ready",
                "Airgapped weak-model validation transcript"
            )
        }
        cleanup = @("No live cleanup was performed during static candidate generation.")
        validation_sequence = @(
            "Validate selected immutable public contract evidence.",
            "Validate QaaS public docs/schema fields.",
            "Run selected top-repo candidate checker.",
            "Build and schema/template-validate the sidecar ExactHttpTextBody custom assertion before executable promotion.",
            "Run QaaS template validation when a Runner host is available.",
            "Run live QaaS act/assert against tracked Flask process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_candidate"
            dry_run = $false
        }
        source_only_blockers = @(
            (New-SourceOnlyBlocker -BlockerId "flask-process-lifecycle-not-proven" -BlockerType "repository_contract" -Description "The README command is public evidence for a candidate command, but process startup, readiness, and cleanup have not been executed and verified." -RequiredEvidence @("Tracked process start transcript", "Readiness probe transcript", "Tracked process cleanup transcript") -PublicEvidence $flaskPublicEvidence -UnblockInstruction "Run an external Flask lifecycle harness and attach the transcripts before promotion.")
            (New-SourceOnlyBlocker -BlockerId "flask-text-body-hook-not-template-validated" -BlockerType "qaas_docs_contract" -Description "A docs-derived ExactHttpTextBody custom assertion has been authored, but Runner assembly discovery, schema regeneration, template validation, build validation, and live QaaS act/assert have not passed." -RequiredEvidence @("Runner host project references the assertion assembly", "Regenerated Runner schema includes Assertion: ExactHttpTextBody", "Template validation transcript for the Flask candidate with the custom assertion enabled", "Live QaaS act/assert transcript against a tracked Flask process") -PublicEvidence @($flaskHookDocsEvidence + @($flaskHookCodePath, $flaskHookUsagePath, $flaskHookPlanPath, $flaskExpectedBodyPath)) -UnblockInstruction "Reference the assertion assembly, regenerate schema/clean bin, run QaaS template validation, then run live QaaS act/assert before promotion.")
            (New-SourceOnlyBlocker -BlockerId "qaas-template-live-not-run" -BlockerType "qaas_docs_contract" -Description "The Runner YAML is schema-derived but has not passed QaaS template or live act/assert validation." -RequiredEvidence @("QaaS template validation transcript", "Live QaaS run/act/assert transcript") -PublicEvidence $flaskDocsEvidence -UnblockInstruction "Run documented QaaS validation commands in an environment with Runner host and Flask process.")
            (New-SourceOnlyBlocker -BlockerId "live-airgapped-weak-model-not-passed" -BlockerType "source_boundary" -Description "Live weak-model validation has not passed for this candidate packet." -RequiredEvidence @("Airgapped transcript with dry_run false and expected output contract preserved") -PublicEvidence @((Join-Path "D:\QaaS\_tools\zappa-harness" "references\airgapped-validation.md")) -UnblockInstruction "Run D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none when quota/routing is available.")
            (New-SourceOnlyBlocker -BlockerId "httpstatus-docs-inconsistency-recorded" -BlockerType "qaas_docs_contract" -Description "The quick-start example uses stale HttpStatus field names, while generated schema docs require StatusCode and OutputNames." -RequiredEvidence @("Runtime/template validation confirming schema-derived field names") -PublicEvidence $flaskDocsEvidence -UnblockInstruction "Keep schema-derived StatusCode/OutputNames unless public docs/schema are updated and revalidated.")
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Selected public contracts support a concrete Flask candidate packet and a docs-derived exact text-body assertion hook, but executable promotion is blocked until process lifecycle, hook schema/template/build/live, QaaS live, cleanup, airgapped, and strong-review evidence pass."
    }
    Write-JsonFile -Path $flaskManifestPath -Value $flaskManifest

    $flaskRecord = [ordered]@{
        rank = [int]$flaskSelected.rank
        repository = "pallets/flask"
        directory = $flaskCandidateDir
        manifest = $flaskManifestPath
        selected_contract = $flaskRecordPath
        status = "candidate_packet_blocked_until_template_live_airgapped_validation"
        promotion_state = "blocked"
        readiness_state = "qaaS_candidate_authored_from_selected_contract"
        artifact_count = $flaskArtifacts.Count
    }
    $records += $flaskRecord
}

$expressRecordPath = Join-Path $SelectedContractsDir "243-expressjs-express\selected-contract.json"
if (Test-Path -LiteralPath $expressRecordPath -PathType Leaf) {
    $expressSelected = Get-Content -LiteralPath $expressRecordPath -Raw | ConvertFrom-Json
    if ([string]$expressSelected.repository -ne "expressjs/express") {
        throw "Expected expressjs/express selected contract, got $($expressSelected.repository)"
    }
    if ([string]$expressSelected.status -ne "contract_content_harvested_not_executable" -or [string]$expressSelected.promotion_state -ne "blocked") {
        throw "Selected Express contract must be harvested and blocked: $expressRecordPath"
    }

    $expressSelectedPublicContracts = @($expressSelected.selected_public_contracts)
    $expressReadmeRecord = $expressSelectedPublicContracts | Where-Object { [string]$_.source_path -in @("README.md", "Readme.md") } | Select-Object -First 1
    if ($null -eq $expressReadmeRecord) {
        throw "Selected Express contract lacks README.md evidence."
    }
    $expressReadmePath = Assert-UnderRoot -Path ([string]$expressReadmeRecord.local_path) -Root $SelectedContractsDir -Description "Express README evidence"
    $expressReadmeText = Get-Content -LiteralPath $expressReadmePath -Raw
    $requiredExpressReadmeMarkers = @(
        "import express from 'express'",
        "const app = express()",
        "app.get('/', (req, res) => {",
        "res.send('Hello World')",
        "app.listen(3000, () => {",
        "http://localhost:3000",
        "npm install express"
    )
    foreach ($marker in $requiredExpressReadmeMarkers) {
        if (-not $expressReadmeText.Contains($marker)) {
            throw "Express README evidence missing marker '$marker': $expressReadmePath"
        }
    }

    $expressSafeRepo = "{0:D3}-{1}" -f [int]$expressSelected.rank, (New-SafeName ([string]$expressSelected.repository).Replace("/", "-"))
    $expressCandidateDir = Join-Path $resolvedOutDir $expressSafeRepo
    $expressAppDir = Join-Path $expressCandidateDir "app"
    $expressExpectationsDir = Join-Path $expressCandidateDir "expectations"
    $expressRequestPayloadsDir = Join-Path $expressCandidateDir "request-payloads"
    $expressHookDir = Join-Path $expressCandidateDir "assertion-packets\ExactHttpTextBody"
    foreach ($dir in @($expressCandidateDir, $expressAppDir, $expressExpectationsDir, $expressRequestPayloadsDir, $expressHookDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $expressRunnerPath = Join-Path $expressCandidateDir "test.qaas.yaml"
    $expressAppPath = Join-Path $expressAppDir "app.mjs"
    $expressExpectedBodyPath = Join-Path $expressExpectationsDir "root-body.txt"
    $expressRequestPayloadPath = Join-Path $expressRequestPayloadsDir "get-root.bin"
    $expressRuntimePlanPath = Join-Path $expressCandidateDir "candidate-runtime-plan.json"
    $expressManifestPath = Join-Path $expressCandidateDir "qaas-artifact-manifest.json"
    $expressHookCodePath = Join-Path $expressHookDir "ExactHttpTextBody.cs"
    $expressHookUsagePath = Join-Path $expressHookDir "ExactHttpTextBody.usage.yaml.txt"
    $expressHookPlanPath = Join-Path $expressHookDir "custom-text-body-hook-plan.json"

    Write-TextFile -Path $expressRunnerPath -Value (New-ExpressRunnerYaml)
    Write-TextFile -Path $expressAppPath -Value @'
// Generated from immutable public Express README evidence.
import express from 'express'

const app = express()

app.get('/', (req, res) => {
  res.send('Hello World')
})

app.listen(3000, () => {
  console.log('Server is running on http://localhost:3000')
})
'@
    Write-TextFile -Path $expressExpectedBodyPath -Value "Hello World"
    [System.IO.File]::WriteAllBytes($expressRequestPayloadPath, [byte[]]::new(0))
    Write-TextFile -Path $expressHookCodePath -Value (New-ExpressExactTextBodyAssertionCode)
    Write-TextFile -Path $expressHookUsagePath -Value (New-ExpressExactTextBodyUsageSnippet)

    $expressHookDocsEvidence = @(
        "D:\QaaS\qaas-docs\docs\assertions\index.md",
        "D:\QaaS\qaas-docs\docs\assertions\custom-authoring-guide.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputContentByExpectedCsvResults\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputDeserializableTo\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\overview.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\schema-extensions.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $expressDocsEvidence = @($docsEvidence + $expressHookDocsEvidence) | Select-Object -Unique
    $expressExpectedBodySha256 = Get-Sha256Hex -Path $expressExpectedBodyPath
    $expressHookBuiltins = @(
        [ordered]@{ name = "HttpStatus"; reason_insufficient = "Status-only assertion; does not compare response body bytes." },
        [ordered]@{ name = "OutputContentByExpectedCsvResults"; reason_insufficient = "JSON/CSV field mapping assertion; not exact raw/plain-text body equality." },
        [ordered]@{ name = "OutputDeserializableTo"; reason_insufficient = "Checks deserialization success, not equality with exact public README text." },
        [ordered]@{ name = "ObjectOutputJsonSchema"; reason_insufficient = "Checks JSON schema compatibility, not exact raw/plain-text body equality." }
    )

    $expressPublicEvidence = @(
        [string]$expressRecordPath
        @($expressSelected.public_evidence)
        @($expressSelectedPublicContracts | ForEach-Object { [string]$_.local_path })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $expressCustomAssertionPacket = [ordered]@{
        packet_id = "express-exact-http-text-body"
        assertion_name = "ExactHttpTextBody"
        status = "blocked_until_build_template_live_airgapped_validation"
        promotion_state = "blocked"
        activation = "sidecar_only"
        wired_into_runner_yaml = $false
        source_files = @($expressHookCodePath)
        yaml_fragment = $expressHookUsagePath
        hook_plan = $expressHookPlanPath
        expected_body_path = $expressExpectedBodyPath
        expected_body_sha256 = $expressExpectedBodySha256
        encoding = "utf-8"
        comparison = "byte_for_byte"
        normalization = "none"
        case_sensitive = $true
        trim = $false
        contains = $false
        docs_evidence = $expressHookDocsEvidence
        public_evidence = $expressPublicEvidence
        validation_records = [ordered]@{
            build = "not_run"
            schema = "not_run"
            template = "not_run"
            live = "not_run"
            airgapped = "not_run"
        }
        weak_validation_passed = $false
    }

    $expressHookPlan = [ordered]@{
        schema_version = 1
        status = "authored_from_public_docs_not_template_validated"
        hook_family = "assertion"
        assertion_type = "ExactHttpTextBody"
        configuration_contract = [ordered]@{
            OutputName = "Required transaction output name, backed by custom assertion docs and the Express transaction name GetRoot."
            ExpectedText = "Required exact expected text, backed by Express README output evidence."
            EncodingName = "Optional text encoding name; defaults to utf-8."
        }
        builtins_considered = $expressHookBuiltins
        docs_evidence = $expressHookDocsEvidence
        files = [ordered]@{
            implementation = $expressHookCodePath
            usage_snippet = $expressHookUsagePath
        }
        validation_sequence = @(
            "Reference the assertion assembly from the Runner host project.",
            "Regenerate Runner schema and clean bin cache so Assertion: ExactHttpTextBody is discoverable.",
            "Run Runner template validation against the Express candidate YAML with the assertion enabled.",
            "Run live QaaS act/assert against a tracked Express process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        custom_assertion_packet = $expressCustomAssertionPacket
        promotion_state = "blocked"
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $expressHookPlanPath -Value $expressHookPlan

    $expressRuntimePlan = [ordered]@{
        schema_version = 1
        repository = "expressjs/express"
        rank = [int]$expressSelected.rank
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate_runtime_command_from_selected_readme_snippet"
        command = "node app.mjs"
        install_command = "npm install express"
        working_directory = $expressAppDir
        fixture = $expressAppPath
        expected_listen_url = "http://127.0.0.1:3000/"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:3000/"
            expected_status = 200
            expected_body = "Hello World"
        }
        cleanup = [ordered]@{
            required = $true
            strategy = "terminate_tracked_process_tree"
            status = "not_validated"
        }
        blockers = @(
            "prove_process_lifecycle_and_cleanup_without assuming private source",
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            assertion_type = "ExactHttpTextBody"
            implementation = $expressHookCodePath
            usage_snippet = $expressHookUsagePath
            hook_plan = $expressHookPlanPath
            validation_status = "not_template_validated"
        }
        custom_assertion_packets = @($expressCustomAssertionPacket)
        public_evidence = $expressPublicEvidence
    }
    Write-JsonFile -Path $expressRuntimePlanPath -Value $expressRuntimePlan

    $expressIntentQuestions = @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "GET / from the README Express app should return HTTP 200 and the exact body Hello World." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may test a generated Express app, add punctuation, or skip the body contract." -HowToOverride "Replace the route and body only with exact public repository evidence." -PublicEvidence $expressPublicEvidence)
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "The Runner target is an externally-started Express HTTP process on 127.0.0.1:3000; QaaS YAML does not start or clean that process." -AnswerSource "public_repo_contract" -RiskIfWrong "Process lifecycle could be incorrectly encoded as undocumented QaaS YAML." -HowToOverride "Provide documented QaaS lifecycle support or keep startup in an external harness plan." -PublicEvidence $expressPublicEvidence)
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "QaaS public docs/schema support HTTP Transactions, FromFileSystem data-source payload bytes, HttpStatus assertions, and custom assertions by short type name; the ExactHttpTextBody hook is authored but not schema/template/live validated." -AnswerSource "public_docs" -RiskIfWrong "A weak model may invent a built-in text body assertion or treat sidecar hook code as executable validation." -HowToOverride "Provide template/build/live validation for the custom assertion packet." -PublicEvidence $expressDocsEvidence)
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Input is a GET request to /. Outputs are HTTP status 200 and body Hello World. Side effects should be read-only for this GET." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may over-assert mutations, persistence, or unrelated Express middleware behavior." -HowToOverride "Provide public side-effect evidence for any additional assertion." -PublicEvidence $expressPublicEvidence)
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, malformed, retry, and observability cases remain blocked; this candidate covers only one README-backed happy path and cleanup planning." -AnswerSource "blocked" -RiskIfWrong "A weak model may claim broad Express framework coverage from one happy-path route." -HowToOverride "Add exact public negative-case and observability contracts before expanding assertions." -PublicEvidence $expressPublicEvidence)
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Dependencies are Node/npm access, Express package installation, app.mjs in the runtime working directory, and port 3000 availability; those dependencies are identified from public evidence but not live-validated." -AnswerSource "blocked" -RiskIfWrong "The candidate may be promoted where Node, npm, Express package restore, port, or fixture placement is unavailable." -HowToOverride "Provide validated dependency transcripts for the target environment." -PublicEvidence $expressPublicEvidence)
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Static candidate validation can run now. Process lifecycle, custom assertion build/schema/template validation, live act/assert execution, cleanup proof, and live weak-model validation are deferred and block promotion." -AnswerSource "blocked" -RiskIfWrong "A weak model may confuse a candidate packet with an executable test." -HowToOverride "Attach passing lifecycle, custom assertion build/schema/template, live, cleanup, airgapped, and strong-review evidence." -PublicEvidence $expressPublicEvidence)
    )

    $expressIntentAssumptions = @(
        (New-IntentAssumption -Assumption "The README simple Express app is the public behavior contract for this candidate." -WhySafe "It contains exact import, route, listen port, URL, and body markers harvested from an immutable Git blob." -RiskIfWrong "The candidate may not match the generated Express application from express-generator." -HowToOverride "Replace the selected contract with another immutable public blob." -PublicEvidence $expressPublicEvidence)
        (New-IntentAssumption -Assumption "Process lifecycle belongs to the external harness until QaaS docs prove otherwise." -WhySafe "The public QaaS Runner docs describe HTTP transactions but not starting arbitrary Node processes." -RiskIfWrong "Startup or cleanup may be missed if a future QaaS lifecycle feature exists." -HowToOverride "Provide public QaaS lifecycle docs and update the checker." -PublicEvidence $docsEvidence)
        (New-IntentAssumption -Assumption "Plain-text body comparison is represented by a custom assertion sidecar, but remains blocked until build/schema/template/live validation passes." -WhySafe "The available built-ins do not prove exact raw text equality, while public custom assertion docs support sidecar authoring by short type name." -RiskIfWrong "A weak model may treat authored code as runtime validation." -HowToOverride "Provide passing custom assertion build, schema, template, and live QaaS evidence." -PublicEvidence $expressDocsEvidence)
    )

    $expressArtifacts = @($expressRunnerPath, $expressAppPath, $expressExpectedBodyPath, $expressRequestPayloadPath, $expressRuntimePlanPath, $expressManifestPath)
    $expressManifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-express-candidate"
        source_repository = "expressjs/express"
        repository_rank = [int]$expressSelected.rank
        selected_contract = $expressRecordPath
        docs_evidence = $expressDocsEvidence
        public_evidence = $expressPublicEvidence
        intent_questions = $expressIntentQuestions
        intent_assumptions = $expressIntentAssumptions
        artifacts = $expressArtifacts
        artifact_count = $expressArtifacts.Count
        artifact_types = @("runner-yaml", "dependency-gate", "documentation", "hook")
        cases = @(
            [ordered]@{
                case_id = "express-read-root"
                scenario = "Call README-backed Express GET / and assert documented HTTP success while the sidecar exact text-body assertion remains build/schema/template/live blocked."
                artifact_type = "runner-yaml"
                public_evidence = $expressPublicEvidence
                setup = @("Install Express and start the generated app.mjs externally.", "Ensure port 3000 is free.", "Use get-root.bin as the byte payload driver for the GET transaction.")
                action = @("Run QaaS Runner against test.qaas.yaml after template validation is available.")
                assertions = @("HttpStatus StatusCode 200 for GetRoot.", "Exact body Hello World is preserved as expected-response evidence but blocked from YAML until the custom assertion is validated.")
                cleanup = @("Terminate the tracked Node process tree.", "Remove candidate session-data after live validation.")
                blocked_reason = "QaaS template, live act/assert, exact plain-text body assertion build/schema/template validation, cleanup, and live weak-model validation have not passed."
                artifact_paths = @($expressRunnerPath, $expressRequestPayloadPath, $expressExpectedBodyPath)
            }
        )
        assertions = @(
            "Candidate Runner YAML uses schema-derived HttpStatus StatusCode/OutputNames.",
            "Candidate preserves README-backed plain-text body evidence and includes a sidecar ExactHttpTextBody custom assertion packet that is not wired into active YAML before validation.",
            "Candidate remains blocked until lifecycle, template, live QaaS, cleanup, airgapped, and strong-review evidence pass."
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            hook_family = "assertion"
            assertion_type = "ExactHttpTextBody"
            implementation = $expressHookCodePath
            usage_snippet = $expressHookUsagePath
            hook_plan = $expressHookPlanPath
            configuration_contract = [ordered]@{
                OutputName = "Required transaction output name to inspect."
                ExpectedText = "Required exact expected response body text."
                EncodingName = "Optional encoding name; defaults to utf-8."
            }
            builtins_considered = $expressHookBuiltins
            docs_evidence = $expressHookDocsEvidence
            validation_status = "not_template_validated"
            weak_validation_passed = $false
        }
        custom_assertion_packets = @($expressCustomAssertionPacket)
        dependency_gates = @(
            (New-DependencyGate -GateId "selected-public-runtime-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $expressPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "selected-public-input-output-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $expressPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "qaas-docs-yaml-shape" -Kind "runtime" -Required $true -Status "ready" -Evidence $expressDocsEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "node-express-process-lifecycle" -Kind "dependency" -Required $true -Status "blocked" -Evidence $expressPublicEvidence -CheckCommand "" -BlockedReason "The external Express process has not been started, tracked, readiness-checked, and cleaned up by the harness.")
            (New-DependencyGate -GateId "plain-text-body-assertion-or-hook" -Kind "qaas-build" -Required $true -Status "ready" -Evidence @($expressHookDocsEvidence + @($expressHookCodePath, $expressHookUsagePath, $expressHookPlanPath, $expressExpectedBodyPath)) -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "cleanup-contract" -Kind "cleanup" -Required $true -Status "blocked" -Evidence $expressPublicEvidence -CheckCommand "" -BlockedReason "Tracked process tree cleanup and session-data cleanup are not live-validated.")
            (New-DependencyGate -GateId "qaas-template" -Kind "qaas-template" -Required $true -Status "blocked" -Evidence $expressDocsEvidence -CheckCommand "" -BlockedReason "QaaS template validation has not run for this candidate.")
            (New-DependencyGate -GateId "qaas-live-act-assert" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence $expressDocsEvidence -CheckCommand "" -BlockedReason "Live QaaS run/act/assert has not run against a tracked Express process.")
            (New-DependencyGate -GateId "airgapped-validation" -Kind "airgapped" -Required $true -Status "blocked" -Evidence @() -CheckCommand "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none" -BlockedReason "Live weak-model validation has not passed.")
        )
        promotion_requirements = [ordered]@{
            current_state = "blocked"
            target_state = "executable_ready"
            required_evidence = @(
                "Public API, CLI, or runtime contract",
                "Public input and expected-output contract",
                "Public dependency/stub contract",
                "Cleanup contract",
                "Documented QaaS body assertion or custom hook for plain text",
                "QaaS template validation result",
                "C# build result when code artifacts exist",
                "Live QaaS run/act/assert result when dependency gates are ready",
                "Airgapped weak-model validation transcript"
            )
        }
        cleanup = @("No live cleanup was performed during static candidate generation.")
        validation_sequence = @(
            "Validate selected immutable public contract evidence.",
            "Validate QaaS public docs/schema fields.",
            "Run selected top-repo candidate checker.",
            "Build and schema/template-validate the sidecar ExactHttpTextBody custom assertion before executable promotion.",
            "Run QaaS template validation when a Runner host is available.",
            "Run live QaaS act/assert against tracked Express process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_candidate"
            dry_run = $false
        }
        source_only_blockers = @(
            (New-SourceOnlyBlocker -BlockerId "express-process-lifecycle-not-proven" -BlockerType "repository_contract" -Description "The README app and install command are public evidence, but process startup, readiness, dependency restore, and cleanup have not been executed and verified." -RequiredEvidence @("npm install transcript", "Tracked process start transcript", "Readiness probe transcript", "Tracked process cleanup transcript") -PublicEvidence $expressPublicEvidence -UnblockInstruction "Run an external Express lifecycle harness and attach the transcripts before promotion.")
            (New-SourceOnlyBlocker -BlockerId "express-text-body-hook-not-template-validated" -BlockerType "qaas_docs_contract" -Description "A docs-derived ExactHttpTextBody custom assertion has been authored, but Runner assembly discovery, schema regeneration, template validation, build validation, and live QaaS act/assert have not passed." -RequiredEvidence @("Runner host project references the assertion assembly", "Regenerated Runner schema includes Assertion: ExactHttpTextBody", "Template validation transcript for the Express candidate with the custom assertion enabled", "Live QaaS act/assert transcript against a tracked Express process") -PublicEvidence @($expressHookDocsEvidence + @($expressHookCodePath, $expressHookUsagePath, $expressHookPlanPath, $expressExpectedBodyPath)) -UnblockInstruction "Reference the assertion assembly, regenerate schema/clean bin, run QaaS template validation, then run live QaaS act/assert before promotion.")
            (New-SourceOnlyBlocker -BlockerId "qaas-template-live-not-run" -BlockerType "qaas_docs_contract" -Description "The Runner YAML is schema-derived but has not passed QaaS template or live act/assert validation." -RequiredEvidence @("QaaS template validation transcript", "Live QaaS run/act/assert transcript") -PublicEvidence $expressDocsEvidence -UnblockInstruction "Run documented QaaS validation commands in an environment with Runner host and Express process.")
            (New-SourceOnlyBlocker -BlockerId "live-airgapped-weak-model-not-passed" -BlockerType "source_boundary" -Description "Live weak-model validation has not passed for this candidate packet." -RequiredEvidence @("Airgapped transcript with dry_run false and expected output contract preserved") -PublicEvidence @((Join-Path "D:\QaaS\_tools\zappa-harness" "references\airgapped-validation.md")) -UnblockInstruction "Run D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none when quota/routing is available.")
            (New-SourceOnlyBlocker -BlockerId "httpstatus-docs-inconsistency-recorded" -BlockerType "qaas_docs_contract" -Description "The quick-start example uses stale HttpStatus field names, while generated schema docs require StatusCode and OutputNames." -RequiredEvidence @("Runtime/template validation confirming schema-derived field names") -PublicEvidence $expressDocsEvidence -UnblockInstruction "Keep schema-derived StatusCode/OutputNames unless public docs/schema are updated and revalidated.")
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Selected public contracts support a concrete Express candidate packet and a docs-derived exact text-body assertion hook, but executable promotion is blocked until process lifecycle, hook schema/template/build/live, QaaS live, cleanup, airgapped, and strong-review evidence pass."
    }
    Write-JsonFile -Path $expressManifestPath -Value $expressManifest

    $expressRecord = [ordered]@{
        rank = [int]$expressSelected.rank
        repository = "expressjs/express"
        directory = $expressCandidateDir
        manifest = $expressManifestPath
        selected_contract = $expressRecordPath
        status = "candidate_packet_blocked_until_template_live_airgapped_validation"
        promotion_state = "blocked"
        readiness_state = "qaaS_candidate_authored_from_selected_contract"
        artifact_count = $expressArtifacts.Count
    }
    $records += $expressRecord
}

$fastApiRecordPath = Join-Path $SelectedContractsDir "114-fastapi-fastapi\selected-contract.json"
if (Test-Path -LiteralPath $fastApiRecordPath -PathType Leaf) {
    $fastApiSelected = Get-Content -LiteralPath $fastApiRecordPath -Raw | ConvertFrom-Json
    if ([string]$fastApiSelected.repository -ne "fastapi/fastapi") {
        throw "Expected fastapi/fastapi selected contract, got $($fastApiSelected.repository)"
    }
    if ([string]$fastApiSelected.status -ne "contract_content_harvested_not_executable" -or [string]$fastApiSelected.promotion_state -ne "blocked") {
        throw "Selected FastAPI contract must be harvested and blocked: $fastApiRecordPath"
    }

    $fastApiSelectedPublicContracts = @($fastApiSelected.selected_public_contracts)
    $fastApiReadmeRecord = $fastApiSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "README.md" } | Select-Object -First 1
    if ($null -eq $fastApiReadmeRecord) {
        throw "Selected FastAPI contract lacks README.md evidence."
    }
    $fastApiReadmePath = Assert-UnderRoot -Path ([string]$fastApiReadmeRecord.local_path) -Root $SelectedContractsDir -Description "FastAPI README evidence"
    $fastApiReadmeText = Get-Content -LiteralPath $fastApiReadmePath -Raw
    $requiredFastApiReadmeMarkers = @(
        'from fastapi import FastAPI',
        'app = FastAPI()',
        '@app.get("/")',
        'return {"Hello": "World"}',
        '@app.get("/items/{item_id}")',
        'return {"item_id": item_id, "q": q}',
        '$ fastapi dev',
        'http://127.0.0.1:8000',
        'http://127.0.0.1:8000/items/5?q=somequery',
        '{"item_id": 5, "q": "somequery"}'
    )
    foreach ($marker in $requiredFastApiReadmeMarkers) {
        if (-not $fastApiReadmeText.Contains($marker)) {
            throw "FastAPI README evidence missing marker '$marker': $fastApiReadmePath"
        }
    }

    $fastApiSafeRepo = "{0:D3}-{1}" -f [int]$fastApiSelected.rank, (New-SafeName ([string]$fastApiSelected.repository).Replace("/", "-"))
    $fastApiCandidateDir = Join-Path $resolvedOutDir $fastApiSafeRepo
    $fastApiAppDir = Join-Path $fastApiCandidateDir "app"
    $fastApiSchemasDir = Join-Path $fastApiCandidateDir "schemas"
    $fastApiRequestPayloadsDir = Join-Path $fastApiCandidateDir "request-payloads"
    foreach ($dir in @($fastApiCandidateDir, $fastApiAppDir, $fastApiSchemasDir, $fastApiRequestPayloadsDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $fastApiRunnerPath = Join-Path $fastApiCandidateDir "test.qaas.yaml"
    $fastApiAppPath = Join-Path $fastApiAppDir "main.py"
    $fastApiSchemaPath = Join-Path $fastApiSchemasDir "item-response.schema.json"
    $fastApiRequestPayloadPath = Join-Path $fastApiRequestPayloadsDir "get-items-5.bin"
    $fastApiRuntimePlanPath = Join-Path $fastApiCandidateDir "candidate-runtime-plan.json"
    $fastApiManifestPath = Join-Path $fastApiCandidateDir "qaas-artifact-manifest.json"

    Write-TextFile -Path $fastApiRunnerPath -Value (New-FastApiRunnerYaml)
    Write-TextFile -Path $fastApiAppPath -Value @'
# Generated from immutable public FastAPI README evidence.
from fastapi import FastAPI

app = FastAPI()


@app.get("/")
def read_root():
    return {"Hello": "World"}


@app.get("/items/{item_id}")
def read_item(item_id: int, q: str | None = None):
    return {"item_id": item_id, "q": q}
'@
    Write-TextFile -Path $fastApiSchemaPath -Value @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["item_id", "q"],
  "additionalProperties": false,
  "properties": {
    "item_id": { "const": 5 },
    "q": { "const": "somequery" }
  }
}
'@
    [System.IO.File]::WriteAllBytes($fastApiRequestPayloadPath, [byte[]]::new(0))

    $fastApiPublicEvidence = @(
        [string]$fastApiRecordPath
        @($fastApiSelected.public_evidence)
        @($fastApiSelectedPublicContracts | ForEach-Object { [string]$_.local_path })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    $fastApiDocsEvidence = @(
        $docsEvidence
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\configuration\yamlView.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\configuration\tableView.md"
    ) | Select-Object -Unique

    $fastApiRuntimePlan = [ordered]@{
        schema_version = 1
        repository = "fastapi/fastapi"
        rank = [int]$fastApiSelected.rank
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        command = "fastapi dev"
        working_directory = $fastApiAppDir
        fixture = $fastApiAppPath
        expected_listen_url = "http://127.0.0.1:8000"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:8000/items/5?q=somequery"
            expected_status = 200
            expected_json = [ordered]@{
                item_id = 5
                q = "somequery"
            }
        }
        cleanup = [ordered]@{
            required = $true
            strategy = "terminate_tracked_process_tree"
            status = "not_validated"
        }
        blockers = @(
            "prove_process_lifecycle_and_cleanup_without assuming private source",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
        public_evidence = $fastApiPublicEvidence
    }
    Write-JsonFile -Path $fastApiRuntimePlanPath -Value $fastApiRuntimePlan

    $fastApiIntentQuestions = @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "GET /items/5?q=somequery from the README FastAPI app should return HTTP 200 and the exact JSON object with item_id 5 and q somequery." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may test the wrong route, drop the query string, or use a loose body assertion." -HowToOverride "Replace the route and expected output only with exact public repository evidence." -PublicEvidence $fastApiPublicEvidence)
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "The Runner target is an externally-started FastAPI HTTP process on 127.0.0.1:8000; QaaS YAML does not start or clean that process." -AnswerSource "public_repo_contract" -RiskIfWrong "Process lifecycle could be incorrectly encoded as undocumented QaaS YAML." -HowToOverride "Provide documented QaaS lifecycle support or keep startup in an external harness plan." -PublicEvidence $fastApiPublicEvidence)
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "QaaS public docs/schema support HTTP Transactions, FromFileSystem data-source bytes, HttpStatus assertions, OutputDeserialize Json, and ObjectOutputJsonSchema for exact schema-backed JSON body validation." -AnswerSource "public_docs" -RiskIfWrong "The YAML could cite invented query/body fields or stale assertion names." -HowToOverride "Update docs evidence and rerun the selected candidate checker." -PublicEvidence $fastApiDocsEvidence)
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Input is a GET request to /items/5?q=somequery with an empty body. Outputs are HTTP status 200 and JSON item_id=5, q=somequery. Side effects should be read-only for this GET." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may over-assert mutations, persistence, or unrelated endpoints." -HowToOverride "Provide public side-effect evidence for any additional assertion." -PublicEvidence $fastApiPublicEvidence)
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, malformed, retry, and observability cases remain blocked; this candidate covers only one README-backed happy path and cleanup planning." -AnswerSource "blocked" -RiskIfWrong "A weak model may claim broad framework coverage from one happy-path route." -HowToOverride "Add exact public negative-case and observability contracts before expanding assertions." -PublicEvidence $fastApiPublicEvidence)
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Dependencies are Python, FastAPI CLI/runtime access, app/main.py in the runtime working directory, and port 8000 availability; those dependencies are identified from public evidence but not live-validated." -AnswerSource "blocked" -RiskIfWrong "The candidate may be promoted where Python, FastAPI CLI, port, or fixture placement is not available." -HowToOverride "Provide validated dependency transcripts for the target environment." -PublicEvidence $fastApiPublicEvidence)
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Static candidate validation can run now. Process lifecycle, QaaS template validation, live act/assert execution, cleanup proof, and live weak-model validation are deferred and block promotion." -AnswerSource "blocked" -RiskIfWrong "A weak model may confuse a candidate packet with an executable test." -HowToOverride "Attach passing lifecycle, template, live, cleanup, airgapped, and strong-review evidence." -PublicEvidence $fastApiPublicEvidence)
    )

    $fastApiIntentAssumptions = @(
        (New-IntentAssumption -Assumption "The README simple example is the public behavior contract for this candidate." -WhySafe "It contains exact app code, command, URL, route with query string, and response body markers harvested from an immutable Git blob." -RiskIfWrong "The candidate may not match another FastAPI app or route." -HowToOverride "Replace the selected contract with another immutable public blob." -PublicEvidence $fastApiPublicEvidence)
        (New-IntentAssumption -Assumption "Process lifecycle belongs to the external harness until QaaS docs prove otherwise." -WhySafe "The public QaaS Runner docs describe HTTP transactions but not starting arbitrary Python processes." -RiskIfWrong "Startup or cleanup may be missed if a future QaaS lifecycle feature exists." -HowToOverride "Provide public QaaS lifecycle docs and update the checker." -PublicEvidence $fastApiDocsEvidence)
        (New-IntentAssumption -Assumption "JSON body equality is represented by an ObjectOutputJsonSchema side data source rather than invented JsonPath or ExpectedBody fields." -WhySafe "ObjectOutputJsonSchema is documented and can enforce required keys, constants, and additionalProperties false." -RiskIfWrong "If the Runner serializes outputs differently, template/live validation will catch it before promotion." -HowToOverride "Provide passing QaaS template/live evidence or a different documented assertion." -PublicEvidence $fastApiDocsEvidence)
    )

    $fastApiArtifacts = @($fastApiRunnerPath, $fastApiAppPath, $fastApiSchemaPath, $fastApiRequestPayloadPath, $fastApiRuntimePlanPath, $fastApiManifestPath)
    $fastApiCases = @(
        [ordered]@{
            case_id = "fastapi-read-item-five"
            scenario = "Call README-backed FastAPI GET /items/5?q=somequery and assert documented HTTP success and exact JSON response schema."
            artifact_type = "runner-yaml"
            public_evidence = @($fastApiPublicEvidence + $fastApiDocsEvidence)
            setup = @("Start FastAPI externally with the generated main.py using the README command.", "Ensure port 8000 is free.", "Use get-items-5.bin as the byte payload driver for the GET transaction.")
            action = @("Run QaaS Runner against test.qaas.yaml after template validation is available.")
            assertions = @("HttpStatus StatusCode 200 for GetItemFive.", "ObjectOutputJsonSchema requires item_id=5, q=somequery, and no additional properties.")
            cleanup = @("Terminate the tracked FastAPI process tree.", "Remove candidate session-data after live validation.")
            blocked_reason = "QaaS template, live act/assert, cleanup, and live weak-model validation have not passed."
            artifact_paths = @($fastApiRunnerPath, $fastApiSchemaPath, $fastApiRequestPayloadPath)
        },
        [ordered]@{
            case_id = "fastapi-runtime-plan"
            scenario = "Keep Python process startup and cleanup outside QaaS YAML until public QaaS docs prove lifecycle support."
            artifact_type = "dependency-gate"
            public_evidence = $fastApiPublicEvidence
            setup = @("Use candidate-runtime-plan.json as an external harness plan only.")
            action = @("Start and stop FastAPI through a tracked process runner, not through undocumented QaaS YAML fields.")
            assertions = @("Runtime plan remains blocked and never counts as executable promotion evidence by itself.")
            cleanup = @("Tracked process tree termination must be validated before promotion.")
            blocked_reason = "Process lifecycle and cleanup are planned but not validated."
            artifact_paths = @($fastApiRuntimePlanPath, $fastApiAppPath)
        },
        [ordered]@{
            case_id = "fastapi-contract-evidence"
            scenario = "Tie every candidate field to immutable selected public contract evidence and QaaS public docs."
            artifact_type = "documentation"
            public_evidence = @($fastApiPublicEvidence + $fastApiDocsEvidence)
            setup = @("Review selected-contract.json, README blob, and QaaS schema docs.")
            action = @("Run selected top-repo candidate checker.")
            assertions = @("Candidate stays blocked until executable evidence exists.", "No undocumented QaaS fields are introduced.")
            cleanup = @("No external resources are created by static candidate validation.")
            blocked_reason = "Static evidence does not prove live behavior."
            artifact_paths = @($fastApiManifestPath)
        }
    )

    $fastApiManifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-fastapi-candidate"
        source_repository = "fastapi/fastapi"
        repository_rank = [int]$fastApiSelected.rank
        selected_contract = $fastApiRecordPath
        docs_evidence = $fastApiDocsEvidence
        public_evidence = $fastApiPublicEvidence
        intent_questions = $fastApiIntentQuestions
        intent_assumptions = $fastApiIntentAssumptions
        artifacts = $fastApiArtifacts
        artifact_count = $fastApiArtifacts.Count
        artifact_types = @("runner-yaml", "dependency-gate", "documentation")
        cases = $fastApiCases
        assertions = @(
            "Candidate Runner YAML uses schema-derived HttpStatus StatusCode/OutputNames.",
            "Candidate body assertion uses documented ObjectOutputJsonSchema with constants for item_id and q.",
            "Candidate remains blocked until lifecycle, template, live QaaS, cleanup, airgapped, and strong-review evidence pass."
        )
        dependency_gates = @(
            (New-DependencyGate -GateId "selected-public-runtime-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $fastApiPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "selected-public-input-output-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $fastApiPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "qaas-docs-yaml-shape" -Kind "runtime" -Required $true -Status "ready" -Evidence $fastApiDocsEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "python-fastapi-process-lifecycle" -Kind "dependency" -Required $true -Status "blocked" -Evidence $fastApiPublicEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-fastapi.ps1" -BlockedReason "The external FastAPI process has not been started, tracked, readiness-checked, and cleaned up by the harness.")
            (New-DependencyGate -GateId "cleanup-contract" -Kind "cleanup" -Required $true -Status "blocked" -Evidence $fastApiPublicEvidence -CheckCommand "" -BlockedReason "Tracked process tree cleanup and session-data cleanup are not live-validated.")
            (New-DependencyGate -GateId "qaas-template" -Kind "qaas-template" -Required $true -Status "blocked" -Evidence $fastApiDocsEvidence -CheckCommand "" -BlockedReason "QaaS template validation has not run for this candidate.")
            (New-DependencyGate -GateId "qaas-live-act-assert" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence $fastApiDocsEvidence -CheckCommand "" -BlockedReason "Live QaaS run/act/assert has not run against a tracked FastAPI process.")
            (New-DependencyGate -GateId "airgapped-validation" -Kind "airgapped" -Required $true -Status "blocked" -Evidence @() -CheckCommand "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none" -BlockedReason "Live weak-model validation has not passed.")
        )
        promotion_requirements = [ordered]@{
            current_state = "blocked"
            target_state = "executable_ready"
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
        cleanup = @("No live cleanup was performed during static candidate generation.")
        validation_sequence = @(
            "Validate selected immutable public contract evidence.",
            "Validate QaaS public docs/schema fields.",
            "Run selected top-repo candidate checker.",
            "Run QaaS template validation when a Runner host is available.",
            "Run live QaaS act/assert against tracked FastAPI process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_candidate"
            dry_run = $false
        }
        source_only_blockers = @(
            (New-SourceOnlyBlocker -BlockerId "fastapi-process-lifecycle-not-proven" -BlockerType "repository_contract" -Description "The README command is public evidence for a candidate command, but process startup, readiness, and cleanup have not been executed and verified." -RequiredEvidence @("Tracked process start transcript", "Readiness probe transcript", "Tracked process cleanup transcript") -PublicEvidence $fastApiPublicEvidence -UnblockInstruction "Run an external FastAPI lifecycle harness and attach the transcripts before promotion.")
            (New-SourceOnlyBlocker -BlockerId "qaas-template-live-not-run" -BlockerType "qaas_docs_contract" -Description "The Runner YAML is schema-derived but has not passed QaaS template or live act/assert validation." -RequiredEvidence @("QaaS template validation transcript", "Live QaaS run/act/assert transcript") -PublicEvidence $fastApiDocsEvidence -UnblockInstruction "Run documented QaaS validation commands in an environment with Runner host and FastAPI process.")
            (New-SourceOnlyBlocker -BlockerId "live-airgapped-weak-model-not-passed" -BlockerType "source_boundary" -Description "Live weak-model validation has not passed for this candidate packet." -RequiredEvidence @("Airgapped transcript with dry_run false and expected output contract preserved") -PublicEvidence @((Join-Path "D:\QaaS\_tools\zappa-harness" "references\airgapped-validation.md")) -UnblockInstruction "Run D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none when quota/routing is available.")
            (New-SourceOnlyBlocker -BlockerId "httpstatus-docs-inconsistency-recorded" -BlockerType "qaas_docs_contract" -Description "The quick-start example uses stale HttpStatus field names, while generated schema docs require StatusCode and OutputNames." -RequiredEvidence @("Runtime/template validation confirming schema-derived field names") -PublicEvidence $fastApiDocsEvidence -UnblockInstruction "Keep schema-derived StatusCode/OutputNames unless public docs/schema are updated and revalidated.")
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Selected public contracts support a concrete FastAPI candidate packet, but executable promotion is blocked until process lifecycle, QaaS template/live, cleanup, airgapped, and strong-review evidence pass."
    }
    Write-JsonFile -Path $fastApiManifestPath -Value $fastApiManifest

    $fastApiRecord = [ordered]@{
        rank = [int]$fastApiSelected.rank
        repository = "fastapi/fastapi"
        directory = $fastApiCandidateDir
        manifest = $fastApiManifestPath
        selected_contract = $fastApiRecordPath
        status = "candidate_packet_blocked_until_template_live_airgapped_validation"
        promotion_state = "blocked"
        readiness_state = "qaaS_candidate_authored_from_selected_contract"
        artifact_count = $fastApiArtifacts.Count
    }
    $records += $fastApiRecord
}

$ginRecordPath = Join-Path $SelectedContractsDir "138-gin-gonic-gin\selected-contract.json"
if (Test-Path -LiteralPath $ginRecordPath -PathType Leaf) {
    $ginSelected = Get-Content -LiteralPath $ginRecordPath -Raw | ConvertFrom-Json
    if ([string]$ginSelected.repository -ne "gin-gonic/gin") {
        throw "Expected gin-gonic/gin selected contract, got $($ginSelected.repository)"
    }
    if ([string]$ginSelected.status -ne "contract_content_harvested_not_executable" -or [string]$ginSelected.promotion_state -ne "blocked") {
        throw "Selected Gin contract must be harvested and blocked: $ginRecordPath"
    }

    $ginSelectedPublicContracts = @($ginSelected.selected_public_contracts)
    $ginReadmeRecord = $ginSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "README.md" } | Select-Object -First 1
    if ($null -eq $ginReadmeRecord) {
        throw "Selected Gin contract lacks README.md evidence."
    }
    $ginReadmePath = Assert-UnderRoot -Path ([string]$ginReadmeRecord.local_path) -Root $SelectedContractsDir -Description "Gin README evidence"
    $ginReadmeText = Get-Content -LiteralPath $ginReadmePath -Raw
    $requiredGinReadmeMarkers = @(
        'Gin requires',
        'Go''s module support',
        'import "github.com/gin-gonic/gin"',
        'r := gin.Default()',
        'r.GET("/ping", func(c *gin.Context) {',
        'c.JSON(http.StatusOK, gin.H{',
        '"message": "pong"',
        'if err := r.Run(); err != nil {',
        'go run main.go',
        'http://localhost:8080/ping',
        '{"message":"pong"}'
    )
    foreach ($marker in $requiredGinReadmeMarkers) {
        if (-not $ginReadmeText.Contains($marker)) {
            throw "Gin README evidence missing marker '$marker': $ginReadmePath"
        }
    }

    $ginSafeRepo = "{0:D3}-{1}" -f [int]$ginSelected.rank, (New-SafeName ([string]$ginSelected.repository).Replace("/", "-"))
    $ginCandidateDir = Join-Path $resolvedOutDir $ginSafeRepo
    $ginAppDir = Join-Path $ginCandidateDir "app"
    $ginSchemasDir = Join-Path $ginCandidateDir "schemas"
    $ginRequestPayloadsDir = Join-Path $ginCandidateDir "request-payloads"
    foreach ($dir in @($ginCandidateDir, $ginAppDir, $ginSchemasDir, $ginRequestPayloadsDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $ginRunnerPath = Join-Path $ginCandidateDir "test.qaas.yaml"
    $ginAppPath = Join-Path $ginAppDir "main.go"
    $ginSchemaPath = Join-Path $ginSchemasDir "ping-response.schema.json"
    $ginRequestPayloadPath = Join-Path $ginRequestPayloadsDir "get-ping.bin"
    $ginRuntimePlanPath = Join-Path $ginCandidateDir "candidate-runtime-plan.json"
    $ginManifestPath = Join-Path $ginCandidateDir "qaas-artifact-manifest.json"

    Write-TextFile -Path $ginRunnerPath -Value (New-GinRunnerYaml)
    Write-TextFile -Path $ginAppPath -Value @'
// Generated from immutable public Gin README evidence.
package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	r.GET("/ping", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"message": "pong",
		})
	})

	if err := r.Run(); err != nil {
		log.Fatalf("failed to run server: %v", err)
	}
}
'@
    Write-TextFile -Path $ginSchemaPath -Value @'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["message"],
  "additionalProperties": false,
  "properties": {
    "message": { "const": "pong" }
  }
}
'@
    [System.IO.File]::WriteAllBytes($ginRequestPayloadPath, [byte[]]::new(0))

    $ginPublicEvidence = @(
        [string]$ginRecordPath
        @($ginSelected.public_evidence)
        @($ginSelectedPublicContracts | ForEach-Object { [string]$_.local_path })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    $ginDocsEvidence = @(
        $docsEvidence
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\configuration\yamlView.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\configuration\tableView.md"
    ) | Select-Object -Unique

    $ginRuntimePlan = [ordered]@{
        schema_version = 1
        repository = "gin-gonic/gin"
        rank = [int]$ginSelected.rank
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        command = "go run main.go"
        working_directory = $ginAppDir
        fixture = $ginAppPath
        expected_listen_url = "http://127.0.0.1:8080"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:8080/ping"
            expected_status = 200
            expected_json = [ordered]@{
                message = "pong"
            }
        }
        cleanup = [ordered]@{
            required = $true
            strategy = "terminate_tracked_process_tree"
            status = "not_validated"
        }
        blockers = @(
            "prove_process_lifecycle_and_cleanup_without assuming private source",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
        public_evidence = $ginPublicEvidence
    }
    Write-JsonFile -Path $ginRuntimePlanPath -Value $ginRuntimePlan

    $ginIntentQuestions = @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "GET /ping from the README Gin app should return HTTP 200 and the exact JSON object with message pong." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may test the wrong route, use localhost inconsistently, or skip the body contract." -HowToOverride "Replace the route and expected output only with exact public repository evidence." -PublicEvidence $ginPublicEvidence)
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "The Runner target is an externally-started Gin HTTP process on 127.0.0.1:8080; QaaS YAML does not start or clean that process." -AnswerSource "public_repo_contract" -RiskIfWrong "Process lifecycle could be incorrectly encoded as undocumented QaaS YAML." -HowToOverride "Provide documented QaaS lifecycle support or keep startup in an external harness plan." -PublicEvidence $ginPublicEvidence)
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "QaaS public docs/schema support HTTP Transactions, FromFileSystem data-source bytes, HttpStatus assertions, OutputDeserialize Json, and ObjectOutputJsonSchema for exact schema-backed JSON body validation." -AnswerSource "public_docs" -RiskIfWrong "The YAML could cite invented body fields or stale assertion names." -HowToOverride "Update docs evidence and rerun the selected candidate checker." -PublicEvidence $ginDocsEvidence)
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Input is a GET request to /ping with an empty body. Outputs are HTTP status 200 and JSON message=pong. Side effects should be read-only for this GET." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may over-assert middleware behavior, headers, logging, or unrelated endpoints." -HowToOverride "Provide public side-effect evidence for any additional assertion." -PublicEvidence $ginPublicEvidence)
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, malformed, retry, and observability cases remain blocked; this candidate covers only one README-backed happy path and cleanup planning." -AnswerSource "blocked" -RiskIfWrong "A weak model may claim broad framework coverage from one happy-path route." -HowToOverride "Add exact public negative-case and observability contracts before expanding assertions." -PublicEvidence $ginPublicEvidence)
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Dependencies are Go 1.25 or later, module resolution for github.com/gin-gonic/gin, main.go in the runtime working directory, and port 8080 availability; those dependencies are identified from public evidence but not live-validated." -AnswerSource "blocked" -RiskIfWrong "The candidate may be promoted where Go, module fetching, port, or fixture placement is not available." -HowToOverride "Provide validated dependency transcripts for the target environment." -PublicEvidence $ginPublicEvidence)
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Static candidate validation can run now. Process lifecycle, module resolution, QaaS template validation, live act/assert execution, cleanup proof, and live weak-model validation are deferred and block promotion." -AnswerSource "blocked" -RiskIfWrong "A weak model may confuse a candidate packet with an executable test." -HowToOverride "Attach passing lifecycle, template, live, cleanup, airgapped, and strong-review evidence." -PublicEvidence $ginPublicEvidence)
    )

    $ginIntentAssumptions = @(
        (New-IntentAssumption -Assumption "The README first application example is the public behavior contract for this candidate." -WhySafe "It contains exact app code, command, URL, route, and response body markers harvested from an immutable Git blob." -RiskIfWrong "The candidate may not match another Gin app or route." -HowToOverride "Replace the selected contract with another immutable public blob." -PublicEvidence $ginPublicEvidence)
        (New-IntentAssumption -Assumption "Process lifecycle belongs to the external harness until QaaS docs prove otherwise." -WhySafe "The public QaaS Runner docs describe HTTP transactions but not starting arbitrary Go processes." -RiskIfWrong "Startup or cleanup may be missed if a future QaaS lifecycle feature exists." -HowToOverride "Provide public QaaS lifecycle docs and update the checker." -PublicEvidence $ginDocsEvidence)
        (New-IntentAssumption -Assumption "JSON body equality is represented by an ObjectOutputJsonSchema side data source rather than invented JsonPath or ExpectedBody fields." -WhySafe "ObjectOutputJsonSchema is documented and can enforce required keys, constants, and additionalProperties false." -RiskIfWrong "If the Runner serializes outputs differently, template/live validation will catch it before promotion." -HowToOverride "Provide passing QaaS template/live evidence or a different documented assertion." -PublicEvidence $ginDocsEvidence)
    )

    $ginArtifacts = @($ginRunnerPath, $ginAppPath, $ginSchemaPath, $ginRequestPayloadPath, $ginRuntimePlanPath, $ginManifestPath)
    $ginCases = @(
        [ordered]@{
            case_id = "gin-read-ping"
            scenario = "Call README-backed Gin GET /ping and assert documented HTTP success and exact JSON response schema."
            artifact_type = "runner-yaml"
            public_evidence = @($ginPublicEvidence + $ginDocsEvidence)
            setup = @("Start Gin externally with the generated main.go using the README command.", "Ensure port 8080 is free.", "Use get-ping.bin as the byte payload driver for the GET transaction.")
            action = @("Run QaaS Runner against test.qaas.yaml after template validation is available.")
            assertions = @("HttpStatus StatusCode 200 for GetPing.", "ObjectOutputJsonSchema requires message=pong and no additional properties.")
            cleanup = @("Terminate the tracked Gin process tree.", "Remove candidate session-data after live validation.")
            blocked_reason = "QaaS template, live act/assert, cleanup, Go module resolution, and live weak-model validation have not passed."
            artifact_paths = @($ginRunnerPath, $ginSchemaPath, $ginRequestPayloadPath)
        },
        [ordered]@{
            case_id = "gin-runtime-plan"
            scenario = "Keep Go process startup and cleanup outside QaaS YAML until public QaaS docs prove lifecycle support."
            artifact_type = "dependency-gate"
            public_evidence = $ginPublicEvidence
            setup = @("Use candidate-runtime-plan.json as an external harness plan only.")
            action = @("Start and stop Gin through a tracked process runner, not through undocumented QaaS YAML fields.")
            assertions = @("Runtime plan remains blocked and never counts as executable promotion evidence by itself.")
            cleanup = @("Tracked process tree termination must be validated before promotion.")
            blocked_reason = "Process lifecycle, module resolution, and cleanup are planned but not validated."
            artifact_paths = @($ginRuntimePlanPath, $ginAppPath)
        },
        [ordered]@{
            case_id = "gin-contract-evidence"
            scenario = "Tie every candidate field to immutable selected public contract evidence and QaaS public docs."
            artifact_type = "documentation"
            public_evidence = @($ginPublicEvidence + $ginDocsEvidence)
            setup = @("Review selected-contract.json, README blob, and QaaS schema docs.")
            action = @("Run selected top-repo candidate checker.")
            assertions = @("Candidate stays blocked until executable evidence exists.", "No undocumented QaaS fields are introduced.")
            cleanup = @("No external resources are created by static candidate validation.")
            blocked_reason = "Static evidence does not prove live behavior."
            artifact_paths = @($ginManifestPath)
        }
    )

    $ginManifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-gin-candidate"
        source_repository = "gin-gonic/gin"
        repository_rank = [int]$ginSelected.rank
        selected_contract = $ginRecordPath
        docs_evidence = $ginDocsEvidence
        public_evidence = $ginPublicEvidence
        intent_questions = $ginIntentQuestions
        intent_assumptions = $ginIntentAssumptions
        artifacts = $ginArtifacts
        artifact_count = $ginArtifacts.Count
        artifact_types = @("runner-yaml", "dependency-gate", "documentation")
        cases = $ginCases
        assertions = @(
            "Candidate Runner YAML uses schema-derived HttpStatus StatusCode/OutputNames.",
            "Candidate body assertion uses documented ObjectOutputJsonSchema with a constant message=pong.",
            "Candidate remains blocked until lifecycle, module resolution, template, live QaaS, cleanup, airgapped, and strong-review evidence pass."
        )
        dependency_gates = @(
            (New-DependencyGate -GateId "selected-public-runtime-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $ginPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "selected-public-input-output-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $ginPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "qaas-docs-yaml-shape" -Kind "runtime" -Required $true -Status "ready" -Evidence $ginDocsEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "go-version-and-module-resolution" -Kind "dependency" -Required $true -Status "blocked" -Evidence $ginPublicEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-gin.ps1" -BlockedReason "Go 1.25+, module support, and github.com/gin-gonic/gin resolution have not been live-validated for the generated fixture.")
            (New-DependencyGate -GateId "go-gin-process-lifecycle" -Kind "dependency" -Required $true -Status "blocked" -Evidence $ginPublicEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-gin.ps1" -BlockedReason "The external Gin process has not been started, tracked, readiness-checked, and cleaned up by the harness.")
            (New-DependencyGate -GateId "cleanup-contract" -Kind "cleanup" -Required $true -Status "blocked" -Evidence $ginPublicEvidence -CheckCommand "" -BlockedReason "Tracked process tree cleanup and session-data cleanup are not live-validated.")
            (New-DependencyGate -GateId "qaas-template" -Kind "qaas-template" -Required $true -Status "blocked" -Evidence $ginDocsEvidence -CheckCommand "" -BlockedReason "QaaS template validation has not run for this candidate.")
            (New-DependencyGate -GateId "qaas-live-act-assert" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence $ginDocsEvidence -CheckCommand "" -BlockedReason "Live QaaS run/act/assert has not run against a tracked Gin process.")
            (New-DependencyGate -GateId "airgapped-validation" -Kind "airgapped" -Required $true -Status "blocked" -Evidence @() -CheckCommand "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none" -BlockedReason "Live weak-model validation has not passed.")
        )
        promotion_requirements = [ordered]@{
            current_state = "blocked"
            target_state = "executable_ready"
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
        cleanup = @("No live cleanup was performed during static candidate generation.")
        validation_sequence = @(
            "Validate selected immutable public contract evidence.",
            "Validate QaaS public docs/schema fields.",
            "Run selected top-repo candidate checker.",
            "Run Go dependency and process lifecycle validation when a safe runtime harness is available.",
            "Run QaaS template validation when a Runner host is available.",
            "Run live QaaS act/assert against tracked Gin process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_candidate"
            dry_run = $false
        }
        source_only_blockers = @(
            (New-SourceOnlyBlocker -BlockerId "gin-process-lifecycle-not-proven" -BlockerType "repository_contract" -Description "The README command is public evidence for a candidate command, but Go module resolution, process startup, readiness, and cleanup have not been executed and verified." -RequiredEvidence @("Go version transcript", "Module resolution transcript", "Tracked process start transcript", "Readiness probe transcript", "Tracked process cleanup transcript") -PublicEvidence $ginPublicEvidence -UnblockInstruction "Run an external Gin lifecycle harness and attach the transcripts before promotion.")
            (New-SourceOnlyBlocker -BlockerId "qaas-template-live-not-run" -BlockerType "qaas_docs_contract" -Description "The Runner YAML is schema-derived but has not passed QaaS template or live act/assert validation." -RequiredEvidence @("QaaS template validation transcript", "Live QaaS run/act/assert transcript") -PublicEvidence $ginDocsEvidence -UnblockInstruction "Run documented QaaS validation commands in an environment with Runner host and Gin process.")
            (New-SourceOnlyBlocker -BlockerId "live-airgapped-weak-model-not-passed" -BlockerType "source_boundary" -Description "Live weak-model validation has not passed for this candidate packet." -RequiredEvidence @("Airgapped transcript with dry_run false and expected output contract preserved") -PublicEvidence @((Join-Path "D:\QaaS\_tools\zappa-harness" "references\airgapped-validation.md")) -UnblockInstruction "Run D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none when quota/routing is available.")
            (New-SourceOnlyBlocker -BlockerId "httpstatus-docs-inconsistency-recorded" -BlockerType "qaas_docs_contract" -Description "The quick-start example uses stale HttpStatus field names, while generated schema docs require StatusCode and OutputNames." -RequiredEvidence @("Runtime/template validation confirming schema-derived field names") -PublicEvidence $ginDocsEvidence -UnblockInstruction "Keep schema-derived StatusCode/OutputNames unless public docs/schema are updated and revalidated.")
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Selected public contracts support a concrete Gin candidate packet, but executable promotion is blocked until Go module resolution, process lifecycle, QaaS template/live, cleanup, airgapped, and strong-review evidence pass."
    }
    Write-JsonFile -Path $ginManifestPath -Value $ginManifest

    $ginRecord = [ordered]@{
        rank = [int]$ginSelected.rank
        repository = "gin-gonic/gin"
        directory = $ginCandidateDir
        manifest = $ginManifestPath
        selected_contract = $ginRecordPath
        status = "candidate_packet_blocked_until_template_live_airgapped_validation"
        promotion_state = "blocked"
        readiness_state = "qaaS_candidate_authored_from_selected_contract"
        artifact_count = $ginArtifacts.Count
    }
    $records += $ginRecord
}

$denoRecordPath = Join-Path $SelectedContractsDir "098-denoland-deno\selected-contract.json"
if (Test-Path -LiteralPath $denoRecordPath -PathType Leaf) {
    $denoSelected = Get-Content -LiteralPath $denoRecordPath -Raw | ConvertFrom-Json
    if ([string]$denoSelected.repository -ne "denoland/deno") {
        throw "Expected denoland/deno selected contract, got $($denoSelected.repository)"
    }
    if ([string]$denoSelected.status -ne "contract_content_harvested_not_executable" -or [string]$denoSelected.promotion_state -ne "blocked") {
        throw "Selected Deno contract must be harvested and blocked: $denoRecordPath"
    }

    $denoSelectedPublicContracts = @($denoSelected.selected_public_contracts)
    $denoReadmeRecord = $denoSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "README.md" } | Select-Object -First 1
    if ($null -eq $denoReadmeRecord) {
        throw "Selected Deno contract lacks README.md evidence."
    }
    $denoReadmePath = Assert-UnderRoot -Path ([string]$denoReadmeRecord.local_path) -Root $SelectedContractsDir -Description "Deno README evidence"
    $denoReadmeText = Get-Content -LiteralPath $denoReadmePath -Raw
    $requiredDenoReadmeMarkers = @(
        "server.ts",
        "Deno.serve((_req: Request) => {",
        'return new Response("Hello, world!");',
        "deno run --allow-net server.ts",
        "http://localhost:8000"
    )
    foreach ($marker in $requiredDenoReadmeMarkers) {
        if (-not $denoReadmeText.Contains($marker)) {
            throw "Deno README evidence missing marker '$marker': $denoReadmePath"
        }
    }

    $denoSafeRepo = "{0:D3}-{1}" -f [int]$denoSelected.rank, (New-SafeName ([string]$denoSelected.repository).Replace("/", "-"))
    $denoCandidateDir = Join-Path $resolvedOutDir $denoSafeRepo
    $denoAppDir = Join-Path $denoCandidateDir "app"
    $denoExpectationsDir = Join-Path $denoCandidateDir "expectations"
    $denoRequestPayloadsDir = Join-Path $denoCandidateDir "request-payloads"
    $denoHookDir = Join-Path $denoCandidateDir "assertion-packets\ExactHttpTextBody"
    foreach ($dir in @($denoCandidateDir, $denoAppDir, $denoExpectationsDir, $denoRequestPayloadsDir, $denoHookDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $denoRunnerPath = Join-Path $denoCandidateDir "test.qaas.yaml"
    $denoServerPath = Join-Path $denoAppDir "server.ts"
    $denoExpectedBodyPath = Join-Path $denoExpectationsDir "root-body.txt"
    $denoRequestPayloadPath = Join-Path $denoRequestPayloadsDir "get-root.bin"
    $denoRuntimePlanPath = Join-Path $denoCandidateDir "candidate-runtime-plan.json"
    $denoManifestPath = Join-Path $denoCandidateDir "qaas-artifact-manifest.json"
    $denoHookCodePath = Join-Path $denoHookDir "ExactHttpTextBody.cs"
    $denoHookUsagePath = Join-Path $denoHookDir "ExactHttpTextBody.usage.yaml.txt"
    $denoHookPlanPath = Join-Path $denoHookDir "custom-text-body-hook-plan.json"

    Write-TextFile -Path $denoRunnerPath -Value (New-DenoRunnerYaml)
    Write-TextFile -Path $denoServerPath -Value @'
// Generated from immutable public Deno README evidence.
Deno.serve((_req: Request) => {
  return new Response("Hello, world!");
});
'@
    Write-TextFile -Path $denoExpectedBodyPath -Value "Hello, world!"
    [System.IO.File]::WriteAllBytes($denoRequestPayloadPath, [byte[]]::new(0))
    Write-TextFile -Path $denoHookCodePath -Value (New-DenoExactTextBodyAssertionCode)
    Write-TextFile -Path $denoHookUsagePath -Value (New-DenoExactTextBodyUsageSnippet)

    $denoHookDocsEvidence = @(
        "D:\QaaS\qaas-docs\docs\assertions\index.md",
        "D:\QaaS\qaas-docs\docs\assertions\custom-authoring-guide.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputContentByExpectedCsvResults\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\OutputDeserializableTo\overview.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\ObjectOutputJsonSchema\overview.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\schema-extensions.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $denoDocsEvidence = @($docsEvidence + $denoHookDocsEvidence) | Select-Object -Unique
    $denoExpectedBodySha256 = Get-Sha256Hex -Path $denoExpectedBodyPath
    $denoHookBuiltins = @(
        [ordered]@{ name = "HttpStatus"; reason_insufficient = "Status-only assertion; does not compare response body bytes." },
        [ordered]@{ name = "OutputContentByExpectedCsvResults"; reason_insufficient = "JSON/CSV field mapping assertion; not exact raw/plain-text body equality." },
        [ordered]@{ name = "OutputDeserializableTo"; reason_insufficient = "Checks deserialization success, not equality with exact public README text." },
        [ordered]@{ name = "ObjectOutputJsonSchema"; reason_insufficient = "Checks JSON schema compatibility, not exact raw/plain-text body equality." }
    )

    $denoPublicEvidence = @(
        [string]$denoRecordPath
        @($denoSelected.public_evidence)
        @($denoSelectedPublicContracts | ForEach-Object { [string]$_.local_path })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $denoCustomAssertionPacket = [ordered]@{
        packet_id = "deno-exact-http-text-body"
        assertion_name = "ExactHttpTextBody"
        status = "blocked_until_build_template_live_airgapped_validation"
        promotion_state = "blocked"
        activation = "sidecar_only"
        wired_into_runner_yaml = $false
        source_files = @($denoHookCodePath)
        yaml_fragment = $denoHookUsagePath
        hook_plan = $denoHookPlanPath
        expected_body_path = $denoExpectedBodyPath
        expected_body_sha256 = $denoExpectedBodySha256
        encoding = "utf-8"
        comparison = "byte_for_byte"
        normalization = "none"
        case_sensitive = $true
        trim = $false
        contains = $false
        docs_evidence = $denoHookDocsEvidence
        public_evidence = $denoPublicEvidence
        validation_records = [ordered]@{
            build = "not_run"
            schema = "not_run"
            template = "not_run"
            live = "not_run"
            airgapped = "not_run"
        }
        weak_validation_passed = $false
    }

    $denoHookPlan = [ordered]@{
        schema_version = 1
        status = "authored_from_public_docs_not_template_validated"
        hook_family = "assertion"
        assertion_type = "ExactHttpTextBody"
        configuration_contract = [ordered]@{
            OutputName = "Required transaction output name, backed by custom assertion docs and the Deno transaction name GetRoot."
            ExpectedText = "Required exact expected text, backed by Deno README output evidence."
            EncodingName = "Optional text encoding name; defaults to utf-8."
        }
        builtins_considered = $denoHookBuiltins
        docs_evidence = $denoHookDocsEvidence
        files = [ordered]@{
            implementation = $denoHookCodePath
            usage_snippet = $denoHookUsagePath
        }
        validation_sequence = @(
            "Reference the assertion assembly from the Runner host project.",
            "Regenerate Runner schema and clean bin cache so Assertion: ExactHttpTextBody is discoverable.",
            "Run Runner template validation against the Deno candidate YAML with the assertion enabled.",
            "Run live QaaS act/assert against a tracked Deno process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        custom_assertion_packet = $denoCustomAssertionPacket
        promotion_state = "blocked"
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $denoHookPlanPath -Value $denoHookPlan

    $denoRuntimePlan = [ordered]@{
        schema_version = 1
        repository = "denoland/deno"
        rank = [int]$denoSelected.rank
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        public_command = "deno run --allow-net server.ts"
        command = "deno run --allow-net server.ts"
        managed_toolchain = [ordered]@{
            required = $true
            source = "official_deno_github_release_asset"
            release_tag = "v2.8.2"
            download_url = "https://github.com/denoland/deno/releases/download/v2.8.2/deno-x86_64-pc-windows-msvc.zip"
            archive_sha256 = "6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9"
            binary = "deno.exe"
            status = "not_validated"
        }
        working_directory = $denoAppDir
        fixture = $denoServerPath
        expected_listen_url = "http://127.0.0.1:8000/"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:8000/"
            expected_status = 200
            expected_body = "Hello, world!"
        }
        cleanup = [ordered]@{
            required = $true
            strategy = "terminate_tracked_process_tree"
            status = "not_validated"
        }
        out_of_scope = @(
            "Deno CLI behavior beyond the README HTTP example",
            "Rust runtime internals",
            "repository schemas and CI behavior not used by this candidate"
        )
        blockers = @(
            "prove_managed_deno_toolchain_without_using_ambient_path",
            "prove_process_lifecycle_and_cleanup_without assuming private source",
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            assertion_type = "ExactHttpTextBody"
            implementation = $denoHookCodePath
            usage_snippet = $denoHookUsagePath
            hook_plan = $denoHookPlanPath
            validation_status = "not_template_validated"
        }
        custom_assertion_packets = @($denoCustomAssertionPacket)
        public_evidence = $denoPublicEvidence
    }
    Write-JsonFile -Path $denoRuntimePlanPath -Value $denoRuntimePlan

    $denoIntentQuestions = @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "GET / from the README Deno server should return HTTP success and the exact body Hello, world!." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may test CLI internals, another route, or a generated server not present in README evidence." -HowToOverride "Replace the route and body only with exact public repository evidence." -PublicEvidence $denoPublicEvidence)
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "The Runner target is an externally-started Deno HTTP process on 127.0.0.1:8000; QaaS YAML does not start or clean that process." -AnswerSource "public_repo_contract" -RiskIfWrong "Process lifecycle could be incorrectly encoded as undocumented QaaS YAML." -HowToOverride "Provide documented QaaS lifecycle support or keep startup in an external harness plan." -PublicEvidence $denoPublicEvidence)
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "QaaS public docs/schema support HTTP Transactions, FromFileSystem data-source payload bytes, HttpStatus assertions, and custom assertions by short type name; the ExactHttpTextBody hook is authored but not schema/template/live validated." -AnswerSource "public_docs" -RiskIfWrong "A weak model may invent a built-in text body assertion or treat sidecar hook code as executable validation." -HowToOverride "Provide template/build/live validation for the custom assertion packet." -PublicEvidence $denoDocsEvidence)
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Input is a GET request to /. Outputs are HTTP success and body Hello, world!. Side effects should be read-only for this GET." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may over-assert runtime internals, filesystem changes, permissions, or unrelated endpoints." -HowToOverride "Provide exact public side-effect evidence for any additional assertion." -PublicEvidence $denoPublicEvidence)
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, malformed, retry, and observability cases remain blocked; this candidate covers only one README-backed happy path plus external cleanup planning." -AnswerSource "blocked" -RiskIfWrong "A weak model may claim broad Deno runtime or permission coverage from one README server example." -HowToOverride "Add exact public negative-case and observability contracts before expanding assertions." -PublicEvidence $denoPublicEvidence)
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "A managed Deno release binary must be downloaded from the official release asset, hash-verified, launched by absolute path, and given a run-local DENO_DIR; port 8000 must be free." -AnswerSource "blocked" -RiskIfWrong "A weak model may trust an ambient deno.exe, mutate user PATH, or miss port cleanup requirements." -HowToOverride "Attach managed toolchain and lifecycle transcripts." -PublicEvidence $denoPublicEvidence)
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Static candidate validation and managed process lifecycle validation can run now. Custom assertion build/schema/template validation, live QaaS act/assert execution, cleanup promotion evidence, and live weak-model validation remain deferred until their evidence exists." -AnswerSource "blocked" -RiskIfWrong "A weak model may confuse a candidate packet or lifecycle-only proof with an executable QaaS test." -HowToOverride "Attach passing lifecycle, custom assertion build/schema/template, live, cleanup, airgapped, and strong-review evidence." -PublicEvidence $denoPublicEvidence)
    )
    $denoIntentAssumptions = @(
        (New-IntentAssumption -Assumption "The README server.ts example is the only public behavior contract promoted by this candidate." -WhySafe "It contains exact server code, command, URL, and response body markers harvested from an immutable Git blob." -RiskIfWrong "The candidate may be mistaken for broad Deno runtime coverage." -HowToOverride "Harvest exact public evidence for additional behavior before adding assertions." -PublicEvidence $denoPublicEvidence)
        (New-IntentAssumption -Assumption "HTTP 200 is a live lifecycle/QaaS observation, while the exact body comes from README evidence." -WhySafe "The README does not literally state status 200, so status success must be proven by execution." -RiskIfWrong "A weak model may overstate source-derived evidence." -HowToOverride "Attach public Deno/Fetch docs or keep status as live evidence." -PublicEvidence $denoPublicEvidence)
    )

    $denoArtifacts = @($denoRunnerPath, $denoServerPath, $denoExpectedBodyPath, $denoRequestPayloadPath, $denoRuntimePlanPath, $denoManifestPath)
    $denoManifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-deno-candidate"
        source_repository = "denoland/deno"
        repository_rank = [int]$denoSelected.rank
        selected_contract = $denoRecordPath
        docs_evidence = $denoDocsEvidence
        public_evidence = $denoPublicEvidence
        intent_questions = $denoIntentQuestions
        intent_assumptions = $denoIntentAssumptions
        artifacts = $denoArtifacts
        artifact_count = $denoArtifacts.Count
        artifact_types = @("runner-yaml", "dependency-gate", "documentation", "hook")
        cases = @(
            [ordered]@{
                case_id = "deno-read-root"
                scenario = "Call README-backed Deno GET / and assert HTTP success while the sidecar exact text-body assertion remains build/schema/template/live blocked."
                artifact_type = "runner-yaml"
                public_evidence = $denoPublicEvidence
                setup = @("Use the managed Deno binary and generated README server.ts.", "Ensure port 8000 is free.", "Use get-root.bin as the byte payload driver for the GET transaction.")
                action = @("Run QaaS Runner against test.qaas.yaml after template validation is available.")
                assertions = @("HttpStatus StatusCode 200 for GetRoot after live execution.", "Exact body Hello, world! is preserved as expected-response evidence but blocked from YAML until the custom assertion is validated.")
                cleanup = @("Terminate the tracked Deno process tree.", "Remove candidate session-data after live validation.")
                blocked_reason = "Managed toolchain, lifecycle, QaaS template/live, exact plain-text body assertion build/schema/template validation, cleanup, and live weak-model validation have not passed."
                artifact_paths = @($denoRunnerPath, $denoRequestPayloadPath, $denoExpectedBodyPath)
            }
        )
        assertions = @(
            "Candidate Runner YAML uses schema-derived HttpStatus StatusCode/OutputNames.",
            "Candidate preserves README-backed plain-text body evidence and includes a sidecar ExactHttpTextBody custom assertion packet that is not wired into active YAML before validation.",
            "Candidate remains blocked until managed toolchain, lifecycle, template, live QaaS, cleanup, airgapped, and strong-review evidence pass."
        )
        custom_text_body_assertion = [ordered]@{
            status = "authored_from_public_docs_not_template_validated"
            hook_family = "assertion"
            assertion_type = "ExactHttpTextBody"
            implementation = $denoHookCodePath
            usage_snippet = $denoHookUsagePath
            hook_plan = $denoHookPlanPath
            configuration_contract = [ordered]@{
                OutputName = "Required transaction output name to inspect."
                ExpectedText = "Required exact expected response body text."
                EncodingName = "Optional encoding name; defaults to utf-8."
            }
            builtins_considered = $denoHookBuiltins
            docs_evidence = $denoHookDocsEvidence
            validation_status = "not_template_validated"
            weak_validation_passed = $false
        }
        custom_assertion_packets = @($denoCustomAssertionPacket)
        dependency_gates = @(
            (New-DependencyGate -GateId "selected-public-runtime-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $denoPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "selected-public-input-output-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $denoPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "qaas-docs-yaml-shape" -Kind "runtime" -Required $true -Status "ready" -Evidence $denoDocsEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "managed-deno-toolchain" -Kind "dependency" -Required $true -Status "blocked" -Evidence $denoPublicEvidence -CheckCommand "" -BlockedReason "The managed Deno release asset has not been downloaded, hash-verified, and version-checked by the harness.")
            (New-DependencyGate -GateId "deno-process-lifecycle" -Kind "dependency" -Required $true -Status "blocked" -Evidence $denoPublicEvidence -CheckCommand "" -BlockedReason "The external Deno process has not been started, tracked, readiness-checked, and cleaned up by the harness.")
            (New-DependencyGate -GateId "plain-text-body-assertion-or-hook" -Kind "qaas-build" -Required $true -Status "ready" -Evidence @($denoHookDocsEvidence + @($denoHookCodePath, $denoHookUsagePath, $denoHookPlanPath, $denoExpectedBodyPath)) -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "cleanup-contract" -Kind "cleanup" -Required $true -Status "blocked" -Evidence $denoPublicEvidence -CheckCommand "" -BlockedReason "Tracked process tree cleanup and session-data cleanup are not live-validated.")
            (New-DependencyGate -GateId "qaas-template" -Kind "qaas-template" -Required $true -Status "blocked" -Evidence $denoDocsEvidence -CheckCommand "" -BlockedReason "QaaS template validation has not run for this candidate.")
            (New-DependencyGate -GateId "qaas-live-act-assert" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence $denoDocsEvidence -CheckCommand "" -BlockedReason "Live QaaS run/act/assert has not run against a tracked Deno process.")
            (New-DependencyGate -GateId "airgapped-validation" -Kind "airgapped" -Required $true -Status "blocked" -Evidence @() -CheckCommand "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none" -BlockedReason "Live weak-model validation has not passed.")
        )
        promotion_requirements = [ordered]@{
            current_state = "blocked"
            target_state = "executable_ready"
            required_evidence = @(
                "Public API, CLI, or runtime contract",
                "Public input and expected-output contract",
                "Public dependency/stub contract",
                "Cleanup contract",
                "Public README server.ts command and exact expected body",
                "Managed Deno release asset download, hash, and version transcript",
                "Tracked process start/readiness/cleanup transcript",
                "Documented QaaS body assertion or custom hook for plain text",
                "QaaS template validation result",
                "C# build result when code artifacts exist",
                "Live QaaS run/act/assert result when dependency gates are ready",
                "Airgapped weak-model validation transcript"
            )
        }
        cleanup = @("No live cleanup was performed during static candidate generation.")
        validation_sequence = @(
            "Validate selected immutable public contract evidence.",
            "Validate managed Deno toolchain source and SHA.",
            "Validate QaaS public docs/schema fields.",
            "Run selected top-repo candidate checker.",
            "Build and schema/template-validate the sidecar ExactHttpTextBody custom assertion before executable promotion.",
            "Run QaaS template validation when a Runner host is available.",
            "Run live QaaS act/assert against tracked Deno process.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_candidate"
            dry_run = $false
        }
        source_only_blockers = @(
            (New-SourceOnlyBlocker -BlockerId "deno-toolchain-not-proven" -BlockerType "repository_contract" -Description "Deno is not assumed from ambient PATH; the official release asset must be downloaded, hash-verified, extracted, and version-checked by the harness." -RequiredEvidence @("Official release metadata", "Archive SHA-256 transcript", "deno --version transcript", "Absolute managed deno.exe path") -PublicEvidence $denoPublicEvidence -UnblockInstruction "Run the managed Deno lifecycle harness and attach the toolchain transcript.")
            (New-SourceOnlyBlocker -BlockerId "deno-process-lifecycle-not-proven" -BlockerType "repository_contract" -Description "The README command is public evidence for a candidate command, but process startup, readiness, and cleanup have not been executed and verified." -RequiredEvidence @("Tracked process start transcript", "Readiness probe transcript", "Tracked process cleanup transcript") -PublicEvidence $denoPublicEvidence -UnblockInstruction "Run an external Deno lifecycle harness and attach the transcripts before promotion.")
            (New-SourceOnlyBlocker -BlockerId "deno-text-body-hook-not-template-validated" -BlockerType "qaas_docs_contract" -Description "A docs-derived ExactHttpTextBody custom assertion has been authored, but Runner assembly discovery, schema regeneration, template validation, build validation, and live QaaS act/assert have not passed." -RequiredEvidence @("Runner host project references the assertion assembly", "Regenerated Runner schema includes Assertion: ExactHttpTextBody", "Template validation transcript for the Deno candidate with the custom assertion enabled", "Live QaaS act/assert transcript against a tracked Deno process") -PublicEvidence @($denoHookDocsEvidence + @($denoHookCodePath, $denoHookUsagePath, $denoHookPlanPath, $denoExpectedBodyPath)) -UnblockInstruction "Reference the assertion assembly, regenerate schema/clean bin, run QaaS template validation, then run live QaaS act/assert before promotion.")
            (New-SourceOnlyBlocker -BlockerId "deno-broad-runtime-coverage-not-selected" -BlockerType "source_boundary" -Description "The selected evidence only supports the README HTTP hello-world behavior, not broad Deno CLI, Rust runtime, schema, permission, or CI behavior." -RequiredEvidence @("Exact public contracts for each additional behavior") -PublicEvidence $denoPublicEvidence -UnblockInstruction "Do not add broad Deno assertions until deterministic public evidence is harvested.")
            (New-SourceOnlyBlocker -BlockerId "qaas-template-live-not-run" -BlockerType "qaas_docs_contract" -Description "The Runner YAML is schema-derived but has not passed QaaS template or live act/assert validation." -RequiredEvidence @("QaaS template validation transcript", "Live QaaS run/act/assert transcript") -PublicEvidence $denoDocsEvidence -UnblockInstruction "Run documented QaaS validation commands in an environment with Runner host and Deno process.")
            (New-SourceOnlyBlocker -BlockerId "live-airgapped-weak-model-not-passed" -BlockerType "source_boundary" -Description "Live weak-model validation has not passed for this candidate packet." -RequiredEvidence @("Airgapped transcript with dry_run false and expected output contract preserved") -PublicEvidence @((Join-Path "D:\QaaS\_tools\zappa-harness" "references\airgapped-validation.md")) -UnblockInstruction "Run D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none when quota/routing is available.")
            (New-SourceOnlyBlocker -BlockerId "httpstatus-docs-inconsistency-recorded" -BlockerType "qaas_docs_contract" -Description "The quick-start example uses stale HttpStatus field names, while generated schema docs require StatusCode and OutputNames." -RequiredEvidence @("Runtime/template validation confirming schema-derived field names") -PublicEvidence $denoDocsEvidence -UnblockInstruction "Keep schema-derived StatusCode/OutputNames unless public docs/schema are updated and revalidated.")
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Selected public contracts support a concrete Deno README server candidate and a docs-derived exact text-body assertion hook, but executable promotion is blocked until managed toolchain, process lifecycle, hook schema/template/build/live, QaaS live, cleanup, airgapped, and strong-review evidence pass."
    }
    Write-JsonFile -Path $denoManifestPath -Value $denoManifest

    $denoRecord = [ordered]@{
        rank = [int]$denoSelected.rank
        repository = "denoland/deno"
        directory = $denoCandidateDir
        manifest = $denoManifestPath
        selected_contract = $denoRecordPath
        status = "candidate_packet_blocked_until_template_live_airgapped_validation"
        promotion_state = "blocked"
        readiness_state = "qaaS_candidate_authored_from_selected_contract"
        artifact_count = $denoArtifacts.Count
    }
    $records += $denoRecord
}

$crawlRecordPath = Join-Path $SelectedContractsDir "250-unclecode-crawl4ai\selected-contract.json"
if (Test-Path -LiteralPath $crawlRecordPath -PathType Leaf) {
    $crawlSelected = Get-Content -LiteralPath $crawlRecordPath -Raw | ConvertFrom-Json
    if ([string]$crawlSelected.repository -ne "unclecode/crawl4ai") {
        throw "Expected unclecode/crawl4ai selected contract, got $($crawlSelected.repository)"
    }
    if ([string]$crawlSelected.status -ne "contract_content_harvested_not_executable" -or [string]$crawlSelected.promotion_state -ne "blocked") {
        throw "Selected Crawl4AI contract must be harvested and blocked: $crawlRecordPath"
    }

    $crawlSelectedPublicContracts = @($crawlSelected.selected_public_contracts)
    $crawlReadmeRecord = $crawlSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "README.md" } | Select-Object -First 1
    $crawlDockerfileRecord = $crawlSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "Dockerfile" } | Select-Object -First 1
    $crawlComposeRecord = $crawlSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "docker-compose.yml" } | Select-Object -First 1
    $crawlSchemasRecord = $crawlSelectedPublicContracts | Where-Object { [string]$_.source_path -eq "deploy/docker/schemas.py" } | Select-Object -First 1
    foreach ($requiredRecord in @($crawlReadmeRecord, $crawlDockerfileRecord, $crawlComposeRecord, $crawlSchemasRecord)) {
        if ($null -eq $requiredRecord) {
            throw "Selected Crawl4AI contract lacks required README/Dockerfile/docker-compose/schemas evidence."
        }
    }

    $crawlReadmePath = Assert-UnderRoot -Path ([string]$crawlReadmeRecord.local_path) -Root $SelectedContractsDir -Description "Crawl4AI README evidence"
    $crawlDockerfilePath = Assert-UnderRoot -Path ([string]$crawlDockerfileRecord.local_path) -Root $SelectedContractsDir -Description "Crawl4AI Dockerfile evidence"
    $crawlComposePath = Assert-UnderRoot -Path ([string]$crawlComposeRecord.local_path) -Root $SelectedContractsDir -Description "Crawl4AI docker-compose evidence"
    $crawlSchemasPath = Assert-UnderRoot -Path ([string]$crawlSchemasRecord.local_path) -Root $SelectedContractsDir -Description "Crawl4AI schema evidence"
    $crawlReadmeText = Get-Content -LiteralPath $crawlReadmePath -Raw
    $crawlDockerfileText = Get-Content -LiteralPath $crawlDockerfilePath -Raw
    $crawlComposeText = Get-Content -LiteralPath $crawlComposePath -Raw
    $crawlSchemasText = Get-Content -LiteralPath $crawlSchemasPath -Raw

    foreach ($marker in @(
        "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest",
        "http://localhost:11235/crawl",
        'if "results" in response.json():',
        'task_id = response.json()["task_id"]',
        'result = requests.get(f"http://localhost:11235/task/{task_id}")'
    )) {
        if (-not $crawlReadmeText.Contains($marker)) {
            throw "Crawl4AI README evidence missing marker '$marker': $crawlReadmePath"
        }
    }
    foreach ($marker in @("curl -f http://localhost:11235/health || exit 1", "redis-cli ping", "[ `$MEM -lt 2048 ]")) {
        if (-not $crawlDockerfileText.Contains($marker)) {
            throw "Crawl4AI Dockerfile evidence missing marker '$marker': $crawlDockerfilePath"
        }
    }
    foreach ($marker in @('test: ["CMD", "curl", "-f", "http://localhost:11235/health"]', "memory: 4G", "memory: 1G", "/dev/shm:/dev/shm")) {
        if (-not $crawlComposeText.Contains($marker)) {
            throw "Crawl4AI docker-compose evidence missing marker '$marker': $crawlComposePath"
        }
    }
    foreach ($marker in @("class CrawlRequest(BaseModel):", "urls: List[str] = Field(min_length=1, max_length=100)")) {
        if (-not $crawlSchemasText.Contains($marker)) {
            throw "Crawl4AI schemas evidence missing marker '$marker': $crawlSchemasPath"
        }
    }

    $crawlSafeRepo = "{0:D3}-{1}" -f [int]$crawlSelected.rank, (New-SafeName ([string]$crawlSelected.repository).Replace("/", "-"))
    $crawlCandidateDir = Join-Path $resolvedOutDir $crawlSafeRepo
    $crawlRequestPayloadsDir = Join-Path $crawlCandidateDir "request-payloads"
    $crawlHookDir = Join-Path $crawlCandidateDir "assertion-packets\HttpStatusBelow400"
    foreach ($dir in @($crawlCandidateDir, $crawlRequestPayloadsDir, $crawlHookDir)) {
        [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    }

    $crawlRunnerPath = Join-Path $crawlCandidateDir "test.qaas.yaml"
    $crawlRequestPayloadPath = Join-Path $crawlRequestPayloadsDir "get-health.bin"
    $crawlRuntimePlanPath = Join-Path $crawlCandidateDir "candidate-runtime-plan.json"
    $crawlManifestPath = Join-Path $crawlCandidateDir "qaas-artifact-manifest.json"
    $crawlHookCodePath = Join-Path $crawlHookDir "HttpStatusBelow400.cs"
    $crawlHookUsagePath = Join-Path $crawlHookDir "HttpStatusBelow400.usage.yaml.txt"
    $crawlHookPlanPath = Join-Path $crawlHookDir "custom-status-hook-plan.json"

    Write-TextFile -Path $crawlRunnerPath -Value (New-Crawl4AiRunnerYaml)
    [System.IO.File]::WriteAllBytes($crawlRequestPayloadPath, [byte[]]::new(0))
    Write-TextFile -Path $crawlHookCodePath -Value (New-Crawl4AiHttpStatusBelow400AssertionCode)
    Write-TextFile -Path $crawlHookUsagePath -Value (New-Crawl4AiHttpStatusBelow400UsageSnippet)

    $crawlHookDocsEvidence = @(
        "D:\QaaS\qaas-docs\docs\assertions\index.md",
        "D:\QaaS\qaas-docs\docs\assertions\custom-authoring-guide.md",
        "D:\QaaS\qaas-docs\docs\assertions\availableAssertions\HttpStatus\overview.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\configurationSections\sessions\types\transactions-yamlView.md",
        "D:\QaaS\qaas-docs\docs\qaas\userInterfaces\runner\schema-extensions.md",
        "D:\QaaS\qaas-docs\docs\assets\schemas\runner-family-schema.json"
    )
    $crawlDocsEvidence = @($docsEvidence + $crawlHookDocsEvidence) | Select-Object -Unique
    $crawlPublicEvidence = @(
        [string]$crawlRecordPath
        @($crawlSelected.public_evidence)
        @($crawlSelectedPublicContracts | ForEach-Object { [string]$_.local_path })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $crawlCustomAssertionPacket = [ordered]@{
        packet_id = "crawl4ai-http-status-below-400"
        assertion_name = "HttpStatusBelow400"
        status = "blocked_until_build_template_live_airgapped_validation"
        promotion_state = "blocked"
        activation = "source_yaml_blocked"
        wired_into_runner_yaml = $true
        source_files = @($crawlHookCodePath)
        yaml_fragment = $crawlHookUsagePath
        hook_plan = $crawlHookPlanPath
        output_body_assertion = "unasserted_no_public_body_contract"
        maximum_exclusive_status_code = 400
        comparison = "http_status_less_than"
        docs_evidence = $crawlHookDocsEvidence
        public_evidence = $crawlPublicEvidence
        validation_records = [ordered]@{
            build = "not_run"
            schema = "not_run"
            template = "not_run"
            live = "not_run"
            airgapped = "not_run"
        }
        weak_validation_passed = $false
    }

    $crawlHookPlan = [ordered]@{
        schema_version = 1
        status = "authored_from_public_docs_not_template_validated"
        hook_family = "assertion"
        assertion_type = "HttpStatusBelow400"
        configuration_contract = [ordered]@{
            OutputNames = "Required transaction output names to inspect."
            MaximumExclusiveStatusCode = "Required exclusive upper bound; Docker curl -f maps to 400."
        }
        builtins_considered = @(
            [ordered]@{ name = "HttpStatus"; reason_insufficient = "Checks exact status equality, while Docker curl -f accepts any HTTP status below 400." }
            [ordered]@{ name = "ObjectOutputJsonSchema"; reason_insufficient = "No harvested public response body/schema contract exists for /health." }
            [ordered]@{ name = "OutputContentByExpectedCsvResults"; reason_insufficient = "No harvested public response body/content contract exists for /health." }
        )
        docs_evidence = $crawlHookDocsEvidence
        files = [ordered]@{
            implementation = $crawlHookCodePath
            usage_snippet = $crawlHookUsagePath
        }
        validation_sequence = @(
            "Reference the assertion assembly from the Runner host project.",
            "Regenerate Runner schema and clean bin cache so Assertion: HttpStatusBelow400 is discoverable.",
            "Run Runner template validation against the Crawl4AI healthcheck YAML.",
            "Run live QaaS act/assert against a test-owned Crawl4AI container.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        custom_assertion_packet = $crawlCustomAssertionPacket
        promotion_state = "blocked"
        weak_validation_passed = $false
    }
    Write-JsonFile -Path $crawlHookPlanPath -Value $crawlHookPlan

    $crawlRuntimePlan = [ordered]@{
        schema_version = 1
        repository = "unclecode/crawl4ai"
        rank = [int]$crawlSelected.rank
        status = "candidate_runtime_plan_blocked"
        promotion_state = "blocked"
        lifecycle_owner = "external_harness_not_qaas_yaml"
        command_support = "candidate-executable-command"
        public_command = "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest"
        pull_command = "docker pull unclecode/crawl4ai:latest"
        safe_test_command_template = "docker run -d -p 127.0.0.1:11235:11235 --name zappa-crawl4ai-health-{run_id} --shm-size=1g unclecode/crawl4ai:latest"
        image = "unclecode/crawl4ai:latest"
        container_name_policy = "unique_test_owned_name_required"
        expected_listen_url = "http://127.0.0.1:11235"
        readiness_probe = [ordered]@{
            method = "GET"
            url = "http://127.0.0.1:11235/health"
            expected_status_semantics = "http_status_less_than_400"
            maximum_exclusive_status_code = 400
            expected_body = "unasserted_no_public_body_contract"
        }
        cleanup = [ordered]@{
            required = $true
            strategy = "docker_rm_force_test_owned_unique_container"
            must_not_remove_container_name = "crawl4ai"
            status = "not_validated"
        }
        resource_safety = [ordered]@{
            shm_size = "1g"
            compose_memory_limit = "4G"
            compose_memory_reservation = "1G"
            exposes_redis_port_in_image = 6379
            requires_live_container_safety_plan = $true
        }
        blocked_endpoints = @(
            [ordered]@{
                route = "/crawl"
                reason = "README example branches between synchronous results and task_id polling; no deterministic response body contract is selected."
            }
        )
        blockers = @(
            "prove_docker_lifecycle_and_cleanup_without_deleting_user_container",
            "build_and_template_validate_http_status_below_400_assertion",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
        public_evidence = $crawlPublicEvidence
    }
    Write-JsonFile -Path $crawlRuntimePlanPath -Value $crawlRuntimePlan

    $crawlIntentQuestions = @(
        (New-IntentQuestion -QuestionId "behavior" -Question "What behavior must be proven?" -SelfAnswer "GET /health against the Dockerized Crawl4AI service must satisfy Docker curl -f semantics, meaning the observed HTTP status is below 400. The response body is not asserted." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may invent an exact status/body contract that the selected public evidence does not provide." -HowToOverride "Add exact public /health response status/body evidence and rerun the selected candidate checker." -PublicEvidence $crawlPublicEvidence)
        (New-IntentQuestion -QuestionId "boundary" -Question "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?" -SelfAnswer "The Runner target is an externally-started, test-owned Docker container exposing Crawl4AI on 127.0.0.1:11235. QaaS YAML performs only the HTTP transaction/assertion; the custom status assertion is a Runner hook and Docker lifecycle remains outside QaaS YAML." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may put Docker lifecycle fields into undocumented QaaS YAML or remove a user-owned container." -HowToOverride "Provide documented QaaS lifecycle support or keep Docker lifecycle in the external harness plan." -PublicEvidence $crawlPublicEvidence)
        (New-IntentQuestion -QuestionId "docs_schema_evidence" -Question "What public docs/schema path proves the capability exists?" -SelfAnswer "QaaS public docs/schema support HTTP Transactions, FromFileSystem payload data sources, and custom assertions by short type name; the custom assertion must still pass build/template/live validation." -AnswerSource "public_docs" -RiskIfWrong "The YAML could cite a built-in range status assertion that does not exist." -HowToOverride "Update docs evidence and rerun the selected candidate checker." -PublicEvidence $crawlDocsEvidence)
        (New-IntentQuestion -QuestionId "inputs_outputs_side_effects" -Question "What inputs, outputs, and side effects prove success?" -SelfAnswer "Input is an empty GET request to /health. Output assertion is HTTP status less than 400 only. Body/schema and /crawl behavior are explicitly out of scope." -AnswerSource "public_repo_contract" -RiskIfWrong "A weak model may promote /crawl or response body assertions from non-deterministic README snippets." -HowToOverride "Harvest deterministic public body/schema evidence before adding those assertions." -PublicEvidence $crawlPublicEvidence)
        (New-IntentQuestion -QuestionId "negative_cases" -Question "Which negative, malformed, outage, retry, cleanup, and observability cases matter?" -SelfAnswer "Negative, malformed, outage, retry, and observability cases remain blocked. Cleanup is explicitly required and must remove only a unique test-owned container. This candidate covers only the Docker /health happy path." -AnswerSource "blocked" -RiskIfWrong "A weak model may claim broad Crawl4AI API coverage or safe Docker cleanup from one healthcheck." -HowToOverride "Add exact public negative/observability contracts and live cleanup evidence before expanding assertions." -PublicEvidence $crawlPublicEvidence)
        (New-IntentQuestion -QuestionId "dependencies" -Question "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?" -SelfAnswer "Docker must be available, image pull must succeed, the HTTP endpoint must bind 127.0.0.1:11235 safely, Redis and browser shared memory requirements must be satisfied inside the container, and cleanup must remove only a unique test-owned container." -AnswerSource "blocked" -RiskIfWrong "The candidate may be promoted in an environment where Docker lifecycle is unsafe or unavailable." -HowToOverride "Attach Docker lifecycle, readiness, cleanup, QaaS live, airgapped, and strong-review transcripts." -PublicEvidence $crawlPublicEvidence)
        (New-IntentQuestion -QuestionId "runnability" -Question "What can run now, and what must be deferred?" -SelfAnswer "Static selected-candidate validation can run now. Docker lifecycle/cleanup, custom assertion build/template/live validation, QaaS live act/assert, strong review, and live airgapped weak-model validation are deferred and block promotion." -AnswerSource "blocked" -RiskIfWrong "A weak model may confuse a blocked healthcheck candidate with an executable promoted test." -HowToOverride "Attach passing Docker lifecycle, custom assertion build/template/live, QaaS live, cleanup, airgapped, and strong-review evidence." -PublicEvidence $crawlPublicEvidence)
    )
    $crawlIntentAssumptions = @(
        (New-IntentAssumption -Assumption "Docker curl -f /health is represented by a custom HttpStatusBelow400 assertion, not by built-in HttpStatus equality." -WhySafe "The public Dockerfile and compose healthchecks use curl -f, and public QaaS docs support custom assertions when built and template-validated." -RiskIfWrong "A weak model may assert StatusCode 200 or body content without selected evidence." -HowToOverride "Provide exact public status/body evidence or a different documented assertion." -PublicEvidence $crawlPublicEvidence)
        (New-IntentAssumption -Assumption "The /crawl README example is not promoted." -WhySafe "The selected README branches on results versus task_id and lacks a deterministic response body contract." -RiskIfWrong "A weak model may turn a sample client snippet into an exact API assertion." -HowToOverride "Harvest exact public /crawl request and response contracts before promotion." -PublicEvidence $crawlPublicEvidence)
    )

    $crawlArtifacts = @(
        $crawlRunnerPath,
        $crawlRequestPayloadPath,
        $crawlRuntimePlanPath,
        $crawlManifestPath
    )

    $crawlManifest = [ordered]@{
        schema_version = 1
        campaign_id = "selected-top-repo-crawl4ai-health-candidate"
        source_repository = "unclecode/crawl4ai"
        repository_rank = [int]$crawlSelected.rank
        selected_contract = $crawlRecordPath
        docs_evidence = $crawlDocsEvidence
        public_evidence = $crawlPublicEvidence
        intent_questions = $crawlIntentQuestions
        intent_assumptions = $crawlIntentAssumptions
        artifacts = $crawlArtifacts
        artifact_count = $crawlArtifacts.Count
        artifact_types = @("runner-yaml", "request-payload", "custom-assertion", "dependency-gate", "documentation")
        cases = @(
            [ordered]@{
                name = "docker-health-curl-f"
                method = "GET"
                route = "/health"
                status_semantics = "http_status_less_than_400"
                body_assertion = "unasserted_no_public_body_contract"
            }
        )
        assertions = @(
            "Candidate Runner YAML uses a docs-derived custom HttpStatusBelow400 assertion for Docker curl -f semantics.",
            "Candidate intentionally does not assert /health response body or schema.",
            "Candidate intentionally does not promote /crawl from the README sample client."
        )
        custom_assertion_packets = @($crawlCustomAssertionPacket)
        dependency_gates = @(
            (New-DependencyGate -GateId "selected-public-runtime-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence $crawlPublicEvidence -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "selected-public-healthcheck-contract" -Kind "runtime" -Required $true -Status "ready" -Evidence @($crawlDockerfilePath, $crawlComposePath) -CheckCommand "" -BlockedReason "")
            (New-DependencyGate -GateId "qaas-docs-yaml-shape" -Kind "runtime" -Required $true -Status "ready" -Evidence $crawlDocsEvidence -CheckCommand "D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite selected-candidates" -BlockedReason "")
            (New-DependencyGate -GateId "http-status-below-400-assertion-or-hook" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence @($crawlHookCodePath, $crawlHookUsagePath, $crawlHookPlanPath) -CheckCommand "" -BlockedReason "The custom HttpStatusBelow400 assertion has not passed build/schema/template/live validation.")
            (New-DependencyGate -GateId "docker-crawl4ai-container-lifecycle" -Kind "dependency" -Required $true -Status "blocked" -Evidence $crawlPublicEvidence -CheckCommand "" -BlockedReason "Docker pull/run/readiness with a unique test-owned container has not been live-validated.")
            (New-DependencyGate -GateId "cleanup-contract" -Kind "cleanup" -Required $true -Status "blocked" -Evidence $crawlPublicEvidence -CheckCommand "" -BlockedReason "Unique test-owned container cleanup has not been live-validated.")
            (New-DependencyGate -GateId "qaas-template" -Kind "qaas-template" -Required $true -Status "blocked" -Evidence $crawlDocsEvidence -CheckCommand "" -BlockedReason "QaaS template validation has not run for this candidate.")
            (New-DependencyGate -GateId "qaas-live-act-assert" -Kind "qaas-build" -Required $true -Status "blocked" -Evidence $crawlDocsEvidence -CheckCommand "" -BlockedReason "Live QaaS run/act/assert has not run against a test-owned Crawl4AI container.")
            (New-DependencyGate -GateId "airgapped-validation" -Kind "airgapped" -Required $true -Status "blocked" -Evidence @() -CheckCommand "D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none" -BlockedReason "Live weak-model validation has not passed.")
        )
        promotion_requirements = [ordered]@{
            current_state = "blocked"
            target_state = "executable_ready"
            required_evidence = @(
                "Public API, CLI, or runtime contract",
                "Public input and expected-output contract",
                "Public dependency/stub contract",
                "Public Docker healthcheck contract",
                "Custom assertion build/schema/template validation",
                "C# build result when code artifacts exist",
                "Docker pull/run/readiness transcript with unique container name",
                "Cleanup contract",
                "Docker cleanup transcript proving no user-owned crawl4ai container was removed",
                "QaaS template validation result",
                "Live QaaS run/act/assert result when dependency gates are ready",
                "Airgapped weak-model validation transcript"
            )
        }
        cleanup = @("No live Docker cleanup was performed during static candidate generation.")
        validation_sequence = @(
            "Validate selected immutable public Docker healthcheck evidence.",
            "Validate QaaS public docs/schema fields and custom assertion plan.",
            "Run selected top-repo candidate checker.",
            "Run Docker lifecycle validation with a unique test-owned container.",
            "Build and template-validate the HttpStatusBelow400 assertion.",
            "Run live QaaS act/assert against the tracked container.",
            "Run live airgapped weak-model validation and strong review before promotion."
        )
        airgapped_validation = [ordered]@{
            required = $true
            status = "not_run_for_this_candidate"
            dry_run = $false
        }
        source_only_blockers = @(
            (New-SourceOnlyBlocker -BlockerId "crawl4ai-docker-lifecycle-not-proven" -BlockerType "repository_contract" -Description "The README command and Docker healthcheck are public evidence, but Docker image pull, startup, readiness, resource limits, and cleanup have not been executed and verified." -RequiredEvidence @("Docker pull transcript", "Unique container run transcript", "Readiness probe transcript", "Cleanup transcript proving only the test-owned container was removed") -PublicEvidence $crawlPublicEvidence -UnblockInstruction "Run a Docker lifecycle harness that uses a unique container name and preserves any user-owned crawl4ai container.")
            (New-SourceOnlyBlocker -BlockerId "crawl4ai-status-below-400-hook-not-template-validated" -BlockerType "qaas_docs_contract" -Description "A docs-derived HttpStatusBelow400 custom assertion is authored and referenced, but Runner assembly discovery, schema/template validation, build validation, and live QaaS act/assert have not passed." -RequiredEvidence @("Assertion build transcript", "Runner project reference transcript", "Template validation transcript", "Live QaaS act/assert transcript") -PublicEvidence @($crawlHookDocsEvidence + @($crawlHookCodePath, $crawlHookUsagePath, $crawlHookPlanPath)) -UnblockInstruction "Reference the assertion assembly, regenerate schema/clean bin, run QaaS template validation, then run live QaaS act/assert before promotion.")
            (New-SourceOnlyBlocker -BlockerId "crawl4ai-health-body-contract-not-selected" -BlockerType "source_boundary" -Description "Selected public evidence defines Docker curl -f status semantics for /health, but no exact response body or schema contract." -RequiredEvidence @("Immutable public /health response body or schema evidence") -PublicEvidence @($crawlDockerfilePath, $crawlComposePath) -UnblockInstruction "Do not add body/schema assertions until deterministic public evidence is harvested.")
            (New-SourceOnlyBlocker -BlockerId "crawl4ai-crawl-endpoint-not-promoted" -BlockerType "source_boundary" -Description "The README /crawl sample branches between results and task_id polling; it is not a deterministic input/output contract." -RequiredEvidence @("Exact public /crawl request/response status/body contract", "Side-effect and cleanup contract") -PublicEvidence @($crawlReadmePath, $crawlSchemasPath) -UnblockInstruction "Keep /crawl out of candidate YAML until exact response and side-effect evidence exists.")
            (New-SourceOnlyBlocker -BlockerId "qaas-template-live-not-run" -BlockerType "qaas_docs_contract" -Description "The Runner YAML and custom assertion are schema-derived but have not passed QaaS template or live act/assert validation." -RequiredEvidence @("QaaS template validation transcript", "Live QaaS run/act/assert transcript") -PublicEvidence $crawlDocsEvidence -UnblockInstruction "Run documented QaaS validation commands in an environment with Runner host and test-owned Crawl4AI container.")
            (New-SourceOnlyBlocker -BlockerId "live-airgapped-weak-model-not-passed" -BlockerType "source_boundary" -Description "Live weak-model validation has not passed for this candidate packet." -RequiredEvidence @("Airgapped transcript with dry_run false and /health status-only contract preserved") -PublicEvidence @((Join-Path "D:\QaaS\_tools\zappa-harness" "references\airgapped-validation.md")) -UnblockInstruction "Run D:\QaaS\_tools\weak-model-session.ps1 -Airgapped -All -ReasoningEffort none when quota/routing is available.")
        )
        status = "blocked_until_repo_contract_review"
        promotion_state = "blocked"
        blocked_reason = "Selected public contracts support a Crawl4AI Docker /health status-only candidate, but executable promotion is blocked until Docker lifecycle/cleanup, custom assertion build/template/live, QaaS template/live, airgapped, and strong-review evidence pass."
    }
    Write-JsonFile -Path $crawlManifestPath -Value $crawlManifest

    $crawlRecord = [ordered]@{
        rank = [int]$crawlSelected.rank
        repository = "unclecode/crawl4ai"
        directory = $crawlCandidateDir
        manifest = $crawlManifestPath
        selected_contract = $crawlRecordPath
        status = "candidate_packet_blocked_until_template_live_airgapped_validation"
        promotion_state = "blocked"
        readiness_state = "qaaS_candidate_authored_from_selected_contract"
        artifact_count = $crawlArtifacts.Count
    }
    $records += $crawlRecord
}

$selectedIndexPath = Join-Path $SelectedContractsDir "selected-contract-index.json"
$deferredRecords = @()
if (Test-Path -LiteralPath $selectedIndexPath -PathType Leaf) {
    $selectedIndex = Get-Content -LiteralPath $selectedIndexPath -Raw | ConvertFrom-Json
    $generatedRepositories = @($records | ForEach-Object { [string]$_.repository })
    foreach ($selectedIndexRecord in @($selectedIndex.records)) {
        $repo = [string]$selectedIndexRecord.repository
        if ($generatedRepositories -contains $repo) {
            continue
        }
        $deferredBlockers = @(
            "candidate_generation_not_implemented",
            "live_harness_not_available",
            "run_live_airgapped_weak_model_validation",
            "run_strong_review_against_selected_contract_evidence"
        )
        if ($repo -eq "unclecode/crawl4ai") {
            $deferredBlockers = @(
                "selected_input_output_contract_missing",
                "selected_crawl_response_is_branching_async_or_results_contract",
                "selected_healthcheck_status_is_not_exact_http_contract",
                "selected_healthcheck_body_contract_missing",
                "docker_runtime_requires_live_container_safety_plan"
            ) + $deferredBlockers
        }
        $deferredRecord = [ordered]@{
            rank = [int]$selectedIndexRecord.rank
            repository = $repo
            selected_contract = [string]$selectedIndexRecord.record_path
            status = "deferred_candidate_packet_blocked"
            promotion_state = "blocked"
            blockers = $deferredBlockers
        }
        if ($repo -eq "unclecode/crawl4ai") {
            $deferredRecord.deferred_reason = "selected_public_contract_lacks_exact_input_output_contract"
            $deferredRecord.unsafe_promotion_risks = @(
                "README /crawl example accepts HTTP 200 and branches between synchronous results and task_id polling.",
                "Docker healthchecks use curl -f /health and prove liveness only, not an exact QaaS-assertable response body.",
                "Container runtime depends on browser shared memory, Redis, memory limits, and cleanup that are not live-validated."
            )
            $deferredRecord.required_before_generation = @(
                "Exact public request payload, response status, and response body contract.",
                "Container lifecycle plan with readiness, isolation, resource limits, and cleanup evidence.",
                "QaaS template validation transcript.",
                "Live QaaS act/assert transcript.",
                "Live airgapped weak-model validation transcript."
            )
        }
        $deferredRecords += $deferredRecord
    }
}

$index = [ordered]@{
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    source_selected_contracts_directory = $SelectedContractsDir
    output_directory = $resolvedOutDir
    selected_candidate_count = $records.Count
    selected_contract_count = if (Test-Path -LiteralPath $selectedIndexPath -PathType Leaf) { [int](Get-Content -LiteralPath $selectedIndexPath -Raw | ConvertFrom-Json).selected_repository_count } else { $records.Count }
    deferred_candidate_count = $deferredRecords.Count
    policy = "selected top-repo candidate packets remain blocked until template/live/cleanup/airgapped/strong-review evidence exists"
    records = @($records)
    deferred_records = @($deferredRecords)
}
$indexPath = Join-Path $resolvedOutDir "selected-candidate-index.json"
Write-JsonFile -Path $indexPath -Value $index

Write-Output "Generated selected top-repo candidate packets: $($records.Count)"
Write-Output "Deferred selected repositories: $($deferredRecords.Count)"
Write-Output "Index: $indexPath"
