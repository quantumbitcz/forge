# Bitbucket Pipelines with Spring

> Extends `modules/ci-cd/bitbucket-pipelines.md` with Spring Boot CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: eclipse-temurin:21-jdk

definitions:
  caches:
    gradle: ~/.gradle/caches
    gradle-wrapper: ~/.gradle/wrapper

pipelines:
  default:
    - step:
        name: Build and Unit Test
        caches:
          - gradle
          - gradle-wrapper
        script:
          - ./gradlew build
        artifacts:
          - build/libs/*.jar

    - step:
        name: Integration Test
        caches:
          - gradle
          - gradle-wrapper
        services:
          - docker
        script:
          - export TESTCONTAINERS_RYUK_DISABLED=true
          - ./gradlew integrationTest
```

## Framework-Specific Patterns

### Testcontainers with Docker Service

Bitbucket Pipelines provides Docker via a service declaration. The service must be explicitly listed for steps that need it.

```yaml
definitions:
  services:
    docker:
      memory: 2048

pipelines:
  default:
    - step:
        services:
          - docker
        script:
          - export TESTCONTAINERS_RYUK_DISABLED=true
          - ./gradlew integrationTest
```

Increase Docker service memory to 2048MB when running multiple Testcontainers simultaneously.

### Maven Build

```yaml
definitions:
  caches:
    maven: ~/.m2/repository

pipelines:
  default:
    - step:
        name: Build and Test
        caches:
          - maven
        script:
          - ./mvnw -B verify
```

### Docker Image Publishing

```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build JAR
          caches:
            - gradle
          script:
            - ./gradlew bootJar
          artifacts:
            - build/libs/*.jar

      - step:
          name: Build and Push Image
          services:
            - docker
          script:
            - docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
            - docker build -t $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT .
            - docker push $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT
```

### Parallel Test Execution

```yaml
- parallel:
    - step:
        name: Unit Tests
        caches:
          - gradle
        script:
          - ./gradlew test
    - step:
        name: Integration Tests
        caches:
          - gradle
        services:
          - docker
        script:
          - export TESTCONTAINERS_RYUK_DISABLED=true
          - ./gradlew integrationTest
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "bitbucket-pipelines.yml"
```

## Additional Dos

- DO define custom cache names for Gradle (`gradle` and `gradle-wrapper`) -- Bitbucket has no built-in Gradle cache
- DO increase Docker service memory when using multiple Testcontainers
- DO use `parallel` steps for independent unit and integration test suites
- DO pass build artifacts between steps to avoid rebuilding

## Additional Don'ts

- DON'T forget the `services: [docker]` declaration -- Testcontainers fails silently without it
- DON'T exceed the 2GB artifact limit -- use `build/libs/*.jar` not `build/**`
- DON'T run Gradle daemon in Bitbucket Pipelines -- set `GRADLE_OPTS=-Dorg.gradle.daemon=false`
