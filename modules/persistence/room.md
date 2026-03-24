# Android Room Best Practices

## Overview
Room is Android's official persistence library, providing an abstraction layer over SQLite with compile-time query verification, coroutine/Flow support, and automatic migration tooling. Use it for all Android local storage needs beyond simple key-value pairs. Avoid it for complex analytical queries or large datasets where SQLite performance limits become a concern — consider realm or a server-side solution.

## Architecture Patterns

### Entity Design
```kotlin
@Entity(
    tableName = "orders",
    foreignKeys = [ForeignKey(
        entity     = User::class,
        parentColumns = ["id"],
        childColumns  = ["user_id"],
        onDelete   = ForeignKey.CASCADE
    )],
    indices = [Index("user_id"), Index(value = ["status", "created_at"])]
)
data class OrderEntity(
    @PrimaryKey(autoGenerate = true)
    val id:        Long       = 0,
    @ColumnInfo(name = "user_id")
    val userId:    Long,
    val total:     Double,
    val status:    String     = "pending",
    @ColumnInfo(name = "created_at")
    val createdAt: Long       = System.currentTimeMillis()
)

// Embedded object — flattened into parent table columns
data class Address(val street: String, val city: String, val zip: String)

@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val email: String,
    @Embedded val address: Address? = null
)
```

### DAO Pattern
```kotlin
@Dao
interface OrderDao {
    @Query("SELECT * FROM orders WHERE id = :id")
    suspend fun findById(id: Long): OrderEntity?

    @Query("SELECT * FROM orders WHERE user_id = :userId ORDER BY created_at DESC")
    fun observeByUserId(userId: Long): Flow<List<OrderEntity>>

    @Query("SELECT * FROM orders WHERE user_id = :userId ORDER BY created_at DESC")
    suspend fun findByUserId(userId: Long): List<OrderEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(order: OrderEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(orders: List<OrderEntity>)

    @Update
    suspend fun update(order: OrderEntity)

    @Query("UPDATE orders SET status = :status WHERE id = :id")
    suspend fun updateStatus(id: Long, status: String)

    @Delete
    suspend fun delete(order: OrderEntity)

    @Query("DELETE FROM orders WHERE user_id = :userId")
    suspend fun deleteByUserId(userId: Long)
}
```

### Relations
```kotlin
// One-to-many relation
data class UserWithOrders(
    @Embedded val user: UserEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "user_id"
    )
    val orders: List<OrderEntity>
)

@Dao
interface UserDao {
    @Transaction
    @Query("SELECT * FROM users WHERE id = :userId")
    suspend fun getUserWithOrders(userId: Long): UserWithOrders?

    // Many-to-many via junction table
    @Transaction
    @Query("SELECT * FROM products")
    fun observeProductsWithTags(): Flow<List<ProductWithTags>>
}
```

### Database Definition
```kotlin
@Database(
    entities  = [UserEntity::class, OrderEntity::class, OrderItemEntity::class],
    version   = 3,
    exportSchema = true              // export schema JSON for migration testing
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun userDao():  UserDao
    abstract fun orderDao(): OrderDao

    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase =
            INSTANCE ?: synchronized(this) {
                Room.databaseBuilder(context.applicationContext,
                                     AppDatabase::class.java, "app.db")
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
                    .build()
                    .also { INSTANCE = it }
            }
    }
}
```

## Configuration

```kotlin
// Type Converters for non-primitive types
class Converters {
    @TypeConverter fun fromInstant(value: Instant?): Long? = value?.toEpochMilli()
    @TypeConverter fun toInstant(value: Long?): Instant?   = value?.let { Instant.ofEpochMilli(it) }

    @TypeConverter fun fromStringList(value: List<String>?): String? =
        value?.let { Json.encodeToString(it) }
    @TypeConverter fun toStringList(value: String?): List<String>? =
        value?.let { Json.decodeFromString(it) }
}
```

## Performance

### Flow and LiveData Observation
```kotlin
// Collect in ViewModel — Room automatically re-emits on data changes
class OrderViewModel(private val dao: OrderDao) : ViewModel() {
    val orders: StateFlow<List<OrderEntity>> = dao
        .observeByUserId(currentUserId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

// In Compose
val orders by viewModel.orders.collectAsStateWithLifecycle()
```

