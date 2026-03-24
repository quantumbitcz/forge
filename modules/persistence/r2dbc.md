# Spring Data R2DBC Best Practices

## Overview
Spring Data R2DBC provides reactive, non-blocking database access for Spring WebFlux applications. Use it when you need fully reactive end-to-end pipelines (Mono/Flux throughout) with no blocking I/O. Avoid it if your team is unfamiliar with reactive programming, if your database driver lacks R2DBC support, or if you need JPA features like L2 caching and entity graphs.

## Architecture Patterns

### Entity Design
```kotlin
// Annotations are from spring-data — no JPA annotations
@Table("orders")
data class Order(
    @Id val id: Long? = null,
    @Column("customer_id") val customerId: Long,
    val total: BigDecimal,
    val status: String = "pending",
    @CreatedDate val createdAt: Instant? = null
)

// R2DBC does NOT support @OneToMany — aggregate roots only
// Relationships must be loaded via separate queries
```

### Repository Pattern
```kotlin
@Repository
interface OrderRepository : ReactiveCrudRepository<Order, Long> {

    // R2DBC UPDATE sets ALL columns — use @Query for partial updates
    @Query("UPDATE orders SET status = :status WHERE id = :id")
    fun updateStatus(id: Long, status: String): Mono<Void>

    @Query("SELECT * FROM orders WHERE customer_id = :customerId ORDER BY created_at DESC LIMIT :limit")
    fun findByCustomerId(customerId: Long, limit: Int): Flux<Order>

    @Query("""
        SELECT o.*, c.name AS customer_name
        FROM orders o JOIN customers c ON c.id = o.customer_id
        WHERE o.status = :status
    """)
    fun findWithCustomerByStatus(status: String): Flux<OrderWithCustomer>
}
```

### DatabaseClient for Complex Queries
```kotlin
@Repository
class OrderDatabaseClient(private val client: DatabaseClient) {

    fun findOrdersWithItems(orderId: Long): Mono<OrderWithItems> =
        client.sql("""
            SELECT o.id, o.total, oi.id AS item_id, oi.product_name, oi.quantity
            FROM orders o
            LEFT JOIN order_items oi ON oi.order_id = o.id
            WHERE o.id = :orderId
        """)
        .bind("orderId", orderId)
        .fetch()
        .all()
        .bufferUntilChanged { it["id"] }
        .map { rows -> mapToOrderWithItems(rows) }
        .single()
}
```

### Connection Pooling (r2dbc-pool)
```kotlin
@Configuration
class R2dbcConfig {
    @Bean
    fun connectionFactory(): ConnectionFactory {
        val base = PostgresqlConnectionFactory(
            PostgresqlConnectionConfiguration.builder()
                .host(env("DB_HOST"))
                .port(5432)
                .database(env("DB_NAME"))
                .username(env("DB_USER"))
                .password(env("DB_PASSWORD"))
                .build()
        )
        return ConnectionPool(
            ConnectionPoolConfiguration.builder(base)
                .maxSize(10)
                .minIdle(2)
                .maxIdleTime(Duration.ofMinutes(30))
                .validationQuery("SELECT 1")
                .build()
        )
    }
}
```

## Configuration

```yaml
# application.yml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/mydb
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    pool:
      max-size: 10
      min-idle: 2
      max-idle-time: 30m
      validation-query: SELECT 1
  data:
    r2dbc:
      repositories:
        enabled: true
```

## Performance

### Avoiding N+1 in Reactive Pipelines
```kotlin
// N+1 anti-pattern: loading orders then fetching customer per order
orderRepo.findAll()
    .flatMap { order -> customerRepo.findById(order.customerId)  // N+1!
        .map { customer -> order.copy(customerName = customer.name) }
    }

// Fix: join in SQL, or use flatMap with concatMap for controlled concurrency
orderRepo.findAll()
    .collectList()
    .flatMap { orders ->
        val ids = orders.map { it.customerId }.toSet()
        customerRepo.findAllById(ids)
            .collectMap { it.id }
            .map { customerMap -> orders.map { it to customerMap[it.customerId] } }
    }
```

