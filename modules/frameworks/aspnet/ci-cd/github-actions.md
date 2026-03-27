# GitHub Actions with ASP.NET

> Extends `modules/ci-cd/github-actions.md` with ASP.NET Core CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: 9.0.x
          cache: true
          cache-dependency-path: '**/packages.lock.json'

      - run: dotnet restore
      - run: dotnet build --no-restore
      - run: dotnet test --no-build --collect:"XPlat Code Coverage" --logger trx
```

## Framework-Specific Patterns

### NuGet Caching

```yaml
- uses: actions/setup-dotnet@v4
  with:
    dotnet-version: 9.0.x
    cache: true
    cache-dependency-path: '**/packages.lock.json'
```

Enable NuGet caching via `actions/setup-dotnet`. Use `packages.lock.json` for deterministic restores (`RestorePackagesWithLockFile` in csproj).

### Test Results Publishing

```yaml
- run: dotnet test --no-build --logger "trx;LogFileName=test-results.trx" --collect:"XPlat Code Coverage"
- uses: dorny/test-reporter@v1
  if: always()
  with:
    name: Test Results
    path: '**/test-results.trx'
    reporter: dotnet-trx
```

### Docker Image Publishing

```yaml
publish:
  needs: build
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO use `actions/setup-dotnet` with `cache: true` for NuGet caching
- DO enable `RestorePackagesWithLockFile` for deterministic restores
- DO collect code coverage with `XPlat Code Coverage`
- DO use `dorny/test-reporter` for GitHub PR test result annotations

## Additional Don'ts

- DON'T cache the entire `~/.nuget` directory manually when using `setup-dotnet` caching
- DON'T skip `--no-build` on `dotnet test` after a successful `dotnet build`
- DON'T run `dotnet restore` without a lockfile in CI
