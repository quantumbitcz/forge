# Azure Pipelines with FastAPI

> Extends `modules/ci-cd/azure-pipelines.md` with FastAPI CI patterns.
> Generic Azure Pipelines conventions (stages, tasks, variable groups) are NOT repeated here.

## Integration Setup

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include: [main]

pool:
  vmImage: ubuntu-latest

stages:
  - stage: Test
    jobs:
      - job: TestAndLint
        services:
          postgres:
            image: postgres:16-alpine
            ports:
              - 5432:5432
            env:
              POSTGRES_DB: test
              POSTGRES_USER: test
              POSTGRES_PASSWORD: test
        steps:
          - task: UsePythonVersion@0
            inputs:
              versionSpec: '3.12'

          - script: pip install uv && uv sync
            displayName: Install dependencies

          - script: uv run ruff check .
            displayName: Lint

          - script: uv run pytest --cov=app --junitxml=report.xml
            displayName: Test
            env:
              DATABASE_URL: postgresql://test:test@localhost:5432/test

          - task: PublishTestResults@2
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: report.xml
```

## Framework-Specific Patterns

### uv Caching

```yaml
- task: Cache@2
  inputs:
    key: 'uv | "$(Agent.OS)" | uv.lock'
    restoreKeys: |
      uv | "$(Agent.OS)"
    path: $(Pipeline.Workspace)/.cache/uv
```

### Alembic Migration Verification

```yaml
- script: |
    uv run alembic upgrade head
    uv run alembic check
  displayName: Verify migrations
  env:
    DATABASE_URL: postgresql://test:test@localhost:5432/test
```

### Multi-Stage Docker Publish

```yaml
- stage: Publish
  dependsOn: Test
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
    - job: PublishImage
      steps:
        - task: Docker@2
          inputs:
            containerRegistry: $(dockerRegistryServiceConnection)
            repository: $(imageRepository)
            command: buildAndPush
            Dockerfile: Dockerfile
            tags: $(Build.SourceVersion)
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "azure-pipelines.yml"
```

## Additional Dos

- DO use `PublishTestResults@2` for Azure test result integration
- DO use `Cache@2` task for uv dependency caching
- DO use service containers for PostgreSQL in test jobs
- DO verify Alembic migrations with `alembic check` before merge

## Additional Don'ts

- DON'T use `script` tasks without `displayName` -- pipeline logs become unreadable
- DON'T skip caching for uv -- Python dependency resolution is slow without it
- DON'T run `alembic upgrade head` in production pipelines without migration review
