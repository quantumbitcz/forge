# Azure Pipelines with NestJS

> Extends `modules/ci-cd/azure-pipelines.md` with NestJS CI patterns.
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
  - stage: Build
    jobs:
      - job: BuildAndTest
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '22.x'

          - task: Cache@2
            inputs:
              key: 'npm | "$(Agent.OS)" | package-lock.json'
              path: $(npm_config_cache)

          - script: npm ci
            displayName: Install dependencies

          - script: npm run lint
            displayName: Lint

          - script: npm run build
            displayName: Build

          - script: npm test -- --coverage
            displayName: Unit tests

          - task: PublishTestResults@2
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: '**/junit.xml'
```

## Framework-Specific Patterns

### Swagger Spec as Artifact

```yaml
- script: node dist/swagger-cli.js > openapi.json
  displayName: Generate OpenAPI spec

- publish: openapi.json
  artifact: openapi-spec
```

### Docker Image Publishing

```yaml
- stage: Publish
  dependsOn: Build
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

- DO run `nest build` to catch compilation errors before tests
- DO generate and publish OpenAPI specs as pipeline artifacts
- DO use `PublishTestResults@2` for test result integration
- DO use `Cache@2` for npm dependency caching

## Additional Don'ts

- DON'T skip the build stage -- NestJS decorators are validated at compile time
- DON'T use `script` tasks without `displayName`
- DON'T cache `node_modules/` -- cache the npm download cache
