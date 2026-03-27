# Azure Pipelines with Angular

> Extends `modules/ci-cd/azure-pipelines.md` with Angular CLI CI patterns.
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

          - script: npx ng lint
            displayName: Lint

          - script: npx ng test --no-watch --browsers=ChromeHeadless
            displayName: Unit Tests

          - script: npx ng build --configuration production
            displayName: Build

          - publish: dist
            artifact: webapp
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

### Angular Universal SSR Build

```yaml
- script: npx ng build --configuration production
  displayName: Build SSR App

- publish: dist/app
  artifact: ssr-bundle
```

For SSR apps, the build output includes both `browser/` and `server/` directories. Publish the entire `dist/app` directory.

### Multi-Stage with Docker Publishing

```yaml
- stage: Publish
  dependsOn: Build
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
    - job: PublishImage
      steps:
        - download: current
          artifact: webapp
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
- DO use `NodeTool@0` to pin Node.js version explicitly
- DO build with `--configuration production` for AOT compilation and tree-shaking
- DO publish build artifacts between stages with `publish`/`download` tasks

## Additional Don'ts

- DON'T use `npm install` in CI -- use `npm ci` for deterministic installs
- DON'T skip `--no-watch` on `ng test` -- CI tests must exit after running
- DON'T cache `node_modules/` directly -- cache the npm cache directory
