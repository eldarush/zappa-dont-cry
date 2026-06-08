#!/usr/bin/env python3
import hashlib
import json
import sys
from pathlib import Path


selected_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts")
contracts_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\top-repos\contracts")
generated_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests\top-repos")
out_dir = Path(sys.argv[4]) if len(sys.argv) > 4 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")

failures: list[str] = []


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"failed to read JSON {path}: {exc}")
        return {}


def is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def require_relative_to(path_value: str, root: Path, label: str, owner: Path) -> Path | None:
    if not isinstance(path_value, str) or not path_value.strip():
        failures.append(f"{label} is empty in {owner}")
        return None
    path = Path(path_value)
    if not path.exists():
        failures.append(f"{label} does not exist in {owner}: {path}")
        return None
    if not is_relative_to(path, root):
        failures.append(f"{label} is outside allowed root {root}: {path}")
        return None
    return path


def valid_git_path(value: str) -> bool:
    if not isinstance(value, str) or not value:
        return False
    if "\\" in value or ":" in value:
        return False
    if value.startswith("/") or value.startswith("../") or "/../" in value or value.endswith("/.."):
        return False
    return not any(ord(ch) < 32 or ord(ch) == 127 for ch in value)


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()


def is_lfs_pointer(data: bytes) -> bool:
    if len(data) > 2048:
        return False
    return data.startswith(b"version https://git-lfs.github.com/spec/v1")


index_path = selected_dir / "selected-contract-index.json"
if not index_path.exists():
    failures.append(f"selected contract index missing: {index_path}")
    index = {}
else:
    index = read_json(index_path)

records = index.get("records") if isinstance(index, dict) else None
if not isinstance(records, list) or not records:
    failures.append(f"selected contract index has no records: {index_path}")
    records = []

if index.get("selected_repository_count") != len(records):
    failures.append(f"selected_repository_count mismatch in {index_path}")

total_fetched_bytes = 0
selected_contract_count = 0
selected_file_count = 0

