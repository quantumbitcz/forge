# Kotlin/Spring Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (Hexagonal / Ports & Adapters)

| Module | Responsibility | Dependencies |
|--------|---------------|--------------|
| `core` | Domain models, use cases, port interfaces | spring-context, spring-tx only |
| `adapter/input/api` | REST controllers, OpenAPI codegen | core |
| `adapter/output/postgresql` | R2DBC persistence, Flyway migrations | core |
| `app` | Spring Boot entry point, test infrastructure | all modules |

**Dependency rule:** Core never imports from adapters. Adapters depend on core via port interfaces.

## Domain Model Pattern

Sealed interface hierarchy per entity:
- `sealed interface Xxx` — core properties
- `sealed interface XxxPersisted : Xxx` — adds typed ID + `createdAt`/`updatedAt`
- `sealed interface XxxNotPersisted : Xxx` — no ID
- `data class XxxPersistedImpl`, `XxxNotPersistedImpl` — implementations
- `@JvmInline value class XxxId(val value: Uuid)` — typed ID with `toJavaUuid()`/`toXxxId()` extensions
- `CreateXxxCommand`, `UpdateXxxCommand` — use cases accept commands, not domain types

Nullable `?` for optional fields. Ports return `T?`, use `findOrThrow()` for required lookups.

## Naming Patterns

| Artifact | Pattern | Annotation |
|----------|---------|------------|
| Use case interface | `ICreateXxxUseCase` | — |
| Use case impl | `ICreateXxxUseCaseImpl` | `@UseCase` + `@Transactional` |
| Read use case impl | `IFindXxxUseCaseImpl` | `@UseCase` + `@Transactional(readOnly = true)` |
| Port interface | `ICreateXxxPort`, `IFindXxxPort` | `fun interface` (single-method) |
| Persistence adapter | `CreateXxxPersistenceAdapter` | `@Adapter` |
| Entity | `XxxEntity` | `@Table` + `@Id` + `@Column` |
| Repository | `XxxRepository` | extends `CoroutineCrudRepository<XxxEntity, UUID>` |
| Persistence mapper | `XxxMapper.kt` (extension fns) | `toDomain()`, `toEntity()` |
| Controller mapper | `XxxMapper.kt` (extension fns) | `toResponse()`, `toCommand()` |

## Core Package Structure

```
core/
  domain/{area}/          # Sealed interfaces, typed IDs, commands
  input/usecase/{area}/   # Use case interfaces
  output/port/{area}/     # Port interfaces
  impl/{area}/            # Use case implementations
```

## Kotlin-First

- **Types:** `kotlin.uuid.Uuid` (domain), `java.util.UUID` (persistence only). `kotlinx.datetime.Instant` (domain), `java.time.Instant` (persistence only).
- **Conversions:** `toJavaUuid()`/`toXxxId()` for IDs, `toJavaInstant()`/`toKotlinInstant()` for timestamps.
- **Idioms:** Extension functions, data classes, sealed interfaces, `when` expressions, trailing commas required.
- **Nullability:** No `!!` ever. Use `?: throw NoSuchElementException(...)` or `requireNotNull()`.

## Reactive Stack

- WebFlux + R2DBC (not WebMVC + JPA)
- All use case and port methods are `suspend` functions
- `Flow` from repositories converted to `List` at adapter boundary
- `CoroutineCrudRepository` (not `ReactiveCrudRepository`)
- R2DBC updates ALL columns — update adapters must fetch existing entity to preserve `createdAt`

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- KDoc on public interfaces (use cases, ports) — explain WHY, not WHAT
- No `!!`, no `println`/`System.out` in production code
- No `@Transactional` on adapters — only on use case impls
- `@UseCase` and `@Adapter` meta-annotations instead of `@Component`/`@Service`
- MaxLineLength: 150 (editorconfig + detekt)

## Testing

- **Framework:** Kotest `ShouldSpec` on JUnit Platform (not JUnit 5 directly)
- **API tests:** Custom `@RestIntegrationTest` annotation — WebTestClient + PostgreSQL + Keycloak Testcontainers
- **Persistence tests:** `@PersistenceIntegrationTest` — SpringBootTest + PostgreSQL Testcontainer
- **Factories:** `testFixtures` source set — `createUser(...)`, `createChatMessage(...)` etc.
- **Auth:** Keycloak test realm with `test-coach`/`password` and `test-client`/`password`
- **Rules:** Test behavior not implementation, no duplicate scenarios, one assertion focus per test

## Security

- JWT Bearer auth via Keycloak, roles mapped by `RealmRoleJwtAuthenticationConverter`
- Path rules: `/me/**` -> client role, most paths -> coach role
- `AuthenticatedUserProvider.currentUserId()` for current user — never trust request body userId
- Coach endpoints must verify coaching relationship before accessing client data
- Enterprise endpoints must verify membership

## Data Access

- JSON columns: `io.r2dbc.postgresql.codec.Json` — mappers convert between `Json` and `String`
- Parameterized queries only — no string interpolation in SQL
- Flyway migrations: `V{N}__{description}.sql`
- Entities: `@Table`/`@Column`/`@Id` + `@CreatedDate`/`@LastModifiedDate` auditing

## Error Handling

| Domain Exception | HTTP Status |
|-----------------|-------------|
| `NoSuchElementException` | 404 |
| `IllegalArgumentException` | 400 |
| `IllegalStateException` | 409 |
| `DuplicateEntityException` | 409 |
| `DomainAccessDeniedException` | 403 |

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.