### Batch Inserts with R2DBC
```kotlin
// Use saveAll for batch inserts — Spring Data batches when possible
orderRepo.saveAll(newOrders.asFlux())
    .then()
    .awaitSingleOrNull()

// Or DatabaseClient for raw bulk insert
client.sql("INSERT INTO orders (customer_id, total) VALUES (:cid, :total)")
    .bind("cid", customerId)
    .bind("total", total)
    .fetch()
    .rowsUpdated()
```

### Backpressure Management
```kotlin
// Use limitRate to control upstream demand
orderRepo.findAll()
    .limitRate(100)          // fetch 100 rows at a time
    .publishOn(Schedulers.boundedElastic())
    .map { process(it) }
    .subscribe()
```

## Security

```kotlin
// SAFE: DatabaseClient always parameterizes bindings
client.sql("SELECT * FROM users WHERE email = :email")
    .bind("email", userInput)
    .fetch().one()

// UNSAFE: never use string interpolation in SQL strings
// client.sql("SELECT * FROM users WHERE email = '$userInput'")

// Row-level security: filter by tenant in every query
fun findOrdersForTenant(tenantId: Long): Flux<Order> =
    orderRepo.findByTenantId(tenantId)  // always scope queries to tenant
```

## Testing

```kotlin
@DataR2dbcTest
@Testcontainers
class OrderRepositoryTest {
    @Container
    val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine")

    @DynamicPropertySource
    companion object {
        @JvmStatic
        fun properties(registry: DynamicPropertyRegistry) {
            registry.add("spring.r2dbc.url") {
                "r2dbc:postgresql://${postgres.host}:${postgres.getMappedPort(5432)}/${postgres.databaseName}"
            }
            registry.add("spring.r2dbc.username") { postgres.username }
            registry.add("spring.r2dbc.password") { postgres.password }
        }
    }

    @Autowired lateinit var orderRepo: OrderRepository

    @Test
    fun `updateStatus modifies only status column`() = runTest {
        val order = orderRepo.save(Order(customerId = 1L, total = BigDecimal("99.99"))).awaitSingle()
        orderRepo.updateStatus(order.id!!, "shipped").awaitSingleOrNull()
        val updated = orderRepo.findById(order.id!!).awaitSingle()
        assertEquals("shipped", updated.status)
        assertEquals(order.total, updated.total)  // unchanged
    }
}
```

## Dos
- Use `@Query` with explicit SQL for partial updates — R2DBC's `save()` always sets all columns.
- Use `DatabaseClient` for complex multi-table queries that repository interfaces cannot express.
- Configure `r2dbc-pool` explicitly — the default pool settings are too conservative for production.
- Use `awaitSingle()` / `awaitSingleOrNull()` in coroutine contexts (Spring Coroutines bridge).
- Add `validationQuery: SELECT 1` to the pool config to recover from idle connection drops.
- Use `@CreatedDate` / `@LastModifiedDate` with `@EnableR2dbcAuditing` for automatic timestamps.
- Scope every query to the current tenant/user when building multi-tenant systems.

## Don'ts
- Don't use R2DBC's `save()` for partial updates on entities with many columns — it will overwrite all fields.
- Don't load relations via `@OneToMany` — R2DBC does not support JPA associations; join in SQL.
- Don't block inside reactive pipelines (`block()`, `Thread.sleep()`) — deadlocks the event loop.
- Don't use `flatMap` for sequential dependent operations with high concurrency — prefer `concatMap` or chain with `.then()`.
- Don't skip connection pool validation — idle connections drop silently without a health check.
- Don't mix R2DBC repositories with JPA repositories in the same application context without careful configuration.
- Don't use `Flux.fromIterable(list).flatMap(repo::save)` for bulk inserts — use `saveAll(publisher)` instead.
