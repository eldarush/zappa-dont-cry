#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


DEFAULT_POLICY_PATH = Path(r"D:\QaaS\_tools\weak-model-policy.json")


@dataclass(frozen=True)
class WeakEvidenceResult:
    weak_validation_eligible: bool
    weak_validation_passed: bool
    evidence_class: str
    eligibility_source: str
    not_weak_reason: str
    classification: str
    dry_run: bool | None
    harness: str
    profile: str
    model: str
    transcript: str
    actual_transcript: str
    summary: str
    reasons: tuple[str, ...]
    expected_models: tuple[str, ...] = ()
    attempted_model_count: int = 0
    missing_attempt_count: int = 0


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def load_policy(policy_path: Path | str = DEFAULT_POLICY_PATH) -> dict[str, Any]:
    path = Path(policy_path)
    if not path.exists():
        raise FileNotFoundError(f"weak model policy not found: {path}")
    return read_json(path)


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _field(text: str, name: str) -> str:
    match = re.search(rf"(?im)^{re.escape(name)}:\s*(.+?)\s*$", text)
    return match.group(1).strip() if match else ""


def _parse_bool(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if value is None:
        return None
    lowered = str(value).strip().lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    return None


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig", errors="ignore")


def _resolve_existing(raw_path: Any, reasons: list[str], label: str) -> Path | None:
    if not raw_path:
        reasons.append(f"{label} path is missing")
        return None
    path = Path(str(raw_path))
    if not path.exists():
        reasons.append(f"{label} path does not exist: {path}")
        return None
    return path.resolve()


def _is_under(path: Path, roots: Iterable[Path]) -> bool:
    resolved = path.resolve()
    for root in roots:
        try:
            resolved.relative_to(root.resolve())
            return True
        except ValueError:
            continue
    return False


def _require_under(path: Path | None, roots: Iterable[Path], reasons: list[str], label: str) -> None:
    if path is None:
        return
    if not _is_under(path, roots):
        joined = ", ".join(str(root) for root in roots)
        reasons.append(f"{label} must stay under one of: {joined}; got {path}")


def _transcript_path_from_wrapper(text: str) -> str:
    matches = re.findall(r"(?im)^Transcript:\s*(.+?)\s*$", text)
    return matches[-1].strip() if matches else ""


def _model_from_transcript_path(path: Path) -> str:
    name = path.name
    match = re.search(r"-claude-copilot-(?P<model>.+?)\.md$", name, re.IGNORECASE)
    if not match:
        match = re.search(r"-copilot-(?P<model>.+?)\.md$", name, re.IGNORECASE)
    if not match:
        return ""
    return match.group("model").replace("id_", "id:")


def _first_summary_model(summary_text: str) -> str:
    models_line = _field(summary_text, "Models")
    models = [model.strip() for model in models_line.split(",") if model.strip()]
    return models[0] if len(models) == 1 else ""


def _classification(text: str, exit_code: int | None, dry_run: bool | None) -> str:
    if dry_run is True or re.search(r"(?im)^Command:\s*DRY_RUN\b", text):
        return "dry_run_assembly"
    if re.search(
        r"additional_spend_limit_reached|additional usage limit|user_weekly_rate_limited|"
        r"rate-limiting chat requests|retry-after|\b402\b",
        text,
        re.IGNORECASE,
    ) or exit_code == 75:
        return "quota_blocked"
    if re.search(r'Model "[^"]+" from --model flag is not available|model .* is not available', text, re.IGNORECASE):
        return "model_unavailable"
    if exit_code == 0:
        return "live_transcript_ready"
    return "unknown_failure"


def _weak_evidence_config(policy: dict[str, Any], reasons: list[str]) -> dict[str, Any]:
    weak_evidence = policy.get("weakEvidence")
    if not isinstance(weak_evidence, dict):
        reasons.append("weakEvidence policy section is missing")
        return {}
    if weak_evidence.get("schemaVersion") != 1:
        reasons.append("weakEvidence.schemaVersion must be 1")
    return weak_evidence


def _eligibility(
    policy: dict[str, Any],
    harness: str,
    profile: str,
    model: str,
    dry_run: bool | None,
    command: str,
    required_evidence_classes: Iterable[str],
    reasons: list[str],
) -> tuple[bool, str, str]:
    weak_evidence = _weak_evidence_config(policy, reasons)
    if not weak_evidence:
        return False, "", "weak-evidence-policy-missing"

    if dry_run is True and weak_evidence.get("dryRunAlwaysNotWeak") is True:
        return False, "", "dry-run-is-never-weak-evidence"

    if harness in set(str(item) for item in _as_list(weak_evidence.get("denyHarnesses"))):
        return False, "", "harness-denied-for-weak-evidence"

    lowered_model = model.lower()
    for pattern in _as_list(weak_evidence.get("denyModelPatterns")):
        if re.search(str(pattern), lowered_model, re.IGNORECASE):
            return False, "", "model-denied-by-weak-evidence-policy"

    allow = weak_evidence.get("allow")
    if not isinstance(allow, dict):
        reasons.append("weakEvidence.allow is missing")
        return False, "", "weak-evidence-allowlist-missing"

    allowed = allow.get(harness)
    if not isinstance(allowed, dict):
        return False, "", "harness-not-in-weak-evidence-allowlist"

    allowed_profiles = set(str(item) for item in _as_list(allowed.get("profiles")))
    if profile not in allowed_profiles:
        return False, str(allowed.get("evidenceClass") or ""), "profile-not-in-weak-evidence-allowlist"

    allowed_models = set(str(item) for item in _as_list(allowed.get("models")))
    if model not in allowed_models:
        return False, str(allowed.get("evidenceClass") or ""), "model-not-in-weak-evidence-allowlist"

    evidence_class = str(allowed.get("evidenceClass") or "")
    accepted_classes = set(str(item) for item in required_evidence_classes)
    if accepted_classes and evidence_class not in accepted_classes:
        return False, evidence_class, "evidence-class-not-accepted-for-promotion"

    command_regex = str(allowed.get("requiredCommandRegex") or "")
    if command_regex and not re.search(command_regex, command, re.IGNORECASE):
        return False, evidence_class, "command-does-not-match-weak-route"

    forbidden_command_routes = (
        r"(^|[\\/\s])codex(\.cmd|\.exe|\.ps1)?(\s|$)",
        r"(^|[\\/\s])agy(\.cmd|\.exe|\.ps1)?(\s|$)",
    )
    if harness != "copilot":
        forbidden_command_routes += (r"(^|[\\/\s])copilot(\.cmd|\.exe|\.ps1)?(\s|$)",)
    for pattern in forbidden_command_routes:
        if re.search(pattern, command, re.IGNORECASE):
            return False, evidence_class, "command-uses-ineligible-hosted-route"

    return True, evidence_class, "weakEvidence.allow"


def _promotion_expected_routes(
    policy: dict[str, Any],
    required_evidence_classes: Iterable[str],
    reasons: list[str],
) -> tuple[tuple[str, str, str, str], ...]:
    weak_evidence = _weak_evidence_config(policy, reasons)
    allow = weak_evidence.get("allow") if weak_evidence else None
    if not isinstance(allow, dict):
        reasons.append("weakEvidence.allow is missing")
        return ()

    accepted_classes = set(str(item) for item in required_evidence_classes)
    routes: list[tuple[str, str, str, str]] = []
    for harness, allowed in allow.items():
        if not isinstance(allowed, dict):
            continue
        evidence_class = str(allowed.get("evidenceClass") or "")
        if accepted_classes and evidence_class not in accepted_classes:
            continue
        profiles = [str(item) for item in _as_list(allowed.get("profiles"))]
        models = [str(item) for item in _as_list(allowed.get("models"))]
        for profile in profiles:
            if profile != "airgapped":
                continue
            for model in models:
                if model:
                    routes.append((str(harness), profile, model, evidence_class))

    if not routes:
        reasons.append("weakEvidence policy defines no required promotion weak model routes")
    return tuple(routes)


def _read_index(index_path: Path | None, reasons: list[str]) -> dict[str, Any]:
    if index_path is None:
        return {}
    try:
        index = read_json(index_path)
    except Exception as exc:
        reasons.append(f"airgapped_validation.index could not be parsed as JSON: {exc}")
        return {}
    if not isinstance(index, dict):
        reasons.append("airgapped_validation.index must be a JSON object")
        return {}
    return index


def _record_bool(record: dict[str, Any], name: str) -> bool | None:
    return _parse_bool(record.get(name))


def _validate_index_record(
    record: dict[str, Any],
    expected_harness: str,
    expected_profile: str,
    expected_model: str,
    expected_evidence_class: str,
    policy: dict[str, Any],
    required_evidence_classes: Iterable[str],
    allowed_roots: Iterable[Path],
    reasons: list[str],
) -> bool:
    label = f"airgapped_validation.index record for {expected_model}"
    record_ok = True

    record_harness = str(record.get("harness") or "")
    record_profile = str(record.get("profile") or "")
    record_model = str(record.get("model") or "")
    if record_harness != expected_harness:
        reasons.append(f"{label} Harness must be {expected_harness}")
        record_ok = False
    if record_profile != expected_profile:
        reasons.append(f"{label} Profile must be {expected_profile}")
        record_ok = False
    if record_model != expected_model:
        reasons.append(f"{label} Model must be {expected_model}")
        record_ok = False

    record_dry_run = _record_bool(record, "dry_run")
    if record_dry_run is not False:
        reasons.append(f"{label} dry_run must be false")
        record_ok = False
    if record.get("weak_validation_passed") is not True:
        reasons.append(f"{label} weak_validation_passed must be true")
        record_ok = False
    if "weak_validation_eligible" in record and record.get("weak_validation_eligible") is not True:
        reasons.append(f"{label} weak_validation_eligible must be true")
        record_ok = False

    try:
        transcript_exit_code = int(record.get("transcript_exit_code"))
    except (TypeError, ValueError):
        transcript_exit_code = None
    if transcript_exit_code != 0:
        reasons.append(f"{label} transcript_exit_code must be 0")
        record_ok = False

    record_classification = str(record.get("classification") or "")
    accepted_live_classifications = {"live_transcript_ready", "live_model_execution_passed"}
    if record_classification not in accepted_live_classifications:
        reasons.append(f"{label} classification must be live, got {record_classification or 'missing'}")
        record_ok = False

    transcript_path = _resolve_existing(record.get("transcript"), reasons, f"{label} transcript")
    summary_path = _resolve_existing(record.get("summary"), reasons, f"{label} summary") if record.get("summary") else None
    _require_under(transcript_path, allowed_roots, reasons, f"{label} transcript")
    _require_under(summary_path, allowed_roots, reasons, f"{label} summary")

    transcript_text = _read_text(transcript_path) if transcript_path else ""
    summary_text = _read_text(summary_path) if summary_path else ""
    command = _field(transcript_text, "Command")
    exit_code_text = _field(transcript_text, "ExitCode")
    try:
        exit_code = int(exit_code_text) if exit_code_text else None
    except ValueError:
        exit_code = None
    transcript_harness = _field(transcript_text, "Harness") or record_harness
    transcript_profile = _field(transcript_text, "Profile") or record_profile
    transcript_model = _field(transcript_text, "Model") or (_model_from_transcript_path(transcript_path) if transcript_path else "")
    transcript_dry_run = _parse_bool(_field(transcript_text, "DryRun"))

    if not command:
        reasons.append(f"{label} transcript missing Command header")
        record_ok = False
    if exit_code != 0:
        reasons.append(f"{label} transcript ExitCode must be 0")
        record_ok = False
    if transcript_harness != expected_harness:
        reasons.append(f"{label} transcript Harness must be {expected_harness}")
        record_ok = False
    if transcript_profile != expected_profile:
        reasons.append(f"{label} transcript Profile must be {expected_profile}")
        record_ok = False
    if transcript_model != expected_model:
        reasons.append(f"{label} transcript Model must be {expected_model}")
        record_ok = False
    if transcript_dry_run is not False:
        reasons.append(f"{label} transcript DryRun must be False")
        record_ok = False
    if not re.search(r"(?im)^weak_validation_passed:\s*true\s*$", transcript_text):
        reasons.append(f"{label} transcript missing weak_validation_passed: true")
        record_ok = False
    if not re.search(r"(?im)^dry_run:\s*false\s*$", transcript_text):
        reasons.append(f"{label} transcript missing dry_run: false")
        record_ok = False
    if re.search(r"(?im)^Command:\s*DRY_RUN\b", transcript_text):
        reasons.append(f"{label} transcript contains a DRY_RUN command")
        record_ok = False

    transcript_classification = _classification(transcript_text, exit_code, transcript_dry_run)
    if transcript_classification != "live_transcript_ready":
        reasons.append(f"{label} transcript classification must be live_transcript_ready, got {transcript_classification}")
        record_ok = False

    eligible, evidence_class, eligibility_source = _eligibility(
        policy,
        transcript_harness,
        transcript_profile,
        transcript_model,
        transcript_dry_run,
        command,
        required_evidence_classes,
        reasons,
    )
    if not eligible:
        reasons.append(f"{label} weak evidence is not eligible: {eligibility_source}")
        record_ok = False
    if evidence_class and evidence_class != expected_evidence_class:
        reasons.append(f"{label} evidence_class must be {expected_evidence_class}")
        record_ok = False

    if summary_path:
        if not re.search(r"(?m)^- PASS exit 0:", summary_text):
            reasons.append(f"{label} summary missing live PASS exit 0 marker")
            record_ok = False
        if re.search(r"(?m)^- FAIL ", summary_text):
            reasons.append(f"{label} summary contains FAIL marker")
            record_ok = False
        if transcript_path and str(transcript_path) not in summary_text and expected_model not in summary_text:
            reasons.append(f"{label} summary does not cite its transcript or model")
            record_ok = False

    return record_ok


def validate_promotion_airgapped_evidence(
    value: Any,
    manifest_path: Path,
    policy_path: Path | str = DEFAULT_POLICY_PATH,
    required_evidence_classes: Iterable[str] | None = None,
) -> WeakEvidenceResult:
    reasons: list[str] = []
    manifest_path = Path(manifest_path)
    manifest_root = manifest_path.parent.resolve()
    allowed_roots = (manifest_root / "evidence", manifest_root / "airgapped")
    policy = load_policy(policy_path)
    weak_evidence = _weak_evidence_config(policy, reasons)
    if required_evidence_classes is None:
        required_evidence_classes = _as_list(weak_evidence.get("promotionEvidenceClasses")) or ["preferred_weak"]
    required_evidence_classes = tuple(str(item) for item in required_evidence_classes)
    expected_routes = _promotion_expected_routes(policy, required_evidence_classes, reasons)
    expected_models = tuple(route[2] for route in expected_routes)

    if not isinstance(value, dict):
        reasons.append("airgapped_validation must be an object")
        return WeakEvidenceResult(False, False, "", "weakEvidence.allow", "airgapped-validation-missing", "missing", None, "", "", "", "", "", "", tuple(reasons), expected_models, 0, len(expected_models))

    if value.get("required") is not True:
        reasons.append("airgapped_validation.required must be true")
    if value.get("status") != "passed":
        reasons.append("airgapped_validation.status must be passed")
    if value.get("exit_code") != 0:
        reasons.append("airgapped_validation.exit_code must be 0")

    dry_run = _parse_bool(value.get("dry_run"))
    if dry_run is not False:
        reasons.append("airgapped_validation.dry_run must be false")
    if value.get("weak_validation_passed") is not True:
        reasons.append("airgapped_validation.weak_validation_passed must be true")

    wrapper_path = _resolve_existing(value.get("transcript"), reasons, "airgapped_validation.transcript")
    summary_path = _resolve_existing(value.get("summary"), reasons, "airgapped_validation.summary") if value.get("summary") else None
    index_path = _resolve_existing(value.get("index"), reasons, "airgapped_validation.index")

    _require_under(wrapper_path, (manifest_root / "evidence",), reasons, "airgapped_validation.transcript")
    _require_under(summary_path, allowed_roots, reasons, "airgapped_validation.summary")
    _require_under(index_path, allowed_roots, reasons, "airgapped_validation.index")

    wrapper_text = _read_text(wrapper_path) if wrapper_path else ""
    summary_text = _read_text(summary_path) if summary_path else ""
    index = _read_index(index_path, reasons)

    actual_transcript_path = None
    actual_from_wrapper = _transcript_path_from_wrapper(wrapper_text)
    if actual_from_wrapper:
        actual_transcript_path = _resolve_existing(actual_from_wrapper, reasons, "actual weak-model transcript")
    elif wrapper_path and re.search(r"(?im)^Harness:\s*", wrapper_text):
        actual_transcript_path = wrapper_path
    else:
        reasons.append("wrapper transcript must contain the actual weak-model Transcript path")

    _require_under(actual_transcript_path, allowed_roots, reasons, "actual weak-model transcript")
    actual_text = _read_text(actual_transcript_path) if actual_transcript_path else ""

    combined_text = "\n".join(part for part in (wrapper_text, summary_text, actual_text) if part)
    command = _field(actual_text, "Command")
    exit_code_text = _field(actual_text, "ExitCode")
    try:
        exit_code = int(exit_code_text) if exit_code_text else None
    except ValueError:
        exit_code = None
    harness = _field(actual_text, "Harness") or _field(summary_text, "Harness")
    profile = _field(actual_text, "Profile") or _field(summary_text, "Profile")
    model = _field(actual_text, "Model") or _model_from_transcript_path(actual_transcript_path) if actual_transcript_path else ""
    if not model:
        model = _first_summary_model(summary_text)
    transcript_dry_run = _parse_bool(_field(actual_text, "DryRun"))
    summary_dry_run = _parse_bool(_field(summary_text, "DryRun"))
    effective_dry_run = transcript_dry_run if transcript_dry_run is not None else dry_run

    if not command:
        reasons.append("actual weak-model transcript missing Command header")
    if exit_code != 0:
        reasons.append("actual weak-model transcript ExitCode must be 0")
    if harness != "claude-copilot":
        reasons.append("actual weak-model transcript Harness must be claude-copilot")
    if profile != "airgapped":
        reasons.append("actual weak-model transcript Profile must be airgapped")
    if not model:
        reasons.append("actual weak-model transcript Model is missing")
    if transcript_dry_run is not False:
        reasons.append("actual weak-model transcript DryRun must be False")
    if summary_dry_run is not False:
        reasons.append("airgapped summary DryRun must be False")
    if _parse_bool(_field(summary_text, "Airgapped")) is not True:
        reasons.append("airgapped summary Airgapped must be True")
    if re.search(r"(?im)^Command:\s*DRY_RUN\b", actual_text) or re.search(r"(?im)^Command:\s*DRY_RUN\b", wrapper_text):
        reasons.append("airgapped evidence contains a DRY_RUN command")
    if not re.search(r"(?m)^- PASS exit 0:", summary_text):
        reasons.append("airgapped summary missing live PASS exit 0 marker")
    if re.search(r"(?m)^- FAIL ", summary_text):
        reasons.append("airgapped summary contains FAIL marker")
    if expected_models:
        summary_models_line = _field(summary_text, "Models")
        summary_models = [model.strip() for model in summary_models_line.split(",") if model.strip()]
        missing_summary_models = sorted(set(expected_models) - set(summary_models))
        if missing_summary_models:
            reasons.append(f"airgapped summary missing preferred weak model(s): {', '.join(missing_summary_models)}")
    if not re.search(r"(?im)^weak_validation_passed:\s*true\s*$", actual_text):
        reasons.append("actual weak-model transcript missing weak_validation_passed: true")
    if not re.search(r"(?im)^dry_run:\s*false\s*$", actual_text):
        reasons.append("actual weak-model transcript missing dry_run: false")

    classification = _classification(combined_text, exit_code, effective_dry_run)
    if classification != "live_transcript_ready":
        reasons.append(f"actual weak-model transcript classification must be live_transcript_ready, got {classification}")

    eligible, evidence_class, eligibility_source = _eligibility(
        policy,
        harness,
        profile,
        model,
        effective_dry_run,
        command,
        required_evidence_classes,
        reasons,
    )
    not_weak_reason = "" if eligible else eligibility_source
    if not eligible:
        reasons.append(f"weak evidence is not eligible: {not_weak_reason}")

    attempted_model_count = 0
    missing_attempt_count = 0
    if expected_routes:
        records = index.get("records") if isinstance(index, dict) else None
        if not isinstance(records, list):
            reasons.append("airgapped validation index records must be a list")
            records = []

        records_by_route: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
        for record in records:
            if not isinstance(record, dict):
                reasons.append("airgapped validation index records must be objects")
                continue
            record_key = (
                str(record.get("harness") or ""),
                str(record.get("profile") or ""),
                str(record.get("model") or ""),
            )
            records_by_route.setdefault(record_key, []).append(record)

        for expected_harness, expected_profile, expected_model, expected_evidence_class in expected_routes:
            key = (expected_harness, expected_profile, expected_model)
            matching_records = records_by_route.get(key) or []
            if not matching_records:
                missing_attempt_count += 1
                reasons.append(f"airgapped validation index missing preferred weak model attempts: {expected_model}")
                continue
            attempted_model_count += 1
            if len(matching_records) > 1:
                reasons.append(f"airgapped validation index has duplicate preferred weak model attempts: {expected_model}")
                continue
            _validate_index_record(
                matching_records[0],
                expected_harness,
                expected_profile,
                expected_model,
                expected_evidence_class,
                policy,
                required_evidence_classes,
                allowed_roots,
                reasons,
            )

    passed = not reasons and eligible
    return WeakEvidenceResult(
        weak_validation_eligible=eligible,
        weak_validation_passed=passed,
        evidence_class=evidence_class,
        eligibility_source=eligibility_source,
        not_weak_reason=not_weak_reason,
        classification=classification,
        dry_run=effective_dry_run,
        harness=harness,
        profile=profile,
        model=model,
        transcript=str(wrapper_path or ""),
        actual_transcript=str(actual_transcript_path or ""),
        summary=str(summary_path or ""),
        reasons=tuple(reasons),
        expected_models=expected_models,
        attempted_model_count=attempted_model_count,
        missing_attempt_count=missing_attempt_count,
    )


def format_reasons(result: WeakEvidenceResult) -> str:
    return "; ".join(result.reasons) if result.reasons else ""
