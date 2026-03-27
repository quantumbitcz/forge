# Tekton with Express

> Extends `modules/ci-cd/tekton.md` with Express/Node.js pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/express-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: express-test
spec:
  workspaces:
    - name: source
    - name: npm-cache
      optional: true
  params:
    - name: NODE_IMAGE
      default: node:22-slim
  steps:
    - name: install-and-test
      image: $(params.NODE_IMAGE)
      workingDir: $(workspaces.source.path)
      env:
        - name: npm_config_cache
          value: $(workspaces.npm-cache.path)
        - name: NODE_ENV
          value: test
      script: |
        #!/usr/bin/env bash
        npm ci
        npx eslint .
        npm test -- --coverage
```

## Framework-Specific Patterns

### Kaniko Image Build

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: express-kaniko-build
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
  name: express-ci
spec:
  workspaces:
    - name: shared-workspace
    - name: npm-cache
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace
    - name: test
      taskRef:
        name: express-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: npm-cache
          workspace: npm-cache
    - name: build-image
      taskRef:
        name: express-kaniko-build
      runAfter: [test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

## Scaffolder Patterns

```yaml
patterns:
  task_test: "tekton/tasks/express-test.yaml"
  task_image: "tekton/tasks/express-kaniko-build.yaml"
  pipeline: "tekton/pipelines/express-ci.yaml"
```

## Additional Dos

- DO persist npm cache via workspaces backed by PersistentVolumeClaims
- DO use Kaniko for rootless image builds
- DO use `npm ci` for deterministic dependency resolution
- DO set `NODE_ENV=test` in test task steps

## Additional Don'ts

- DON'T skip `runAfter` ordering -- Tekton tasks run in parallel by default
- DON'T embed registry credentials in Task specs -- use Tekton's `docker-config` workspace
- DON'T use `npm install` in Tekton tasks -- use `npm ci` for reproducibility
