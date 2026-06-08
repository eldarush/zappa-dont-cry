#!/usr/bin/env python3
import re
import subprocess
import sys
from pathlib import Path

import yaml


skill_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Users\eldar\.codex\skills\zappa-dont-cry")
quick_validate = Path(r"C:\Users\eldar\.codex\skills\.system\skill-creator\scripts\quick_validate.py")
failures = []
names = {}

for skill_md in sorted(skill_root.glob("*/SKILL.md")):
    folder = skill_md.parent.name
    text = skill_md.read_text(encoding="utf-8")
    if "TODO" in text or "Replace with" in text or "[TODO" in text:
        failures.append(f"template text remains: {skill_md}")

    match = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not match:
        failures.append(f"missing frontmatter: {skill_md}")
        continue

    try:
        meta = yaml.safe_load(match.group(1))
    except Exception as exc:
        failures.append(f"frontmatter parse failed: {skill_md}: {exc}")
        continue

    if not isinstance(meta, dict):
        failures.append(f"frontmatter is not a mapping: {skill_md}")
        continue

    name = meta.get("name")
    description = meta.get("description")
    if not isinstance(name, str):
        failures.append(f"name is not a string: {skill_md}")
    elif name != folder:
        failures.append(f"folder/name mismatch: folder={folder} name={name}")
    elif name in names:
        failures.append(f"duplicate skill name: {name} in {skill_md} and {names[name]}")
    else:
        names[name] = str(skill_md)

    if not isinstance(description, str):
        failures.append(f"description is not a string: {skill_md}")
    elif len(description.strip()) < 40:
        failures.append(f"description too short: {skill_md}")
    elif "Complete and informative" in description or "TODO" in description:
        failures.append(f"description placeholder remains: {skill_md}")

    if quick_validate.exists():
        result = subprocess.run([sys.executable, str(quick_validate), str(skill_md.parent)], capture_output=True, text=True)
        if result.returncode != 0:
            failures.append(f"quick_validate failed: {skill_md.parent}: {result.stdout} {result.stderr}")

if not names:
    failures.append(f"no skill metadata found under {skill_root}")

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Skill metadata check passed for {len(names)} skills.")
