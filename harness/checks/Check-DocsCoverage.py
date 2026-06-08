#!/usr/bin/env python3
import json
import sys
from collections import Counter
from pathlib import Path


docs_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\qaas-docs\docs")
coverage_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage\qaas-docs-coverage.json")
skeleton_index = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests\docs-coverage\coverage-skeleton-index.json")

failures = []
valid_families = {
    "assertion",
    "assertion-schema",
    "configuration",
    "documentation",
    "framework",
    "generator",
    "generator-schema",
    "mocker",
    "probe",
    "probe-schema",
    "processor",
    "processor-schema",
    "runner",
}

md_count = len(list(docs_root.rglob("*.md")))

try:
    coverage = json.loads(coverage_path.read_text(encoding="utf-8-sig"))
except Exception as exc:
    print(f"ERROR: coverage JSON did not parse: {exc}", file=sys.stderr)
    sys.exit(1)

records = coverage.get("records", [])
if coverage.get("count") != md_count or len(records) != md_count:
    failures.append(f"coverage count mismatch: docs={md_count} json={coverage.get('count')} records={len(records)}")

ids = [r.get("coverage_id") for r in records]
if len(ids) != len(set(ids)):
    failures.append("coverage_id values are not unique")

families = Counter()
for record in records:
    family = record.get("family")
    if family not in valid_families:
        failures.append(f"invalid family {family!r} for {record.get('relative_path')}")
    else:
        families[family] += 1
    if not Path(record.get("full_path", "")).exists():
        failures.append(f"missing full_path: {record.get('full_path')}")
    if not record.get("artifact_types"):
        failures.append(f"missing artifact_types: {record.get('coverage_id')}")

by_family = coverage.get("by_family")
if not isinstance(by_family, dict) or "" in by_family:
    failures.append("by_family is missing or contains an empty key")
else:
    recomputed = dict(sorted(families.items()))
    observed = {k: by_family[k] for k in sorted(by_family)}
    if observed != recomputed:
        failures.append(f"by_family mismatch: observed={observed} recomputed={recomputed}")

try:
    index = json.loads(skeleton_index.read_text(encoding="utf-8-sig"))
except Exception as exc:
    failures.append(f"skeleton index did not parse: {exc}")
else:
    if index.get("count") != len(records):
        failures.append(f"skeleton index count mismatch: {index.get('count')} vs {len(records)}")
    output_dir = Path(index.get("output_directory", ""))
    manifests = list(output_dir.rglob("qaas-artifact-manifest.json")) if output_dir.exists() else []
    if len(manifests) != len(records):
        failures.append(f"skeleton manifest count mismatch: {len(manifests)} vs {len(records)}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Docs coverage check passed for {len(records)} records.")
