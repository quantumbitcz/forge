# Hibernate / JPA Best Practices

## Overview
JPA/Hibernate is the standard ORM for Java/Kotlin on the JVM. Use it for domain-driven applications where a rich object model maps naturally to relational data. Avoid it for bulk analytical queries, high-throughput batch ETL, or when you need fine-grained SQL control — reach for jOOQ or JDBC templates instead.

## Architecture Patterns

### Entity Design
```java
@Entity
@Table(name = "orders")
public class Order {
    @Id @GeneratedValue(strategy = GenerationType.SEQUENCE,
                        generator = "order_seq")
    @SequenceGenerator(name = "order_seq", allocationSize = 50)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_id", nullable = false)
    private Customer customer;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL,
               orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();
}
```

### Repository Pattern (Spring Data JPA)
```java
public interface OrderRepository extends JpaRepository<Order, Long> {
    @EntityGraph(attributePaths = {"items", "items.product"})
    Optional<Order> findWithItemsById(Long id);

    @Query("SELECT o FROM Order o JOIN FETCH o.customer WHERE o.status = :status")
    List<Order> findByStatusWithCustomer(@Param("status") OrderStatus status);
}
```

### Avoiding N+1 with Batch Size
```java
// Entity-level batch fetching
@Entity
public class Customer {
    @OneToMany(mappedBy = "customer", fetch = FetchType.LAZY)
    @BatchSize(size = 25)
    private List<Order> orders;
}

// Global default in application.properties
// spring.jpa.properties.hibernate.default_batch_fetch_size=25
```

### Inheritance Strategies
```java
// SINGLE_TABLE: best performance, nullable columns for subtypes
@Entity
@Inheritance(strategy = InheritanceType.SINGLE_TABLE)
@DiscriminatorColumn(name = "payment_type")
public abstract class Payment { ... }

// JOINED: normalized schema, use for large type hierarchies with many fields
@Entity
@Inheritance(strategy = InheritanceType.JOINED)
public abstract class Notification { ... }
```

## Configuration

```yaml
# application.yml
spring:
  jpa:
    open-in-view: false               # Never use OSIV in production
    properties:
      hibernate:
        default_batch_fetch_size: 25
        jdbc.batch_size: 50
        order_inserts: true
        order_updates: true
        generate_statistics: false    # Enable only for profiling
    hibernate:
      ddl-auto: validate              # Production: validate; dev: update
  datasource:
    hikari:
      maximum-pool-size: 10
      minimum-idle: 2
      connection-timeout: 30000
```

## Performance

### Entity Graph for Complex Fetches
```java
@NamedEntityGraph(
    name = "Order.full",
    attributeNodes = {
        @NamedAttributeNode("customer"),
        @NamedAttributeNode(value = "items", subgraph = "items-subgraph")
    },
    subgraphs = @NamedSubgraph(name = "items-subgraph",
                               attributeNodes = @NamedAttributeNode("product"))
)
@Entity public class Order { ... }

// Usage
EntityGraph<?> graph = em.getEntityGraph("Order.full");
Map<String, Object> hints = Map.of("javax.persistence.fetchgraph", graph);
em.find(Order.class, id, hints);
```

### Batch Inserts
```java
@Transactional
public void bulkInsert(List<Product> products) {
    for (int i = 0; i < products.size(); i++) {
        em.persist(products.get(i));
        if (i % 50 == 0) {
            em.flush();
            em.clear(); // prevent L1 cache bloat
        }
    }
}
```

### Second-Level Cache (Caffeine)
```java
@Entity
@Cache(usage = CacheConcurrencyStrategy.READ_WRITE)
public class ProductCategory { ... }

// application.properties
// spring.jpa.properties.hibernate.cache.use_second_level_cache=true
// spring.jpa.properties.hibernate.cache.region.factory_class=jcache
```

## Security

- Always use parameterized JPQL/Criteria — never concatenate user input into queries.
- Use `@PreAuthorize` / row-level filters via Hibernate Filters for multi-tenant data isolation.
- Never expose entity IDs directly in APIs; use surrogate keys or UUIDs.

```java
// Safe: parameterized
em.createQuery("SELECT u FROM User u WHERE u.email = :email", User.class)
  .setParameter("email", email).getSingleResult();

// UNSAFE: string concatenation — SQL injection risk
em.createQuery("SELECT u FROM User u WHERE u.email = '" + email + "'");
```

## Testing

```kotlin
@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.NONE)
@Testcontainers
class OrderRepositoryTest {
    @Container
    val postgres = PostgreSQLContainer<Nothing>("postgres:16-alpine")

    @Autowired lateinit var orderRepo: OrderRepository

    @Test fun `findWithItemsById loads items in single query`() {
        val order = orderRepo.findWithItemsById(1L)
        // assert no lazy-load exceptions outside transaction
        assertThat(order).isPresent
        assertThat(order.get().items).isNotEmpty()
    }
}
```

## Dos
- Set `spring.jpa.open-in-view=false` — OSIV silently opens DB connections during HTTP rendering.
- Use `FetchType.LAZY` on all associations; load eagerly only when needed via `@EntityGraph` or `JOIN FETCH`.
- Set `hibernate.default_batch_fetch_size` globally to reduce N+1 queries from lazy collections.
- Use sequence generators with `allocationSize > 1` for performant bulk inserts.
- Flush and clear the `EntityManager` in batches when inserting large datasets.
- Prefer `@Query` with `JOIN FETCH` over separate repository calls that trigger lazy loading.
- Use `@Transactional(readOnly = true)` on read-only service methods for Hibernate optimizations.

## Don'ts
- Don't use `FetchType.EAGER` on `@OneToMany` or `@ManyToMany` — it causes Cartesian product queries.
- Don't use `ddl-auto: create-drop` or `update` in production — use Flyway/Liquibase migrations.
- Don't call repository methods outside of a transaction and then access lazy collections.
- Don't use `@ManyToMany` with a plain `Set` without considering `equals`/`hashCode` contracts.
- Don't enable `generate_statistics` in production — significant overhead.
- Don't use `em.merge()` on detached entities without understanding dirty-checking implications.
- Don't store large blobs in entities without `@Basic(fetch = FetchType.LAZY)`.
