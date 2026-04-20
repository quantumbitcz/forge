# GitHub Actions with Jetpack Compose

> Extends `modules/ci-cd/github-actions.md` with Android + Jetpack Compose CI patterns.
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
    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
          cache: gradle

      - name: Setup Android SDK
        uses: android-actions/setup-android@v3

      - name: Lint
        run: ./gradlew lintDebug detekt

      - name: Unit Tests
        run: ./gradlew testDebugUnitTest

      - name: Build
        run: ./gradlew assembleDebug

      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: app/build/outputs/apk/debug/*.apk
```

## Framework-Specific Patterns

### Android SDK Setup

```yaml
- uses: android-actions/setup-android@v3
# Automatically installs SDK tools, platform-tools, and build-tools
# matching compileSdk from build.gradle.kts
```

The `android-actions/setup-android` action installs the Android SDK based on your project's `compileSdk`. It's simpler than manual `sdkmanager` calls.

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

Use both `actions/setup-java` (caches Gradle wrapper) and `gradle/actions/setup-gradle` (caches Gradle build cache). Set `cache-read-only` on PRs to prevent cache pollution.

### Instrumented Tests on Emulator

```yaml
instrumented-tests:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: actions/setup-java@v4
      with:
        distribution: temurin
        java-version: 21
        cache: gradle

    - name: Enable KVM
      run: |
        echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
        sudo udevadm control --reload-rules
        sudo udevadm trigger --name-match=kvm

    - name: Instrumented Tests
      uses: reactivecircus/android-emulator-runner@v2
      with:
        api-level: 34
        arch: x86_64
        profile: pixel_6
        script: ./gradlew connectedDebugAndroidTest
```

KVM acceleration is required for acceptable emulator performance on GitHub Actions runners. Enable it before starting the emulator.

### AAB Publishing (Release)

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

    - name: Build Release AAB
      run: ./gradlew bundleProdRelease
      env:
        KEYSTORE_FILE: ${{ secrets.KEYSTORE_BASE64 }}
        KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
        KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
        KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}

    - uses: r0adkll/upload-google-play@v1
      with:
        serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT }}
        packageName: com.example.app
        releaseFiles: app/build/outputs/bundle/prodRelease/*.aab
        track: internal
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
  publish_workflow: ".github/workflows/publish.yml"
```

## Additional Dos

- DO use `android-actions/setup-android` for SDK management
- DO enable KVM acceleration for emulator-based instrumented tests
- DO use `gradle/actions/setup-gradle` with `cache-read-only` on PRs
- DO build AAB (not APK) for Google Play distribution
- DO use `r0adkll/upload-google-play` for automated Play Store uploads

## Additional Don'ts

- DON'T skip KVM setup for instrumented tests -- emulator is unusably slow without it
- DON'T embed keystore files in the repository -- use base64-encoded secrets
- DON'T run instrumented tests on every PR -- they're slow; reserve for main branch
- DON'T publish APKs to Google Play -- use AAB format for app size optimization
