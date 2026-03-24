# Spring Cache + Caffeine

> Spring-specific patterns for local in-process caching with Caffeine. Extends generic Spring conventions.

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-cache")
implementation("com.github.ben-manes.caffeine:caffeine")
```

```kotlin
// CacheConfig.kt
@Configuration
@EnableCaching
class CacheConfig {
    @Bean
    fun cacheManager(): CacheManager = CaffeineCacheManager().apply {
        setCaffeine(
            Caffeine.newBuilder()
                .maximumSize(1_000)
                .expireAfterWrite(10, TimeUnit.MINUTES)
                .recordStats()
        )
        // Per-cache TTL: register named specs
        setCacheNames(listOf("users", "products"))
    }
}
```

## Framework-Specific Patterns

```kotlin
// Per-cache spec via application.yml
spring:
  cache:
    caffeine:
      spec: maximumSize=500,expireAfterWrite=5m
    cache-names: users, products
```

```kotlin
@Service
class UserService(private val userRepo: UserRepository) {

    @Cacheable("users", key = "#id")
    fun findById(id: UUID): User = userRepo.findByIdOrThrow(id)

    @CachePut("users", key = "#user.id")
    fun save(user: User): User = userRepo.save(user)

    @CacheEvict("users", key = "#id")
    fun delete(id: UUID) = userRepo.deleteById(id)

    // Evict all entries on bulk changes
    @CacheEvict("users", allEntries = true)
    fun invalidateAll() = Unit
}
```

SpEL key expressions: `#id`, `#user.id`, `#root.method.name + '_' + #id`, `T(java.util.Objects).hash(#a, #b)`.

## Scaffolder Patterns

```
src/main/kotlin/com/example/
  config/
    CacheConfig.kt           # CaffeineCacheManager + @EnableCaching
  service/
    UserService.kt           # @Cacheable/@CacheEvict methods
  metrics/
    CacheMetrics.kt          # Micrometer Caffeine stats binding
```

## Dos

- Register named caches explicitly so per-cache specs (different TTL/size) can be applied
- Bind Caffeine stats to Micrometer: `CaffeineStatsCounter` or `MicrometerStatsCounter`
- Use `@CachePut` on write methods to keep the cache warm instead of immediately evicting
- Make cache keys deterministic and collision-free; include tenant/user context when needed

## Don'ts

- Don't use Caffeine for shared/distributed state — it is local to the JVM instance
- Don't cache mutable objects by reference; ensure cached values are immutable or defensively copied
- Don't skip `key =` when the method has multiple parameters — default key may collide
- Don't use `@Cacheable` on `@Transactional` methods without understanding read-committed interaction
