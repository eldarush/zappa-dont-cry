# Recursive Development Loop

Use this loop when improving zappa-dont-cry.

1. Strong model drafts or patches a skill.
2. Validate skill syntax with `scripts/validate-zappa-pack.ps1`.
3. Run weak airgapped validation with `scripts/run-airgapped-validation.ps1`.
4. Strong model reviews the weak transcript against QaaS docs evidence.
5. Patch the skill to fix ambiguity.
6. Repeat until the weak transcript follows the skill without unsupported QaaS claims.

For top GitHub repositories:

1. Fetch current repository list with `scripts/fetch-top-github-repos.ps1 -Count 250`.
2. Create a campaign manifest under `D:\QaaS\_tmp\zappa-dont-cry\top-repos`.
3. Plan docs-only QaaS test coverage per repository category.
4. Generate YAML/code only when public docs and repo-visible contracts are enough.
5. Mark missing runtime knowledge as blockers rather than inventing tests.

Do not claim all 250 repositories are fully tested until every repository has executable artifacts, manifests, dependency gates, validation transcripts, and result evidence.

For QaaS functionality coverage:

1. Build the docs coverage inventory with `scripts/build-qaas-docs-coverage.ps1`.
2. Generate docs-only YAML/C# skeletons with `scripts/generate-qaas-coverage-skeletons.ps1`.
3. Treat every skeleton as blocked until a public component/repository contract fills the placeholders.
4. Promote a skeleton to executable only after template/build/live validation evidence exists.
