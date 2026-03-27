# Tekton with NestJS

> Extends `modules/ci-cd/tekton.md` with NestJS pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/nestjs-build-test.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: nestjs-build-test
spec:
  workspaces:
    - name: source
    - name: npm-cache
      optional: true
  steps:
    - name: install-build-test
      image: node:22-slim
      workingDir: $(workspaces.source.path)
      env:
        - name: npm_config_cache
          value: $(workspaces.npm-cache.path)
      script: |
        #!/usr/bin/env bash
        npm ci
        npm run lint
        npm run build
        npm test -- --coverage
```

## Framework-Specific Patterns

### E2E Test with Database Sidecar

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: nestjs-e2e-test
spec:
  workspaces:
    - name: source
  sidecars:
    - name: postgres
      image: postgres:16-alpine
      env:
        - name: POSTGRES_DB
          value: test
        - name: POSTGRES_USER
          value: test
        - name: POSTGRES_PASSWORD
          value: test
  steps:
    - name: e2e-test
      image: node:22-slim
      workingDir: $(workspaces.source.path)
      env:
        - name: DATABASE_URL
          value: postgresql://test:test@localhost:5432/test
      script: |
        #!/usr/bin/env bash
        npm ci && npm run build
        until node -e "const net = require('net'); const s = net.createConnection(5432, 'localhost'); s.on('connect', () => process.exit(0)); s.on('error', () => process.exit(1));" 2>/dev/null; do sleep 1; done
        npm run test:e2e
```

### Full Pipeline

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: nestjs-ci
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
    - name: build-and-test
      taskRef:
        name: nestjs-build-test
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: npm-cache
          workspace: npm-cache
    - name: e2e-test
      taskRef:
        name: nestjs-e2e-test
      runAfter: [build-and-test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

## Scaffolder Patterns

```yaml
patterns:
  task_build: "tekton/tasks/nestjs-build-test.yaml"
  task_e2e: "tekton/tasks/nestjs-e2e-test.yaml"
  pipeline: "tekton/pipelines/nestjs-ci.yaml"
```

## Additional Dos

- DO run `nest build` before any test tasks
- DO use sidecars for database dependencies in E2E tests
- DO wait for PostgreSQL readiness before running E2E tests
- DO persist npm cache via PVC-backed workspaces

## Additional Don'ts

- DON'T skip `runAfter` ordering -- Tekton tasks run in parallel by default
- DON'T embed registry credentials in Task specs
- DON'T skip the build step -- NestJS requires compilation
