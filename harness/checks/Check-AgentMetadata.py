#!/usr/bin/env python3
import sys
from pathlib import Path

import yaml


skill_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Users\eldar\.codex\skills\zappa-dont-cry")
failures = []
count = 0

for skill_dir in sorted(p for p in skill_root.iterdir() if p.is_dir()):
    if not (skill_dir / "SKILL.md").exists():
        continue

    agent_yaml = skill_dir / "agents" / "openai.yaml"
    if not agent_yaml.exists():
        failures.append(f"missing agents/openai.yaml: {skill_dir}")
        continue

    data = yaml.safe_load(agent_yaml.read_text(encoding="utf-8"))
    interface = data.get("interface") if isinstance(data, dict) else None
    if not isinstance(interface, dict):
        failures.append(f"missing interface mapping: {agent_yaml}")
        continue

    for key in ("display_name", "short_description", "default_prompt"):
        value = interface.get(key)
        if not isinstance(value, str) or not value.strip():
            failures.append(f"{key} missing or not a string: {agent_yaml}")

    prompt = interface.get("default_prompt", "")
    if prompt.strip().lower() in {"use this qaas skill.", "use this skill."}:
        failures.append(f"generic default_prompt: {agent_yaml}")

    count += 1

if failures:
    for failure in failures:
        print(f"ERROR: {failure}", file=sys.stderr)
    sys.exit(1)

print(f"Agent metadata check passed for {count} skills.")
