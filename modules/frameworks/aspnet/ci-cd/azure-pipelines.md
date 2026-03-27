# Azure Pipelines with ASP.NET

> Extends `modules/ci-cd/azure-pipelines.md` with ASP.NET Core CI patterns.
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
  buildConfiguration: Release

stages:
  - stage: Build
    jobs:
      - job: BuildAndTest
        steps:
          - task: UseDotNet@2
            inputs:
              packageType: sdk
              version: 9.0.x

          - task: DotNetCoreCLI@2
            displayName: Restore
            inputs:
              command: restore

          - task: DotNetCoreCLI@2
            displayName: Build
            inputs:
              command: build
              arguments: '--no-restore -c $(buildConfiguration)'

          - task: DotNetCoreCLI@2
            displayName: Test
            inputs:
              command: test
              arguments: '--no-build -c $(buildConfiguration) --collect:"XPlat Code Coverage"'

          - task: PublishCodeCoverageResults@2
            inputs:
              summaryFileLocation: '**/coverage.cobertura.xml'
```

## Framework-Specific Patterns

### Native .NET Tasks

Azure Pipelines has first-class .NET support via `DotNetCoreCLI@2`. Use these instead of `script` tasks to get automatic test result publishing and NuGet credential injection.

### NuGet Caching

```yaml
- task: Cache@2
  inputs:
    key: 'nuget | "$(Agent.OS)" | **/packages.lock.json'
    restoreKeys: |
      nuget | "$(Agent.OS)"
    path: $(NUGET_PACKAGES)
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

- DO use `DotNetCoreCLI@2` tasks for automatic test result publishing
- DO use `UseDotNet@2` for .NET SDK version management
- DO use `Cache@2` with `packages.lock.json` for NuGet caching
- DO publish code coverage with `PublishCodeCoverageResults@2`

## Additional Don'ts

- DON'T use `script` tasks for dotnet commands when `DotNetCoreCLI@2` exists
- DON'T build in Debug configuration in CI
- DON'T skip code coverage collection
