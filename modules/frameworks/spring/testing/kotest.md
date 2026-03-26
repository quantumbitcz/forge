# Spring Boot + Kotest Testing

> Extends `modules/testing/kotest.md` with Spring-specific integration patterns.
> Generic Kotest conventions (ShouldSpec, matchers, MockK, data-driven) are NOT repeated here.
> Web stack choice (`web:`) and persistence choice (`persistence:`) affect test annotations and clients.

## Integration Test Annotations

### API Tests
```kotlin
@RestIntegrationTest  // custom meta-annotation
class UserApiTests : ShouldSpec({
    // Full stack + PostgreSQL Testcontainer + Keycloak Testcontainer
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

## Controller Tests by Web Stack

### MVC (`web: mvc`)
```kotlin
@WebMvcTest(UserController::class)
class UserControllerTest(@Autowired val mockMvc: MockMvc) {
    @MockkBean
    private lateinit var createUser: ICreateUserUseCase

    should("create user") {
        every { createUser(any()) } returns testUser()

        mockMvc.post("/api/v1/users") {
            contentType = MediaType.APPLICATION_JSON
            content = objectMapper.writeValueAsString(createUserRequest())
        }.andExpect {
            status { isCreated() }
            jsonPath("$.id") { exists() }
        }
    }
}
```

### WebFlux (`web: webflux`)
```kotlin
@WebFluxTest(UserController::class)
class UserControllerTest(@Autowired val webTestClient: WebTestClient) {
    @MockkBean
    private lateinit var createUser: ICreateUserUseCase

    should("create user") {
        coEvery { createUser(any()) } returns testUser()

        webTestClient.post().uri("/api/v1/users")
            .contentType(MediaType.APPLICATION_JSON)
            .bodyValue(createUserRequest())
            .exchange()
            .expectStatus().isCreated
            .expectBody<UserResponse>()
            .returnResult().responseBody!!
    }
}
```

Use `coEvery`/`coVerify` (MockK coroutine variants) for mocking suspend functions in WebFlux controllers.

## Use Case Tests

```kotlin
class CreateUserUseCaseTest : ShouldSpec({
    val port = mockk<ICreateUserPort>()
    val useCase = ICreateUserUseCaseImpl(port)

    should("create user with valid command") {
        // For WebFlux: wrap in runTest { } for coroutine support
        every { port.save(any()) } returns testUser()
        val result = useCase(createUserCommand())
        result.name shouldBe "Test User"
        verify(exactly = 1) { port.save(any()) }
    }
})
```

For WebFlux projects with `suspend` use cases, use `runTest` and `coEvery`/`coVerify`.

## Database Test Patterns by Persistence Stack

### Hibernate / JPA (`persistence: hibernate`)
```kotlin
@DataJpaTest
@AutoConfigureTestDatabase(replace = NONE)  // use real DB, not H2
class UserRepositoryTest : ShouldSpec({
    // @Transactional rolls back after each test
    // EntityManager available for setup/teardown
})
```

### R2DBC (`persistence: r2dbc`)
```kotlin
@DataR2dbcTest
class UserRepositoryTest : ShouldSpec({
    // Use DatabaseClient for direct SQL setup/teardown in test lifecycle hooks
    // No @Transactional rollback — use manual cleanup
})
```

### jOOQ (`persistence: jooq`)
```kotlin
@SpringBootTest(classes = [JooqTestConfig::class])
@Transactional
class OrderRepositoryTest : ShouldSpec({
    // DSLContext injected, transaction rolls back after each test
})
```

### Exposed (`persistence: exposed`)
```kotlin
@SpringBootTest(classes = [ExposedTestConfig::class])
@Transactional
class OrderRepositoryTest : ShouldSpec({
    // SpringTransactionManager context, rolls back after each test
})
```

## Shared Patterns

- Testcontainers PostgreSQL shared across test classes via `@SharedContainerConfig`
- Flyway migrations run automatically before tests
- Clean database state between tests: use `@Sql` scripts or transactional rollback
- WebTestClient works with both MVC and WebFlux — prefer it for consistency in projects that may mix

## What to Test at Each Layer

| Layer | Test type | Tools |
|-------|-----------|-------|
| Controller | Integration | `@RestIntegrationTest`, MockMvc or WebTestClient (depends on `web:`), real DB |
| Use case | Unit | MockK for ports; `runTest` for suspend functions (WebFlux) |
| Persistence adapter | Integration | `@PersistenceIntegrationTest`, real PostgreSQL |
| Mapper | Unit | Direct function calls, no Spring context |
