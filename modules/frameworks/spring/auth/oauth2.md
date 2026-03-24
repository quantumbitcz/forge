# Spring Security OAuth2

> Spring-specific patterns for OAuth2 resource server and OIDC client. Extends generic Spring conventions.

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-security")
implementation("org.springframework.boot:spring-boot-starter-oauth2-resource-server")
// For OIDC client (BFF or server-side app):
implementation("org.springframework.boot:spring-boot-starter-oauth2-client")
```

```yaml
# application.yml — resource server (JWT)
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${OAUTH2_ISSUER_URI}   # auto-discovers JWKS endpoint
```

## Framework-Specific Patterns

```kotlin
// SecurityConfig.kt — resource server
@Configuration
@EnableWebSecurity
@EnableMethodSecurity
class SecurityConfig {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain = http
        .csrf { it.disable() }
        .authorizeHttpRequests { auth ->
            auth.requestMatchers("/actuator/health/**").permitAll()
            auth.anyRequest().authenticated()
        }
        .oauth2ResourceServer { rs ->
            rs.jwt { jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter()) }
        }
        .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
        .build()

    @Bean
    fun jwtAuthConverter(): JwtAuthenticationConverter = JwtAuthenticationConverter().apply {
        setJwtGrantedAuthoritiesConverter { jwt ->
            val roles = jwt.getClaimAsStringList("roles") ?: emptyList()
            roles.map { SimpleGrantedAuthority("ROLE_$it") }
        }
    }
}
```

```kotlin
// Method security
@Service
class OrderService {

    @PreAuthorize("hasRole('USER')")
    fun createOrder(command: CreateOrderCommand): Order = TODO()

    @PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
    fun getOrders(userId: String): List<Order> = TODO()
}
```

Custom `JwtDecoder` for additional validation (e.g., audience check):

```kotlin
@Bean
fun jwtDecoder(@Value("\${spring.security.oauth2.resourceserver.jwt.issuer-uri}") issuer: String,
               @Value("\${oauth2.audience}") audience: String): JwtDecoder {
    val decoder = JwtDecoders.fromIssuerLocation<NimbusJwtDecoder>(issuer)
    decoder.setJwtValidator(
        DelegatingOAuth2TokenValidator(
            JwtValidators.createDefaultWithIssuer(issuer),
            JwtClaimValidator("aud") { aud: List<*> -> aud.contains(audience) }
        )
    )
    return decoder
}
```

OIDC client registration (when acting as OAuth2 client):

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          keycloak:
            client-id: ${OIDC_CLIENT_ID}
            client-secret: ${OIDC_CLIENT_SECRET}
            scope: openid, profile, email
        provider:
          keycloak:
            issuer-uri: ${OAUTH2_ISSUER_URI}
```

## Scaffolder Patterns

```
src/main/kotlin/com/example/
  config/
    SecurityConfig.kt         # SecurityFilterChain, jwtAuthConverter
    JwtDecoderConfig.kt       # custom JwtDecoder (audience, extra claims)
  security/
    CurrentUser.kt            # @AuthenticationPrincipal resolver / extension val
```

## Dos

- Use `issuer-uri` auto-configuration — Spring fetches JWKS automatically and rotates keys
- Use `@EnableMethodSecurity` + `@PreAuthorize` for fine-grained access control in services
- Validate the `aud` claim to prevent token reuse across services
- Extract an `@CurrentUser` annotation wrapping `@AuthenticationPrincipal Jwt` for cleaner controller signatures

## Don'ts

- Don't store tokens server-side in HTTP sessions for stateless resource servers
- Don't implement your own JWT parsing — use Spring's `NimbusJwtDecoder`
- Don't use `permitAll()` broadly without understanding the security boundary at each endpoint
- Don't skip CSRF disabling justification in code comments — document why it is safe (stateless JWT, no cookies)
