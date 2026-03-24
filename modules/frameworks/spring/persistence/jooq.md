# jOOQ with Spring

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-jooq")

// Code generation
jooq {
    configurations {
        create("main") {
            jooqConfiguration.apply {
                jdbc.apply {
                    driver = "org.postgresql.Driver"
                    url = "jdbc:postgresql://localhost:5432/mydb"
                    user = "postgres"
                    password = "postgres"
                }
                generator.apply {
                    database.apply {
                        name = "org.jooq.meta.postgres.PostgresDatabase"
                        includes = ".*"
                        excludes = "flyway_schema_history"
                        inputSchema = "public"
                    }
                    target.apply {
                        packageName = "com.example.db"
                        directory = "build/generated-src/jooq/main"
                    }
                }
            }
        }
    }
}
```

## Framework-Specific Patterns

### DSLContext Injection

```kotlin
@Repository
class OrderRepository(private val dsl: DSLContext) {
    fun findByCustomer(customerId: UUID): List<OrderRecord> =
        dsl.selectFrom(ORDER)
            .where(ORDER.CUSTOMER_ID.eq(customerId))
            .fetchInto(OrderRecord::class.java)
}
```

`spring-boot-starter-jooq` auto-configures `DSLContext` as a bean — inject directly.

### @Transactional Integration

```kotlin
@Service
@Transactional
class OrderService(private val dsl: DSLContext) {
    fun placeOrder(cmd: PlaceOrderCmd) {
        // jOOQ uses the Spring-managed transaction automatically
        dsl.insertInto(ORDER)
            .set(ORDER.CUSTOMER_ID, cmd.customerId)
            .set(ORDER.STATUS, "PENDING")
            .execute()
    }
}
```

Spring's `JooqExceptionTranslator` is auto-registered, translating jOOQ exceptions to Spring `DataAccessException`.

### Optimistic Locking with Version Field

```kotlin
dsl.update(PRODUCT)
    .set(PRODUCT.STOCK, PRODUCT.STOCK.minus(quantity))
    .set(PRODUCT.VERSION, PRODUCT.VERSION.plus(1))
    .where(PRODUCT.ID.eq(productId))
    .and(PRODUCT.VERSION.eq(expectedVersion))
    .execute()
    .also { updated -> if (updated == 0) throw OptimisticLockException(productId) }
```

## Scaffolder Patterns

```yaml
patterns:
  repository: "src/main/kotlin/{package}/persistence/{Entity}Repository.kt"
  jooq_config: "build.gradle.kts"          # Generation config inline in build file
  generated_src: "build/generated-src/jooq/main/{package}/tables/"
```

## Additional Dos/Don'ts

- DO run jOOQ codegen against a real DB schema (via Testcontainers in Gradle task) — not a mock
- DO add `build/generated-src/jooq/main` to version control if schema is stable
- DO use `dsl.transactionResult {}` for nested transactions within a service call
- DON'T write raw SQL strings — jOOQ's type-safe DSL is the whole point
- DON'T share `DSLContext` across threads without understanding connection pool implications
