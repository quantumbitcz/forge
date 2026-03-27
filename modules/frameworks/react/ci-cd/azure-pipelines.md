# Azure Pipelines with React

> Extends `modules/ci-cd/azure-pipelines.md` with React + Vite CI patterns.
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

          - script: npm run test
            displayName: Test

          - script: npm run build
            displayName: Build

          - publish: dist
            artifact: webapp
```

## Framework-Specific Patterns

### Bun Alternative

```yaml
steps:
  - script: |
      curl -fsSL https://bun.sh/install | bash
      export PATH="$HOME/.bun/bin:$PATH"
      bun install --frozen-lockfile
      bun run build
    displayName: Build with Bun
```

### Dependency Caching

```yaml
- task: Cache@2
  inputs:
    key: 'npm | "$(Agent.OS)" | package-lock.json'
    restoreKeys: |
      npm | "$(Agent.OS)"
    path: $(npm_config_cache)

- script: npm ci
  displayName: Install dependencies
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
          artifact: webapp
        - task: Docker@2
          inputs:
            containerRegistry: $(dockerRegistryServiceConnection)
            repository: $(imageRepository)
            command: buildAndPush
            Dockerfile: Dockerfile
            tags: $(Build.SourceVersion)
```

### Playwright E2E Tests

```yaml
- script: npx playwright install --with-deps chromium
  displayName: Install Playwright

- script: npx playwright test
  displayName: E2E Tests

- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: "playwright-report/results.xml"
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "azure-pipelines.yml"
```

## Additional Dos

- DO use `Cache@2` task with `package-lock.json` as cache key for npm dependencies
- DO publish build artifacts between stages with `publish`/`download` tasks
- DO use `NodeTool@0` to pin the Node.js version explicitly
- DO publish Playwright JUnit results with `PublishTestResults@2` for test trend tracking

## Additional Don'ts

- DON'T use `npm install` in CI -- use `npm ci` for deterministic installs
- DON'T cache `node_modules/` directly -- cache the npm cache directory instead
- DON'T skip type checking in CI even if the build succeeds -- run `tsc --noEmit` explicitly
