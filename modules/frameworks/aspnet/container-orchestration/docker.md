# Docker with ASP.NET

> Extends `modules/container-orchestration/docker.md` with ASP.NET Core containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY *.sln ./
COPY src/*/*.csproj ./
RUN for f in *.csproj; do mkdir -p "src/${f%.csproj}" && mv "$f" "src/${f%.csproj}/"; done
RUN dotnet restore

COPY src/ ./src/
RUN dotnet publish src/MyApp.Api/MyApp.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app

RUN addgroup --system app && adduser --system --group app

COPY --from=build /app/publish .

USER app:app

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["dotnet", "MyApp.Api.dll"]
```

Copy csproj files first for layer caching -- dependency restore is cached independently from code changes.

## Framework-Specific Patterns

### ASP.NET Health Checks

```csharp
// Program.cs
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>();

app.MapHealthChecks("/health");
```

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
```

### Kestrel Configuration

```dockerfile
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_EnableDiagnostics=0
```

Set `DOTNET_EnableDiagnostics=0` to disable diagnostic pipes in production containers -- reduces attack surface.

### Self-Contained Deployment

```dockerfile
RUN dotnet publish -c Release -o /app/publish --self-contained -r linux-x64 \
    /p:PublishTrimmed=true /p:PublishSingleFile=true

FROM mcr.microsoft.com/dotnet/runtime-deps:9.0
```

Self-contained with trimming produces a single executable without the .NET runtime. Use `runtime-deps` base image (smallest).

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO copy csproj files first for dependency layer caching
- DO use `dotnet publish` with `-c Release` for production images
- DO set `DOTNET_EnableDiagnostics=0` in production containers
- DO use `mcr.microsoft.com/dotnet/aspnet` for framework-dependent, `runtime-deps` for self-contained

## Additional Don'ts

- DON'T include the SDK image in the runtime stage
- DON'T use `dotnet run` in production -- use `dotnet MyApp.dll` or the published executable
- DON'T run as root -- create an `app` user
- DON'T copy test projects into the runtime image
