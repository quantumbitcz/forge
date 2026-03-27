# Tekton with Gin

> Extends `modules/ci-cd/tekton.md` with Gin/Go pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/gin-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: gin-test
spec:
  workspaces:
    - name: source
    - name: go-cache
      optional: true
  params:
    - name: GO_IMAGE
      default: golang:1.23-alpine
  steps:
    - name: vet-and-test
      image: $(params.GO_IMAGE)
      workingDir: $(workspaces.source.path)
      env:
        - name: GOMODCACHE
          value: $(workspaces.go-cache.path)/mod
        - name: GOCACHE
          value: $(workspaces.go-cache.path)/build
        - name: GIN_MODE
          value: test
      script: |
        #!/usr/bin/env sh
        go vet ./...
        go test ./... -race -coverprofile=coverage.out
        CGO_ENABLED=0 go build -o /dev/null ./...
```

## Framework-Specific Patterns

### Kaniko Image Build

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: gin-kaniko-build
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
  name: gin-ci
spec:
  workspaces:
    - name: shared-workspace
    - name: go-cache
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
    - name: test
      taskRef:
        name: gin-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: go-cache
          workspace: go-cache
    - name: build-image
      taskRef:
        name: gin-kaniko-build
      runAfter: [test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

### Static Binary Build Task

```yaml
- name: build-static
  image: golang:1.23-alpine
  script: |
    #!/usr/bin/env sh
    CGO_ENABLED=0 GOOS=linux go build -o app ./cmd/server
```

## Scaffolder Patterns

```yaml
patterns:
  task_test: "tekton/tasks/gin-test.yaml"
  task_image: "tekton/tasks/gin-kaniko-build.yaml"
  pipeline: "tekton/pipelines/gin-ci.yaml"
```

## Additional Dos

- DO persist Go module cache via workspaces backed by PersistentVolumeClaims
- DO use Kaniko for rootless image builds
- DO set `GIN_MODE=test` in test task environment
- DO use `-race` flag to detect data races

## Additional Don'ts

- DON'T skip `runAfter` -- Tekton tasks run in parallel by default
- DON'T embed registry credentials in Task specs -- use `docker-config` workspace
- DON'T use `go install` for CI builds -- use `go build` with explicit output
- DON'T build with CGO enabled when targeting `scratch` Docker images
