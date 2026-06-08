#!/usr/bin/env python3
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from weak_evidence_policy import format_reasons, validate_promotion_airgapped_evidence


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
coverage_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")
packet_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\promotion-packets")

candidate_index_path = coverage_dir / "promotion-candidate-index.json"
summary_path = coverage_dir / "promotion-packet-summary.json"

required_evidence_ids = (
    "template",
    "build",
    "live",
    "airgapped",
)

blocked_markers = (
    "__DOCUMENTED_",
    "__PUBLIC_",
    "__REPLACE_",
    "__QAAS_",
    "blocked_until_",
    "Status: blocked_until_",
    "Links: []",
    "Storages: []",
    "DataSources: []",
    "Sessions: []",
    "Stubs: []",
)

failures: list[str] = []


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"failed to parse JSON {path}: {exc}")
        return None


def validation_passed(value) -> bool:
    return isinstance(value, dict) and value.get("status") == "passed" and value.get("exit_code") == 0


def transcript_path(value) -> str:
    if not isinstance(value, dict):
        return ""
    transcript = value.get("transcript")
    return str(transcript) if transcript else ""


def placeholder_count(artifacts: list[str]) -> int:
    count = 0
    for raw_path in artifacts:
        path = Path(raw_path)
        if not path.exists() or path.suffix.lower() not in {".yaml", ".yml", ".cs"}:
            continue
        text = path.read_text(encoding="utf-8-sig", errors="ignore")
        if any(marker in text for marker in blocked_markers):
            count += 1
    return count


def packet_file_name(manifest_path: Path) -> str:
    relative = manifest_path.parent.name
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", relative).strip("-")
    return f"{safe or 'packet'}.promotion-packet.json"


candidate_index = read_json(candidate_index_path)
candidate_records = {}
candidate_summary = {}
if candidate_index:
    candidate_summary = candidate_index.get("summary") or {}
    for record in candidate_index.get("records") or []:
        manifest = record.get("manifest") if isinstance(record, dict) else None
        if manifest:
            candidate_records[str(manifest)] = record

manifest_paths = sorted(root.rglob("qaas-artifact-manifest.json"))
packet_dir.mkdir(parents=True, exist_ok=True)

manifest_count = 0
executable_manifest_count = 0
packet_count = 0
written_packets: list[str] = []
blocked_executable_count = 0

for manifest_path in manifest_paths:
    manifest_count += 1
    manifest = read_json(manifest_path)
    if not manifest:
        continue
    promotion_state = manifest.get("promotion_state")
    if promotion_state != "executable":
        continue

    executable_manifest_count += 1
    blockers: list[str] = []
    if manifest.get("status") != "executable":
        blockers.append("status is not executable")
    if str(manifest_path) not in candidate_records:
        blockers.append("manifest is missing from promotion-candidate-index")
    if manifest.get("source_only_blockers"):
        blockers.append("source_only_blockers is not empty")
    if not manifest.get("docs_evidence"):
        blockers.append("docs_evidence is empty")
    if not manifest.get("intent_questions"):
        blockers.append("intent_questions is empty")

    gates = manifest.get("dependency_gates")
    if not isinstance(gates, list) or not gates:
        blockers.append("dependency_gates is missing")
        gates = []
    for gate in gates:
        if isinstance(gate, dict) and gate.get("required") is True and gate.get("status") != "passed":
            blockers.append(f"required dependency gate is not passed: {gate.get('gate_id')}")

    artifacts = [str(path) for path in manifest.get("artifacts") or []]
    missing_artifacts = [path for path in artifacts if not Path(path).exists()]
    if missing_artifacts:
        blockers.append(f"artifact path(s) missing: {missing_artifacts}")
    artifact_placeholder_count = placeholder_count(artifacts)
    if artifact_placeholder_count:
        blockers.append(f"{artifact_placeholder_count} artifact(s) contain blocked markers")

    validations = {
        "template": manifest.get("template_validation"),
        "build": manifest.get("build_validation"),
        "live": manifest.get("live_validation"),
        "airgapped": manifest.get("airgapped_validation"),
    }
    validation_evidence = {}
    airgapped_result = validate_promotion_airgapped_evidence(validations["airgapped"], manifest_path)
    for key in required_evidence_ids:
        value = validations[key]
        if key == "airgapped":
            if not airgapped_result.weak_validation_passed:
                blockers.append(
                    "airgapped_validation is not passed with policy-eligible live weak transcript: "
                    f"{format_reasons(airgapped_result)}"
                )
            validation_evidence[key] = transcript_path(value)
        else:
            if not validation_passed(value):
                blockers.append(f"{key}_validation is not passed")
            transcript = transcript_path(value)
            if not transcript or not Path(transcript).exists():
                blockers.append(f"{key}_validation transcript is missing")
            validation_evidence[key] = transcript

    if blockers:
        blocked_executable_count += 1
        failures.append(f"executable manifest cannot produce promotion packet: {manifest_path}: {', '.join(blockers)}")
        continue

    packet = {
        "schema_version": 1,
        "packet_id": manifest_path.parent.name,
        "manifest": str(manifest_path),
        "campaign_id": manifest.get("campaign_id"),
        "source_repository": manifest.get("source_repository"),
        "promotion_state": "executable",
        "status": "executable",
        "artifacts": artifacts,
        "docs_evidence": manifest.get("docs_evidence"),
        "intent_questions": manifest.get("intent_questions"),
        "dependency_gates": gates,
        "validation_evidence": validation_evidence,
        "validation_results": validations,
        "promotion_requirements": manifest.get("promotion_requirements"),
        "source_only_blockers": [],
        "placeholder_artifact_count": 0,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    packet_path = packet_dir / packet_file_name(manifest_path)
    packet_path.write_text(json.dumps(packet, indent=2), encoding="utf-8")
    packet_count += 1
    written_packets.append(str(packet_path))

if not manifest_paths:
    failures.append(f"no manifests found under {root}")

promotable_candidate_count = int(candidate_summary.get("promotable_candidate_count", 0) or 0)
candidate_manifest_count = int(candidate_summary.get("manifest_count", 0) or 0)
if candidate_index and candidate_manifest_count != manifest_count:
    failures.append("promotion-candidate-index manifest_count does not match generated manifest count")

status = "ready" if packet_count > 0 and blocked_executable_count == 0 else "blocked"
summary = {
    "schema_version": 1,
    "promotion_packet_status": status,
    "completion_ready": False,
    "manifest_count": manifest_count,
    "promotion_candidate_index": str(candidate_index_path),
    "promotable_candidate_count": promotable_candidate_count,
    "executable_manifest_count": executable_manifest_count,
    "packet_count": packet_count,
    "blocked_executable_count": blocked_executable_count,
    "packet_dir": str(packet_dir),
    "packets": written_packets,
    "required_packet_evidence": list(required_evidence_ids),
    "blocked_reason": (
        "No executable manifests or promotable candidates have complete template/build/live/airgapped evidence."
        if packet_count == 0
        else ""
    ),
    "candidate_summary": candidate_summary,
}
coverage_dir.mkdir(parents=True, exist_ok=True)
summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(
    "Promotion packet check passed with "
    f"promotion_packet_status={status}; "
    f"packet_count={packet_count}; "
    f"promotable_candidate_count={promotable_candidate_count}."
)
print(f"Summary: {summary_path}")
