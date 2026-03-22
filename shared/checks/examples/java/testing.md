# Testing Patterns (Java)

## junit5-parameterized

**Instead of:**
```java
@Test void testParseValidEmail()   { assertTrue(EmailValidator.isValid("a@b.com")); }
@Test void testParseWithPlus()     { assertTrue(EmailValidator.isValid("a+tag@b.com")); }
@Test void testParseNoDomain()     { assertFalse(EmailValidator.isValid("a@")); }
@Test void testParseEmpty()        { assertFalse(EmailValidator.isValid("")); }
```

**Do this:**
```java
@ParameterizedTest
@CsvSource({
    "a@b.com,      true",
    "a+tag@b.com,  true",
    "a@,           false",
    "'',           false"
})
void validatesEmailFormat(String input, boolean expected) {
    assertThat(EmailValidator.isValid(input)).isEqualTo(expected);
}
```

**Why:** `@ParameterizedTest` eliminates copy-paste test methods, makes it trivial to add cases, and reports each row as a separate test result for clear failure isolation.

## mockito-verify

**Instead of:**
```java
@Test
void sendWelcomeEmail() {
    var sent = new AtomicBoolean(false);
    var mailer = new Mailer() {
        @Override public void send(String to, String body) { sent.set(true); }
    };
    new RegistrationService(repo, mailer).register(newUser);
    assertTrue(sent.get());
}
```

**Do this:**
```java
@Test
void sendWelcomeEmail(@Mock Mailer mailer) {
    new RegistrationService(repo, mailer).register(newUser);

    verify(mailer).send(
        eq(newUser.getEmail()),
        contains("Welcome")
    );
}
```

**Why:** Mockito's `verify` with argument matchers asserts both that the call happened and what was passed, replacing hand-rolled fakes that only check "was something called."

## assertj-fluent

**Instead of:**
```java
@Test
void filtersActiveUsers() {
    var result = service.findActive(teamId);
    assertEquals(2, result.size());
    assertTrue(result.stream().allMatch(u -> u.getStatus() == ACTIVE));
    assertNotNull(result.get(0).getLastLogin());
}
```

**Do this:**
```java
@Test
void filtersActiveUsers() {
    var result = service.findActive(teamId);
    assertThat(result)
        .hasSize(2)
        .allSatisfy(u -> assertThat(u.getStatus()).isEqualTo(ACTIVE))
        .extracting(User::getLastLogin)
        .doesNotContainNull();
}
```

**Why:** AssertJ's fluent chain produces a single readable assertion block with rich failure messages (showing the actual list contents), instead of three unrelated `assert*` calls that only say "expected true."

## test-naming

**Instead of:**
```java
@Test void test1() { /* ... */ }
@Test void testGetUser() { /* ... */ }
@Test void testGetUserNotFound() { /* ... */ }
```

**Do this:**
```java
@Nested
class FindById {
    @Test void returnsUserWhenExists() { /* ... */ }
    @Test void throwsNotFoundForUnknownId() { /* ... */ }
    @Test void throwsOnNullId() { /* ... */ }
}
```

**Why:** `@Nested` classes group tests by operation and descriptive method names read as a specification, making test reports self-documenting without opening the source.
