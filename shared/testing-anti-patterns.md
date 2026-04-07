# Testing Anti-Patterns Reference

Patterns that produce tests which cost maintenance time without catching bugs. Each pattern includes a gate function — a question whose answer reveals whether the anti-pattern is present.

---

## 1. Testing Mock Behavior, Not Real Behavior

**Description:** Tests verify that mocks were called with expected arguments but never exercise the actual logic under test. The test passes regardless of whether the implementation is correct.

**Red flag:** Test file has more `verify(mock)` / `expect(mock).toHaveBeenCalledWith(...)` lines than actual assertions on output values.

**Gate:** "If I change the implementation logic, does this test still pass? If yes, it's testing mocks."

**Example (bad):**
```
// Tests that the service calls the repo — not that it returns the right result
test("getUser calls repository") {
    when(repo.findById(1)).thenReturn(user)
    service.getUser(1)
    verify(repo).findById(1)  // passes even if service ignores the result
}
```

**Fix:** Assert on the return value or observable side effect. Mock setup is scaffolding, not the test.
```
test("getUser returns user from repository") {
    when(repo.findById(1)).thenReturn(user)
    result = service.getUser(1)
    assertEquals(user.name, result.name)
}
```

---

## 2. Test-Only Methods in Production Code

**Description:** Public methods, constructors, or accessors added to production classes solely to support test setup or assertion. These expand the public API surface with no production consumer.

**Red flag:** Methods annotated `@VisibleForTesting`, or `internal` methods called only from test files.

**Gate:** "Would this method exist if tests didn't need it?"

**Example (bad):**
```
class OrderProcessor {
    // Only exists so tests can inject a specific clock
    fun setClockForTesting(clock: Clock) { this.clock = clock }
}
```

**Fix:** Use constructor injection or a factory. The production API should not know tests exist.
```
class OrderProcessor(private val clock: Clock = Clock.systemUTC())
```

---

## 3. Mocking Without Understanding Dependencies

**Description:** Mocks return happy-path values that don't match the real dependency's behavior — wrong types, missing error modes, impossible state combinations. Tests pass against the mock but fail against reality.

**Red flag:** Mock setup uses arbitrary placeholder values (`"test"`, `0`, `null`) without checking what the real dependency actually returns.

**Gate:** "Does this mock match the real dependency's contract?"

**Example (bad):**
```
// Real API returns { data: [...], pagination: { next: url } }
// Mock omits pagination entirely
when(api.listUsers()).thenReturn(listOf(user))
```

**Fix:** Base mock return values on actual API responses. Record a real response and use it as the mock fixture. For external APIs, keep a contract test that validates mock assumptions.

---

## 4. Incomplete Mocks

**Description:** Mocks return objects with only the fields the current test needs, hiding bugs that surface when production code accesses other fields. A subset of pattern 3, but common enough to call out separately.

**Red flag:** Mock response objects constructed with only 2-3 fields when the real response has 15+.

**Gate:** "Does this mock include all fields the real response has?"

**Example (bad):**
```
// Real UserProfile has 12 fields; mock has 2
mockProfile = UserProfile(name="Alice", email="a@b.com")
// Production code later accesses mockProfile.role — gets null, no test catches it
```

**Fix:** Use factory functions or fixtures that produce complete objects. Override only the fields relevant to each test.
```
mockProfile = completeUserProfile().copy(name="Alice")
```

---

## 5. Integration Tests as Afterthought

**Description:** All tests are unit tests with mocked dependencies. Integration tests are added late (or never), so the system's actual wiring is never verified. Bugs hide in the seams between components.

**Red flag:** Test suite has 200 unit tests and 0 integration tests. Or integration tests exist but are `@Disabled`.

**Gate:** "Do I have at least one test that exercises the real dependency chain?"

**Example (bad):**
```
// 50 unit tests for UserService with mocked UserRepository
// Zero tests that actually hit the database
// Bug: JPA mapping is wrong — no test catches it
```

**Fix:** For every significant integration boundary (database, HTTP client, message queue), write at least one test that uses the real dependency (or a realistic substitute like Testcontainers). Unit tests verify logic; integration tests verify wiring.

---

## 6. Assertion-Free Tests

**Description:** Tests execute code paths but never assert outcomes. They pass as long as no exception is thrown, giving false confidence. Often created by writing the "arrange" and "act" steps and forgetting "assert."

**Red flag:** Test methods with no `assert*`, `expect*`, `verify*`, or `should*` calls.

**Gate:** "If I remove all assertions, does this test still pass?" (If there are no assertions, the answer is trivially yes.)

**Example (bad):**
```
test("process order") {
    order = createOrder()
    service.process(order)
    // test ends here — no assertion
}
```

**Fix:** Every test must assert at least one observable outcome: a return value, a state change, a published event, or a specific exception.
```
test("process order sets status to CONFIRMED") {
    order = createOrder()
    result = service.process(order)
    assertEquals(OrderStatus.CONFIRMED, result.status)
}
```

---

## 7. Order-Dependent Tests

**Description:** Tests rely on execution order or shared mutable state (static variables, database rows from a previous test, filesystem artifacts). They pass in suite order but fail when run in isolation or in parallel.

**Red flag:** Test fails when run alone but passes in the full suite. Or test passes locally but fails in CI with a different runner.

**Gate:** "Can I run this test in isolation and it still passes?"

**Example (bad):**
```
// Test A inserts a user into shared database
// Test B queries "all users" and expects exactly 1 result
// If Test A doesn't run first, Test B fails
// If Test C also inserts a user, Test B fails
```

**Fix:** Each test sets up its own state and tears it down (or uses transactions that roll back). Never rely on artifacts from other tests. Use unique identifiers to avoid collisions in shared resources.

---

## Quick Reference

| # | Anti-Pattern | Gate Question |
|---|-------------|---------------|
| 1 | Testing mocks | Does changing implementation still pass the test? |
| 2 | Test-only methods | Would this method exist without tests? |
| 3 | Wrong mocks | Does the mock match the real contract? |
| 4 | Incomplete mocks | Does the mock include all real fields? |
| 5 | No integration tests | Is there a test with the real dependency chain? |
| 6 | No assertions | Does the test still pass with assertions removed? |
| 7 | Order-dependent | Does the test pass when run in isolation? |
