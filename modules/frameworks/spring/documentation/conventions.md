# Spring Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with Spring-specific patterns.

## Code Documentation

- Use KDoc for all public API (classes, functions, properties). Minimum: summary line + `@param`/`@return` for non-obvious signatures.
- Document use case interfaces — they are the primary API consumed by controllers. Skip implementation classes if the interface doc is complete.
- Annotate `@Transactional` usage in KDoc: state the transaction boundary and why it is on this class, not the caller.
- Domain entity KDoc: describe invariants and valid states, not just field meanings.
- Port interfaces (hexagonal architecture): document the contract, not the adapter implementation.

```kotlin
/**
 * Creates a new user account and publishes a [UserCreatedEvent].
 *
 * Transactional boundary: committed before event publication via outbox pattern.
 *
 * @param command validated creation request
 * @return the persisted user in [UserPersisted] state
 * @throws UserAlreadyExistsException if [CreateUserCommand.email] is already registered
 */
interface ICreateUserUseCase {
    operator fun invoke(command: CreateUserCommand): UserPersisted
}
```

## Architecture Documentation

- Document the hexagonal layer boundaries: `domain/` (pure Kotlin, no framework), `application/` (use cases, ports), `infrastructure/` (adapters, Spring beans).
- Include a C4 Component diagram showing the hexagonal rings and their dependencies.
- Document the sealed interface hierarchy (`XxxPersisted` / `XxxNotPersisted` / `XxxId`) — include an ER or class diagram showing the states.
- Document web stack choice (`web: mvc` or `web: webflux`) and why: blocking vs reactive trade-offs for the project context.
- Document persistence stack choice (`persistence: hibernate | r2dbc | jooq | exposed`) and the resulting transaction model.
- OpenAPI spec: use springdoc-openapi. Annotate controllers with `@Operation` and `@ApiResponse`. Spec served at `/v3/api-docs` and Swagger UI at `/swagger-ui.html`.

## Diagram Guidance

- **Layer diagram:** C4 Component with hexagonal rings (domain, application, infrastructure, adapters).
- **Entity states:** Class diagram showing sealed interface hierarchy and state transitions.
- **JPA entities:** ER diagram for domain aggregates and their persistence model.
- **Event flow:** Sequence diagram for use cases that publish domain events via outbox pattern.

## Dos

- KDoc on all `interface` and `data class` in `domain/` and `application/`
- Reference port interfaces by name (e.g., `ICreateUserPort`) in architecture docs
- Keep OpenAPI annotations on controllers, not use cases

## Don'ts

- Don't document Spring internal annotations (`@Service`, `@Repository`) — they are self-evident
- Don't duplicate domain glossary in OpenAPI descriptions — link to the domain model doc
