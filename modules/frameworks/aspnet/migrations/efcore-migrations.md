# ASP.NET Core + EF Core Migrations

> ASP.NET Core-specific patterns for EF Core migrations. Extends generic ASP.NET conventions.
> EF Core setup is covered in `persistence/efcore.md`. Not repeated here.

## CLI Setup

```bash
dotnet tool install --global dotnet-ef
# Or add as local tool
dotnet tool install dotnet-ef
dotnet tool restore
```

Required package in the project:
```bash
dotnet add package Microsoft.EntityFrameworkCore.Design
```

## Core Commands

```bash
# Create a new migration
dotnet ef migrations add CreateUsersTable --project Infrastructure --startup-project Api

# Apply pending migrations
dotnet ef database update --project Infrastructure --startup-project Api

# Revert last migration
dotnet ef database update PreviousMigrationName

# Remove last unapplied migration
dotnet ef migrations remove --project Infrastructure --startup-project Api

# List all migrations and their status
dotnet ef migrations list --project Infrastructure --startup-project Api
```

## Idempotent SQL Scripts

Generate a script safe to run on any database state:

```bash
dotnet ef migrations script --idempotent --output migrations.sql \
    --project Infrastructure --startup-project Api
```

Use this for manual production deployments or DBA review.

## Migration Bundles (EF 8+)

Self-contained executable that applies migrations without the EF CLI:

```bash
dotnet ef migrations bundle --self-contained -r linux-x64 \
    --project Infrastructure --startup-project Api \
    --output ./artifacts/efbundle
```

Deploy the bundle alongside the application and run it as part of the deployment step:

```yaml
# GitHub Actions deployment step
- name: Apply migrations
  run: ./artifacts/efbundle --connection "${{ secrets.DB_CONNECTION_STRING }}"
```

## CI/CD Deployment Pattern

Recommended approach: migration bundle in a pre-deploy job:

```yaml
jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
      - run: dotnet ef migrations bundle --self-contained -r linux-x64 -o efbundle
      - run: ./efbundle
        env:
          CONNECTIONSTRINGS__DEFAULTCONNECTION: ${{ secrets.DB_CONNECTION_STRING }}

  deploy:
    needs: migrate
    runs-on: ubuntu-latest
    # ... deploy application
```

## Auto-Apply at Startup (Staging Only)

```csharp
// Program.cs — staging/preview environments only
if (app.Environment.IsStaging() || app.Environment.IsDevelopment())
{
    using var scope = app.Services.CreateScope();
    var dbContext = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await dbContext.Database.MigrateAsync();
}
```

Do NOT use this pattern in production — it does not handle concurrent deployment scenarios.

## Scaffolder Patterns

```yaml
patterns:
  migrations_dir: "Infrastructure/Persistence/Migrations/"
  migration: "Infrastructure/Persistence/Migrations/{timestamp}_{Name}.cs"
  migration_snapshot: "Infrastructure/Persistence/Migrations/AppDbContextModelSnapshot.cs"
  bundle_output: "artifacts/efbundle"
```

## Additional Dos/Don'ts

- DO use migration bundles for production deployments — they are self-contained and auditable
- DO generate idempotent scripts for change-management review
- DO separate the `--project` (data layer) from `--startup-project` (API) in all CLI commands
- DO commit all migration files (`.cs` snapshot) — never `.gitignore` the Migrations folder
- DON'T use `database update` directly in production CI without a rollback plan
- DON'T add data transformations in migrations that can fail — prefer a separate script
- DON'T modify generated migration code manually unless absolutely necessary
