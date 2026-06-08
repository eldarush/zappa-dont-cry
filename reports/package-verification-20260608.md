# Package Verification - 2026-06-08

Verified from `D:\QaaS` and package checkout `D:\QaaS\_deliverables\zappa-dont-cry-20260608-1607`.

## Passed

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\weak-model-session.ps1 -ListProfiles -PolicyPath .\weak-model-policy.json
```

Result: package-local weak-model launcher loads its policy and profile list.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\harness\checks\Check-HarnessReport.ps1 -ReportPath .\reports\report.json
```

Result: package-local final harness report self-check passed for the latest `65/65` full harness report.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite weak-routing
```

Result: source-workspace weak-routing suite passed.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite weak-agent-packet
```

Result: source-workspace weak-agent task packet suite passed.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\harness\checks\Check-WeakAgentTaskPacket.ps1 -HarnessRoot .\harness -PacketRoot D:\QaaS\_tmp\zappa-dont-cry\weak-agent-packets\package-check-final-65
```

Result: package-local weak-agent task packet contract check passed.

```powershell
python D:\QaaS\_tools\zappa-harness\checks\Check-SelectedTopRepoCandidates.py D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts D:\QaaS\_tmp\zappa-dont-cry\coverage
```

Result: selected top-repo candidate check passed for 8 candidate packets.

```powershell
python .\harness\checks\Check-SelectedTopRepoCandidatePromotionReadiness.py .\generated-tests\selected-top-repo-candidates .\coverage
```

Result: package-local selected promotion readiness passed for 8 candidates.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\checks\Check-HarnessReport.ps1 -ReportPath D:\QaaS\_tmp\zappa-dont-cry\harness-runs\20260608-193857-088\report.json
```

Result: source final harness report self-check passed.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\Invoke-ZappaHarness.ps1 -Suite all
```

Result: source final harness passed `65/65` checks from `D:\QaaS\_tmp\zappa-dont-cry\harness-runs\20260608-193857-088\report.json`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-lifecycle-spring-boot.ps1
```

Result: Spring Boot lifecycle passed with Spring Boot `4.0.6`, Java `25+`, a built JAR, HTTP `200`, exact body `Hello World!`, and tracked cleanup evidence.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\QaaS\_tools\zappa-harness\scripts\run-selected-top-repo-candidate-live-spring-boot.ps1
```

Result: Spring Boot live QaaS validation passed with ExactHttpTextBody build/template/live evidence, QaaS template/live execution, exact body `Hello World!`, manifest adoption, and cleanup evidence.

## Known Portability Limit

The direct package-local `Check-SelectedTopRepoCandidates.py` check is not portable yet because generated manifests and validation summaries intentionally preserve absolute `D:\QaaS\_tmp\zappa-dont-cry` evidence paths. The full replay path remains the original `D:\QaaS` workspace layout documented in the README.

This limitation does not change the current completion state: deterministic validation passed, policy promotion remains blocked by missing live preferred weak-model evidence.
