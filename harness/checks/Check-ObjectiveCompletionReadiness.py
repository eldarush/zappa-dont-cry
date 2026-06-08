#!/usr/bin/env python3
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from weak_evidence_policy import format_reasons, validate_promotion_airgapped_evidence


generated_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
coverage_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage\objective-capability-coverage.json")
blockers_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\blockers")

failures: list[str] = []


def read_json(path: Path):
    if not path.exists():
        failures.append(f"missing required JSON file: {path}")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"failed to parse {path}: {exc}")
        return None


coverage = read_json(coverage_path)
promotion_index = read_json(coverage_path.parent / "promotion-candidate-index.json")
promotion_packet = read_json(coverage_path.parent / "promotion-packet-summary.json")
top_repo_triage = read_json(coverage_path.parent / "top-repo-promotion-triage.json")
preferred_live = read_json(blockers_dir / "airgapped-live-latest.json")
fallback_live = read_json(blockers_dir / "copilot-fallback-latest.json")
scenario_live = read_json(blockers_dir / "weak-scenario-output-latest.json")
adversarial_live = read_json(blockers_dir / "weak-adversarial-output-latest.json")

manifest_count = 0
executable_count = 0
blocked_count = 0
executable_missing_evidence: list[str] = []

for manifest_path in sorted(generated_root.rglob("qaas-artifact-manifest.json")):
    manifest_count += 1
    manifest = read_json(manifest_path)
    if not manifest:
        continue
    if manifest.get("promotion_state") == "executable":
        executable_count += 1
        for field in ("template_validation", "build_validation", "live_validation"):
            validation = manifest.get(field)
            if not isinstance(validation, dict) or validation.get("status") != "passed" or validation.get("exit_code") != 0:
                executable_missing_evidence.append(f"{manifest_path} missing passed {field}")
        airgapped = manifest.get("airgapped_validation")
        airgapped_result = validate_promotion_airgapped_evidence(airgapped, manifest_path)
        if not airgapped_result.weak_validation_passed:
            executable_missing_evidence.append(
                f"{manifest_path} missing policy-eligible live weak airgapped_validation: "
                f"{format_reasons(airgapped_result)}"
            )
    else:
        blocked_count += 1
        if manifest.get("promotion_state") != "blocked":
            failures.append(f"non-executable manifest must fail closed as blocked: {manifest_path}")
        if not manifest.get("blocked_reason"):
            failures.append(f"blocked manifest missing blocked_reason: {manifest_path}")
        airgapped = manifest.get("airgapped_validation")
        if isinstance(airgapped, dict) and airgapped.get("status") == "passed":
            airgapped_result = validate_promotion_airgapped_evidence(airgapped, manifest_path)
            if not airgapped_result.weak_validation_passed:
                failures.append(
                    f"blocked manifest claims passed airgapped_validation without policy-eligible live weak evidence: "
                    f"{manifest_path}: {format_reasons(airgapped_result)}"
                )

if manifest_count == 0:
    failures.append(f"no generated manifests found under {generated_root}")

coverage_blockers = set()
if coverage:
    if coverage.get("objective_completion_status") != "not_complete":
        failures.append("objective coverage must remain not_complete until all blockers are cleared")
    coverage_blockers = set(coverage.get("completion_blockers") or [])
    for required_blocker in ("top_250_repositories", "weak_model_validation", "adversarial_weak_model_validation", "fail_closed_completion"):
        if required_blocker not in coverage_blockers:
            failures.append(f"objective coverage missing required blocker: {required_blocker}")

promotion_summary = {}
if promotion_index:
    if promotion_index.get("promotion_index_status") != "blocked":
        failures.append("promotion candidate index must remain blocked until executable evidence exists")
    if promotion_index.get("completion_ready") is not False:
        failures.append("promotion candidate index must not report completion_ready")
    promotion_summary = promotion_index.get("summary") or {}
    if promotion_summary.get("manifest_count") != manifest_count:
        failures.append("promotion candidate index manifest_count does not match generated manifest count")
    if promotion_summary.get("executable_manifest_count") != executable_count:
        failures.append("promotion candidate index executable_manifest_count does not match generated manifest count")

