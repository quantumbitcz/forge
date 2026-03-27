# Tekton with ASP.NET

> Extends `modules/ci-cd/tekton.md` with ASP.NET Core pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/aspnet-build-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: aspnet-build-test
spec:
  workspaces:
    - name: source
    - name: nuget-cache
      optional: true
  params:
    - name: DOTNET_IMAGE
      default: mcr.microsoft.com/dotnet/sdk:9.0
    - name: CONFIGURATION
      default: Release
  steps:
    - name: build-and-test
      image: $(params.DOTNET_IMAGE)
      workingDir: $(workspaces.source.path)
      env:
        - name: NUGET_PACKAGES
          value: $(workspaces.nuget-cache.path)
      script: |
        #!/usr/bin/env bash
        dotnet restore
        dotnet build --no-restore -c $(params.CONFIGURATION)
        dotnet test --no-build -c $(params.CONFIGURATION) --logger "trx;LogFileName=results.trx"
```

## Framework-Specific Patterns

### Kaniko Image Build

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: aspnet-kaniko-build
spec:
  workspaces:
    - name: source
    - name: docker-config
  params:
    - name: IMAGE
    - name: TAG
      default: latest
  steps:
    - name: kaniko
      image: gcr.io/kaniko-project/executor:latest
      args:
        - --dockerfile=$(workspaces.source.path)/Dockerfile
        - --context=$(workspaces.source.path)
        - --destination=$(params.IMAGE):$(params.TAG)
```

### Full Pipeline

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: aspnet-ci
spec:
  workspaces:
    - name: shared-workspace
    - name: nuget-cache
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
    - name: build-and-test
      taskRef:
        name: aspnet-build-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: nuget-cache
          workspace: nuget-cache
    - name: build-image
      taskRef:
        name: aspnet-kaniko-build
      runAfter: [build-and-test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

## Scaffolder Patterns

```yaml
patterns:
  task_build: "tekton/tasks/aspnet-build-test.yaml"
  task_image: "tekton/tasks/aspnet-kaniko-build.yaml"
  pipeline: "tekton/pipelines/aspnet-ci.yaml"
```

## Additional Dos

- DO persist NuGet cache via PVC-backed workspaces
- DO use Kaniko for rootless image builds
- DO build in Release configuration
- DO use the .NET SDK image for build tasks

## Additional Don'ts

- DON'T skip `runAfter` ordering
- DON'T embed registry credentials in Task specs
- DON'T use Debug configuration in CI
