# Testcontainers Conventions (Cross-Framework)
> Support tier: contract-verified
Testcontainers provides real infrastructure (PostgreSQL, Redis, Kafka, etc.) spun up in Docker for integration tests. These conventions apply regardless of language/framework.

## Core Principle

Use Testcontainers for tests that require real infrastructure semantics (transactions, pub/sub ordering, index behaviour). Do NOT use them for pure unit tests — the startup cost (~2-5s per container) is too high.

## Common Container Setup

### PostgreSQL

```kotlin // Kotlin (any framework)
val postgres = PostgreSQLContainer("postgres:16-alpine")
    .withDatabaseName("testdb")
    .withUsername("test")
    .withPassword("test")
```

```python # Python
from testcontainers.postgres import PostgresContainer
postgres = PostgresContainer("postgres:16-alpine")
```

```go // Go
req := testcontainers.ContainerRequest{
    Image: "postgres:16-alpine",
    Env: map[string]string{"POSTGRES_PASSWORD": "test"},
    ExposedPorts: []string{"5432/tcp"},
    WaitingFor: wait.ForListeningPort("5432/tcp"),
}
```

### Redis / Kafka

Use the official `RedisContainer` / `KafkaContainer` classes where available. Pin to a specific image tag — avoid `latest` in test infrastructure.

## Lifecycle: Per-Test vs Per-Class vs Reuse

| Mode | When to use | Cost |
|------|-------------|------|
| Per test | Tests mutate schema; full isolation required | High |
| Per class (`@Container` static / class-scope fixture) | Tests share read-heavy data | Medium |
| Reuse mode (`withReuse(true)`) | Local dev only — fast iteration | Low — persistent across runs |

**Default for CI:** per-class lifecycle. Each test class gets one container; tests within the class truncate tables in `beforeEach`/`setUp`.

**Reuse mode is NOT safe for CI** — containers may have stale data from a previous run. Enable only via `testcontainers.reuse.enable=true` in `~/.testcontainers.properties`.

## Connection String Injection

### Spring Boot (`@DynamicPropertySource`)

```kotlin
companion object {
    @Container @JvmStatic
    val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine")

    @DynamicPropertySource @JvmStatic
    fun props(registry: DynamicPropertyRegistry) {
        registry.add("spring.r2dbc.url") { postgres.jdbcUrl.replace("jdbc:", "r2dbc:") }
        registry.add("spring.r2dbc.username", postgres::getUsername)
        registry.add("spring.r2dbc.password", postgres::getPassword)
    }
}
```

### FastAPI / pytest

```python
@pytest.fixture(scope="session")
def postgres():
    with PostgresContainer("postgres:16-alpine") as pg:
        yield pg

@pytest.fixture(scope="session")
def db_url(postgres):
    return postgres.get_connection_url()
```

### Go (`testcontainers-go`)

Retrieve the mapped port with `container.MappedPort(ctx, "5432")` and build the DSN from the dynamic host/port.

### .NET (`Testcontainers.PostgreSql`)

```csharp
private readonly PostgreSqlContainer _pg = new PostgreSqlBuilder()
    .WithImage("postgres:16-alpine")
    .Build();

public async Task InitializeAsync() => await _pg.StartAsync();
public async Task DisposeAsync()    => await _pg.DisposeAsync();

// Connection string:
_pg.GetConnectionString()
```

## Cleanup and Port Management

- Never hardcode container ports — always use dynamically assigned mapped ports
- Always call `stop()`/`close()`/`DisposeAsync()` in teardown; Ryuk handles stragglers but explicit cleanup is safer
- Use `WaitingFor` / `waitStrategy` to ensure the container is ready before the test starts

## CI Considerations

- **GitHub Actions:** Docker is available by default — no special setup needed
- **Docker-in-Docker (DinD):** Set `DOCKER_HOST` and `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` when running in Kubernetes-based CI
- **GitHub Actions services:** Use native `services:` blocks for simple, single-container needs — reserve Testcontainers for dynamic or multi-container scenarios
- **Parallelism:** Each CI job gets its own Docker context; running test suites in parallel is safe
- **Image caching:** Pre-pull images in a CI setup step (`docker pull postgres:16-alpine`) to avoid repeated downloads

## What NOT to Use Testcontainers For

- Testing SQL query correctness on a simple schema — an H2/SQLite in-memory DB may suffice
- Tests that only verify your ORM model mappings — unit test the mapper instead
- Smoke tests that already have a live staging environment available

## Anti-Patterns

- `Thread.sleep()` / `time.sleep()` waiting for container readiness — use `WaitingFor` strategies
- Sharing one container across the entire test suite when tests mutate state without cleanup
- Using `latest` image tags — pin to a specific version for reproducibility
- Starting containers inside individual test methods — pay startup cost once per class/session
