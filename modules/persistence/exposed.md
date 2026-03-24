# Kotlin Exposed Best Practices

## Overview
Exposed is a lightweight Kotlin SQL library from JetBrains with two APIs: a type-safe DSL for SQL-like queries and a DAO layer for active-record style access. Use it for Kotlin-first projects needing type-safe queries without full ORM weight. Avoid it for projects requiring JPA compatibility, complex inheritance mappings, or L2 caching infrastructure.

## Architecture Patterns

### DSL vs DAO — Choosing Wisely
```kotlin
// DSL: preferred for complex queries, batch ops, reporting
val results = Users
    .join(Orders, JoinType.LEFT, Users.id, Orders.userId)
    .select { Users.active eq true }
    .orderBy(Users.createdAt, SortOrder.DESC)
    .limit(50)
    .map { row -> UserDto(row[Users.id].value, row[Users.email]) }

// DAO: preferred for CRUD-heavy domain objects with lifecycle
class User(id: EntityID<Int>) : IntEntity(id) {
    companion object : IntEntityClass<User>(Users)
    var email by Users.email
    var name  by Users.name
    val orders by Order referrersOn Orders.userId
}
```

### Table Definitions
```kotlin
object Users : IntIdTable("users") {
    val email     = varchar("email", 255).uniqueIndex()
    val name      = varchar("name", 100)
    val active    = bool("active").default(true)
    val createdAt = timestamp("created_at")
                        .defaultExpression(CurrentTimestamp())
}

object Orders : LongIdTable("orders") {
    val userId    = reference("user_id", Users, onDelete = ReferenceOption.CASCADE)
    val total     = decimal("total", 10, 2)
    val status    = enumerationByName("status", 20, OrderStatus::class)
}
```

### Custom Column Types
```kotlin
class UUIDColumnType : ColumnType() {
    override fun sqlType() = "UUID"
    override fun valueFromDB(value: Any): UUID = when (value) {
        is UUID   -> value
        is String -> UUID.fromString(value)
        else      -> error("Unexpected value: $value")
    }
}
fun Table.uuid(name: String) = registerColumn<UUID>(name, UUIDColumnType())
```

## Configuration

```kotlin
// Ktor / standalone wiring
Database.connect(
    url      = "jdbc:postgresql://localhost:5432/mydb",
    driver   = "org.postgresql.Driver",
    user     = env("DB_USER"),
    password = env("DB_PASSWORD")
)

// With HikariCP connection pooling
val config = HikariConfig().apply {
    jdbcUrl         = env("DB_URL")
    maximumPoolSize = 10
    minimumIdle     = 2
    isAutoCommit    = false    // Exposed manages transactions
    transactionIsolation = "TRANSACTION_REPEATABLE_READ"
}
Database.connect(HikariDataSource(config))
```

## Performance

### Batch Operations
```kotlin
transaction {
    // Batch insert
    Users.batchInsert(userDtos) { dto ->
        this[Users.email] = dto.email
        this[Users.name]  = dto.name
    }

    // Bulk update with upsert
    Users.upsert(Users.email) {
        it[email]  = "new@example.com"
        it[active] = true
    }
}
```

### Coroutine Support
```kotlin
// Use newSuspendedTransaction for suspend contexts
suspend fun findActiveUsers(): List<UserDto> = newSuspendedTransaction(Dispatchers.IO) {
    Users.selectAll()
        .where { Users.active eq true }
        .map { UserDto(it[Users.id].value, it[Users.email]) }
}

// Configure dispatcher for all transactions globally
TransactionManager.defaultDatabase?.let {
    TransactionManager.manager.defaultIsolationLevel =
        Connection.TRANSACTION_READ_COMMITTED
}
```

### Eager Loading to Prevent N+1
```kotlin
// DAO: use .with() to eagerly load references
transaction {
    User.all().with(User::orders).forEach { user ->
        println(user.orders.count()) // no extra queries
    }
}

// DSL: explicit join is always explicit — no hidden queries
Users.join(Orders, JoinType.LEFT, Users.id, Orders.userId)
    .selectAll()
    .groupBy { it[Users.id] }
```

## Security

```kotlin
// Safe: Exposed parameterizes values automatically
Users.selectAll().where { Users.email eq userInput }

// Safe: explicit parameterized expression
val stmt = Users.selectAll()
    .where { Users.email like "%${userInput.replace("%", "\\%")}%" }

// Never build raw SQL with user input — use stringLiteral() if needed
Op.build { Users.name eq stringLiteral(sanitized) }
```

## Testing

```kotlin
class UserRepositoryTest {
    companion object {
        @Container val db = PostgreSQLContainer<Nothing>("postgres:16-alpine")
            .apply { start() }
    }

    @BeforeEach fun setup() {
        Database.connect(db.jdbcUrl, "org.postgresql.Driver", db.username, db.password)
        transaction { SchemaUtils.create(Users, Orders) }
    }

    @AfterEach fun teardown() {
        transaction { SchemaUtils.drop(Orders, Users) }
    }

    @Test fun `batchInsert persists all users`() = transaction {
        Users.batchInsert(listOf("a@test.com", "b@test.com")) {
            this[Users.email] = it; this[Users.name] = "Test"
        }
        assertEquals(2, Users.selectAll().count())
    }
}
```

## Dos
- Prefer the DSL API for read queries and batch operations; use DAO for entities with rich lifecycle.
- Always wrap operations in `transaction { }` — Exposed requires an active transaction context.
- Use `newSuspendedTransaction(Dispatchers.IO)` in coroutine contexts to avoid blocking the event loop.
- Use `batchInsert` instead of looping `insert` calls — dramatically reduces round trips.
- Define `onDelete = ReferenceOption.CASCADE` on FK columns to maintain referential integrity.
- Use `SchemaUtils.createMissingTablesAndColumns()` in dev; use Flyway/Liquibase in production.
- Set `isAutoCommit = false` in HikariCP config — Exposed manages commits explicitly.

## Don'ts
- Don't access DAO relations outside a `transaction { }` block — causes `IllegalStateException`.
- Don't use `.with()` when you only need one entity — single eager loads add unnecessary overhead.
- Don't mix DAO and DSL for the same table in the same transaction without understanding cache invalidation.
- Don't share `Database` connections across threads without a proper connection pool.
- Don't use `SchemaUtils.create` in production migrations — it is not idempotent across schema changes.
- Don't forget to add indexes on FK columns and frequently filtered columns.
- Don't use `selectAll()` on large tables without `.limit()` or `.where()` — full table scans.
