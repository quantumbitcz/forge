# Entity Framework Core Best Practices

## Overview
Entity Framework Core is the standard ORM for .NET applications. Use it for domain-driven applications where a rich object model maps naturally to relational data. Prefer it for greenfield .NET projects with moderate query complexity. Reach for Dapper or raw ADO.NET for bulk analytical queries, high-throughput inserts, or when you need precise SQL control.

## Architecture Patterns

### DbContext design
```csharp
public class AppDbContext : DbContext
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Order> Orders => Set<Order>();

    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    protected override void OnModelCreating(ModelBuilder builder)
    {
        builder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}

// Entity configuration using IEntityTypeConfiguration (preferred over Data Annotations)
public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.HasKey(u => u.Id);
        builder.Property(u => u.Email).IsRequired().HasMaxLength(256);
        builder.HasIndex(u => u.Email).IsUnique();
        builder.HasMany(u => u.Orders).WithOne(o => o.User).HasForeignKey(o => o.UserId);
    }
}
```

### Repository pattern
```csharp
public class UserRepository : IUserRepository
{
    private readonly AppDbContext _db;

    public UserRepository(AppDbContext db) => _db = db;

    public async Task<User?> FindByIdAsync(Guid id, CancellationToken ct = default)
        => await _db.Users.FindAsync(new object[] { id }, ct);

    public async Task<List<User>> GetActiveAsync(CancellationToken ct = default)
        => await _db.Users
            .Where(u => u.IsActive)
            .AsNoTracking()
            .ToListAsync(ct);

    public async Task<User> AddAsync(User user, CancellationToken ct = default)
    {
        _db.Users.Add(user);
        await _db.SaveChangesAsync(ct);
        return user;
    }
}
```

### Value converters
```csharp
// Money value object stored as decimal column
builder.Property(o => o.Amount)
    .HasConversion(
        m => m.Value,
        v => Money.Of(v))
    .HasColumnType("decimal(18,2)");
```

## Configuration

```csharp
// Program.cs
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("Default"),
        npgsql => npgsql
            .MigrationsAssembly(typeof(AppDbContext).Assembly.FullName)
            .EnableRetryOnFailure(3, TimeSpan.FromSeconds(5), null))
    .UseSnakeCaseNamingConvention()   // EFCore.NamingConventions
    .EnableSensitiveDataLogging(builder.Environment.IsDevelopment())
    .EnableDetailedErrors(builder.Environment.IsDevelopment()));
```

## Performance

### Compiled queries
```csharp
// Avoids LINQ expression tree compilation on every call
private static readonly Func<AppDbContext, Guid, Task<User?>> FindUser =
    EF.CompileAsyncQuery((AppDbContext db, Guid id) =>
        db.Users.FirstOrDefault(u => u.Id == id));

// Usage
var user = await FindUser(_db, id);
```

### Split queries for collection navigation
```csharp
// Avoids Cartesian explosion when loading multiple collections
var orders = await _db.Orders
    .Include(o => o.Items)
    .Include(o => o.Tags)
    .AsSplitQuery()
    .ToListAsync(ct);
```

### Bulk operations (EF Core 7+)
```csharp
// Single UPDATE without loading entities
await _db.Users
    .Where(u => u.LastLoginAt < DateTime.UtcNow.AddYears(-1))
    .ExecuteUpdateAsync(s => s.SetProperty(u => u.IsActive, false), ct);

// Bulk DELETE
await _db.AuditLogs
    .Where(l => l.CreatedAt < DateTime.UtcNow.AddDays(-90))
    .ExecuteDeleteAsync(ct);
```

## Security

- Always use parameterized queries — EF Core parameterizes by default; never use `FromSqlRaw` with string interpolation.
- Use `FromSqlInterpolated` when you need raw SQL with parameters — it is injection-safe.
- Apply global query filters for soft delete and multi-tenancy to prevent data leakage.
- Never expose `DbContext` directly in controllers; go through repositories or services.

```csharp
// Safe: interpolated (auto-parameterized)
var users = await _db.Users.FromSqlInterpolated($"SELECT * FROM users WHERE email = {email}").ToListAsync();

// UNSAFE: raw with concatenation
var users = await _db.Users.FromSqlRaw($"SELECT * FROM users WHERE email = '{email}'").ToListAsync();

// Global query filter for multi-tenancy
builder.Entity<Order>().HasQueryFilter(o => o.TenantId == _tenantId);
```

## Testing

```csharp
public class UserRepositoryTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder().Build();

    public async Task InitializeAsync()
    {
        await _db.StartAsync();
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_db.GetConnectionString())
            .Options;
        var context = new AppDbContext(options);
        await context.Database.MigrateAsync();
    }

    [Fact]
    public async Task AddAsync_PersistsUser()
    {
        // Arrange
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_db.GetConnectionString())
            .Options;
        await using var db = new AppDbContext(options);
        var repo = new UserRepository(db);

        // Act
        var user = await repo.AddAsync(new User { Id = Guid.NewGuid(), Email = "x@y.com" });

        // Assert
        (await repo.FindByIdAsync(user.Id)).Should().NotBeNull();
    }

    public async Task DisposeAsync() => await _db.DisposeAsync();
}
```

## Dos
- Use `AsNoTracking()` for read-only queries — significant performance gain with no change tracking overhead.
- Use `IEntityTypeConfiguration<T>` classes instead of `OnModelCreating` monolith methods.
- Use `ExecuteUpdateAsync`/`ExecuteDeleteAsync` (EF Core 7+) for bulk mutations without loading entities.
- Use `AsSplitQuery()` when including multiple collection navigations to avoid Cartesian explosion.
- Use compiled queries for hot paths that run frequently with the same LINQ shape.
- Apply global query filters for soft delete and tenant isolation — they cannot be accidentally forgotten.

## Don'ts
- Don't use `FromSqlRaw` with string concatenation — use `FromSqlInterpolated` or parameters.
- Don't use `Include` on unbounded collections without pagination or projection.
- Don't call `SaveChangesAsync` in a loop; batch changes and save once per unit of work.
- Don't enable `EnableSensitiveDataLogging` in production — it logs parameter values including PII.
- Don't use `Database.EnsureCreated()` in production — use migrations instead.
- Don't load full entities just to update one column; use `ExecuteUpdateAsync` or attach and mark property modified.
