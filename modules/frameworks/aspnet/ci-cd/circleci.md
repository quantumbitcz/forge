# CircleCI with ASP.NET

> Extends `modules/ci-cd/circleci.md` with ASP.NET Core CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

jobs:
  build-and-test:
    docker:
      - image: mcr.microsoft.com/dotnet/sdk:9.0
    steps:
      - checkout
      - restore_cache:
          keys:
            - nuget-{{ checksum "**/*.csproj" }}
      - run: dotnet restore
      - save_cache:
          key: nuget-{{ checksum "**/*.csproj" }}
          paths:
            - ~/.nuget/packages
      - run: dotnet build --no-restore -c Release
      - run: dotnet test --no-build -c Release --logger "trx;LogFileName=results.trx"
      - store_test_results:
          path: .

workflows:
  ci:
    jobs:
      - build-and-test
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO cache `~/.nuget/packages` keyed by csproj file checksums
- DO use `store_test_results` for CircleCI test insights
- DO build in Release configuration
- DO use the .NET SDK Docker image

## Additional Don'ts

- DON'T use `machine` executor for .NET builds -- `docker` executor starts faster
- DON'T cache `bin/` or `obj/` directories
- DON'T skip NuGet restore caching
