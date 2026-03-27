# Azure Pipelines with Express

> Extends `modules/ci-cd/azure-pipelines.md` with Express/Node.js CI patterns.
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
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '22.x'

          - task: Cache@2
            inputs:
              key: 'npm | "$(Agent.OS)" | package-lock.json'
              restoreKeys: |
                npm | "$(Agent.OS)"
              path: $(npm_config_cache)

          - script: npm ci
            displayName: Install dependencies

          - script: npx eslint .
            displayName: Lint

          - script: npm test -- --coverage
            displayName: Test
            env:
              NODE_ENV: test

          - task: PublishTestResults@2
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: '**/junit.xml'
```

## Framework-Specific Patterns

### npm Cache

```yaml
- task: Cache@2
  inputs:
    key: 'npm | "$(Agent.OS)" | package-lock.json'
    restoreKeys: |
      npm | "$(Agent.OS)"
    path: $(npm_config_cache)
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

- DO use `Cache@2` with `package-lock.json` as cache key
- DO use `NodeTool@0` for Node.js version management
- DO use `PublishTestResults@2` for Azure test result integration
- DO set `NODE_ENV=test` for test jobs

## Additional Don'ts

- DON'T use `npm install` in CI -- use `npm ci` for deterministic installs
- DON'T cache `node_modules/` -- cache the npm download cache
- DON'T skip `displayName` on script tasks
