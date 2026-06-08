#!/usr/bin/env python3
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from weak_evidence_policy import format_reasons, validate_promotion_airgapped_evidence


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
blocked_statuses = {"blocked_until_contract_review", "blocked_until_repo_contract_review"}
executable_statuses = {"executable_ready", "validated_executable"}
required_promotion_evidence = {
    "QaaS template validation result",
    "C# build result when code artifacts exist",
    "Live QaaS run/act/assert result when dependency gates are ready",
    "Airgapped weak-model validation transcript",
}

failures = []
manifest_count = 0

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    manifest_count += 1
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    status = manifest.get("status")
    promotion_state = manifest.get("promotion_state")
    promotion = manifest.get("promotion_requirements")

    if status in blocked_statuses:
        if promotion_state != "blocked":
            failures.append(f"blocked manifest promotion_state is not blocked: {manifest_path}")
        if not manifest.get("blocked_reason"):
            failures.append(f"blocked manifest missing blocked_reason: {manifest_path}")
        if not isinstance(promotion, dict):
            failures.append(f"blocked manifest missing promotion_requirements: {manifest_path}")
        else:
            if promotion.get("current_state") != "blocked":
                failures.append(f"blocked manifest promotion current_state is not blocked: {manifest_path}")
            evidence = set(promotion.get("required_evidence", []))
            missing = required_promotion_evidence - evidence
            if missing:
                failures.append(f"promotion requirements missing {sorted(missing)}: {manifest_path}")

        for artifact in manifest.get("artifacts", []):
            path = Path(artifact)
            if path.suffix.lower() in {".yaml", ".yml", ".cs"} and path.exists():
                content = path.read_text(encoding="utf-8-sig")
                if "__DOCUMENTED_ASSERTION_OR_CUSTOM__" in content and status not in blocked_statuses:
                    failures.append(f"placeholder artifact is not blocked: {path}")

        airgapped = manifest.get("airgapped_validation", {})
        if isinstance(airgapped, dict) and airgapped.get("required") is True and airgapped.get("status") == "passed":
            airgapped_result = validate_promotion_airgapped_evidence(airgapped, manifest_path)
            if not airgapped_result.weak_validation_passed:
                failures.append(
                    "airgapped passed without policy-eligible live weak evidence: "
                    f"{manifest_path}: {format_reasons(airgapped_result)}"
                )

    elif status in executable_statuses or promotion_state == "executable":
        if promotion_state != "executable" or status != "executable":
            failures.append(f"executable status/promotion_state mismatch: {manifest_path}")
        airgapped_result = validate_promotion_airgapped_evidence(manifest.get("airgapped_validation"), manifest_path)
        if not airgapped_result.weak_validation_passed:
            failures.append(
                "executable manifest missing policy-eligible live weak airgapped evidence: "
                f"{manifest_path}: {format_reasons(airgapped_result)}"
            )
        evidence = manifest.get("validation_evidence")
        if not isinstance(evidence, dict):
            failures.append(f"executable manifest missing validation_evidence: {manifest_path}")
        else:
            for key in ("template", "build", "live", "airgapped"):
                value = evidence.get(key)
                if not value or not Path(value).exists():
                    failures.append(f"executable manifest missing validation evidence {key}: {manifest_path}")
        for artifact in manifest.get("artifacts", []):
            path = Path(artifact)
            if path.suffix.lower() in {".yaml", ".yml", ".cs"} and path.exists():
                if "__DOCUMENTED_ASSERTION_OR_CUSTOM__" in path.read_text(encoding="utf-8-sig"):
                    failures.append(f"executable artifact still contains placeholder: {path}")
    else:
        failures.append(f"unknown manifest status {status!r}: {manifest_path}")

if manifest_count == 0:
    failures.append(f"no manifests found under {root}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Promotion readiness check passed for {manifest_count} manifests.")
