# Spring Boot + JUnit 5 / AssertJ Testing

> Extends `modules/testing/junit5.md` with Spring-specific integration patterns.
> Generic JUnit 5 conventions (nested classes, AssertJ, Mockito, parameterized tests) are NOT repeated here.

## Integration Test Annotations

### Full Application Tests
```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
class UserControllerIT {
    @Autowired MockMvc mockMvc;
    // Full context with real beans, MockMvc for HTTP layer
}
```

### Controller Slice Tests
```java
@WebMvcTest(UserController.class)
class UserControllerTest {
    @Autowired MockMvc mockMvc;
    @MockBean UserService userService;
    // Only web layer — service mocked
}
```

### Repository Tests
```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class UserRepositoryTest {
    @Autowired UserRepository repo;
    // JPA slice with real database via Testcontainers
}
```

## MockMvc Patterns

```java
mockMvc.perform(post("/api/users")
        .contentType(MediaType.APPLICATION_JSON)
        .content(objectMapper.writeValueAsString(request)))
    .andExpect(status().isCreated())
    .andExpect(jsonPath("$.name").value("Alice"))
    .andExpect(header().exists("Location"));
```

Use `@WithMockUser(roles = "ADMIN")` for security-aware controller tests. For JWT-based auth, configure a mock `JwtDecoder` bean.

## Service Mocking

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {
    @Mock UserRepository repo;
    @InjectMocks UserServiceImpl service;
}
```

Use `@MockBean` in `@SpringBootTest` to replace a real bean with a mock in the application context. Prefer `@Mock` + `@InjectMocks` in pure unit tests (no Spring context).

## Testcontainers with @DynamicPropertySource

```java
@Testcontainers
@SpringBootTest
class UserServiceIT {
    @Container
    static PostgreSQLContainer<?> pg = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void dbProps(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", pg::getJdbcUrl);
        registry.add("spring.datasource.username", pg::getUsername);
        registry.add("spring.datasource.password", pg::getPassword);
    }
}
```

Share containers across test classes via a base class or `@SharedContainerConfig` to avoid startup overhead.

## What to Test at Each Layer

| Layer | Test type | Tools |
|-------|-----------|-------|
| Controller | Slice / Integration | `@WebMvcTest` or `@SpringBootTest` + MockMvc |
| Service | Unit | Mockito `@Mock` + `@InjectMocks`, no Spring context |
| Repository | Slice | `@DataJpaTest` + Testcontainers PostgreSQL |
| Mapper | Unit | Direct method calls, no Spring context |

## Test Data

- Builder pattern or factory methods for test entities — avoid constructing complex objects inline
- Use `@Sql("/test-data.sql")` for integration tests that need pre-populated data
- Prefer `@Transactional` on test classes for automatic rollback between tests (JPA only)
