# OAuth2 with Jetpack Compose (AppAuth Android)

## Integration Setup

```kotlin
// build.gradle.kts
implementation("net.openid:appauth:0.11.1")
implementation("androidx.security:security-crypto:1.1.0-alpha06")  // EncryptedSharedPreferences
```

## Framework-Specific Patterns

### PKCE Authorization Flow
```kotlin
class AuthService @Inject constructor(@ApplicationContext private val ctx: Context) {
    private val authService = AuthorizationService(ctx)

    fun buildAuthRequest(config: AuthorizationServiceConfiguration): AuthorizationRequest =
        AuthorizationRequest.Builder(
            config,
            BuildConfig.CLIENT_ID,
            ResponseTypeValues.CODE,
            Uri.parse(BuildConfig.REDIRECT_URI)
        )
        .setScope("openid profile email")
        .build()   // AppAuth generates PKCE code_verifier/challenge automatically

    fun performTokenExchange(
        response: AuthorizationResponse,
        callback: (TokenResponse?, AuthorizationException?) -> Unit
    ) {
        authService.performTokenRequest(
            response.createTokenExchangeRequest(),
            callback
        )
    }
}
```

### Token Storage (EncryptedSharedPreferences)
```kotlin
class TokenStore @Inject constructor(@ApplicationContext ctx: Context) {
    private val prefs = EncryptedSharedPreferences.create(
        ctx, "auth_prefs",
        MasterKey.Builder(ctx).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun saveTokens(accessToken: String, refreshToken: String, expiresAt: Long) {
        prefs.edit()
            .putString("access_token",  accessToken)
            .putString("refresh_token", refreshToken)
            .putLong("expires_at",      expiresAt)
            .apply()
    }

    fun getAccessToken():   String? = prefs.getString("access_token",  null)
    fun getRefreshToken():  String? = prefs.getString("refresh_token", null)
    fun isTokenExpired():   Boolean = System.currentTimeMillis() > prefs.getLong("expires_at", 0) - 60_000
}
```

### Refresh Token Flow
```kotlin
suspend fun refreshTokenIfNeeded(): String? {
    if (!tokenStore.isTokenExpired()) return tokenStore.getAccessToken()
    val refreshToken = tokenStore.getRefreshToken() ?: return null
    // Use AppAuth ClientAuthentication + TokenRequest for refresh
    return withContext(Dispatchers.IO) {
        suspendCancellableCoroutine { cont ->
            authService.performTokenRequest(buildRefreshRequest(refreshToken)) { resp, ex ->
                if (resp != null) {
                    tokenStore.saveTokens(resp.accessToken!!, resp.refreshToken ?: refreshToken,
                                         resp.accessTokenExpirationTime ?: 0)
                    cont.resume(resp.accessToken)
                } else cont.resume(null)
            }
        }
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  auth_service:  "data/auth/AuthService.kt"
  token_store:   "data/auth/TokenStore.kt"
  auth_activity: "ui/auth/AuthCallbackActivity.kt"
```

## Additional Dos/Don'ts

- DO use AppAuth's built-in PKCE — never implement PKCE manually
- DO store tokens in `EncryptedSharedPreferences`; never in plain `SharedPreferences` or a file
- DO handle token refresh proactively (60s before expiry) to avoid 401 mid-request
- DO register a custom redirect URI scheme in `AndroidManifest.xml` for the callback Activity
- DON'T store `client_secret` in the APK — use public client (PKCE only) for mobile
- DON'T log access tokens or refresh tokens; treat them as credentials
- DON'T use `WebView` for OAuth flows — use Chrome Custom Tabs via AppAuth for security
