#!/usr/bin/env python3
import sys
from pathlib import Path


skill_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Users\eldar\.codex\skills\zappa-dont-cry")

requirements = {
    "intent handling": ("intent_questions", "intent_assumptions"),
    "public docs only": ("public qaas docs", "docs/schema evidence", "docs-only"),
    "source-code boundary": ("unless the user explicitly provides source code", "source code as unavailable", "do not use qaas source"),
    "anti-invention": ("do not invent",),
    "harness validation": (r"d:\qaas\_tools\zappa-harness\invoke-zappaharness.ps1",),
    "airgapped validation": (r"d:\qaas\_tools\weak-model-session.ps1 -airgapped",),
    "dry-run caveat": ("dry runs as prompt assembly only", "dry validation", "dry run"),
}

failures = []
count = 0

for skill_md in sorted(skill_root.glob("*/SKILL.md")):
    count += 1
    text = skill_md.read_text(encoding="utf-8").lower()
    for label, needles in requirements.items():
        if not any(needle.lower() in text for needle in needles):
            failures.append(f"{skill_md.parent.name} missing {label}")

    if "required output" not in text and "output contract" not in text:
        failures.append(f"{skill_md.parent.name} missing required output section")

    if "hard rules" not in text and "rejection rules" not in text:
        failures.append(f"{skill_md.parent.name} missing hard/rejection rules")

if count == 0:
    failures.append(f"no skills found under {skill_root}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Skill quality check passed for {count} skills.")
