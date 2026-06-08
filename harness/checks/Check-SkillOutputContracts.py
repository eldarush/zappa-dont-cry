#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


skill_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Users\eldar\.codex\skills\zappa-dont-cry")
fixture_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(r"D:\QaaS\_tools\zappa-harness\fixtures\skill-output-contracts.json")


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.lower())


failures: list[str] = []

if not fixture_path.exists():
    failures.append(f"missing fixture: {fixture_path}")
else:
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    if fixture.get("schema_version") != 1:
        failures.append("skill output contract fixture must have schema_version 1")

    contracts = fixture.get("contracts", [])
    if len(contracts) != 11:
        failures.append(f"expected 11 skill output contracts, found {len(contracts)}")

    seen: set[str] = set()
    for contract in contracts:
        skill = contract.get("skill")
        if not skill:
            failures.append("contract missing skill")
            continue
        if skill in seen:
            failures.append(f"duplicate contract for skill: {skill}")
        seen.add(skill)

        skill_md = skill_root / skill / "SKILL.md"
        if not skill_md.exists():
            failures.append(f"contract references missing skill: {skill}")
            continue

        text = normalize(skill_md.read_text(encoding="utf-8"))
        if "required output" not in text and "required output shape" not in text and "output contract" not in text:
            failures.append(f"{skill} missing explicit output section")

        for term in contract.get("required_output_terms", []):
            if not isinstance(term, str) or not term.strip():
                failures.append(f"{skill} has empty required_output_terms entry")
                continue
            if normalize(term) not in text:
                failures.append(f"{skill} output contract missing term: {term}")
        for group_index, group in enumerate(contract.get("required_any_output_term_groups", [])):
            if not isinstance(group, list) or not group:
                failures.append(f"{skill} has empty required_any_output_term_groups[{group_index}]")
                continue
            for term in group:
                if not isinstance(term, str) or not term.strip():
                    failures.append(f"{skill} has empty required_any_output_term_groups[{group_index}] entry")
                    continue
                if normalize(term) not in text:
                    failures.append(f"{skill} any-output contract group missing term: {term}")

    installed = {path.parent.name for path in skill_root.glob("*/SKILL.md")}
    missing_contracts = installed - seen
    extra_contracts = seen - installed
    if missing_contracts:
        failures.append(f"installed skills missing output contracts: {sorted(missing_contracts)}")
    if extra_contracts:
        failures.append(f"contracts for non-installed skills: {sorted(extra_contracts)}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print("Skill output contract check passed for 11 skills.")
