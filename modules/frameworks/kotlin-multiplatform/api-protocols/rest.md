# REST APIs with Kotlin Multiplatform (Ktor Client)

## Integration Setup

```kotlin
// build.gradle.kts (shared module)
commonMain.dependencies {
    implementation("io.ktor:ktor-client-core:2.3.11")
    implementation("io.ktor:ktor-client-content-negotiation:2.3.11")
    implementation("io.ktor:ktor-client-logging:2.3.11")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.11")
}
androidMain.dependencies {
    implementation("io.ktor:ktor-client-okhttp:2.3.11")
}
iosMain.dependencies {
    implementation("io.ktor:ktor-client-darwin:2.3.11")
}
jvmMain.dependencies {
    implementation("io.ktor:ktor-client-cio:2.3.11")
}
```

## Framework-Specific Patterns

### HttpClient Configuration (commonMain)
```kotlin
// commonMain — engine injected via expect/actual or DI
fun createHttpClient(engine: HttpClientEngine) = HttpClient(engine) {
    install(ContentNegotiation) {
        json(Json { ignoreUnknownKeys = true; isLenient = true })
    }
    install(Logging) {
        level = if (BuildKonfig.DEBUG) LogLevel.HEADERS else LogLevel.NONE
    }
    defaultRequest {
        url(BuildKonfig.API_BASE_URL)
        header("Accept", "application/json")
    }
    HttpResponseValidator {
        validateResponse { response ->
            if (response.status.value >= 400) throw ClientRequestException(response, "")
        }
    }
}
```

### Platform Engine (expect/actual)
```kotlin
// commonMain
expect fun httpClientEngine(): HttpClientEngine

// androidMain
actual fun httpClientEngine(): HttpClientEngine = OkHttp.create()

// iosMain
actual fun httpClientEngine(): HttpClientEngine = Darwin.create()
```

### Typed API Service
```kotlin
class TodoApiService(private val client: HttpClient) {
    suspend fun getTodos(): List<TodoDto> =
        client.get("todos").body()

    suspend fun createTodo(request: CreateTodoRequest): TodoDto =
        client.post("todos") { contentType(ContentType.Application.Json); setBody(request) }.body()

    suspend fun deleteTodo(id: Long) =
        client.delete("todos/$id")
}
```

### Repository with Flow
```kotlin
class TodoRepository(private val api: TodoApiService, private val dao: TodoQueries) {
    fun getTodos(): Flow<List<Todo>> = flow {
        emit(dao.selectAll().executeAsList().map(TodoEntity::toDomain))
        val remote = api.getTodos()
        remote.forEach { dao.upsert(it.toEntity()) }
        emit(dao.selectAll().executeAsList().map(TodoEntity::toDomain))
    }.flowOn(Dispatchers.Default)
}
```

## Scaffolder Patterns

```yaml
patterns:
  http_client:   "commonMain/kotlin/.../network/HttpClientFactory.kt"
  api_service:   "commonMain/kotlin/.../network/{Feature}ApiService.kt"
  dto:           "commonMain/kotlin/.../network/dto/{Entity}Dto.kt"
  repository:    "commonMain/kotlin/.../repository/{Feature}RepositoryImpl.kt"
```

## Additional Dos/Don'ts

- DO configure the `HttpClient` once and share it via dependency injection (Koin)
- DO use `kotlinx.serialization` with `@Serializable` for all DTOs — works on all platforms
- DO set `ignoreUnknownKeys = true` in `Json` config to survive API additions
- DO use `expect/actual` only for the engine; keep all networking logic in `commonMain`
- DON'T catch exceptions in the repository without re-wrapping them as domain errors
- DON'T use `runBlocking` on iOS — use `kotlinx.coroutines` dispatcher or Swift `async`
- DON'T share a single `HttpClient` across tests; create a fresh instance per test with a mock engine
