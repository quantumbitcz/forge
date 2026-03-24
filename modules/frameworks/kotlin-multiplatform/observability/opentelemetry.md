# Observability with Kotlin Multiplatform

## Integration Setup

```kotlin
// Kermit — KMP-first structured logger
commonMain.dependencies {
    implementation("co.touchlab:kermit:2.0.4")
    implementation("co.touchlab:kermit-crashlytics:2.0.4")   // crash bridge (optional)
}

// Ktor client monitoring plugin (built-in)
implementation("io.ktor:ktor-client-logging:2.3.11")
```

> Full OTel SDK KMP support is in active development (opentelemetry-kotlin).
> Use Kermit + platform bridges as the stable alternative until the KMP SDK reaches stable.

## Framework-Specific Patterns

### Kermit Logger Setup (commonMain)
```kotlin
// commonMain
val logger = Logger(
    config = StaticConfig(minSeverity = Severity.Debug),
    tag    = "AppLogger"
)

// Usage
logger.d { "Fetching todos for user $userId" }
logger.e(throwable) { "Failed to sync todos" }
logger.w { "Cache miss for key=$key, fetching from network" }
```

### expect/actual for Platform Crash Reporting
```kotlin
// commonMain
expect fun initializeCrashReporting()
expect fun recordNonFatalException(t: Throwable, context: Map<String, String> = emptyMap())

// androidMain — Firebase Crashlytics
actual fun initializeCrashReporting() = FirebaseCrashlytics.getInstance().setCrashlyticsCollectionEnabled(true)
actual fun recordNonFatalException(t: Throwable, ctx: Map<String, String>) {
    ctx.forEach { (k, v) -> FirebaseCrashlytics.getInstance().setCustomKey(k, v) }
    FirebaseCrashlytics.getInstance().recordException(t)
}

// iosMain — Firebase Crashlytics via Swift interop
actual fun initializeCrashReporting() { /* call FirebaseCrashlytics.crashlytics().setCrashlyticsCollectionEnabled(true) */ }
actual fun recordNonFatalException(t: Throwable, ctx: Map<String, String>) { /* bridge to ObjC */ }
```

### Ktor Client Monitoring
```kotlin
val client = HttpClient(engine) {
    install(Logging) {
        logger = object : io.ktor.client.plugins.logging.Logger {
            override fun log(message: String) { logger.d { message } }
        }
        level = if (BuildKonfig.DEBUG) LogLevel.HEADERS else LogLevel.NONE
        // Sanitize: don't log Authorization header
        sanitizeHeader { header -> header == HttpHeaders.Authorization }
    }
}
```

### Manual Span Emulation (until OTel KMP stable)
```kotlin
suspend fun <T> traced(name: String, tags: Map<String, String> = emptyMap(), block: suspend () -> T): T {
    val start = Clock.System.now()
    logger.d { "[$name] start ${tags.entries.joinToString { "${it.key}=${it.value}" }}" }
    return try {
        block().also {
            logger.d { "[$name] completed in ${Clock.System.now() - start}" }
        }
    } catch (e: Exception) {
        logger.e(e) { "[$name] failed" }
        recordNonFatalException(e, tags)
        throw e
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  logger:          "commonMain/kotlin/.../observability/AppLogger.kt"
  crash_reporting: "commonMain/kotlin/.../observability/CrashReporting.kt"
  traced_helper:   "commonMain/kotlin/.../observability/Tracing.kt"
```

## Additional Dos/Don'ts

- DO use Kermit for all logging in `commonMain`; it bridges to native loggers per platform
- DO add crash reporting via `expect/actual` so each platform uses its native SDK
- DO sanitize the `Authorization` header in Ktor `Logging` to avoid logging tokens
- DO use `traced {}` wrapper for critical business flows until OTel KMP SDK is stable
- DON'T log PII (names, emails, device IDs) — apply user consent rules before logging
- DON'T use `println` in KMP code; it bypasses log levels and isn't filterable on iOS
- DON'T initialize crash reporting before user consent if required by your privacy policy (GDPR)
