# QaaS Runner Project

This project was created from the `ZappaPromotionSeed.Runner` dotnet template pack.

## Included Defaults

- `NuGet.config` defaults restores to `nuget.org`
- `Program.cs` runs `QaaS.Runner.Bootstrap.New(args).Run()`
- `test.qaas.yaml` contains only placeholder metadata and one minimal session
- Rider launch settings use `run test.qaas.yaml`

## First Run

```bash
dotnet restore --configfile NuGet.config
dotnet run --project ZappaPromotionSeed.Runner/ZappaPromotionSeed.Runner.csproj -- run test.qaas.yaml
```

Replace the placeholder metadata and expand the session before using the project for real workloads.
