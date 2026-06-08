#!/usr/bin/env python3
import json
import sys
from pathlib import Path


generated_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
coverage_path = Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage\qaas-docs-coverage.json")
top_contracts = Path(r"D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts")
failures = []


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def check_index(index_path, expected_campaign):
    index = load_json(index_path)
    out_dir = Path(index["output_directory"])
    manifests = sorted(out_dir.rglob("qaas-artifact-manifest.json"))
    if index.get("count") != len(manifests):
        failures.append(f"index count mismatch: {index_path}")
    by_dir = {str(Path(m).parent): m for m in manifests}
    for record in index.get("records", []):
        manifest_path = by_dir.get(record.get("directory"))
        if not manifest_path:
            failures.append(f"index record directory lacks manifest: {record.get('directory')}")
            continue
        manifest = load_json(manifest_path)
        if manifest.get("campaign_id") != expected_campaign:
            failures.append(f"manifest campaign mismatch: {manifest_path}")
        if record.get("status") != manifest.get("status"):
            failures.append(f"index/manifest status mismatch: {manifest_path}")
        if record.get("promotion_state") != manifest.get("promotion_state"):
            failures.append(f"index/manifest promotion_state mismatch: {manifest_path}")


docs_index = generated_root / "docs-coverage" / "coverage-skeleton-index.json"
top_index = generated_root / "top-repos" / "top-repo-artifact-index.json"
check_index(docs_index, "qaas-docs-coverage")
check_index(top_index, "top-github-repos")

coverage = {r["coverage_id"]: r for r in load_json(coverage_path).get("records", [])}
for manifest_path in (generated_root / "docs-coverage").rglob("qaas-artifact-manifest.json"):
    manifest = load_json(manifest_path)
    record = coverage.get(manifest.get("coverage_id"))
    if not record:
        failures.append(f"docs manifest coverage_id missing from coverage index: {manifest_path}")
        continue
    for field in ("source_document", "family"):
        expected = record["full_path"] if field == "source_document" else record[field]
        if manifest.get(field) != expected:
            failures.append(f"docs manifest {field} mismatch: {manifest_path}")

contracts_by_repo = {}
for contract_path in top_contracts.rglob("repo-contract.json"):
    contract = load_json(contract_path)
    contracts_by_repo[contract["repository"]] = (contract_path, contract)
for manifest_path in (generated_root / "top-repos").rglob("qaas-artifact-manifest.json"):
    manifest = load_json(manifest_path)
    contract_entry = contracts_by_repo.get(manifest.get("source_repository"))
    if not contract_entry:
        failures.append(f"top manifest missing matching contract: {manifest_path}")
        continue
    contract_path, contract = contract_entry
    if Path(manifest.get("repo_contract", "")) != contract_path:
        failures.append(f"top manifest repo_contract mismatch: {manifest_path}")
    if manifest.get("repository_rank") != contract.get("rank"):
        failures.append(f"top manifest rank mismatch: {manifest_path}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print("Index/manifest consistency check passed.")
