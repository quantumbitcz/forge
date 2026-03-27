# Bitbucket Pipelines with ASP.NET

> Extends `modules/ci-cd/bitbucket-pipelines.md` with ASP.NET Core CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: mcr.microsoft.com/dotnet/sdk:9.0

definitions:
  caches:
    nuget: ~/.nuget/packages

pipelines:
  default:
    - step:
        name: Build and Test
        caches:
          - nuget
        script:
          - dotnet restore
          - dotnet build --no-restore -c Release
          - dotnet test --no-build -c Release --logger "trx;LogFileName=results.trx"
```

## Framework-Specific Patterns

### Docker Image Publishing

```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build and Push Image
          services:
            - docker
          script:
            - docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
            - docker build -t $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT .
            - docker push $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "bitbucket-pipelines.yml"
```

## Additional Dos

- DO define a custom `nuget` cache pointing to `~/.nuget/packages`
- DO build in Release configuration
- DO use `dotnet test --logger trx` for test results
- DO use the .NET SDK Docker image

## Additional Don'ts

- DON'T cache `bin/` or `obj/` directories
- DON'T use Debug configuration in CI
- DON'T skip NuGet caching -- .NET restores can be slow
