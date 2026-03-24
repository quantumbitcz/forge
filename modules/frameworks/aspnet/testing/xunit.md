# ASP.NET Core + xUnit Testing Patterns

> ASP.NET Core-specific testing patterns for xUnit. Extends `modules/testing/xunit-nunit.md`.
> Generic xUnit conventions (Fact, Theory, FluentAssertions, Moq) are NOT repeated here.

## Integration Tests with WebApplicationFactory

### Full Application Tests

```csharp
public class UserApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public UserApiTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task CreateUser_ReturnsCreated_WithLocationHeader()
    {
        var request = new CreateUserRequest { Name = "Alice", Email = "alice@example.com" };
        var response = await _client.PostAsJsonAsync("/api/v1/users", request);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();
    }
}
```

### Customized Factory

Override services (e.g., swap real DB for Testcontainers):

```csharp
public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Remove real DbContext and replace with test database
            var descriptor = services.Single(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>));
            services.Remove(descriptor);
            services.AddDbContext<AppDbContext>(options =>
                options.UseNpgsql(TestContainerConnectionString));
        });
    }
}
```

## Controller Slice Tests

For lightweight unit-style controller tests without full application context:

```csharp
[Fact]
public async Task GetUser_ReturnsNotFound_WhenUserDoesNotExist()
{
    var service = Substitute.For<IUserService>();  // NSubstitute or Moq
    service.GetByIdAsync(Arg.Any<Guid>(), Arg.Any<CancellationToken>())
           .Returns((UserResponse?)null);
    var controller = new UsersController(service);

    var result = await controller.GetAsync(Guid.NewGuid(), CancellationToken.None);

    result.Result.Should().BeOfType<NotFoundResult>();
}
```

## Repository / EF Core Tests with Testcontainers

```csharp
public class UserRepositoryTests : IAsyncLifetime
{
    private PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    private AppDbContext _dbContext = null!;

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_postgres.GetConnectionString())
            .Options;
        _dbContext = new AppDbContext(options);
        await _dbContext.Database.MigrateAsync();
    }

    [Fact]
    public async Task FindByEmail_ReturnsUser_WhenExists()
    {
        _dbContext.Users.Add(new User { Name = "Alice", Email = "alice@example.com" });
        await _dbContext.SaveChangesAsync();

        var result = await new UserRepository(_dbContext).FindByEmailAsync("alice@example.com");

        result.Should().NotBeNull();
        result!.Name.Should().Be("Alice");
    }

    public async Task DisposeAsync() => await _postgres.DisposeAsync();
}
```

## Service Unit Tests

```csharp
public class UserServiceTests
{
    private readonly IUserRepository _repo = Substitute.For<IUserRepository>();
    private readonly UserService _sut;

    public UserServiceTests() => _sut = new UserService(_repo);

    [Fact]
    public async Task CreateUser_ThrowsConflict_WhenEmailExists()
    {
        _repo.ExistsByEmailAsync("alice@example.com", default).Returns(true);

        var act = async () => await _sut.CreateAsync(
            new CreateUserRequest { Name = "Alice", Email = "alice@example.com" });

        await act.Should().ThrowAsync<ConflictException>();
    }
}
```

## FluentAssertions Patterns

- `response.StatusCode.Should().Be(HttpStatusCode.Ok)`
- `result.Should().BeOfType<OkObjectResult>().Which.Value.Should().BeEquivalentTo(expected)`
- `act.Should().ThrowAsync<XxxException>().WithMessage("*partial message*")`
- Use `.BeEquivalentTo()` for DTO comparison — ignores property order

## What to Test at Each Layer

| Layer | Test type | Tools |
|-------|-----------|-------|
| Controller (API) | Integration | `WebApplicationFactory` + `HttpClient` |
| Controller (unit) | Unit | NSubstitute/Moq + direct instantiation |
| Service | Unit | NSubstitute/Moq, no ASP.NET context |
| Repository | Integration | Testcontainers PostgreSQL + EF Core |
| Mapper | Unit | Direct static method calls |

## Sharing Testcontainers Across Tests

Use `ICollectionFixture<T>` to share a single container across a test collection:

```csharp
[CollectionDefinition("Database")]
public class DatabaseCollection : ICollectionDefinition<DatabaseFixture> { }

[Collection("Database")]
public class UserRepositoryTests(DatabaseFixture db) { ... }
```

This avoids spinning up a container per test class.
