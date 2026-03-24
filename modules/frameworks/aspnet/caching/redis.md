# ASP.NET Core + Redis Caching

> ASP.NET Core-specific patterns for distributed caching via StackExchange.Redis. Extends generic ASP.NET conventions.

## Integration Setup

```bash
dotnet add package Microsoft.Extensions.Caching.StackExchangeRedis
dotnet add package Microsoft.AspNetCore.OutputCaching.StackExchangeRedis  # .NET 7+ output caching
```

```csharp
// Program.cs
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    // redis://localhost:6379,abortConnect=false,connectTimeout=5000
    options.InstanceName = "myapp:";  // key prefix
});

// Output caching (API response level)
builder.Services.AddOutputCache(options =>
{
    options.AddBasePolicy(policy => policy.Expire(TimeSpan.FromSeconds(30)));
    options.AddPolicy("products", policy => policy.Expire(TimeSpan.FromMinutes(5)).Tag("products"));
});
builder.Services.AddStackExchangeRedisOutputCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
});
```

## Framework-Specific Patterns

### IDistributedCache — manual cache-aside

```csharp
// Application/Services/UserService.cs
public class UserService(IDistributedCache cache, IUserRepository repo)
{
    private static readonly DistributedCacheEntryOptions _opts = new()
    {
        AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10),
        SlidingExpiration = TimeSpan.FromMinutes(2),
    };

    public async Task<UserDto?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        var key = $"users:{id}";
        var cached = await cache.GetStringAsync(key, ct);
        if (cached is not null)
            return JsonSerializer.Deserialize<UserDto>(cached);

        var user = await repo.FindByIdAsync(id, ct);
        if (user is null) return null;

        var dto = user.ToDto();
        await cache.SetStringAsync(key, JsonSerializer.Serialize(dto), _opts, ct);
        return dto;
    }

    public async Task InvalidateAsync(Guid id, CancellationToken ct = default)
        => await cache.RemoveAsync($"users:{id}", ct);
}
```

### Output caching middleware (endpoint level)

```csharp
// Controllers/ProductsController.cs
[HttpGet]
[OutputCache(PolicyName = "products")]
public async Task<IActionResult> List() { ... }

// Programmatic invalidation
app.MapPost("/products", async (IOutputCacheStore store, ...) =>
{
    // ... create product ...
    await store.EvictByTagAsync("products", ct);
    return Results.Created(...);
});
```

## Scaffolder Patterns

```
Application/
  Services/
    UserService.cs          # IDistributedCache cache-aside pattern
Infrastructure/
  DependencyInjection.cs    # AddStackExchangeRedisCache registration
```

## Dos

- Always set `AbsoluteExpirationRelativeToNow` — never let keys live forever in Redis
- Set `InstanceName` to scope keys per application and prevent cross-app collisions in shared Redis
- Use `OutputCache` attribute for read-heavy GET endpoints; use `IDistributedCache` for programmatic control
- Tag output cache entries so they can be batch-evicted by domain event (e.g., `EvictByTagAsync("products")`)

## Don'ts

- Don't use `IMemoryCache` for data that must be consistent across multiple instances — use `IDistributedCache`
- Don't cache mutable domain entities — cache DTOs or value objects that don't change identity
- Don't skip `CancellationToken` on all cache calls — long Redis operations should be cancellable
- Don't use `SlidingExpiration` alone without `AbsoluteExpiration` — sliding expiry allows indefinite cache lifetime
