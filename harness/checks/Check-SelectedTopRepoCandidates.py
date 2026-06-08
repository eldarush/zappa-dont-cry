#!/usr/bin/env python3
import csv
import hashlib
import json
import re
import sys
from pathlib import Path


candidate_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests\selected-top-repo-candidates")
selected_contracts_root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\top-repos\selected-contracts")
coverage_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")

failures: list[str] = []
HTTPSTATUS_DOCS_ADVISORY_ID = "httpstatus-docs-inconsistency-recorded"


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"failed to parse JSON {path}: {exc}")
        return {}


def path_is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def require_under(path: Path, root: Path, label: str):
    if not path.exists():
        failures.append(f"{label} missing: {path}")
        return
    if not path_is_relative_to(path, root):
        failures.append(f"{label} must stay under {root}: {path}")


def path_equals(actual, expected: Path) -> bool:
    try:
        return Path(str(actual)).resolve() == expected.resolve()
    except Exception:
        return False


def text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8-sig")
    except Exception as exc:
        failures.append(f"failed to read text {path}: {exc}")
        return ""


def require_marker(content: str, marker: str, path: Path):
    if marker not in content:
        failures.append(f"missing marker {marker!r}: {path}")


def require_no_marker(content: str, marker: str, path: Path, reason: str):
    if marker in content:
        failures.append(f"{reason}: {path}")


def require_no_utf8_bom(path: Path, label: str):
    if not path.exists() or not path.is_file():
        return
    try:
        if path.read_bytes().startswith(b"\xef\xbb\xbf"):
            failures.append(f"{label} must be UTF-8 without BOM: {path}")
    except Exception as exc:
        failures.append(f"failed to inspect BOM for {label} {path}: {exc}")


