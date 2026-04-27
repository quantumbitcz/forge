# xUnit / NUnit Testing Conventions (.NET)
> Support tier: contract-verified
## Test Structure

Prefer **xUnit** for new projects — it enforces test isolation by creating a fresh instance per test. NUnit is acceptable for existing test suites. One test class per production class; use nested classes for scenario grouping.

```csharp
public class OrderServiceTests
{
    private readonly IOrderRepository _repo;
    private readonly OrderService _sut;

    public OrderServiceTests()   // xUnit: constructor = setUp
    {
        _repo = Substitute.For<IOrderRepository>();
        _sut  = new OrderService(_repo);
    }

    public class WhenPlacingAnOrder : OrderServiceTests
    {
        [Fact]
        public async Task ItPersistsAndReturnsTheOrder() { ... }
    }
}
```

## Naming

- Class: `{Subject}Tests`
- Method: `{Action}_{Context}__{Expectation}` or plain English
- Nested class (scenario group): `When{Condition}` / `Given{State}`

## Assertions / Matchers

Use **FluentAssertions**:

```csharp
result.Should().Be(expected);
list.Should().ContainSingle(x => x.Id == id);
list.Should().BeEquivalentTo(expected);
str.Should().StartWith("prefix").And.EndWith("suffix");
act.Should().Throw<ArgumentException>().WithMessage("*invalid*");
await act.Should().ThrowAsync<NotFoundException>();
obj.Should().BeNull();
obj.Should().NotBeNull().And.BeOfType<Admin>();
```

Avoid `Assert.Equal` — FluentAssertions error messages are far more readable.

## Test Attributes — xUnit

```csharp
[Fact]                             // single test case
[Theory]                           // data-driven
[InlineData(1, "one")]             // inline parameters
[MemberData(nameof(Cases))]        // method-provided data
[ClassData(typeof(OrderCases))]    // class-provided data
[Trait("Category", "Integration")] // categorization
```

## Test Attributes — NUnit

```csharp
[Test]
[TestCase(1, "one")]
[TestCaseSource(nameof(Cases))]
[Category("Integration")]
[SetUp] / [TearDown]
[OneTimeSetUp] / [OneTimeTearDown]
```

## Lifecycle — xUnit

xUnit has no `[SetUp]` — use the constructor. For async setup implement `IAsyncLifetime`:

```csharp
public class DbTests : IAsyncLifetime
{
    public async Task InitializeAsync() { /* start container */ }
    public async Task DisposeAsync()    { /* stop container  */ }
}
```

For shared expensive context (e.g., database), use `IClassFixture<T>`:

```csharp
public class UserTests : IClassFixture<DatabaseFixture>
{
    public UserTests(DatabaseFixture db) { ... }
}
```

## Mocking — NSubstitute

```csharp
var repo = Substitute.For<IUserRepository>();
repo.FindById(Arg.Any<Guid>()).Returns(user);
repo.FindById(Arg.Any<Guid>()).Returns(Task.FromResult(user));  // async

// Verify calls
await repo.Received(1).Save(Arg.Is<User>(u => u.Email == "a@b.com"));
repo.DidNotReceive().Delete(Arg.Any<Guid>());
```

## Integration Tests

Use `WebApplicationFactory<Program>` for in-process API tests:

```csharp
public class UserApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    public UserApiTests(WebApplicationFactory<Program> factory)
        => _client = factory.CreateClient();

    [Fact]
    public async Task GetUser_ReturnsOk()
    {
        var resp = await _client.GetAsync("/users/1");
        resp.Should().HaveStatusCode(HttpStatusCode.OK);
    }
}
```

## Collection Fixtures

For database sharing across test classes:

```csharp
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionFixture<DatabaseFixture> { }

[Collection("Database")]
public class OrderTests { ... }
```

## What NOT to Test

- Auto-property getters/setters with no logic
- EF Core model configuration (column names, FK constraints) — test via migrations
- Serialization/deserialization of simple DTOs — trust `System.Text.Json`
- ASP.NET Core middleware you didn't write

## Anti-Patterns

- Sharing mutable state via static fields across tests (xUnit runs in parallel by default)
- `Thread.Sleep` — use `Task.Delay` or mock `IDateTimeProvider`
- Nesting `IClassFixture` and constructor setup for the same concern
- Asserting on exception `.Message` string with exact match — use `.WithMessage("*partial*")`
- Overusing `[Collection]` to serialize tests when isolation is not actually needed
