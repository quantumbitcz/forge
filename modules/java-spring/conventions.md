# Java/Spring Boot Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (Layered)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `controller` | REST endpoints, request/response mapping | service |
| `service` | Business logic, transaction boundaries | repository, dto |
| `repository` | Data access (Spring Data JPA) | entity |
| `dto` | Data transfer objects for API layer | — |
| `entity` | JPA entities, database mapping | — |
| `config` | Spring configuration, security, beans | all |

**Dependency rule:** Controllers depend on services, never on repositories directly. Services depend on repositories. DTOs are used at the controller boundary; entities never leak into API responses.

## Entity & DTO Pattern

JPA entities:
- Annotated with `@Entity`, `@Table`, `@Id`, `@GeneratedValue`
- Use `@Column` for explicit column mapping
- Lifecycle callbacks via `@PrePersist`, `@PreUpdate` or Spring Data auditing (`@CreatedDate`, `@LastModifiedDate`)
- Relationships: prefer `FetchType.LAZY`, use `@EntityGraph` for eager fetching when needed
- Equals/hashCode based on business key or ID — never on all fields

DTOs:
- Separate request and response DTOs: `CreateXxxRequest`, `UpdateXxxRequest`, `XxxResponse`
- Use Java records (`record XxxResponse(...)`) for immutable response types
- Validation annotations (`@NotNull`, `@Size`, `@Valid`) on request DTOs, not on entities
- Mapper methods in a dedicated `XxxMapper` class (or MapStruct interface)

## Naming Patterns

| Artifact | Pattern | Annotation |
|----------|---------|------------|
| Controller | `XxxController` | `@RestController` + `@RequestMapping` |
| Service interface | `XxxService` | — |
| Service impl | `XxxServiceImpl` | `@Service` + `@Transactional` |
| Repository | `XxxRepository` | extends `JpaRepository<XxxEntity, Long>` |
| Entity | `XxxEntity` or `Xxx` | `@Entity` + `@Table` |
| Request DTO | `CreateXxxRequest` | `record` with validation annotations |
| Response DTO | `XxxResponse` | `record` |
| Mapper | `XxxMapper` | `@Component` or MapStruct `@Mapper` |
| Config | `XxxConfig` | `@Configuration` |

## Package Structure

```
com.example.app/
  controller/         # REST controllers
  service/            # Service interfaces
  service/impl/       # Service implementations
  repository/         # Spring Data JPA repositories
  entity/             # JPA entities
  dto/                # Request/response DTOs
  mapper/             # Entity <-> DTO mappers
  config/             # Spring configuration classes
  exception/          # Custom exceptions + global handler
```

## Dependency Injection

- **Constructor injection only** — never use `@Autowired` on fields or setters
- Use `private final` fields with a constructor (or Lombok `@RequiredArgsConstructor`)
- For optional dependencies, use `Optional<T>` constructor parameter or `@Nullable`
- Prefer interface-based injection for services

## Transaction Management

- `@Transactional` on service methods, not on controllers or repositories
- Read-only operations: `@Transactional(readOnly = true)`
- Propagation: default `REQUIRED` unless explicitly needed otherwise
- Never catch and swallow exceptions inside `@Transactional` methods without re-throwing — this breaks rollback

## Spring Security Patterns

- SecurityFilterChain bean in a `@Configuration` class (not extending `WebSecurityConfigurerAdapter` — deprecated)
- Method-level security with `@PreAuthorize` or `@Secured` where appropriate
- Password encoding: `BCryptPasswordEncoder` (never store plaintext)
- CSRF: enabled for browser clients, disabled for stateless REST APIs with JWT
- JWT: validate via `JwtDecoder` bean or custom filter; extract claims in a utility or `@AuthenticationPrincipal`
- Never trust user-supplied IDs for authorization — always verify ownership server-side

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- Javadoc on public service interfaces — explain WHY, not WHAT
- No `System.out.println` in production code — use SLF4J (`@Slf4j` with Lombok or `LoggerFactory`)
- No field injection (`@Autowired` on fields)
- No entity objects in controller responses — always map to DTOs
- Prefer `Optional` return from repository `findBy*` methods; avoid `.get()` without `.isPresent()` check

## Testing

