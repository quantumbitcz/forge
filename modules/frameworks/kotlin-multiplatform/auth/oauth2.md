# OAuth2 with Kotlin Multiplatform

## Integration Setup

```kotlin
// No single KMP OAuth2 library — use Ktor Client for token exchange + platform-specific auth UI
commonMain.dependencies {
    implementation("io.ktor:ktor-client-core:2.3.11")
    implementation("io.ktor:ktor-client-content-negotiation:2.3.11")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.11")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
}
// Platform-specific: AppAuth-Android / AppAuth-iOS via expect/actual
```

## Framework-Specific Patterns

### Token Model & Refresh Logic (commonMain)
```kotlin
@Serializable
data class TokenPair(
    val accessToken:  String,
    val refreshToken: String,
    val expiresAt:    Long         // Unix ms
) {
    fun isExpired(bufferMs: Long = 60_000L) =
        Clock.System.now().toEpochMilliseconds() > expiresAt - bufferMs
}

class TokenService(
    private val client:     HttpClient,
    private val tokenStore: TokenStore,
    private val config:     OAuthConfig
) {
    suspend fun refreshIfNeeded(): String {
        val tokens = tokenStore.load() ?: throw AuthException.NotAuthenticated
        if (!tokens.isExpired()) return tokens.accessToken
        return refresh(tokens.refreshToken)
    }

    private suspend fun refresh(refreshToken: String): String {
        val response: TokenResponse = client.submitForm(
            url = config.tokenEndpoint,
            formParameters = parameters {
                append("grant_type",    "refresh_token")
                append("refresh_token", refreshToken)
                append("client_id",     config.clientId)
            }
        ).body()
        val newTokens = TokenPair(
            accessToken  = response.accessToken,
            refreshToken = response.refreshToken ?: refreshToken,
            expiresAt    = Clock.System.now().toEpochMilliseconds() + response.expiresIn * 1000L
        )
        tokenStore.save(newTokens)
        return newTokens.accessToken
    }
}
```

### Token Storage (expect/actual)
```kotlin
// commonMain
expect class TokenStore {
    suspend fun save(tokens: TokenPair)
    suspend fun load(): TokenPair?
    suspend fun clear()
}

// androidMain — EncryptedSharedPreferences
actual class TokenStore(private val ctx: Context) : TokenStore { /* ... */ }

// iosMain — iOS Keychain
actual class TokenStore : TokenStore { /* ... */ }
```

### Ktor Auth Plugin Integration
```kotlin
val client = HttpClient(engine) {
    install(Auth) {
        bearer {
            loadTokens {
                val tokens = tokenStore.load() ?: return@loadTokens null
                BearerTokens(tokens.accessToken, tokens.refreshToken)
            }
            refreshTokens {
                val newToken = tokenService.refresh(oldTokens!!.refreshToken)
                BearerTokens(newToken, oldTokens!!.refreshToken)
            }
        }
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  token_service: "commonMain/kotlin/.../auth/TokenService.kt"
  token_store:   "commonMain/kotlin/.../auth/TokenStore.kt"
  oauth_config:  "commonMain/kotlin/.../auth/OAuthConfig.kt"
```

## Additional Dos/Don'ts

- DO implement the PKCE flow on each platform using AppAuth (Android) and AppAuth-iOS
- DO keep token refresh logic in `commonMain`; only storage is platform-specific
- DO use Ktor's `Auth` plugin with bearer tokens for automatic refresh on 401
- DO store tokens in the platform keychain/EncryptedSharedPreferences — not in SQLDelight
- DON'T bundle `client_secret` in the app binary — mobile apps must use PKCE public client flow
- DON'T retry indefinitely on refresh failure — clear tokens and force re-login after 1 retry
- DON'T log `TokenPair` fields; treat access and refresh tokens as secrets
