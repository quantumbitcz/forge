# REST APIs with Jetpack Compose (Retrofit / Ktor Client)

## Integration Setup

```kotlin
// build.gradle.kts — Retrofit approach (most common)
implementation("com.squareup.retrofit2:retrofit:2.11.0")
implementation("com.squareup.retrofit2:converter-gson:2.11.0")
// or kotlinx.serialization converter:
implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")

// Ktor Client alternative
implementation("io.ktor:ktor-client-android:2.3.11")
implementation("io.ktor:ktor-client-content-negotiation:2.3.11")
implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.11")
```

## Framework-Specific Patterns

### Retrofit Typed API Interface
```kotlin
interface TodoApi {
    @GET("todos")
    suspend fun getTodos(): List<TodoDto>

    @GET("todos/{id}")
    suspend fun getTodo(@Path("id") id: Long): TodoDto

    @POST("todos")
    suspend fun createTodo(@Body request: CreateTodoRequest): TodoDto

    @PUT("todos/{id}")
    suspend fun updateTodo(@Path("id") id: Long, @Body request: UpdateTodoRequest): TodoDto

    @DELETE("todos/{id}")
    suspend fun deleteTodo(@Path("id") id: Long): Response<Unit>
}
```

### Hilt Module
```kotlin
@Module @InstallIn(SingletonComponent::class)
object NetworkModule {
    @Provides @Singleton
    fun provideRetrofit(): Retrofit = Retrofit.Builder()
        .baseUrl(BuildConfig.API_BASE_URL)
        .addConverterFactory(Json.asConverterFactory("application/json".toMediaType()))
        .build()

    @Provides @Singleton
    fun provideTodoApi(retrofit: Retrofit): TodoApi =
        retrofit.create(TodoApi::class.java)
}
```

### Flow from API Calls (Repository Pattern)
```kotlin
class TodoRepository @Inject constructor(private val api: TodoApi) {
    fun getTodos(): Flow<Result<List<TodoDto>>> = flow {
        emit(Result.Loading)
        emit(runCatching { api.getTodos() }.fold(
            onSuccess = { Result.Success(it) },
            onFailure = { Result.Error(it) }
        ))
    }.flowOn(Dispatchers.IO)
}
```

### ViewModel Integration
```kotlin
@HiltViewModel
class TodoViewModel @Inject constructor(private val repo: TodoRepository) : ViewModel() {
    val todos = repo.getTodos()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), Result.Loading)
}
```

## Scaffolder Patterns

```yaml
patterns:
  api:        "data/remote/api/{Feature}Api.kt"
  dto:        "data/remote/dto/{Entity}Dto.kt"
  repository: "data/repository/{Feature}RepositoryImpl.kt"
  module:     "di/NetworkModule.kt"
```

## Additional Dos/Don'ts

- DO use `suspend fun` in Retrofit interfaces — they run on the calling coroutine's dispatcher
- DO use a sealed `Result<T>` type (Loading/Success/Error) in the repository layer
- DO configure `OkHttpClient` with timeout values matching backend SLAs
- DO inject `Dispatcher.IO` via Hilt for repository flows to avoid hardcoding
- DON'T call API methods from Composables directly — always go through ViewModel
- DON'T expose `Response<T>` wrappers to the ViewModel; unwrap errors in the repository
- DON'T use `runBlocking` in ViewModels or Composables to call suspend functions
