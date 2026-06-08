# Weak Model Validation Summary

Workspace: D:\QaaS
Harness: claude-copilot
Profile: airgapped
ReasoningEffort: none
Models: id:gpt-3.5-turbo, id:gpt-3.5-turbo-0613, gpt-4o-mini, gpt-4o-mini-2024-07-18
DryRun: False
Airgapped: True
PolicyPath: D:\QaaS\_tools\weak-model-policy.json
HarnessRole: Weakest known hosted path for airgapped testing
HarnessConfidence: configured-but-quota-blocked
HarnessCaveat: Use exact id:gpt-3.5-turbo first for airgapped testing. If that hosted route is quota/model blocked, retry only bridge-discovered weak proxy models: id:gpt-3.5-turbo-0613, gpt-4o-mini, and gpt-4o-mini-2024-07-18. Claude aliases route to Opus in this local bridge and are too strong for weak validation. These are skill-following proxies only, not benchmark-equivalent proof for MiniMax M2.5.
ScenarioId: spring-boot-selected-candidate-docs-only
ScenarioKind: scenario
PromptHashSha256: 64411d0f8ae1d341490c880041a1820ea21e380d01f5afe0239c45c1935af773
InjectedSkills: 

## Results
- FAIL exit 1: D:\QaaS\_tmp\weak-model-validation\20260608-173406-860-f94dcde5-claude-copilot-id_gpt-3.5-turbo.md classification=quota_blocked weak_validation_eligible=True evidence_class=preferred_weak not_weak_reason=eligible-policy-weak-proxy (missing expected pattern: blocked; missing expected pattern: Hello World!; missing expected pattern: 8080)
- FAIL exit 1: D:\QaaS\_tmp\weak-model-validation\20260608-173406-860-f94dcde5-claude-copilot-id_gpt-3.5-turbo-0613.md classification=quota_blocked weak_validation_eligible=True evidence_class=preferred_weak not_weak_reason=eligible-policy-weak-proxy (missing expected pattern: blocked; missing expected pattern: Hello World!; missing expected pattern: 8080)
- FAIL exit 1: D:\QaaS\_tmp\weak-model-validation\20260608-173406-860-f94dcde5-claude-copilot-gpt-4o-mini.md classification=quota_blocked weak_validation_eligible=True evidence_class=preferred_weak not_weak_reason=eligible-policy-weak-proxy (missing expected pattern: blocked; missing expected pattern: Hello World!; missing expected pattern: 8080)
- FAIL exit 1: D:\QaaS\_tmp\weak-model-validation\20260608-173406-860-f94dcde5-claude-copilot-gpt-4o-mini-2024-07-18.md classification=quota_blocked weak_validation_eligible=True evidence_class=preferred_weak not_weak_reason=eligible-policy-weak-proxy (missing expected pattern: blocked; missing expected pattern: Hello World!; missing expected pattern: 8080)