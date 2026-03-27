# CircleCI with Spring

> Extends `modules/ci-cd/circleci.md` with Spring Boot CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  gradle: circleci/gradle@3.0
  docker: circleci/docker@2.6

executors:
  jdk:
    docker:
      - image: cimg/openjdk:21.0
    resource_class: medium

jobs:
  build-and-test:
    executor: jdk
    steps:
      - checkout
      - gradle/with_cache:
          steps:
            - run: ./gradlew build

  integration-test:
    executor: jdk
    steps:
      - checkout
      - setup_remote_docker:
          docker_layer_caching: true
      - gradle/with_cache:
          steps:
            - run:
                command: ./gradlew integrationTest
                environment:
                  TESTCONTAINERS_RYUK_DISABLED: "true"

workflows:
  ci:
    jobs:
      - build-and-test
      - integration-test:
          requires:
            - build-and-test
```

## Framework-Specific Patterns

### Testcontainers with Remote Docker

CircleCI uses remote Docker for container operations. Enable `setup_remote_docker` for Testcontainers, and disable Ryuk since the remote Docker environment handles cleanup.

```yaml
- setup_remote_docker:
    docker_layer_caching: true
    version: default
```

Note: `setup_remote_docker` creates a separate VM for Docker -- containers are not co-located with the build executor. Testcontainers detects this automatically via environment checks.

### Gradle Caching

```yaml
- gradle/with_cache:
    deps_checksum_file: gradle/libs.versions.toml
    steps:
      - run: ./gradlew build
```

The CircleCI Gradle orb caches `~/.gradle/caches` and `~/.gradle/wrapper`. Specify `deps_checksum_file` for cache key precision.

### Maven Caching

```yaml
- restore_cache:
    keys:
      - maven-{{ checksum "pom.xml" }}
      - maven-
- run: ./mvnw -B package
- save_cache:
    key: maven-{{ checksum "pom.xml" }}
    paths:
      - ~/.m2/repository
```

### Spring Native Build

```yaml
native-build:
  docker:
    - image: ghcr.io/graalvm/graalvm-community:21
  resource_class: large
  steps:
    - checkout
    - run:
        command: ./gradlew nativeCompile
        no_output_timeout: 20m
```

Use `resource_class: large` for native builds -- GraalVM's `native-image` is memory-intensive.

### Docker Image Publishing

```yaml
publish:
  executor: jdk
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: true
    - run: ./gradlew bootJar
    - docker/build:
        image: $CIRCLE_PROJECT_REPONAME
        tag: $CIRCLE_SHA1
    - docker/push:
        image: $CIRCLE_PROJECT_REPONAME
        tag: $CIRCLE_SHA1
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use `setup_remote_docker` with `docker_layer_caching: true` for Testcontainers
- DO use the CircleCI Gradle orb for standardized caching
- DO use `resource_class: large` for GraalVM native image builds
- DO set `no_output_timeout` for long-running native compilation steps

## Additional Don'ts

- DON'T assume Docker is available in the build executor without `setup_remote_docker`
- DON'T use `machine` executor for simple Java builds -- `docker` executor is faster to start
- DON'T cache the entire `build/` directory -- cache only Gradle/Maven dependency directories
