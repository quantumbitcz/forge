# Azure Pipelines with Spring

> Extends `modules/ci-cd/azure-pipelines.md` with Spring Boot CI patterns.
> Generic Azure Pipelines conventions (stages, tasks, variable groups) are NOT repeated here.

## Integration Setup

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include: [main]

pool:
  vmImage: ubuntu-latest

variables:
  GRADLE_OPTS: '-Dorg.gradle.daemon=false'

stages:
  - stage: Build
    jobs:
      - job: BuildAndTest
        steps:
          - task: JavaToolInstaller@0
            inputs:
              versionSpec: '21'
              jdkArchitectureOption: x64
              jdkSourceOption: PreInstalled

          - task: Gradle@3
            inputs:
              gradleWrapperFile: gradlew
              tasks: build
              publishJUnitResults: true
              testResultsFiles: '**/TEST-*.xml'
              javaHomeOption: JDKVersion
              jdkVersionOption: '1.21'
```

## Framework-Specific Patterns

### Testcontainers in Azure Pipelines

Azure-hosted agents include Docker. Testcontainers works directly -- no Docker-in-Docker needed.

```yaml
- script: ./gradlew integrationTest
  displayName: Integration Tests
  env:
    TESTCONTAINERS_RYUK_DISABLED: 'true'
```

### Maven Build

```yaml
- task: Maven@4
  inputs:
    mavenPomFile: pom.xml
    goals: 'verify'
    options: '-B'
    publishJUnitResults: true
    testResultsFiles: '**/TEST-*.xml'
    javaHomeOption: JDKVersion
    jdkVersionOption: '1.21'
```

### Gradle Caching

```yaml
- task: Cache@2
  inputs:
    key: 'gradle | "$(Agent.OS)" | **/build.gradle.kts | gradle/libs.versions.toml'
    restoreKeys: |
      gradle | "$(Agent.OS)"
    path: $(GRADLE_USER_HOME)/caches

- task: Cache@2
  inputs:
    key: 'gradle-wrapper | "$(Agent.OS)" | gradle/wrapper/gradle-wrapper.properties'
    path: $(GRADLE_USER_HOME)/wrapper
```

### Multi-Stage Pipeline with Azure Artifacts

```yaml
stages:
  - stage: Build
    jobs:
      - job: Build
        steps:
          - task: Gradle@3
            inputs:
              tasks: build bootJar
          - publish: build/libs
            artifact: spring-boot-jar

  - stage: Publish
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: PublishImage
        steps:
          - download: current
            artifact: spring-boot-jar
          - task: Docker@2
            inputs:
              containerRegistry: $(dockerRegistryServiceConnection)
              repository: $(imageRepository)
              command: buildAndPush
              Dockerfile: Dockerfile
              tags: $(Build.SourceVersion)
```

### Spring Native Build

```yaml
- stage: NativeBuild
  condition: eq(variables['Build.SourceBranch'], 'refs/heads/main')
  jobs:
    - job: NativeCompile
      timeoutInMinutes: 30
      steps:
        - script: |
            curl -sL https://get.graalvm.org/jdk | bash -s -- graalvm-community-jdk-21
            export JAVA_HOME=$HOME/graalvm-community-openjdk-21
            ./gradlew nativeCompile
          displayName: GraalVM Native Build
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "azure-pipelines.yml"
```

## Additional Dos

- DO use the built-in `Gradle@3` and `Maven@4` tasks for automatic JUnit result publishing
- DO use `Cache@2` task with composite keys including `libs.versions.toml` for Gradle
- DO publish build artifacts between stages with `publish`/`download` tasks
- DO use Azure Artifacts feed for internal Spring Boot library distribution

## Additional Don'ts

- DON'T use `script` task for Gradle/Maven when a built-in task exists -- you lose JUnit integration
- DON'T cache the entire Gradle home -- cache only `caches` and `wrapper` subdirectories
- DON'T run native builds on every PR -- limit to `main` branch with a `condition`
