# GORM Best Practices

## Overview
GORM is the most widely used ORM for Go applications. Use it for projects that benefit from auto-migration, model-driven code, and a fluent query API. For high-performance bulk operations or complex analytical queries, prefer raw `database/sql` or `sqlx` — GORM's reflection overhead becomes measurable at scale.

## Architecture Patterns

### Model definition
```go
// Use struct tags for schema control; embed gorm.Model for audit fields
type User struct {
    gorm.Model                      // adds ID, CreatedAt, UpdatedAt, DeletedAt (soft delete)
    Email    string `gorm:"uniqueIndex;not null;size:256"`
    Name     string `gorm:"not null;size:128"`
    IsActive bool   `gorm:"default:true"`
}

// Custom primary key (UUID)
type Product struct {
    ID          uuid.UUID `gorm:"type:uuid;primaryKey"`
    Name        string    `gorm:"not null"`
    TenantID    uuid.UUID `gorm:"type:uuid;index"`
    DeletedAt   gorm.DeletedAt `gorm:"index"` // soft delete support
}
```

### Repository pattern with interface
```go
type UserRepository interface {
    FindByID(ctx context.Context, id uint) (*User, error)
    FindAll(ctx context.Context) ([]User, error)
    Create(ctx context.Context, user *User) error
    Update(ctx context.Context, user *User) error
    Delete(ctx context.Context, id uint) error
}

type gormUserRepository struct {
    db *gorm.DB
}

func (r *gormUserRepository) FindByID(ctx context.Context, id uint) (*User, error) {
    var user User
    result := r.db.WithContext(ctx).First(&user, id)
    if errors.Is(result.Error, gorm.ErrRecordNotFound) {
        return nil, nil
    }
    return &user, result.Error
}

func (r *gormUserRepository) Create(ctx context.Context, user *User) error {
    return r.db.WithContext(ctx).Create(user).Error
}
```

### Scopes for reusable query logic
```go
func ActiveUsers(db *gorm.DB) *gorm.DB {
    return db.Where("is_active = ?", true)
}

func TenantScoped(tenantID uuid.UUID) func(*gorm.DB) *gorm.DB {
    return func(db *gorm.DB) *gorm.DB {
        return db.Where("tenant_id = ?", tenantID)
    }
}

// Usage
db.Scopes(ActiveUsers, TenantScoped(tid)).Find(&users)
```

### Hooks for lifecycle events
```go
func (u *User) BeforeCreate(tx *gorm.DB) error {
    if u.ID == uuid.Nil {
        u.ID = uuid.New()
    }
    return nil
}

func (u *User) AfterCreate(tx *gorm.DB) error {
    // e.g., emit domain event
    return nil
}
```

## Configuration

```go
// Database initialization with connection pool settings
func NewDB(cfg Config) (*gorm.DB, error) {
    dsn := fmt.Sprintf(
        "host=%s user=%s password=%s dbname=%s port=%d sslmode=require TimeZone=UTC",
        cfg.Host, cfg.User, cfg.Password, cfg.DBName, cfg.Port,
    )
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
        Logger:                 logger.Default.LogMode(logger.Warn),
        PrepareStmt:            true,  // cache prepared statements
        SkipDefaultTransaction: true,  // skip implicit transactions for single operations
        NamingConvention:       schema.NamingStrategy{SingularTable: false},
    })
    if err != nil {
        return nil, err
    }

    sqlDB, _ := db.DB()
    sqlDB.SetMaxOpenConns(10)
    sqlDB.SetMaxIdleConns(5)
    sqlDB.SetConnMaxLifetime(5 * time.Minute)
    return db, nil
}
```

## Performance

- Set `SkipDefaultTransaction: true` to skip implicit transactions on single-row reads/writes.
- Set `PrepareStmt: true` to cache prepared statements across calls.
- Use `Select("id, email")` to avoid `SELECT *` on wide tables.
- Use `CreateInBatches` for bulk inserts; never loop `Create` calls.
- Use `Preload` for associations to avoid N+1 queries; avoid `Joins` for one-to-many.

```go
// Batch insert
db.CreateInBatches(users, 100)

// Avoid N+1: preload associations
db.Preload("Orders").Find(&users)

// Targeted update — only update changed columns
db.Model(&user).Select("email", "updated_at").Updates(User{Email: newEmail})

// Raw SQL for complex queries
var result []SummaryRow
db.Raw("SELECT date_trunc('day', created_at) AS day, COUNT(*) FROM orders GROUP BY 1").Scan(&result)
```

## Security

- Never pass user input directly into raw SQL strings — use parameterized `?` placeholders with GORM's argument binding.
- Use scopes for row-level tenant isolation rather than per-query `.Where` calls that can be accidentally omitted.
- Soft delete (`gorm.DeletedAt`) does not hard-delete — ensure periodic purge jobs for GDPR compliance.
- Store DSN credentials in environment variables; never in source code or config files committed to VCS.

```go
// Safe: parameterized
db.Where("email = ?", email).First(&user)

// UNSAFE: SQL injection risk
db.Where("email = '" + email + "'").First(&user)
```

## Testing

```go
func setupTestDB(t *testing.T) *gorm.DB {
    t.Helper()
    ctx := context.Background()
    container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
        ContainerRequest: testcontainers.ContainerRequest{
            Image:        "postgres:16-alpine",
            ExposedPorts: []string{"5432/tcp"},
            Env: map[string]string{
                "POSTGRES_PASSWORD": "test",
                "POSTGRES_DB":       "testdb",
            },
            WaitingFor: wait.ForListeningPort("5432/tcp"),
        },
        Started: true,
    })
    require.NoError(t, err)
    t.Cleanup(func() { container.Terminate(ctx) })

    host, _ := container.Host(ctx)
    port, _ := container.MappedPort(ctx, "5432")
    dsn := fmt.Sprintf("host=%s port=%s user=postgres password=test dbname=testdb sslmode=disable", host, port.Port())
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
    require.NoError(t, err)
    require.NoError(t, db.AutoMigrate(&User{}))
    return db
}

func TestCreateUser(t *testing.T) {
    db := setupTestDB(t)
    repo := NewGormUserRepository(db)
    user := &User{Email: "test@example.com", Name: "Test"}
    require.NoError(t, repo.Create(context.Background(), user))
    found, err := repo.FindByID(context.Background(), user.ID)
    require.NoError(t, err)
    assert.Equal(t, "test@example.com", found.Email)
}
```

## Dos
- Always pass `context.Context` via `.WithContext(ctx)` for query cancellation and timeout propagation.
- Use `CreateInBatches` for bulk inserts to reduce round-trips.
- Use `Select(fields...)` and projection structs for read-heavy paths to avoid loading unused columns.
- Use scopes to encapsulate reusable filter logic and prevent multi-tenancy bugs.
- Embed `gorm.Model` for standard audit fields; use custom `BeforeCreate` hooks to set UUIDs.

## Don'ts
- Don't use `AutoMigrate` in production — use Flyway, Liquibase, or `golang-migrate` instead.
- Don't use raw SQL string concatenation in `db.Raw()` or `db.Exec()` with user input.
- Don't call `db.Save()` on a partially-loaded struct — it updates all columns and can overwrite fields.
- Don't use `db.First()` without handling `gorm.ErrRecordNotFound` explicitly.
- Don't access GORM outside a transaction when multiple related writes must be atomic.
- Don't rely on GORM's implicit transaction for multi-step operations; use `db.Transaction()` explicitly.
