# Hibernate with Spring

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-data-jpa")
// Hibernate is the default JPA provider — no explicit dep needed
```

```yaml
# application.yml
spring:
  jpa:
    open-in-view: false          # MUST be disabled — prevents lazy-load anti-pattern
    hibernate:
      ddl-auto: validate         # validate in prod; create-drop in tests
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
        jdbc.batch_size: 25
        order_inserts: true
        order_updates: true
        cache:
          use_second_level_cache: true
          region.factory_class: org.hibernate.cache.jcache.JCacheCacheRegionFactory
```

## Framework-Specific Patterns

### Entity Graph (avoid N+1)

```kotlin
@EntityGraph(attributePaths = ["orders", "orders.items"])
fun findWithOrdersById(id: UUID): Optional<Customer>
```

Prefer `@EntityGraph` over `JOIN FETCH` in JPQL for reusability across queries.

### Spring Data JPA Repository

```kotlin
interface CustomerRepository : JpaRepository<Customer, UUID> {
    @Query("SELECT c FROM Customer c WHERE c.status = :status")
    fun findAllByStatus(@Param("status") status: CustomerStatus): List<Customer>
}
```

### L2 Cache with Spring Cache

```kotlin
@Entity
@Cache(usage = CacheConcurrencyStrategy.READ_WRITE)
@Cacheable
class Product(...)
```

Enable `@EnableCaching` on a `@Configuration` class. Use `READ_WRITE` for mutable entities, `NONSTRICT_READ_WRITE` for rarely-changed data.

### open-in-view: false
Spring Boot defaults this to `true`. Set it to `false` — it binds the Hibernate session to the HTTP request thread, causing unintended lazy loads in the view layer and connection exhaustion under load.

## Scaffolder Patterns

```yaml
patterns:
  entity: "src/main/kotlin/{package}/domain/{Entity}.kt"
  repository: "src/main/kotlin/{package}/persistence/{Entity}Repository.kt"
  jpa_config: "src/main/kotlin/{package}/config/JpaConfig.kt"
```

## Additional Dos/Don'ts

- DO annotate `@Transactional` on use-case/service implementations, never on repositories
- DO use `@Modifying` + `@Query` for bulk updates — avoids entity load + dirty-check cycle
- DO set `batch_size` and `order_inserts/updates` for bulk operations
- DON'T rely on `ddl-auto: update` in any shared environment
- DON'T expose `@Entity` classes directly from REST controllers — map to DTOs
- DON'T use `FetchType.EAGER` on collection associations
