# Kotlin Multiplatform Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with KMP-specific patterns.

## Code Documentation

- Use KDoc for all `expect` declarations — they are the platform-agnostic API. `actual` implementations need doc only if they diverge from the `expect` contract.
- `commonMain` public API: document as you would any Kotlin library — every public class, function, and property.
- `expect`/`actual` pairs: document in `expect`; note in `actual` only when the platform implementation has non-obvious behavior or limitations.
- `@Throws` annotations on `suspend` functions shared with iOS/Swift: document the exception types — Swift callers cannot use Kotlin flow for errors.
- Ktor client usage in `commonMain`: document base URL, auth scheme, and retry policy.

```kotlin
/**
 * Retrieves the coaching session for the given [sessionId].
 *
 * @param sessionId The unique session identifier.
 * @return The session data or null if not found.
 * @throws NetworkException if the request fails after retry.
 */
expect suspend fun getSession(sessionId: SessionId): Session?
```

## Architecture Documentation

- Document the source set layout: `commonMain`, `androidMain`, `iosMain`, `jvmMain` — what each contains and why platform-specific code lives there.
- Document `expect`/`actual` split decisions: which APIs are platform-split and why they cannot be commonized.
- Document the shared business logic boundary: what is in `commonMain` vs what is intentionally platform-specific.
- Document Gradle multiplatform targets and the minimum supported platform versions.
- KMP + Compose Multiplatform: document shared UI vs platform-specific UI boundaries.

## Diagram Guidance

- **Source set graph:** Mermaid class diagram showing source set relationships (`commonMain` → `androidMain`, `iosMain`).
- **Shared vs platform-specific:** Table listing major components and their source set placement.

## Dos

- KDoc on all `expect` declarations — iOS and Android callers share this as their only API reference
- Document `@Throws` on `suspend` functions exposed to Swift — required for safe Swift interop
- Document Gradle version catalog usage — shared dependency versions are a multiplatform concern

## Don'ts

- Don't duplicate `actual` docs when they match the `expect` contract exactly
- Don't omit source set placement rationale — `commonMain` vs platform-specific is an architectural decision
