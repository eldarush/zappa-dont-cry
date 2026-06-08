#!/usr/bin/env python3
import json
import sys
from pathlib import Path


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
failures = []
checked = 0

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    docs_evidence = manifest.get("docs_evidence", [])
    if manifest.get("promotion_state") == "executable":
        checked += 1
        if not all(isinstance(item, dict) for item in docs_evidence):
            failures.append(f"executable manifest must use structured docs_evidence objects: {manifest_path}")
            continue
        for item in docs_evidence:
            for field in ("path", "claim", "supports"):
                if field not in item:
                    failures.append(f"docs_evidence item missing {field}: {manifest_path}")
            if not Path(item.get("path", "")).exists():
                failures.append(f"docs_evidence path missing: {manifest_path}: {item.get('path')}")
        supports = {support for item in docs_evidence for support in item.get("supports", [])}
        for required in ("template_validation.command", "build_validation.command", "airgapped_validation"):
            if required not in supports:
                failures.append(f"executable manifest docs_evidence does not support {required}: {manifest_path}")
    else:
        if not docs_evidence:
            failures.append(f"blocked manifest has no docs_evidence: {manifest_path}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Docs evidence coverage check passed; executable manifests checked: {checked}.")