- **Unit tests:** JUnit 5 + Mockito for service layer
- **Integration tests:** `@SpringBootTest` + `@AutoConfigureMockMvc` or `@WebMvcTest` for controller slice
- **Database tests:** `@DataJpaTest` with H2 or Testcontainers (PostgreSQL)
- **Naming:** `should_doSomething_when_condition` or `givenX_whenY_thenZ`
- **Factories:** Test builders or fixture methods for creating test entities
- **Rules:** Test behavior not implementation, one logical assertion per test

## Error Handling

Global exception handler via `@RestControllerAdvice`:

| Exception | HTTP Status |
|-----------|-------------|
| `EntityNotFoundException` (custom) | 404 |
| `IllegalArgumentException` | 400 |
| `ConstraintViolationException` | 400 |
| `AccessDeniedException` | 403 |
| `DataIntegrityViolationException` | 409 |

Return a consistent error response body: `{ "status": 404, "error": "Not Found", "message": "..." }`.

## Data Access

- Parameterized queries only — no string concatenation in `@Query` JPQL/SQL
- Use Spring Data derived query methods where possible: `findByEmail(String email)`
- Custom queries: `@Query("SELECT e FROM Xxx e WHERE ...")` with named parameters `:param`
- Flyway or Liquibase for migrations: `V{N}__{description}.sql`
- Pagination: return `Page<XxxResponse>` from controllers, accept `Pageable` parameter

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use constructor injection exclusively — never field injection (`@Autowired` on fields)
- Return specific DTOs from controllers, never entities
- Use `@Transactional(readOnly = true)` for read-only queries (enables DB optimizations)
- Validate all external input at the controller layer with `@Valid` / `@Validated`
- Use `Optional<T>` for nullable return values from repositories, never return null
- Prefer composition over inheritance for service logic
- Use Spring Profiles for environment-specific configuration
- Configure connection pool sizing explicitly (HikariCP defaults may not suit your load)

### Don't
- Don't catch `Exception` broadly — catch specific exception types
- Don't use `@Autowired` on fields — use constructor injection (testability, immutability)
- Don't expose entity IDs as sequential integers in APIs — use UUIDs
- Don't put business logic in controllers — controllers only validate, delegate, and map
- Don't use `@PostConstruct` for complex initialization — use `ApplicationRunner` or `@EventListener`
- Don't create circular dependencies between services — refactor to extract shared logic
- Don't use `System.out.println` — use SLF4J logger
- Don't hardcode configuration values — use `@Value` or `@ConfigurationProperties`

## Performance Anti-Patterns

### N+1 Query Prevention
- Use `@EntityGraph` or `JOIN FETCH` in JPQL for associations accessed in a loop
- For collections: prefer batch fetching (`@BatchSize(size = 25)`) over individual loads
- Monitor with: `spring.jpa.show-sql=true` in dev, Hibernate Statistics in tests
- Rule: if a service method triggers more SQL statements than entities returned, it's likely N+1

### Caching Strategy
- Use `@Cacheable` for read-heavy, rarely-changing data (lookups, config, reference data)
- Always define explicit cache names — never use default cache
- Implement TTL-based eviction — don't rely on infinite caches
- Use `@CacheEvict` on write operations that invalidate cached data
- Anti-pattern: caching mutable objects — always return copies or immutable types

### Connection Pool
- Set HikariCP `maximumPoolSize` to 2x CPU cores for I/O-bound workloads
- Set `connectionTimeout` to 10 seconds (fail fast, don't queue indefinitely)
- Monitor with HikariCP metrics (active, idle, waiting)

## Async / Reactive Patterns

### When to Use @Async
- Background tasks: email sending, report generation, audit logging
- Always use a custom `TaskExecutor` — never rely on the default (unbounded thread creation)
- Return `CompletableFuture<T>` for async methods that callers need to await

### Common Pitfalls
- `@Async` on private methods: does NOT work (proxy-based AOP)
- `@Transactional` + `@Async` on the same method: transaction is lost (runs in new thread)
- Missing `@EnableAsync`: `@Async` annotation silently ignored

## Logging and Monitoring

### Structured Logging
- Use SLF4J with Logback — configure JSON format for production
- Add MDC context for request tracing: `correlationId`, `userId`, `endpoint`
- Log at appropriate levels: ERROR (action needed), WARN (degraded), INFO (business events), DEBUG (dev only)
- Never log sensitive data: passwords, tokens, PII, full request bodies

### Spring Boot Actuator
- Enable `/health`, `/metrics`, `/info` endpoints
- Secure actuator endpoints — don't expose `/env` or `/beans` in production
- Custom health indicators for critical dependencies (database, cache, message queue)
