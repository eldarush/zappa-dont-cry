#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
failures = []
checked = 0

blocked_markers = [
    "blocked_until_",
    "__DOCUMENTED_ASSERTION_OR_CUSTOM__",
    "Links: []",
    "Storages: []",
    "DataSources: []",
    "Sessions: []",
    "Stubs: []",
]

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if manifest.get("promotion_state") != "executable":
        continue
    checked += 1
    for artifact in manifest.get("artifacts", []):
        path = Path(artifact)
        if not path.exists() or path.suffix.lower() not in {".yaml", ".yml", ".cs"}:
            continue
        content = path.read_text(encoding="utf-8-sig")
        for marker in blocked_markers:
            if marker in content:
                failures.append(f"executable artifact contains blocked marker {marker!r}: {path}")
        if path.name == "test.qaas.yaml":
            if not re.search(r"(?m)^Sessions:\s*\n\s+-", content):
                failures.append(f"executable Runner YAML lacks non-empty Sessions: {path}")
            if not re.search(r"(?m)^Assertions:\s*\n\s+-", content):
                failures.append(f"executable Runner YAML lacks non-empty Assertions: {path}")
        if path.name == "mocker.qaas.yaml":
            if not re.search(r"(?m)^Stubs:\s*\n\s+-", content):
                failures.append(f"executable Mocker YAML lacks non-empty Stubs: {path}")
            if "Processor:" not in content:
                failures.append(f"executable Mocker YAML lacks Processor linkage: {path}")
        if path.suffix.lower() == ".cs":
            if "public const string" in content and "QaaS" not in content.replace("QaaSTopRepoConfigSkeleton", ""):
                failures.append(f"executable C# appears to be constants-only skeleton: {path}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Executable artifact shape check passed; executable manifests checked: {checked}.")
