#!/usr/bin/env python3
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from weak_evidence_policy import format_reasons, validate_promotion_airgapped_evidence


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")

required_validation_fields = ("template_validation", "build_validation", "live_validation")
weak_model_blockers = {"live-airgapped-weak-model-not-passed"}
required_promotion_evidence = {
    "Public API, CLI, or runtime contract",
    "Public input and expected-output contract",
    "Public dependency/stub contract",
    "Cleanup contract",
    "QaaS template validation result",
    "C# build result when code artifacts exist",
    "Live QaaS run/act/assert result when dependency gates are ready",
    "Airgapped weak-model validation transcript",
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def is_passed_validation(value) -> bool:
    return isinstance(value, dict) and value.get("status") == "passed" and value.get("exit_code") == 0


def artifact_has_placeholder(path: Path) -> bool:
    if path.suffix.lower() not in {".yaml", ".yml", ".cs"} or not path.exists():
        return False
    text = path.read_text(encoding="utf-8-sig", errors="ignore")
    non_comment_text = "\n".join(
        line
        for line in text.splitlines()
        if not line.lstrip().startswith(("#", "//"))
    )
    markers = (
        "__DOCUMENTED_",
        "__PUBLIC_",
        "__REPLACE_",
        "blocked_until_",
        "Status: blocked_until_",
    )
    return any(marker in non_comment_text for marker in markers)


failures: list[str] = []
records = []
summary = {
    "manifest_count": 0,
    "executable_manifest_count": 0,
    "deterministic_executable_candidate_count": 0,
    "weak_blocked_deterministic_candidate_count": 0,
    "source_scope_blocked_deterministic_candidate_count": 0,
    "promotable_candidate_count": 0,
    "blocked_manifest_count": 0,
    "blocked_by_dependency_gates_count": 0,
    "blocked_by_source_only_count": 0,
    "missing_template_validation_count": 0,
    "missing_build_validation_count": 0,
    "missing_live_validation_count": 0,
    "missing_airgapped_validation_count": 0,
    "placeholder_artifact_count": 0,
}

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    summary["manifest_count"] += 1
    try:
        manifest = read_json(manifest_path)
    except Exception as exc:
        failures.append(f"manifest parse failed: {manifest_path}: {exc}")
        continue

    promotion_state = manifest.get("promotion_state")
    status = manifest.get("status")
    source_repository = manifest.get("source_repository")
    dependency_gates = manifest.get("dependency_gates")
    source_only_blockers = manifest.get("source_only_blockers")
    promotion_requirements = manifest.get("promotion_requirements")

    if not source_repository:
        failures.append(f"manifest missing source_repository: {manifest_path}")
    if not isinstance(dependency_gates, list) or not dependency_gates:
        failures.append(f"manifest missing dependency_gates: {manifest_path}")
        dependency_gates = []
    if not isinstance(source_only_blockers, list):
        failures.append(f"manifest missing source_only_blockers list: {manifest_path}")
        source_only_blockers = []
    if not isinstance(promotion_requirements, dict):
        failures.append(f"manifest missing promotion_requirements: {manifest_path}")
        promotion_requirements = {}
    else:
        evidence = set(promotion_requirements.get("required_evidence") or [])
        missing_evidence = sorted(required_promotion_evidence - evidence)
        if missing_evidence:
            failures.append(f"manifest promotion_requirements missing {missing_evidence}: {manifest_path}")

    required_gates = [gate for gate in dependency_gates if isinstance(gate, dict) and gate.get("required") is True]
    blocked_gates = [gate for gate in required_gates if gate.get("status") == "blocked"]
    failed_gates = [gate for gate in required_gates if gate.get("status") == "failed"]
    unready_gates = [gate for gate in required_gates if gate.get("status") not in {"ready", "passed"}]
    missing_gate_evidence = [
        gate.get("gate_id")
        for gate in required_gates
        if gate.get("status") in {"ready", "passed"}
        and (not isinstance(gate.get("evidence"), list) or not gate.get("evidence"))
    ]

    if missing_gate_evidence:
        failures.append(f"ready/passed gates lack evidence {missing_gate_evidence}: {manifest_path}")
    for gate in blocked_gates + failed_gates:
        if not gate.get("blocked_reason"):
            failures.append(f"blocked/failed gate missing blocked_reason {gate.get('gate_id')}: {manifest_path}")

    validations_passed = {field: is_passed_validation(manifest.get(field)) for field in required_validation_fields}
    airgapped_result = validate_promotion_airgapped_evidence(manifest.get("airgapped_validation"), manifest_path)
    airgapped_passed = airgapped_result.weak_validation_passed
    airgapped = manifest.get("airgapped_validation")
    if isinstance(airgapped, dict) and airgapped.get("status") == "passed" and not airgapped_passed:
        failures.append(
            "airgapped_validation is passed but not policy-eligible live weak evidence "
            f"for {manifest_path}: {format_reasons(airgapped_result)}"
        )

    artifacts = [Path(path) for path in manifest.get("artifacts", [])]
    placeholder_artifacts = [str(path) for path in artifacts if artifact_has_placeholder(path)]
    summary["placeholder_artifact_count"] += len(placeholder_artifacts)

    if not validations_passed["template_validation"]:
        summary["missing_template_validation_count"] += 1
    if not validations_passed["build_validation"]:
        summary["missing_build_validation_count"] += 1
    if not validations_passed["live_validation"]:
        summary["missing_live_validation_count"] += 1
    if not airgapped_passed:
        summary["missing_airgapped_validation_count"] += 1

    source_blocker_ids = [
        str(blocker.get("blocker_id"))
        for blocker in source_only_blockers
        if isinstance(blocker, dict) and blocker.get("blocker_id")
    ]
    unready_gate_ids = [
        str(gate.get("gate_id"))
        for gate in unready_gates
        if isinstance(gate, dict) and gate.get("gate_id")
    ]
    only_airgapped_gate_unready = bool(unready_gate_ids) and set(unready_gate_ids) <= {"airgapped-validation"}
    deterministic_executable_candidate = (
        all(validations_passed.values())
        and not placeholder_artifacts
        and only_airgapped_gate_unready
        and not airgapped_passed
    )
    weak_only_deterministic_candidate = (
        deterministic_executable_candidate
        and bool(source_blocker_ids)
        and set(source_blocker_ids) <= weak_model_blockers
    )
    source_scope_blocked_deterministic_candidate = (
        deterministic_executable_candidate
        and not weak_only_deterministic_candidate
        and bool(source_blocker_ids)
    )
    if deterministic_executable_candidate:
        summary["deterministic_executable_candidate_count"] += 1
    if weak_only_deterministic_candidate:
        summary["weak_blocked_deterministic_candidate_count"] += 1
    if source_scope_blocked_deterministic_candidate:
        summary["source_scope_blocked_deterministic_candidate_count"] += 1

    if promotion_state == "executable":
        summary["executable_manifest_count"] += 1
        missing = [field for field, passed in validations_passed.items() if not passed]
        if not airgapped_passed:
            missing.append("airgapped_validation")
        if unready_gates:
            missing.append("dependency_gates")
        if placeholder_artifacts:
            missing.append("placeholder_artifacts")
        if missing:
            failures.append(f"executable manifest missing promotion evidence {missing}: {manifest_path}")
        candidate_state = "executable_validated" if not missing else "invalid_executable"
    else:
        summary["blocked_manifest_count"] += 1
        if promotion_state != "blocked":
            failures.append(f"non-executable manifest must use promotion_state blocked: {manifest_path}")
        if not manifest.get("blocked_reason"):
            failures.append(f"blocked manifest missing blocked_reason: {manifest_path}")
        if source_only_blockers:
            summary["blocked_by_source_only_count"] += 1
        if weak_only_deterministic_candidate:
            summary["blocked_by_dependency_gates_count"] += 1
            candidate_state = "deterministic_executable_weak_blocked"
        elif source_scope_blocked_deterministic_candidate:
            summary["blocked_by_dependency_gates_count"] += 1
            candidate_state = "deterministic_executable_source_scope_blocked"
        elif blocked_gates or failed_gates or unready_gates:
            summary["blocked_by_dependency_gates_count"] += 1
            candidate_state = "blocked_by_dependency_gates"
        elif all(validations_passed.values()) and airgapped_passed and not placeholder_artifacts:
            summary["promotable_candidate_count"] += 1
            candidate_state = "promotable_candidate"
        else:
            candidate_state = "blocked_by_validation_evidence"

    records.append(
        {
            "manifest": str(manifest_path),
            "campaign_id": manifest.get("campaign_id"),
            "source_repository": source_repository,
            "status": status,
            "promotion_state": promotion_state,
            "candidate_state": candidate_state,
            "required_gate_count": len(required_gates),
            "blocked_gate_count": len(blocked_gates),
            "failed_gate_count": len(failed_gates),
            "unready_gate_count": len(unready_gates),
            "unready_gate_ids": unready_gate_ids,
            "source_only_blocker_count": len(source_only_blockers),
            "source_only_blockers": source_blocker_ids,
            "template_validation_passed": validations_passed["template_validation"],
            "build_validation_passed": validations_passed["build_validation"],
            "live_validation_passed": validations_passed["live_validation"],
            "airgapped_validation_passed": airgapped_passed,
            "deterministic_executable_candidate": deterministic_executable_candidate,
            "weak_only_deterministic_candidate": weak_only_deterministic_candidate,
            "source_scope_blocked_deterministic_candidate": source_scope_blocked_deterministic_candidate,
            "airgapped_evidence_class": airgapped_result.evidence_class,
            "airgapped_evidence_model": airgapped_result.model,
            "airgapped_evidence_reason": format_reasons(airgapped_result),
            "placeholder_artifact_count": len(placeholder_artifacts),
        }
    )

if summary["manifest_count"] == 0:
    failures.append(f"no manifests found under {root}")

out_dir.mkdir(parents=True, exist_ok=True)
record_path = out_dir / "promotion-candidate-index.json"
record = {
    "schema_version": 1,
    "promotion_index_status": "blocked",
    "completion_ready": False,
    "summary": summary,
    "records": records,
}
record_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(
    "Promotion candidate index check passed for "
    f"{summary['manifest_count']} manifests; "
    f"{summary['promotable_candidate_count']} promotable candidates; "
    f"{summary['executable_manifest_count']} executable manifests."
)
print(f"Record: {record_path}")
