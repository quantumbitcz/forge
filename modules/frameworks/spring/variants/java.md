# Spring Boot + Java Variant

> Extends `modules/frameworks/spring/conventions.md` with Java-specific Spring patterns.
> General Java idioms are in `modules/languages/java.md` — not duplicated here.

## Entity & DTO Pattern

**JPA Entities:**
- `@Entity` + `@Table` + `@Id` + `@GeneratedValue` (UUID strategy preferred)
- `@Column` for explicit column mapping; `@CreatedDate` / `@LastModifiedDate` via Spring Data auditing
- Lifecycle callbacks: `@PrePersist`, `@PreUpdate` or auditing annotations
- Relationships: prefer `FetchType.LAZY`; use `@EntityGraph` for controlled eager fetching
- `equals` / `hashCode` based on business key or ID — never on all fields

**DTOs:**
- Use Java records for immutable response and request types: `record XxxResponse(UUID id, String name, ...)`
- Separate request and response: `CreateXxxRequest`, `UpdateXxxRequest`, `XxxResponse`
- Validation annotations (`@NotNull`, `@NotBlank`, `@Size`, `@Valid`) on request DTOs, not on entities
- Mapper methods in a dedicated `XxxMapper` class or MapStruct `@Mapper` interface

## Bean Validation

- `@Valid` on `@RequestBody` parameters in controllers — triggers JSR 380 validation
- `@Validated` on class level for method-parameter validation (e.g., `@PathVariable` constraints)
- Custom constraint annotations for complex business rules: `@ValidDateRange`, `@UniqueEmail`
- Validation groups for conditional validation: `Create.class`, `Update.class`

## Naming Overrides

| Artifact | Spring+Java Pattern |
|----------|---------------------|
| Service interface | `XxxService` |
| Service impl | `XxxServiceImpl` with `@Service` + `@Transactional` |
| Repository | extends `JpaRepository<XxxEntity, UUID>` |
| Mapper | `XxxMapper` with `@Component` or MapStruct `@Mapper(componentModel = "spring")` |
| Config | `XxxConfig` with `@Configuration` |

## Package Structure

```
com.example.app/
  controller/         # REST controllers
  service/            # Service interfaces
  service/impl/       # Service implementations
  repository/         # Spring Data JPA repositories
  entity/             # JPA entities
  dto/                # Request/response records
  mapper/             # Entity <-> DTO mappers
  config/             # Spring configuration classes
  exception/          # Custom exceptions + @RestControllerAdvice handler
```

## Optional for Repository Returns

- Repository `findBy*` methods return `Optional<T>` — never return bare null from a finder
- Use `orElseThrow(() -> new EntityNotFoundException(...))` for required lookups
- Use `orElse(defaultValue)` or `ifPresent(consumer)` — never call `.get()` without a guard

## Local Type Inference

- Use `var` for local variables when the type is obvious from the right-hand side
- Do not use `var` for fields, method parameters, or return types
- Especially useful in test code to reduce boilerplate: `var response = mockMvc.perform(...)`

## Streams in Services

- Prefer Streams API for collection transforms in service methods: `list.stream().map(...).toList()`
- Use method references for simple delegates: `users.stream().map(User::getName)`
- For complex multi-step pipelines, extract intermediate variables for readability
- Avoid side effects in stream operations — `forEach` is terminal consumption, not result building

## Javadoc for Spring Components

- Javadoc on all public service interfaces — explain the business rule and expected behavior
- Document exception semantics: which exceptions can be thrown and under what conditions
- Skip Javadoc on trivial getters/setters and mapper methods with self-documenting names
- Use `@param`, `@return`, `@throws` tags for methods with non-obvious contracts

## Async Patterns

- `@Async` with a custom `TaskExecutor` — never rely on the default (unbounded thread creation)
- Return `CompletableFuture<T>` for async methods that callers need to await
- `@Async` does NOT work on private methods (proxy-based AOP)
- `@Transactional` + `@Async` on the same method: transaction is lost — use separate beans
- Must have `@EnableAsync` on a config class — without it, `@Async` is silently ignored
