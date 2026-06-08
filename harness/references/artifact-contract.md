# QaaS Artifact Contract

Every generated QaaS test campaign must include a manifest named `qaas-artifact-manifest.json`.

Manifest fields:

- `campaign_id`
- `source_repository`
- `docs_evidence`
- `intent_questions`
- `intent_assumptions`
- `artifacts`
- `cases`
- `assertions`
- `dependency_gates`
- `cleanup`
- `validation_sequence`
- `airgapped_validation`
- `source_only_blockers`

`source_repository` is the public evidence origin for the campaign. For QaaS docs coverage campaigns, use the canonical public docs repository identifier, such as `qaas-docs`, and keep `source_document` as additional page-level detail.

`intent_questions` is required on every manifest. It records the self-answered clarification questions used when a user request is vague or questions are forbidden. Every manifest must cover these `question_id` values: `behavior`, `boundary`, `docs_schema_evidence`, `inputs_outputs_side_effects`, `negative_cases`, `dependencies`, and `runnability`.

`source_only_blockers` is required on every manifest. It may be empty only when the manifest is not blocked. Any manifest with `promotion_state: blocked` or a blocked `status` must include at least one structured blocker.

Each `intent_questions` entry must include:

- `question_id`: one of the canonical question IDs above
- `question`: non-empty string
- `self_answer`: non-empty string
- `answer_source`: `public_docs`, `public_repo_contract`, `assumption`, or `blocked`
- `risk_if_wrong`: non-empty string
- `how_to_override`: non-empty string
- `public_evidence`: non-empty list of non-empty strings

Each case must include:

- `case_id`
- `scenario`
- `artifact_type`: `runner-yaml`, `runner-code`, `mocker-yaml`, `mocker-code`, `hook`, `config-as-code`, `dependency-gate`, or `documentation`
- `public_evidence`
- `setup`
- `action`
- `assertions`
- `cleanup`
- `blocked_reason`
- `artifact_paths`

Minimum validation sequence:

1. Docs/schema evidence check.
2. Static artifact shape check.
3. QaaS `template` check when a runnable host exists.
4. Build check for C# hooks or configuration-as-code.
5. Live `run`, `act`, or `assert` only after dependency gates are ready.
6. Promotion packet generation only after executable artifacts have passed template, build, live, airgapped, and per-manifest strong-review evidence gates.

Never make "runs successfully" the only assertion.

Promotion packet rules:

- `D:\QaaS\_tmp\zappa-dont-cry\coverage\promotion-packet-summary.json` records whether any executable packet exists.
- `D:\QaaS\_tmp\zappa-dont-cry\promotion-packets` may contain packet JSON files only for manifests with `promotion_state: executable`.
- If the promotion candidate index has `promotable_candidate_count: 0`, the packet summary must pass structurally with `promotion_packet_status: blocked` and `packet_count: 0`.
- No packet may be emitted for blocked skeletons.
- A packet requires non-empty `docs_evidence` and `intent_questions`, empty `source_only_blockers`, all required dependency gates passed, no placeholder markers in YAML/C# artifacts, and existing transcript paths for template, build, live, and airgapped validation.
- Blocked selected-repository candidate packets must stay outside `promotion-packets`, use `promotion_state: blocked`, and preserve lifecycle/template/live/airgapped blockers until executable evidence exists.

Each `source_only_blockers` entry must include:

- `blocker_id`: non-empty string
- `blocker_type`: one of `source_boundary`, `repository_contract`, `repository_or_component_contract`, `component_contract`, or `qaas_docs_contract`
- `description`: non-empty string
- `required_evidence`: non-empty list of non-empty strings
- `public_evidence`: non-empty list of non-empty strings
- `unblock_instruction`: non-empty string
