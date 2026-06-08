#!/usr/bin/env python3
import json
import re
import sys
from collections import Counter
from pathlib import Path


candidate_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates")
coverage_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")
expected_count = int(sys.argv[3]) if len(sys.argv) > 3 else 8
min_deterministic_ready = int(sys.argv[4]) if len(sys.argv) > 4 else 6

ADVISORY_BLOCKERS = {"httpstatus-docs-inconsistency-recorded"}
WEAK_BLOCKERS = {"live-airgapped-weak-model-not-passed"}
SCOPE_BLOCKERS = {
    "deno-broad-runtime-coverage-not-selected",
    "spring-boot-broad-runtime-coverage-not-selected",
    "crawl4ai-health-body-contract-not-selected",
    "crawl4ai-crawl-endpoint-not-promoted",
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def passed_validation(value) -> bool:
    return isinstance(value, dict) and value.get("status") == "passed" and value.get("exit_code") == 0


def gate_map(manifest: dict) -> dict[str, dict]:
    result = {}
    for gate in manifest.get("dependency_gates") or []:
        if isinstance(gate, dict) and gate.get("gate_id"):
            result[str(gate["gate_id"])] = gate
    return result


def gate_passed(gates: dict[str, dict], gate_id: str) -> bool:
    gate = gates.get(gate_id)
    return isinstance(gate, dict) and gate.get("status") == "passed" and bool(gate.get("evidence"))


def blocker_ids(manifest: dict) -> list[str]:
    return [
        str(blocker.get("blocker_id"))
        for blocker in manifest.get("source_only_blockers") or []
        if isinstance(blocker, dict) and blocker.get("blocker_id")
    ]


def advisory_ids(manifest: dict) -> list[str]:
    return [
        str(advisory.get("advisory_id"))
        for advisory in manifest.get("validation_advisories") or []
        if isinstance(advisory, dict) and advisory.get("advisory_id")
    ]


def uses_builtin_httpstatus_assertion(manifest_path: Path, manifest: dict) -> bool:
    candidate_dir = manifest_path.parent
    paths = []
    for artifact in manifest.get("artifacts") or []:
        if isinstance(artifact, str) and artifact.lower().endswith((".yaml", ".yml")):
            paths.append(Path(artifact))
    default_yaml = candidate_dir / "test.qaas.yaml"
    if default_yaml.exists():
        paths.append(default_yaml)

    seen: set[Path] = set()
    for path in paths:
        resolved = path if path.is_absolute() else candidate_dir / path
        if resolved in seen or not resolved.exists():
            continue
        seen.add(resolved)
        text = resolved.read_text(encoding="utf-8-sig")
        if re.search(r"(?m)^\s*Assertion:\s*HttpStatus\s*$", text):
            return True
    return False


def classify_blocker(blocker_id: str) -> str:
    if blocker_id in WEAK_BLOCKERS:
        return "weak_model"
    if blocker_id in SCOPE_BLOCKERS:
        return "selected_scope"
    return "deterministic_evidence"


failures: list[str] = []
index_path = candidate_root / "selected-candidate-index.json"
if not index_path.exists():
    print(f"ERROR: missing selected candidate index: {index_path}", file=sys.stderr)
    sys.exit(1)

index = read_json(index_path)
records = []
class_counts: Counter[str] = Counter()
blocker_class_counts: Counter[str] = Counter()
deterministic_ready_count = 0
airgapped_missing_count = 0
docs_advisory_record_count = 0
qaas_validation_missing_count = 0
scope_blocked_count = 0

index_records = index.get("records")
if not isinstance(index_records, list):
    failures.append(f"selected candidate index missing records list: {index_path}")
    index_records = []

if expected_count >= 0 and len(index_records) != expected_count:
    failures.append(f"expected {expected_count} selected candidates, found {len(index_records)}")

for record in index_records:
    manifest_path = Path(str(record.get("manifest") or ""))
    repository = str(record.get("repository") or "")
    if not manifest_path.exists():
        failures.append(f"selected candidate manifest missing for {repository}: {manifest_path}")
        continue

    manifest = read_json(manifest_path)
    gates = gate_map(manifest)
    blockers = blocker_ids(manifest)
    advisories = advisory_ids(manifest)
    classes = sorted({classify_blocker(blocker_id) for blocker_id in blockers})
    for blocker_class in classes:
        blocker_class_counts[blocker_class] += 1

    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation")) and gate_passed(gates, "cleanup-contract")
    template_live_passed = (
        passed_validation(manifest.get("build_validation"))
        and passed_validation(manifest.get("template_validation"))
        and passed_validation(manifest.get("live_validation"))
        and passed_validation(manifest.get("selected_candidate_qaas_validation"))
        and gate_passed(gates, "qaas-template")
        and gate_passed(gates, "qaas-live-act-assert")
    )
    deterministic_ready = lifecycle_passed and template_live_passed

    if deterministic_ready:
        deterministic_ready_count += 1
        stale_deterministic = [blocker_id for blocker_id in blockers if classify_blocker(blocker_id) == "deterministic_evidence"]
        if stale_deterministic:
            failures.append(
                f"deterministically ready selected candidate still has deterministic evidence blockers "
                f"{stale_deterministic}: {manifest_path}"
            )
    else:
        qaas_validation_missing_count += 1

    has_weak_blocker = bool(WEAK_BLOCKERS & set(blockers))
    if has_weak_blocker:
        airgapped_missing_count += 1
    has_docs_advisory = bool(ADVISORY_BLOCKERS & set(advisories))
    has_docs_advisory_blocker = bool(ADVISORY_BLOCKERS & set(blockers))
    uses_httpstatus_contract = uses_builtin_httpstatus_assertion(manifest_path, manifest)
    tracks_httpstatus_docs_contract = uses_httpstatus_contract or has_docs_advisory or has_docs_advisory_blocker
    if has_docs_advisory:
        docs_advisory_record_count += 1
    if SCOPE_BLOCKERS & set(blockers):
        scope_blocked_count += 1

    if tracks_httpstatus_docs_contract and deterministic_ready and has_docs_advisory_blocker:
        failures.append(
            f"deterministically ready selected candidate must move HttpStatus docs inconsistency "
            f"to validation_advisories: {manifest_path}"
        )
    if tracks_httpstatus_docs_contract and deterministic_ready and not has_docs_advisory:
        failures.append(f"deterministically ready selected candidate missing HttpStatus validation advisory: {manifest_path}")
    if tracks_httpstatus_docs_contract and not deterministic_ready and not has_docs_advisory_blocker:
        failures.append(f"pre-QaaS selected candidate must keep HttpStatus docs inconsistency as source blocker: {manifest_path}")

    if manifest.get("promotion_state") != "blocked":
        failures.append(f"selected candidate readiness only accepts blocked promotion_state: {manifest_path}")
    if manifest.get("airgapped_validation", {}).get("status") == "passed":
        failures.append(f"selected candidate cannot mark airgapped passed in readiness check: {manifest_path}")
    if deterministic_ready and not has_weak_blocker:
        failures.append(f"deterministically ready selected candidate must still expose weak-model blocker: {manifest_path}")

    if not deterministic_ready:
        readiness_class = "deterministic_evidence_blocked"
    elif any(classify_blocker(blocker_id) == "selected_scope" for blocker_id in blockers):
        readiness_class = "airgapped_plus_scope_blocked"
    elif blockers == ["live-airgapped-weak-model-not-passed"]:
        readiness_class = "airgapped_only_blocked"
    else:
        readiness_class = "airgapped_blocked"

    class_counts[readiness_class] += 1
    records.append(
        {
            "repository": repository,
            "rank": record.get("rank"),
            "manifest": str(manifest_path),
            "promotion_state": manifest.get("promotion_state"),
            "readiness_class": readiness_class,
            "deterministic_ready": deterministic_ready,
            "lifecycle_passed": lifecycle_passed,
            "template_live_passed": template_live_passed,
            "airgapped_missing": has_weak_blocker,
            "uses_builtin_httpstatus_assertion": uses_httpstatus_contract,
            "tracks_httpstatus_docs_contract": tracks_httpstatus_docs_contract,
            "docs_advisory_recorded": has_docs_advisory,
            "docs_advisory_blocking": has_docs_advisory_blocker,
            "scope_blocked": bool(SCOPE_BLOCKERS & set(blockers)),
            "source_only_blockers": blockers,
            "validation_advisories": advisories,
            "blocker_classes": classes,
            "note": (
                "HttpStatus docs inconsistency is blocking before QaaS validation and non-blocking after "
                "schema-derived template/live validation"
                if tracks_httpstatus_docs_contract
                else "No built-in HttpStatus docs inconsistency tracking is required for this candidate"
            ),
        }
    )

if deterministic_ready_count < min_deterministic_ready:
    failures.append(
        f"expected at least {min_deterministic_ready} selected candidates with lifecycle/template/live evidence, "
        f"found {deterministic_ready_count}"
    )

records.sort(key=lambda item: (not item["deterministic_ready"], item["rank"] or 9999, item["repository"]))
coverage_dir.mkdir(parents=True, exist_ok=True)
record_path = coverage_dir / "selected-candidate-promotion-readiness.json"
summary = {
    "schema_version": 1,
    "readiness_status": "blocked_until_airgapped_or_scope",
    "completion_ready": False,
    "selected_candidate_index": str(index_path),
    "selected_candidate_count": len(index_records),
    "deterministic_ready_count": deterministic_ready_count,
    "qaas_validation_missing_count": qaas_validation_missing_count,
    "airgapped_missing_count": airgapped_missing_count,
    "docs_advisory_record_count": docs_advisory_record_count,
    "scope_blocked_count": scope_blocked_count,
    "by_readiness_class": dict(sorted(class_counts.items())),
    "by_blocker_class": dict(sorted(blocker_class_counts.items())),
    "records": records,
}
record_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(
    "Selected candidate promotion readiness passed for "
    f"{len(index_records)} candidates; "
    f"{deterministic_ready_count} have lifecycle/template/live evidence; "
    f"{airgapped_missing_count} remain airgapped-blocked."
)
print(f"Record: {record_path}")
