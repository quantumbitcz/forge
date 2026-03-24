# SQLite with Jetpack Compose (Room + Hilt)

## Integration Setup

```kotlin
// build.gradle.kts (app)
plugins { id("com.google.devtools.ksp") }

dependencies {
    val room = "2.6.1"
    implementation("androidx.room:room-runtime:$room")
    implementation("androidx.room:room-ktx:$room")      // coroutine + Flow support
    ksp("androidx.room:room-compiler:$room")

    implementation("com.google.dagger:hilt-android:2.51")
    ksp("com.google.dagger:hilt-android-compiler:2.51")
}
```

## Framework-Specific Patterns

### Room + Hilt Wiring
```kotlin
@Database(
    entities  = [UserEntity::class, OrderEntity::class],
    version   = 2,
    exportSchema = true   // commit generated schema JSON for migration testing
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun userDao():  UserDao
    abstract fun orderDao(): OrderDao
}

@Module @InstallIn(SingletonComponent::class)
object DatabaseModule {
    @Provides @Singleton
    fun provideDatabase(@ApplicationContext ctx: Context): AppDatabase =
        Room.databaseBuilder(ctx, AppDatabase::class.java, "app.db")
            .addMigrations(MIGRATION_1_2)
            .build()

    @Provides fun provideUserDao(db: AppDatabase): UserDao = db.userDao()
}
```

### Reactive UI with Compose
```kotlin
@HiltViewModel
class UserViewModel @Inject constructor(
    private val userDao: UserDao
) : ViewModel() {
    val users: StateFlow<List<UserEntity>> = userDao.observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

@Composable
fun UserListScreen(vm: UserViewModel = hiltViewModel()) {
    val users by vm.users.collectAsStateWithLifecycle()
    LazyColumn { items(users) { UserItem(it) } }
}
```

## Scaffolder Patterns

```yaml
patterns:
  entity:   "data/local/entity/{Entity}Entity.kt"
  dao:      "data/local/dao/{Entity}Dao.kt"
  database: "data/local/AppDatabase.kt"
  module:   "di/DatabaseModule.kt"
```

## Additional Dos/Don'ts

- DO use `ksp` (not `kapt`) for Room code generation in new projects — faster incremental builds
- DO set `exportSchema = true` and commit schema JSON to track migration history
- DO inject DAOs via Hilt; never instantiate `AppDatabase` directly outside the DI module
- DO use `Flow<T>` DAOs for reactive Compose UIs; Room re-emits on every write
- DON'T use `allowMainThreadQueries()` outside tests; always use `suspend` or coroutine dispatchers
- DON'T use `fallbackToDestructiveMigration()` in production — write explicit migrations
- DON'T store large BLOBs in Room; persist files to internal storage and store only the path
