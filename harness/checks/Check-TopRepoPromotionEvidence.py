#!/usr/bin/env python3
import json
import sys
from pathlib import Path


contracts_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts")
generated_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests\top-repos")
failures = []
checked = 0

for manifest_path in sorted(generated_dir.rglob("qaas-artifact-manifest.json")):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    contract_path = Path(manifest.get("repo_contract", ""))
    if not contract_path.exists():
        failures.append(f"repo_contract path missing: {manifest_path}")
        continue
    contract = json.loads(contract_path.read_text(encoding="utf-8-sig"))
    if manifest.get("promotion_state") != "executable":
        continue
    checked += 1
    promotion_contracts = contract.get("promotion_contracts")
    if not isinstance(promotion_contracts, list) or not promotion_contracts:
        failures.append(f"executable top repo lacks promotion_contracts: {manifest_path}")
        continue
    supports = {item.get("supports") for item in promotion_contracts if isinstance(item, dict)}
    if "runtime-contract" not in supports:
        failures.append(f"executable top repo lacks runtime-contract promotion evidence: {manifest_path}")
    if "executable-command" not in supports:
        failures.append(f"executable top repo lacks executable-command promotion evidence: {manifest_path}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Top-repo promotion evidence check passed; executable manifests checked: {checked}.")
