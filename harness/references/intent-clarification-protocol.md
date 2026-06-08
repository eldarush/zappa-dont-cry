# Intent Clarification Protocol

Assume the user may not know which QaaS artifact they need. Convert vague intent into constrained choices.

Ask or self-answer these in order:

1. What behavior must be proven?
2. What is the system boundary: Runner target, Mocker dependency, hook host, or configuration-as-code?
3. What public docs/schema path proves the capability exists?
4. What inputs, outputs, and side effects prove success?
5. Which negative, malformed, outage, retry, cleanup, and observability cases matter?
6. Which dependencies must exist: broker, HTTP endpoint, database, Redis, S3, Kubernetes, filesystem, credentials, ports?
7. What can run now, and what must be deferred?

When the user forbids questions:

- Produce `intent_assumptions`.
- For each assumption, include `why_safe`, `risk_if_wrong`, and `how_to_override`.
- Validate the assumptions with an airgapped dry run when possible.

Do not use insulting wording in outputs. Be direct and concrete.
