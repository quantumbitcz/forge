# Spring Boot Framework Conventions
> Support tier: contract-verified
> Language-agnostic Spring patterns. Language-specific idioms (Kotlin null safety, Java records, etc.)
> are in `modules/languages/{lang}.md`. Framework-language integration is in `variants/{lang}.md`.

## Architecture (Hexagonal / Clean)

| Module | Responsibility | Dependencies |
|--------|---------------|--------------|
| `core` | Domain models, use cases, port interfaces | spring-context, spring-tx only |
| `adapter/input/api` | REST controllers, request/response mapping | core |
| `adapter/output/persistence` | Database access, entity mapping, migrations | core |
| `app` | Spring Boot entry point, configuration, test infrastructure | all modules |

**Dependency rule:** Core never imports from adapters. Adapters depend on core via port interfaces. Controllers depend on services/use cases, never on repositories directly. Entities never leak into API responses — always map to DTOs.

## Naming

| Artifact | Pattern | Annotation |
|----------|---------|------------|
| Controller | `XxxController` | `@RestController` + `@RequestMapping` |
| Service / Use case | `XxxService` or `IXxxUseCase` | `@Service` / custom `@UseCase` |
| Repository | `XxxRepository` | extends Spring Data repository (type depends on `persistence:` choice) |
| Entity | `XxxEntity` | `@Entity`/`@Table` + `@Id` + `@Column` |
| Request DTO | `CreateXxxRequest` / `UpdateXxxRequest` | validation annotations |
| Response DTO | `XxxResponse` | immutable |
| Mapper | `XxxMapper` | `@Component` or extension object |
| Config | `XxxConfig` | `@Configuration` |

## Code Quality

- Functions: max ~30 lines, prefer ~20 for controller/service methods
- Max 3 nesting levels per method
- File size: max ~400 lines, prefer ~200 per component
- Public interfaces (use cases, services, ports) must have documentation explaining WHY, not WHAT
- No `System.out.println` / `print` / `printStackTrace` in production code — use SLF4J logger
- No entity objects in controller responses — always map to DTOs
- MaxLineLength: 150 (editorconfig)

## Error Handling

Global exception handler via `@RestControllerAdvice` / `@ControllerAdvice`. Return consistent ProblemDetail responses (RFC 7807 in Spring 6+).

| Domain Exception | HTTP Status |
|-----------------|-------------|
| `NoSuchElementException` / `EntityNotFoundException` | 404 |
| `IllegalArgumentException` / `ConstraintViolationException` | 400 |
| `IllegalStateException` / `DataIntegrityViolationException` | 409 |
| `AccessDeniedException` / `DomainAccessDeniedException` | 403 |

Map domain exceptions at the controller boundary. Services throw domain-specific exceptions; controllers translate to HTTP.

## Security

- `SecurityFilterChain` bean in a `@Configuration` class — never extend `WebSecurityConfigurerAdapter` (removed in Spring Security 6)
- Method-level security with `@PreAuthorize` or `@Secured` where appropriate
- Use `@EnableMethodSecurity` (not `@EnableGlobalMethodSecurity`, deprecated in 6.0)
- CSRF: enabled for browser clients, disabled for stateless REST APIs with JWT
- JWT: validate via `JwtDecoder` bean or custom filter; extract claims via `@AuthenticationPrincipal`
- Never trust user-supplied IDs for authorization — always verify resource ownership server-side
- CORS: configure explicitly in `SecurityFilterChain` — do not use `@CrossOrigin` on individual controllers in production
- Password encoding: `BCryptPasswordEncoder` — never store plaintext

## Performance

### Connection Pooling
- Set pool size to 2x CPU cores for I/O-bound workloads — specific config depends on `persistence:` choice (see binding file)
- Set connection timeout to 10 seconds — fail fast, do not queue indefinitely
- Monitor pool metrics (active, idle, waiting)

### N+1 Prevention
- Specific prevention strategies depend on `persistence:` choice — see the persistence binding file for patterns
- Rule: if a method triggers more SQL statements than entities returned, suspect N+1
- Monitor with query logging in dev, statistics in tests

### Caching
- Use `@Cacheable` for read-heavy, rarely-changing data (lookups, config, reference data)
- Always define explicit cache names — never use default cache
- Set explicit TTL — infinite caches cause stale data bugs
- Use `@CacheEvict` on write operations that invalidate cached data
- Never cache mutable objects — return copies or immutable types

## API Design

- Use specific mapping annotations: `@GetMapping`, `@PostMapping`, `@PutMapping`, `@DeleteMapping`, `@PatchMapping` — not `@RequestMapping(method=...)`
- Return `ResponseEntity<T>` with appropriate status codes
- Pagination: accept `Pageable` / page parameters, return `Page<T>` or equivalent paginated wrapper
- Use `@RequestMatchers` for path-based authorization (not `.antMatchers()` / `.mvcMatchers()`, removed in 6.0)
- Version APIs via URL path (`/api/v1/...`) or header, not query parameter
- Validate all external input at the controller layer with `@Valid` / `@Validated`

## Database

### Migrations
- Flyway (preferred) or Liquibase for schema migrations
- Migration naming: `V{N}__{description}.sql` (Flyway) or changelog XML/YAML (Liquibase)
- Never modify an applied migration — create a new one

### Data Access
- Parameterized queries only — no string concatenation in SQL/JPQL/HQL
- Use Spring Data derived query methods where possible: `findByEmail(email)`
- Custom queries: `@Query` with named parameters `:param`
- Entities: `@CreatedDate` / `@LastModifiedDate` for audit fields (Spring Data auditing)
- JSON columns: use database-specific JSON types; convert in mapper layer

