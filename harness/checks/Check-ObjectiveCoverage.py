#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


skill_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Users\eldar\.codex\skills\zappa-dont-cry")
harness_root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tools\zappa-harness")
fixture_path = Path(sys.argv[3]) if len(sys.argv) > 3 else harness_root / "fixtures" / "objective-capability-map.json"
out_dir = Path(sys.argv[4]) if len(sys.argv) > 4 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower())


failures: list[str] = []
allowed_statuses = {
    "covered_by_contract",
    "structural_artifacts_blocked_until_executable_evidence",
    "blocked_by_hosted_quota",
    "blocked_until_live_and_executable_evidence",
}

if not fixture_path.exists():
    failures.append(f"missing fixture: {fixture_path}")
else:
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

    if fixture.get("schema_version") != 1:
        failures.append("objective capability fixture must have schema_version 1")

    capabilities = fixture.get("capabilities", [])
    if len(capabilities) < 12:
        failures.append("objective capability fixture must cover at least 12 capabilities")

    skill_texts: dict[str, str] = {}
    for skill_md in sorted(skill_root.glob("*/SKILL.md")):
        skill_texts[skill_md.parent.name] = normalize(skill_md.read_text(encoding="utf-8"))

    if len(skill_texts) < 11:
        failures.append(f"expected at least 11 zappa skills, found {len(skill_texts)}")

    harness_script = harness_root / "Invoke-ZappaHarness.ps1"
    harness_text = normalize(harness_script.read_text(encoding="utf-8")) if harness_script.exists() else ""
    if not harness_text:
        failures.append(f"missing harness script: {harness_script}")

    def harness_emits_result(result_name: str) -> bool:
        normalized = normalize(result_name)
        if normalized in harness_text:
            return True
        if normalized.startswith("artifact-manifests-") and "artifact-manifests-$target" in harness_text:
            return True
        return False

    seen_ids: set[str] = set()
    coverage_records = []
    blocked_ids = set()

    for capability in capabilities:
        cid = capability.get("id")
        if not cid:
            failures.append("capability missing id")
            continue
        if cid in seen_ids:
            failures.append(f"duplicate capability id: {cid}")
        seen_ids.add(cid)

        status = capability.get("status")
        if status not in allowed_statuses:
            failures.append(f"{cid} has invalid status: {status}")
        if status != "covered_by_contract":
            blocked_ids.add(cid)

        required_skills = capability.get("required_skills", [])
        if not required_skills:
            failures.append(f"{cid} has no required_skills")

        combined_skill_text = ""
        for skill in required_skills:
            if skill not in skill_texts:
                failures.append(f"{cid} references missing skill: {skill}")
            else:
                combined_skill_text += "\n" + skill_texts[skill]

        for term in capability.get("required_terms", []):
            if normalize(term) not in combined_skill_text:
                failures.append(f"{cid} missing required term in required skills: {term}")

        result_names = capability.get("harness_result_names", [])
        if not result_names:
            failures.append(f"{cid} has no harness_result_names")
        for result_name in result_names:
            if not harness_emits_result(result_name):
                failures.append(f"{cid} references harness result not emitted by Invoke-ZappaHarness.ps1: {result_name}")

        coverage_records.append(
            {
                "id": cid,
                "status": status,
                "required_skills": required_skills,
                "harness_result_names": result_names,
            }
        )

    expected_blocked = {
        "top_250_repositories",
        "weak_model_validation",
        "adversarial_weak_model_validation",
        "fail_closed_completion",
    }
    missing_blocked = expected_blocked - blocked_ids
    if missing_blocked:
        failures.append(f"objective map must keep these capabilities blocked until stronger evidence exists: {sorted(missing_blocked)}")
    capability_by_id = {record["id"]: record for record in coverage_records}
    weak_model_record = capability_by_id.get("weak_model_validation")
    if not weak_model_record:
        failures.append("objective map missing weak_model_validation capability")
    elif "weak-adversarial-scenarios" not in weak_model_record.get("harness_result_names", []):
        failures.append("weak_model_validation must reference harness result: weak-adversarial-scenarios")
    if "adversarial_weak_model_validation" not in capability_by_id:
        failures.append("objective map missing adversarial_weak_model_validation capability")

    out_dir.mkdir(parents=True, exist_ok=True)
    record_path = out_dir / "objective-capability-coverage.json"
    record = {
        "schema_version": 1,
        "objective_completion_status": "not_complete",
        "completion_blockers": sorted(blocked_ids),
        "capability_count": len(coverage_records),
        "capabilities": coverage_records,
    }
    record_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Objective capability coverage check passed for {len(coverage_records)} capabilities.")
print(f"Coverage record: {record_path}")
