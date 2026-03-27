# GitLab CI with Jetpack Compose

> Extends `modules/ci-cd/gitlab-ci.md` with Android + Jetpack Compose CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: cimg/android:2024.10.1

stages:
  - build
  - test
  - publish

variables:
  GRADLE_OPTS: "-Dorg.gradle.daemon=false"
  GRADLE_USER_HOME: "$CI_PROJECT_DIR/.gradle"

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .gradle/caches
    - .gradle/wrapper

build:
  stage: build
  script:
    - ./gradlew assembleDebug
  artifacts:
    paths:
      - app/build/outputs/apk/debug/*.apk
    expire_in: 1 hour

test:
  stage: test
  script:
    - ./gradlew testDebugUnitTest lintDebug detekt
  artifacts:
    reports:
      junit: app/build/test-results/testDebugUnitTest/*.xml
```

## Framework-Specific Patterns

### Android Docker Image

Use `cimg/android` or a custom Android SDK image. These include the SDK, build tools, and platform tools pre-installed.

```yaml
image: cimg/android:2024.10.1
```

Alternatively, use the official Gradle image and install the SDK:

```yaml
image: gradle:8.11-jdk21
before_script:
  - apt-get update && apt-get install -y android-sdk
```

### Instrumented Tests

```yaml
instrumented-test:
  stage: test
  tags:
    - android-emulator  # requires self-hosted runner with KVM
  script:
    - sdkmanager "system-images;android-34;google_apis;x86_64"
    - avdmanager create avd -n test -k "system-images;android-34;google_apis;x86_64" --force
    - emulator -avd test -no-audio -no-window &
    - adb wait-for-device
    - ./gradlew connectedDebugAndroidTest
  artifacts:
    reports:
      junit: app/build/outputs/androidTest-results/connected/*.xml
```

Instrumented tests require an Android emulator, which needs KVM support. This typically requires self-hosted runners with hardware virtualization.

### AAB Publishing

```yaml
publish:
  stage: publish
  script:
    - echo $KEYSTORE_BASE64 | base64 -d > keystore.jks
    - ./gradlew bundleProdRelease
        -Pandroid.injected.signing.store.file=$(pwd)/keystore.jks
        -Pandroid.injected.signing.store.password=$KEYSTORE_PASSWORD
        -Pandroid.injected.signing.key.alias=$KEY_ALIAS
        -Pandroid.injected.signing.key.password=$KEY_PASSWORD
    - gem install fastlane
    - fastlane supply
        --aab app/build/outputs/bundle/prodRelease/*.aab
        --track internal
        --json_key_data "$PLAY_SERVICE_ACCOUNT_JSON"
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

### Compose Compiler Reports

```yaml
compose-report:
  stage: build
  script:
    - ./gradlew assembleRelease
  artifacts:
    paths:
      - app/build/compose_compiler/
    expire_in: 30 days
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO use an Android-specific Docker image with SDK pre-installed
- DO disable Gradle daemon in CI (`-Dorg.gradle.daemon=false`)
- DO cache `.gradle/caches` and `.gradle/wrapper` keyed by branch
- DO use self-hosted runners with KVM for instrumented tests
- DO publish JUnit XML results for test trend tracking

## Additional Don'ts

- DON'T run instrumented tests on shared GitLab runners -- they lack KVM support
- DON'T embed keystore files in the repository -- use base64-encoded CI variables
- DON'T skip Compose compiler reports on `main` -- they help track recomposition regressions
- DON'T use `gradle daemon` in CI -- ephemeral runners don't benefit from it
