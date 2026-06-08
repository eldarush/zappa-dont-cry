# QaaS Docs Index

Use public documentation and generated schemas as the contract.

Primary roots:

- `D:\QaaS\qaas-docs\docs`
- `D:\QaaS\qaas-docs\docs\_generated\schemas`
- `D:\QaaS\qaas-docs\tools\QaaS.Docs.Generator\Snapshots`

Generated schema pages:

- `docs\_generated\schemas\assertions.md`
- `docs\_generated\schemas\generators.md`
- `docs\_generated\schemas\probes.md`
- `docs\_generated\schemas\processors.md`

Runner and Mocker discovery:

- Search docs with `rg -n "Runner|Mocker|template|run|act|assert|configuration|YAML|hook" D:\QaaS\qaas-docs\docs`.
- Search generated schemas with `rg -n "<field-or-hook-name>" D:\QaaS\qaas-docs\docs\_generated\schemas`.
- Search CLI snapshots with `rg -n "<command-or-flag>" D:\QaaS\qaas-docs\tools\QaaS.Docs.Generator\Snapshots`.

Evidence rule:

- A QaaS behavior is usable only when a docs page, generated schema, generated snapshot, or provided user artifact proves it.
- Source-only findings must be marked `source_only` and cannot be presented as public capability.
- If docs evidence is missing, provide a documented fallback or a blocker.
