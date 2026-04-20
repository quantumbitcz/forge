# GitHub Actions with Spring

> Extends `modules/ci-cd/github-actions.md` with Spring Boot CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    services:
      docker:
        image: docker:dind
        options: --privileged
    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: |
            21
            17
          cache: gradle

      - name: Build and test
        run: ./gradlew build
        env:
          TESTCONTAINERS_RYUK_DISABLED: true

      - name: Integration tests
        run: ./gradlew integrationTest
        env:
          TESTCONTAINERS_RYUK_DISABLED: true
```

## Framework-Specific Patterns

### Testcontainers in GitHub Actions

GitHub Actions runners include Docker. Testcontainers works out of the box, but disable Ryuk (the container reaper) -- the runner is ephemeral so cleanup is unnecessary and Ryuk can cause socket permission issues.

```yaml
env:
  TESTCONTAINERS_RYUK_DISABLED: true
  TESTCONTAINERS_CHECKS_DISABLE: true
```

### Gradle Caching

```yaml
- uses: actions/setup-java@v4
  with:
    distribution: temurin
    java-version: 21
    cache: gradle

- uses: gradle/actions/setup-gradle@v4
  with:
    cache-read-only: ${{ github.ref != 'refs/heads/main' }}
```

Use `gradle/actions/setup-gradle` for fine-grained Gradle cache control. Set `cache-read-only` on PRs to avoid cache pollution from feature branches.

### Maven Caching

```yaml
- uses: actions/setup-java@v4
  with:
    distribution: temurin
    java-version: 21
    cache: maven
```

### Spring Native (GraalVM) Build

```yaml
native-build:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: graalvm/setup-graalvm@v1
      with:
        java-version: 21
        distribution: graalce
    - name: Build native image
      run: ./gradlew nativeCompile
    - name: Test native image
      run: ./gradlew nativeTest
```

Native builds are slow (5-15 min). Run as a separate job, optionally only on `main` or release branches.

### Docker Image Publishing

```yaml
publish:
  needs: build
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: actions/setup-java@v4
      with:
        distribution: temurin
        java-version: 21
        cache: gradle

    - name: Build layered JAR
      run: ./gradlew bootJar

    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
  native_workflow: ".github/workflows/native.yml"
```

## Additional Dos

- DO disable Testcontainers Ryuk in GitHub Actions (`TESTCONTAINERS_RYUK_DISABLED=true`)
- DO use `gradle/actions/setup-gradle` for cache control beyond what `actions/setup-java` provides
- DO run native builds as a separate job to avoid blocking the main pipeline
- DO use `ghcr.io` for container images -- authentication uses the built-in `GITHUB_TOKEN`

## Additional Don'ts

- DON'T cache `~/.gradle/caches` manually when using `actions/setup-java` with `cache: gradle`
- DON'T run `nativeCompile` on every PR -- it's slow and resource-intensive
- DON'T use `docker/dind` service unless you need Docker-in-Docker for Testcontainers on custom runners
