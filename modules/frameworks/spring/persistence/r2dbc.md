# R2DBC with Spring

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-data-r2dbc")
implementation("org.postgresql:r2dbc-postgresql")
implementation("io.r2dbc:r2dbc-pool")
```

```yaml
# application.yml
spring:
  r2dbc:
    url: r2dbc:postgresql://${DB_HOST:localhost}:5432/${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    pool:
      initial-size: 2
      max-size: 10
      max-idle-time: 30m
      validation-query: SELECT 1
```

## Framework-Specific Patterns

### ReactiveCrudRepository

```kotlin
interface OrderRepository : ReactiveCrudRepository<Order, UUID> {
    fun findByCustomerId(customerId: UUID): Flux<Order>

    @Query("SELECT * FROM orders WHERE status = :status LIMIT :limit")
    fun findByStatus(status: String, limit: Int): Flux<Order>
}
```

Use `@Query` for any query with joins or complex predicates — derived query methods are limited in R2DBC.

### @Transactional with Coroutines

```kotlin
@Service
@Transactional
class OrderService(private val repo: OrderRepository) {
    suspend fun placeOrder(cmd: PlaceOrderCmd): Order {
        val order = Order(customerId = cmd.customerId, status = OrderStatus.PENDING)
        return repo.save(order).awaitSingle()
    }
}
```

`@Transactional` works with coroutines via `TransactionalOperator` under the hood. Always use `suspend` functions in reactive Spring services.

### DatabaseClient for Complex Queries

```kotlin
@Repository
class ReportRepository(private val client: DatabaseClient) {
    fun salesSummary(from: LocalDate): Flux<SalesSummaryRow> =
        client.sql("""
            SELECT date_trunc('day', created_at) AS day, SUM(amount) AS total
            FROM orders WHERE created_at >= :from GROUP BY 1
        """)
            .bind("from", from)
            .map { row, _ ->
                SalesSummaryRow(
                    day = row.get("day", LocalDate::class.java)!!,
                    total = row.get("total", BigDecimal::class.java)!!
                )
            }
            .all()
}
```

### R2DBC UPDATE Sets All Columns

R2DBC's `save()` issues a full `UPDATE` (all columns). For partial updates, use `@Query`:

```kotlin
@Query("UPDATE orders SET status = :status WHERE id = :id")
fun updateStatus(id: UUID, status: String): Mono<Int>
```

## Scaffolder Patterns

```yaml
patterns:
  repository: "src/main/kotlin/{package}/persistence/{Entity}Repository.kt"
  db_client_repo: "src/main/kotlin/{package}/persistence/{Entity}QueryRepository.kt"
  r2dbc_config: "src/main/kotlin/{package}/config/R2dbcConfig.kt"
```

## Additional Dos/Don'ts

- DO use `@Query` for partial updates — never rely on `save()` for field-level patches
- DO configure `r2dbc-pool` explicitly; the default pool is unbounded
- DO use `awaitSingle()` / `awaitFirstOrNull()` in suspend functions instead of `.block()`
- DON'T mix blocking JDBC calls on the R2DBC connection pool thread
- DON'T use `@OneToMany` / `@ManyToOne` JPA annotations — R2DBC has no ORM join support
