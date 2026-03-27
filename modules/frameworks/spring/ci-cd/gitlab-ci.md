# GitLab CI with Spring

> Extends `modules/ci-cd/gitlab-ci.md` with Spring Boot CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: eclipse-temurin:21-jdk

stages:
  - build
  - test
  - integration-test
  - publish

variables:
  GRADLE_OPTS: "-Dorg.gradle.daemon=false"
  GRADLE_USER_HOME: "$CI_PROJECT_DIR/.gradle"

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .gradle/caches
    - .gradle/wrapper
```

## Framework-Specific Patterns

### Gradle Build

```yaml
build:
  stage: build
  script:
    - ./gradlew assemble
  artifacts:
    paths:
      - build/libs/*.jar
    expire_in: 1 hour
```

### Testcontainers with Docker Service

```yaml
integration-test:
  stage: integration-test
  services:
    - docker:dind
  variables:
    DOCKER_HOST: tcp://docker:2375
    DOCKER_TLS_CERTDIR: ""
    TESTCONTAINERS_RYUK_DISABLED: "true"
    TESTCONTAINERS_HOST_OVERRIDE: docker
  script:
    - ./gradlew integrationTest
```

GitLab CI requires explicit Docker-in-Docker service for Testcontainers. Set `TESTCONTAINERS_HOST_OVERRIDE=docker` to route container traffic to the DinD sidecar.

### Maven Build

```yaml
build:
  stage: build
  image: eclipse-temurin:21-jdk
  script:
    - ./mvnw -B package -DskipTests
  cache:
    key: "$CI_COMMIT_REF_SLUG"
    paths:
      - .m2/repository
  variables:
    MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository"
```

### Spring Native Build

```yaml
native-build:
  stage: build
  image: ghcr.io/graalvm/graalvm-community:21
  script:
    - ./gradlew nativeCompile
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  timeout: 20m
```

### Docker Image Publishing

```yaml
publish:
  stage: publish
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO disable Gradle daemon in CI (`-Dorg.gradle.daemon=false`) -- daemon overhead isn't recouped in ephemeral runners
- DO set `TESTCONTAINERS_HOST_OVERRIDE=docker` when using Docker-in-Docker service
- DO cache `.gradle/caches` and `.gradle/wrapper` keyed by branch slug
- DO use `artifacts` with `expire_in` for build outputs passed between stages

## Additional Don'ts

- DON'T use `DOCKER_TLS_CERTDIR` with a value when connecting to DinD without TLS
- DON'T cache `build/` directory -- it's large and rarely provides meaningful speedup
- DON'T forget `--no-daemon` equivalent for Maven (`-B` batch mode is sufficient)
