# Tekton with Axum

> Extends `modules/ci-cd/tekton.md` with Axum/Rust pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/axum-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: axum-test
spec:
  workspaces:
    - name: source
    - name: cargo-cache
      optional: true
  params:
    - name: RUST_IMAGE
      default: rust:1.80-slim
  steps:
    - name: clippy-and-test
      image: $(params.RUST_IMAGE)
      workingDir: $(workspaces.source.path)
      env:
        - name: CARGO_HOME
          value: $(workspaces.cargo-cache.path)
      script: |
        #!/usr/bin/env bash
        cargo clippy -- -D warnings
        cargo test
        cargo build --release
```

## Framework-Specific Patterns

### Kaniko Image Build

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: axum-kaniko-build
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
  name: axum-ci
spec:
  workspaces:
    - name: shared-workspace
    - name: cargo-cache
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
    - name: test
      taskRef:
        name: axum-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: cargo-cache
          workspace: cargo-cache
    - name: build-image
      taskRef:
        name: axum-kaniko-build
      runAfter: [test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

### Static Binary Build Task

```yaml
- name: build-static
  image: rust:1.80-slim
  script: |
    #!/usr/bin/env bash
    rustup target add x86_64-unknown-linux-musl
    RUSTFLAGS='-C target-feature=+crt-static' \
      cargo build --release --target x86_64-unknown-linux-musl
```

## Scaffolder Patterns

```yaml
patterns:
  task_test: "tekton/tasks/axum-test.yaml"
  task_image: "tekton/tasks/axum-kaniko-build.yaml"
  pipeline: "tekton/pipelines/axum-ci.yaml"
```

## Additional Dos

- DO persist Cargo cache via workspaces backed by PersistentVolumeClaims
- DO use Kaniko for rootless image builds in Tekton
- DO run `cargo clippy -- -D warnings` before tests
- DO use `runAfter` for sequential task ordering

## Additional Don'ts

- DON'T skip `runAfter` -- Tekton tasks run in parallel by default
- DON'T embed registry credentials in Task specs -- use `docker-config` workspace
- DON'T use `resource_class` style hints -- Tekton uses Kubernetes resource requests/limits
- DON'T build without `--release` for production images
