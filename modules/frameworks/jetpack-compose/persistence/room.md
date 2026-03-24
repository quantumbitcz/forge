# Jetpack Compose + Room

> Compose-specific patterns for Room persistence. Extends generic Jetpack Compose conventions.
> Generic Compose patterns (ViewModel, state hoisting, Hilt) are NOT repeated here.

## Integration Setup

`build.gradle.kts` (app module):
```kotlin
plugins {
    id("com.google.devtools.ksp")
}

dependencies {
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")      // Coroutines / Flow support
    ksp("androidx.room:room-compiler:$roomVersion")
}
```

## Entity Definition

```kotlin
// data/local/entity/UserEntity.kt
@Entity(tableName = "users")
data class UserEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "display_name") val displayName: String,
    @ColumnInfo(name = "email") val email: String,
    @ColumnInfo(name = "created_at") val createdAt: Long = System.currentTimeMillis(),
)
```

## DAO

```kotlin
@Dao
interface UserDao {
    @Query("SELECT * FROM users ORDER BY display_name ASC")
    fun observeAll(): Flow<List<UserEntity>>   // Flow — auto-updates on DB change

    @Query("SELECT * FROM users WHERE id = :id")
    suspend fun findById(id: String): UserEntity?

    @Upsert
    suspend fun upsert(user: UserEntity)

    @Delete
    suspend fun delete(user: UserEntity)
}
```

## Database Class

```kotlin
@Database(
    entities = [UserEntity::class, OrderEntity::class],
    version = 2,
    exportSchema = true,   // ALWAYS true — schema JSON enables migration testing
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun userDao(): UserDao
    abstract fun orderDao(): OrderDao
}
```

`exportSchema = true` writes schema JSON to `schemas/`. Commit these files to version control.

## Hilt @Provides

```kotlin
// di/DatabaseModule.kt
@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase =
        Room.databaseBuilder(context, AppDatabase::class.java, "app_database")
            .addMigrations(MIGRATION_1_2)
            .fallbackToDestructiveMigration()   // only during development
            .build()

    @Provides
    fun provideUserDao(db: AppDatabase): UserDao = db.userDao()
}
```

Remove `fallbackToDestructiveMigration()` before production release.

## DAO Injection into ViewModels

Inject via repository — ViewModels should not depend on Room directly:

```kotlin
// domain/repository/UserRepository.kt
class UserRepository @Inject constructor(private val userDao: UserDao) {
    fun observeUsers(): Flow<List<User>> =
        userDao.observeAll().map { entities -> entities.map(UserEntity::toDomain) }

    suspend fun save(user: User) = userDao.upsert(user.toEntity())
}

// ui/users/UsersViewModel.kt
@HiltViewModel
class UsersViewModel @Inject constructor(private val userRepository: UserRepository) : ViewModel() {
    val users: StateFlow<List<User>> = userRepository.observeUsers()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
}
```

## Migrations

```kotlin
val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE users ADD COLUMN avatar_url TEXT")
    }
}
```

## Migration Testing

```kotlin
@RunWith(AndroidJUnit4::class)
class MigrationTest {
    @get:Rule val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        AppDatabase::class.java,
    )

    @Test
    fun migrate1To2() {
        helper.createDatabase(TEST_DB, 1).close()
        helper.runMigrationsAndValidate(TEST_DB, 2, true, MIGRATION_1_2)
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  entity: "data/local/entity/{Name}Entity.kt"
  dao: "data/local/dao/{Name}Dao.kt"
  database: "data/local/AppDatabase.kt"
  di_module: "di/DatabaseModule.kt"
  repository: "domain/repository/{Name}Repository.kt"
  schemas_dir: "schemas/"
  migration: "data/local/migration/Migration_{from}_{to}.kt"
```

## Additional Dos/Don'ts

- DO set `exportSchema = true` and commit `schemas/*.json` — required for migration testing
- DO use `Flow` return types in DAOs for reactive UI updates
- DO inject DAOs into repositories, not ViewModels directly
- DO write a `Migration` object for every version bump before release
- DON'T use `fallbackToDestructiveMigration()` in production builds
- DON'T run Room queries on the main thread — always use `suspend` or `Flow`
- DON'T use `@Entity` fields as primary keys unless they are stable identifiers
