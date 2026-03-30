# Spring + PiTest

> Extends `modules/code-quality/pitest.md` with Spring Boot-specific integration.
> Generic PiTest conventions (installation, mutator selection, thresholds, incremental analysis) are NOT repeated here.

## Integration Setup

PiTest with Kotlin requires the `pitest-kotlin` bridge. Target domain classes only — Spring infrastructure is not worth mutating:

```kotlin
// build.gradle.kts
plugins {
    id("info.solidsoft.pitest") version "1.15.0"
}

dependencies {
    testImplementation("org.pitest:pitest-kotlin:1.2.0")
}

pitest {
    pitestVersion = "1.16.1"
    junit5PluginVersion = "1.2.1"
    targetClasses = setOf(
        "com.example.domain.*",
        "com.example.service.*",
        "com.example.usecase.*"
    )
    excludedClasses = setOf(
        "*.config.*",            // @Configuration classes
        "*.*Application",        // Spring Boot entry point
        "*.generated.*",         // annotation processor output
        "*.*Dto",                // data carriers — no logic to mutate
        "*.*Mapper",             // MapStruct generated implementations
        "*.*Repository"          // Spring Data interfaces — no source
    )
    mutationThreshold = 60
    outputFormats = setOf("HTML", "XML")
    withHistory = true
}
```

## Framework-Specific Patterns

### Exclude `@Configuration` classes

`@Configuration` classes contain bean wiring, not business logic. Mutations to them test Spring's DI machinery, not your code:

```kotlin
pitest {
    excludedClasses = setOf(
        "*.config.*",
        "**.*Config",
        "**.*Configuration"
    )
}
```

### `@SpringBootTest` separation

`@SpringBootTest` integration tests load the full Spring context (~5-30 seconds startup). Do not use them as PiTest's test suite — use unit tests with mocks instead:

```kotlin
pitest {
    // Restrict to fast unit tests — exclude @SpringBootTest integration tests
    excludedTestClasses = setOf(
        "*IT",           // integration test convention
        "*IntegrationTest",
        "*E2ETest"
    )
    targetTests = setOf(
        "com.example.*Test",   // only unit tests
        "com.example.*Spec"    // Kotest specs
    )
}
```

Keep `@SpringBootTest` in a separate `integrationTest` source set so PiTest never discovers them automatically.

### Kotlin pitest setup

The `pitest-kotlin` bridge is required for Kotlin bytecode mutation. Without it, PiTest analyzes the compiled Kotlin bytecode with Java mutators and misses Kotlin-specific constructs (data class `copy()`, sealed class exhaustiveness):

```kotlin
dependencies {
    // Required — enables Kotlin-aware mutation operators
    testImplementation("org.pitest:pitest-kotlin:1.2.0")
}

pitest {
    // Kotlin data class copy() is compiler-generated — exclude from mutation
    excludedMethods = setOf("copy", "component1", "component2", "component3")
}
```

### Handling slow `@Transactional` tests

PiTest forks a JVM per mutant and runs the full test suite per fork. `@Transactional` rollback tests in Spring are slow under mutation. Keep mutation targets in pure domain/service classes tested without Spring context:

```kotlin
pitest {
    threads = 4
    timeoutConstant = 8000L   // spring context-free tests are still slow in mutation forks
    timeoutFactor = 2.0
}
```

## Additional Dos

- Target `domain.*`, `service.*`, `usecase.*` packages — these contain the logic worth mutating.
- Use `excludedTestClasses` to exclude integration and E2E tests from PiTest's test discovery.
- Enable `pitest-kotlin` bridge — without it, Kotlin-specific bytecode patterns produce misleading mutation scores.

## Additional Don'ts

- Don't mutate `@Configuration`, `@Entity`, or `*Dto` classes — they contain no conditional logic to kill.
- Don't run PiTest with `@SpringBootTest` as the test suite — context startup time makes each mutation run minutes-long.
- Don't set `mutationThreshold` above 80% on first adoption — start at 60% and raise as dead tests are replaced with assertions.
