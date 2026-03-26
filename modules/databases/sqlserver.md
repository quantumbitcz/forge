# SQL Server Best Practices

## Overview
Microsoft SQL Server is an enterprise relational database with deep Windows/.NET integration, advanced query optimization, and mature tooling. Use it for enterprise applications, .NET backends, data warehousing (with columnstore indexes), and workloads needing tight Active Directory integration. Avoid SQL Server for cost-sensitive startups (licensing), Linux-first teams preferring PostgreSQL, or simple embedded use cases (use SQLite).

## Architecture Patterns

**Connection pooling via ADO.NET or HikariCP:**
```csharp
// .NET — pooling is automatic; tune via connection string
"Server=db;Database=mydb;User Id=app;Password=...;Max Pool Size=100;Min Pool Size=5;Connection Timeout=15;Encrypt=True;TrustServerCertificate=False"
```
ADO.NET pools by default. Never disable pooling (`Pooling=false`) in production.

**Clustered vs non-clustered indexes:**
```sql
-- Clustered index defines physical row order — one per table
CREATE CLUSTERED INDEX IX_Orders_CreatedAt ON Orders(CreatedAt);

-- Non-clustered index for lookup patterns
CREATE NONCLUSTERED INDEX IX_Orders_UserId
  ON Orders(UserId) INCLUDE (Status, Total);
```
Use `INCLUDE` columns to create covering indexes that avoid key lookups.

**Filtered indexes for sparse conditions:**
```sql
CREATE NONCLUSTERED INDEX IX_Orders_Active
  ON Orders(UserId, CreatedAt)
  WHERE Status = 'Active';
```

**Temporal tables for audit trails:**
```sql
CREATE TABLE Products (
  Id INT PRIMARY KEY,
  Name NVARCHAR(100),
  Price DECIMAL(18,2),
  ValidFrom DATETIME2 GENERATED ALWAYS AS ROW START,
  ValidTo DATETIME2 GENERATED ALWAYS AS ROW END,
  PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON);
```

**Anti-pattern — cursors for set-based operations:** Row-by-row cursor processing is orders of magnitude slower than set-based SQL. Replace cursors with CTEs, window functions, or MERGE statements.

## Configuration

**Development:**
```sql
-- Enable query store for performance tracking
ALTER DATABASE mydb SET QUERY_STORE = ON;
ALTER DATABASE mydb SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
```

**Production tuning:**
```sql
-- Memory: 75-80% of RAM for SQL Server
EXEC sp_configure 'max server memory (MB)', 24576; -- 24GB on 32GB host
RECONFIGURE;

-- Max degree of parallelism (NUMA-aware)
EXEC sp_configure 'max degree of parallelism', 4;
EXEC sp_configure 'cost threshold for parallelism', 25;
RECONFIGURE;

-- TempDB: one data file per CPU core (up to 8)
ALTER DATABASE tempdb ADD FILE (NAME = 'tempdev2', FILENAME = '/var/opt/mssql/data/tempdev2.ndf');
```

**Connection string (production):**
```
Server=tcp:myserver.database.windows.net,1433;Database=mydb;User ID=app;Password=...;Encrypt=True;Connection Timeout=15;Application Name=myapp
```

## Performance

**Execution plan analysis:**
```sql
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
-- Or graphical plan
SET SHOWPLAN_XML ON;
```
Look for: table scans on large tables, key lookups, implicit conversions, parameter sniffing issues.

**Avoid implicit type conversions:**
```sql
-- BAD: varchar parameter against nvarchar column — full scan
WHERE Email = @email  -- @email is varchar, column is nvarchar

-- GOOD: match parameter type to column type
DECLARE @email NVARCHAR(255) = N'user@example.com';
```

**Batch operations with MERGE:**
```sql
MERGE INTO Products AS target
USING @updates AS source ON target.Id = source.Id
WHEN MATCHED THEN UPDATE SET Name = source.Name, Price = source.Price
WHEN NOT MATCHED THEN INSERT (Id, Name, Price) VALUES (source.Id, source.Name, source.Price);
```

**Columnstore indexes for analytics:**
```sql
CREATE NONCLUSTERED COLUMNSTORE INDEX IX_Sales_Columnstore
  ON Sales(ProductId, Quantity, Amount, SaleDate);
```

## Security

**Least-privilege database roles:**
```sql
CREATE LOGIN app_user WITH PASSWORD = '...';
CREATE USER app_user FOR LOGIN app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO app_user;
-- Optionally deny stored proc execution if app shouldn't call them:
-- DENY EXECUTE ON SCHEMA::dbo TO app_user;
```

**Always Encrypted for sensitive columns:**
```sql
CREATE COLUMN ENCRYPTION KEY CEK1 WITH VALUES (
  COLUMN_MASTER_KEY = CMK1,
  ALGORITHM = 'RSA_OAEP',
  ENCRYPTED_VALUE = 0x...
);
ALTER TABLE Users ALTER COLUMN SSN NVARCHAR(11)
  ENCRYPTED WITH (ENCRYPTION_TYPE = DETERMINISTIC, ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256', COLUMN_ENCRYPTION_KEY = CEK1);
```

**Parameterized queries (prevent SQL injection):**
```csharp
using var cmd = new SqlCommand("SELECT * FROM Users WHERE Email = @email", conn);
cmd.Parameters.AddWithValue("@email", email);
```

**Transparent Data Encryption (TDE) for data at rest:**
```sql
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
  ENCRYPTION BY SERVER CERTIFICATE MyServerCert;
ALTER DATABASE mydb SET ENCRYPTION ON;
```

## Testing

Use **Testcontainers** for integration tests:
```csharp
var container = new MsSqlBuilder()
    .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
    .WithPassword("Strong!Passw0rd")
    .Build();
await container.StartAsync();
```

For CI environments without Docker, use **LocalDB** (`(localdb)\MSSQLLocalDB`) on Windows or SQL Server Linux containers. Run EF Core migrations inside the container before tests. Test with `SNAPSHOT` isolation level if your app uses it.

## Dos
- Use `NVARCHAR` over `VARCHAR` for Unicode support — prevents encoding bugs with international data.
- Enable Query Store in all environments to track query performance regressions across deployments.
- Use `TRY_CONVERT`/`TRY_CAST` instead of `CONVERT`/`CAST` to avoid runtime conversion errors.
- Prefer `MERGE` for upsert operations — atomic and set-based.
- Use `OPTION (RECOMPILE)` for queries with highly variable parameter distributions (parameter sniffing mitigation).
- Set `READ_COMMITTED_SNAPSHOT` isolation to reduce reader-writer blocking without explicit snapshot transactions.
- Monitor wait statistics (`sys.dm_os_wait_stats`) to identify bottlenecks.

## Don'ts
- Don't use `NOLOCK` (read uncommitted) as a blanket performance fix — it returns dirty, phantom, and non-repeatable reads that cause subtle data bugs.
- Don't use `SELECT *` in production queries — it prevents covering index usage and couples code to schema.
- Don't store business logic in triggers — they hide side effects, complicate debugging, and don't compose with ORMs.
- Don't use `sp_` prefix for stored procedures — SQL Server checks the master database first for `sp_` procedures, adding overhead.
- Don't skip index maintenance — fragmented indexes degrade performance; rebuild at > 30% fragmentation, reorganize at 10-30%.
- Don't use `IDENTITY` columns as business-facing IDs — they leak information about row counts and insertion order.
- Don't use `@@IDENTITY` — it returns the last identity from any scope; use `SCOPE_IDENTITY()` or `OUTPUT` clause instead.