for record in records:
    if not isinstance(record, dict):
        failures.append(f"selected contract index record is not an object: {index_path}")
        continue
    record_path = require_relative_to(str(record.get("record_path") or ""), selected_dir, "record_path", index_path)
    if not record_path:
        continue
    selected = read_json(record_path)
    selected_contract_count += 1

    if selected.get("status") != "contract_content_harvested_not_executable":
        failures.append(f"selected contract status is not fail-closed: {record_path}")
    if selected.get("promotion_state") != "blocked":
        failures.append(f"selected contract promotion_state is not blocked: {record_path}")
    if "promotion_contracts" in selected:
        failures.append(f"selected contract must not emit promotion_contracts: {record_path}")
    if selected.get("readiness_state") != "selected_public_contract_content_harvested":
        failures.append(f"selected contract readiness_state unexpected: {record_path}")

    source_contract_path = require_relative_to(str(selected.get("source_contract") or ""), contracts_dir, "source_contract", record_path)
    require_relative_to(str(selected.get("readme_snapshot") or ""), contracts_dir, "readme_snapshot", record_path)
    tree_path = require_relative_to(str(selected.get("tree_snapshot") or ""), contracts_dir, "tree_snapshot", record_path)
    if not source_contract_path or not tree_path:
        continue

    source_contract = read_json(source_contract_path)
    if selected.get("repository") != source_contract.get("repository"):
        failures.append(f"selected contract repository mismatch with source contract: {record_path}")
    if selected.get("rank") != source_contract.get("rank"):
        failures.append(f"selected contract rank mismatch with source contract: {record_path}")

    tree_json = read_json(tree_path)
    tree_items = {
        item.get("path"): item
        for item in tree_json.get("tree", [])
        if isinstance(item, dict) and item.get("type") == "blob"
    }

    files = selected.get("selected_public_contracts")
    fetched_files = selected.get("fetched_files")
    if not isinstance(files, list) or not files:
        failures.append(f"selected_public_contracts missing or empty: {record_path}")
        files = []
    if files != fetched_files:
        failures.append(f"selected_public_contracts must match fetched_files exactly: {record_path}")

    seen_paths: set[str] = set()
    for file_record in files:
        if not isinstance(file_record, dict):
            failures.append(f"selected_public_contract entry is not an object: {record_path}")
            continue
        selected_file_count += 1
        source_path = file_record.get("source_path")
        if not valid_git_path(source_path):
            failures.append(f"selected source_path is unsafe: {record_path}: {source_path!r}")
            continue
        if source_path in seen_paths:
            failures.append(f"duplicate selected source_path: {record_path}: {source_path}")
        seen_paths.add(source_path)

        tree_item = tree_items.get(source_path)
        if not tree_item:
            failures.append(f"selected source_path is not a blob in tree snapshot: {record_path}: {source_path}")
            continue

        local_path = require_relative_to(str(file_record.get("local_path") or ""), selected_dir, "selected local_path", record_path)
        if not local_path:
            continue
        if is_relative_to(local_path, generated_dir):
            failures.append(f"selected evidence must not be written under generated tests: {local_path}")

        data = local_path.read_bytes()
        total_fetched_bytes += len(data)
        expected_size = int(tree_item.get("size") or -1)
        if len(data) != expected_size:
            failures.append(f"selected file size mismatch for {source_path}: tree={expected_size} local={len(data)}")
        if file_record.get("size") != expected_size:
            failures.append(f"selected metadata size mismatch for {source_path}: {record_path}")
        if file_record.get("fetched_size") != len(data):
            failures.append(f"selected metadata fetched_size mismatch for {source_path}: {record_path}")

        expected_sha = str(tree_item.get("sha") or "")
        actual_git_sha = git_blob_sha(data)
        if file_record.get("sha") != expected_sha:
            failures.append(f"selected metadata sha does not match tree for {source_path}: {record_path}")
        if actual_git_sha != expected_sha:
            failures.append(f"selected git blob sha mismatch for {source_path}: expected={expected_sha} actual={actual_git_sha}")
        if file_record.get("git_blob_sha_verified") is not True:
            failures.append(f"selected git_blob_sha_verified is not true for {source_path}: {record_path}")

        actual_sha256 = hashlib.sha256(data).hexdigest()
        if file_record.get("content_sha256") != actual_sha256:
            failures.append(f"selected content_sha256 mismatch for {source_path}: {record_path}")
        if file_record.get("github_blob_url") != tree_item.get("url"):
            failures.append(f"selected github_blob_url is not the immutable tree blob URL for {source_path}: {record_path}")
        if expected_sha and expected_sha not in str(file_record.get("github_blob_url") or ""):
            failures.append(f"selected github_blob_url does not contain blob sha for {source_path}: {record_path}")
        try:
            data.decode("utf-8")
        except UnicodeDecodeError as exc:
            failures.append(f"selected file is not UTF-8 text for {source_path}: {exc}")
        if is_lfs_pointer(data):
            failures.append(f"selected file is a Git LFS pointer for {source_path}: {record_path}")

    promotion_contracts = selected.get("candidate_promotion_contracts")
    if isinstance(promotion_contracts, list):
        for contract in promotion_contracts:
            if not isinstance(contract, dict):
                failures.append(f"candidate_promotion_contract is not an object: {record_path}")
                continue
            if contract.get("status") == "executable" or contract.get("supports") == "executable-command":
                failures.append(f"selected evidence must not claim executable promotion: {record_path}")

    blockers = selected.get("remaining_blockers")
    if not isinstance(blockers, list) or not blockers:
        failures.append(f"selected contract must keep remaining_blockers: {record_path}")
    else:
        required_blockers = {
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
            "run_live_airgapped_weak_model_validation",
        }
        missing = required_blockers - set(blockers)
        if missing:
            failures.append(f"selected contract missing required blockers {sorted(missing)}: {record_path}")

for manifest_path in sorted(generated_dir.rglob("qaas-artifact-manifest.json")):
    manifest = read_json(manifest_path)
    if manifest.get("promotion_state") == "executable":
        failures.append(f"selected contract harvest must not leave top-repo manifest executable: {manifest_path}")

out_dir.mkdir(parents=True, exist_ok=True)
summary_path = out_dir / "selected-top-repo-contracts.json"
summary = {
    "schema_version": 1,
    "status": "selected_contract_content_harvested_not_executable",
    "completion_ready": False,
    "selected_contract_count": selected_contract_count,
    "selected_file_count": selected_file_count,
    "total_fetched_bytes": total_fetched_bytes,
    "selected_contract_index": str(index_path),
}
summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(
    "Selected top-repo contract check passed for "
    f"{selected_contract_count} repositories and {selected_file_count} immutable blobs."
)
print(f"Record: {summary_path}")
