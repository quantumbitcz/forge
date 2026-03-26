# Spring WebFlux (Reactive Stack)

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-webflux")
```

```yaml
# application.yml — Netty is the default server (no Tomcat)
server:
  netty:
    connection-timeout: 10s
    idle-timeout: 60s
```

## Controller Patterns

### Kotlin (Coroutines)
```kotlin
@RestController
@RequestMapping("/api/v1/users")
class UserController(private val createUser: ICreateUserUseCase) {

    @PostMapping
    suspend fun create(@Valid @RequestBody req: CreateUserRequest): ResponseEntity<UserResponse> {
        val user = createUser(req.toCommand())
        return ResponseEntity.status(HttpStatus.CREATED).body(user.toResponse())
    }

    @GetMapping("/{id}")
    suspend fun findById(@PathVariable id: UUID): ResponseEntity<UserResponse> =
        ResponseEntity.ok(findUser(id).toResponse())
}
```

All handler methods are `suspend` functions. Spring converts them to reactive types under the hood.

### Kotlin (Reactor — avoid if coroutines are available)
```kotlin
@GetMapping("/{id}")
fun findById(@PathVariable id: UUID): Mono<ResponseEntity<UserResponse>> =
    userService.findById(id).map { ResponseEntity.ok(it.toResponse()) }
```

Prefer coroutines over raw Reactor types in Kotlin — cleaner error handling and readability.

### Java
```java
@RestController
@RequestMapping("/api/v1/users")
public class UserController {
    private final UserService userService;

    @GetMapping("/{id}")
    public Mono<ResponseEntity<UserResponse>> findById(@PathVariable UUID id) {
        return userService.findById(id)
            .map(user -> ResponseEntity.ok(UserMapper.toResponse(user)));
    }

    @GetMapping
    public Flux<UserResponse> findAll() {
        return userService.findAll().map(UserMapper::toResponse);
    }
}
```

## Thread Model

- Non-blocking event loop (Netty) — a small number of threads handle many connections
- **Never block** inside a WebFlux handler: no `Thread.sleep()`, no blocking JDBC, no `CompletableFuture.get()`
- For blocking calls that can't be avoided, wrap with `Schedulers.boundedElastic()`
- Use R2DBC, reactive Redis, or reactive HTTP clients — not their blocking counterparts

## Coroutine Support (Kotlin)

- All use case and port methods should be `suspend` functions
- `Flow<T>` from repositories — convert to `List<T>` at adapter boundary when needed
- `@Transactional` works on `suspend` functions natively in Spring 6+
- Use `CoroutineCrudRepository` (not `ReactiveCrudRepository`) for native coroutine support with Spring Data

```kotlin
// build.gradle.kts — required for coroutine support
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core")
implementation("org.jetbrains.kotlinx:kotlinx-coroutines-reactor")  // bridge
```

## Testing

### Controller Slice Test
```kotlin
@WebFluxTest(UserController::class)
class UserControllerTest(@Autowired val webTestClient: WebTestClient) {

    @MockkBean
    private lateinit var createUser: ICreateUserUseCase

    @Test
    fun `should create user`() {
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

### Full Integration Test
```kotlin
@SpringBootTest(webEnvironment = RANDOM_PORT)
class UserApiIntegrationTest(@Autowired val webTestClient: WebTestClient) {
    // WebTestClient is the standard client for WebFlux tests
}
```

### Key Annotations
| Scope | Annotation | Client |
|-------|-----------|--------|
| Controller slice | `@WebFluxTest` | `WebTestClient` |
| Full stack | `@SpringBootTest(RANDOM_PORT)` | `WebTestClient` |

Use `coEvery`/`coVerify` (MockK coroutine variants) for mocking suspend functions.

## Context7 Libraries
```yaml
context7_libraries:
  - "spring-boot"
  - "spring-webflux"
  - "kotlinx-coroutines"   # if Kotlin
```

## Dos
- DO use `suspend` functions (Kotlin) or `Mono`/`Flux` (Java) consistently across all handlers
- DO use `WebTestClient` for all controller testing
- DO use `awaitSingle()` / `awaitFirstOrNull()` in suspend functions instead of `.block()`
- DO configure `server.shutdown=graceful` for in-flight request completion

## Don'ts
- DON'T block inside a WebFlux handler — this starves the event loop and causes cascading timeouts
- DON'T mix `spring-boot-starter-web` and `spring-boot-starter-webflux` unless intentional
- DON'T use blocking JDBC/JPA drivers on the WebFlux thread pool — use R2DBC, jOOQ-reactive, or offload to `boundedElastic`
- DON'T use `@WebMvcTest` for WebFlux controllers — use `@WebFluxTest`
