# JetBrains Koog (Kotlin ORM) Best Practices

## Overview
Koog is JetBrains' experimental Kotlin-first ORM with coroutine-native design and Kotlin Multiplatform (KMP) support. Use it for greenfield Kotlin/KMP projects that need a pure-Kotlin persistence layer with suspend functions throughout. Avoid it for projects requiring JPA compatibility, mature L2 caching, or production-critical stability — Koog is still evolving and its API surface may change.

## Architecture Patterns

### Schema Definition in Kotlin
```kotlin
// Define schema as Kotlin objects — single source of truth
object UsersTable : Table("users") {
    val id        = long("id").primaryKey().autoIncrement()
    val email     = varchar("email", 255).unique()
    val name      = varchar("name", 100)
    val createdAt = timestamp("created_at").default { Clock.System.now() }
}

object OrdersTable : Table("orders") {
    val id         = long("id").primaryKey().autoIncrement()
    val userId     = long("user_id").references(UsersTable.id)
    val total      = decimal("total", 10, 2)
    val status     = varchar("status", 20).default { "pending" }
}
```

### Repository Pattern
```kotlin
class UserRepository(private val db: Database) {

    suspend fun findById(id: Long): User? = db.query {
        UsersTable.selectAll()
            .where { UsersTable.id eq id }
            .singleOrNull()
            ?.toUser()
    }

    suspend fun save(user: NewUser): User = db.transaction {
        val id = UsersTable.insert {
            it[email] = user.email
            it[name]  = user.name
        }
        findById(id) ?: error("Insert failed")
    }

    private fun ResultRow.toUser() = User(
        id    = this[UsersTable.id],
        email = this[UsersTable.email],
        name  = this[UsersTable.name]
    )
}
```

### Coroutine-First Transaction Management
```kotlin
// All DB operations are suspend functions
suspend fun transferFunds(fromId: Long, toId: Long, amount: BigDecimal) =
    db.transaction {
        val from = AccountsTable.selectAll()
            .where { AccountsTable.id eq fromId }
            .single()
        require(from[AccountsTable.balance] >= amount) { "Insufficient funds" }

        AccountsTable.update({ AccountsTable.id eq fromId }) {
            it[balance] = from[AccountsTable.balance] - amount
        }
        AccountsTable.update({ AccountsTable.id eq toId }) {
            it[balance] = AccountsTable.balance + amount
        }
    }
```

### KMP Considerations
```kotlin
// commonMain: define interfaces and domain models
interface UserRepository {
    suspend fun findById(id: Long): User?
    suspend fun save(user: NewUser): User
}

// jvmMain / nativeMain: provide platform-specific implementations
// Use expect/actual for database driver selection across platforms
expect fun createDatabase(config: DatabaseConfig): Database
```

## Configuration

```kotlin
// JVM setup with connection pooling
val database = Database.connect(
    config = DatabaseConfig(
        url      = System.getenv("DB_URL"),
        driver   = "org.postgresql.Driver",
        user     = System.getenv("DB_USER"),
        password = System.getenv("DB_PASSWORD"),
        poolSize = 10
    )
)

// Schema creation / migration
database.query {
    SchemaUtils.createMissing(UsersTable, OrdersTable)
}
// Production: delegate to Flyway/Liquibase instead
```

## Performance

### Batch Operations
```kotlin
suspend fun bulkInsertUsers(users: List<NewUser>): Unit = db.transaction {
    UsersTable.batchInsert(users) { user ->
        this[UsersTable.email] = user.email
        this[UsersTable.name]  = user.name
    }
}
```

### Preventing N+1 via Explicit Joins
```kotlin
// Koog does not auto-load relations — make joins explicit
suspend fun findUsersWithOrders(): List<UserWithOrders> = db.query {
    (UsersTable leftJoin OrdersTable)
        .selectAll()
        .groupBy({ it[UsersTable.id] }) { row ->
            row[OrdersTable.id]?.let { orderId ->
                Order(id = orderId, total = row[OrdersTable.total])
            }
        }
        .map { (userId, orders) ->
            UserWithOrders(userId, orders.filterNotNull())
        }
}
```

### Migration Support
```kotlin
// Define migrations as versioned Kotlin objects
object V1__CreateUsers : Migration(1) {
    override suspend fun up(db: Database) {
        db.query { SchemaUtils.create(UsersTable) }
    }
    override suspend fun down(db: Database) {
        db.query { SchemaUtils.drop(UsersTable) }
    }
}

val migrationRunner = MigrationRunner(db, listOf(V1__CreateUsers, V2__AddOrders))
migrationRunner.runPending()
```

## Security

```kotlin
// Safe: all Koog query builders parameterize values
UsersTable.selectAll().where { UsersTable.email eq userInputEmail }

// Safe: explicit parameter binding in raw queries
db.query {
    rawQuery("SELECT * FROM users WHERE email = ?", listOf(userInputEmail))
}

// UNSAFE: never interpolate user input into raw SQL strings
// db.query { rawQuery("SELECT * FROM users WHERE email = '$userInput'") }
```

## Testing

```kotlin
class UserRepositoryTest {
    private lateinit var db: Database
    private lateinit var repo: UserRepository

    @BeforeEach fun setup() {
        // Use H2 or SQLite in-memory for fast unit tests
        db = Database.connect(
            DatabaseConfig(url = "jdbc:h2:mem:test;DB_CLOSE_DELAY=-1",
                           driver = "org.h2.Driver")
        )
        runBlocking { db.query { SchemaUtils.create(UsersTable) } }
        repo = UserRepository(db)
    }

    @Test fun `save and findById round-trip`() = runTest {
        val saved = repo.save(NewUser("alice@test.com", "Alice"))
        val found = repo.findById(saved.id)
        assertEquals("alice@test.com", found?.email)
    }
}

// Integration test with Testcontainers for PostgreSQL
@Testcontainers
class UserRepositoryIntegrationTest {
    @Container
    val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine")
    // connect db to postgres.jdbcUrl ...
}
```

## Dos
- Always use `db.transaction { }` for multi-step writes — Koog transactions are suspend-safe.
- Use `db.query { }` (read-only scope) vs `db.transaction { }` (read-write) to signal intent clearly.
- Expose domain interfaces (`UserRepository`) in commonMain; place Koog implementations in platform source sets.
- Use `batchInsert` for bulk writes — avoids per-row coroutine suspension overhead.
- Favor explicit joins over in-memory aggregation to keep data transfer minimal.
- Pin Koog versions exactly in `libs.versions.toml` — API stability is not yet guaranteed.
- Use Flyway/Liquibase for production schema migrations; use Koog's `SchemaUtils` only in dev/test.

## Don'ts
- Don't use Koog for production-critical systems without thorough evaluation — it is experimental.
- Don't rely on automatic relation loading — Koog requires explicit joins; implicit lazy loading is not supported.
- Don't block inside `db.query { }` or `db.transaction { }` — keep the coroutine dispatcher free.
- Don't share `Database` instances across test cases without resetting state between tests.
- Don't use raw query methods with string interpolation for user-supplied values — parameterize explicitly.
- Don't mix Koog and JDBC directly in the same transaction boundary without understanding isolation.
- Don't use `SchemaUtils.create` in production — it is not migration-aware and will fail on existing tables.
