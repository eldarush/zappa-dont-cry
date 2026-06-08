#!/usr/bin/env python3
import json
import sys
from collections import Counter
from pathlib import Path


contracts_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts")
generated_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests\top-repos")
out_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")
expected_count = int(sys.argv[4]) if len(sys.argv) > 4 else 250

runtime_match_keys = ("node", "python", "go", "java", "rust", "dotnet")
high_value_surfaces = {
    "api-contract-validation",
    "runner-yaml-from-public-contract",
    "containerized-runtime-smoke",
    "ci-documented-command-discovery",
    "node-service-or-package-contract",
    "python-cli-or-service-contract",
    "go-cli-or-service-contract",
    "rust-cli-or-service-contract",
    "jvm-service-contract",
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def as_list(value):
    return value if isinstance(value, list) else []


def match_count(contract: dict, key: str) -> int:
    matches = contract.get("path_matches")
    if not isinstance(matches, dict):
        return 0
    return len(as_list(matches.get(key)))


def score_contract(contract: dict) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []
    strength = contract.get("contract_strength")
    surfaces = set(as_list(contract.get("candidate_qaas_surfaces")))

    if strength == "contract_files_found":
        score += 4
        reasons.append("contract_files_found")
    elif strength == "readme_plus_runtime_hints":
        score += 2
        reasons.append("readme_plus_runtime_hints")
    elif strength == "readme_only":
        score += 1
        reasons.append("readme_only")

    api_count = match_count(contract, "api_contracts")
    test_count = match_count(contract, "tests")
    ci_count = match_count(contract, "ci")
    container_count = match_count(contract, "containers")
    runtime_count = sum(match_count(contract, key) for key in runtime_match_keys)

    if api_count:
        score += 2
        reasons.append(f"api_contract_paths:{api_count}")
    if test_count:
        score += 2
        reasons.append(f"test_paths:{test_count}")
    if ci_count:
        score += 1
        reasons.append(f"ci_paths:{ci_count}")
    if container_count:
        score += 1
        reasons.append(f"container_paths:{container_count}")
    if runtime_count:
        score += 1
        reasons.append(f"runtime_paths:{runtime_count}")
    if surfaces & high_value_surfaces:
        score += 1
        reasons.append("high_value_surface")

    return score, reasons


def triage_state(score: int, contract: dict) -> str:
    api_count = match_count(contract, "api_contracts")
    test_count = match_count(contract, "tests")
    runtime_count = sum(match_count(contract, key) for key in runtime_match_keys)
    if score >= 8 and api_count and test_count:
        return "promotion_candidate_review"
    if score >= 5 and (api_count or runtime_count):
        return "contract_review_priority"
    return "contract_discovery_backlog"


def remaining_blockers(state: str, manifest: dict | None) -> list[str]:
    blockers = [
        "select_exact_public_runtime_or_api_contract",
        "derive_public_input_output_examples",
        "derive_public_dependency_or_stub_contract",
        "derive_cleanup_contract",
        "replace_blocked_qaaS_placeholders",
        "run_qaaS_template_validation",
        "run_qaaS_build_validation",
        "run_live_qaaS_act_assert_validation",
        "run_live_airgapped_weak_model_validation",
    ]
    if manifest and manifest.get("promotion_state") == "executable":
        return [item for item in blockers if item != "replace_blocked_qaaS_placeholders"]
    if state == "promotion_candidate_review":
        return blockers
    if state == "contract_review_priority":
        return ["choose_target_contract"] + blockers
    return ["harvest_more_specific_public_contracts"] + blockers


failures: list[str] = []
contract_paths = sorted(contracts_dir.rglob("repo-contract.json"))
manifest_paths = sorted(generated_dir.rglob("qaas-artifact-manifest.json"))

if not contract_paths:
    failures.append(f"no repo contracts found under {contracts_dir}")
if not manifest_paths:
    failures.append(f"no top-repo manifests found under {generated_dir}")
if expected_count and len(contract_paths) != expected_count:
    failures.append(f"expected {expected_count} repo contracts, found {len(contract_paths)}")

manifests_by_repo = {}
for manifest_path in manifest_paths:
    manifest = read_json(manifest_path)
    repo = manifest.get("source_repository")
    if not repo:
        failures.append(f"top-repo manifest missing source_repository: {manifest_path}")
        continue
    manifests_by_repo[repo] = (manifest_path, manifest)

records = []
strength_counts: Counter[str] = Counter()
state_counts: Counter[str] = Counter()
executable_count = 0
blocked_count = 0
missing_manifest_count = 0

for contract_path in contract_paths:
    contract = read_json(contract_path)
    repo = contract.get("repository")
    if not repo:
        failures.append(f"repo contract missing repository: {contract_path}")
        continue
    if contract.get("status") != "contract_harvested":
        failures.append(f"repo contract not harvested cleanly: {contract_path}")
    if as_list(contract.get("errors")):
        failures.append(f"repo contract contains errors: {contract_path}")
    for evidence in as_list(contract.get("public_evidence")):
        if not Path(evidence).exists():
            failures.append(f"repo contract public evidence path missing for {repo}: {evidence}")

    manifest_path = None
    manifest = None
    if repo in manifests_by_repo:
        manifest_path, manifest = manifests_by_repo[repo]
    else:
        missing_manifest_count += 1

    if manifest and manifest.get("promotion_state") == "executable":
        executable_count += 1
    else:
        blocked_count += 1

    score, reasons = score_contract(contract)
    state = triage_state(score, contract)
    strength = str(contract.get("contract_strength") or "unknown")
    strength_counts[strength] += 1
    state_counts[state] += 1

    api_count = match_count(contract, "api_contracts")
    test_count = match_count(contract, "tests")
    ci_count = match_count(contract, "ci")
    container_count = match_count(contract, "containers")
    runtime_count = sum(match_count(contract, key) for key in runtime_match_keys)

    records.append(
        {
            "rank": int(contract.get("rank") or 0),
            "repository": repo,
            "contract": str(contract_path),
            "manifest": str(manifest_path) if manifest_path else None,
            "contract_strength": strength,
            "triage_score": score,
            "triage_state": state,
            "score_reasons": reasons,
            "candidate_qaas_surfaces": as_list(contract.get("candidate_qaas_surfaces")),
            "path_match_counts": {
                "api_contracts": api_count,
                "tests": test_count,
                "ci": ci_count,
                "containers": container_count,
                "runtime": runtime_count,
            },
            "promotion_state": manifest.get("promotion_state") if manifest else "missing_manifest",
            "remaining_blockers": remaining_blockers(state, manifest),
            "public_evidence": as_list(contract.get("public_evidence")),
        }
    )

records.sort(key=lambda item: (-item["triage_score"], item["rank"]))
high_potential = [record for record in records if record["triage_state"] == "promotion_candidate_review"]
priority = [record for record in records if record["triage_state"] == "contract_review_priority"]

out_dir.mkdir(parents=True, exist_ok=True)
record_path = out_dir / "top-repo-promotion-triage.json"
summary = {
    "schema_version": 1,
    "triage_status": "blocked_until_selected_contracts_are_promoted",
    "completion_ready": False,
    "contracts_dir": str(contracts_dir),
    "generated_dir": str(generated_dir),
    "contract_count": len(contract_paths),
    "manifest_count": len(manifest_paths),
    "missing_manifest_count": missing_manifest_count,
    "executable_manifest_count": executable_count,
    "blocked_manifest_count": blocked_count,
    "high_potential_count": len(high_potential),
    "contract_review_priority_count": len(priority),
    "by_contract_strength": dict(sorted(strength_counts.items())),
    "by_triage_state": dict(sorted(state_counts.items())),
    "top_candidates": records[:25],
    "records": records,
}
record_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

if missing_manifest_count:
    failures.append(f"{missing_manifest_count} repo contracts do not have generated top-repo manifests")
if len(manifest_paths) != len(contract_paths):
    failures.append("top-repo manifest count does not match contract count")
if not high_potential:
    failures.append("no promotion_candidate_review records were identified")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(
    "Top-repo promotion triage passed for "
    f"{len(contract_paths)} contracts; "
    f"{len(high_potential)} high-potential repositories; "
    f"{len(priority)} contract-review-priority repositories."
)
print(f"Record: {record_path}")
