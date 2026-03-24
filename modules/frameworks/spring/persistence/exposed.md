# Exposed with Spring

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.jetbrains.exposed:exposed-spring-boot-starter:0.49.0")
implementation("org.jetbrains.exposed:exposed-kotlin-datetime:0.49.0")
implementation("org.jetbrains.exposed:exposed-json:0.49.0")
```

```yaml
# application.yml
spring:
  exposed:
    generate-ddl: false          # Use Flyway instead
    excluded-packages: ""        # Packages to skip for schema scan
```

The `exposed-spring-boot-starter` auto-configures `SpringTransactionManager` and wires it to the Spring `DataSource` — no manual bean definition needed.

## Framework-Specific Patterns

### SpringTransactionManager + @Transactional

```kotlin
@Service
@Transactional
class OrderService(private val db: Database) {
    fun createOrder(cmd: CreateOrderCmd): OrderId =
        transaction {  // Uses the Spring-managed transaction
            Orders.insertAndGetId { it[customerId] = cmd.customerId }
                .let { OrderId(it.value) }
        }
}
```

Exposed's `transaction {}` block participates in the existing Spring transaction when `SpringTransactionManager` is configured. Do not open a new `transaction {}` inside a `@Transactional` method — it will join the same connection.

### Coroutine Transaction Scope

```kotlin
@Transactional
suspend fun findActiveOrders(): List<Order> =
    newSuspendedTransaction(Dispatchers.IO) {
        Orders.selectAll()
            .where { Orders.status eq OrderStatus.ACTIVE }
            .map { it.toOrder() }
    }
```

Use `newSuspendedTransaction` for coroutine-aware DB access. Requires `exposed-spring-boot-starter` 0.48+.

### Testing Equivalent to @DataJpaTest

```kotlin
@SpringBootTest(classes = [ExposedTestConfig::class])
@Transactional
class OrderRepositoryTest {
    // Full Exposed + SpringTransactionManager context
    // @Transactional rolls back after each test
}

@TestConfiguration
class ExposedTestConfig {
    @Bean
    @ServiceConnection
    fun postgres(): PostgreSQLContainer<*> = PostgreSQLContainer("postgres:16-alpine")
}
```

There is no `@DataExposedTest` slice — use a narrow `@SpringBootTest` with only persistence beans.

## Scaffolder Patterns

```yaml
patterns:
  table_object: "src/main/kotlin/{package}/persistence/tables/{Entity}Table.kt"
  repository: "src/main/kotlin/{package}/persistence/{Entity}Repository.kt"
  test_config: "src/test/kotlin/{package}/config/ExposedTestConfig.kt"
```

## Additional Dos/Don'ts

- DO use `SpringTransactionManager` — never create a bare `Database.connect()` alongside Spring's `DataSource`
- DO map `ResultRow` to domain types at the repository boundary; never expose `ResultRow` to services
- DO use `exposed-kotlin-datetime` types (`kotlinx.datetime.Instant`) instead of Java `Date`
- DON'T call `transaction {}` inside a method already annotated `@Transactional` — use the block or the annotation, not both
- DON'T enable `generate-ddl: true` in production; let Flyway manage schema
