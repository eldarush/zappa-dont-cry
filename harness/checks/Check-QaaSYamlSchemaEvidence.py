#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


generated_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
schema_root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\qaas-docs\docs\assets\schemas")
out_dir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")

runner_schema_path = schema_root / "runner-family-schema.json"
mocker_schema_path = schema_root / "mocker-family-schema.json"
failures: list[str] = []


def read_json(path: Path):
    if not path.exists():
        failures.append(f"missing schema/evidence file: {path}")
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"failed to parse JSON {path}: {exc}")
        return {}


def top_level_yaml_keys(path: Path) -> list[str]:
    keys: list[str] = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not line or line.startswith("#") or line[0].isspace():
            continue
        match = re.match(r"^([A-Za-z][A-Za-z0-9_]*):", line)
        if match:
            keys.append(match.group(1))
    return keys


def passed_validation(manifest: dict, field: str) -> bool:
    value = manifest.get(field)
    return (
        isinstance(value, dict)
        and value.get("status") == "passed"
        and value.get("exit_code") == 0
        and bool(value.get("transcript"))
        and Path(value.get("transcript")).exists()
    )


def path_is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def blocked_without_placeholders_allowed(manifest: dict, manifest_path: Path) -> bool:
    expected_manifest_path = generated_root / "promotion-seed" / "qaas-docs-hello-world-http" / "qaas-artifact-manifest.json"
    blocked_reason = str(manifest.get("blocked_reason") or "").lower()
    airgapped = manifest.get("airgapped_validation") or {}
    source_blockers = manifest.get("source_only_blockers") or []
    if isinstance(source_blockers, dict):
        source_blockers = [source_blockers]
    return (
        manifest_path.resolve() == expected_manifest_path.resolve()
        and path_is_relative_to(manifest_path, generated_root)
        and manifest.get("campaign_id") == "promotion-seed-qaas-docs-hello-world-http"
        and manifest.get("promotion_state") == "blocked"
        and manifest.get("status") == "blocked_until_contract_review"
        and passed_validation(manifest, "template_validation")
        and passed_validation(manifest, "build_validation")
        and passed_validation(manifest, "live_validation")
        and isinstance(airgapped, dict)
        and airgapped.get("required") is True
        and airgapped.get("status") != "passed"
        and airgapped.get("dry_run") is True
        and any(
            isinstance(blocker, dict)
            and blocker.get("blocker_id") == "promotion-seed-live-airgapped-not-passed"
            for blocker in source_blockers
        )
        and "airgapped" in blocked_reason
    )


runner_schema = read_json(runner_schema_path)
mocker_schema = read_json(mocker_schema_path)
runner_allowed = set((runner_schema.get("properties") or {}).keys())
mocker_allowed = set((mocker_schema.get("properties") or {}).keys())

if not runner_allowed:
    failures.append(f"runner schema has no top-level properties: {runner_schema_path}")
if not mocker_allowed:
    failures.append(f"mocker schema has no top-level properties: {mocker_schema_path}")

yaml_count = 0
runner_count = 0
mocker_count = 0
blocked_placeholder_count = 0

placeholder_markers = (
    "__DOCUMENTED_ASSERTION_OR_CUSTOM__",
    "Sessions: []",
    "Stubs: []",
    "Links: []",
    "Storages: []",
    "DataSources: []",
    "blocked_until_",
)

for manifest_path in sorted(generated_root.rglob("qaas-artifact-manifest.json")):
    manifest = read_json(manifest_path)
    if not manifest:
        continue
    promotion_state = manifest.get("promotion_state")
    blocked = promotion_state == "blocked"
    blocked_reason = manifest.get("blocked_reason")

    for artifact in manifest.get("artifacts", []):
        path = Path(artifact)
        if path.suffix.lower() not in {".yaml", ".yml"}:
            continue
        yaml_count += 1
        if not path.exists():
            failures.append(f"manifest references missing YAML artifact {path}: {manifest_path}")
            continue

        if path.name == "test.qaas.yaml":
            kind = "runner"
            allowed = runner_allowed
            evidence_path = runner_schema_path
            runner_count += 1
        elif path.name == "mocker.qaas.yaml":
            kind = "mocker"
            allowed = mocker_allowed
            evidence_path = mocker_schema_path
            mocker_count += 1
        else:
            failures.append(f"unknown QaaS YAML artifact name {path.name}: {path}")
            continue

        keys = top_level_yaml_keys(path)
        if not keys:
            failures.append(f"{kind} YAML has no top-level keys: {path}")
        for key in keys:
            if key not in allowed:
                failures.append(f"{kind} YAML uses undocumented top-level key {key!r} from {evidence_path}: {path}")

        content = path.read_text(encoding="utf-8-sig")
        has_placeholder = any(marker in content for marker in placeholder_markers)
        if has_placeholder:
            blocked_placeholder_count += 1
            if not blocked:
                failures.append(f"placeholder/blocking marker appears in non-blocked manifest: {path}")
            if not blocked_reason:
                failures.append(f"blocked YAML placeholder lacks manifest blocked_reason: {path}")
        elif blocked and not blocked_without_placeholders_allowed(manifest, manifest_path):
            failures.append(f"blocked YAML lacks explicit blocked/placeholder marker: {path}")

        if not blocked:
            if kind == "runner" and ("Sessions: []" in content or "__DOCUMENTED_ASSERTION_OR_CUSTOM__" in content):
                failures.append(f"executable runner YAML still contains blocked runner placeholders: {path}")
            if kind == "mocker" and "Stubs: []" in content:
                failures.append(f"executable mocker YAML still contains blocked mocker placeholders: {path}")

if yaml_count == 0:
    failures.append(f"no QaaS YAML artifacts found under {generated_root}")

out_dir.mkdir(parents=True, exist_ok=True)
record_path = out_dir / "qaas-yaml-schema-evidence.json"
record = {
    "schema_version": 1,
    "runner_schema": str(runner_schema_path),
    "mocker_schema": str(mocker_schema_path),
    "runner_allowed_top_level_keys": sorted(runner_allowed),
    "mocker_allowed_top_level_keys": sorted(mocker_allowed),
    "yaml_count": yaml_count,
    "runner_yaml_count": runner_count,
    "mocker_yaml_count": mocker_count,
    "blocked_placeholder_yaml_count": blocked_placeholder_count,
}
record_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"QaaS YAML schema evidence check passed for {yaml_count} YAML artifacts.")
print(f"Record: {record_path}")