def sha256_hex(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except Exception as exc:
        failures.append(f"failed to hash {path}: {exc}")
        return None


def passed_validation(value) -> bool:
    return isinstance(value, dict) and value.get("status") == "passed" and value.get("exit_code") == 0


def same_validation_record(left: dict, right: dict) -> bool:
    if not isinstance(left, dict) or not isinstance(right, dict):
        return False
    for field in ("status", "exit_code", "command", "transcript"):
        if left.get(field) != right.get(field):
            return False
    return True


def validate_lifecycle_evidence_paths(
    manifest_validation: dict,
    runtime_validation: dict,
    manifest_path: Path,
    runtime_plan_path: Path,
    repository: str,
    summary_filename: str,
    response_validator,
    required_transcript_markers: tuple[str, ...],
):
    if not passed_validation(manifest_validation):
        failures.append(f"{repository} manifest lifecycle_validation must be passed when lifecycle is adopted: {manifest_path}")
        return
    if not passed_validation(runtime_validation):
        failures.append(f"{repository} runtime plan lifecycle_validation must be passed when lifecycle is adopted: {runtime_plan_path}")
        return

    for field in ("summary", "transcript", "response"):
        if manifest_validation.get(field) != runtime_validation.get(field):
            failures.append(f"{repository} manifest/runtime lifecycle {field} paths must match: {manifest_path}")

    summary_path = Path(str(manifest_validation.get("summary", "")))
    transcript_path = Path(str(manifest_validation.get("transcript", "")))
    response_path = Path(str(manifest_validation.get("response", "")))
    lifecycle_root = coverage_dir.parent / "lifecycle-runs" / "selected-top-repo-candidates"
    require_under(summary_path, coverage_dir, f"{repository} lifecycle summary")
    require_under(transcript_path, lifecycle_root, f"{repository} lifecycle transcript")
    require_under(response_path, lifecycle_root, f"{repository} lifecycle response")
    if summary_path.name != summary_filename:
        failures.append(f"{repository} lifecycle summary filename mismatch: {summary_path}")
    if not summary_path.exists():
        return

    summary = read_json(summary_path)
    if summary.get("status") != "passed":
        failures.append(f"{repository} lifecycle summary must be passed: {summary_path}")
    if summary.get("repository") != repository:
        failures.append(f"{repository} lifecycle summary repository mismatch: {summary_path}")
    if summary.get("promotion_state") != "blocked" or summary.get("completion_ready") is not False:
        failures.append(f"{repository} lifecycle summary must remain blocked and not completion-ready: {summary_path}")
    if summary.get("exit_code") != 0:
        failures.append(f"{repository} lifecycle summary exit_code must be 0: {summary_path}")
    if summary.get("response_status") != 200 or summary.get("response_contract_passed") is not True:
        failures.append(f"{repository} lifecycle summary must prove HTTP 200 response contract: {summary_path}")
    if summary.get("cleanup_passed") is not True:
        failures.append(f"{repository} lifecycle summary must prove cleanup_passed true: {summary_path}")
    if summary.get("port_owners_after_cleanup_count") != 0:
        failures.append(f"{repository} lifecycle summary must prove zero port owners after cleanup: {summary_path}")
    remaining_process_ids = summary.get("remaining_tracked_process_ids", [])
    if not isinstance(remaining_process_ids, list) or len(remaining_process_ids) != 0:
        failures.append(f"{repository} lifecycle summary must prove no remaining tracked process ids: {summary_path}")
    if summary.get("weak_validation_passed") is not False:
        failures.append(f"{repository} lifecycle summary must not claim weak validation passed: {summary_path}")
    if not path_equals(summary.get("manifest"), manifest_path):
        failures.append(f"{repository} lifecycle summary manifest path mismatch: {summary_path}")
    if not path_equals(summary.get("runtime_plan"), runtime_plan_path):
        failures.append(f"{repository} lifecycle summary runtime_plan path mismatch: {summary_path}")
    if not path_equals(summary.get("transcript"), transcript_path):
        failures.append(f"{repository} lifecycle summary transcript path mismatch: {summary_path}")
    if not path_equals(summary.get("response"), response_path):
        failures.append(f"{repository} lifecycle summary response path mismatch: {summary_path}")
    response_validator(response_path)
    transcript_text = text(transcript_path)
    for marker in required_transcript_markers:
        if marker not in transcript_text:
            failures.append(f"{repository} lifecycle transcript missing marker {marker!r}: {transcript_path}")


def validate_fastapi_qaas_evidence(
    manifest: dict,
    runtime_plan: dict,
    manifest_path: Path,
    runtime_plan_path: Path,
):
    repository = "fastapi/fastapi"
    manifest_validation = manifest.get("selected_candidate_qaas_validation")
    runtime_validation = runtime_plan.get("qaas_validation")
    if not passed_validation(manifest_validation):
        failures.append(f"{repository} manifest selected_candidate_qaas_validation must be passed when QaaS is adopted: {manifest_path}")
        return
    if not passed_validation(runtime_validation):
        failures.append(f"{repository} runtime plan qaas_validation must be passed when QaaS is adopted: {runtime_plan_path}")
        return

    for field in ("summary", "transcript", "response", "run_dir"):
        if manifest_validation.get(field) != runtime_validation.get(field):
            failures.append(f"{repository} manifest/runtime QaaS {field} paths must match: {manifest_path}")

    live_root = coverage_dir.parent / "live-runs" / "selected-top-repo-candidates"
    summary_path = Path(str(manifest_validation.get("summary", "")))
    transcript_path = Path(str(manifest_validation.get("transcript", "")))
    response_path = Path(str(manifest_validation.get("response", "")))
    run_dir = Path(str(manifest_validation.get("run_dir", "")))
    require_under(summary_path, coverage_dir, f"{repository} live summary")
    require_under(transcript_path, live_root, f"{repository} live transcript")
    require_under(response_path, live_root, f"{repository} live response")
    if not run_dir.exists() or not path_is_relative_to(run_dir, live_root):
        failures.append(f"{repository} live run_dir must exist under {live_root}: {run_dir}")
    if summary_path.name != "selected-top-repo-candidate-live-fastapi.json":
        failures.append(f"{repository} live summary filename mismatch: {summary_path}")
    if not summary_path.exists():
        return

    summary = read_json(summary_path)
    if summary.get("status") != "passed":
        failures.append(f"{repository} live summary must be passed: {summary_path}")
    if summary.get("repository") != repository:
        failures.append(f"{repository} live summary repository mismatch: {summary_path}")
    if summary.get("validation_kind") != "selected_candidate_qaas_template_live":
        failures.append(f"{repository} live summary validation_kind mismatch: {summary_path}")
    if summary.get("promotion_state") != "blocked" or summary.get("completion_ready") is not False:
        failures.append(f"{repository} live summary must remain blocked and not completion-ready: {summary_path}")
    if summary.get("exit_code") != 0:
        failures.append(f"{repository} live summary exit_code must be 0: {summary_path}")
    if summary.get("manifest_updated") is not True:
        failures.append(f"{repository} live summary must prove manifest_updated true after adoption: {summary_path}")
    if summary.get("weak_validation_passed") is not False:
        failures.append(f"{repository} live summary must not claim weak validation passed: {summary_path}")
    if summary.get("response_status") != 200 or summary.get("response_contract_passed") is not True:
        failures.append(f"{repository} live summary must prove HTTP 200 response contract: {summary_path}")
    if summary.get("cleanup_passed") is not True:
        failures.append(f"{repository} live summary must prove cleanup_passed true: {summary_path}")
    if summary.get("port_owners_after_cleanup_count") != 0:
        failures.append(f"{repository} live summary must prove zero port owners after cleanup: {summary_path}")
    remaining_process_ids = summary.get("remaining_tracked_process_ids", [])
    if not isinstance(remaining_process_ids, list) or len(remaining_process_ids) != 0:
        failures.append(f"{repository} live summary must prove no remaining tracked process ids: {summary_path}")
    if summary.get("install_command") != 'python -m pip install "fastapi[standard]"':
        failures.append(f"{repository} live summary install_command mismatch: {summary_path}")
    if not summary.get("fastapi_module_version") or not summary.get("uvicorn_module_version"):
        failures.append(f"{repository} live summary must record FastAPI and Uvicorn versions: {summary_path}")
    if not path_equals(summary.get("manifest"), manifest_path):
        failures.append(f"{repository} live summary manifest path mismatch: {summary_path}")
    if not path_equals(summary.get("runtime_plan"), runtime_plan_path):
        failures.append(f"{repository} live summary runtime_plan path mismatch: {summary_path}")
    if not path_equals(summary.get("transcript"), transcript_path):
        failures.append(f"{repository} live summary transcript path mismatch: {summary_path}")
    if not path_equals(summary.get("response"), response_path):
        failures.append(f"{repository} live summary response path mismatch: {summary_path}")
    if not path_equals(summary.get("run_dir"), run_dir):
        failures.append(f"{repository} live summary run_dir mismatch: {summary_path}")

    for validation_field in ("build_validation", "template_validation", "live_validation"):
        validation = summary.get(validation_field)
        manifest_field = manifest.get(validation_field)
        if not passed_validation(validation):
            failures.append(f"{repository} live summary missing passed {validation_field}: {summary_path}")
            continue
        if not passed_validation(manifest_field):
            failures.append(f"{repository} manifest missing passed {validation_field}: {manifest_path}")
        elif not same_validation_record(validation, manifest_field):
            failures.append(f"{repository} manifest {validation_field} must equal live summary record: {manifest_path}")
        transcript = Path(str(validation.get("transcript", "")))
        require_under(transcript, live_root, f"{repository} {validation_field} transcript")

    hashes = summary.get("source_hashes", {})
    staged_yaml_path = Path(str(summary.get("runner_yaml", "")))
    source_yaml_path = manifest_path.parent / "test.qaas.yaml"
    source_schema_path = manifest_path.parent / "schemas" / "item-response.schema.json"
    staged_schema_path = staged_yaml_path.parent / "schemas" / "item-response.schema.json"
    source_payload_path = manifest_path.parent / "request-payloads" / "get-items-5.bin"
    staged_payload_path = staged_yaml_path.parent / "request-payloads" / "get-items-5.bin"
    source_app_path = manifest_path.parent / "app" / "main.py"
    staged_app_path = run_dir / "fastapi-work" / "main.py"
    expected_hash_paths = (
        ("candidate_yaml_sha256", source_yaml_path),
        ("staged_yaml_sha256", staged_yaml_path),
        ("candidate_schema_sha256", source_schema_path),
        ("staged_schema_sha256", staged_schema_path),
        ("candidate_request_payload_sha256", source_payload_path),
        ("staged_request_payload_sha256", staged_payload_path),
        ("candidate_app_sha256", source_app_path),
        ("staged_app_sha256", staged_app_path),
    )
    for hash_field, path in expected_hash_paths:
        require_under(path, live_root if hash_field.startswith("staged_") else manifest_path.parent, f"{repository} {hash_field} source")
        actual_hash = sha256_hex(path)
        if actual_hash is not None and hashes.get(hash_field) != actual_hash:
            failures.append(f"{repository} live source hash {hash_field} does not match actual file: {path}")
    for left, right in (
        ("candidate_yaml_sha256", "staged_yaml_sha256"),
        ("candidate_schema_sha256", "staged_schema_sha256"),
        ("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        ("candidate_app_sha256", "staged_app_sha256"),
    ):
        if hashes.get(left) != hashes.get(right):
            failures.append(f"{repository} live source hash mismatch {left}/{right}: {summary_path}")

    try:
        response = json.loads(response_path.read_text(encoding="utf-8-sig"))
        if response != {"item_id": 5, "q": "somequery"}:
            failures.append(f"{repository} live response must exactly match README-backed JSON body: {response_path}")
    except Exception as exc:
        failures.append(f"failed to validate {repository} live response {response_path}: {exc}")

    transcript_text = text(transcript_path)
    for marker in (
        "FastApiCommand: fastapi dev",
        'InstallCommand: python -m pip install "fastapi[standard]"',
        "Ready: True",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "ExitCode: 0",
    ):
        if marker not in transcript_text:
            failures.append(f"{repository} live transcript missing marker {marker!r}: {transcript_path}")

    live_validation = summary.get("live_validation", {})
    live_transcript_path = Path(str(live_validation.get("transcript", "")))
    live_transcript_text = text(live_transcript_path)
    for marker in (
        "HTTP Get request to http://127.0.0.1:8000/items/5?q=somequery completed with status 200.",
        "Running assertion HttpStatus GetItemFiveReturnedOk",
        "Running assertion ObjectOutputJsonSchema GetItemFiveBodyMatchesReadmeSchema",
        "Runner completed. ExitCode=0",
    ):
        if marker not in live_transcript_text:
            failures.append(f"{repository} live Runner transcript missing marker {marker!r}: {live_transcript_path}")
    if "http://127.0.0.1:8000//items/5" in live_transcript_text:
        failures.append(f"{repository} live Runner transcript must not include double-slash route: {live_transcript_path}")


def validate_express_qaas_evidence(
    manifest: dict,
    runtime_plan: dict,
    manifest_path: Path,
    runtime_plan_path: Path,
):
    repository = "expressjs/express"
    manifest_validation = manifest.get("selected_candidate_qaas_validation")
    runtime_validation = runtime_plan.get("qaas_validation")
    if not passed_validation(manifest_validation):
        failures.append(f"{repository} manifest selected_candidate_qaas_validation must be passed when QaaS is adopted: {manifest_path}")
        return
    if not passed_validation(runtime_validation):
        failures.append(f"{repository} runtime plan qaas_validation must be passed when QaaS is adopted: {runtime_plan_path}")
        return

    for field in ("summary", "transcript", "response", "run_dir"):
        if manifest_validation.get(field) != runtime_validation.get(field):
            failures.append(f"{repository} manifest/runtime QaaS {field} paths must match: {manifest_path}")

    live_root = coverage_dir.parent / "live-runs" / "selected-top-repo-candidates"
    candidate_dir = manifest_path.parent
    summary_path = Path(str(manifest_validation.get("summary", "")))
    transcript_path = Path(str(manifest_validation.get("transcript", "")))
    response_path = Path(str(manifest_validation.get("response", "")))
    run_dir = Path(str(manifest_validation.get("run_dir", "")))
    require_under(summary_path, coverage_dir, f"{repository} live summary")
    require_under(transcript_path, live_root, f"{repository} live transcript")
    require_under(response_path, live_root, f"{repository} live response")
    if not run_dir.exists() or not path_is_relative_to(run_dir, live_root):
        failures.append(f"{repository} live run_dir must exist under {live_root}: {run_dir}")
    if summary_path.name != "selected-top-repo-candidate-live-express.json":
        failures.append(f"{repository} live summary filename mismatch: {summary_path}")
    if not summary_path.exists():
        return

    summary = read_json(summary_path)
    if summary.get("status") != "passed":
        failures.append(f"{repository} live summary must be passed: {summary_path}")
    if summary.get("repository") != repository:
        failures.append(f"{repository} live summary repository mismatch: {summary_path}")
    if summary.get("validation_kind") != "selected_candidate_qaas_template_live":
        failures.append(f"{repository} live summary validation_kind mismatch: {summary_path}")
    if summary.get("promotion_state") != "blocked" or summary.get("completion_ready") is not False:
        failures.append(f"{repository} live summary must remain blocked and not completion-ready: {summary_path}")
    if summary.get("exit_code") != 0:
        failures.append(f"{repository} live summary exit_code must be 0: {summary_path}")
    if summary.get("manifest_updated") is not True:
        failures.append(f"{repository} live summary must prove manifest_updated true after adoption: {summary_path}")
    if summary.get("weak_validation_passed") is not False:
        failures.append(f"{repository} live summary must not claim weak validation passed: {summary_path}")
    if summary.get("response_status") != 200 or summary.get("response_contract_passed") is not True:
        failures.append(f"{repository} live summary must prove HTTP 200 response contract: {summary_path}")
    if summary.get("cleanup_passed") is not True:
        failures.append(f"{repository} live summary must prove cleanup_passed true: {summary_path}")
    if summary.get("port_owners_after_cleanup_count") != 0:
        failures.append(f"{repository} live summary must prove zero port owners after cleanup: {summary_path}")
    remaining_process_ids = summary.get("remaining_tracked_process_ids", [])
    if not isinstance(remaining_process_ids, list) or len(remaining_process_ids) != 0:
        failures.append(f"{repository} live summary must prove no remaining tracked process ids: {summary_path}")
    if summary.get("install_command") != "npm install express":
        failures.append(f"{repository} live summary install_command mismatch: {summary_path}")
    if summary.get("npm_install_exit_code") != 0:
        failures.append(f"{repository} live summary npm_install_exit_code must be 0: {summary_path}")
    if summary.get("express_package_available") is not True:
        failures.append(f"{repository} live summary must prove Express package availability: {summary_path}")
    if summary.get("node_major_version_at_least_18") is not True:
        failures.append(f"{repository} live summary must prove Node major version is at least 18: {summary_path}")
    if not summary.get("node_path") or not summary.get("npm_path") or not summary.get("node_version") or not summary.get("npm_version"):
        failures.append(f"{repository} live summary must record node/npm path and version evidence: {summary_path}")
    if summary.get("assertion_project_reference_added") is not True:
        failures.append(f"{repository} live summary must prove assertion project reference: {summary_path}")
    package_spec = summary.get("package_spec")
    installed_express_version = summary.get("installed_express_version")
    if not isinstance(package_spec, str) or not package_spec.startswith("express@"):
        failures.append(f"{repository} live summary package_spec must pin express@version: {summary_path}")
    if not installed_express_version:
        failures.append(f"{repository} live summary must record installed Express version: {summary_path}")
    elif package_spec != f"express@{installed_express_version}":
        failures.append(f"{repository} live summary package_spec must match installed Express version: {summary_path}")
    if summary.get("install_execution_command") != f"npm install {package_spec}":
        failures.append(f"{repository} live summary install_execution_command mismatch: {summary_path}")
    if not path_equals(summary.get("manifest"), manifest_path):
        failures.append(f"{repository} live summary manifest path mismatch: {summary_path}")
    if not path_equals(summary.get("runtime_plan"), runtime_plan_path):
        failures.append(f"{repository} live summary runtime_plan path mismatch: {summary_path}")
    if not path_equals(summary.get("transcript"), transcript_path):
        failures.append(f"{repository} live summary transcript path mismatch: {summary_path}")
    if not path_equals(summary.get("response"), response_path):
        failures.append(f"{repository} live summary response path mismatch: {summary_path}")
    if not path_equals(summary.get("run_dir"), run_dir):
        failures.append(f"{repository} live summary run_dir mismatch: {summary_path}")

    for validation_field in ("assertion_build_validation", "build_validation", "template_validation", "live_validation"):
        validation = summary.get(validation_field)
        manifest_field = manifest.get(validation_field)
        if not passed_validation(validation):
            failures.append(f"{repository} live summary missing passed {validation_field}: {summary_path}")
            continue
        if not passed_validation(manifest_field):
            failures.append(f"{repository} manifest missing passed {validation_field}: {manifest_path}")
        elif not same_validation_record(validation, manifest_field):
            failures.append(f"{repository} manifest {validation_field} must equal live summary record: {manifest_path}")
        validation_transcript = Path(str(validation.get("transcript", "")))
        require_under(validation_transcript, live_root, f"{repository} {validation_field} transcript")

    hashes = summary.get("source_hashes", {})
    staged_yaml_path = Path(str(summary.get("runner_yaml", "")))
    staged_runner_root = staged_yaml_path.parent
    source_yaml_path = candidate_dir / "test.qaas.yaml"
    source_payload_path = candidate_dir / "request-payloads" / "get-root.bin"
    staged_payload_path = staged_runner_root / "request-payloads" / "get-root.bin"
    source_app_path = candidate_dir / "app" / "app.mjs"
    staged_app_path = run_dir / "express-work" / "app.mjs"
    source_body_path = candidate_dir / "expectations" / "root-body.txt"
    staged_body_path = staged_runner_root / "expectations" / "root-body.txt"
    source_assertion_path = candidate_dir / "assertion-packets" / "ExactHttpTextBody" / "ExactHttpTextBody.cs"
    staged_assertion_path = Path(str(summary.get("assertion_source", "")))
    expected_hash_paths = (
        ("candidate_yaml_sha256", source_yaml_path, candidate_dir),
        ("staged_yaml_sha256", staged_yaml_path, live_root),
        ("candidate_request_payload_sha256", source_payload_path, candidate_dir),
        ("staged_request_payload_sha256", staged_payload_path, live_root),
        ("candidate_app_sha256", source_app_path, candidate_dir),
        ("staged_app_sha256", staged_app_path, live_root),
        ("candidate_expected_body_sha256", source_body_path, candidate_dir),
        ("staged_expected_body_sha256", staged_body_path, live_root),
        ("candidate_assertion_sha256", source_assertion_path, candidate_dir),
        ("staged_assertion_sha256", staged_assertion_path, live_root),
    )
    for hash_field, path, root in expected_hash_paths:
        require_under(path, root, f"{repository} {hash_field} source")
        actual_hash = sha256_hex(path)
        if actual_hash is not None and hashes.get(hash_field) != actual_hash:
            failures.append(f"{repository} live source hash {hash_field} does not match actual file: {path}")
    for left, right in (
        ("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        ("candidate_app_sha256", "staged_app_sha256"),
        ("candidate_expected_body_sha256", "staged_expected_body_sha256"),
        ("candidate_assertion_sha256", "staged_assertion_sha256"),
    ):
        if hashes.get(left) != hashes.get(right):
            failures.append(f"{repository} live source hash mismatch {left}/{right}: {summary_path}")
    if hashes.get("candidate_yaml_sha256") == hashes.get("staged_yaml_sha256"):
        failures.append(f"{repository} staged live YAML must differ from source YAML because only the staged runner activates ExactHttpTextBody: {summary_path}")

    selected_package_path = Path(str(summary.get("selected_package_evidence", "")))
    selected_readme_path = Path(str(summary.get("selected_readme_evidence", "")))
    selected_example_path = Path(str(summary.get("selected_example_evidence", "")))
    selected_acceptance_path = Path(str(summary.get("selected_acceptance_evidence", "")))
    staged_package_json_path = Path(str(summary.get("staged_package_json", "")))
    package_lock_path = Path(str(summary.get("package_lock", "")))
    installed_express_package_path = Path(str(summary.get("installed_express_package", "")))
    npm_stdout_path = Path(str(summary.get("npm_install_stdout", "")))
    npm_stderr_path = Path(str(summary.get("npm_install_stderr", "")))
    for path, label in (
        (selected_package_path, f"{repository} selected package evidence"),
        (selected_readme_path, f"{repository} selected README evidence"),
        (selected_example_path, f"{repository} selected example evidence"),
        (selected_acceptance_path, f"{repository} selected acceptance evidence"),
    ):
        require_under(path, selected_contracts_root, label)
    for hash_field, path in (
        ("selected_readme_sha256", selected_readme_path),
        ("selected_package_sha256", selected_package_path),
        ("selected_example_sha256", selected_example_path),
        ("selected_acceptance_sha256", selected_acceptance_path),
    ):
        actual_hash = sha256_hex(path)
        if actual_hash is not None and hashes.get(hash_field) != actual_hash:
            failures.append(f"{repository} live selected-evidence hash {hash_field} does not match actual file: {path}")
    for path, label in (
        (staged_package_json_path, f"{repository} staged package.json"),
        (package_lock_path, f"{repository} package-lock.json"),
        (installed_express_package_path, f"{repository} installed Express package.json"),
        (npm_stdout_path, f"{repository} npm install stdout"),
        (npm_stderr_path, f"{repository} npm install stderr"),
    ):
        require_under(path, live_root, label)
    for hash_field, path in (
        ("staged_package_json_sha256", staged_package_json_path),
        ("package_lock_sha256", package_lock_path),
        ("installed_express_package_sha256", installed_express_package_path),
    ):
        actual_hash = sha256_hex(path)
        if actual_hash is not None and hashes.get(hash_field) != actual_hash:
            failures.append(f"{repository} live package hash {hash_field} does not match actual file: {path}")
    selected_package = read_json(selected_package_path)
    selected_version = selected_package.get("version")
    if not selected_version:
        failures.append(f"{repository} selected package evidence must record version: {selected_package_path}")
    elif installed_express_version != selected_version:
        failures.append(f"{repository} installed Express version must match selected package evidence: {summary_path}")
    installed_package = read_json(installed_express_package_path)
    if installed_package.get("name") != "express" or installed_package.get("version") != installed_express_version:
        failures.append(f"{repository} installed Express package evidence mismatch: {installed_express_package_path}")

    if text(response_path) != "Hello World":
        failures.append(f"{repository} live response must exactly match README-backed text body: {response_path}")
    actual_response_sha = sha256_hex(response_path)
    if actual_response_sha is not None and summary.get("response_body_sha256") != actual_response_sha:
        failures.append(f"{repository} live response_body_sha256 does not match actual response file: {response_path}")

    source_yaml_text = text(source_yaml_path)
    staged_yaml_text = text(staged_yaml_path)
    require_no_marker(source_yaml_text, "Assertion: ExactHttpTextBody", source_yaml_path, f"{repository} source YAML must not activate ExactHttpTextBody")
    for marker in ("Assertion: ExactHttpTextBody", "OutputName: GetRoot", "ExpectedText: Hello World", "EncodingName: utf-8", "Route: ''", "Port: 3000", "Name: ExpressReadRoot"):
        require_marker(staged_yaml_text, marker, staged_yaml_path)
    if re.search(r"(?m)^\s*Route:\s*/\s*$", staged_yaml_text):
        failures.append(f"{repository} staged live YAML must use empty root route to avoid double-slash URL: {staged_yaml_path}")

    runner_program_path = Path(str(summary.get("runner_program", "")))
    runner_project_path = Path(str(summary.get("runner_project", "")))
    assertion_project_path = Path(str(summary.get("assertion_project", "")))
    assertion_source_path = Path(str(summary.get("assertion_source", "")))
    for path, label in (
        (runner_program_path, f"{repository} runner Program.cs"),
        (runner_project_path, f"{repository} runner project"),
        (assertion_project_path, f"{repository} assertion project"),
        (assertion_source_path, f"{repository} assertion source"),
    ):
        require_under(path, live_root, label)
        require_no_utf8_bom(path, label)
    if "System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Express.Assertions.ExactHttpTextBody));" not in text(runner_program_path):
        failures.append(f"{repository} runner Program.cs must force-load ExactHttpTextBody assembly: {runner_program_path}")
    runner_project_text = text(runner_project_path)
    if "ProjectReference" not in runner_project_text or "ZappaSelectedExpress.Assertions.csproj" not in runner_project_text:
        failures.append(f"{repository} runner project must reference assertion project: {runner_project_path}")
    if 'PackageReference Include="QaaS.Framework.SDK" Version="1.5.1"' not in text(assertion_project_path):
        failures.append(f"{repository} assertion project must reference QaaS.Framework.SDK 1.5.1: {assertion_project_path}")
    assertion_text = text(assertion_source_path)
    for marker in (
        "namespace ZappaDontCry.SelectedCandidates.Express.Assertions;",
        "BaseAssertion<ExactHttpTextBodyConfig>",
        "using QaaS.Framework.SDK.Extensions;",
        "GetOutputByName(Configuration.OutputName).Data",
        "StringComparison.Ordinal",
    ):
        require_marker(assertion_text, marker, assertion_source_path)

    transcript_text = text(transcript_path)
    for marker in (
        "Validation: selected-top-repo-candidate-live-express",
        "Repository: expressjs/express",
        "NodeCommand: node app.mjs",
        "InstallCommand: npm install express",
        "InstallExecutionCommand: npm install express@",
        "NpmInstallExitCode: 0",
        "ExpressPackageAvailable: True",
        "NodeMajorVersionAtLeast18: True",
        "AssertionProjectReferenceAdded: True",
        "Ready: True",
        "ResponseBodySha256:",
        "AssertionBuildPassed: True",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "ExitCode: 0",
    ):
        require_marker(transcript_text, marker, transcript_path)

    template_transcript_path = Path(str(summary.get("template_validation", {}).get("transcript", "")))
    template_transcript_text = text(template_transcript_path)
    for marker in ("Found IAssertion hook instance ExactHttpTextBody", "Assertion: ExactHttpTextBody", "Runner completed. ExitCode=0"):
        require_marker(template_transcript_text, marker, template_transcript_path)
    live_transcript_path = Path(str(summary.get("live_validation", {}).get("transcript", "")))
    live_transcript_text = text(live_transcript_path)
    for marker in (
        "Found IAssertion hook instance ExactHttpTextBody",
        "HTTP Get request to http://127.0.0.1:3000/ completed with status 200.",
        "Running assertion ExactHttpTextBody GetRootBodyMatchesReadme",
        "Running assertion HttpStatus GetRootReturnedOk",
        "Runner completed. ExitCode=0",
    ):
        require_marker(live_transcript_text, marker, live_transcript_path)
    if "http://127.0.0.1:3000//" in live_transcript_text:
        failures.append(f"{repository} live Runner transcript must not include double-slash route: {live_transcript_path}")


def validate_flask_qaas_evidence(
    manifest: dict,
    runtime_plan: dict,
    manifest_path: Path,
    runtime_plan_path: Path,
):
    repository = "pallets/flask"
    manifest_validation = manifest.get("selected_candidate_qaas_validation")
    runtime_validation = runtime_plan.get("qaas_validation")
    if not passed_validation(manifest_validation):
        failures.append(f"{repository} manifest selected_candidate_qaas_validation must be passed when QaaS is adopted: {manifest_path}")
        return
    if not passed_validation(runtime_validation):
        failures.append(f"{repository} runtime plan qaas_validation must be passed when QaaS is adopted: {runtime_plan_path}")
        return

    for field in ("summary", "transcript", "response", "run_dir"):
        if manifest_validation.get(field) != runtime_validation.get(field):
            failures.append(f"{repository} manifest/runtime QaaS {field} paths must match: {manifest_path}")

    live_root = coverage_dir.parent / "live-runs" / "selected-top-repo-candidates"
    candidate_dir = manifest_path.parent
    summary_path = Path(str(manifest_validation.get("summary", "")))
    transcript_path = Path(str(manifest_validation.get("transcript", "")))
    response_path = Path(str(manifest_validation.get("response", "")))
    run_dir = Path(str(manifest_validation.get("run_dir", "")))
    require_under(summary_path, coverage_dir, f"{repository} live summary")
    require_under(transcript_path, live_root, f"{repository} live transcript")
    require_under(response_path, live_root, f"{repository} live response")
    if not run_dir.exists() or not path_is_relative_to(run_dir, live_root):
        failures.append(f"{repository} live run_dir must exist under {live_root}: {run_dir}")
    if summary_path.name != "selected-top-repo-candidate-live-flask.json":
        failures.append(f"{repository} live summary filename mismatch: {summary_path}")
    if not summary_path.exists():
        return

    summary = read_json(summary_path)
    if summary.get("status") != "passed":
        failures.append(f"{repository} live summary must be passed: {summary_path}")
    if summary.get("repository") != repository:
        failures.append(f"{repository} live summary repository mismatch: {summary_path}")
    if summary.get("validation_kind") != "selected_candidate_qaas_template_live":
        failures.append(f"{repository} live summary validation_kind mismatch: {summary_path}")
    if summary.get("promotion_state") != "blocked" or summary.get("completion_ready") is not False:
        failures.append(f"{repository} live summary must remain blocked and not completion-ready: {summary_path}")
    if summary.get("exit_code") != 0:
        failures.append(f"{repository} live summary exit_code must be 0: {summary_path}")
    if summary.get("manifest_updated") is not True:
        failures.append(f"{repository} live summary must prove manifest_updated true after adoption: {summary_path}")
    if summary.get("weak_validation_passed") is not False:
        failures.append(f"{repository} live summary must not claim weak validation passed: {summary_path}")
    if summary.get("response_status") != 200 or summary.get("response_contract_passed") is not True:
        failures.append(f"{repository} live summary must prove HTTP 200 response contract: {summary_path}")
    if summary.get("cleanup_passed") is not True:
        failures.append(f"{repository} live summary must prove cleanup_passed true: {summary_path}")
    if summary.get("port_owners_after_cleanup_count") != 0:
        failures.append(f"{repository} live summary must prove zero port owners after cleanup: {summary_path}")
    remaining_process_ids = summary.get("remaining_tracked_process_ids", [])
    if not isinstance(remaining_process_ids, list) or len(remaining_process_ids) != 0:
        failures.append(f"{repository} live summary must prove no remaining tracked process ids: {summary_path}")
    if summary.get("install_command") != "python -m pip install Flask":
        failures.append(f"{repository} live summary install_command mismatch: {summary_path}")
    if not summary.get("flask_version"):
        failures.append(f"{repository} live summary must record Flask version: {summary_path}")
    if summary.get("assertion_project_reference_added") is not True:
        failures.append(f"{repository} live summary must prove assertion project reference: {summary_path}")
    if not path_equals(summary.get("manifest"), manifest_path):
        failures.append(f"{repository} live summary manifest path mismatch: {summary_path}")
    if not path_equals(summary.get("runtime_plan"), runtime_plan_path):
        failures.append(f"{repository} live summary runtime_plan path mismatch: {summary_path}")
    if not path_equals(summary.get("transcript"), transcript_path):
        failures.append(f"{repository} live summary transcript path mismatch: {summary_path}")
    if not path_equals(summary.get("response"), response_path):
        failures.append(f"{repository} live summary response path mismatch: {summary_path}")
    if not path_equals(summary.get("run_dir"), run_dir):
        failures.append(f"{repository} live summary run_dir mismatch: {summary_path}")

    for validation_field in ("assertion_build_validation", "build_validation", "template_validation", "live_validation"):
        validation = summary.get(validation_field)
        manifest_field = manifest.get(validation_field)
        if not passed_validation(validation):
            failures.append(f"{repository} live summary missing passed {validation_field}: {summary_path}")
            continue
        if not passed_validation(manifest_field):
            failures.append(f"{repository} manifest missing passed {validation_field}: {manifest_path}")
        elif not same_validation_record(validation, manifest_field):
            failures.append(f"{repository} manifest {validation_field} must equal live summary record: {manifest_path}")
        validation_transcript = Path(str(validation.get("transcript", "")))
        require_under(validation_transcript, live_root, f"{repository} {validation_field} transcript")

    hashes = summary.get("source_hashes", {})
    staged_yaml_path = Path(str(summary.get("runner_yaml", "")))
    staged_runner_root = staged_yaml_path.parent
    source_yaml_path = candidate_dir / "test.qaas.yaml"
    source_payload_path = candidate_dir / "request-payloads" / "get-root.bin"
    staged_payload_path = staged_runner_root / "request-payloads" / "get-root.bin"
    source_app_path = candidate_dir / "app" / "app.py"
    staged_app_path = run_dir / "flask-work" / "app.py"
    source_body_path = candidate_dir / "expectations" / "root-body.txt"
    staged_body_path = staged_runner_root / "expectations" / "root-body.txt"
    source_assertion_path = candidate_dir / "assertion-packets" / "ExactHttpTextBody" / "ExactHttpTextBody.cs"
    staged_assertion_path = Path(str(summary.get("assertion_source", "")))
    expected_hash_paths = (
        ("candidate_yaml_sha256", source_yaml_path, candidate_dir),
        ("staged_yaml_sha256", staged_yaml_path, live_root),
        ("candidate_request_payload_sha256", source_payload_path, candidate_dir),
        ("staged_request_payload_sha256", staged_payload_path, live_root),
        ("candidate_app_sha256", source_app_path, candidate_dir),
        ("staged_app_sha256", staged_app_path, live_root),
        ("candidate_expected_body_sha256", source_body_path, candidate_dir),
        ("staged_expected_body_sha256", staged_body_path, live_root),
        ("candidate_assertion_sha256", source_assertion_path, candidate_dir),
        ("staged_assertion_sha256", staged_assertion_path, live_root),
    )
    for hash_field, path, root in expected_hash_paths:
        require_under(path, root, f"{repository} {hash_field} source")
        actual_hash = sha256_hex(path)
        if actual_hash is not None and hashes.get(hash_field) != actual_hash:
            failures.append(f"{repository} live source hash {hash_field} does not match actual file: {path}")
    for left, right in (
        ("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        ("candidate_app_sha256", "staged_app_sha256"),
        ("candidate_expected_body_sha256", "staged_expected_body_sha256"),
        ("candidate_assertion_sha256", "staged_assertion_sha256"),
    ):
        if hashes.get(left) != hashes.get(right):
            failures.append(f"{repository} live source hash mismatch {left}/{right}: {summary_path}")
    if hashes.get("candidate_yaml_sha256") == hashes.get("staged_yaml_sha256"):
        failures.append(f"{repository} staged live YAML must differ from source YAML because only the staged runner activates ExactHttpTextBody: {summary_path}")

    if text(response_path) != "Hello, World!":
        failures.append(f"{repository} live response must exactly match README-backed text body: {response_path}")
    actual_response_sha = sha256_hex(response_path)
    if actual_response_sha is not None and summary.get("response_body_sha256") != actual_response_sha:
        failures.append(f"{repository} live response_body_sha256 does not match actual response file: {response_path}")

    source_yaml_text = text(source_yaml_path)
    staged_yaml_text = text(staged_yaml_path)
    require_no_marker(source_yaml_text, "Assertion: ExactHttpTextBody", source_yaml_path, f"{repository} source YAML must not activate ExactHttpTextBody")
    for marker in ("Assertion: ExactHttpTextBody", "OutputName: GetRoot", "ExpectedText: Hello, World!", "EncodingName: utf-8", "Route: ''"):
        require_marker(staged_yaml_text, marker, staged_yaml_path)
    if re.search(r"(?m)^\s*Route:\s*/\s*$", staged_yaml_text):
        failures.append(f"{repository} staged live YAML must use empty root route to avoid double-slash URL: {staged_yaml_path}")

    runner_program_path = Path(str(summary.get("runner_program", "")))
    runner_project_path = Path(str(summary.get("runner_project", "")))
    assertion_project_path = Path(str(summary.get("assertion_project", "")))
    assertion_source_path = Path(str(summary.get("assertion_source", "")))
    for path, label in (
        (runner_program_path, f"{repository} runner Program.cs"),
        (runner_project_path, f"{repository} runner project"),
        (assertion_project_path, f"{repository} assertion project"),
        (assertion_source_path, f"{repository} assertion source"),
    ):
        require_under(path, live_root, label)
        require_no_utf8_bom(path, label)
    if "System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Flask.Assertions.ExactHttpTextBody));" not in text(runner_program_path):
        failures.append(f"{repository} runner Program.cs must force-load ExactHttpTextBody assembly: {runner_program_path}")
    runner_project_text = text(runner_project_path)
    if "ProjectReference" not in runner_project_text or "ZappaSelectedFlask.Assertions.csproj" not in runner_project_text:
        failures.append(f"{repository} runner project must reference assertion project: {runner_project_path}")
    if 'PackageReference Include="QaaS.Framework.SDK" Version="1.5.1"' not in text(assertion_project_path):
        failures.append(f"{repository} assertion project must reference QaaS.Framework.SDK 1.5.1: {assertion_project_path}")
    assertion_text = text(assertion_source_path)
    for marker in (
        "BaseAssertion<ExactHttpTextBodyConfig>",
        "using QaaS.Framework.SDK.Extensions;",
        "GetOutputByName(Configuration.OutputName).Data",
        "StringComparison.Ordinal",
    ):
        require_marker(assertion_text, marker, assertion_source_path)

    transcript_text = text(transcript_path)
    for marker in (
        "FlaskCommand: flask run --no-reload --host 127.0.0.1 --port 5000",
        "InstallCommand: python -m pip install Flask",
        "AssertionProjectReferenceAdded: True",
        "Ready: True",
        "AssertionBuildPassed: True",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "ExitCode: 0",
    ):
        require_marker(transcript_text, marker, transcript_path)

    template_transcript_text = text(Path(str(summary.get("template_validation", {}).get("transcript", ""))))
    for marker in ("Found IAssertion hook instance ExactHttpTextBody", "Assertion: ExactHttpTextBody", "Runner completed. ExitCode=0"):
        require_marker(template_transcript_text, marker, Path(str(summary.get("template_validation", {}).get("transcript", ""))))
    live_transcript_path = Path(str(summary.get("live_validation", {}).get("transcript", "")))
    live_transcript_text = text(live_transcript_path)
    for marker in (
        "Found IAssertion hook instance ExactHttpTextBody",
        "HTTP Get request to http://127.0.0.1:5000/ completed with status 200.",
        "Running assertion ExactHttpTextBody GetRootBodyMatchesReadme",
        "Running assertion HttpStatus GetRootReturnedOk",
        "Runner completed. ExitCode=0",
    ):
        require_marker(live_transcript_text, marker, live_transcript_path)
    if "http://127.0.0.1:5000//" in live_transcript_text:
        failures.append(f"{repository} live Runner transcript must not include double-slash route: {live_transcript_path}")


def validate_deno_qaas_evidence(
    manifest: dict,
    runtime_plan: dict,
    manifest_path: Path,
    runtime_plan_path: Path,
):
    repository = "denoland/deno"
    manifest_validation = manifest.get("selected_candidate_qaas_validation")
    runtime_validation = runtime_plan.get("qaas_validation")
    if not passed_validation(manifest_validation):
        failures.append(f"{repository} manifest selected_candidate_qaas_validation must be passed when QaaS is adopted: {manifest_path}")
        return
    if not passed_validation(runtime_validation):
        failures.append(f"{repository} runtime plan qaas_validation must be passed when QaaS is adopted: {runtime_plan_path}")
        return

    for field in ("summary", "transcript", "response", "run_dir"):
        if manifest_validation.get(field) != runtime_validation.get(field):
            failures.append(f"{repository} manifest/runtime QaaS {field} paths must match: {manifest_path}")

    live_root = coverage_dir.parent / "live-runs" / "selected-top-repo-candidates"
    toolchain_root = coverage_dir.parent / "toolchains" / "deno"
    candidate_dir = manifest_path.parent
    summary_path = Path(str(manifest_validation.get("summary", "")))
    transcript_path = Path(str(manifest_validation.get("transcript", "")))
    response_path = Path(str(manifest_validation.get("response", "")))
    run_dir = Path(str(manifest_validation.get("run_dir", "")))
    require_under(summary_path, coverage_dir, f"{repository} live summary")
    require_under(transcript_path, live_root, f"{repository} live transcript")
    require_under(response_path, live_root, f"{repository} live response")
    if not run_dir.exists() or not path_is_relative_to(run_dir, live_root):
        failures.append(f"{repository} live run_dir must exist under {live_root}: {run_dir}")
    if summary_path.name != "selected-top-repo-candidate-live-deno.json":
        failures.append(f"{repository} live summary filename mismatch: {summary_path}")
    if not summary_path.exists():
        return

    summary = read_json(summary_path)
    if summary.get("status") != "passed":
        failures.append(f"{repository} live summary must be passed: {summary_path}")
    if summary.get("repository") != repository:
        failures.append(f"{repository} live summary repository mismatch: {summary_path}")
    if summary.get("validation_kind") != "selected_candidate_qaas_template_live":
        failures.append(f"{repository} live summary validation_kind mismatch: {summary_path}")
    if summary.get("promotion_state") != "blocked" or summary.get("completion_ready") is not False:
        failures.append(f"{repository} live summary must remain blocked and not completion-ready: {summary_path}")
    if summary.get("exit_code") != 0:
        failures.append(f"{repository} live summary exit_code must be 0: {summary_path}")
    if summary.get("manifest_updated") is not True:
        failures.append(f"{repository} live summary must prove manifest_updated true after adoption: {summary_path}")
    if summary.get("weak_validation_passed") is not False:
        failures.append(f"{repository} live summary must not claim weak validation passed: {summary_path}")
    if summary.get("response_status") != 200 or summary.get("response_contract_passed") is not True:
        failures.append(f"{repository} live summary must prove HTTP 200 response contract: {summary_path}")
    if summary.get("cleanup_passed") is not True:
        failures.append(f"{repository} live summary must prove cleanup_passed true: {summary_path}")
    if summary.get("port_owners_after_cleanup_count") != 0:
        failures.append(f"{repository} live summary must prove zero port owners after cleanup: {summary_path}")
    remaining_process_ids = summary.get("remaining_tracked_process_ids", [])
    if not isinstance(remaining_process_ids, list) or len(remaining_process_ids) != 0:
        failures.append(f"{repository} live summary must prove no remaining tracked process ids: {summary_path}")
    if summary.get("assertion_project_reference_added") is not True:
        failures.append(f"{repository} live summary must prove assertion project reference: {summary_path}")
    if not str(summary.get("deno_version", "")).startswith("deno 2.8.2"):
        failures.append(f"{repository} live summary must prove managed Deno 2.8.2: {summary_path}")
    if summary.get("managed_toolchain_archive_sha256") != "6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9":
        failures.append(f"{repository} live summary managed toolchain SHA mismatch: {summary_path}")
    deno_path = Path(str(summary.get("deno_path", "")))
    require_under(deno_path, toolchain_root, f"{repository} managed deno_path")
    if not path_equals(summary.get("manifest"), manifest_path):
        failures.append(f"{repository} live summary manifest path mismatch: {summary_path}")
    if not path_equals(summary.get("runtime_plan"), runtime_plan_path):
        failures.append(f"{repository} live summary runtime_plan path mismatch: {summary_path}")
    if not path_equals(summary.get("transcript"), transcript_path):
        failures.append(f"{repository} live summary transcript path mismatch: {summary_path}")
    if not path_equals(summary.get("response"), response_path):
        failures.append(f"{repository} live summary response path mismatch: {summary_path}")
    if not path_equals(summary.get("run_dir"), run_dir):
        failures.append(f"{repository} live summary run_dir mismatch: {summary_path}")

    for validation_field in ("assertion_build_validation", "build_validation", "template_validation", "live_validation"):
        validation = summary.get(validation_field)
        manifest_field = manifest.get(validation_field)
        if not passed_validation(validation):
            failures.append(f"{repository} live summary missing passed {validation_field}: {summary_path}")
            continue
        if not passed_validation(manifest_field):
            failures.append(f"{repository} manifest missing passed {validation_field}: {manifest_path}")
        elif not same_validation_record(validation, manifest_field):
            failures.append(f"{repository} manifest {validation_field} must equal live summary record: {manifest_path}")
        validation_transcript = Path(str(validation.get("transcript", "")))
        require_under(validation_transcript, live_root, f"{repository} {validation_field} transcript")

    hashes = summary.get("source_hashes", {})
    staged_yaml_path = Path(str(summary.get("runner_yaml", "")))
    staged_runner_root = staged_yaml_path.parent
    source_yaml_path = candidate_dir / "test.qaas.yaml"
    source_payload_path = candidate_dir / "request-payloads" / "get-root.bin"
    staged_payload_path = staged_runner_root / "request-payloads" / "get-root.bin"
    source_server_path = candidate_dir / "app" / "server.ts"
    staged_server_path = run_dir / "deno-work" / "server.ts"
    source_body_path = candidate_dir / "expectations" / "root-body.txt"
    staged_body_path = staged_runner_root / "expectations" / "root-body.txt"
    source_assertion_path = candidate_dir / "assertion-packets" / "ExactHttpTextBody" / "ExactHttpTextBody.cs"
    staged_assertion_path = Path(str(summary.get("assertion_source", "")))
    selected_readme_path = Path(str(summary.get("selected_readme_evidence", "")))
    expected_hash_paths = (
        ("candidate_yaml_sha256", source_yaml_path, candidate_dir),
        ("staged_yaml_sha256", staged_yaml_path, live_root),
        ("candidate_request_payload_sha256", source_payload_path, candidate_dir),
        ("staged_request_payload_sha256", staged_payload_path, live_root),
        ("candidate_server_sha256", source_server_path, candidate_dir),
        ("staged_server_sha256", staged_server_path, live_root),
        ("candidate_expected_body_sha256", source_body_path, candidate_dir),
        ("staged_expected_body_sha256", staged_body_path, live_root),
        ("candidate_assertion_sha256", source_assertion_path, candidate_dir),
        ("staged_assertion_sha256", staged_assertion_path, live_root),
        ("selected_readme_sha256", selected_readme_path, selected_contracts_root),
    )
    for hash_field, path, root in expected_hash_paths:
        require_under(path, root, f"{repository} {hash_field} source")
        actual_hash = sha256_hex(path)
        if actual_hash is not None and hashes.get(hash_field) != actual_hash:
            failures.append(f"{repository} live source hash {hash_field} does not match actual file: {path}")
    for left, right in (
        ("candidate_request_payload_sha256", "staged_request_payload_sha256"),
        ("candidate_server_sha256", "staged_server_sha256"),
        ("candidate_expected_body_sha256", "staged_expected_body_sha256"),
        ("candidate_assertion_sha256", "staged_assertion_sha256"),
    ):
        if hashes.get(left) != hashes.get(right):
            failures.append(f"{repository} live source hash mismatch {left}/{right}: {summary_path}")
    if hashes.get("candidate_yaml_sha256") == hashes.get("staged_yaml_sha256"):
        failures.append(f"{repository} staged live YAML must differ from source YAML because only the staged runner activates ExactHttpTextBody: {summary_path}")

    if text(response_path) != "Hello, world!":
        failures.append(f"{repository} live response must exactly match README-backed text body: {response_path}")
    actual_response_sha = sha256_hex(response_path)
    if actual_response_sha is not None and summary.get("response_body_sha256") != actual_response_sha:
        failures.append(f"{repository} live response_body_sha256 does not match actual response file: {response_path}")

    source_yaml_text = text(source_yaml_path)
    staged_yaml_text = text(staged_yaml_path)
    require_no_marker(source_yaml_text, "Assertion: ExactHttpTextBody", source_yaml_path, f"{repository} source YAML must not activate ExactHttpTextBody")
    for marker in ("Assertion: ExactHttpTextBody", "OutputName: GetRoot", "ExpectedText: Hello, world!", "EncodingName: utf-8", "Route: ''"):
        require_marker(staged_yaml_text, marker, staged_yaml_path)
    if re.search(r"(?m)^\s*Route:\s*/\s*$", staged_yaml_text):
        failures.append(f"{repository} staged live YAML must use empty root route to avoid double-slash URL: {staged_yaml_path}")

    runner_program_path = Path(str(summary.get("runner_program", "")))
    runner_project_path = Path(str(summary.get("runner_project", "")))
    assertion_project_path = Path(str(summary.get("assertion_project", "")))
    assertion_source_path = Path(str(summary.get("assertion_source", "")))
    for path, label in (
        (runner_program_path, f"{repository} runner Program.cs"),
        (runner_project_path, f"{repository} runner project"),
        (assertion_project_path, f"{repository} assertion project"),
        (assertion_source_path, f"{repository} assertion source"),
    ):
        require_under(path, live_root, label)
        require_no_utf8_bom(path, label)
    if "System.GC.KeepAlive(typeof(ZappaDontCry.SelectedCandidates.Deno.Assertions.ExactHttpTextBody));" not in text(runner_program_path):
        failures.append(f"{repository} runner Program.cs must force-load ExactHttpTextBody assembly: {runner_program_path}")
    runner_project_text = text(runner_project_path)
    if "ProjectReference" not in runner_project_text or "ZappaSelectedDeno.Assertions.csproj" not in runner_project_text:
        failures.append(f"{repository} runner project must reference assertion project: {runner_project_path}")
    if 'PackageReference Include="QaaS.Framework.SDK" Version="1.5.1"' not in text(assertion_project_path):
        failures.append(f"{repository} assertion project must reference QaaS.Framework.SDK 1.5.1: {assertion_project_path}")
    assertion_text = text(assertion_source_path)
    for marker in (
        "BaseAssertion<ExactHttpTextBodyConfig>",
        "using QaaS.Framework.SDK.Extensions;",
        "GetOutputByName(Configuration.OutputName).Data",
        "StringComparison.Ordinal",
    ):
        require_marker(assertion_text, marker, assertion_source_path)

    transcript_text = text(transcript_path)
    for marker in (
        "Validation: selected-top-repo-candidate-live-deno",
        "Repository: denoland/deno",
        "DenoCommand: deno run --allow-net server.ts",
        "DenoVersion: deno 2.8.2",
        "DenoDir:",
        "ManagedToolchainArchiveSha256: 6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9",
        "AssertionProjectReferenceAdded: True",
        "Ready: True",
        "ResponseBodySha256:",
        "AssertionBuildPassed: True",
        "BuildPassed: True",
        "TemplatePassed: True",
        "LivePassed: True",
        "CleanupPassed: True",
        "ExitCode: 0",
    ):
        require_marker(transcript_text, marker, transcript_path)

    template_transcript_path = Path(str(summary.get("template_validation", {}).get("transcript", "")))
    template_transcript_text = text(template_transcript_path)
    for marker in ("Found IAssertion hook instance ExactHttpTextBody", "Assertion: ExactHttpTextBody", "Runner completed. ExitCode=0"):
        require_marker(template_transcript_text, marker, template_transcript_path)
    live_transcript_path = Path(str(summary.get("live_validation", {}).get("transcript", "")))
    live_transcript_text = text(live_transcript_path)
    for marker in (
        "Found IAssertion hook instance ExactHttpTextBody",
        "HTTP Get request to http://127.0.0.1:8000/ completed with status 200.",
        "Running assertion ExactHttpTextBody GetRootBodyMatchesReadme",
        "Running assertion HttpStatus GetRootReturnedOk",
        "Runner completed. ExitCode=0",
    ):
        require_marker(live_transcript_text, marker, live_transcript_path)
    if "http://127.0.0.1:8000//" in live_transcript_text:
        failures.append(f"{repository} live Runner transcript must not include double-slash route: {live_transcript_path}")


def selected_supports(selected: dict) -> set[str]:
    return {
        item.get("supports")
        for item in selected.get("candidate_promotion_contracts", [])
        if isinstance(item, dict)
    }


def get_gate_map(manifest: dict) -> dict[str, dict]:
    return {
        gate.get("gate_id"): gate
        for gate in manifest.get("dependency_gates", [])
        if isinstance(gate, dict)
    }


def get_blocker_ids(manifest: dict) -> set[str]:
    return {
        blocker.get("blocker_id")
        for blocker in manifest.get("source_only_blockers", [])
        if isinstance(blocker, dict)
    }


def get_advisory_ids(manifest: dict) -> set[str]:
    return {
        advisory.get("advisory_id")
        for advisory in manifest.get("validation_advisories", [])
        if isinstance(advisory, dict)
    }


def validate_httpstatus_docs_advisory(manifest: dict, manifest_path: Path, qaas_passed: bool, label: str):
    blockers = get_blocker_ids(manifest)
    advisories = get_advisory_ids(manifest)
    if qaas_passed:
        if HTTPSTATUS_DOCS_ADVISORY_ID in blockers:
            failures.append(
                f"{label} candidate manifest should move {HTTPSTATUS_DOCS_ADVISORY_ID} "
                f"from source_only_blockers to validation_advisories after QaaS validation passes: {manifest_path}"
            )
        if HTTPSTATUS_DOCS_ADVISORY_ID not in advisories:
            failures.append(
                f"{label} candidate manifest missing non-blocking validation advisory "
                f"{HTTPSTATUS_DOCS_ADVISORY_ID}: {manifest_path}"
            )
    else:
        if HTTPSTATUS_DOCS_ADVISORY_ID not in blockers:
            failures.append(f"{label} candidate manifest missing source blocker {HTTPSTATUS_DOCS_ADVISORY_ID}: {manifest_path}")


def validate_common_candidate(
    record: dict,
    manifest: dict,
    selected: dict,
    manifest_path: Path,
    selected_path: Path,
    candidate_dir: Path,
    expected_assertion_marker: str = "Assertion: HttpStatus",
    expected_status_marker: str = "StatusCode: 200",
):
    repository = record.get("repository")
    if manifest.get("source_repository") != repository:
        failures.append(f"manifest source_repository does not match index record: {manifest_path}")
    if selected.get("repository") != repository:
        failures.append(f"selected contract repository does not match index record: {selected_path}")
    if manifest.get("selected_contract") != str(selected_path):
        failures.append(f"manifest selected_contract mismatch: {manifest_path}")
    if manifest.get("status") != "blocked_until_repo_contract_review":
        failures.append(f"candidate manifest status must stay blocked_until_repo_contract_review: {manifest_path}")
    if manifest.get("promotion_state") != "blocked":
        failures.append(f"candidate manifest promotion_state must stay blocked: {manifest_path}")
    if not manifest.get("blocked_reason"):
        failures.append(f"candidate manifest missing blocked_reason: {manifest_path}")

    if selected.get("status") != "contract_content_harvested_not_executable":
        failures.append(f"selected contract must be content-harvested only: {selected_path}")
    if selected.get("promotion_state") != "blocked":
        failures.append(f"selected contract promotion_state must stay blocked: {selected_path}")
    for selected_file in selected.get("selected_public_contracts", []):
        if not isinstance(selected_file, dict):
            failures.append(f"selected_public_contracts item is not an object: {selected_path}")
            continue
        source_path = str(selected_file.get("source_path", ""))
        if (
            not source_path
            or source_path.startswith(("/", "\\"))
            or "\\" in source_path
            or ":" in source_path
            or ".." in Path(source_path).parts
        ):
            failures.append(f"selected public contract has unsafe source_path {source_path!r}: {selected_path}")
        sha = selected_file.get("sha")
        blob_url = str(selected_file.get("github_blob_url", ""))
        if selected_file.get("git_blob_sha_verified") is not True:
            failures.append(f"selected public contract lacks git_blob_sha_verified: {selected_path}: {source_path}")
        if not sha or not blob_url.endswith(f"/git/blobs/{sha}"):
            failures.append(f"selected public contract must use immutable Git blob URL: {selected_path}: {source_path}")
        if "raw.githubusercontent.com" in blob_url or "/blob/main/" in blob_url or "/raw/" in blob_url:
            failures.append(f"selected public contract uses mutable/raw GitHub URL: {selected_path}: {source_path}")

    supports = selected_supports(selected)
    if "executable-command" in supports:
        failures.append(f"selected contract must not claim executable-command support: {selected_path}")

    artifacts = [Path(path) for path in manifest.get("artifacts", [])]
    if manifest.get("artifact_count") != len(artifacts):
        failures.append(f"artifact_count mismatch: {manifest_path}")
    for artifact in artifacts:
        require_under(artifact, candidate_dir, "candidate artifact")
        require_no_utf8_bom(artifact, "candidate artifact")
        if path_is_relative_to(artifact, selected_contracts_root):
            failures.append(f"candidate artifact must not be written under selected evidence root: {artifact}")

    require_no_utf8_bom(manifest_path, "candidate manifest")

    runner_path = candidate_dir / "test.qaas.yaml"
    runtime_plan_path = candidate_dir / "candidate-runtime-plan.json"
    for required_artifact in (runner_path, runtime_plan_path, manifest_path):
        if required_artifact not in artifacts:
            failures.append(f"required artifact not listed in manifest artifacts: {required_artifact}")
        require_under(required_artifact, candidate_dir, "required candidate artifact")

    yaml = text(runner_path)
    require_marker(yaml, "blocked_until_template_live_airgapped_validation", runner_path)
    require_marker(yaml, "Storages:", runner_path)
    require_marker(yaml, "Generator: FromFileSystem", runner_path)
    if expected_assertion_marker:
        require_marker(yaml, expected_assertion_marker, runner_path)
    if expected_status_marker:
        require_marker(yaml, expected_status_marker, runner_path)
    require_marker(yaml, "OutputNames:", runner_path)
    require_marker(yaml, "BaseAddress: http://127.0.0.1", runner_path)
    require_marker(yaml, "Method: Get", runner_path)
    require_no_marker(yaml, "Generator: FromCSV", runner_path, "candidate YAML uses stale FromCSV generator instead of file-backed bytes")
    require_no_marker(yaml, "ExpectedStatus:", runner_path, "candidate YAML uses stale HttpStatus ExpectedStatus field")
    for invented_key in ("CandidateContracts", "PromotionEvidence", "ExecutableCommand"):
        if re.search(rf"(?m)^{invented_key}\s*:", yaml):
            failures.append(f"candidate YAML uses invented top-level {invented_key} key: {runner_path}")
    if re.search(r"(?mi)^\s*(Process|Startup|StartCommand|CleanupCommand|CommandLine|Shell|WorkingDirectory)\s*:", yaml):
        failures.append(f"candidate YAML uses undocumented process lifecycle fields: {runner_path}")

    for evidence_path in manifest.get("docs_evidence", []):
        if not Path(evidence_path).exists():
            failures.append(f"candidate docs_evidence path missing: {manifest_path}: {evidence_path}")
    for evidence_path in manifest.get("public_evidence", []):
        resolved_evidence_path = Path(evidence_path)
        if not resolved_evidence_path.exists():
            failures.append(f"candidate public_evidence path missing: {manifest_path}: {evidence_path}")
            continue
        if path_is_relative_to(resolved_evidence_path, candidate_root):
            failures.append(f"candidate public_evidence must not point to generated candidate artifacts: {manifest_path}: {evidence_path}")

    for nested_manifest_path in candidate_dir.rglob("qaas-artifact-manifest.json"):
        nested = read_json(nested_manifest_path)
        if nested.get("promotion_state") == "executable":
            failures.append(f"selected candidate manifest must not be executable: {nested_manifest_path}")

    airgapped = manifest.get("airgapped_validation")
    if not isinstance(airgapped, dict) or airgapped.get("status") == "passed":
        failures.append(f"candidate manifest must not have passed airgapped validation: {manifest_path}")

    return artifacts, yaml, read_json(runtime_plan_path), runtime_plan_path


def validate_common_gates(manifest: dict, manifest_path: Path, lifecycle_passed: bool, qaas_passed: bool, lifecycle_gate_ids: tuple[str, ...]):
    gates = get_gate_map(manifest)
    for ready_gate in ("selected-public-runtime-contract", "selected-public-input-output-contract", "qaas-docs-yaml-shape"):
        gate = gates.get(ready_gate)
        if not gate or gate.get("status") != "ready" or not gate.get("evidence"):
            failures.append(f"candidate ready gate missing evidence or ready status {ready_gate}: {manifest_path}")
    for lifecycle_gate in lifecycle_gate_ids:
        gate = gates.get(lifecycle_gate)
        if lifecycle_passed:
            if not gate or gate.get("status") != "passed" or not gate.get("evidence"):
                failures.append(f"candidate lifecycle gate missing passed status/evidence {lifecycle_gate}: {manifest_path}")
        else:
            if not gate or gate.get("status") != "blocked" or not gate.get("blocked_reason"):
                failures.append(f"candidate lifecycle gate missing blocked status/reason {lifecycle_gate}: {manifest_path}")
    cleanup_gate = gates.get("cleanup-contract")
    if lifecycle_passed:
        if not cleanup_gate or cleanup_gate.get("status") != "passed" or not cleanup_gate.get("evidence"):
            failures.append(f"candidate cleanup gate missing passed status/evidence: {manifest_path}")
    elif not cleanup_gate or cleanup_gate.get("status") != "blocked" or not cleanup_gate.get("blocked_reason"):
        failures.append(f"candidate cleanup gate missing blocked status/reason: {manifest_path}")
    for qaas_gate in ("qaas-template", "qaas-live-act-assert"):
        gate = gates.get(qaas_gate)
        if qaas_passed:
            if not gate or gate.get("status") != "passed" or not gate.get("evidence"):
                failures.append(f"candidate QaaS gate missing passed status/evidence {qaas_gate}: {manifest_path}")
        else:
            if not gate or gate.get("status") != "blocked" or not gate.get("blocked_reason"):
                failures.append(f"candidate QaaS gate missing blocked status/reason {qaas_gate}: {manifest_path}")
    gate = gates.get("airgapped-validation")
    if not gate or gate.get("status") != "blocked" or not gate.get("blocked_reason"):
        failures.append(f"candidate blocked gate missing blocked status/reason airgapped-validation: {manifest_path}")


def selected_file_path(selected: dict, source_path: str) -> Path | None:
    for selected_file in selected.get("selected_public_contracts", []):
        if isinstance(selected_file, dict) and selected_file.get("source_path") == source_path:
            return Path(str(selected_file.get("local_path", "")))
    return None


def validate_crawl4ai_deferred(deferred: dict, selected_path: Path, index_path: Path):
    blockers = set(deferred.get("blockers", []))
    for blocker in (
        "selected_input_output_contract_missing",
        "selected_crawl_response_is_branching_async_or_results_contract",
        "selected_healthcheck_status_is_not_exact_http_contract",
        "selected_healthcheck_body_contract_missing",
        "docker_runtime_requires_live_container_safety_plan",
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence",
    ):
        if blocker not in blockers:
            failures.append(f"Crawl4AI deferred record missing blocker {blocker}: {index_path}")
    if deferred.get("deferred_reason") != "selected_public_contract_lacks_exact_input_output_contract":
        failures.append(f"Crawl4AI deferred record missing exact deferred_reason: {index_path}")
    for list_field in ("unsafe_promotion_risks", "required_before_generation"):
        values = deferred.get(list_field)
        if not isinstance(values, list) or len(values) < 3:
            failures.append(f"Crawl4AI deferred record missing {list_field}: {index_path}")

    if not selected_path.exists():
        return
    selected = read_json(selected_path)
    supports = selected_supports(selected)
    if "candidate-executable-command" not in supports:
        failures.append(f"Crawl4AI selected contract must retain docker executable-command evidence while deferred: {selected_path}")
    if "input-output-contract" in supports:
        failures.append(f"Crawl4AI deferred record must be revisited because selected contract now claims input-output-contract: {selected_path}")

    required_paths = {
        "README.md": (
            "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest",
            "http://localhost:11235/crawl",
            "if response.status_code == 200:",
            'if "results" in response.json():',
            'task_id = response.json()["task_id"]',
        ),
        "Dockerfile": (
            "curl -f http://localhost:11235/health || exit 1",
            "redis-cli ping",
            "MEM=$(free -m",
        ),
        "docker-compose.yml": (
            'test: ["CMD", "curl", "-f", "http://localhost:11235/health"]',
            "memory: 4G",
            "memory: 1G",
            "/dev/shm:/dev/shm",
        ),
        "deploy/docker/schemas.py": (
            "class CrawlRequest(BaseModel):",
            "urls: List[str] = Field(min_length=1, max_length=100)",
        ),
    }
    for source_path, markers in required_paths.items():
        evidence_path = selected_file_path(selected, source_path)
        if evidence_path is None:
            failures.append(f"Crawl4AI deferred evidence missing selected file {source_path}: {selected_path}")
            continue
        require_under(evidence_path, selected_contracts_root, "Crawl4AI deferred evidence")
        evidence_text = text(evidence_path)
        for marker in markers:
            require_marker(evidence_text, marker, evidence_path)


def validate_exact_http_text_body_packet(
    packet,
    owner_path: Path,
    expected_body_sha: str,
    candidate_dir: Path,
    label: str,
    qaas_passed: bool = False,
    expected_packet_id: str = "flask-exact-http-text-body",
):
    if not isinstance(packet, dict):
        failures.append(f"{label} is not an object: {owner_path}")
        return

    expected_status = "build_template_live_validated_blocked_until_airgapped" if qaas_passed else "blocked_until_build_template_live_airgapped_validation"
    expected_activation = "staged_live_runner_only" if qaas_passed else "sidecar_only"
    expected_packet_values = {
        "packet_id": expected_packet_id,
        "assertion_name": "ExactHttpTextBody",
        "status": expected_status,
        "promotion_state": "blocked",
        "activation": expected_activation,
        "encoding": "utf-8",
        "comparison": "byte_for_byte",
        "normalization": "none",
    }
    for field, expected in expected_packet_values.items():
        if packet.get(field) != expected:
            failures.append(f"{label} {field} must be {expected!r}: {owner_path}")
    if packet.get("wired_into_runner_yaml") is not qaas_passed:
        failures.append(f"{label} wired_into_runner_yaml must be {qaas_passed}: {owner_path}")
    for field in ("trim", "contains", "weak_validation_passed"):
        if packet.get(field) is not False:
            failures.append(f"{label} {field} must be false: {owner_path}")
    if packet.get("case_sensitive") is not True:
        failures.append(f"{label} must be case_sensitive true: {owner_path}")
    if expected_body_sha and packet.get("expected_body_sha256") != expected_body_sha:
        failures.append(f"{label} expected_body_sha256 mismatch: {owner_path}")
    for field in ("yaml_fragment", "hook_plan", "expected_body_path"):
        packet_path = Path(str(packet.get(field, "")))
        require_under(packet_path, candidate_dir, f"{label} {field}")
    for source_file in packet.get("source_files", []):
        source_path = Path(str(source_file))
        require_under(source_path, candidate_dir, f"{label} source file")
        if "assertion-packets" not in source_path.parts:
            failures.append(f"{label} source must live under assertion-packets: {source_path}")
    if packet.get("wired_into_runner_yaml") is False and packet.get("yaml_fragment") and Path(str(packet.get("yaml_fragment"))).suffix.lower() in {".yaml", ".yml"}:
        failures.append(f"{label} sidecar YAML fragment must not be executable YAML: {packet.get('yaml_fragment')}")
    validation_records = packet.get("validation_records")
    if not isinstance(validation_records, dict):
        failures.append(f"{label} missing validation_records: {owner_path}")
    else:
        for field in ("build", "schema", "template", "live"):
            expected_validation = "passed" if qaas_passed else "not_run"
            if validation_records.get(field) != expected_validation:
                failures.append(f"{label} validation {field} must be {expected_validation}: {owner_path}")
        if validation_records.get("airgapped") != "not_run":
            failures.append(f"{label} validation airgapped must remain not_run: {owner_path}")


def validate_http_status_below_400_packet(packet, owner_path: Path, candidate_dir: Path, label: str, qaas_passed: bool = False):
    if not isinstance(packet, dict):
        failures.append(f"{label} is not an object: {owner_path}")
        return

    expected_status = "build_template_live_validated_blocked_until_airgapped" if qaas_passed else "blocked_until_build_template_live_airgapped_validation"
    expected_activation = "staged_live_runner_only" if qaas_passed else "source_yaml_blocked"
    expected_packet_values = {
        "packet_id": "crawl4ai-http-status-below-400",
        "assertion_name": "HttpStatusBelow400",
        "status": expected_status,
        "promotion_state": "blocked",
        "activation": expected_activation,
        "wired_into_runner_yaml": True,
        "output_body_assertion": "unasserted_no_public_body_contract",
        "maximum_exclusive_status_code": 400,
        "comparison": "http_status_less_than",
    }
    for field, expected in expected_packet_values.items():
        if packet.get(field) != expected:
            failures.append(f"{label} {field} must be {expected!r}: {owner_path}")

    for field in ("yaml_fragment", "hook_plan"):
        packet_path = Path(str(packet.get(field, "")))
        require_under(packet_path, candidate_dir, f"{label} {field}")
    for source_file in packet.get("source_files", []):
        source_path = Path(str(source_file))
        require_under(source_path, candidate_dir, f"{label} source file")
        if "assertion-packets" not in source_path.parts:
            failures.append(f"{label} source must live under assertion-packets: {source_path}")

    validation_records = packet.get("validation_records")
    if not isinstance(validation_records, dict):
        failures.append(f"{label} missing validation_records: {owner_path}")
    else:
        for field in ("build", "schema", "template", "live"):
            expected_validation = "passed" if qaas_passed else "not_run"
            if validation_records.get(field) != expected_validation:
                failures.append(f"{label} validation {field} must be {expected_validation}: {owner_path}")
        if validation_records.get("airgapped") != "not_run":
            failures.append(f"{label} validation airgapped must remain not_run: {owner_path}")


def validate_json_server(record: dict, manifest: dict, selected: dict, manifest_path: Path, selected_path: Path, candidate_dir: Path):
    supports = selected_supports(selected)
    for required_support in ("runtime-contract", "http-contract", "candidate-executable-command", "input-output-contract"):
        if required_support not in supports:
            failures.append(f"selected contract lacks candidate support {required_support}: {selected_path}")

    artifacts, yaml, runtime_plan, runtime_plan_path = validate_common_candidate(record, manifest, selected, manifest_path, selected_path, candidate_dir)

    runner_path = candidate_dir / "test.qaas.yaml"
    db_path = candidate_dir / "fixtures" / "db.json"
    expectation_path = candidate_dir / "expectations" / "posts-1.csv"
    request_payload_path = candidate_dir / "request-payloads" / "get-post-one.bin"
    for required_artifact in (db_path, expectation_path, request_payload_path):
        if required_artifact not in artifacts:
            failures.append(f"required artifact not listed in manifest artifacts: {required_artifact}")
        require_under(required_artifact, candidate_dir, "required candidate artifact")

    require_marker(yaml, "Name: GetPostOnePayload", runner_path)
    require_marker(yaml, "Path: './request-payloads'", runner_path)
    require_marker(yaml, "SearchPattern: 'get-post-one.bin'", runner_path)
    require_marker(yaml, "Name: ExpectedPostOneCsv", runner_path)
    require_marker(yaml, "Path: './expectations'", runner_path)
    require_marker(yaml, "SearchPattern: 'posts-1.csv'", runner_path)
    require_marker(yaml, "Assertion: OutputContentByExpectedCsvResults", runner_path)
    require_marker(yaml, "ColumnNameToFieldPathMap:", runner_path)
    require_marker(yaml, "Port: 3000", runner_path)
    require_marker(yaml, "Route: /posts/1", runner_path)
    require_marker(yaml, "OutputDeserialize:", runner_path)
    require_marker(yaml, "Deserializer: Json", runner_path)
    if "npx json-server" in yaml:
        failures.append(f"candidate YAML embeds external process command instead of runtime plan: {runner_path}")
    if not re.search(r"(?s)Transactions:.*DataSourceNames:\s*\n\s*-\s*GetPostOnePayload.*DataSourcePatterns:\s*\n\s*-\s*GetPostOnePayload", yaml):
        failures.append(f"candidate transaction must be driven by GetPostOnePayload DataSourceNames and DataSourcePatterns: {runner_path}")

    try:
        db = json.loads(db_path.read_text(encoding="utf-8-sig"))
        post = db["posts"][0]
        if post != {"id": "1", "title": "a title", "views": 100}:
            failures.append(f"candidate db.json first post does not match README evidence: {db_path}")
    except Exception as exc:
        failures.append(f"failed to validate candidate db.json {db_path}: {exc}")

    try:
        payload_bytes = request_payload_path.read_bytes()
        if payload_bytes != b"":
            failures.append(f"candidate GET payload driver must be an empty byte file: {request_payload_path}")
    except Exception as exc:
        failures.append(f"failed to validate request payload {request_payload_path}: {exc}")

    try:
        with expectation_path.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))
        expected_rows = [
            {"id": "1", "title": "a title", "views": "100"},
            {"id": "1", "title": "a title", "views": "100"},
        ]
        if rows != expected_rows:
            failures.append(f"candidate expected CSV does not match README evidence: {expectation_path}")
    except Exception as exc:
        failures.append(f"failed to validate expected CSV {expectation_path}: {exc}")

    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation"))
    qaas_passed = (
        passed_validation(manifest.get("build_validation"))
        and passed_validation(manifest.get("template_validation"))
        and passed_validation(manifest.get("live_validation"))
        and passed_validation(manifest.get("selected_candidate_qaas_validation"))
        and passed_validation(runtime_plan.get("qaas_validation"))
    )
    validate_runtime_plan_common(runtime_plan, runtime_plan_path, "typicode/json-server", "npx json-server db.json", lifecycle_passed, qaas_passed)

    if runtime_plan.get("command_support") != "candidate-executable-command":
        failures.append(f"runtime plan must use candidate-executable-command support: {runtime_plan_path}")
    cleanup = runtime_plan.get("cleanup")
    if not isinstance(cleanup, dict):
        failures.append(f"runtime plan cleanup missing: {runtime_plan_path}")
    elif cleanup.get("status") == "passed" and not lifecycle_passed:
        failures.append(f"runtime plan cleanup passed without manifest lifecycle_validation: {runtime_plan_path}")
    elif cleanup.get("status") != "passed" and lifecycle_passed:
        failures.append(f"runtime plan cleanup must be passed when manifest lifecycle_validation passed: {runtime_plan_path}")

    blockers = get_blocker_ids(manifest)
    required_blockers = [
        "live-airgapped-weak-model-not-passed",
    ]
    validate_httpstatus_docs_advisory(manifest, manifest_path, qaas_passed, "json-server")
    if qaas_passed:
        if "qaas-template-live-not-run" in blockers:
            failures.append(f"candidate manifest still contains satisfied blocker qaas-template-live-not-run: {manifest_path}")
    else:
        required_blockers.append("qaas-template-live-not-run")
    if not lifecycle_passed:
        required_blockers.append("json-server-process-lifecycle-not-proven")
    elif "json-server-process-lifecycle-not-proven" in blockers:
        failures.append(f"candidate manifest still contains satisfied blocker json-server-process-lifecycle-not-proven: {manifest_path}")
    for blocker_id in required_blockers:
        if blocker_id not in blockers:
            failures.append(f"candidate manifest missing source blocker {blocker_id}: {manifest_path}")

    validate_common_gates(manifest, manifest_path, lifecycle_passed, qaas_passed, ("node-json-server-process-lifecycle",))


def validate_express(record: dict, manifest: dict, selected: dict, manifest_path: Path, selected_path: Path, candidate_dir: Path):
    supports = selected_supports(selected)
    for required_support in ("runtime-contract", "input-output-contract"):
        if required_support not in supports:
            failures.append(f"selected contract lacks candidate support {required_support}: {selected_path}")

    artifacts, yaml, runtime_plan, runtime_plan_path = validate_common_candidate(record, manifest, selected, manifest_path, selected_path, candidate_dir)

    runner_path = candidate_dir / "test.qaas.yaml"
    app_path = candidate_dir / "app" / "app.mjs"
    expected_body_path = candidate_dir / "expectations" / "root-body.txt"
    request_payload_path = candidate_dir / "request-payloads" / "get-root.bin"
    for required_artifact in (app_path, expected_body_path, request_payload_path):
        if required_artifact not in artifacts:
            failures.append(f"required Express artifact not listed in manifest artifacts: {required_artifact}")
        require_under(required_artifact, candidate_dir, "required Express candidate artifact")

    expected_body_sha = sha256_hex(expected_body_path) or ""

    qaas_fields = (
        manifest.get("assertion_build_validation"),
        manifest.get("build_validation"),
        manifest.get("template_validation"),
        manifest.get("live_validation"),
        manifest.get("selected_candidate_qaas_validation"),
        runtime_plan.get("qaas_validation"),
    )
    qaas_claimed = any(passed_validation(field) for field in qaas_fields)
    qaas_passed = all(passed_validation(field) for field in qaas_fields)
    if qaas_claimed and not qaas_passed:
        failures.append(f"Express candidate must not claim partial QaaS validation passed: {manifest_path}")
    if qaas_passed:
        validate_express_qaas_evidence(manifest, runtime_plan, manifest_path, runtime_plan_path)

    require_marker(yaml, "Name: GetRootPayload", runner_path)
    require_marker(yaml, "Path: './request-payloads'", runner_path)
    require_marker(yaml, "SearchPattern: 'get-root.bin'", runner_path)
    require_marker(yaml, "Name: ExpressReadRoot", runner_path)
    require_marker(yaml, "Port: 3000", runner_path)
    require_marker(yaml, "Route: /", runner_path)
    require_no_marker(yaml, "OutputContentByExpectedCsvResults", runner_path, "Express plain-text packet must not misuse JSON-oriented CSV body assertion")
    require_no_marker(yaml, "Assertion: ExactHttpTextBody", runner_path, "Express active YAML must not use custom assertion before schema/template/live validation")
    require_no_marker(yaml, "node app.mjs", runner_path, "candidate YAML embeds external process command instead of runtime plan")
    require_no_marker(yaml, "import express", runner_path, "candidate YAML embeds JavaScript source instead of runtime plan")
    require_no_marker(yaml, "res.send", runner_path, "candidate YAML embeds JavaScript source instead of runtime plan")
    if not re.search(r"(?s)Transactions:.*DataSourceNames:\s*\n\s*-\s*GetRootPayload.*DataSourcePatterns:\s*\n\s*-\s*GetRootPayload", yaml):
        failures.append(f"Express transaction must be driven by GetRootPayload DataSourceNames and DataSourcePatterns: {runner_path}")

    app_text = text(app_path)
    for marker in (
        "import express from 'express'",
        "const app = express()",
        "app.get('/', (req, res) => {",
        "res.send('Hello World')",
        "app.listen(3000, () => {",
        "http://localhost:3000",
    ):
        require_marker(app_text, marker, app_path)

    if text(expected_body_path) != "Hello World":
        failures.append(f"Express expected body must match README evidence exactly: {expected_body_path}")
    try:
        if request_payload_path.read_bytes() != b"":
            failures.append(f"Express GET payload driver must be an empty byte file: {request_payload_path}")
    except Exception as exc:
        failures.append(f"failed to validate Express request payload {request_payload_path}: {exc}")

    hook = manifest.get("custom_text_body_assertion")
    if not isinstance(hook, dict):
        failures.append(f"Express candidate must include custom_text_body_assertion hook packet: {manifest_path}")
    else:
        expected_hook_status = "build_template_live_validated" if qaas_passed else "authored_from_public_docs_not_template_validated"
        expected_validation_status = "build_template_live_validated" if qaas_passed else "not_template_validated"
        if hook.get("status") != expected_hook_status:
            failures.append(f"Express custom text-body hook status must be {expected_hook_status!r}: {manifest_path}")
        if hook.get("validation_status") != expected_validation_status:
            failures.append(f"Express custom text-body hook validation_status must be {expected_validation_status!r}: {manifest_path}")
        if hook.get("hook_family") != "assertion" or hook.get("assertion_type") != "ExactHttpTextBody":
            failures.append(f"Express custom hook must be ExactHttpTextBody assertion: {manifest_path}")
        if hook.get("weak_validation_passed") is not False:
            failures.append(f"Express custom hook must not claim weak validation passed: {manifest_path}")
        for field in ("implementation", "usage_snippet", "hook_plan"):
            hook_path = Path(str(hook.get(field, "")))
            require_under(hook_path, candidate_dir, f"Express custom hook {field}")
            require_no_utf8_bom(hook_path, f"Express custom hook {field}")
        implementation_path = Path(str(hook.get("implementation", "")))
        usage_path = Path(str(hook.get("usage_snippet", "")))
        plan_path = Path(str(hook.get("hook_plan", "")))
        implementation_text = text(implementation_path)
        for marker in (
            "namespace ZappaDontCry.SelectedCandidates.Express.Assertions;",
            "BaseAssertion<ExactHttpTextBodyConfig>",
            "GetOutputByName(Configuration.OutputName).Data",
            "item.Body is not byte[] body",
            "Encoding.GetEncoding",
            "StringComparison.Ordinal",
            "AssertionMessage",
            "return false",
        ):
            require_marker(implementation_text, marker, implementation_path)
        for forbidden_marker in ("null!", ".Result", ".Wait()", "GetAwaiter().GetResult()", "Task.Run(", "throw new"):
            require_no_marker(implementation_text, forbidden_marker, implementation_path, "Express custom hook uses forbidden or promotion-unsafe code marker")
        for forbidden_marker in (
            "StringComparison.OrdinalIgnoreCase",
            ".Trim(",
            ".Contains(",
            ".StartsWith(",
            ".EndsWith(",
            ".IndexOf(",
            ".Replace(",
            ".Normalize(",
            ".ToLowerInvariant(",
            ".ToUpperInvariant(",
            "Regex.",
        ):
            require_no_marker(implementation_text, forbidden_marker, implementation_path, "Express custom hook must preserve exact byte-for-byte text semantics")
        usage_text = text(usage_path)
        if usage_path.suffix.lower() in {".yaml", ".yml"}:
            failures.append(f"Express custom assertion usage snippet must not be executable YAML before schema/template validation: {usage_path}")
        for marker in ("Assertion: ExactHttpTextBody", "OutputName: GetRoot", "ExpectedText: Hello World", "EncodingName: utf-8"):
            require_marker(usage_text, marker, usage_path)
        plan = read_json(plan_path)
        if plan.get("status") != "authored_from_public_docs_not_template_validated":
            failures.append(f"Express custom hook plan must stay not template-validated: {plan_path}")
        if plan.get("weak_validation_passed") is not False:
            failures.append(f"Express custom hook plan must not claim weak validation passed: {plan_path}")
        validate_exact_http_text_body_packet(
            plan.get("custom_assertion_packet"),
            plan_path,
            expected_body_sha,
            candidate_dir,
            "Express custom hook plan packet",
            expected_packet_id="express-exact-http-text-body",
        )

    packets = manifest.get("custom_assertion_packets")
    if not isinstance(packets, list) or len(packets) != 1:
        failures.append(f"Express candidate must include exactly one custom assertion packet: {manifest_path}")
    else:
        validate_exact_http_text_body_packet(
            packets[0],
            manifest_path,
            expected_body_sha,
            candidate_dir,
            "Express custom assertion packet",
            qaas_passed,
            expected_packet_id="express-exact-http-text-body",
        )

    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation"))
    if qaas_passed and not lifecycle_passed:
        failures.append(f"Express candidate cannot adopt QaaS live validation before lifecycle_validation is passed: {manifest_path}")
    validate_runtime_plan_common(runtime_plan, runtime_plan_path, "expressjs/express", "node app.mjs", lifecycle_passed, qaas_passed)
    runtime_blockers = runtime_plan.get("blockers", [])
    if lifecycle_passed:
        if not passed_validation(runtime_plan.get("lifecycle_validation")):
            failures.append(f"Express runtime plan missing passed lifecycle_validation: {runtime_plan_path}")

        def validate_express_response(response_path: Path):
            try:
                if response_path.read_text(encoding="utf-8-sig") != "Hello World":
                    failures.append(f"Express lifecycle response must exactly match README-backed text body: {response_path}")
            except Exception as exc:
                failures.append(f"failed to validate Express lifecycle response {response_path}: {exc}")

        validate_lifecycle_evidence_paths(
            manifest.get("lifecycle_validation"),
            runtime_plan.get("lifecycle_validation"),
            manifest_path,
            runtime_plan_path,
            "expressjs/express",
            "selected-top-repo-candidate-lifecycle-express.json",
            validate_express_response,
            ("InstallCommand: npm install express", "Command: node app.mjs", "NpmInstallExitCode: 0", "PackageSpec: express@", "ExpressPackageAvailable: True", "NodeMajorVersionAtLeast18: True", "Ready: True", "ResponseBodySha256:", "CleanupPassed: True", "ExitCode: 0"),
        )
    elif "prove_process_lifecycle_and_cleanup_without assuming private source" not in runtime_blockers:
        failures.append(f"Express runtime plan missing lifecycle blocker before lifecycle validation passes: {runtime_plan_path}")
    if runtime_plan.get("command_support") != "candidate_runtime_command_from_selected_readme_snippet":
        failures.append(f"Express runtime plan command_support must remain candidate_runtime_command_from_selected_readme_snippet: {runtime_plan_path}")
    if runtime_plan.get("install_command") != "npm install express":
        failures.append(f"Express runtime plan install_command mismatch: {runtime_plan_path}")
    if runtime_plan.get("working_directory") != str(candidate_dir / "app"):
        failures.append(f"Express runtime plan working_directory must be generated app directory: {runtime_plan_path}")
    if runtime_plan.get("fixture") != str(app_path):
        failures.append(f"Express runtime plan fixture must be generated app/app.mjs: {runtime_plan_path}")
    if runtime_plan.get("expected_listen_url") != "http://127.0.0.1:3000/":
        failures.append(f"Express runtime plan expected_listen_url mismatch: {runtime_plan_path}")
    readiness = runtime_plan.get("readiness_probe")
    if not isinstance(readiness, dict):
        failures.append(f"Express runtime plan readiness_probe missing: {runtime_plan_path}")
    else:
        if readiness.get("method") != "GET" or readiness.get("url") != "http://127.0.0.1:3000/" or readiness.get("expected_status") != 200:
            failures.append(f"Express runtime plan readiness_probe mismatch: {runtime_plan_path}")
        if readiness.get("expected_body") != "Hello World":
            failures.append(f"Express runtime plan readiness_probe expected_body mismatch: {runtime_plan_path}")
    runtime_hook = runtime_plan.get("custom_text_body_assertion")
    expected_runtime_hook_status = "build_template_live_validated" if qaas_passed else "authored_from_public_docs_not_template_validated"
    expected_runtime_validation_status = "build_template_live_validated" if qaas_passed else "not_template_validated"
    if not isinstance(runtime_hook, dict):
        failures.append(f"Express runtime plan must include custom_text_body_assertion: {runtime_plan_path}")
    else:
        if runtime_hook.get("status") != expected_runtime_hook_status:
            failures.append(f"Express runtime plan custom_text_body_assertion status must be {expected_runtime_hook_status!r}: {runtime_plan_path}")
        if runtime_hook.get("validation_status") != expected_runtime_validation_status:
            failures.append(f"Express runtime plan custom_text_body_assertion validation_status must be {expected_runtime_validation_status!r}: {runtime_plan_path}")
    required_runtime_blockers = [
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence",
    ]
    if qaas_passed:
        for satisfied_blocker in (
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
        ):
            if satisfied_blocker in runtime_plan.get("blockers", []):
                failures.append(f"Express runtime plan still contains satisfied blocker {satisfied_blocker}: {runtime_plan_path}")
    else:
        required_runtime_blockers.extend([
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
        ])
    if not lifecycle_passed:
        required_runtime_blockers.append("prove_process_lifecycle_and_cleanup_without assuming private source")
    for required_blocker in required_runtime_blockers:
        if required_blocker not in runtime_plan.get("blockers", []):
            failures.append(f"Express runtime plan missing blocker {required_blocker}: {runtime_plan_path}")
    runtime_packets = runtime_plan.get("custom_assertion_packets")
    if not isinstance(runtime_packets, list) or len(runtime_packets) != 1:
        failures.append(f"Express runtime plan must include exactly one custom assertion packet: {runtime_plan_path}")
    else:
        validate_exact_http_text_body_packet(
            runtime_packets[0],
            runtime_plan_path,
            expected_body_sha,
            candidate_dir,
            "Express runtime plan custom assertion packet",
            qaas_passed,
            expected_packet_id="express-exact-http-text-body",
        )

    cleanup = runtime_plan.get("cleanup")
    if not isinstance(cleanup, dict):
        failures.append(f"Express runtime plan cleanup missing: {runtime_plan_path}")
    elif cleanup.get("status") == "passed" and not lifecycle_passed:
        failures.append(f"Express runtime plan cleanup passed without manifest lifecycle_validation: {runtime_plan_path}")
    elif cleanup.get("status") != "passed" and lifecycle_passed:
        failures.append(f"Express runtime plan cleanup must be passed when manifest lifecycle_validation passed: {runtime_plan_path}")

    blockers = get_blocker_ids(manifest)
    required_blockers = [
        "live-airgapped-weak-model-not-passed",
    ]
    validate_httpstatus_docs_advisory(manifest, manifest_path, qaas_passed, "Express")
    if qaas_passed:
        for satisfied_blocker in ("express-text-body-hook-not-template-validated", "qaas-template-live-not-run"):
            if satisfied_blocker in blockers:
                failures.append(f"Express candidate manifest still contains satisfied blocker {satisfied_blocker}: {manifest_path}")
    else:
        required_blockers.extend([
            "express-text-body-hook-not-template-validated",
            "qaas-template-live-not-run",
        ])
    if not lifecycle_passed:
        required_blockers.append("express-process-lifecycle-not-proven")
    elif "express-process-lifecycle-not-proven" in blockers:
        failures.append(f"Express candidate manifest still contains satisfied blocker express-process-lifecycle-not-proven: {manifest_path}")
    for blocker_id in required_blockers:
        if blocker_id not in blockers:
            failures.append(f"Express candidate manifest missing source blocker {blocker_id}: {manifest_path}")

    gates = get_gate_map(manifest)
    body_gate = gates.get("plain-text-body-assertion-or-hook")
    expected_body_gate_status = "passed" if qaas_passed else "ready"
    if not body_gate or body_gate.get("status") != expected_body_gate_status or not body_gate.get("evidence"):
        failures.append(f"Express candidate plain-text body assertion hook gate must be {expected_body_gate_status}: {manifest_path}")
    validate_common_gates(manifest, manifest_path, lifecycle_passed, qaas_passed, ("node-express-process-lifecycle",))


def validate_flask(record: dict, manifest: dict, selected: dict, manifest_path: Path, selected_path: Path, candidate_dir: Path):
    supports = selected_supports(selected)
    for required_support in ("runtime-contract", "candidate-executable-command", "input-output-contract"):
        if required_support not in supports:
            failures.append(f"selected contract lacks candidate support {required_support}: {selected_path}")

    artifacts, yaml, runtime_plan, runtime_plan_path = validate_common_candidate(record, manifest, selected, manifest_path, selected_path, candidate_dir)

    runner_path = candidate_dir / "test.qaas.yaml"
    app_path = candidate_dir / "app" / "app.py"
    expected_body_path = candidate_dir / "expectations" / "root-body.txt"
    request_payload_path = candidate_dir / "request-payloads" / "get-root.bin"
    for required_artifact in (app_path, expected_body_path, request_payload_path):
        if required_artifact not in artifacts:
            failures.append(f"required artifact not listed in manifest artifacts: {required_artifact}")
        require_under(required_artifact, candidate_dir, "required candidate artifact")

    expected_body_sha = ""
    try:
        import hashlib

        expected_body_sha = hashlib.sha256(expected_body_path.read_bytes()).hexdigest()
    except Exception as exc:
        failures.append(f"failed to hash Flask expected body {expected_body_path}: {exc}")

    qaas_fields = (
        manifest.get("assertion_build_validation"),
        manifest.get("build_validation"),
        manifest.get("template_validation"),
        manifest.get("live_validation"),
        manifest.get("selected_candidate_qaas_validation"),
        runtime_plan.get("qaas_validation"),
    )
    qaas_claimed = any(passed_validation(field) for field in qaas_fields)
    qaas_passed = all(passed_validation(field) for field in qaas_fields)
    if qaas_claimed and not qaas_passed:
        failures.append(f"Flask candidate must not claim partial QaaS validation passed: {manifest_path}")
    if qaas_passed:
        validate_flask_qaas_evidence(manifest, runtime_plan, manifest_path, runtime_plan_path)

    require_marker(yaml, "Name: GetRootPayload", runner_path)
    require_marker(yaml, "Path: './request-payloads'", runner_path)
    require_marker(yaml, "SearchPattern: 'get-root.bin'", runner_path)
    require_marker(yaml, "Port: 5000", runner_path)
    require_marker(yaml, "Route: /", runner_path)
    require_no_marker(yaml, "OutputContentByExpectedCsvResults", runner_path, "Flask plain-text packet must not misuse JSON-oriented CSV body assertion")
    require_no_marker(yaml, "Assertion: ExactHttpTextBody", runner_path, "Flask active YAML must not use custom assertion before schema/template/live validation")
    require_no_marker(yaml, "flask run", runner_path, "candidate YAML embeds external process command instead of runtime plan")
    if not re.search(r"(?s)Transactions:.*DataSourceNames:\s*\n\s*-\s*GetRootPayload.*DataSourcePatterns:\s*\n\s*-\s*GetRootPayload", yaml):
        failures.append(f"candidate transaction must be driven by GetRootPayload DataSourceNames and DataSourcePatterns: {runner_path}")

    app_text = text(app_path)
    for marker in ('from flask import Flask', 'app = Flask(__name__)', '@app.route("/")', 'return "Hello, World!"'):
        require_marker(app_text, marker, app_path)

    hook = manifest.get("custom_text_body_assertion")
    if not isinstance(hook, dict):
        failures.append(f"Flask candidate must include custom_text_body_assertion hook packet: {manifest_path}")
    else:
        expected_hook_status = "build_template_live_validated" if qaas_passed else "authored_from_public_docs_not_template_validated"
        expected_validation_status = "build_template_live_validated" if qaas_passed else "not_template_validated"
        if hook.get("status") != expected_hook_status:
            failures.append(f"Flask custom text-body hook status must be {expected_hook_status!r}: {manifest_path}")
        if hook.get("validation_status") != expected_validation_status:
            failures.append(f"Flask custom text-body hook validation_status must be {expected_validation_status!r}: {manifest_path}")
        if hook.get("hook_family") != "assertion" or hook.get("assertion_type") != "ExactHttpTextBody":
            failures.append(f"Flask custom hook must be ExactHttpTextBody assertion: {manifest_path}")
        if hook.get("weak_validation_passed") is not False:
            failures.append(f"Flask custom hook must not claim weak validation passed: {manifest_path}")
        for field in ("implementation", "usage_snippet", "hook_plan"):
            hook_path = Path(str(hook.get(field, "")))
            require_under(hook_path, candidate_dir, f"Flask custom hook {field}")
            require_no_utf8_bom(hook_path, f"Flask custom hook {field}")
        implementation_path = Path(str(hook.get("implementation", "")))
        usage_path = Path(str(hook.get("usage_snippet", "")))
        plan_path = Path(str(hook.get("hook_plan", "")))
        implementation_text = text(implementation_path)
        for marker in (
            "BaseAssertion<ExactHttpTextBodyConfig>",
            "IImmutableList<SessionData>",
            "IImmutableList<DataSource>",
            "GetOutputByName(Configuration.OutputName).Data",
            "item.Body is not byte[] body",
            "Encoding.GetEncoding",
            "StringComparison.Ordinal",
            "AssertionMessage",
            "return false",
        ):
            require_marker(implementation_text, marker, implementation_path)
        for forbidden_marker in ("null!", ".Result", ".Wait()", "GetAwaiter().GetResult()", "Task.Run(", "throw new"):
            require_no_marker(implementation_text, forbidden_marker, implementation_path, "Flask custom hook uses forbidden or promotion-unsafe code marker")
        for forbidden_marker in (
            "StringComparison.OrdinalIgnoreCase",
            ".Trim(",
            ".Contains(",
            ".StartsWith(",
            ".EndsWith(",
            ".IndexOf(",
            ".Replace(",
            ".Normalize(",
            ".ToLowerInvariant(",
            ".ToUpperInvariant(",
            "Regex.",
        ):
            require_no_marker(implementation_text, forbidden_marker, implementation_path, "Flask custom hook must preserve exact byte-for-byte text semantics")
        usage_text = text(usage_path)
        if usage_path.suffix.lower() in {".yaml", ".yml"}:
            failures.append(f"Flask custom assertion usage snippet must not be executable YAML before schema/template validation: {usage_path}")
        for marker in ("Assertion: ExactHttpTextBody", "OutputName: GetRoot", "ExpectedText: Hello, World!", "EncodingName: utf-8"):
            require_marker(usage_text, marker, usage_path)
        plan = read_json(plan_path)
        if plan.get("status") != "authored_from_public_docs_not_template_validated":
            failures.append(f"Flask custom hook plan must stay not template-validated: {plan_path}")
        if plan.get("weak_validation_passed") is not False:
            failures.append(f"Flask custom hook plan must not claim weak validation passed: {plan_path}")
        builtins = {
            item.get("name")
            for item in plan.get("builtins_considered", [])
            if isinstance(item, dict)
        }
        for required_builtin in ("HttpStatus", "OutputContentByExpectedCsvResults"):
            if required_builtin not in builtins:
                failures.append(f"Flask custom hook plan missing builtin consideration {required_builtin}: {plan_path}")
        validate_exact_http_text_body_packet(
            plan.get("custom_assertion_packet"),
            plan_path,
            expected_body_sha,
            candidate_dir,
            "Flask custom hook plan packet",
        )

    packets = manifest.get("custom_assertion_packets")
    if not isinstance(packets, list) or len(packets) != 1:
        failures.append(f"Flask candidate must include exactly one custom assertion packet: {manifest_path}")
    else:
        validate_exact_http_text_body_packet(
            packets[0],
            manifest_path,
            expected_body_sha,
            candidate_dir,
            "Flask custom assertion packet",
            qaas_passed,
        )

    if text(expected_body_path) != "Hello, World!":
        failures.append(f"Flask expected body must match README evidence exactly: {expected_body_path}")
    try:
        if request_payload_path.read_bytes() != b"":
            failures.append(f"Flask GET payload driver must be an empty byte file: {request_payload_path}")
    except Exception as exc:
        failures.append(f"failed to validate Flask request payload {request_payload_path}: {exc}")

    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation"))
    if qaas_passed and not lifecycle_passed:
        failures.append(f"Flask candidate cannot adopt QaaS live validation before lifecycle_validation is passed: {manifest_path}")
    validate_runtime_plan_common(runtime_plan, runtime_plan_path, "pallets/flask", "flask run", lifecycle_passed, qaas_passed)
    runtime_hook = runtime_plan.get("custom_text_body_assertion")
    expected_runtime_hook_status = "build_template_live_validated" if qaas_passed else "authored_from_public_docs_not_template_validated"
    expected_runtime_validation_status = "build_template_live_validated" if qaas_passed else "not_template_validated"
    if not isinstance(runtime_hook, dict):
        failures.append(f"Flask runtime plan must include custom_text_body_assertion: {runtime_plan_path}")
    else:
        if runtime_hook.get("status") != expected_runtime_hook_status:
            failures.append(f"Flask runtime plan custom_text_body_assertion status must be {expected_runtime_hook_status!r}: {runtime_plan_path}")
        if runtime_hook.get("validation_status") != expected_runtime_validation_status:
            failures.append(f"Flask runtime plan custom_text_body_assertion validation_status must be {expected_runtime_validation_status!r}: {runtime_plan_path}")
    required_runtime_blockers = [
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence",
    ]
    if qaas_passed:
        for satisfied_blocker in (
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
        ):
            if satisfied_blocker in runtime_plan.get("blockers", []):
                failures.append(f"Flask runtime plan still contains satisfied blocker {satisfied_blocker}: {runtime_plan_path}")
    else:
        required_runtime_blockers.extend([
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
        ])
    if not lifecycle_passed:
        required_runtime_blockers.append("prove_process_lifecycle_and_cleanup_without assuming private source")
    for required_blocker in required_runtime_blockers:
        if required_blocker not in runtime_plan.get("blockers", []):
            failures.append(f"Flask runtime plan missing blocker {required_blocker}: {runtime_plan_path}")

    runtime_packets = runtime_plan.get("custom_assertion_packets")
    if not isinstance(runtime_packets, list) or len(runtime_packets) != 1:
        failures.append(f"Flask runtime plan must include exactly one custom assertion packet: {runtime_plan_path}")
    else:
        validate_exact_http_text_body_packet(
            runtime_packets[0],
            runtime_plan_path,
            expected_body_sha,
            candidate_dir,
            "Flask runtime plan custom assertion packet",
            qaas_passed,
        )

    cleanup = runtime_plan.get("cleanup")
    if not isinstance(cleanup, dict):
        failures.append(f"Flask runtime plan cleanup missing: {runtime_plan_path}")
    elif cleanup.get("status") == "passed" and not lifecycle_passed:
        failures.append(f"Flask runtime plan cleanup passed without manifest lifecycle_validation: {runtime_plan_path}")
    elif cleanup.get("status") != "passed" and lifecycle_passed:
        failures.append(f"Flask runtime plan cleanup must be passed when manifest lifecycle_validation passed: {runtime_plan_path}")

    blockers = get_blocker_ids(manifest)
    required_source_blockers = [
        "live-airgapped-weak-model-not-passed",
    ]
    validate_httpstatus_docs_advisory(manifest, manifest_path, qaas_passed, "Flask")
    if qaas_passed:
        for satisfied_blocker in ("flask-text-body-hook-not-template-validated", "qaas-template-live-not-run"):
            if satisfied_blocker in blockers:
                failures.append(f"Flask candidate manifest still contains satisfied blocker {satisfied_blocker}: {manifest_path}")
    else:
        required_source_blockers.extend([
            "flask-text-body-hook-not-template-validated",
            "qaas-template-live-not-run",
        ])
    if not lifecycle_passed:
        required_source_blockers.append("flask-process-lifecycle-not-proven")
    elif "flask-process-lifecycle-not-proven" in blockers:
        failures.append(f"Flask candidate manifest still contains satisfied blocker flask-process-lifecycle-not-proven: {manifest_path}")
    for blocker_id in required_source_blockers:
        if blocker_id not in blockers:
            failures.append(f"Flask candidate manifest missing source blocker {blocker_id}: {manifest_path}")
    if "flask-text-body-assertion-not-mapped" in blockers:
        failures.append(f"Flask candidate still contains satisfied blocker flask-text-body-assertion-not-mapped: {manifest_path}")

    gates = get_gate_map(manifest)
    body_gate = gates.get("plain-text-body-assertion-or-hook")
    expected_body_gate_status = "passed" if qaas_passed else "ready"
    if not body_gate or body_gate.get("status") != expected_body_gate_status or not body_gate.get("evidence"):
        failures.append(f"Flask candidate plain-text body assertion hook gate must be {expected_body_gate_status}: {manifest_path}")
    validate_common_gates(manifest, manifest_path, lifecycle_passed, qaas_passed, ("python-flask-process-lifecycle",))


def validate_deno(record: dict, manifest: dict, selected: dict, manifest_path: Path, selected_path: Path, candidate_dir: Path):
    supports = selected_supports(selected)
    for required_support in ("runtime-contract", "candidate-executable-command", "input-output-contract"):
        if required_support not in supports:
            failures.append(f"selected contract lacks candidate support {required_support}: {selected_path}")

    artifacts, yaml, runtime_plan, runtime_plan_path = validate_common_candidate(record, manifest, selected, manifest_path, selected_path, candidate_dir)

    runner_path = candidate_dir / "test.qaas.yaml"
    server_path = candidate_dir / "app" / "server.ts"
    expected_body_path = candidate_dir / "expectations" / "root-body.txt"
    request_payload_path = candidate_dir / "request-payloads" / "get-root.bin"
    for required_artifact in (server_path, expected_body_path, request_payload_path):
        if required_artifact not in artifacts:
            failures.append(f"required Deno artifact not listed in manifest artifacts: {required_artifact}")
        require_under(required_artifact, candidate_dir, "required Deno candidate artifact")

    expected_body_sha = sha256_hex(expected_body_path) or ""

    qaas_fields = (
        manifest.get("assertion_build_validation"),
        manifest.get("build_validation"),
        manifest.get("template_validation"),
        manifest.get("live_validation"),
        manifest.get("selected_candidate_qaas_validation"),
        runtime_plan.get("qaas_validation"),
    )
    qaas_claimed = any(passed_validation(field) for field in qaas_fields)
    qaas_passed = all(passed_validation(field) for field in qaas_fields)
    if qaas_claimed and not qaas_passed:
        failures.append(f"Deno candidate must not claim partial QaaS validation passed: {manifest_path}")
    if qaas_passed:
        validate_deno_qaas_evidence(manifest, runtime_plan, manifest_path, runtime_plan_path)

    require_marker(yaml, "Name: GetRootPayload", runner_path)
    require_marker(yaml, "Path: './request-payloads'", runner_path)
    require_marker(yaml, "SearchPattern: 'get-root.bin'", runner_path)
    require_marker(yaml, "Name: DenoReadRoot", runner_path)
    require_marker(yaml, "Port: 8000", runner_path)
    require_marker(yaml, "Route: /", runner_path)
    require_no_marker(yaml, "Assertion: ExactHttpTextBody", runner_path, "Deno active YAML must not use custom assertion before schema/template/live validation")
    require_no_marker(yaml, "deno run", runner_path, "candidate YAML embeds external process command instead of runtime plan")
    require_no_marker(yaml, "Deno.serve", runner_path, "candidate YAML embeds TypeScript source instead of runtime plan")
    require_no_marker(yaml, "Hello, world!", runner_path, "candidate YAML embeds exact text body before custom assertion validation")
    if not re.search(r"(?s)Transactions:.*DataSourceNames:\s*\n\s*-\s*GetRootPayload.*DataSourcePatterns:\s*\n\s*-\s*GetRootPayload", yaml):
        failures.append(f"Deno transaction must be driven by GetRootPayload DataSourceNames and DataSourcePatterns: {runner_path}")

    server_text = text(server_path)
    for marker in (
        "Deno.serve((_req: Request) => {",
        'return new Response("Hello, world!");',
    ):
        require_marker(server_text, marker, server_path)
    for forbidden_marker in ("npm", "node", "express", "flask", "fastapi"):
        require_no_marker(server_text, forbidden_marker, server_path, "Deno server fixture must not spoof another runtime")

    if text(expected_body_path) != "Hello, world!":
        failures.append(f"Deno expected body must match README evidence exactly: {expected_body_path}")
    try:
        if request_payload_path.read_bytes() != b"":
            failures.append(f"Deno GET payload driver must be an empty byte file: {request_payload_path}")
    except Exception as exc:
        failures.append(f"failed to validate Deno request payload {request_payload_path}: {exc}")

    hook = manifest.get("custom_text_body_assertion")
    if not isinstance(hook, dict):
        failures.append(f"Deno candidate must include custom_text_body_assertion hook packet: {manifest_path}")
    else:
        expected_hook_status = "build_template_live_validated" if qaas_passed else "authored_from_public_docs_not_template_validated"
        expected_validation_status = "build_template_live_validated" if qaas_passed else "not_template_validated"
        if hook.get("status") != expected_hook_status:
            failures.append(f"Deno custom text-body hook status must be {expected_hook_status!r}: {manifest_path}")
        if hook.get("validation_status") != expected_validation_status:
            failures.append(f"Deno custom text-body hook validation_status must be {expected_validation_status!r}: {manifest_path}")
        if hook.get("hook_family") != "assertion" or hook.get("assertion_type") != "ExactHttpTextBody":
            failures.append(f"Deno custom hook must be ExactHttpTextBody assertion: {manifest_path}")
        if hook.get("weak_validation_passed") is not False:
            failures.append(f"Deno custom hook must not claim weak validation passed: {manifest_path}")
        for field in ("implementation", "usage_snippet", "hook_plan"):
            hook_path = Path(str(hook.get(field, "")))
            require_under(hook_path, candidate_dir, f"Deno custom hook {field}")
            require_no_utf8_bom(hook_path, f"Deno custom hook {field}")
        implementation_path = Path(str(hook.get("implementation", "")))
        usage_path = Path(str(hook.get("usage_snippet", "")))
        plan_path = Path(str(hook.get("hook_plan", "")))
        implementation_text = text(implementation_path)
        for marker in (
            "namespace ZappaDontCry.SelectedCandidates.Deno.Assertions;",
            "BaseAssertion<ExactHttpTextBodyConfig>",
            "GetOutputByName(Configuration.OutputName).Data",
            "item.Body is not byte[] body",
            "Encoding.GetEncoding",
            "StringComparison.Ordinal",
        ):
            require_marker(implementation_text, marker, implementation_path)
        for forbidden_marker in ("null!", ".Result", ".Wait()", "GetAwaiter().GetResult()", "Task.Run(", "throw new"):
            require_no_marker(implementation_text, forbidden_marker, implementation_path, "Deno custom hook uses forbidden or promotion-unsafe code marker")
        usage_text = text(usage_path)
        if usage_path.suffix.lower() in {".yaml", ".yml"}:
            failures.append(f"Deno custom assertion usage snippet must not be executable YAML before schema/template validation: {usage_path}")
        for marker in ("Assertion: ExactHttpTextBody", "OutputName: GetRoot", "ExpectedText: Hello, world!", "EncodingName: utf-8"):
            require_marker(usage_text, marker, usage_path)
        plan = read_json(plan_path)
        if plan.get("status") != "authored_from_public_docs_not_template_validated":
            failures.append(f"Deno custom hook plan must stay not template-validated: {plan_path}")
        if plan.get("weak_validation_passed") is not False:
            failures.append(f"Deno custom hook plan must not claim weak validation passed: {plan_path}")
        validate_exact_http_text_body_packet(
            plan.get("custom_assertion_packet"),
            plan_path,
            expected_body_sha,
            candidate_dir,
            "Deno custom hook plan packet",
            expected_packet_id="deno-exact-http-text-body",
        )

    packets = manifest.get("custom_assertion_packets")
    if not isinstance(packets, list) or len(packets) != 1:
        failures.append(f"Deno candidate must include exactly one custom assertion packet: {manifest_path}")
    else:
        validate_exact_http_text_body_packet(
            packets[0],
            manifest_path,
            expected_body_sha,
            candidate_dir,
            "Deno custom assertion packet",
            qaas_passed,
            expected_packet_id="deno-exact-http-text-body",
        )

    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation"))
    if qaas_passed and not lifecycle_passed:
        failures.append(f"Deno candidate cannot adopt QaaS live validation before lifecycle_validation is passed: {manifest_path}")
    validate_runtime_plan_common(runtime_plan, runtime_plan_path, "denoland/deno", "deno run --allow-net server.ts", lifecycle_passed, qaas_passed)
    if runtime_plan.get("command_support") != "candidate-executable-command":
        failures.append(f"Deno runtime plan command_support mismatch: {runtime_plan_path}")
    if runtime_plan.get("public_command") != "deno run --allow-net server.ts":
        failures.append(f"Deno runtime plan public_command mismatch: {runtime_plan_path}")
    if runtime_plan.get("working_directory") != str(candidate_dir / "app"):
        failures.append(f"Deno runtime plan working_directory must be generated app directory: {runtime_plan_path}")
    if runtime_plan.get("fixture") != str(server_path):
        failures.append(f"Deno runtime plan fixture must be generated app/server.ts: {runtime_plan_path}")
    if runtime_plan.get("expected_listen_url") != "http://127.0.0.1:8000/":
        failures.append(f"Deno runtime plan expected_listen_url mismatch: {runtime_plan_path}")
    readiness = runtime_plan.get("readiness_probe")
    if not isinstance(readiness, dict):
        failures.append(f"Deno runtime plan readiness_probe missing: {runtime_plan_path}")
    else:
        if readiness.get("method") != "GET" or readiness.get("url") != "http://127.0.0.1:8000/" or readiness.get("expected_status") != 200:
            failures.append(f"Deno runtime plan readiness_probe mismatch: {runtime_plan_path}")
        if readiness.get("expected_body") != "Hello, world!":
            failures.append(f"Deno runtime plan readiness_probe expected_body mismatch: {runtime_plan_path}")

    managed = runtime_plan.get("managed_toolchain")
    if not isinstance(managed, dict):
        failures.append(f"Deno runtime plan managed_toolchain missing: {runtime_plan_path}")
    else:
        expected_toolchain = {
            "required": True,
            "source": "official_deno_github_release_asset",
            "release_tag": "v2.8.2",
            "download_url": "https://github.com/denoland/deno/releases/download/v2.8.2/deno-x86_64-pc-windows-msvc.zip",
            "archive_sha256": "6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9",
            "binary": "deno.exe",
        }
        for field, expected in expected_toolchain.items():
            if managed.get(field) != expected:
                failures.append(f"Deno managed_toolchain {field} mismatch: {runtime_plan_path}")
        expected_status = "passed" if lifecycle_passed else "not_validated"
        if managed.get("status") != expected_status:
            failures.append(f"Deno managed_toolchain status must be {expected_status}: {runtime_plan_path}")

    if lifecycle_passed:
        if not passed_validation(runtime_plan.get("lifecycle_validation")):
            failures.append(f"Deno runtime plan missing passed lifecycle_validation: {runtime_plan_path}")

        def validate_deno_response(response_path: Path):
            try:
                if response_path.read_text(encoding="utf-8-sig") != "Hello, world!":
                    failures.append(f"Deno lifecycle response must exactly match README-backed text body: {response_path}")
            except Exception as exc:
                failures.append(f"failed to validate Deno lifecycle response {response_path}: {exc}")

        validate_lifecycle_evidence_paths(
            manifest.get("lifecycle_validation"),
            runtime_plan.get("lifecycle_validation"),
            manifest_path,
            runtime_plan_path,
            "denoland/deno",
            "selected-top-repo-candidate-lifecycle-deno.json",
            validate_deno_response,
            ("DownloadUrl: https://github.com/denoland/deno/releases/download/v2.8.2/deno-x86_64-pc-windows-msvc.zip", "DenoArchiveSha256: 6fe073b11cabeba2f2726d8a3d1592b198aec5f23dab3473d0dc8d5ec7aee1c9", "DenoVersion:", "Command: deno run --allow-net server.ts", "DenoDir:", "Ready: True", "ResponseBodySha256:", "CleanupPassed: True", "ExitCode: 0"),
        )
    else:
        for required_blocker in (
            "prove_managed_deno_toolchain_without_using_ambient_path",
            "prove_process_lifecycle_and_cleanup_without assuming private source",
        ):
            if required_blocker not in runtime_plan.get("blockers", []):
                failures.append(f"Deno runtime plan missing lifecycle blocker {required_blocker}: {runtime_plan_path}")

    runtime_packets = runtime_plan.get("custom_assertion_packets")
    if not isinstance(runtime_packets, list) or len(runtime_packets) != 1:
        failures.append(f"Deno runtime plan must include exactly one custom assertion packet: {runtime_plan_path}")
    else:
        validate_exact_http_text_body_packet(
            runtime_packets[0],
            runtime_plan_path,
            expected_body_sha,
            candidate_dir,
            "Deno runtime plan custom assertion packet",
            qaas_passed,
            expected_packet_id="deno-exact-http-text-body",
        )
    runtime_hook = runtime_plan.get("custom_text_body_assertion")
    if not isinstance(runtime_hook, dict):
        failures.append(f"Deno runtime plan must include custom_text_body_assertion: {runtime_plan_path}")
    else:
        expected_runtime_hook_status = "build_template_live_validated" if qaas_passed else "authored_from_public_docs_not_template_validated"
        expected_runtime_validation_status = "build_template_live_validated" if qaas_passed else "not_template_validated"
        if runtime_hook.get("status") != expected_runtime_hook_status:
            failures.append(f"Deno runtime plan custom_text_body_assertion status must be {expected_runtime_hook_status!r}: {runtime_plan_path}")
        if runtime_hook.get("validation_status") != expected_runtime_validation_status:
            failures.append(f"Deno runtime plan custom_text_body_assertion validation_status must be {expected_runtime_validation_status!r}: {runtime_plan_path}")
    required_runtime_blockers = [
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence",
    ]
    if qaas_passed:
        for satisfied_blocker in ("validate_exact_text_body_custom_assertion_schema_template_and_live", "run_qaaS_template_validation", "run_live_qaaS_act_assert_validation"):
            if satisfied_blocker in runtime_plan.get("blockers", []):
                failures.append(f"Deno runtime plan still contains satisfied blocker {satisfied_blocker}: {runtime_plan_path}")
    else:
        required_runtime_blockers.extend([
            "validate_exact_text_body_custom_assertion_schema_template_and_live",
            "run_qaaS_template_validation",
            "run_live_qaaS_act_assert_validation",
        ])
    for required_blocker in required_runtime_blockers:
        if required_blocker not in runtime_plan.get("blockers", []):
            failures.append(f"Deno runtime plan missing blocker {required_blocker}: {runtime_plan_path}")

    cleanup = runtime_plan.get("cleanup")
    if not isinstance(cleanup, dict):
        failures.append(f"Deno runtime plan cleanup missing: {runtime_plan_path}")
    elif cleanup.get("status") == "passed" and not lifecycle_passed:
        failures.append(f"Deno runtime plan cleanup passed without manifest lifecycle_validation: {runtime_plan_path}")
    elif cleanup.get("status") != "passed" and lifecycle_passed:
        failures.append(f"Deno runtime plan cleanup must be passed when manifest lifecycle_validation passed: {runtime_plan_path}")

    blockers = get_blocker_ids(manifest)
    required_blockers = [
        "deno-broad-runtime-coverage-not-selected",
        "live-airgapped-weak-model-not-passed",
    ]
    validate_httpstatus_docs_advisory(manifest, manifest_path, qaas_passed, "Deno")
    if qaas_passed:
        for satisfied_blocker in ("deno-text-body-hook-not-template-validated", "qaas-template-live-not-run"):
            if satisfied_blocker in blockers:
                failures.append(f"Deno candidate manifest still contains satisfied blocker {satisfied_blocker}: {manifest_path}")
    else:
        required_blockers.extend([
            "deno-text-body-hook-not-template-validated",
            "qaas-template-live-not-run",
        ])
    if lifecycle_passed:
        for satisfied_blocker in ("deno-toolchain-not-proven", "deno-process-lifecycle-not-proven"):
            if satisfied_blocker in blockers:
                failures.append(f"Deno candidate manifest still contains satisfied blocker {satisfied_blocker}: {manifest_path}")
    else:
        required_blockers.extend(["deno-toolchain-not-proven", "deno-process-lifecycle-not-proven"])
    for blocker_id in required_blockers:
        if blocker_id not in blockers:
            failures.append(f"Deno candidate manifest missing source blocker {blocker_id}: {manifest_path}")

    gates = get_gate_map(manifest)
    body_gate = gates.get("plain-text-body-assertion-or-hook")
    expected_body_gate_status = "passed" if qaas_passed else "ready"
    if not body_gate or body_gate.get("status") != expected_body_gate_status or not body_gate.get("evidence"):
        failures.append(f"Deno candidate plain-text body assertion hook gate must be {expected_body_gate_status}: {manifest_path}")
    validate_common_gates(manifest, manifest_path, lifecycle_passed, qaas_passed, ("managed-deno-toolchain", "deno-process-lifecycle"))


def validate_crawl4ai(record: dict, manifest: dict, selected: dict, manifest_path: Path, selected_path: Path, candidate_dir: Path):
    supports = selected_supports(selected)
    if "candidate-executable-command" not in supports:
        failures.append(f"selected contract lacks Docker executable-command evidence: {selected_path}")
    if "input-output-contract" in supports:
        failures.append(f"Crawl4AI checker must be revisited before accepting a broad input-output contract claim: {selected_path}")

    artifacts, yaml, runtime_plan, runtime_plan_path = validate_common_candidate(
        record,
        manifest,
        selected,
        manifest_path,
        selected_path,
        candidate_dir,
        expected_assertion_marker="Assertion: HttpStatusBelow400",
        expected_status_marker="MaximumExclusiveStatusCode: 400",
    )

    runner_path = candidate_dir / "test.qaas.yaml"
    request_payload_path = candidate_dir / "request-payloads" / "get-health.bin"
    assertion_source_path = candidate_dir / "assertion-packets" / "HttpStatusBelow400" / "HttpStatusBelow400.cs"
    assertion_usage_path = candidate_dir / "assertion-packets" / "HttpStatusBelow400" / "HttpStatusBelow400.usage.yaml.txt"
    assertion_plan_path = candidate_dir / "assertion-packets" / "HttpStatusBelow400" / "custom-status-hook-plan.json"
    if request_payload_path not in artifacts:
        failures.append(f"required Crawl4AI artifact not listed in manifest artifacts: {request_payload_path}")
    for required_path in (request_payload_path, assertion_source_path, assertion_usage_path, assertion_plan_path):
        require_under(required_path, candidate_dir, "required Crawl4AI path")
        if not required_path.exists():
            failures.append(f"required Crawl4AI path missing: {required_path}")

    for marker in (
        "Name: GetHealthPayload",
        "SearchPattern: 'get-health.bin'",
        "Name: Crawl4AiHealth",
        "Name: GetHealth",
        "Port: 11235",
        "Route: health",
        "Assertion: HttpStatusBelow400",
        "OutputNames:",
        "- GetHealth",
    ):
        require_marker(yaml, marker, runner_path)
    for forbidden_marker in (
        "StatusCode: 200",
        "Route: /health",
        "Route: /crawl",
        "ObjectOutputJsonSchema",
        "OutputContentByExpectedCsvResults",
        "ExpectedBody",
        "JsonPathEquals",
        "OutputDeserialize:",
        "Deserializer: Json",
        "http://localhost:11235/crawl",
    ):
        require_no_marker(yaml, forbidden_marker, runner_path, "Crawl4AI health candidate must stay status-only and must not promote /crawl or body/schema assertions")
    if re.search(r"(?m)^\s*Assertion:\s+HttpStatus\s*$", yaml):
        failures.append(f"Crawl4AI health candidate must use HttpStatusBelow400, not built-in HttpStatus equality: {runner_path}")

    try:
        if request_payload_path.read_bytes() != b"":
            failures.append(f"Crawl4AI GET /health payload driver must be an empty byte file: {request_payload_path}")
    except Exception as exc:
        failures.append(f"failed to validate Crawl4AI request payload {request_payload_path}: {exc}")

    assertion_text = text(assertion_source_path)
    for marker in (
        "public sealed class HttpStatusBelow400",
        "public string[] OutputNames",
        "public int MaximumExclusiveStatusCode",
        ".MetaData?.Http?.StatusCode",
        "statusCode >= Configuration.MaximumExclusiveStatusCode",
        "required status <",
    ):
        require_marker(assertion_text, marker, assertion_source_path)
    for forbidden_marker in (".Body", "ExpectedText", "ObjectOutputJsonSchema", "JsonDocument", "Deserialize"):
        require_no_marker(assertion_text, forbidden_marker, assertion_source_path, "Crawl4AI custom assertion must inspect HTTP status metadata only")

    usage_text = text(assertion_usage_path)
    for marker in ("Assertion: HttpStatusBelow400", "MaximumExclusiveStatusCode: 400", "- GetHealth"):
        require_marker(usage_text, marker, assertion_usage_path)

    hook_plan = read_json(assertion_plan_path)
    if hook_plan.get("assertion_type") != "HttpStatusBelow400" or hook_plan.get("promotion_state") != "blocked":
        failures.append(f"Crawl4AI hook plan must stay blocked for HttpStatusBelow400: {assertion_plan_path}")
    packet = None
    for candidate_packet in manifest.get("custom_assertion_packets", []):
        if isinstance(candidate_packet, dict) and candidate_packet.get("assertion_name") == "HttpStatusBelow400":
            packet = candidate_packet
            break

    qaas_fields = (
        manifest.get("assertion_build_validation"),
        manifest.get("build_validation"),
        manifest.get("template_validation"),
        manifest.get("live_validation"),
        manifest.get("selected_candidate_qaas_validation"),
        runtime_plan.get("qaas_validation"),
    )
    qaas_claimed = any(passed_validation(field) for field in qaas_fields)
    qaas_passed = all(passed_validation(field) for field in qaas_fields)
    if qaas_claimed and not qaas_passed:
        failures.append(f"Crawl4AI candidate must not claim partial QaaS validation passed: {manifest_path}")
    if qaas_passed:
        failures.append(f"Crawl4AI live QaaS evidence checker is not implemented yet; do not mark QaaS validation passed: {manifest_path}")
    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation"))
    validate_http_status_below_400_packet(packet, manifest_path, candidate_dir, "Crawl4AI custom assertion packet", qaas_passed=False)

    selected_files = {
        "README.md": (
            "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest",
            "http://localhost:11235/crawl",
            'if "results" in response.json():',
            'task_id = response.json()["task_id"]',
        ),
        "Dockerfile": (
            "curl -f http://localhost:11235/health || exit 1",
            "redis-cli ping",
            "MEM=$(free -m",
        ),
        "docker-compose.yml": (
            'test: ["CMD", "curl", "-f", "http://localhost:11235/health"]',
            "memory: 4G",
            "memory: 1G",
            "/dev/shm:/dev/shm",
        ),
        "deploy/docker/schemas.py": (
            "class CrawlRequest(BaseModel):",
            "urls: List[str] = Field(min_length=1, max_length=100)",
        ),
    }
    selected_texts: dict[str, str] = {}
    for source_path, markers in selected_files.items():
        evidence_path = selected_file_path(selected, source_path)
        if evidence_path is None:
            failures.append(f"Crawl4AI selected evidence missing selected file {source_path}: {selected_path}")
            continue
        require_under(evidence_path, selected_contracts_root, "Crawl4AI selected evidence")
        selected_texts[source_path] = text(evidence_path)
        for marker in markers:
            require_marker(selected_texts[source_path], marker, evidence_path)
    if "deploy/docker/schemas.py" in selected_texts:
        require_no_marker(selected_texts["deploy/docker/schemas.py"], "class CrawlResponse", selected_file_path(selected, "deploy/docker/schemas.py") or selected_path, "Crawl4AI selected schema must not be treated as response-body evidence")

    if runtime_plan.get("command_support") != "candidate-executable-command":
        failures.append(f"Crawl4AI runtime plan must use candidate-executable-command support: {runtime_plan_path}")
    if runtime_plan.get("public_command") != "docker run -d -p 11235:11235 --name crawl4ai --shm-size=1g unclecode/crawl4ai:latest":
        failures.append(f"Crawl4AI runtime plan public_command mismatch: {runtime_plan_path}")
    if runtime_plan.get("pull_command") != "docker pull unclecode/crawl4ai:latest":
        failures.append(f"Crawl4AI runtime plan pull_command mismatch: {runtime_plan_path}")
    if runtime_plan.get("image") != "unclecode/crawl4ai:latest":
        failures.append(f"Crawl4AI runtime plan image mismatch: {runtime_plan_path}")
    safe_template = str(runtime_plan.get("safe_test_command_template", ""))
    for marker in ("--name zappa-crawl4ai-health-{run_id}", "--shm-size=1g", "unclecode/crawl4ai:latest", "127.0.0.1:11235:11235"):
        if marker not in safe_template:
            failures.append(f"Crawl4AI runtime plan safe_test_command_template missing {marker}: {runtime_plan_path}")
    if "--name crawl4ai" in safe_template:
        failures.append(f"Crawl4AI safe test command must not reuse the public container name crawl4ai: {runtime_plan_path}")

    readiness = runtime_plan.get("readiness_probe")
    if not isinstance(readiness, dict):
        failures.append(f"Crawl4AI runtime plan readiness_probe missing: {runtime_plan_path}")
    else:
        expected_readiness = {
            "method": "GET",
            "url": "http://127.0.0.1:11235/health",
            "expected_status_semantics": "http_status_less_than_400",
            "maximum_exclusive_status_code": 400,
            "expected_body": "unasserted_no_public_body_contract",
        }
        for field, expected in expected_readiness.items():
            if readiness.get(field) != expected:
                failures.append(f"Crawl4AI readiness_probe {field} mismatch: {runtime_plan_path}")

    cleanup = runtime_plan.get("cleanup")
    if not isinstance(cleanup, dict):
        failures.append(f"Crawl4AI runtime plan cleanup missing: {runtime_plan_path}")
    else:
        if cleanup.get("strategy") != "docker_rm_force_test_owned_unique_container":
            failures.append(f"Crawl4AI cleanup strategy must remove only a test-owned unique container: {runtime_plan_path}")
        if cleanup.get("must_not_remove_container_name") != "crawl4ai":
            failures.append(f"Crawl4AI cleanup must explicitly protect user-owned crawl4ai container name: {runtime_plan_path}")
        if lifecycle_passed:
            if cleanup.get("status") != "passed":
                failures.append(f"Crawl4AI cleanup must be passed after live lifecycle evidence: {runtime_plan_path}")
            evidence = cleanup.get("evidence")
            if not isinstance(evidence, list) or not evidence:
                failures.append(f"Crawl4AI cleanup must cite lifecycle evidence after pass: {runtime_plan_path}")
            if str(cleanup.get("last_validated_container_name", "")).startswith("zappa-crawl4ai-health-") is not True:
                failures.append(f"Crawl4AI cleanup must record the test-owned validated container name: {runtime_plan_path}")
        elif cleanup.get("status") != "not_validated":
            failures.append(f"Crawl4AI cleanup must remain not_validated before live lifecycle evidence: {runtime_plan_path}")

    blocked_endpoints = runtime_plan.get("blocked_endpoints", [])
    if not any(isinstance(endpoint, dict) and endpoint.get("route") == "/crawl" for endpoint in blocked_endpoints):
        failures.append(f"Crawl4AI runtime plan must explicitly block /crawl promotion: {runtime_plan_path}")

    runtime_blockers = runtime_plan.get("blockers", [])
    required_runtime_blockers = [
        "build_and_template_validate_http_status_below_400_assertion",
        "run_qaaS_template_validation",
        "run_live_qaaS_act_assert_validation",
        "run_live_airgapped_weak_model_validation",
        "run_strong_review_against_selected_contract_evidence",
    ]
    if lifecycle_passed:
        if "prove_docker_lifecycle_and_cleanup_without_deleting_user_container" in runtime_blockers:
            failures.append(f"Crawl4AI runtime plan still contains satisfied Docker lifecycle blocker: {runtime_plan_path}")
    else:
        required_runtime_blockers.insert(0, "prove_docker_lifecycle_and_cleanup_without_deleting_user_container")
    for blocker in required_runtime_blockers:
        if blocker not in runtime_blockers:
            failures.append(f"Crawl4AI runtime plan missing blocker {blocker}: {runtime_plan_path}")

    blockers = get_blocker_ids(manifest)
    required_source_blockers = [
        "crawl4ai-status-below-400-hook-not-template-validated",
        "crawl4ai-health-body-contract-not-selected",
        "crawl4ai-crawl-endpoint-not-promoted",
        "qaas-template-live-not-run",
        "live-airgapped-weak-model-not-passed",
    ]
    if lifecycle_passed:
        if "crawl4ai-docker-lifecycle-not-proven" in blockers:
            failures.append(f"Crawl4AI candidate manifest still contains satisfied Docker lifecycle blocker: {manifest_path}")
    else:
        required_source_blockers.insert(0, "crawl4ai-docker-lifecycle-not-proven")
    for blocker_id in required_source_blockers:
        if blocker_id not in blockers:
            failures.append(f"Crawl4AI candidate manifest missing source blocker {blocker_id}: {manifest_path}")

    gates = get_gate_map(manifest)
    for ready_gate in ("selected-public-runtime-contract", "selected-public-healthcheck-contract", "qaas-docs-yaml-shape"):
        gate = gates.get(ready_gate)
        if not gate or gate.get("status") != "ready" or not gate.get("evidence"):
            failures.append(f"Crawl4AI ready gate missing evidence or ready status {ready_gate}: {manifest_path}")
    for lifecycle_gate in ("docker-crawl4ai-container-lifecycle", "cleanup-contract"):
        gate = gates.get(lifecycle_gate)
        if lifecycle_passed:
            if not gate or gate.get("status") != "passed" or not gate.get("evidence"):
                failures.append(f"Crawl4AI lifecycle gate missing passed status/evidence {lifecycle_gate}: {manifest_path}")
        elif not gate or gate.get("status") != "blocked" or not gate.get("blocked_reason"):
            failures.append(f"Crawl4AI lifecycle gate missing blocked status/reason {lifecycle_gate}: {manifest_path}")
    for blocked_gate in (
        "http-status-below-400-assertion-or-hook",
        "qaas-template",
        "qaas-live-act-assert",
        "airgapped-validation",
    ):
        gate = gates.get(blocked_gate)
        if not gate or gate.get("status") != "blocked" or not gate.get("blocked_reason"):
            failures.append(f"Crawl4AI blocked gate missing blocked status/reason {blocked_gate}: {manifest_path}")
    if lifecycle_passed:
        lifecycle_record = manifest.get("lifecycle_validation")
        if not isinstance(lifecycle_record, dict):
            failures.append(f"Crawl4AI manifest missing lifecycle_validation after lifecycle pass: {manifest_path}")
        else:
            summary_path = Path(str(lifecycle_record.get("summary", "")))
            transcript_path = Path(str(lifecycle_record.get("transcript", "")))
            response_path = Path(str(lifecycle_record.get("response", "")))
            for evidence_path, label in (
                (summary_path, "lifecycle summary"),
                (transcript_path, "lifecycle transcript"),
                (response_path, "lifecycle response"),
            ):
                require_under(evidence_path, coverage_dir if label == "lifecycle summary" else Path(r"D:\QaaS\_tmp\zappa-dont-cry\lifecycle-runs\selected-top-repo-candidates"), f"Crawl4AI {label}")
            if lifecycle_record.get("status") != "passed" or lifecycle_record.get("exit_code") != 0:
                failures.append(f"Crawl4AI lifecycle_validation must be passed with exit_code 0: {manifest_path}")


def validate_fastapi(record: dict, manifest: dict, selected: dict, manifest_path: Path, selected_path: Path, candidate_dir: Path):
    supports = selected_supports(selected)
    for required_support in ("runtime-contract", "http-contract", "candidate-executable-command"):
        if required_support not in supports:
            failures.append(f"selected contract lacks candidate support {required_support}: {selected_path}")

    artifacts, yaml, runtime_plan, runtime_plan_path = validate_common_candidate(record, manifest, selected, manifest_path, selected_path, candidate_dir)

    runner_path = candidate_dir / "test.qaas.yaml"
    app_path = candidate_dir / "app" / "main.py"
    schema_path = candidate_dir / "schemas" / "item-response.schema.json"
    request_payload_path = candidate_dir / "request-payloads" / "get-items-5.bin"
    for required_artifact in (app_path, schema_path, request_payload_path):
        if required_artifact not in artifacts:
            failures.append(f"required artifact not listed in manifest artifacts: {required_artifact}")
        require_under(required_artifact, candidate_dir, "required candidate artifact")

    require_marker(yaml, "Name: GetItemPayload", runner_path)
    require_marker(yaml, "Path: './request-payloads'", runner_path)
    require_marker(yaml, "SearchPattern: 'get-items-5.bin'", runner_path)
    require_marker(yaml, "Name: FastApiReadmeItemResponseSchemas", runner_path)
    require_marker(yaml, "Path: './schemas'", runner_path)
    require_marker(yaml, "SearchPattern: 'item-response.schema.json'", runner_path)
    require_marker(yaml, "Assertion: ObjectOutputJsonSchema", runner_path)
    require_marker(yaml, "Port: 8000", runner_path)
    require_marker(yaml, "Route: items/5?q=somequery", runner_path)
    require_no_marker(yaml, "Route: /items/5?q=somequery", runner_path, "FastAPI QaaS route must omit the leading slash to avoid a double-slash request")
    require_marker(yaml, "OutputDeserialize:", runner_path)
    require_marker(yaml, "Deserializer: Json", runner_path)
    require_marker(yaml, "OutputName: GetItemFive", runner_path)
    require_no_marker(yaml, "fastapi dev", runner_path, "candidate YAML embeds external process command instead of runtime plan")
    require_no_marker(yaml, "fastapi run", runner_path, "candidate YAML embeds external process command instead of runtime plan")
    require_no_marker(yaml, "uvicorn", runner_path, "candidate YAML embeds external process command instead of runtime plan")
    for invented_marker in ("QueryParameters", "ExpectedBody", "JsonPathEquals", "Assertion: ExactHttpTextBody", "OutputContentByExpectedCsvResults"):
        require_no_marker(yaml, invented_marker, runner_path, "FastAPI candidate uses non-selected or invented body/query assertion shape")
    if not re.search(r"(?s)Transactions:.*DataSourceNames:\s*\n\s*-\s*GetItemPayload.*DataSourcePatterns:\s*\n\s*-\s*GetItemPayload", yaml):
        failures.append(f"candidate transaction must be driven by GetItemPayload DataSourceNames and DataSourcePatterns: {runner_path}")
    if not re.search(r"(?s)Assertion: ObjectOutputJsonSchema.*DataSourceNames:\s*\n\s*-\s*FastApiReadmeItemResponseSchemas", yaml):
        failures.append(f"FastAPI body assertion must load FastApiReadmeItemResponseSchemas: {runner_path}")

    app_text = text(app_path)
    for marker in (
        "from fastapi import FastAPI",
        "app = FastAPI()",
        '@app.get("/")',
        'return {"Hello": "World"}',
        '@app.get("/items/{item_id}")',
        "def read_item(item_id: int, q: str | None = None):",
        'return {"item_id": item_id, "q": q}',
    ):
        require_marker(app_text, marker, app_path)

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
        expected_schema_core = {
            "$schema": "http://json-schema.org/draft-07/schema#",
            "type": "object",
            "required": ["item_id", "q"],
            "additionalProperties": False,
            "properties": {
                "item_id": {"const": 5},
                "q": {"const": "somequery"},
            },
        }
        if schema != expected_schema_core:
            failures.append(f"FastAPI JSON schema does not exactly match README response evidence: {schema_path}")
    except Exception as exc:
        failures.append(f"failed to validate FastAPI JSON schema {schema_path}: {exc}")

    try:
        if request_payload_path.read_bytes() != b"":
            failures.append(f"FastAPI GET payload driver must be an empty byte file: {request_payload_path}")
    except Exception as exc:
        failures.append(f"failed to validate FastAPI request payload {request_payload_path}: {exc}")

    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation"))
    qaas_fields = (
        manifest.get("build_validation"),
        manifest.get("template_validation"),
        manifest.get("live_validation"),
        manifest.get("selected_candidate_qaas_validation"),
        runtime_plan.get("qaas_validation"),
    )
    qaas_claimed = any(passed_validation(field) for field in qaas_fields)
    qaas_passed = all(passed_validation(field) for field in qaas_fields)
    if qaas_claimed and not qaas_passed:
        failures.append(f"FastAPI candidate must not claim QaaS validation yet: {manifest_path}")
    if qaas_passed:
        validate_fastapi_qaas_evidence(manifest, runtime_plan, manifest_path, runtime_plan_path)
    validate_runtime_plan_common(runtime_plan, runtime_plan_path, "fastapi/fastapi", "fastapi dev", lifecycle_passed, qaas_passed)
    runtime_blockers = runtime_plan.get("blockers", [])
    if lifecycle_passed:
        if not passed_validation(runtime_plan.get("lifecycle_validation")):
            failures.append(f"FastAPI runtime plan missing passed lifecycle_validation: {runtime_plan_path}")
        def validate_fastapi_response(response_path: Path):
            try:
                response = json.loads(response_path.read_text(encoding="utf-8-sig"))
                if response != {"item_id": 5, "q": "somequery"}:
                    failures.append(f"FastAPI lifecycle response must exactly match README-backed JSON body: {response_path}")
            except Exception as exc:
                failures.append(f"failed to validate FastAPI lifecycle response {response_path}: {exc}")

        validate_lifecycle_evidence_paths(
            manifest.get("lifecycle_validation"),
            runtime_plan.get("lifecycle_validation"),
            manifest_path,
            runtime_plan_path,
            "fastapi/fastapi",
            "selected-top-repo-candidate-lifecycle-fastapi.json",
            validate_fastapi_response,
            ("Command: fastapi dev", "Ready: True", "CleanupPassed: True", "ExitCode: 0"),
        )
    elif "prove_process_lifecycle_and_cleanup_without assuming private source" not in runtime_blockers:
        failures.append(f"FastAPI runtime plan missing lifecycle blocker before lifecycle validation passes: {runtime_plan_path}")
    if "run_strong_review_against_selected_contract_evidence" not in runtime_blockers:
        failures.append(f"FastAPI runtime plan missing strong-review blocker run_strong_review_against_selected_contract_evidence: {runtime_plan_path}")

    if runtime_plan.get("command_support") != "candidate-executable-command":
        failures.append(f"runtime plan must use candidate-executable-command support: {runtime_plan_path}")
    if runtime_plan.get("working_directory") != str(candidate_dir / "app"):
        failures.append(f"FastAPI runtime plan working_directory must be generated app directory: {runtime_plan_path}")
    if runtime_plan.get("fixture") != str(app_path):
        failures.append(f"FastAPI runtime plan fixture must be generated app/main.py: {runtime_plan_path}")
    if runtime_plan.get("expected_listen_url") != "http://127.0.0.1:8000":
        failures.append(f"FastAPI runtime plan expected_listen_url mismatch: {runtime_plan_path}")
    readiness = runtime_plan.get("readiness_probe")
    if not isinstance(readiness, dict):
        failures.append(f"FastAPI runtime plan readiness_probe missing: {runtime_plan_path}")
    else:
        if readiness.get("method") != "GET" or readiness.get("url") != "http://127.0.0.1:8000/items/5?q=somequery" or readiness.get("expected_status") != 200:
            failures.append(f"FastAPI runtime plan readiness_probe mismatch: {runtime_plan_path}")
        if readiness.get("expected_json") != {"item_id": 5, "q": "somequery"}:
            failures.append(f"FastAPI runtime plan readiness_probe expected_json mismatch: {runtime_plan_path}")

    cleanup = runtime_plan.get("cleanup")
    if not isinstance(cleanup, dict):
        failures.append(f"FastAPI runtime plan cleanup missing: {runtime_plan_path}")
    elif cleanup.get("status") == "passed" and not lifecycle_passed:
        failures.append(f"FastAPI runtime plan cleanup passed without manifest lifecycle_validation: {runtime_plan_path}")
    elif cleanup.get("status") != "passed" and lifecycle_passed:
        failures.append(f"FastAPI runtime plan cleanup must be passed when manifest lifecycle_validation passed: {runtime_plan_path}")

    blockers = get_blocker_ids(manifest)
    required_blockers = [
        "live-airgapped-weak-model-not-passed",
    ]
    validate_httpstatus_docs_advisory(manifest, manifest_path, qaas_passed, "FastAPI")
    if qaas_passed:
        if "qaas-template-live-not-run" in blockers:
            failures.append(f"FastAPI candidate manifest still contains satisfied blocker qaas-template-live-not-run: {manifest_path}")
    else:
        required_blockers.append("qaas-template-live-not-run")
    if not lifecycle_passed:
        required_blockers.append("fastapi-process-lifecycle-not-proven")
    elif "fastapi-process-lifecycle-not-proven" in blockers:
        failures.append(f"FastAPI candidate manifest still contains satisfied blocker fastapi-process-lifecycle-not-proven: {manifest_path}")
    for blocker_id in required_blockers:
        if blocker_id not in blockers:
            failures.append(f"FastAPI candidate manifest missing source blocker {blocker_id}: {manifest_path}")

    validate_common_gates(manifest, manifest_path, lifecycle_passed, qaas_passed, ("python-fastapi-process-lifecycle",))


def validate_gin(record: dict, manifest: dict, selected: dict, manifest_path: Path, selected_path: Path, candidate_dir: Path):
    supports = selected_supports(selected)
    for required_support in ("candidate-executable-command", "input-output-contract"):
        if required_support not in supports:
            failures.append(f"selected contract lacks candidate support {required_support}: {selected_path}")

    artifacts, yaml, runtime_plan, runtime_plan_path = validate_common_candidate(record, manifest, selected, manifest_path, selected_path, candidate_dir)

    runner_path = candidate_dir / "test.qaas.yaml"
    app_path = candidate_dir / "app" / "main.go"
    schema_path = candidate_dir / "schemas" / "ping-response.schema.json"
    request_payload_path = candidate_dir / "request-payloads" / "get-ping.bin"
    for required_artifact in (app_path, schema_path, request_payload_path):
        if required_artifact not in artifacts:
            failures.append(f"required artifact not listed in manifest artifacts: {required_artifact}")
        require_under(required_artifact, candidate_dir, "required candidate artifact")

    require_marker(yaml, "Name: GetPingPayload", runner_path)
    require_marker(yaml, "Path: './request-payloads'", runner_path)
    require_marker(yaml, "SearchPattern: 'get-ping.bin'", runner_path)
    require_marker(yaml, "Name: GinReadmePingResponseSchemas", runner_path)
    require_marker(yaml, "Path: './schemas'", runner_path)
    require_marker(yaml, "SearchPattern: 'ping-response.schema.json'", runner_path)
    require_marker(yaml, "Assertion: ObjectOutputJsonSchema", runner_path)
    require_marker(yaml, "Port: 8080", runner_path)
    require_marker(yaml, "Route: /ping", runner_path)
    require_marker(yaml, "OutputDeserialize:", runner_path)
    require_marker(yaml, "Deserializer: Json", runner_path)
    require_marker(yaml, "OutputName: GetPing", runner_path)
    require_no_marker(yaml, "go run", runner_path, "candidate YAML embeds external process command instead of runtime plan")
    require_no_marker(yaml, "gin.Default", runner_path, "candidate YAML embeds Go source instead of runtime plan")
    require_no_marker(yaml, "r.Run", runner_path, "candidate YAML embeds Go source instead of runtime plan")
    for invented_marker in ("QueryParameters", "ExpectedBody", "JsonPathEquals", "Assertion: ExactHttpTextBody", "OutputContentByExpectedCsvResults"):
        require_no_marker(yaml, invented_marker, runner_path, "Gin candidate uses non-selected or invented body/query assertion shape")
    if not re.search(r"(?s)Transactions:.*DataSourceNames:\s*\n\s*-\s*GetPingPayload.*DataSourcePatterns:\s*\n\s*-\s*GetPingPayload", yaml):
        failures.append(f"candidate transaction must be driven by GetPingPayload DataSourceNames and DataSourcePatterns: {runner_path}")
    if not re.search(r"(?s)Assertion: ObjectOutputJsonSchema.*DataSourceNames:\s*\n\s*-\s*GinReadmePingResponseSchemas", yaml):
        failures.append(f"Gin body assertion must load GinReadmePingResponseSchemas: {runner_path}")

    app_text = text(app_path)
    for marker in (
        "package main",
        '"log"',
        '"net/http"',
        '"github.com/gin-gonic/gin"',
        "r := gin.Default()",
        'r.GET("/ping", func(c *gin.Context) {',
        "c.JSON(http.StatusOK, gin.H{",
        '"message": "pong"',
        "if err := r.Run(); err != nil {",
        'log.Fatalf("failed to run server: %v", err)',
    ):
        require_marker(app_text, marker, app_path)

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
        expected_schema_core = {
            "$schema": "http://json-schema.org/draft-07/schema#",
            "type": "object",
            "required": ["message"],
            "additionalProperties": False,
            "properties": {
                "message": {"const": "pong"},
            },
        }
        if schema != expected_schema_core:
            failures.append(f"Gin JSON schema does not exactly match README response evidence: {schema_path}")
    except Exception as exc:
        failures.append(f"failed to validate Gin JSON schema {schema_path}: {exc}")

    try:
        if request_payload_path.read_bytes() != b"":
            failures.append(f"Gin GET payload driver must be an empty byte file: {request_payload_path}")
    except Exception as exc:
        failures.append(f"failed to validate Gin request payload {request_payload_path}: {exc}")

    lifecycle_passed = passed_validation(manifest.get("lifecycle_validation"))
    qaas_passed = (
        passed_validation(manifest.get("build_validation"))
        and passed_validation(manifest.get("template_validation"))
        and passed_validation(manifest.get("live_validation"))
        and passed_validation(manifest.get("selected_candidate_qaas_validation"))
        and passed_validation(runtime_plan.get("qaas_validation"))
    )
    validate_runtime_plan_common(runtime_plan, runtime_plan_path, "gin-gonic/gin", "go run main.go", lifecycle_passed, qaas_passed)

    if runtime_plan.get("command_support") != "candidate-executable-command":
        failures.append(f"runtime plan must use candidate-executable-command support: {runtime_plan_path}")
    if runtime_plan.get("working_directory") != str(candidate_dir / "app"):
        failures.append(f"Gin runtime plan working_directory must be generated app directory: {runtime_plan_path}")
    if runtime_plan.get("fixture") != str(app_path):
        failures.append(f"Gin runtime plan fixture must be generated app/main.go: {runtime_plan_path}")
    if runtime_plan.get("expected_listen_url") != "http://127.0.0.1:8080":
        failures.append(f"Gin runtime plan expected_listen_url mismatch: {runtime_plan_path}")
    readiness = runtime_plan.get("readiness_probe")
    if not isinstance(readiness, dict):
        failures.append(f"Gin runtime plan readiness_probe missing: {runtime_plan_path}")
    else:
        if readiness.get("method") != "GET" or readiness.get("url") != "http://127.0.0.1:8080/ping" or readiness.get("expected_status") != 200:
            failures.append(f"Gin runtime plan readiness_probe mismatch: {runtime_plan_path}")
        if readiness.get("expected_json") != {"message": "pong"}:
            failures.append(f"Gin runtime plan readiness_probe expected_json mismatch: {runtime_plan_path}")

    cleanup = runtime_plan.get("cleanup")
    if not isinstance(cleanup, dict):
        failures.append(f"Gin runtime plan cleanup missing: {runtime_plan_path}")
    elif cleanup.get("status") == "passed" and not lifecycle_passed:
        failures.append(f"Gin runtime plan cleanup passed without manifest lifecycle_validation: {runtime_plan_path}")
    elif cleanup.get("status") != "passed" and lifecycle_passed:
        failures.append(f"Gin runtime plan cleanup must be passed when manifest lifecycle_validation passed: {runtime_plan_path}")

    blockers = get_blocker_ids(manifest)
    required_blockers = [
        "live-airgapped-weak-model-not-passed",
    ]
    validate_httpstatus_docs_advisory(manifest, manifest_path, qaas_passed, "Gin")
    if qaas_passed:
        if "qaas-template-live-not-run" in blockers:
            failures.append(f"Gin candidate manifest still contains satisfied blocker qaas-template-live-not-run: {manifest_path}")
    else:
        required_blockers.append("qaas-template-live-not-run")
    if not lifecycle_passed:
        required_blockers.append("gin-process-lifecycle-not-proven")
    elif "gin-process-lifecycle-not-proven" in blockers:
        failures.append(f"Gin candidate manifest still contains satisfied blocker gin-process-lifecycle-not-proven: {manifest_path}")
    for blocker_id in required_blockers:
        if blocker_id not in blockers:
            failures.append(f"Gin candidate manifest missing source blocker {blocker_id}: {manifest_path}")

    validate_common_gates(manifest, manifest_path, lifecycle_passed, qaas_passed, ("go-version-and-module-resolution", "go-gin-process-lifecycle"))


def validate_runtime_plan_common(runtime_plan: dict, runtime_plan_path: Path, repository: str, command: str, lifecycle_passed: bool, qaas_passed: bool):
    if runtime_plan.get("repository") != repository:
        failures.append(f"runtime plan repository mismatch: {runtime_plan_path}")
    if runtime_plan.get("status") != "candidate_runtime_plan_blocked":
        failures.append(f"runtime plan status must stay blocked: {runtime_plan_path}")
    if runtime_plan.get("promotion_state") != "blocked":
        failures.append(f"runtime plan promotion_state must stay blocked: {runtime_plan_path}")
    if runtime_plan.get("lifecycle_owner") != "external_harness_not_qaas_yaml":
        failures.append(f"runtime plan must keep lifecycle outside QaaS YAML: {runtime_plan_path}")
    if runtime_plan.get("command") != command:
        failures.append(f"runtime plan command mismatch: {runtime_plan_path}")
    runtime_blockers = runtime_plan.get("blockers", [])
    if lifecycle_passed and "prove_process_lifecycle_and_cleanup_without assuming private source" in runtime_blockers:
        failures.append(f"runtime plan still contains satisfied lifecycle blocker: {runtime_plan_path}")
    if qaas_passed:
        for satisfied_blocker in ("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation"):
            if satisfied_blocker in runtime_blockers:
                failures.append(f"runtime plan still contains satisfied blocker {satisfied_blocker}: {runtime_plan_path}")
    else:
        for blocker in ("run_qaaS_template_validation", "run_live_qaaS_act_assert_validation"):
            if blocker not in runtime_blockers:
                failures.append(f"runtime plan missing blocker {blocker}: {runtime_plan_path}")
    if "run_live_airgapped_weak_model_validation" not in runtime_blockers:
        failures.append(f"runtime plan missing weak-model blocker run_live_airgapped_weak_model_validation: {runtime_plan_path}")


index_path = candidate_root / "selected-candidate-index.json"
if any(part.lower() == "promotion-packets" for part in candidate_root.resolve().parts):
    failures.append(f"selected candidate root must not be under promotion-packets: {candidate_root}")
if not index_path.exists():
    failures.append(f"missing selected candidate index: {index_path}")
    index = {}
else:
    index = read_json(index_path)
    require_no_utf8_bom(index_path, "selected candidate index")

records = index.get("records", [])
if not isinstance(records, list) or not records:
    failures.append(f"selected candidate index has no records: {index_path}")
    records = []

if index.get("selected_candidate_count") != len(records):
    failures.append(f"selected_candidate_count mismatch: {index_path}")

selected_index_path = selected_contracts_root / "selected-contract-index.json"
selected_contract_count = None
if selected_index_path.exists():
    selected_index = read_json(selected_index_path)
    selected_contract_count = selected_index.get("selected_repository_count")
    deferred_records = index.get("deferred_records", [])
    if not isinstance(deferred_records, list):
        failures.append(f"deferred_records must be a list when selected-contract index exists: {index_path}")
        deferred_records = []
    if index.get("selected_contract_count") != selected_contract_count:
        failures.append(f"selected_contract_count mismatch: {index_path}")
    if len(records) + len(deferred_records) != selected_contract_count:
        failures.append(f"selected candidates plus deferred records must equal selected contracts: {index_path}")
    generated_repos = {record.get("repository") for record in records if isinstance(record, dict)}
    deferred_repos = {record.get("repository") for record in deferred_records if isinstance(record, dict)}
    for selected_record in selected_index.get("records", []):
        repo = selected_record.get("repository")
        if repo not in generated_repos and repo not in deferred_repos:
            failures.append(f"selected repository missing generated or deferred candidate record: {repo}")
    for deferred in deferred_records:
        if not isinstance(deferred, dict):
            failures.append(f"deferred record is not an object: {index_path}")
            continue
        if deferred.get("promotion_state") != "blocked":
            failures.append(f"deferred record promotion_state must be blocked: {deferred}")
        blockers = deferred.get("blockers")
        if not isinstance(blockers, list) or not blockers:
            failures.append(f"deferred record missing blockers: {deferred}")
        selected_path = Path(deferred.get("selected_contract", ""))
        require_under(selected_path, selected_contracts_root, "deferred selected contract")
        if deferred.get("repository") == "unclecode/crawl4ai":
            validate_crawl4ai_deferred(deferred, selected_path, index_path)

summary = {
    "schema_version": 1,
    "status": "selected_candidate_packets_blocked",
    "completion_ready": False,
    "candidate_count": len(records),
    "selected_contract_count": selected_contract_count,
    "deferred_candidate_count": len(index.get("deferred_records", []) or []),
    "repositories": [],
}

validators = {
    "typicode/json-server": validate_json_server,
    "expressjs/express": validate_express,
    "denoland/deno": validate_deno,
    "fastapi/fastapi": validate_fastapi,
    "gin-gonic/gin": validate_gin,
    "pallets/flask": validate_flask,
    "unclecode/crawl4ai": validate_crawl4ai,
}

for record in records:
    if not isinstance(record, dict):
        failures.append(f"candidate index record is not an object: {index_path}")
        continue

    if record.get("promotion_state") != "blocked":
        failures.append(f"candidate index record promotion_state must be blocked: {record}")
    if record.get("status") != "candidate_packet_blocked_until_template_live_airgapped_validation":
        failures.append(f"candidate index record has unexpected status: {record}")

    manifest_path = Path(record.get("manifest", ""))
    selected_path = Path(record.get("selected_contract", ""))
    candidate_dir = Path(record.get("directory", ""))
    require_under(candidate_dir, candidate_root, "candidate directory")
    require_under(manifest_path, candidate_root, "candidate manifest")
    require_under(selected_path, selected_contracts_root, "selected contract")
    if not manifest_path.exists() or not selected_path.exists():
        continue

    manifest = read_json(manifest_path)
    selected = read_json(selected_path)

    repository = record.get("repository")
    summary["repositories"].append(repository)
    validator = validators.get(repository)
    if validator is None:
        failures.append(f"no selected candidate validator registered for repository {repository}: {manifest_path}")
        continue
    validator(record, manifest, selected, manifest_path, selected_path, candidate_dir)

coverage_dir.mkdir(parents=True, exist_ok=True)
summary_path = coverage_dir / "selected-top-repo-candidates.json"
summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Selected top-repo candidate check passed for {len(records)} candidate packet(s).")
print(f"Record: {summary_path}")
