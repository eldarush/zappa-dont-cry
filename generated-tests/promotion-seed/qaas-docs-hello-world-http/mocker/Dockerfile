FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore ZappaPromotionSeed.Mocker.sln --configfile NuGet.config
RUN dotnet publish ZappaPromotionSeed.Mocker/ZappaPromotionSeed.Mocker.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/runtime:10.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "ZappaPromotionSeed.Mocker.dll", "mocker.qaas.yaml"]
