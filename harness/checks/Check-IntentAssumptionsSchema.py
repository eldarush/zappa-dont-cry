#!/usr/bin/env python3
import json
import sys
from pathlib import Path


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
required_fields = ("assumption", "why_safe", "risk_if_wrong", "how_to_override")
failures: list[str] = []
manifest_count = 0
assumption_count = 0

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    manifest_count += 1
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"manifest parse failed: {manifest_path}: {exc}")
        continue

    assumptions = manifest.get("intent_assumptions")
    if not isinstance(assumptions, list) or not assumptions:
        failures.append(f"intent_assumptions missing or empty: {manifest_path}")
        continue

    for index, assumption in enumerate(assumptions):
        assumption_count += 1
        if not isinstance(assumption, dict):
            failures.append(f"intent_assumptions[{index}] must be an object: {manifest_path}")
            continue
        for field in required_fields:
            value = assumption.get(field)
            if not isinstance(value, str) or not value.strip():
                failures.append(f"intent_assumptions[{index}] missing non-empty {field}: {manifest_path}")
        evidence = assumption.get("public_evidence")
        if not isinstance(evidence, list) or not evidence:
            failures.append(f"intent_assumptions[{index}] missing non-empty public_evidence: {manifest_path}")

if manifest_count == 0:
    failures.append(f"no manifests found under {root}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Intent assumptions schema check passed for {manifest_count} manifests and {assumption_count} assumptions.")
