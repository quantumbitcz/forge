# Spring Boot + Kotest Testing

> Extends `modules/testing/kotest.md` with Spring-specific integration patterns.
> Generic Kotest conventions (ShouldSpec, matchers, MockK, data-driven) are NOT repeated here.

## Integration Test Annotations

### API Tests
```kotlin
@RestIntegrationTest  // custom meta-annotation
class UserApiTests : ShouldSpec({
    // WebTestClient + PostgreSQL Testcontainer + Keycloak Testcontainer
})
```
`@RestIntegrationTest` bundles `@SpringBootTest(webEnvironment = RANDOM_PORT)` + Testcontainer lifecycle + test security config.

### Persistence Tests
```kotlin
@PersistenceIntegrationTest  // custom meta-annotation
class UserRepositoryTests : ShouldSpec({
    // SpringBootTest + PostgreSQL Testcontainer (no web layer)
})
```

## Test Fixtures

- `testFixtures` source set in Gradle — shared across all test modules
- Factory functions: `createUser(name = "test", ...)`, `createChatMessage(...)` with sensible defaults
- Factories return domain objects (not entities) — mapper extensions convert to entities when needed
- Override only the fields relevant to the test case; rely on defaults for everything else

## Test Realm (Keycloak)

- Predefined test users: `test-admin` / `password` (ADMIN role), `test-user` / `password` (USER role)
- Test realm auto-imported via Testcontainer init script
- Use helper functions to obtain JWT tokens: `getAdminToken()`, `getUserToken()`

## WebTestClient with Coroutines

```kotlin
webTestClient.post().uri("/api/users")
    .headers { it.setBearerAuth(getAdminToken()) }
    .bodyValue(createUserRequest)
    .exchange()
    .expectStatus().isCreated
    .expectBody<UserResponse>()
    .returnResult().responseBody!!
```

Use `awaitExchange` variants for suspend-friendly assertions when testing reactive endpoints directly.

## Database Test Patterns

- Testcontainers PostgreSQL shared across test classes via `@SharedContainerConfig`
- Flyway migrations run automatically before tests
- Clean database state between tests: use `@Sql` scripts or transactional rollback
- For R2DBC: use `DatabaseClient` for direct SQL setup/teardown in test lifecycle hooks

## What to Test at Each Layer

| Layer | Test type | Tools |
|-------|-----------|-------|
| Controller | Integration | `@RestIntegrationTest`, WebTestClient, real DB |
| Use case | Unit | MockK for ports, `runTest` for coroutines |
| Persistence adapter | Integration | `@PersistenceIntegrationTest`, real PostgreSQL |
| Mapper | Unit | Direct function calls, no Spring context |
