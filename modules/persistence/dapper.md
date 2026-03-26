# Dapper Best Practices

## Overview
Dapper is a lightweight micro-ORM for .NET that extends `IDbConnection` with simple object mapping. Use it when you need direct SQL control with convenient result mapping, high-performance data access, or when EF Core's overhead is unnecessary. Dapper excels at read-heavy applications, reporting, stored procedure integration, and scenarios where SQL expertise is preferred over LINQ. Avoid it for complex domain models with deep relationships where EF Core's change tracking and navigation properties save significant development time.

## Architecture Patterns

**Basic query mapping:**
```csharp
public record User(int Id, string Email, string Name, DateTime CreatedAt);

var users = await connection.QueryAsync<User>(
    "SELECT id, email, name, created_at FROM users WHERE email LIKE @Pattern ORDER BY created_at DESC LIMIT @Limit",
    new { Pattern = "%@example.com", Limit = 20 });
```

**Multi-mapping (joins):**
```csharp
var orders = await connection.QueryAsync<Order, User, Order>(
    @"SELECT o.*, u.* FROM orders o
      INNER JOIN users u ON o.user_id = u.id
      WHERE o.status = @Status",
    (order, user) => { order.User = user; return order; },
    new { Status = "active" },
    splitOn: "id");
```

**Stored procedures:**
```csharp
var result = await connection.QueryAsync<OrderSummary>(
    "sp_GetOrderSummary",
    new { UserId = userId, StartDate = startDate },
    commandType: CommandType.StoredProcedure);
```

**Transactions:**
```csharp
using var transaction = connection.BeginTransaction();
var orderId = await connection.ExecuteScalarAsync<int>(
    "INSERT INTO orders (user_id, total) VALUES (@UserId, @Total) RETURNING id",
    new { UserId = userId, Total = total }, transaction);
await connection.ExecuteAsync(
    "INSERT INTO order_items (order_id, sku, qty, price) VALUES (@OrderId, @Sku, @Qty, @Price)",
    items.Select(i => new { OrderId = orderId, i.Sku, i.Qty, i.Price }), transaction);
transaction.Commit();
```

**Anti-pattern — building SQL with string concatenation:** Dapper parameterizes `@param` placeholders. Never use `$"WHERE id = {userId}"` — use `new { userId }` as the parameter object.

## Configuration

**Connection management (ASP.NET Core DI):**
```csharp
builder.Services.AddScoped<IDbConnection>(_ =>
    new NpgsqlConnection(builder.Configuration.GetConnectionString("Default")));
```

**Dapper configuration:**
```csharp
// Map snake_case columns to PascalCase properties
Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;

// Custom type handler
SqlMapper.AddTypeHandler(new DateTimeOffsetHandler());
```

## Performance

**Use `QueryFirstOrDefaultAsync` instead of `QueryAsync().FirstOrDefault()`** — the former adds `LIMIT 1` at the SQL level.

**Buffered vs unbuffered:**
```csharp
// Default: buffered (loads all rows into memory)
var users = await connection.QueryAsync<User>(sql);

// Unbuffered: streams rows one by one (for large result sets)
var users = connection.Query<User>(sql, buffered: false);
```

**Batch operations with Dapper.Plus or manual multi-row INSERT:**
```csharp
// Multi-row insert
await connection.ExecuteAsync(
    "INSERT INTO events (type, payload) VALUES (@Type, @Payload::jsonb)",
    events);  // Dapper iterates the collection automatically
```

**CommandDefinition for cancellation and timeouts:**
```csharp
var cmd = new CommandDefinition(sql, parameters, commandTimeout: 30, cancellationToken: ct);
var result = await connection.QueryAsync<User>(cmd);
```

## Security

**All parameters are bind parameters by default.** Dapper escapes nothing — it sends parameters as protocol-level bind values, making SQL injection impossible when using `@param` placeholders.

**Never use string interpolation for SQL:**
```csharp
// SAFE
connection.Query<User>("SELECT * FROM users WHERE id = @Id", new { Id = userId });

// UNSAFE — SQL injection
connection.Query<User>($"SELECT * FROM users WHERE id = {userId}");
```

**Use `IDbConnection` behind a repository interface** to control SQL access and prevent ad-hoc queries from controllers.

## Testing

```csharp
[Fact]
public async Task Should_find_user_by_email()
{
    await using var connection = new NpgsqlConnection(_connectionString);
    await connection.ExecuteAsync("INSERT INTO users (email, name) VALUES (@Email, @Name)",
        new { Email = "test@example.com", Name = "Test" });

    var user = await connection.QueryFirstOrDefaultAsync<User>(
        "SELECT * FROM users WHERE email = @Email", new { Email = "test@example.com" });

    Assert.NotNull(user);
    Assert.Equal("test@example.com", user.Email);
}
```

Use Testcontainers for integration tests with a real database. Dapper tests are fast because there's no ORM startup overhead. Test SQL queries against the actual database engine to catch syntax and type-mapping issues.

## Dos
- Use `MatchNamesWithUnderscores = true` to automatically map `snake_case` DB columns to `PascalCase` C# properties.
- Use parameterized queries (`@param` + anonymous objects) for all user-facing queries.
- Use `QueryFirstOrDefaultAsync` for single-result queries — it's cleaner and adds `LIMIT 1`.
- Use transactions explicitly for multi-statement operations — Dapper doesn't have a unit of work.
- Use records or readonly DTOs for query results — Dapper maps to constructors and properties.
- Use `CommandDefinition` with `CancellationToken` for long-running queries.
- Keep SQL in the repository layer — don't scatter queries across controllers and services.

## Don'ts
- Don't use string interpolation (`$"..."`) for SQL — it bypasses parameterization entirely.
- Don't use `Query` (buffered) for large result sets — use `Query(buffered: false)` or pagination.
- Don't share `IDbConnection` across threads — connections are not thread-safe.
- Don't use Dapper for complex domain models with deep object graphs — EF Core handles those better.
- Don't forget to dispose connections — use `using` statements or DI scoped lifetime.
- Don't write migration logic with Dapper — use a dedicated migration tool (Flyway, FluentMigrator, DbUp).
- Don't ignore `splitOn` in multi-mapping queries — incorrect splits produce null navigation properties.
