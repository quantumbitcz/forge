# Spring Cache + Redis

> Spring-specific patterns for distributed caching via Spring Data Redis. Extends generic Spring conventions.

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-data-redis")
implementation("org.springframework.boot:spring-boot-starter-cache")
```

```yaml
# application.yml
spring:
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: 6379
      lettuce:
        pool:
          max-active: 8
          max-idle: 4
          min-idle: 1
          max-wait: 200ms
```

```kotlin
// CacheConfig.kt
@Configuration
@EnableCaching
class CacheConfig(private val redisConnectionFactory: RedisConnectionFactory) {

    private fun objectMapper() = ObjectMapper()
        .findAndRegisterModules()
        .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)

    @Bean
    fun cacheManager(): RedisCacheManager {
        val defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(10))
            .serializeKeysWith(RedisSerializationContext.SerializationPair.fromSerializer(StringRedisSerializer()))
            .serializeValuesWith(
                RedisSerializationContext.SerializationPair.fromSerializer(
                    GenericJackson2JsonRedisSerializer(objectMapper())
                )
            )
            .disableCachingNullValues()

        val perCacheConfigs = mapOf(
            "users"    to defaultConfig.entryTtl(Duration.ofMinutes(30)),
            "sessions" to defaultConfig.entryTtl(Duration.ofHours(1)),
        )

        return RedisCacheManager.builder(redisConnectionFactory)
            .cacheDefaults(defaultConfig)
            .withInitialCacheConfigurations(perCacheConfigs)
            .build()
    }
}
```

## Framework-Specific Patterns

```kotlin
@Service
class UserService(private val userRepo: UserRepository) {

    @Cacheable("users", key = "#id", unless = "#result == null")
    fun findById(id: UUID): User? = userRepo.findById(id).orElse(null)

    @CachePut("users", key = "#result.id")
    fun update(command: UpdateUserCommand): User = userRepo.save(command.toEntity())

    @CacheEvict("users", key = "#id")
    fun delete(id: UUID) = userRepo.deleteById(id)
}
```

Use `RedisTemplate` for advanced operations (sorted sets, pub/sub, Lua scripts):

```kotlin
@Service
class RateLimiterService(private val redis: StringRedisTemplate) {
    fun isAllowed(key: String, limit: Long, window: Duration): Boolean {
        val count = redis.opsForValue().increment(key) ?: 1L
        if (count == 1L) redis.expire(key, window)
        return count <= limit
    }
}
```

## Scaffolder Patterns

```
src/main/kotlin/com/example/
  config/
    CacheConfig.kt           # RedisCacheManager + TTL per cache
    RedisConfig.kt           # RedisTemplate<String, Any> bean (optional)
  service/
    UserService.kt           # @Cacheable/@CacheEvict methods
  health/
    RedisHealthIndicator.kt  # custom health check (optional; auto via Actuator)
```

## Dos

- Always set per-cache TTLs — never let keys persist indefinitely in production
- Use `GenericJackson2JsonRedisSerializer` with a configured `ObjectMapper` so types survive restart
- Set `disableCachingNullValues()` to avoid caching empty results unless explicitly needed
- Prefix cache names with the service name in multi-service deployments to avoid key collision

## Don'ts

- Don't use `JdkSerializationRedisSerializer` — serialized bytes are not readable and break on class changes
- Don't skip connection pool configuration — default Lettuce settings are too permissive for production
- Don't use `@Cacheable` on methods that return non-serializable types without a custom serializer
- Don't let cache misses flood the DB on cold start — consider cache warming via `ApplicationRunner`
