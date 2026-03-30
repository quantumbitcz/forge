# Spring + Error Prone

> Extends `modules/code-quality/errorprone.md` with Spring Boot-specific integration.
> Generic Error Prone conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Error Prone applies to Java compilation; for Kotlin use detekt's `potential-bugs` rule set instead. Add the compiler plugin to Java compilation tasks:

```kotlin
// build.gradle.kts
plugins {
    id("net.ltgt.errorprone") version "4.0.1"
}

dependencies {
    errorprone("com.google.errorprone:error_prone_core:2.28.0")
    // Nullaway for @Nullable propagation
    errorprone("com.uber.nullaway:nullaway:0.11.3")
}

tasks.withType<JavaCompile>().configureEach {
    options.errorprone {
        check("NullAway", CheckSeverity.ERROR)
        option("NullAway:AnnotatedPackages", "com.example")
        // Spring-specific suppressions
        check("ImmutableEnumChecker", CheckSeverity.OFF)
    }
}
```

## Framework-Specific Patterns

### Suppress `ImmutableEnumChecker` for `@ConfigurationProperties`

Error Prone's `ImmutableEnumChecker` fires on enums with mutable fields, but Spring `@ConfigurationProperties`-bound enums require setters or mutable state for property binding:

```kotlin
// Suppress for enums used as config values
@ConfigurationProperties(prefix = "app")
@SuppressWarnings("ImmutableEnumChecker")
enum class CacheStrategy { NONE, IN_MEMORY, REDIS }
```

Or disable globally in `build.gradle.kts` when `@ConfigurationProperties` enums are common:

```kotlin
options.errorprone {
    check("ImmutableEnumChecker", CheckSeverity.OFF)
}
```

### `@Nullable` handling with NullAway

Spring's `@Autowired` fields are non-null post-injection but NullAway sees them as potentially null. Use constructor injection to satisfy NullAway without suppression:

```java
// Preferred — NullAway compatible, no suppression needed
@Service
public class OrderService {
    private final OrderRepository repository;

    public OrderService(OrderRepository repository) {
        this.repository = repository;   // NullAway: provably non-null
    }
}

// Avoid — NullAway flags @Autowired field injection as potential null
@Service
public class OrderService {
    @Autowired
    @Nullable  // required to suppress NullAway warning
    private OrderRepository repository;
}
```

Configure NullAway to recognize Spring annotations as non-null initializers:

```kotlin
options.errorprone {
    option("NullAway:ExcludedFieldAnnotations",
        "org.springframework.beans.factory.annotation.Autowired," +
        "org.springframework.beans.factory.annotation.Value")
}
```

### Suppress false positives for Spring AOP proxies

Error Prone's `OverrideThrowableToString` and `DoNotMock` checks can fire on Spring proxy-generated classes. Exclude the `build/` output directory:

```kotlin
tasks.withType<JavaCompile>().configureEach {
    // Error Prone runs on compilation input, not generated class files
    // Exclude generated source directories to avoid duplicate analysis
    options.compilerArgs.add("-Xep:DoNotMock:OFF")  // Spring @MockBean conflicts
}
```

## Additional Dos

- Use constructor injection in Java Spring beans — it makes NullAway analysis deterministic and eliminates the need for `@Nullable` suppressions on injected fields.
- Suppress `ImmutableEnumChecker` selectively for enums bound via `@ConfigurationProperties` — not globally.
- Enable NullAway with `AnnotatedPackages` scoped to your domain packages, not Spring framework packages.

## Additional Don'ts

- Don't apply Error Prone to Kotlin source sets — the compiler plugin only hooks into `JavaCompile` tasks; Kotlin has its own null safety system.
- Don't suppress `FutureReturnValueIgnored` for Spring async methods — `@Async` return values should always be `CompletableFuture<T>` or `void`, not silently ignored.
- Don't disable `MustBeClosedChecker` globally — Spring JDBC `ResultSet` and `Stream` objects from `JdbcTemplate` must be closed in try-with-resources.
