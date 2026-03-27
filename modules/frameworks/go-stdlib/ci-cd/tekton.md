# Tekton with Go stdlib

> Extends `modules/ci-cd/tekton.md` with Go stdlib pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/go-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: go-test
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
  name: go-kaniko-build
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
  name: go-ci
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
        name: go-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: go-cache
          workspace: go-cache
    - name: build-image
      taskRef:
        name: go-kaniko-build
      runAfter: [test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

### Multi-Architecture Build

```yaml
- name: build-multiarch
  image: golang:1.23-alpine
  script: |
    #!/usr/bin/env sh
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o app-amd64 ./cmd/server
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o app-arm64 ./cmd/server
```

Go's cross-compilation makes multi-architecture builds trivial -- no QEMU or buildx required.

## Scaffolder Patterns

```yaml
patterns:
  task_test: "tekton/tasks/go-test.yaml"
  task_image: "tekton/tasks/go-kaniko-build.yaml"
  pipeline: "tekton/pipelines/go-ci.yaml"
```

## Additional Dos

- DO persist Go module cache via workspaces backed by PersistentVolumeClaims
- DO use Kaniko for rootless image builds in Tekton
- DO run `go vet` before tests
- DO use `-race` flag to detect data races
- DO build with `CGO_ENABLED=0` for static binaries

## Additional Don'ts

- DON'T skip `runAfter` -- Tekton tasks run in parallel by default
- DON'T embed registry credentials in Task specs -- use `docker-config` workspace
- DON'T build with CGO enabled when targeting `scratch` Docker images
- DON'T skip `go vet` -- it catches common Go mistakes
