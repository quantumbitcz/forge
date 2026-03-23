# Spring Boot + Kotlin Variant

> Extends `modules/frameworks/spring/conventions.md` with Kotlin-specific Spring patterns.
> General Kotlin idioms are in `modules/languages/kotlin.md` — not duplicated here.

## Domain Model Pattern

Sealed interface hierarchy per entity:
- `sealed interface Xxx` — core properties shared across states
- `sealed interface XxxPersisted : Xxx` — adds typed ID + `createdAt` / `updatedAt`
- `sealed interface XxxNotPersisted : Xxx` — no ID (pre-persistence)
- `data class XxxPersistedImpl`, `XxxNotPersistedImpl` — concrete implementations
- `@JvmInline value class XxxId(val value: Uuid)` — typed ID with `toJavaUuid()` / `toXxxId()` extensions
- `CreateXxxCommand`, `UpdateXxxCommand` — use cases accept commands, not raw domain types

## Kotlin-First Type Boundaries

- **Core layer:** `kotlin.uuid.Uuid`, `kotlinx.datetime.Instant`, Kotlin nullable `T?`
- **Persistence layer:** `java.util.UUID`, `java.time.Instant` (R2DBC/JPA driver requirements)
- **Conversions:** `toJavaUuid()` / `toKotlinUuid()` for IDs; `toJavaInstant()` / `toKotlinInstant()` for timestamps
- Ports return `T?` for optional lookups; use `?: throw NoSuchElementException(...)` for required lookups

## Reactive Stack (WebFlux + R2DBC)

- All use case and port methods are `suspend` functions
- `Flow<T>` from repositories converted to `List<T>` at adapter boundary
- Use `CoroutineCrudRepository` (not `ReactiveCrudRepository`) — native coroutine support
- R2DBC `UPDATE` sets ALL columns — use `@Query` for partial updates; fetch existing entity to preserve `createdAt`
- No lazy loading in R2DBC — all associations must be explicitly fetched
- Transactions in coroutines: `@Transactional` on suspend functions (Spring 6+ supports this natively)

## Naming Overrides

| Artifact | Spring+Kotlin Pattern |
|----------|----------------------|
| Use case interface | `ICreateXxxUseCase` (fun interface, single-method) |
| Use case impl | `ICreateXxxUseCaseImpl` with `@UseCase` + `@Transactional` |
| Port interface | `ICreateXxxPort`, `IFindXxxPort` (fun interface) |
| Persistence adapter | `CreateXxxPersistenceAdapter` with `@Adapter` |
| Repository | extends `CoroutineCrudRepository<XxxEntity, UUID>` |
| Mapper | extension functions in `XxxMapper.kt`: `toDomain()`, `toEntity()`, `toResponse()`, `toCommand()` |

## Package Structure

```
core/
  domain/{area}/          # Sealed interfaces, typed IDs, commands
  input/usecase/{area}/   # Use case interfaces (fun interface)
  output/port/{area}/     # Port interfaces (fun interface)
  impl/{area}/            # Use case implementations
adapter/input/api/
  controller/             # REST controllers (suspend handler functions)
  mapper/                 # toResponse() / toCommand() extensions
adapter/output/postgresql/
  entity/                 # R2DBC @Table entities
  mapper/                 # toDomain() / toEntity() extensions
  repository/             # CoroutineCrudRepository interfaces
  adapter/                # Port implementations
```

## Extension Functions for Spring

- Group Spring-related extensions in dedicated `*Extensions.kt` files
- Use extension functions for mapper logic — keep mappers stateless
- JSON column handling: `io.r2dbc.postgresql.codec.Json` with mapper extensions for `Json <-> String`

## KDoc for Spring Components

- KDoc on all public use case interfaces and port interfaces — explain the business rule, not the mechanism
- Document suspend semantics for callers: whether the function is safe to call from any dispatcher
- Skip KDoc on mapper extension functions when the name is self-documenting (`toDomain()`, `toEntity()`)

## Meta-Annotations

- `@UseCase` — meta-annotation combining `@Component` + stereotype marker for use case impls
- `@Adapter` — meta-annotation combining `@Component` + stereotype marker for persistence adapters
- Prefer these over `@Service` / `@Component` for domain layer clarity
