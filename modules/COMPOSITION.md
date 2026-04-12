# Module Composition

Defines how convention files are loaded, composed, and prioritized when agents build the convention stack for a project component.

## Composition Order (highest priority first)

1. **Framework variant** — `modules/frameworks/{fw}/variants/{lang}.md` (e.g., `spring/variants/kotlin.md`)
2. **Framework binding** — `modules/frameworks/{fw}/{layer}/{tool}.md` (e.g., `spring/persistence/exposed.md`)
3. **Framework core** — `modules/frameworks/{fw}/conventions.md` (e.g., `spring/conventions.md`)
4. **Language** — `modules/languages/{lang}.md` (e.g., `languages/kotlin.md`)
5. **Testing framework** — `modules/testing/{test-fw}.md` (e.g., `testing/kotest.md`)
6. **Domain modules** — `modules/{layer}/{tool}.md` (e.g., `persistence/exposed.md`, `databases/postgresql.md`)
7. **Code quality tools** — `modules/code-quality/{tool}.md` (e.g., `code-quality/eslint.md`)
8. **Build/CI/Container** — `modules/build-systems/{bs}.md`, `modules/ci-cd/{ci}.md`, `modules/container-orchestration/{co}.md`

**Most specific wins.** When two files provide guidance on the same topic, the higher-priority file's guidance takes precedence.

## Conflict Resolution

When two convention files provide conflicting guidance:

- **Additive sections** (Dos, Don'ts, Patterns, Anti-Patterns): both apply — entries are merged.
- **Override sections** (Configuration, Integration Setup, Scaffolder Patterns): the higher-priority file replaces the lower-priority file's section entirely.
- **Explicit contradiction:** when a binding explicitly contradicts its generic layer (e.g., different implementation strategy), the binding wins.

See `shared/agent-communication.md` §9 for the full composition protocol.

## Soft Cap

Convention stacks are capped at **12 files per component** to control token costs. Each agent `.md` file is loaded as the subagent system prompt — every convention file adds to the token budget.

If a component's stack exceeds 12 files, the orchestrator trims from the bottom of the priority order (code quality tools first, then build/CI, then domain modules) until within budget. A WARNING is logged with the trimmed files.

## Module Overviews

Each module's overview section (the first paragraph or `## Overview` section) must stay under **15 lines**. This ensures the convention stack stays within token ceilings even for complex multi-framework projects.

## Worked Example

**Project:** Spring Boot + Kotlin + Gradle + PostgreSQL + Exposed ORM + Kotest + Testcontainers + GitHub Actions

**Resolved convention stack (8 files):**

| Priority | File | Purpose |
|----------|------|---------|
| 1 | `frameworks/spring/variants/kotlin.md` | Sealed interfaces, typed IDs, extension functions |
| 2 | `frameworks/spring/persistence/exposed.md` | Spring + Exposed integration patterns |
| 3 | `frameworks/spring/conventions.md` | Hexagonal arch, dependency rules, error handling |
| 4 | `languages/kotlin.md` | Coroutines, null safety, sealed classes |
| 5 | `testing/kotest.md` | ShouldSpec, data-driven, property-based testing |
| 6 | `persistence/exposed.md` | Generic Exposed ORM patterns |
| 7 | `databases/postgresql.md` | Connection pooling, JSONB, advisory locks |
| 8 | `build-systems/gradle.md` | Convention plugins, version catalogs |

Additional files that may be loaded conditionally (within the 12-file cap):
- `testing/testcontainers.md` — if integration tests are detected
- `ci-cd/github-actions.md` — if `.github/workflows/` exists
- `code-quality/detekt.md` — if `detekt.yml` or `build.gradle.kts` references detekt

**Total: 8-11 files** — well within the 12-file soft cap.

## Variant Strategy

Not all frameworks have variants. Variants exist when language-specific idioms significantly change the framework's usage patterns:

| Framework | Variants | Reason |
|-----------|----------|--------|
| Spring | `kotlin.md`, `java.md` | Hexagonal arch diverges: sealed interfaces (Kotlin) vs records (Java) |
| SvelteKit | — | TypeScript-only ecosystem, no variant needed |
| Next.js | — | TypeScript-first, no significant language divergence |
| React | — | TypeScript-dominant, vanilla JS is legacy |
| Angular | — | TypeScript-only by design |

Variants are justified when the language choice changes architectural patterns (not just syntax). If the only difference is syntax, the language module handles it.

## Framework Bindings

Framework bindings connect a framework to specific tools in other layers. They live in subdirectories of the framework:

```
modules/frameworks/spring/
├── conventions.md          # Core framework conventions
├── variants/
│   ├── kotlin.md           # Kotlin-specific Spring patterns
│   └── java.md             # Java-specific Spring patterns
├── persistence/
│   ├── exposed.md          # Spring + Exposed ORM
│   └── jpa.md              # Spring + JPA/Hibernate
├── web/
│   └── htmx.md             # Spring + HTMX
└── testing/
    └── testcontainers.md   # Spring + Testcontainers
```

Bindings EXTEND generic layer modules. A project using Spring + Exposed loads both `persistence/exposed.md` (generic) AND `spring/persistence/exposed.md` (binding). The binding adds Spring-specific integration patterns on top of the generic ORM guidance.

## Config-Driven Loading

The convention stack is determined by `forge.local.md` component configuration:

```yaml
components:
  backend:
    language: kotlin
    framework: spring
    variant: kotlin
    testing: kotest
    persistence: exposed
    database: postgresql
    build_system: gradle
    ci: github-actions
```

Each field maps to a module path. The orchestrator resolves the full stack at PREFLIGHT and stores the SHA-256 hash in `state.json.components.{name}.conventions_hash` for mid-run drift detection.
