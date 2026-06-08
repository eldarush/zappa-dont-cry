# QaaS Mocker Project

This project was created from the `ZappaPromotionSeed.Mocker` dotnet template pack.

## Included Defaults

- `Program.cs` runs `QaaS.Mocker.Bootstrap.New(args).Run()`
- `NuGet.config` defaults restores to `nuget.org`
- `mocker.qaas.yaml` includes a minimal local `/health` mock on `http://127.0.0.1:8080`
- `Processors/HealthProcessor.cs` returns the default plain-text health payload
- `Dockerfile`, `NuGet.config`, and `.github/workflows/ci.yml` are included

## First Run

```bash
dotnet restore --configfile NuGet.config
dotnet run --project ZappaPromotionSeed.Mocker/ZappaPromotionSeed.Mocker.csproj -- run mocker.qaas.yaml
curl http://127.0.0.1:8080/health
```

Use this as a starting point for your own stubs and endpoints. For example, you can lint the file before expanding it:

```bash
dotnet run --project ZappaPromotionSeed.Mocker/ZappaPromotionSeed.Mocker.csproj -- -m Lint mocker.qaas.yaml
```

If you restore from a private feed or local Artifactory, update `NuGet.config` before the first restore.
