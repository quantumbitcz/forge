# ASP.NET Core + EF Core

> ASP.NET Core-specific patterns for Entity Framework Core. Extends generic ASP.NET conventions.
> Generic ASP.NET patterns (controllers, DI, error handling) are NOT repeated here.

## Integration Setup

```bash
dotnet add package Microsoft.EntityFrameworkCore
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL   # or SqlServer / Sqlite
dotnet add package Microsoft.EntityFrameworkCore.Design    # for migrations CLI
```

## DbContext Registration

```csharp
// Program.cs
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        npgsql => npgsql.EnableRetryOnFailure(maxRetryCount: 3)));
```

For scoped lifetime (default), each HTTP request gets its own `DbContext` — do NOT make it singleton.

## DbContext Definition

```csharp
// Infrastructure/Persistence/AppDbContext.cs
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

## Entity Configuration

```csharp
// Infrastructure/Persistence/Config/UserConfiguration.cs
public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.HasKey(u => u.Id);
        builder.Property(u => u.Email).HasMaxLength(320).IsRequired();
        builder.HasIndex(u => u.Email).IsUnique();
        builder.HasMany(u => u.Orders).WithOne(o => o.User).HasForeignKey(o => o.UserId);
    }
}
```

## Value Converters

```csharp
// Map domain type (e.g., Money) to DB column
builder.Property(o => o.Amount)
    .HasConversion(
        v => v.Amount,
        v => new Money(v, Currency.EUR))
    .HasColumnType("decimal(18,2)");
```

## Compiled Queries

```csharp
// Cache compiled query for hot paths
private static readonly Func<AppDbContext, Guid, Task<User?>> GetUserById =
    EF.CompileAsyncQuery((AppDbContext ctx, Guid id) =>
        ctx.Users.AsNoTracking().FirstOrDefault(u => u.Id == id));

// Usage
var user = await GetUserById(_dbContext, id);
```

## Change Tracking

- Use `AsNoTracking()` for read-only queries (reports, lookups) — reduces overhead significantly
- Use `AsNoTrackingWithIdentityResolution()` when projecting related data with duplicates
- Avoid loading entities you only need to read — use `Select()` projections

```csharp
// Read-only projection — no change tracking
var dto = await _context.Users
    .AsNoTracking()
    .Where(u => u.Id == id)
    .Select(u => new UserDto(u.Id, u.Name, u.Email))
    .FirstOrDefaultAsync();
```

## Split Queries

Prevent cartesian explosion when loading multiple collection navigations:

```csharp
var users = await _context.Users
    .Include(u => u.Orders)
    .Include(u => u.Addresses)
    .AsSplitQuery()   // issues separate SQL per Include
    .ToListAsync();
```

## Scaffolder Patterns

```yaml
patterns:
  db_context: "Infrastructure/Persistence/AppDbContext.cs"
  entity_config: "Infrastructure/Persistence/Config/{Entity}Configuration.cs"
  repository: "Infrastructure/Persistence/{Entity}Repository.cs"
  repository_interface: "Application/Interfaces/I{Entity}Repository.cs"
  migrations_dir: "Infrastructure/Persistence/Migrations/"
```

## Additional Dos/Don'ts

- DO use `ApplyConfigurationsFromAssembly` — keeps DbContext clean
- DO use compiled queries (`EF.CompileAsyncQuery`) for hot-path reads
- DO use `AsNoTracking()` for all read-only operations
- DO use `AsSplitQuery()` when including multiple collection navigations
- DON'T call `SaveChangesAsync()` in repositories — call it in the unit-of-work or application layer
- DON'T use `EF.Functions` in domain logic — keep domain layer EF-free
- DON'T set `AutoSave` on the DbContext — save changes explicitly
