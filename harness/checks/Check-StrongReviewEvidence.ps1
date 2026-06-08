param(
    [string]$ReviewPath = "D:\QaaS\_tmp\zappa-dont-cry\strong-reviews\initial-pack-review.md",
    [string]$HarnessRunRoot = "D:\QaaS\_tmp\zappa-dont-cry\harness-runs",
    [string]$BlockersDir = "D:\QaaS\_tmp\zappa-dont-cry\blockers",
    [string]$CoveragePath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\objective-capability-coverage.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

if (-not (Test-Path -LiteralPath $ReviewPath -PathType Leaf)) {
    Add-Failure "Missing strong review: $ReviewPath"
} elseif (-not (Test-Path -LiteralPath $HarnessRunRoot -PathType Container)) {
    Add-Failure "Missing harness run root: $HarnessRunRoot"
} else {
    $review = Get-Content -LiteralPath $ReviewPath -Raw
    $reviewInfo = Get-Item -LiteralPath $ReviewPath

    $reports = @(Get-ChildItem -LiteralPath $HarnessRunRoot -Recurse -File -Filter "report.json" |
        ForEach-Object {
            try {
                $report = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                if ($report.suite -eq "all" -and $report.overall_status -eq "passed") {
                    $results = @()
                    if ($report.PSObject.Properties.Name -contains "results") {
                        $results = @($report.results)
                    }
                    $sourceOnlyResult = @($results | Where-Object { $_.name -eq "source-only-blockers" }) | Select-Object -First 1
                    $promotionPacketResult = @($results | Where-Object { $_.name -eq "promotion-packet" }) | Select-Object -First 1
                    $promotionSeedResult = @($results | Where-Object { $_.name -eq "promotion-seed-lifecycle" }) | Select-Object -First 1
                    $topRepoTriageResult = @($results | Where-Object { $_.name -eq "top-repo-promotion-triage" }) | Select-Object -First 1
                    $weakScenarioIndexResult = @($results | Where-Object { $_.name -eq "weak-scenario-live-index" }) | Select-Object -First 1
                    $weakAdversarialIndexResult = @($results | Where-Object { $_.name -eq "weak-adversarial-live-index" }) | Select-Object -First 1
                    $weakSuiteRunnerResult = @($results | Where-Object { $_.name -eq "weak-suite-runner" }) | Select-Object -First 1
                    $adversarialResult = @($results | Where-Object { $_.name -eq "weak-adversarial-scenarios" }) | Select-Object -First 1
                    $adversarialOutputResult = @($results | Where-Object { $_.name -eq "weak-adversarial-outputs" }) | Select-Object -First 1
                    [pscustomobject]@{
                        Path = $_.FullName
                        GeneratedAt = [datetime]$report.generated_at
                        Total = [int]$report.summary.total
                        Passed = [int]$report.summary.passed
                        Failed = [int]$report.summary.failed
                        SourceOnlyStatus = if ($null -ne $sourceOnlyResult) { $sourceOnlyResult.status } else { $null }
                        SourceOnlyLog = if ($null -ne $sourceOnlyResult) { $sourceOnlyResult.log } else { $null }
                        PromotionPacketStatus = if ($null -ne $promotionPacketResult) { $promotionPacketResult.status } else { $null }
                        PromotionPacketLog = if ($null -ne $promotionPacketResult) { $promotionPacketResult.log } else { $null }
                        PromotionSeedStatus = if ($null -ne $promotionSeedResult) { $promotionSeedResult.status } else { $null }
                        PromotionSeedLog = if ($null -ne $promotionSeedResult) { $promotionSeedResult.log } else { $null }
                        TopRepoTriageStatus = if ($null -ne $topRepoTriageResult) { $topRepoTriageResult.status } else { $null }
                        TopRepoTriageLog = if ($null -ne $topRepoTriageResult) { $topRepoTriageResult.log } else { $null }
                        WeakScenarioIndexStatus = if ($null -ne $weakScenarioIndexResult) { $weakScenarioIndexResult.status } else { $null }
                        WeakScenarioIndexLog = if ($null -ne $weakScenarioIndexResult) { $weakScenarioIndexResult.log } else { $null }
                        WeakAdversarialIndexStatus = if ($null -ne $weakAdversarialIndexResult) { $weakAdversarialIndexResult.status } else { $null }
                        WeakAdversarialIndexLog = if ($null -ne $weakAdversarialIndexResult) { $weakAdversarialIndexResult.log } else { $null }
                        WeakSuiteRunnerStatus = if ($null -ne $weakSuiteRunnerResult) { $weakSuiteRunnerResult.status } else { $null }
                        WeakSuiteRunnerLog = if ($null -ne $weakSuiteRunnerResult) { $weakSuiteRunnerResult.log } else { $null }
                        AdversarialStatus = if ($null -ne $adversarialResult) { $adversarialResult.status } else { $null }
                        AdversarialLog = if ($null -ne $adversarialResult) { $adversarialResult.log } else { $null }
                        AdversarialOutputStatus = if ($null -ne $adversarialOutputResult) { $adversarialOutputResult.status } else { $null }
                        AdversarialOutputLog = if ($null -ne $adversarialOutputResult) { $adversarialOutputResult.log } else { $null }
                    }
                }
            } catch {
                $null
            }
        } |
        Sort-Object GeneratedAt -Descending)

    if ($reports.Count -eq 0) {
        Add-Failure "No passed full harness reports found under $HarnessRunRoot"
    } else {
        $latest = $reports[0]
        if ($reviewInfo.LastWriteTimeUtc -lt $latest.GeneratedAt.ToUniversalTime()) {
            Add-Failure "Strong review is older than latest passed full harness report: $($latest.Path)"
        }
        if ($review -notmatch [regex]::Escape($latest.Path)) {
            Add-Failure "Strong review does not cite latest passed full harness report: $($latest.Path)"
        }
        if ($review -notmatch "Full harness suite passed with $($latest.Total) checks") {
            Add-Failure "Strong review does not cite latest full harness check count $($latest.Total)"
        }
        if ($review -notmatch "$($latest.Passed) passed") {
            Add-Failure "Strong review does not cite latest full harness passed count $($latest.Passed)"
        }
        if ($review -notmatch "$($latest.Failed) failed") {
            Add-Failure "Strong review does not cite latest full harness failed count $($latest.Failed)"
        }
        if ($latest.SourceOnlyStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed source-only-blockers result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.SourceOnlyLog -PathType Leaf)) {
            Add-Failure "Latest source-only-blockers log does not exist: $($latest.SourceOnlyLog)"
        } else {
            $sourceOnlyLog = Get-Content -LiteralPath $latest.SourceOnlyLog -Raw
            $sourceOnlyMatch = [regex]::Match($sourceOnlyLog, "Source-only blocker check passed for (?<manifest_count>\d+) manifests and (?<blocker_count>\d+) blockers\.")
            if (-not $sourceOnlyMatch.Success) {
                Add-Failure "Could not parse source-only-blockers log counts: $($latest.SourceOnlyLog)"
            } else {
                $sourceOnlyManifestCount = [int]$sourceOnlyMatch.Groups["manifest_count"].Value
                $sourceOnlyBlockerCount = [int]$sourceOnlyMatch.Groups["blocker_count"].Value
                foreach ($requiredText in @(
                    $latest.SourceOnlyLog,
                    "source_only_blockers",
                    "$sourceOnlyManifestCount manifests",
                    "$sourceOnlyBlockerCount blockers"
                )) {
                    if ($review -notmatch [regex]::Escape($requiredText)) {
                        Add-Failure "Strong review missing source-only evidence text: $requiredText"
                    }
                }
            }
        }
        if ($latest.PromotionPacketStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed promotion-packet result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.PromotionPacketLog -PathType Leaf)) {
            Add-Failure "Latest promotion-packet log does not exist: $($latest.PromotionPacketLog)"
        } else {
            $promotionPacketLog = Get-Content -LiteralPath $latest.PromotionPacketLog -Raw
            $packetSummaryMatch = [regex]::Match($promotionPacketLog, "Summary:\s*(?<path>.+promotion-packet-summary\.json)")
            if (-not $packetSummaryMatch.Success) {
                Add-Failure "Could not parse promotion-packet summary path from log: $($latest.PromotionPacketLog)"
            } else {
                $packetSummaryFromLog = $packetSummaryMatch.Groups["path"].Value.Trim()
                if (-not (Test-Path -LiteralPath $packetSummaryFromLog -PathType Leaf)) {
                    Add-Failure "Promotion packet summary file does not exist: $packetSummaryFromLog"
                }
            }
        }
        if ($latest.PromotionSeedStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed promotion-seed-lifecycle result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.PromotionSeedLog -PathType Leaf)) {
            Add-Failure "Latest promotion-seed-lifecycle log does not exist: $($latest.PromotionSeedLog)"
        } else {
            $promotionSeedLog = Get-Content -LiteralPath $latest.PromotionSeedLog -Raw
            $seedManifestMatch = [regex]::Match($promotionSeedLog, "Manifest:\s*(?<path>.+qaas-artifact-manifest\.json)")
            if (-not $seedManifestMatch.Success) {
                Add-Failure "Could not parse promotion seed manifest path from log: $($latest.PromotionSeedLog)"
            } else {
                $seedManifestPath = $seedManifestMatch.Groups["path"].Value.Trim()
                if (-not (Test-Path -LiteralPath $seedManifestPath -PathType Leaf)) {
                    Add-Failure "Promotion seed manifest file does not exist: $seedManifestPath"
                } else {
                    $seedManifest = Read-JsonFile -Path $seedManifestPath
                    foreach ($requiredText in @(
                        "promotion-seed-lifecycle",
                        $latest.PromotionSeedLog,
                        $seedManifestPath,
                        "campaign_id: $($seedManifest.campaign_id)",
                        "template_validation_status: $($seedManifest.template_validation.status)",
                        "build_validation_status: $($seedManifest.build_validation.status)",
                        "live_validation_status: $($seedManifest.live_validation.status)",
                        "airgapped_validation_status: $($seedManifest.airgapped_validation.status)",
                        "promotion_state: $($seedManifest.promotion_state)"
                    )) {
                        if ($review -notmatch [regex]::Escape($requiredText)) {
                            Add-Failure "Strong review missing promotion seed evidence text: $requiredText"
                        }
                    }
                }
            }
        }
        if ($latest.TopRepoTriageStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed top-repo-promotion-triage result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.TopRepoTriageLog -PathType Leaf)) {
            Add-Failure "Latest top-repo-promotion-triage log does not exist: $($latest.TopRepoTriageLog)"
        } else {
            $topRepoTriageLog = Get-Content -LiteralPath $latest.TopRepoTriageLog -Raw
            $triageRecordMatch = [regex]::Match($topRepoTriageLog, "Record:\s*(?<path>.+top-repo-promotion-triage\.json)")
            if (-not $triageRecordMatch.Success) {
                Add-Failure "Could not parse top-repo-promotion-triage record path from log: $($latest.TopRepoTriageLog)"
            } else {
                $triageRecordPath = $triageRecordMatch.Groups["path"].Value.Trim()
                if (-not (Test-Path -LiteralPath $triageRecordPath -PathType Leaf)) {
                    Add-Failure "Top-repo promotion triage record file does not exist: $triageRecordPath"
                } else {
                    $triageRecord = Read-JsonFile -Path $triageRecordPath
                    $backlogCount = $triageRecord.by_triage_state.contract_discovery_backlog
                    foreach ($requiredText in @(
                        "top-repo-promotion-triage",
                        $latest.TopRepoTriageLog,
                        $triageRecordPath,
                        "triage_status: $($triageRecord.triage_status)",
                        "completion_ready: $($triageRecord.completion_ready.ToString().ToLowerInvariant())",
                        "contract_count: $($triageRecord.contract_count)",
                        "manifest_count: $($triageRecord.manifest_count)",
                        "high_potential_count: $($triageRecord.high_potential_count)",
                        "contract_review_priority_count: $($triageRecord.contract_review_priority_count)",
                        "contract_discovery_backlog: $backlogCount"
                    )) {
                        if ($review -notmatch [regex]::Escape($requiredText)) {
                            Add-Failure "Strong review missing top-repo triage evidence text: $requiredText"
                        }
                    }
                }
            }
        }
        if ($latest.WeakScenarioIndexStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed weak-scenario-live-index result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.WeakScenarioIndexLog -PathType Leaf)) {
            Add-Failure "Latest weak-scenario-live-index log does not exist: $($latest.WeakScenarioIndexLog)"
        }
        if ($latest.WeakAdversarialIndexStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed weak-adversarial-live-index result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.WeakAdversarialIndexLog -PathType Leaf)) {
            Add-Failure "Latest weak-adversarial-live-index log does not exist: $($latest.WeakAdversarialIndexLog)"
        }

        if ($latest.WeakSuiteRunnerStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed weak-suite-runner result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.WeakSuiteRunnerLog -PathType Leaf)) {
            Add-Failure "Latest weak-suite-runner log does not exist: $($latest.WeakSuiteRunnerLog)"
        } else {
            $weakSuiteRunnerLog = Get-Content -LiteralPath $latest.WeakSuiteRunnerLog -Raw
            $summaryMatches = [regex]::Matches($weakSuiteRunnerLog, "Summary:\s*(?<path>.+weak-scenario-suite-runner-summary\.json)")
            $indexMatches = [regex]::Matches($weakSuiteRunnerLog, "Index:\s*(?<path>.+weak-(?:scenario|adversarial)-runner-index\.json)")
            if ($summaryMatches.Count -lt 2) {
                Add-Failure "Could not parse cooperative and adversarial weak-suite-runner summaries from log: $($latest.WeakSuiteRunnerLog)"
            } elseif ($indexMatches.Count -lt 2) {
                Add-Failure "Could not parse cooperative and adversarial weak-suite-runner indexes from log: $($latest.WeakSuiteRunnerLog)"
            } else {
                $runnerSummaries = @($summaryMatches | ForEach-Object { $_.Groups["path"].Value.Trim() })
                $runnerIndexes = @($indexMatches | ForEach-Object { $_.Groups["path"].Value.Trim() })
                $cooperativeSummaryPath = $runnerSummaries[0]
                $adversarialSummaryPath = $runnerSummaries[1]
                $cooperativeIndexPath = $runnerIndexes[0]
                $adversarialIndexPath = $runnerIndexes[1]
                if (-not (Test-Path -LiteralPath $cooperativeSummaryPath -PathType Leaf)) {
                    Add-Failure "Weak suite cooperative summary file does not exist: $cooperativeSummaryPath"
                } elseif (-not (Test-Path -LiteralPath $adversarialSummaryPath -PathType Leaf)) {
                    Add-Failure "Weak suite adversarial summary file does not exist: $adversarialSummaryPath"
                } elseif (-not (Test-Path -LiteralPath $cooperativeIndexPath -PathType Leaf)) {
                    Add-Failure "Weak suite cooperative index file does not exist: $cooperativeIndexPath"
                } elseif (-not (Test-Path -LiteralPath $adversarialIndexPath -PathType Leaf)) {
                    Add-Failure "Weak suite adversarial index file does not exist: $adversarialIndexPath"
                } else {
                    $cooperativeSummary = Read-JsonFile -Path $cooperativeSummaryPath
                    $adversarialSummary = Read-JsonFile -Path $adversarialSummaryPath
                    foreach ($requiredText in @(
                        "weak-suite-runner",
                        $latest.WeakSuiteRunnerLog,
                        $cooperativeSummaryPath,
                        $adversarialSummaryPath,
                        $cooperativeIndexPath,
                        $adversarialIndexPath,
                        "cooperative_runner_scenario_count: $($cooperativeSummary.scenario_count)",
                        "adversarial_runner_scenario_count: $($adversarialSummary.scenario_count)",
                        "runner_status: dry_run_prompt_assembly",
                        "match_status: runner_recorded",
                        "classification: dry_run_assembly"
                    )) {
                        if ($review -notmatch [regex]::Escape($requiredText)) {
                            Add-Failure "Strong review missing weak suite runner evidence text: $requiredText"
                        }
                    }
                }
            }
        }
        
        if ($latest.AdversarialStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed weak-adversarial-scenarios result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.AdversarialLog -PathType Leaf)) {
            Add-Failure "Latest weak-adversarial-scenarios log does not exist: $($latest.AdversarialLog)"
        } else {
            $adversarialLog = Get-Content -LiteralPath $latest.AdversarialLog -Raw
            $recordMatch = [regex]::Match($adversarialLog, "Records:\s*(?<path>.+weak-adversarial-scenario-records\.json)")
            if (-not $recordMatch.Success) {
                Add-Failure "Could not parse weak-adversarial-scenarios record path from log: $($latest.AdversarialLog)"
            } else {
                $adversarialRecordPath = $recordMatch.Groups["path"].Value.Trim()
                if (-not (Test-Path -LiteralPath $adversarialRecordPath -PathType Leaf)) {
                    Add-Failure "Weak adversarial record file does not exist: $adversarialRecordPath"
                } else {
                    $adversarialRecord = Read-JsonFile -Path $adversarialRecordPath
                    foreach ($requiredText in @(
                        "weak-adversarial-scenarios",
                        $adversarialRecordPath,
                        "weak-adversarial-scenario-records.json",
                        "validation_kind: $($adversarialRecord.validation_kind)",
                        "adversarial_scenario_count: $($adversarialRecord.adversarial_scenario_count)",
                        "weak_validation_passed: $($adversarialRecord.weak_validation_passed.ToString().ToLowerInvariant())"
                    )) {
                        if ($review -notmatch [regex]::Escape($requiredText)) {
                            Add-Failure "Strong review missing adversarial weak-model evidence text: $requiredText"
                        }
                    }
                }
            }
        }
        if ($latest.AdversarialOutputStatus -ne "passed") {
            Add-Failure "Latest passed full harness report does not contain a passed weak-adversarial-outputs result: $($latest.Path)"
        } elseif (-not (Test-Path -LiteralPath $latest.AdversarialOutputLog -PathType Leaf)) {
            Add-Failure "Latest weak-adversarial-outputs log does not exist: $($latest.AdversarialOutputLog)"
        } else {
            $adversarialOutputLog = Get-Content -LiteralPath $latest.AdversarialOutputLog -Raw
            $outputRecordMatch = [regex]::Match($adversarialOutputLog, "Record:\s*(?<path>.+weak-adversarial-output-latest\.json)")
            if (-not $outputRecordMatch.Success) {
                Add-Failure "Could not parse weak-adversarial-outputs record path from log: $($latest.AdversarialOutputLog)"
            } else {
                $adversarialOutputRecordPath = $outputRecordMatch.Groups["path"].Value.Trim()
                if (-not (Test-Path -LiteralPath $adversarialOutputRecordPath -PathType Leaf)) {
                    Add-Failure "Weak adversarial output record file does not exist: $adversarialOutputRecordPath"
                } else {
                    $adversarialOutputRecord = Read-JsonFile -Path $adversarialOutputRecordPath
                    foreach ($requiredText in @(
                        "weak-adversarial-outputs",
                        $adversarialOutputRecordPath,
                        "weak-adversarial-output-latest.json",
                        "validation_kind: $($adversarialOutputRecord.validation_kind)",
                        "required_adversarial_scenario_count: $($adversarialOutputRecord.required_adversarial_scenario_count)",
                        "quota_blocked_count: $($adversarialOutputRecord.quota_blocked_count)",
                        "missing_transcript_count: $($adversarialOutputRecord.missing_transcript_count)",
                        "weak_validation_passed: $($adversarialOutputRecord.weak_validation_passed.ToString().ToLowerInvariant())"
                    )) {
                        if ($review -notmatch [regex]::Escape($requiredText)) {
                            Add-Failure "Strong review missing adversarial live-output evidence text: $requiredText"
                        }
                    }
                }
            }
        }
    }

    $yamlEvidencePath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\qaas-yaml-schema-evidence.json"
    $intentClarificationPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\intent-clarification-coverage.json"
    $promotionCandidateIndexPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\promotion-candidate-index.json"
    $promotionPacketSummaryPath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\promotion-packet-summary.json"
    $topRepoPromotionTriagePath = "D:\QaaS\_tmp\zappa-dont-cry\coverage\top-repo-promotion-triage.json"
    $completionReadinessPath = Join-Path $BlockersDir "objective-completion-readiness.json"
    $airgappedLivePath = Join-Path $BlockersDir "airgapped-live-latest.json"
    $copilotFallbackPath = Join-Path $BlockersDir "copilot-fallback-latest.json"
    $weakScenarioOutputPath = Join-Path $BlockersDir "weak-scenario-output-latest.json"
    $weakAdversarialOutputPath = Join-Path $BlockersDir "weak-adversarial-output-latest.json"
    $weakScenarioIndexPath = Join-Path $BlockersDir "weak-scenario-live-index-latest.json"
    $weakAdversarialIndexPath = Join-Path $BlockersDir "weak-adversarial-live-index-latest.json"

    foreach ($path in @(
        $CoveragePath,
        $yamlEvidencePath,
        $intentClarificationPath,
        $promotionCandidateIndexPath,
        $promotionPacketSummaryPath,
        $topRepoPromotionTriagePath,
        $completionReadinessPath,
        $airgappedLivePath,
        $copilotFallbackPath,
        $weakScenarioOutputPath,
        $weakAdversarialOutputPath,
        $weakScenarioIndexPath,
        $weakAdversarialIndexPath
    )) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-Failure "Expected cited evidence file does not exist: $path"
        } elseif ($review -notmatch [regex]::Escape($path)) {
            Add-Failure "Strong review does not cite evidence file: $path"
        }
    }

    if (Test-Path -LiteralPath $completionReadinessPath -PathType Leaf) {
        $completionReadiness = Read-JsonFile -Path $completionReadinessPath
        foreach ($requiredText in @(
            "$($completionReadiness.blocked_manifest_count) blocked manifests",
            "$($completionReadiness.executable_manifest_count) executable manifests",
            "live_weak_model_ready: $($completionReadiness.live_weak_model_ready.ToString().ToLowerInvariant())",
            "no_promotable_qaas_manifests",
            "promotion_dependency_gates_blocked",
            "promotion_source_only_blocked",
            "promotion_template_validation_missing",
            "promotion_live_validation_missing",
            "promotion_airgapped_validation_missing"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing completion-readiness evidence text: $requiredText"
            }
        }
    }

    if (Test-Path -LiteralPath $promotionCandidateIndexPath -PathType Leaf) {
        $promotionIndex = Read-JsonFile -Path $promotionCandidateIndexPath
        $summary = $promotionIndex.summary
        foreach ($requiredText in @(
            "promotion-candidate-index",
            $promotionCandidateIndexPath,
            "promotable_candidate_count: $($summary.promotable_candidate_count)",
            "executable_manifest_count: $($summary.executable_manifest_count)",
            "blocked_by_dependency_gates_count: $($summary.blocked_by_dependency_gates_count)",
            "blocked_by_source_only_count: $($summary.blocked_by_source_only_count)",
            "placeholder_artifact_count: $($summary.placeholder_artifact_count)"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing promotion index evidence text: $requiredText"
            }
        }
    }

    if (Test-Path -LiteralPath $promotionPacketSummaryPath -PathType Leaf) {
        $promotionPacket = Read-JsonFile -Path $promotionPacketSummaryPath
        foreach ($requiredText in @(
            "promotion-packet",
            $promotionPacketSummaryPath,
            "promotion_packet_status: $($promotionPacket.promotion_packet_status)",
            "packet_count: $($promotionPacket.packet_count)",
            "promotable_candidate_count: $($promotionPacket.promotable_candidate_count)",
            "executable_manifest_count: $($promotionPacket.executable_manifest_count)"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing promotion packet evidence text: $requiredText"
            }
        }
    }

    if (Test-Path -LiteralPath $yamlEvidencePath -PathType Leaf) {
        $yamlEvidence = Read-JsonFile -Path $yamlEvidencePath
        foreach ($requiredText in @(
            "$($yamlEvidence.yaml_count) YAML artifacts",
            "runner-family-schema.json",
            "mocker-family-schema.json"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing YAML evidence text: $requiredText"
            }
        }
    }

    if (Test-Path -LiteralPath $intentClarificationPath -PathType Leaf) {
        $intentClarification = Read-JsonFile -Path $intentClarificationPath
        foreach ($requiredText in @(
            "intent-clarification-coverage",
            $intentClarificationPath,
            "intent_question_count: $($intentClarification.intent_question_count)",
            "canonical_question_count: $($intentClarification.canonical_question_count)",
            "expected_question_count: $($intentClarification.expected_question_count)",
            "blocked_answer_count: $($intentClarification.blocked_answer_count)"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing intent clarification evidence text: $requiredText"
            }
        }
    }

    if (Test-Path -LiteralPath $weakScenarioIndexPath -PathType Leaf) {
        $weakScenarioIndex = Read-JsonFile -Path $weakScenarioIndexPath
        foreach ($requiredText in @(
            "weak-scenario-live-index",
            $weakScenarioIndexPath,
            "indexed_scenario_count: $($weakScenarioIndex.indexed_scenario_count)",
            "prompt_hash_sha256",
            "match_status: exact_prompt_match",
            "index_status: $($weakScenarioIndex.index_status)"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing weak scenario index evidence text: $requiredText"
            }
        }
    }

    if (Test-Path -LiteralPath $weakAdversarialIndexPath -PathType Leaf) {
        $weakAdversarialIndex = Read-JsonFile -Path $weakAdversarialIndexPath
        foreach ($requiredText in @(
            "weak-adversarial-live-index",
            $weakAdversarialIndexPath,
            "indexed_scenario_count: $($weakAdversarialIndex.indexed_scenario_count)",
            "prompt_hash_sha256",
            "index_status: $($weakAdversarialIndex.index_status)"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing weak adversarial index evidence text: $requiredText"
            }
        }
    }

    if (Test-Path -LiteralPath $weakScenarioOutputPath -PathType Leaf) {
        $weakScenarioOutput = Read-JsonFile -Path $weakScenarioOutputPath
        foreach ($requiredText in @(
            "weak-scenario-outputs",
            $weakScenarioOutputPath,
            "weak-scenario-output-latest.json",
            "validation_kind: $($weakScenarioOutput.validation_kind)",
            "required_scenario_count: $($weakScenarioOutput.required_scenario_count)",
            "transcript_count: $($weakScenarioOutput.transcript_count)",
            "quota_blocked_count: $($weakScenarioOutput.quota_blocked_count)",
            "missing_transcript_count: $($weakScenarioOutput.missing_transcript_count)",
            "weak_validation_passed: $($weakScenarioOutput.weak_validation_passed.ToString().ToLowerInvariant())"
        )) {
            if ($review -notmatch [regex]::Escape($requiredText)) {
                Add-Failure "Strong review missing weak scenario live-output evidence text: $requiredText"
            }
        }
    }

    foreach ($requiredText in @(
        "objective_completion_status: not_complete",
        "completion_readiness: blocked",
        "live_weak_scenario_outputs_not_passed",
        "live_adversarial_weak_outputs_not_passed",
        "blocker_id",
        "unblock_instruction",
        "250 manifests, 500 YAML files, and 250 C# files",
        "513 manifests, 329 YAML files, and 387 C# files",
        "weak_validation_passed: false"
    )) {
        if ($review -notmatch [regex]::Escape($requiredText)) {
            Add-Failure "Strong review missing required text: $requiredText"
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { [Console]::Error.WriteLine("ERROR: $_") }
    exit 1
}

Write-Output "Strong review evidence check passed."
