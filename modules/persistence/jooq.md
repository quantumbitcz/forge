# jOOQ Best Practices

## Overview
jOOQ generates type-safe Java/Kotlin DSL from your actual database schema, giving you the full power of SQL with compile-time correctness. Use it when you need complex SQL (CTEs, window functions, LATERAL joins, stored procs) without losing type safety. Avoid it for simple CRUD-only applications where the code generation step adds friction without benefit.

## Architecture Patterns

### Code Generation Setup
```xml
<!-- pom.xml / build.gradle.kts — generate from live DB or DDL scripts -->
<generator>
  <database>
    <name>org.jooq.meta.postgres.PostgresDatabase</name>
    <inputSchema>public</inputSchema>
  </database>
  <target>
    <packageName>com.example.db.generated</packageName>
    <directory>src/main/generated</directory>
  </target>
</generator>
```

### Repository Pattern
```kotlin
// Wrap DSLContext — inject via Spring/Koin, never instantiate directly
@Repository
class OrderRepository(private val dsl: DSLContext) {

    fun findByIdWithItems(orderId: Long): OrderWithItems? =
        dsl.select(
                ORDERS.asterisk(),
                multiset(
                    select(ORDER_ITEMS.asterisk())
                        .from(ORDER_ITEMS)
                        .where(ORDER_ITEMS.ORDER_ID.eq(ORDERS.ID))
                ).`as`("items").convertFrom { it.into(OrderItem::class.java) }
            )
            .from(ORDERS)
            .where(ORDERS.ID.eq(orderId))
            .fetchOne { it.into(OrderWithItems::class.java) }
}
```

### Dynamic Queries
```kotlin
fun search(filter: OrderFilter): List<OrderRecord> {
    val conditions = buildList {
        filter.status?.let { add(ORDERS.STATUS.eq(it.name)) }
        filter.minTotal?.let { add(ORDERS.TOTAL.ge(it)) }
        filter.customerId?.let { add(ORDERS.CUSTOMER_ID.eq(it)) }
    }
    return dsl.selectFrom(ORDERS)
        .where(DSL.and(conditions))
        .orderBy(ORDERS.CREATED_AT.desc())
        .fetch()
}
```

### Stored Procedures and Plain SQL
```kotlin
// Stored procedure (generated)
val result = GetOrderSummary().apply {
    setOrderId(42L)
    execute(dsl.configuration())
}

// Plain SQL with typed binding — safe parameterization
val customSql = dsl.resultQuery(
    "SELECT * FROM orders WHERE jsonb_column->>'key' = {0}",
    DSL.`val`(userInput)
).fetchInto(Order::class.java)
```

## Configuration

```kotlin
@Configuration
class JooqConfig(private val dataSource: DataSource) {

    @Bean
    fun dslContext(): DSLContext = DSL.using(
        dataSource,
        SQLDialect.POSTGRES
    ).apply {
        settings()
            .withRenderNameStyle(RenderNameStyle.QUOTED)
            .withExecuteLogging(false)   // use structured logging listener instead
    }

    @Bean
    fun jooqExecuteListener() = object : DefaultExecuteListener() {
        override fun executeStart(ctx: ExecuteContext) {
            log.debug("jOOQ: {}", ctx.query()?.toString())
        }
    }
}
```

## Performance

### Batch Operations
```kotlin
// Batch inserts — single prepared statement, multiple bindings
dsl.batch(
    products.map { p ->
        dsl.insertInto(PRODUCTS)
            .set(PRODUCTS.NAME, p.name)
            .set(PRODUCTS.PRICE, p.price)
    }
).execute()

// Bulk upsert with ON CONFLICT
dsl.insertInto(PRICES, PRICES.SKU, PRICES.AMOUNT)
    .valuesOfRows(prices.map { row(it.sku, it.amount) })
    .onConflict(PRICES.SKU)
    .doUpdate()
    .set(PRICES.AMOUNT, excluded(PRICES.AMOUNT))
    .execute()
```

### Record Mapping and Projection
```kotlin
// Fetch only needed columns — avoids SELECT *
data class OrderSummary(val id: Long, val total: BigDecimal, val status: String)

val summaries = dsl
    .select(ORDERS.ID, ORDERS.TOTAL, ORDERS.STATUS)
    .from(ORDERS)
    .where(ORDERS.CUSTOMER_ID.eq(customerId))
    .fetchInto(OrderSummary::class.java)
```

### Window Functions and CTEs
```kotlin
val ranked = dsl.with("ranked").`as`(
    select(ORDERS.asterisk(),
           rowNumber().over(partitionBy(ORDERS.CUSTOMER_ID)
                                .orderBy(ORDERS.CREATED_AT.desc()))
               .`as`("rn"))
        .from(ORDERS)
)
.select().from(DSL.table(DSL.name("ranked")))
.where(DSL.field(DSL.name("rn")).eq(1))
.fetchInto(Order::class.java)
```

## Security

```kotlin
// SAFE: all DSL conditions are parameterized — jOOQ never interpolates strings
dsl.selectFrom(USERS).where(USERS.EMAIL.eq(userInput))

// SAFE: explicit DSL.param for plain SQL
dsl.resultQuery("SELECT * FROM users WHERE role = {0}", DSL.param("role", userInput))

// UNSAFE: never use DSL.field(userInput) — allows schema injection
// UNSAFE: never use String.format() inside .condition(...)
```

## Testing

```kotlin
@SpringBootTest
@Testcontainers
class OrderRepositoryTest {
    @Container
    val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine")
        .withInitScript("schema.sql")

    @Autowired lateinit var orderRepo: OrderRepository

    @Test
    fun `findByIdWithItems returns nested items`() {
        val order = orderRepo.findByIdWithItems(1L)
        assertThat(order).isNotNull
        assertThat(order!!.items).hasSize(2)
    }
}

// Unit test with mock DSLContext (for pure logic tests)
val mockDsl = mock<DSLContext>()
// jOOQ's MockDataProvider can replay recorded queries for fast unit tests
val provider = MockDataProvider { ctx ->
    arrayOf(MockResult(1, dsl.newResult(ORDERS.ID, ORDERS.TOTAL)))
}
val mockConn = MockConnection(provider)
val testDsl  = DSL.using(mockConn, SQLDialect.POSTGRES)
```

## Dos
- Generate code from the real database schema using jOOQ's code generator — never hand-write table/field references.
- Use `multiset()` for nested collection queries instead of joining and de-duplicating in application code.
- Use `dsl.batch(...)` for multi-row inserts/updates — avoids per-row round trips.
- Use `fetchInto(DataClass::class.java)` with value classes or records for clean projection.
- Inject `DSLContext` via DI — never call `DSL.using(...)` in business logic.
- Use `onConflict(...).doUpdate()` for upsert semantics instead of select-then-insert.
- Add a logging `ExecuteListener` for structured SQL query tracing in development.

## Don'ts
- Don't use `DSL.field(userString)` with user input — allows identifier injection.
- Don't call `fetch()` without `.limit()` on potentially large tables.
- Don't use `fetchLazy()` (cursor) without closing the cursor — causes connection leaks.
- Don't skip code regeneration after schema migrations — stale generated code causes runtime errors.
- Don't mix jOOQ and Hibernate on the same transaction boundary without careful isolation.
- Don't use `record.store()` active-record style in complex domain logic — prefer explicit repository methods.
- Don't log full query strings with bound parameters in production — may expose PII.
