# ASP.NET + PostgreSQL (Npgsql + EF Core)

> PostgreSQL setup for ASP.NET using Npgsql EF Core provider with connection string config, health check, and NpgsqlDataSource.

## Integration Setup

```bash
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
dotnet add package Microsoft.EntityFrameworkCore.Design
dotnet add package AspNetCore.HealthChecks.NpgSql
```

## Framework-Specific Patterns

### `appsettings.json` connection string
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=myapp;Username=app;Password=secret"
  }
}
```
In production use user secrets or environment variable: `ConnectionStrings__DefaultConnection`.

### DI registration in `Program.cs`
```csharp
// Program.cs
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        npgsql => npgsql.EnableRetryOnFailure(maxRetryCount: 3)
    ));

// NpgsqlDataSource for raw ADO.NET or Dapper
builder.Services.AddNpgsqlDataSource(
    builder.Configuration.GetConnectionString("DefaultConnection")!);

// Health check
builder.Services.AddHealthChecks()
    .AddNpgSql(builder.Configuration.GetConnectionString("DefaultConnection")!);
```

### DbContext
```csharp
// Infrastructure/AppDbContext.cs
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema("public");
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
    }
}
```

### Entity configuration
```csharp
// Infrastructure/Configurations/UserConfiguration.cs
public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.HasKey(u => u.Id);
        builder.Property(u => u.Email).IsRequired().HasMaxLength(256);
        builder.HasIndex(u => u.Email).IsUnique();
    }
}
```

### Health check endpoint
```csharp
app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("db"),
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse,
});
```

## Scaffolder Patterns
```
src/
  Infrastructure/
    AppDbContext.cs
    Configurations/
      UserConfiguration.cs
  Migrations/
    <timestamp>_InitialCreate.cs
  Program.cs
appsettings.json
appsettings.Development.json
```

## Dos
- Use `IEntityTypeConfiguration<T>` classes over `OnModelCreating` inline configuration
- Enable `EnableRetryOnFailure` for transient fault handling in cloud environments
- Map `ConnectionStrings__DefaultConnection` as an environment variable in containers
- Use `NpgsqlDataSource` for raw SQL / Dapper alongside EF Core in the same app

## Don'ts
- Don't use `EnsureCreated()` in production — use EF migrations (`dotnet ef database update`)
- Don't store connection string passwords in `appsettings.json` committed to git
- Don't call `DbContext` from multiple threads simultaneously — it is not thread-safe
- Don't skip the health check endpoint — K8s readiness probes depend on it
