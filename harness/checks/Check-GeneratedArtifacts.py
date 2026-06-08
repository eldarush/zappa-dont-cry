#!/usr/bin/env python3
import json
import sys
from pathlib import Path


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
target = sys.argv[2] if len(sys.argv) > 2 else "all"
contract_path = Path(r"D:\QaaS\_tools\zappa-harness\fixtures\artifact-contract.required-fields.json")
contract = json.loads(contract_path.read_text(encoding="utf-8"))

roots = []
if target in ("all", "docs-coverage"):
    roots.append(root / "docs-coverage")
if target in ("all", "top-repos"):
    roots.append(root / "top-repos")

failures = []
manifest_count = 0
allowed_artifact_types = {
    "runner-yaml",
    "runner-code",
    "mocker-yaml",
    "mocker-code",
    "hook",
    "config-as-code",
    "dependency-gate",
    "documentation",
}
required_case_fields = (
    "case_id",
    "scenario",
    "artifact_type",
    "public_evidence",
    "setup",
    "action",
    "assertions",
    "cleanup",
    "blocked_reason",
    "artifact_paths",
)

for base in roots:
    if not base.exists():
        failures.append(f"missing generated artifact root: {base}")
        continue
    for manifest_path in sorted(base.rglob("qaas-artifact-manifest.json")):
        manifest_count += 1
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        except Exception as exc:
            failures.append(f"manifest parse failed: {manifest_path}: {exc}")
            continue

        required = list(contract["requiredManifestFields"])
        if "top-repos" in manifest_path.parts:
            required += contract["topRepoAdditionalFields"]

        for field in required:
            if field not in manifest:
                failures.append(f"missing field {field}: {manifest_path}")

        status = manifest.get("status")
        if status not in contract["allowedBlockedStatuses"]:
            failures.append(f"unexpected status {status}: {manifest_path}")

        for list_field in ("intent_questions", "intent_assumptions", "cases", "assertions", "dependency_gates"):
            value = manifest.get(list_field)
            if not isinstance(value, list) or not value:
                failures.append(f"{list_field} missing or empty: {manifest_path}")

        for list_field in ("cleanup", "source_only_blockers"):
            value = manifest.get(list_field)
            if not isinstance(value, list):
                failures.append(f"{list_field} missing or not a list: {manifest_path}")

        airgapped = manifest.get("airgapped_validation")
        if not isinstance(airgapped, dict) or airgapped.get("required") is not True:
            failures.append(f"airgapped_validation.required is not true: {manifest_path}")
        elif airgapped.get("status") == "passed":
            transcript = airgapped.get("transcript")
            if not transcript or not Path(transcript).exists():
                failures.append(f"passed airgapped validation without transcript: {manifest_path}")
            elif "DryRun: True" in Path(transcript).read_text(encoding="utf-8-sig", errors="ignore"):
                failures.append(f"airgapped passed transcript is a dry run: {manifest_path}")

        artifacts = manifest.get("artifacts", [])
        if manifest.get("artifact_count") != len(artifacts):
            failures.append(f"artifact_count mismatch: {manifest_path}")
        artifact_paths = [Path(artifact) for artifact in artifacts]
        for artifact in artifacts:
            if not Path(artifact).exists():
                failures.append(f"missing artifact path {artifact}: {manifest_path}")

        for case in manifest.get("cases", []):
            if not isinstance(case, dict):
                failures.append(f"case is not an object: {manifest_path}")
                continue
            for field in required_case_fields:
                if field not in case:
                    failures.append(f"case missing {field}: {manifest_path}")
            for string_field in ("case_id", "scenario", "artifact_type", "blocked_reason"):
                if not isinstance(case.get(string_field), str) or not case.get(string_field, "").strip():
                    failures.append(f"case {string_field} missing or empty: {manifest_path}")
            artifact_type = case.get("artifact_type")
            if artifact_type not in allowed_artifact_types:
                failures.append(f"case has invalid artifact_type {artifact_type}: {manifest_path}")
            for list_field in ("public_evidence", "setup", "action", "assertions"):
                value = case.get(list_field)
                if not isinstance(value, list) or not value:
                    failures.append(f"case {list_field} missing or empty: {manifest_path}")
            cleanup = case.get("cleanup")
            if not isinstance(cleanup, list) or not cleanup:
                failures.append(f"case cleanup missing or empty: {manifest_path}")

            case_artifact_paths = case.get("artifact_paths")
            if not isinstance(case_artifact_paths, list) or not case_artifact_paths:
                failures.append(f"case artifact_paths missing or empty: {manifest_path}")
                case_paths = []
            else:
                case_paths = [Path(path) for path in case_artifact_paths]
                manifest_dir = manifest_path.parent.resolve()
                for path in case_paths:
                    if not path.exists():
                        failures.append(f"case artifact path does not exist {path}: {manifest_path}")
                        continue
                    try:
                        path.resolve().relative_to(manifest_dir)
                    except ValueError:
                        failures.append(f"case artifact path is outside manifest directory {path}: {manifest_path}")
                    if path not in artifact_paths:
                        failures.append(f"case artifact path not listed in manifest artifacts {path}: {manifest_path}")

            if artifact_type == "runner-yaml" and not any(path.name == "test.qaas.yaml" for path in case_paths):
                failures.append(f"runner-yaml case lacks test.qaas.yaml artifact: {manifest_path}")
            elif artifact_type == "mocker-yaml" and not any(path.name == "mocker.qaas.yaml" for path in case_paths):
                failures.append(f"mocker-yaml case lacks mocker.qaas.yaml artifact: {manifest_path}")
            elif artifact_type in {"runner-code", "mocker-code", "config-as-code", "hook"} and not any(path.suffix.lower() == ".cs" for path in case_paths):
                failures.append(f"{artifact_type} case lacks C# artifact: {manifest_path}")

        artifact_types = manifest.get("artifact_types")
        if isinstance(artifact_types, list):
            case_types = {case.get("artifact_type") for case in manifest.get("cases", []) if isinstance(case, dict)}
            for artifact_type in artifact_types:
                if artifact_type not in case_types:
                    failures.append(f"artifact_types entry lacks matching case {artifact_type}: {manifest_path}")

        docs_evidence = manifest.get("docs_evidence", [])
        if not isinstance(docs_evidence, list) or not docs_evidence:
            failures.append(f"empty docs_evidence: {manifest_path}")

if manifest_count == 0:
    failures.append(f"no manifests found for target {target}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Generated artifact manifest check passed for {manifest_count} manifests.")
