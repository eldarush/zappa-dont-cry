#!/usr/bin/env python3
import json
import sys
from pathlib import Path


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
required_fields = (
    "blocker_id",
    "blocker_type",
    "description",
    "required_evidence",
    "public_evidence",
    "unblock_instruction",
)
allowed_types = {
    "source_boundary",
    "repository_contract",
    "repository_or_component_contract",
    "component_contract",
    "qaas_docs_contract",
}
failures: list[str] = []
manifest_count = 0
blocker_count = 0

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    manifest_count += 1
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"manifest parse failed: {manifest_path}: {exc}")
        continue

    blockers = manifest.get("source_only_blockers")
    if not isinstance(blockers, list):
        failures.append(f"source_only_blockers missing or not a list: {manifest_path}")
        continue

    if manifest.get("promotion_state") == "blocked":
        if not blockers:
            failures.append(f"blocked manifest missing non-empty source_only_blockers: {manifest_path}")
            continue

    for index, blocker in enumerate(blockers):
        blocker_count += 1
        if not isinstance(blocker, dict):
            failures.append(f"source_only_blockers[{index}] is not an object: {manifest_path}")
            continue
        for field in required_fields:
            if field not in blocker:
                failures.append(f"source_only_blockers[{index}] missing {field}: {manifest_path}")
        for field in ("blocker_id", "blocker_type", "description", "unblock_instruction"):
            value = blocker.get(field)
            if not isinstance(value, str) or not value.strip():
                failures.append(f"source_only_blockers[{index}] has empty {field}: {manifest_path}")
        if blocker.get("blocker_type") not in allowed_types:
            failures.append(f"source_only_blockers[{index}] invalid blocker_type {blocker.get('blocker_type')!r}: {manifest_path}")
        for field in ("required_evidence", "public_evidence"):
            value = blocker.get(field)
            if not isinstance(value, list) or not value:
                failures.append(f"source_only_blockers[{index}] missing non-empty {field}: {manifest_path}")
                continue
            for item_index, item in enumerate(value):
                if not isinstance(item, str) or not item.strip():
                    failures.append(
                        f"source_only_blockers[{index}].{field}[{item_index}] is not a non-empty string: {manifest_path}"
                    )

if manifest_count == 0:
    failures.append(f"no manifests found under {root}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Source-only blocker check passed for {manifest_count} manifests and {blocker_count} blockers.")
