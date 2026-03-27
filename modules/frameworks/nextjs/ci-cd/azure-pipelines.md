# Azure Pipelines with Next.js

> Extends `modules/ci-cd/azure-pipelines.md` with Next.js CI patterns.
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

          - task: Cache@2
            inputs:
              key: 'nextjs | "$(Agent.OS)" | package-lock.json'
              path: .next/cache

          - script: npm ci
            displayName: Install

          - script: npm run lint
            displayName: Lint

          - script: npm run build
            displayName: Build

          - script: npm test
            displayName: Test

          - task: PublishTestResults@2
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: '**/junit.xml'
```

## Framework-Specific Patterns

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

- DO cache both npm dependencies and `.next/cache` separately
- DO run `next lint` and `next build` in CI
- DO use `PublishTestResults@2` for test integration
- DO use `Cache@2` with separate keys for npm and Next.js caches

## Additional Don'ts

- DON'T skip the build step -- Next.js validates at compile time
- DON'T cache all of `.next/` -- only `.next/cache`
- DON'T skip `displayName` on script tasks
