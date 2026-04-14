# GitHub Actions with Kotlin Multiplatform

> Extends `modules/ci-cd/github-actions.md` with KMP multi-target CI patterns.
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
  build-jvm-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
          cache: gradle

      - uses: android-actions/setup-android@v3

      - name: Build and Test (JVM + Android)
        run: ./gradlew :shared:jvmTest :shared:testDebugUnitTest :androidApp:assembleDebug

  build-ios:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
          cache: gradle

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app

      - name: Build and Test (iOS)
        run: ./gradlew :shared:iosSimulatorArm64Test
```

## Framework-Specific Patterns

### Multi-Target Matrix Strategy

```yaml
jobs:
  test:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            task: ":shared:jvmTest"
          - os: ubuntu-latest
            task: ":shared:testDebugUnitTest"
          - os: macos-15
            task: ":shared:iosSimulatorArm64Test"
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
          cache: gradle
      - run: ./gradlew ${{ matrix.task }}
```

iOS targets require MacOS runners. JVM and Android targets run on Ubuntu. Use a matrix to run them in parallel.

### Gradle Caching

```yaml
- uses: gradle/actions/setup-gradle@v4
  with:
    cache-read-only: ${{ github.ref != 'refs/heads/main' }}
```

KMP builds are slow due to multiple target compilations. Aggressive caching is critical.

### XCFramework Publishing

```yaml
publish-ios:
  needs: [build-jvm-android, build-ios]
  if: github.ref == 'refs/heads/main'
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-java@v4
      with:
        distribution: temurin
        java-version: 21
        cache: gradle
    - run: sudo xcode-select -s /Applications/Xcode_16.2.app
    - run: ./gradlew :shared:assembleXCFramework
    - uses: actions/upload-artifact@v4
      with:
        name: xcframework
        path: shared/build/XCFrameworks/release/
```

### Lint and Static Analysis

```yaml
lint:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-java@v4
      with:
        distribution: temurin
        java-version: 21
        cache: gradle
    - run: ./gradlew lintKotlin detekt
```

Lint and detekt run on JVM only -- no need for MacOS runners or Android SDK.

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO use a matrix strategy to parallelize JVM, Android, and iOS target builds
- DO use MacOS runners for iOS target compilation and testing
- DO use `gradle/actions/setup-gradle` with aggressive caching for KMP builds
- DO publish XCFramework on main branch merges for iOS consumers

## Additional Don'ts

- DON'T run iOS tests on Ubuntu -- they require MacOS with Xcode
- DON'T run all targets sequentially -- use matrix parallelism
- DON'T skip Gradle caching for KMP -- multi-target builds are slow without it
- DON'T use `macos-latest` without pinning Xcode -- it may change between runs