deterministic_executable_count = int(promotion_summary.get("deterministic_executable_candidate_count") or 0)
weak_blocked_deterministic_count = int(promotion_summary.get("weak_blocked_deterministic_candidate_count") or 0)
source_scope_blocked_deterministic_count = int(promotion_summary.get("source_scope_blocked_deterministic_candidate_count") or 0)

promotion_packet_summary = {}
if promotion_packet:
    if promotion_packet.get("promotion_packet_status") != "blocked":
        failures.append("promotion packet summary must remain blocked until executable packets exist")
    if promotion_packet.get("completion_ready") is not False:
        failures.append("promotion packet summary must not report completion_ready")
    promotion_packet_summary = promotion_packet
    if promotion_packet_summary.get("manifest_count") != manifest_count:
        failures.append("promotion packet manifest_count does not match generated manifest count")
    if promotion_packet_summary.get("executable_manifest_count") != executable_count:
        failures.append("promotion packet executable_manifest_count does not match generated manifest count")

top_repo_triage_summary = {}
if top_repo_triage:
    if top_repo_triage.get("triage_status") != "blocked_until_selected_contracts_are_promoted":
        failures.append("top-repo promotion triage must remain blocked until selected contracts are promoted")
    if top_repo_triage.get("completion_ready") is not False:
        failures.append("top-repo promotion triage must not report completion_ready")
    top_repo_triage_summary = {
        "triage_status": top_repo_triage.get("triage_status"),
        "completion_ready": top_repo_triage.get("completion_ready"),
        "contract_count": top_repo_triage.get("contract_count"),
        "manifest_count": top_repo_triage.get("manifest_count"),
        "high_potential_count": top_repo_triage.get("high_potential_count"),
        "contract_review_priority_count": top_repo_triage.get("contract_review_priority_count"),
        "by_triage_state": top_repo_triage.get("by_triage_state") or {},
    }
    if top_repo_triage.get("manifest_count") != 250:
        failures.append("top-repo promotion triage must account for 250 top-repo manifests")
    if int(top_repo_triage.get("high_potential_count") or 0) == 0:
        completion_blocker = "no_top_repo_promotion_candidates_ranked"
    else:
        completion_blocker = ""
else:
    completion_blocker = "top_repo_promotion_triage_missing"

preferred_live_passed = bool(preferred_live and preferred_live.get("weak_validation_passed") is True and preferred_live.get("dry_run") is False)
fallback_all_passed = bool(fallback_live and fallback_live.get("weak_validation_passed") is True and fallback_live.get("dry_run") is False)
live_weak_ready = preferred_live_passed

if preferred_live:
    if preferred_live.get("validation_kind") != "live_model_execution":
        failures.append("preferred live weak record must use validation_kind live_model_execution")
    if preferred_live.get("dry_run") is not False:
        failures.append("preferred live weak record must not be a dry run")

if fallback_live:
    if fallback_live.get("validation_kind") != "fallback_live_model_execution":
        failures.append("fallback weak record must use validation_kind fallback_live_model_execution")
    if fallback_live.get("dry_run") is not False:
        failures.append("fallback weak record must not be a dry run")

scenario_live_ready = bool(scenario_live and scenario_live.get("weak_validation_passed") is True and scenario_live.get("dry_run") is False)
if scenario_live:
    if scenario_live.get("validation_kind") != "live_scenario_model_execution":
        failures.append("weak scenario output record must use validation_kind live_scenario_model_execution")
    if scenario_live.get("dry_run") is not False:
        failures.append("weak scenario output record must not be a dry run")

adversarial_live_ready = bool(adversarial_live and adversarial_live.get("weak_validation_passed") is True and adversarial_live.get("dry_run") is False)
if adversarial_live:
    if adversarial_live.get("validation_kind") != "live_adversarial_model_execution":
        failures.append("weak adversarial output record must use validation_kind live_adversarial_model_execution")
    if adversarial_live.get("dry_run") is not False:
        failures.append("weak adversarial output record must not be a dry run")

if executable_missing_evidence:
    failures.extend(executable_missing_evidence)

