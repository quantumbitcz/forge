# Tekton with Spring

> Extends `modules/ci-cd/tekton.md` with Spring Boot pipeline task patterns.
> Generic Tekton conventions (Tasks, Pipelines, PipelineRuns, workspaces) are NOT repeated here.

## Integration Setup

```yaml
# tekton/tasks/spring-boot-build.yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: spring-boot-gradle-build
spec:
  workspaces:
    - name: source
    - name: gradle-cache
      optional: true
  params:
    - name: JAVA_IMAGE
      default: eclipse-temurin:21-jdk
    - name: GRADLE_ARGS
      default: "build"
  steps:
    - name: build
      image: $(params.JAVA_IMAGE)
      workingDir: $(workspaces.source.path)
      env:
        - name: GRADLE_OPTS
          value: "-Dorg.gradle.daemon=false"
        - name: GRADLE_USER_HOME
          value: $(workspaces.gradle-cache.path)
      script: |
        #!/usr/bin/env bash
        ./gradlew $(params.GRADLE_ARGS)
```

## Framework-Specific Patterns

### Testcontainers with Sidecar

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: spring-boot-integration-test
spec:
  workspaces:
    - name: source
    - name: gradle-cache
      optional: true
  sidecars:
    - name: dind
      image: docker:dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
  steps:
    - name: integration-test
      image: eclipse-temurin:21-jdk
      workingDir: $(workspaces.source.path)
      env:
        - name: DOCKER_HOST
          value: tcp://localhost:2375
        - name: TESTCONTAINERS_RYUK_DISABLED
          value: "true"
        - name: GRADLE_OPTS
          value: "-Dorg.gradle.daemon=false"
      script: |
        #!/usr/bin/env bash
        # Wait for Docker daemon
        until docker info >/dev/null 2>&1; do sleep 1; done
        ./gradlew integrationTest
```

The Docker-in-Docker sidecar runs alongside the build step in the same pod. Wait for the Docker daemon before running tests.

### Maven Build Task

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: spring-boot-maven-build
spec:
  workspaces:
    - name: source
    - name: maven-cache
      optional: true
  steps:
    - name: build
      image: eclipse-temurin:21-jdk
      workingDir: $(workspaces.source.path)
      env:
        - name: MAVEN_OPTS
          value: "-Dmaven.repo.local=$(workspaces.maven-cache.path)"
      script: |
        #!/usr/bin/env bash
        ./mvnw -B verify
```

### Kaniko Image Build

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: spring-boot-kaniko-build
spec:
  workspaces:
    - name: source
    - name: docker-config
  params:
    - name: IMAGE
    - name: TAG
      default: latest
  steps:
    - name: boot-jar
      image: eclipse-temurin:21-jdk
      workingDir: $(workspaces.source.path)
      script: |
        #!/usr/bin/env bash
        ./gradlew bootJar
    - name: kaniko
      image: gcr.io/kaniko-project/executor:latest
      args:
        - --dockerfile=$(workspaces.source.path)/Dockerfile
        - --context=$(workspaces.source.path)
        - --destination=$(params.IMAGE):$(params.TAG)
```

Kaniko builds container images without a Docker daemon -- runs as a regular container, no privileged mode needed.

### Full Pipeline

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: spring-boot-ci
spec:
  workspaces:
    - name: shared-workspace
    - name: gradle-cache
  tasks:
    - name: fetch-source
      taskRef:
        name: git-clone
      workspaces:
        - name: output
          workspace: shared-workspace

    - name: build-and-test
      taskRef:
        name: spring-boot-gradle-build
      runAfter: [fetch-source]
      workspaces:
        - name: source
          workspace: shared-workspace
        - name: gradle-cache
          workspace: gradle-cache

    - name: integration-test
      taskRef:
        name: spring-boot-integration-test
      runAfter: [build-and-test]
      workspaces:
        - name: source
          workspace: shared-workspace

    - name: build-image
      taskRef:
        name: spring-boot-kaniko-build
      runAfter: [integration-test]
      workspaces:
        - name: source
          workspace: shared-workspace
```

## Scaffolder Patterns

```yaml
patterns:
  task_build: "tekton/tasks/spring-boot-build.yaml"
  task_integration: "tekton/tasks/spring-boot-integration-test.yaml"
  task_image: "tekton/tasks/spring-boot-kaniko-build.yaml"
  pipeline: "tekton/pipelines/spring-boot-ci.yaml"
```

## Additional Dos

- DO use sidecars for Docker-in-Docker instead of privileged init containers
- DO use Kaniko for image builds in environments where privileged containers are restricted
- DO persist Gradle/Maven caches via workspaces backed by PersistentVolumeClaims
- DO wait for Docker daemon readiness in sidecar-based integration test tasks

## Additional Don'ts

- DON'T use `privileged: true` on build steps -- confine it to the DinD sidecar
- DON'T skip `runAfter` ordering -- Tekton tasks run in parallel by default
- DON'T embed registry credentials in Task specs -- use Tekton's `docker-config` workspace
