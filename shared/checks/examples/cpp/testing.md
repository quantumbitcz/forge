# Testing Patterns (C++)

## arrange-act-assert

**Instead of:**
```cpp
TEST(ParserTest, Parses) {
    Parser p;
    p.setInput("hello world");
    auto result = p.parse();
    EXPECT_TRUE(result.has_value());
    EXPECT_EQ(result->tokens.size(), 2);
    EXPECT_EQ(result->tokens[0].text, "hello");
}
```

**Do this:**
```cpp
TEST(ParserTest, ParsesSpaceSeparatedTokens) {
    // Arrange
    Parser parser;

    // Act
    auto result = parser.parse("hello world");

    // Assert
    ASSERT_TRUE(result.has_value());
    EXPECT_THAT(result->tokens, SizeIs(2));
    EXPECT_THAT(result->tokens[0].text, Eq("hello"));
}
```

**Why:** Naming tests after the specific scenario, separating phases, and using matchers makes test failures self-documenting — the test name and matcher output tell you what broke without reading the implementation.

## mock-interfaces

**Instead of:**
```cpp
TEST(ServiceTest, SendsEmail) {
    bool email_sent = false;
    // Monkeypatch or global flag
    Service svc;
    svc.notify("user@test.com");
    EXPECT_TRUE(email_sent);
}
```

**Do this:**
```cpp
class MockNotifier : public Notifier {
public:
    MOCK_METHOD(void, send, (std::string_view to, std::string_view body), (override));
};

TEST(ServiceTest, NotifiesUserOnCompletion) {
    MockNotifier notifier;
    EXPECT_CALL(notifier, send("user@test.com", HasSubstr("completed")));

    Service svc(notifier);
    svc.complete_task("task-1");
}
```

**Why:** Interface-based mocking verifies the interaction contract between components. GMock expectations fail with precise messages about which call was missing or unexpected.