completion_blockers: list[str] = []
if executable_count == 0:
    completion_blockers.append("no_policy_executable_qaas_manifests")
    if deterministic_executable_count == 0:
        completion_blockers.append("no_deterministic_executable_qaas_manifests")
    else:
        completion_blockers.append("deterministic_executable_qaas_manifests_not_policy_executable")
        if weak_blocked_deterministic_count > 0:
            completion_blockers.append("deterministic_executable_qaas_manifests_waiting_on_live_weak_model")
        if source_scope_blocked_deterministic_count > 0:
            completion_blockers.append("deterministic_executable_qaas_manifests_waiting_on_selected_scope")
if promotion_summary.get("promotable_candidate_count", 0) == 0:
    completion_blockers.append("no_promotable_qaas_manifests")
if promotion_summary.get("blocked_by_dependency_gates_count", 0) > 0:
    completion_blockers.append("promotion_dependency_gates_blocked")
if promotion_summary.get("blocked_by_source_only_count", 0) > 0:
    completion_blockers.append("promotion_source_only_blocked")
if promotion_summary.get("missing_template_validation_count", 0) > 0:
    completion_blockers.append("promotion_template_validation_missing")
if promotion_summary.get("missing_build_validation_count", 0) > 0:
    completion_blockers.append("promotion_build_validation_missing")
if promotion_summary.get("missing_live_validation_count", 0) > 0:
    completion_blockers.append("promotion_live_validation_missing")
if promotion_summary.get("missing_airgapped_validation_count", 0) > 0:
    completion_blockers.append("promotion_airgapped_validation_missing")
if promotion_packet_summary.get("packet_count", 0) == 0:
    completion_blockers.append("no_executable_promotion_packets")
if promotion_packet_summary.get("promotion_packet_status") == "blocked":
    completion_blockers.append("promotion_packets_blocked")
if completion_blocker:
    completion_blockers.append(completion_blocker)
if not live_weak_ready:
    completion_blockers.append("live_weak_model_validation_not_passed")
if not scenario_live_ready:
    completion_blockers.append("live_weak_scenario_outputs_not_passed")
if not adversarial_live_ready:
    completion_blockers.append("live_adversarial_weak_outputs_not_passed")
if coverage_blockers:
    completion_blockers.extend(sorted(coverage_blockers))

completion_readiness = "ready" if not completion_blockers and executable_count == manifest_count and manifest_count > 0 else "blocked"
if completion_readiness != "blocked":
    failures.append("completion readiness unexpectedly became ready without an explicit final audit")

blockers_dir.mkdir(parents=True, exist_ok=True)
record_path = blockers_dir / "objective-completion-readiness.json"
record = {
    "schema_version": 1,
    "structural_status": "passed",
    "completion_readiness": completion_readiness,
    "manifest_count": manifest_count,
    "blocked_manifest_count": blocked_count,
    "executable_manifest_count": executable_count,
    "policy_executable_manifest_count": executable_count,
    "deterministic_executable_manifest_count": deterministic_executable_count,
    "weak_blocked_deterministic_manifest_count": weak_blocked_deterministic_count,
    "source_scope_blocked_deterministic_manifest_count": source_scope_blocked_deterministic_count,
    "live_weak_model_ready": live_weak_ready,
    "fallback_weak_model_ready": fallback_all_passed,
    "completion_blockers": sorted(set(completion_blockers)),
    "coverage_record": str(coverage_path),
    "promotion_candidate_index": str(coverage_path.parent / "promotion-candidate-index.json"),
    "promotion_packet_summary": str(coverage_path.parent / "promotion-packet-summary.json"),
    "top_repo_promotion_triage": str(coverage_path.parent / "top-repo-promotion-triage.json"),
    "top_repo_promotion_triage_summary": top_repo_triage_summary,
    "preferred_live_record": str(blockers_dir / "airgapped-live-latest.json"),
    "fallback_live_record": str(blockers_dir / "copilot-fallback-latest.json"),
    "weak_scenario_output_record": str(blockers_dir / "weak-scenario-output-latest.json"),
    "weak_adversarial_output_record": str(blockers_dir / "weak-adversarial-output-latest.json"),
}
record_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print("Objective completion readiness check passed with completion_readiness=blocked.")
print(f"Record: {record_path}")
