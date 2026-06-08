#!/usr/bin/env python3
import json
import sys
from pathlib import Path


root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\generated-tests")
out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tmp\zappa-dont-cry\coverage")

canonical_questions = {
    "behavior": "What behavior must be proven?",
    "boundary": "What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?",
    "docs_schema_evidence": "What public docs/schema path proves the capability exists?",
    "inputs_outputs_side_effects": "What inputs, outputs, and side effects prove success?",
    "negative_cases": "Which negative, malformed, outage, retry, cleanup, and observability cases matter?",
    "dependencies": "Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?",
    "runnability": "What can run now, and what must be deferred?",
}
allowed_answer_sources = {"public_docs", "public_repo_contract", "assumption", "blocked"}
required_fields = (
    "question_id",
    "question",
    "self_answer",
    "answer_source",
    "risk_if_wrong",
    "how_to_override",
    "public_evidence",
)

failures: list[str] = []
manifest_count = 0
question_count = 0
blocked_answer_count = 0
source_counts = {source: 0 for source in allowed_answer_sources}

for manifest_path in sorted(root.rglob("qaas-artifact-manifest.json")):
    manifest_count += 1
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        failures.append(f"manifest parse failed: {manifest_path}: {exc}")
        continue

    questions = manifest.get("intent_questions")
    if not isinstance(questions, list) or not questions:
        failures.append(f"intent_questions missing or empty: {manifest_path}")
        continue

    seen_ids: set[str] = set()
    for index, question in enumerate(questions):
        question_count += 1
        if not isinstance(question, dict):
            failures.append(f"intent_questions[{index}] must be an object: {manifest_path}")
            continue
        for field in required_fields:
            if field not in question:
                failures.append(f"intent_questions[{index}] missing {field}: {manifest_path}")

        question_id = question.get("question_id")
        if not isinstance(question_id, str) or question_id not in canonical_questions:
            failures.append(f"intent_questions[{index}] has invalid question_id {question_id!r}: {manifest_path}")
        else:
            if question_id in seen_ids:
                failures.append(f"duplicate intent question_id {question_id}: {manifest_path}")
            seen_ids.add(question_id)
            expected_question = canonical_questions[question_id]
            if question.get("question") != expected_question:
                failures.append(f"intent question text mismatch for {question_id}: {manifest_path}")

        for field in ("question", "self_answer", "risk_if_wrong", "how_to_override"):
            value = question.get(field)
            if not isinstance(value, str) or not value.strip():
                failures.append(f"intent_questions[{index}] has empty {field}: {manifest_path}")

        source = question.get("answer_source")
        if source not in allowed_answer_sources:
            failures.append(f"intent_questions[{index}] invalid answer_source {source!r}: {manifest_path}")
        else:
            source_counts[source] += 1
            if source == "blocked":
                blocked_answer_count += 1

        evidence = question.get("public_evidence")
        if not isinstance(evidence, list) or not evidence:
            failures.append(f"intent_questions[{index}] missing non-empty public_evidence: {manifest_path}")
        else:
            for evidence_index, item in enumerate(evidence):
                if not isinstance(item, str) or not item.strip():
                    failures.append(
                        f"intent_questions[{index}].public_evidence[{evidence_index}] is not a non-empty string: {manifest_path}"
                    )

    missing_ids = sorted(set(canonical_questions) - seen_ids)
    if missing_ids:
        failures.append(f"manifest missing canonical intent question IDs {missing_ids}: {manifest_path}")

    if manifest.get("promotion_state") == "blocked":
        blocked_or_assumption = [
            item
            for item in questions
            if isinstance(item, dict) and item.get("answer_source") in {"blocked", "assumption"}
        ]
        if len(blocked_or_assumption) < 3:
            failures.append(f"blocked manifest lacks enough blocked/assumption intent answers: {manifest_path}")

if manifest_count == 0:
    failures.append(f"no manifests found under {root}")

out_dir.mkdir(parents=True, exist_ok=True)
record_path = out_dir / "intent-clarification-coverage.json"
record = {
    "schema_version": 1,
    "manifest_count": manifest_count,
    "intent_question_count": question_count,
    "canonical_question_count": len(canonical_questions),
    "expected_question_count": manifest_count * len(canonical_questions),
    "blocked_answer_count": blocked_answer_count,
    "answer_source_counts": dict(sorted(source_counts.items())),
}
record_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(
    f"Intent clarification coverage check passed for {manifest_count} manifests "
    f"and {question_count} self-answered questions."
)
print(f"Record: {record_path}")
