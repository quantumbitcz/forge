# GitLab CI with Kotlin Multiplatform

> Extends `modules/ci-cd/gitlab-ci.md` with KMP multi-target CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
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

build-jvm:
  stage: build
  image: eclipse-temurin:21-jdk
  script:
    - ./gradlew :shared:jvmJar
  artifacts:
    paths:
      - shared/build/libs/*.jar
    expire_in: 1 hour

build-android:
  stage: build
  image: cimg/android:2024.10.1
  script:
    - ./gradlew :androidApp:assembleDebug
  artifacts:
    paths:
      - androidApp/build/outputs/apk/debug/*.apk
    expire_in: 1 hour
```

## Framework-Specific Patterns

### iOS Build on macOS Runner

```yaml
build-ios:
  stage: build
  tags:
    - macos
    - xcode
  before_script:
    - sudo xcode-select -s /Applications/Xcode_16.2.app
  script:
    - ./gradlew :shared:iosSimulatorArm64Test
    - ./gradlew :shared:assembleXCFramework
  artifacts:
    paths:
      - shared/build/XCFrameworks/
    expire_in: 7 days
```

iOS targets require self-hosted macOS runners with Xcode. Tag them with `macos` and `xcode`.

### JVM and Common Tests

```yaml
test-jvm:
  stage: test
  image: eclipse-temurin:21-jdk
  script:
    - ./gradlew :shared:jvmTest
  artifacts:
    reports:
      junit: shared/build/test-results/jvmTest/*.xml

test-android:
  stage: test
  image: cimg/android:2024.10.1
  script:
    - ./gradlew :shared:testDebugUnitTest
  artifacts:
    reports:
      junit: shared/build/test-results/testDebugUnitTest/*.xml
```

### Lint and Static Analysis

```yaml
lint:
  stage: build
  image: eclipse-temurin:21-jdk
  script:
    - ./gradlew lintKotlin detekt
```

### Maven Publishing

```yaml
publish-jvm:
  stage: publish
  image: eclipse-temurin:21-jdk
  script:
    - ./gradlew :shared:publishJvmPublicationToMavenRepository
  rules:
    - if: $CI_COMMIT_TAG
  variables:
    MAVEN_REPO_URL: $CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/maven
    MAVEN_REPO_USER: gitlab-ci-token
    MAVEN_REPO_TOKEN: $CI_JOB_TOKEN
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO use self-hosted macOS runners for iOS targets
- DO run JVM and Android tests on Linux runners for faster execution
- DO disable Gradle daemon in CI (`-Dorg.gradle.daemon=false`)
- DO cache `.gradle/caches` and `.gradle/wrapper` keyed by branch
- DO publish JUnit XML results for test trend tracking

## Additional Don'ts

- DON'T run iOS builds on shared Linux runners -- they require macOS with Xcode
- DON'T run all targets in a single job -- split by platform for parallelism
- DON'T skip Gradle caching for KMP -- multi-target builds are slow
- DON'T use `gradle daemon` in CI -- ephemeral runners don't benefit from it
