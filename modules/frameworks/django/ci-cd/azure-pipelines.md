# Azure Pipelines with Django

> Extends `modules/ci-cd/azure-pipelines.md` with Django CI patterns.
> Generic Azure Pipelines conventions (stages, tasks, variable groups) are NOT repeated here.

## Integration Setup

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include: [main]

pool:
  vmImage: ubuntu-latest

variables:
  DJANGO_SETTINGS_MODULE: config.settings.test

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

          - script: |
              uv run python manage.py migrate
              uv run python manage.py makemigrations --check --dry-run
            displayName: Verify migrations
            env:
              DATABASE_URL: postgresql://test:test@localhost:5432/test

          - script: uv run python manage.py collectstatic --noinput
            displayName: Collect static files

          - script: uv run pytest --cov --junitxml=report.xml
            displayName: Test
            env:
              DATABASE_URL: postgresql://test:test@localhost:5432/test

          - task: PublishTestResults@2
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: report.xml
```

## Framework-Specific Patterns

### Django Deploy Check

```yaml
- script: uv run python manage.py check --deploy
  displayName: Django deploy checks
  env:
    DJANGO_SETTINGS_MODULE: config.settings.production
    SECRET_KEY: ci-dummy-key
    DATABASE_URL: postgresql://test:test@localhost:5432/test
```

### Docker Image Publishing

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

- DO set `DJANGO_SETTINGS_MODULE` as a pipeline-level variable
- DO use `PublishTestResults@2` for Azure test result integration
- DO run `manage.py check --deploy` against production settings
- DO verify migrations with `makemigrations --check --dry-run`

## Additional Don'ts

- DON'T use production `SECRET_KEY` in CI -- use a dummy value
- DON'T skip `collectstatic` -- broken static file pipelines cause runtime errors
- DON'T run all steps without `displayName` -- pipeline logs become unreadable