### Transaction Management
- `@Transactional` on service/use-case methods only — never on controllers or repositories/adapters
- Read-only operations: `@Transactional(readOnly = true)` — enables DB optimizations
- Default propagation: `REQUIRED` unless explicitly needed otherwise
- Never catch and swallow exceptions inside `@Transactional` methods without re-throwing — this breaks rollback
- Handle `DataIntegrityViolationException` for unique constraint violations — map to domain-specific errors

## Dependency Injection

- **Constructor injection only** — never use `@Autowired` on fields or setters
- Use `private final` fields (or `val` in Kotlin) with a constructor
- For optional dependencies: `Optional<T>` parameter or `@Nullable`
- Prefer interface-based injection for services and ports
- Use meta-annotations (`@UseCase`, `@Adapter`) over generic `@Component`/`@Service` when the project defines them

## Testing

### Test Framework
- **Kotest ShouldSpec** for Kotlin Spring projects; **JUnit 5** for Java Spring projects
- Use `@SpringBootTest` for full integration tests
- Controller slice: `@WebMvcTest` (when `web: mvc`) or `@WebFluxTest` (when `web: webflux`)
- Repository slice: `@DataJpaTest` (when `persistence: hibernate`) or `@DataR2dbcTest` (when `persistence: r2dbc`)

### Integration Test Patterns
- Controller tests: use `MockMvc` (when `web: mvc`) or `WebTestClient` (when `web: webflux`) to verify request/response contracts
- Service tests: unit-test with mocked repository interfaces (MockK for Kotlin, Mockito for Java)
- Repository tests: use **Testcontainers** with a real database engine — avoid H2 for anything beyond trivial cases
- End-to-end: `@SpringBootTest(webEnvironment = RANDOM_PORT)` + `WebTestClient` (works with both MVC and WebFlux)

### What to Test
- Business rules in service/use-case layer (primary focus)
- Request validation, error mapping, and HTTP status codes at the controller layer
- Database queries and constraint handling at the repository layer
- Security rules: endpoint access control, ownership verification

### What NOT to Test
- Spring DI wiring (if the app starts, DI works)
- Framework-provided serialization of standard types
- Default Spring Security filter chain behavior (e.g., 401 for missing credentials)
- Getter/setter code in DTOs or entities

### Example Test Structure
```
src/test/kotlin/{package}/
  controller/XxxControllerTest.kt    # @WebMvcTest or @WebFluxTest (depends on web: choice)
  service/XxxServiceTest.kt          # unit test with mocks
  repository/XxxRepositoryTest.kt    # @DataJpaTest or @DataR2dbcTest (depends on persistence: choice)
  integration/XxxIntegrationTest.kt  # @SpringBootTest full stack
```

For general Kotest/JUnit 5 patterns, see `modules/testing/kotest.md` and `modules/testing/junit5.md`.
For Testcontainers usage, see `modules/testing/testcontainers.md`.

## TDD Flow

```
scaffold -> write tests (RED) -> implement (GREEN) -> refactor
```

1. **Scaffold**: create class/interface stubs with proper annotations
2. **RED**: write the test expressing expected behaviour — must fail
3. **GREEN**: implement the minimum code to pass
4. **Refactor**: clean up, extract, optimize — tests must still pass

## Smart Test Rules

- Test behaviour, not implementation — tests should not break on internal refactoring
- No duplicate test scenarios — each test covers a distinct case
- Do not test framework internals (Spring dependency injection, serialization of third-party types)
- One logical assertion concept per test (use soft assertions when checking multiple facets of one result)
- Prefer integration tests for controller layer, unit tests for service/use-case layer
- Use Testcontainers for database tests — avoid H2 for anything beyond trivial cases

## Logging and Monitoring

- SLF4J with Logback — configure JSON format for production
- Add MDC context for request tracing: `correlationId`, `userId`, `endpoint`
- Log levels: ERROR (action needed), WARN (degraded), INFO (business events), DEBUG (dev only)
- Never log sensitive data: passwords, tokens, PII, full request bodies
- Enable Spring Boot Actuator: `/health`, `/metrics`, `/info` — secure `/env` and `/beans` in production
- Custom health indicators for critical dependencies (database, cache, message queue)

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use constructor injection exclusively — never field injection
- Return specific DTOs from controllers, never entities
- Use `@Transactional(readOnly = true)` for read-only queries
- Validate all external input at the controller layer
- Use Spring Profiles for environment-specific configuration
- Configure connection pool sizing explicitly
- Prefer composition over inheritance for service logic
- Use specific mapping annotations (`@GetMapping`, etc.) over generic `@RequestMapping`
- Define `SecurityFilterChain` as a `@Bean` — never extend deprecated adapters
- Use `@ConfigurationProperties` for structured config — not scattered `@Value` annotations

### Don't
- Don't catch `Exception` broadly — catch specific exception types
- Don't expose entity IDs as sequential integers in APIs — use UUIDs
- Don't put business logic in controllers — controllers validate, delegate, and map only
- Don't use `@PostConstruct` for complex initialization — use `ApplicationRunner` or `@EventListener`
- Don't create circular dependencies between services — extract shared logic
- Don't hardcode configuration values — use `@Value` or `@ConfigurationProperties`
- Don't use `System.out.println` — use SLF4J logger
- Don't suppress exceptions inside `@Transactional` — this silently prevents rollback
- Don't use deprecated security APIs (`WebSecurityConfigurerAdapter`, `antMatchers`, `@EnableGlobalMethodSecurity`)
- Don't rely on default thread pools for `@Async` — configure a custom `TaskExecutor`
