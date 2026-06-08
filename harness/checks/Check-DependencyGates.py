#!/usr/bin/env python3
import json
import sys
from pathlib import Path


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
allowed_kinds = {"runtime", "dependency", "cleanup", "qaas-template", "qaas-build", "airgapped"}
allowed_statuses = {"blocked", "ready", "passed", "failed", "not_applicable"}
required_gate_fields = {"gate_id", "kind", "required", "status", "evidence", "check_command", "blocked_reason"}
failures = []
count = 0

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    count += 1
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    gates = manifest.get("dependency_gates")
    if not isinstance(gates, list) or not gates:
        failures.append(f"dependency_gates missing or empty: {manifest_path}")
        continue

    for gate in gates:
        if not isinstance(gate, dict):
            failures.append(f"dependency gate is not an object: {manifest_path}")
            continue
        missing = required_gate_fields - set(gate)
        if missing:
            failures.append(f"dependency gate missing fields {sorted(missing)}: {manifest_path}")
        if gate.get("kind") not in allowed_kinds:
            failures.append(f"invalid gate kind {gate.get('kind')!r}: {manifest_path}")
        if gate.get("status") not in allowed_statuses:
            failures.append(f"invalid gate status {gate.get('status')!r}: {manifest_path}")
        if not isinstance(gate.get("required"), bool):
            failures.append(f"gate required is not boolean: {manifest_path}")
        if not isinstance(gate.get("evidence"), list):
            failures.append(f"gate evidence is not a list: {manifest_path}")
        if gate.get("required") and gate.get("status") in {"blocked", "failed"} and not gate.get("blocked_reason"):
            failures.append(f"blocked/failed required gate lacks blocked_reason: {manifest_path}")

    if manifest.get("promotion_state") == "executable":
        for gate in gates:
            if gate.get("required") and gate.get("status") != "passed":
                failures.append(f"executable manifest has non-passed required gate {gate.get('gate_id')}: {manifest_path}")

if count == 0:
    failures.append(f"no manifests found under {root}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Dependency gate check passed for {count} manifests.")
