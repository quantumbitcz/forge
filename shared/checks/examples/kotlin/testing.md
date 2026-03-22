# Testing Patterns (Kotlin)

## kotest-shouldspec

**Instead of:**
```kotlin
@Test
fun `test order total calculation`() {
    val order = Order(listOf(LineItem("A", 2, 10.0), LineItem("B", 1, 5.0)))
    val total = order.calculateTotal()
    assertEquals(25.0, total)
}
```

**Do this:**
```kotlin
class OrderSpec : ShouldSpec({
    context("calculateTotal") {
        should("sum quantity * price for each line item") {
            val order = Order(listOf(LineItem("A", 2, 10.0), LineItem("B", 1, 5.0)))
            order.calculateTotal() shouldBe 25.0
        }
        should("return zero for an empty order") {
            Order(emptyList()).calculateTotal() shouldBe 0.0
        }
    }
})
```

**Why:** Kotest's `ShouldSpec` groups related assertions under a shared context, reads as a specification, and provides better failure output than flat JUnit methods.

## testcontainers-setup

**Instead of:**
```kotlin
@SpringBootTest
class UserRepositoryTest {
    // relies on a shared external database being available
    @Autowired lateinit var repo: UserRepository

    @Test
    fun `saves and retrieves user`() {
        repo.save(testUser)
        repo.findById(testUser.id) shouldNotBe null
    }
}
```

**Do this:**
```kotlin
@SpringBootTest
@Testcontainers
class UserRepositoryTest {
    companion object {
        @Container
        val postgres = PostgreSQLContainer("postgres:16-alpine")
            .withDatabaseName("test")

        @DynamicPropertySource @JvmStatic
        fun props(reg: DynamicPropertyRegistry) {
            reg.add("spring.r2dbc.url") { postgres.jdbcUrl.replace("jdbc", "r2dbc") }
            reg.add("spring.r2dbc.username", postgres::getUsername)
            reg.add("spring.r2dbc.password", postgres::getPassword)
        }
    }
}
```

**Why:** Testcontainers spin up a real database per test class, making integration tests self-contained and reproducible without shared infrastructure or manual setup.

## test-fixtures

**Instead of:**
```kotlin
@Test
fun `applies discount to premium user`() {
    val user = User(
        id = uuid(), name = "Alice", email = "a@b.com",
        plan = Plan.PREMIUM, createdAt = Instant.now(),
        address = Address("St", "City", "CZ"), verified = true
    )
    val result = discountService.calculate(user, cart)
    result.percentage shouldBe 15
}
```

**Do this:**
```kotlin
// in test-fixtures module / TestData.kt
fun aUser(
    plan: Plan = Plan.FREE,
    verified: Boolean = true,
) = User(
    id = uuid(), name = "Test", email = "test@example.com",
    plan = plan, createdAt = Instant.DISTANT_PAST,
    address = Address("St", "City", "CZ"), verified = verified,
)

@Test
fun `applies discount to premium user`() {
    val result = discountService.calculate(aUser(plan = Plan.PREMIUM), cart)
    result.percentage shouldBe 15
}
```

**Why:** Factory functions with sensible defaults highlight only the fields that matter for each test, reducing noise and making it trivial to create variants without copy-pasting constructors.

## assertion-style

**Instead of:**
```kotlin
@Test
fun `filters active products`() {
    val result = service.findActive(catalogId)
    assertTrue(result.size == 2)
    assertTrue(result.all { it.status == Status.ACTIVE })
    assertTrue(result.any { it.name == "Widget" })
}
```

**Do this:**
```kotlin
@Test
fun `filters active products`() {
    val result = service.findActive(catalogId)
    result.shouldHaveSize(2)
    result.shouldAll { it.status shouldBe Status.ACTIVE }
    result.shouldExist { it.name == "Widget" }
}
```

**Why:** Kotest matchers produce descriptive failure messages (e.g., "expected size 2 but was 3") whereas bare `assertTrue` only reports "expected true, got false", making failures harder to diagnose.
