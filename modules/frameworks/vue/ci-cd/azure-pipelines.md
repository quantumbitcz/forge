# Azure Pipelines with Vue / Nuxt

> Extends `modules/ci-cd/azure-pipelines.md` with Vue 3 / Nuxt 3 CI patterns.
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
              versionSpec: "22.x"

          - script: npm ci
            displayName: Install dependencies

          - script: npm run lint
            displayName: Lint

          - script: npx nuxi typecheck
            displayName: Type Check

          - script: npm run test
            displayName: Test

          - script: npm run build
            displayName: Build

          - publish: .output
            artifact: nuxt-output
```

## Framework-Specific Patterns

### Dependency Caching

```yaml
- task: Cache@2
  inputs:
    key: 'npm | "$(Agent.OS)" | package-lock.json'
    restoreKeys: |
      npm | "$(Agent.OS)"
    path: $(npm_config_cache)
```

### Static Site Generation

```yaml
- script: npx nuxt generate
  displayName: Generate Static Site

- publish: .output/public
  artifact: static-site
```

### Multi-Stage with Docker Publishing

```yaml
- stage: Publish
  dependsOn: Build
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
    - job: PublishImage
      steps:
        - download: current
          artifact: nuxt-output
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

- DO use `nuxi typecheck` for Nuxt-generated type validation
- DO use `Cache@2` with `package-lock.json` as cache key
- DO publish `.output/` as an artifact for downstream stages
- DO choose between `nuxt build` (SSR) and `nuxt generate` (static) based on deployment target

## Additional Don'ts

- DON'T use `npm install` in CI -- use `npm ci`
- DON'T skip `nuxi typecheck` -- plain `tsc` misses Nuxt auto-import types
- DON'T cache `node_modules/` directly -- cache the npm cache directory
