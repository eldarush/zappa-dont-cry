# Plan

Status: SCOPED

Rules:

- READ must happen before PATCH.
- RUN_TESTS must use a command_id from commands.json, not raw shell.
- REPORT must cite evidence paths.
- END must state blockers and whether weak_validation_passed is still false.

Steps:

1. READ task.md, state.json, and commands.json.
2. READ public QaaS docs/schema evidence for the task.
3. PLAN the smallest QaaS artifact or fix with hard assertions and dependency gates.
4. PATCH only the files needed for the task.
5. RUN_TESTS harness_skill_output_contracts for skill/output-shape work or the narrowest relevant command ID.
6. RUN_TESTS airgapped_all only when live weak evidence is required and quota is available.
7. REPORT changed files, commands, evidence paths, risks, and blockers.
8. END with completion_decision: blocked unless template/build/live/eligible weak validation and strong review are all proven.