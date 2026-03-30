# Spring + detekt

> Extends `modules/code-quality/detekt.md` with Spring Boot-specific integration.
> Generic detekt conventions (rule categories, configuration patterns, CI integration) are NOT repeated here.

## Integration Setup

Apply detekt in the shared convention plugin alongside Spring Boot, not per-module:

```kotlin
// build-logic/src/main/kotlin/spring-conventions.gradle.kts
plugins {
    id("io.gitlab.arturbosch.detekt")
}

detekt {
    config.setFrom(files("$rootDir/config/detekt.yml"))
    buildUponDefaultConfig = true
    source.setFrom("src/main/kotlin", "src/test/kotlin")  // exclude build/generated
}
```

Exclude the Gradle build output — Spring annotation processors (MapStruct, Hibernate metamodel, OpenAPI generator) emit code into `build/generated/`:

```kotlin
detekt {
    source.setFrom(
        fileTree("src/main/kotlin"),
        fileTree("src/test/kotlin")
    )
    // Do NOT include build/generated/ — contains processor output
}
```

## Framework-Specific Patterns

### Suppress MagicNumber in `@Value` defaults

`@Value("${timeout.ms:30000}")` uses integer literals that detekt flags as `MagicNumber`. Suppress at the property level:

```kotlin
@Value("\${service.timeout.ms:30000}")
@Suppress("MagicNumber")
private val timeoutMs: Long = 30_000
```

Or configure `detekt.yml` to exclude `@Value`-annotated properties:

```yaml
style:
  MagicNumber:
    ignoreAnnotated: ['Value', 'ConfigurationProperties']
    excludes: ['**/test/**', '**/it/**']
```

### Disable detekt-formatting when ktlint is active

Running both `detekt-formatting` and `ktlint` on the same source set causes duplicate formatting violations. Remove the `detekt-formatting` plugin when ktlint is in use:

```kotlin
// build.gradle.kts — omit this dependency when ktlint is present
// detektPlugins("io.gitlab.arturbosch.detekt:detekt-formatting:1.23.7")
```

The `@Transactional` annotation on use case implementations (not interfaces) can exceed `LongMethod` thresholds in orchestration classes. Use baseline exclusion rather than global threshold relaxation:

```yaml
complexity:
  LongMethod:
    threshold: 60
    excludes: ['**/usecase/**/*UseCase.kt']
```

### `@Transactional` scope rules

Detekt's `FunctionNaming` rule conflicts with Spring integration test method names that use backticks:

```kotlin
// Integration test — Kotlin backtick names are idiomatic
@Test
fun `should commit transaction when use case succeeds`() { … }
```

Exclude test sources from `FunctionNaming`:

```yaml
naming:
  FunctionNaming:
    excludes: ['**/test/**', '**/it/**']
```

## Additional Dos

- Exclude `build/generated/` from `source.setFrom()` — Spring annotation processors produce code that fails detekt legitimately.
- Use `ignoreAnnotated: ['Value']` for `MagicNumber` — `@Value` defaults are not magic numbers.
- Run `detektMain` and `detektTest` separately; use relaxed `LongMethod`/`TooManyFunctions` thresholds for `detektTest`.

## Additional Don'ts

- Don't include `detekt-formatting` when ktlint is active — duplicate violations cause confusion and slow CI.
- Don't suppress `LateinitUsage` globally — Spring `@Autowired lateinit var` is legacy; prefer constructor injection.
- Don't raise `TooManyFunctions` threshold for `@Configuration` classes — split large configs into focused `@Configuration` beans instead.
