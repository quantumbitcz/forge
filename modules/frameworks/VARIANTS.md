# Framework Variant Analysis

This document records the variant analysis for each of the 21 supported frameworks.
A "variant" is a separate conventions file within `variants/` that captures meaningful
architectural differences within the same framework, beyond mere language syntax.

## Existing Variants

### Spring: kotlin / java
- **Rationale:** Kotlin variant uses hexagonal architecture with sealed interfaces, ports & adapters.
  Java variant uses layered architecture with standard Spring patterns. The architectural
  differences are significant enough to warrant separate convention files.
- **Files:** `variants/kotlin.md`, `variants/java.md`

## Frameworks That Do NOT Need Additional Variants

### Single-Language Variant (Identity Variant)

Most frameworks ship a single variant file matching their primary language. This is an
identity variant (e.g., `react/variants/typescript.md`) that carries language-specific
conventions applied on top of the framework conventions. These are NOT architectural
variants in the Spring sense -- they are the standard configuration.

### React, Next.js, Express, NestJS, SvelteKit, Svelte, Vue, Angular
- **Rationale:** These frameworks are TypeScript-first. JavaScript usage is legacy and declining.
  The convention differences between TS and JS are limited to type annotations and build config,
  which are handled by the language module (`modules/languages/typescript.md`). A separate
  JS variant would duplicate 95% of content.
- **Exception:** If a project explicitly uses JavaScript without TypeScript, the language detection
  in `engine.sh` already handles this (`.js`/`.jsx` map to `typescript` language module which
  covers both).

### FastAPI, Django
- **Rationale:** Python-only. No meaningful variant axis. Both use the `python` variant.

### Axum
- **Rationale:** Rust-only. No variant axis.

### SwiftUI, Vapor
- **Rationale:** Swift-only. No variant axis.

### Embedded
- **Rationale:** C-only. No variant axis. If C++ embedded support is added, it would be a
  separate framework module, not a variant (the build system and safety constraints differ
  fundamentally).

### Go-stdlib, Gin
- **Rationale:** Go-only. No variant axis.

### ASP.NET
- **Rationale:** C#-only in practice. F# is theoretically possible but would be a separate
  framework module, not a variant.

### Jetpack Compose, Kotlin Multiplatform
- **Rationale:** Kotlin-only. Platform target (Android/iOS/Desktop/Web) is handled by the
  framework's conventions directly, not via variants.

### K8s
- **Rationale:** Infrastructure, no application language. No variant axis. Uses no variant file.

## Future Variant Candidates

None currently identified. If a framework develops a meaningful architectural axis
(not just language syntax differences), add a variant directory with conventions.
A variant is warranted when:

1. The architectural patterns differ fundamentally (e.g., hexagonal vs layered)
2. The code review rules would conflict if combined in a single file
3. The differences go beyond what language modules can express
