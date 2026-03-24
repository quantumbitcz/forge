# EF Core Migrations Best Practices

## Overview
EF Core Migrations is the built-in schema evolution tool for .NET projects using Entity Framework Core. Use it for .NET applications that already use EF Core — migrations integrate directly with the model and DbContext, keeping schema and code in sync. For teams preferring SQL-first migrations, pair EF Core with Flyway or Liquibase instead.

## Architecture Patterns

### Directory structure
```
src/
└── Infrastructure/
    └── Persistence/
        ├── AppDbContext.cs
        └── Migrations/
            ├── 20240101000000_InitialCreate.cs
            ├── 20240101000000_InitialCreate.Designer.cs
            ├── 20240115093000_AddUserEmailIndex.cs
            └── AppDbContextModelSnapshot.cs
```

### Creating and applying migrations
```bash
# Add a new migration
dotnet ef migrations add AddUserEmailIndex \
  --project src/Infrastructure \
  --startup-project src/Api \
  --output-dir Persistence/Migrations

# Apply pending migrations
dotnet ef database update \
  --project src/Infrastructure \
  --startup-project src/Api

# Generate idempotent SQL script (for production / review)
dotnet ef migrations script --idempotent \
  --output migrations.sql \
  --project src/Infrastructure \
  --startup-project src/Api
```

### Migration bundle (single executable)
```bash
# Produces a self-contained binary that applies migrations
dotnet ef migrations bundle \
  --project src/Infrastructure \
  --startup-project src/Api \
  --output ./efbundle

# Run in CI/CD
./efbundle --connection "$CONNECTION_STRING"
```

## Configuration

```csharp
// Apply migrations at startup (suitable for dev / containerized deployments)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}

// In production pipelines, prefer the migration bundle or idempotent SQL script
// so migrations are not run by the application process itself
```

## Performance

### Zero-downtime migrations
Split breaking DDL changes across two deployments:
1. Deploy N: Add new nullable column (non-breaking to the running app).
2. Deploy N+1: Backfill data, add NOT NULL constraint, remove old column.

```csharp
// Migration N — add nullable column
migrationBuilder.AddColumn<string>(
    name: "display_name",
    table: "users",
    nullable: true);

// Migration N+1 — backfill then enforce constraint
migrationBuilder.Sql("UPDATE users SET display_name = first_name || ' ' || last_name WHERE display_name IS NULL");
migrationBuilder.AlterColumn<string>(
    name: "display_name",
    table: "users",
    nullable: false,
    defaultValue: "");
```

### Concurrent index creation (PostgreSQL)
```csharp
// Avoid table lock for large tables; must disable transactions
migrationBuilder.Sql(
    "CREATE INDEX CONCURRENTLY idx_orders_status ON orders(status);",
    suppressTransaction: true);
```

## Security
- Run migrations with a deployment user that has DDL rights; the runtime app user should have DML only.
- Store the migration connection string separately from the runtime connection string (different credentials).
- Review generated migration files before merging — EF Core may generate unexpected `DropColumn` or `DropTable` calls after model changes.
- Use `--idempotent` scripts for production to allow safe re-runs after partial failures.

## Testing

```csharp
// Integration test: apply migrations to a Testcontainer before the test suite
public class MigrationTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder().Build();

    public async Task InitializeAsync() => await _db.StartAsync();
    public async Task DisposeAsync() => await _db.DisposeAsync();

    [Fact]
    public async Task AllMigrationsApply_WithoutError()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(_db.GetConnectionString())
            .Options;
        await using var db = new AppDbContext(options);
        // MigrateAsync applies all pending migrations; throws on failure
        await db.Database.MigrateAsync();
        var pending = (await db.Database.GetPendingMigrationsAsync()).ToList();
        pending.Should().BeEmpty("all migrations should be applied");
    }
}
```

## Dos
- Use `--idempotent` SQL scripts for production deployments — safe to re-run after partial failures.
- Use migration bundles in CI/CD pipelines for self-contained, version-pinned deployments.
- Review auto-generated migrations before committing — EF Core may produce destructive operations unexpectedly.
- Test all migrations on a copy of production data before rolling out to large tables.
- Use `suppressTransaction: true` for `CREATE INDEX CONCURRENTLY` and similar non-transactional DDL.

## Don'ts
- Don't modify migration files after they have been applied to any shared environment — it breaks the migration history.
- Don't use `Database.EnsureCreated()` in any environment that uses migrations — they are mutually exclusive.
- Don't apply migrations from the application process in production — use the bundle or SQL script approach.
- Don't use `dotnet ef database update` directly in production; generate and review scripts first.
- Don't delete the `Migrations/` folder to "start fresh" without resetting all environments; use a squash migration instead.