### Batch Operations and Transactions
```kotlin
// Room wraps @Insert list in a transaction automatically
suspend fun syncOrders(remote: List<OrderEntity>) {
    withTransaction(db) {
        dao.deleteByUserId(remote.first().userId)
        dao.insertAll(remote)
    }
}

// Explicit transaction block
suspend fun transfer(db: AppDatabase, fromId: Long, toId: Long, amount: Double) {
    db.withTransaction {
        val from = db.accountDao().findById(fromId)!!
        db.accountDao().update(from.copy(balance = from.balance - amount))
        val to = db.accountDao().findById(toId)!!
        db.accountDao().update(to.copy(balance = to.balance + amount))
    }
}
```

## Security

```kotlin
// SAFE: Room always generates parameterized queries from @Query
@Query("SELECT * FROM users WHERE email = :email")
suspend fun findByEmail(email: String): UserEntity?

// Encrypted database with SQLCipher
Room.databaseBuilder(context, AppDatabase::class.java, "app.db")
    .openHelperFactory(SupportFactory(passphrase.toByteArray()))
    .build()

// Never store sensitive data in plain text — use EncryptedSharedPreferences or SQLCipher
```

## Testing

```kotlin
@RunWith(AndroidJUnit4::class)
class OrderDaoTest {
    private lateinit var db:  AppDatabase
    private lateinit var dao: OrderDao

    @Before fun createDb() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db  = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
                  .allowMainThreadQueries()   // tests only
                  .build()
        dao = db.orderDao()
    }

    @After fun closeDb() = db.close()

    @Test fun insertAndFindById() = runTest {
        val entity = OrderEntity(userId = 1L, total = 49.99)
        val id     = dao.insert(entity)
        val found  = dao.findById(id)
        assertNotNull(found)
        assertEquals(49.99, found!!.total, 0.001)
    }

    @Test fun observeByUserId_emitsOnInsert() = runTest {
        val flow = dao.observeByUserId(1L)
        launch {
            flow.test {
                assertEquals(0, awaitItem().size)
                dao.insert(OrderEntity(userId = 1L, total = 10.0))
                assertEquals(1, awaitItem().size)
                cancelAndIgnoreRemainingEvents()
            }
        }
    }
}
```

## Migration Strategies
```kotlin
val MIGRATION_2_3 = object : Migration(2, 3) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE orders ADD COLUMN notes TEXT")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)")
    }
}

// Test migrations with MigrationTestHelper
@Rule @JvmField val helper = MigrationTestHelper(
    InstrumentationRegistry.getInstrumentation(),
    AppDatabase::class.java
)

@Test fun migrate2To3() {
    helper.createDatabase(TEST_DB, 2).close()
    helper.runMigrationsAndValidate(TEST_DB, 3, true, MIGRATION_2_3)
}
```

## Dos
- Use `Flow<T>` return types in DAOs for reactive UI updates — Room emits on every data change.
- Always add `@Index` on foreign key columns and frequently filtered columns.
- Use `db.withTransaction { }` for multi-DAO operations to ensure atomicity.
- Export schema JSON (`exportSchema = true`) and commit it — enables migration regression testing.
- Use `Room.inMemoryDatabaseBuilder` with `allowMainThreadQueries()` in unit tests only.
- Use `@TypeConverter` for domain types (Instant, List, enums) instead of raw primitives everywhere.
- Use `OnConflictStrategy.REPLACE` for upsert semantics in sync operations.

## Don'ts
- Don't perform Room operations on the main thread — always use `suspend` or background dispatcher.
- Don't use `@Query` with string concatenation for user input — always use `:paramName` bindings.
- Don't define `@Relation` without `@Transaction` on the DAO query — partial reads cause inconsistency.
- Don't use `LiveData` in new code — prefer `Flow` which is coroutine-native and testable.
- Don't forget `fallbackToDestructiveMigration()` side effects — it drops and recreates the DB.
- Don't skip migration tests — `MigrationTestHelper` catches schema validation errors before production.
- Don't store large BLOBs in Room entities — use the file system and store only the path.
