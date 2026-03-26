# Spring MVC (Servlet Stack)

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-web")
```

```yaml
# application.yml
spring:
  mvc:
    servlet:
      path: /api       # optional — or set via @RequestMapping on base controller
server:
  tomcat:
    threads:
      max: 200         # default; tune based on load profile
      min-spare: 10
    max-connections: 8192
```

## Controller Patterns

### Kotlin
```kotlin
@RestController
@RequestMapping("/api/v1/users")
class UserController(private val createUser: ICreateUserUseCase) {

    @PostMapping
    fun create(@Valid @RequestBody req: CreateUserRequest): ResponseEntity<UserResponse> {
        val user = createUser(req.toCommand())
        return ResponseEntity.status(HttpStatus.CREATED).body(user.toResponse())
    }

    @GetMapping("/{id}")
    fun findById(@PathVariable id: UUID): ResponseEntity<UserResponse> =
        ResponseEntity.ok(findUser(id).toResponse())
}
```

### Java
```java
@RestController
@RequestMapping("/api/v1/users")
public class UserController {
    private final UserService userService;

    @PostMapping
    public ResponseEntity<UserResponse> create(@Valid @RequestBody CreateUserRequest req) {
        var user = userService.create(req);
        return ResponseEntity.status(HttpStatus.CREATED).body(UserMapper.toResponse(user));
    }
}
```

All handler methods return blocking types (`ResponseEntity<T>`, `T`, `void`). Never return `Mono`/`Flux` — that is the WebFlux stack.

## Thread Model

- One thread per request (servlet container thread pool)
- Blocking I/O is expected and safe
- Configure `server.tomcat.threads.max` for throughput tuning
- For long-running tasks, offload to `@Async` with a custom `TaskExecutor`

## Testing

### Controller Slice Test
```kotlin
@WebMvcTest(UserController::class)
class UserControllerTest(@Autowired val mockMvc: MockMvc) {

    @MockkBean
    private lateinit var createUser: ICreateUserUseCase

    @Test
    fun `should create user`() {
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

### Full Integration Test
```kotlin
@SpringBootTest(webEnvironment = RANDOM_PORT)
class UserApiIntegrationTest(@Autowired val restTemplate: TestRestTemplate) {
    // or use WebTestClient (also works with MVC since Spring 5.3)
}
```

### Key Annotations
| Scope | Annotation | Client |
|-------|-----------|--------|
| Controller slice | `@WebMvcTest` | `MockMvc` |
| Full stack | `@SpringBootTest(RANDOM_PORT)` | `TestRestTemplate` or `WebTestClient` |

`WebTestClient` works with both MVC and WebFlux — prefer it for consistency if the project may later adopt WebFlux for some controllers.

## Context7 Libraries
```yaml
context7_libraries:
  - "spring-boot"
  - "spring-web"          # spring-web (MVC), NOT spring-webflux
```

## Dos
- DO configure thread pool sizing explicitly for production workloads
- DO use `@Async` with a custom `TaskExecutor` for background work — never block the request thread for minutes
- DO use `MockMvc` for fast controller-only tests without starting the full server
- DO set `server.shutdown=graceful` for clean shutdown under load

## Don'ts
- DON'T return reactive types (`Mono`, `Flux`) from MVC controllers — they will serialize as JSON objects, not reactive streams
- DON'T mix `spring-boot-starter-web` and `spring-boot-starter-webflux` on the classpath unless intentional (Spring Boot defaults to MVC when both are present)
- DON'T assume unlimited concurrency — the servlet thread pool is bounded
