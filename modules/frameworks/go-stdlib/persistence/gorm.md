# Go stdlib + GORM

> GORM patterns for Go stdlib projects. Extends generic Go conventions.
> Raw `database/sql` patterns are in `databases/postgresql.md`.

## Integration Setup

```go
// go.mod
require (
    gorm.io/gorm v1.25.0
    gorm.io/driver/postgres v1.5.0
)
```

```go
import (
    "gorm.io/driver/postgres"
    "gorm.io/gorm"
    "gorm.io/gorm/logger"
)
```

## Initialization

```go
func NewDB(dsn string) (*gorm.DB, error) {
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{
        Logger: logger.Default.LogMode(logger.Warn), // Silent in prod, Info in dev
        PrepareStmt: true,                           // Cache prepared statements
        TranslateError: true,                        // Map DB errors to gorm.ErrRecordNotFound etc.
    })
    if err != nil {
        return nil, fmt.Errorf("open db: %w", err)
    }

    sqlDB, _ := db.DB()
    sqlDB.SetMaxOpenConns(20)
    sqlDB.SetMaxIdleConns(5)
    sqlDB.SetConnMaxLifetime(30 * time.Minute)
    return db, nil
}
```

## AutoMigrate

```go
// Call once at startup — safe for additions, not for destructive changes
func Migrate(db *gorm.DB) error {
    return db.AutoMigrate(
        &User{},
        &Order{},
    )
}
```

Use `AutoMigrate` only in development or controlled environments. Prefer goose/migrate in production (see `migrations/goose.md`).

## Model Conventions

```go
type User struct {
    gorm.Model                          // embeds ID, CreatedAt, UpdatedAt, DeletedAt (soft-delete)
    Name  string `gorm:"not null"`
    Email string `gorm:"uniqueIndex;not null"`
}

// Custom primary key (no soft-delete)
type Product struct {
    ID        uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
    Name      string
    CreatedAt time.Time
}
```

## Repository Pattern

```go
type UserRepository interface {
    GetByID(ctx context.Context, id uuid.UUID) (*User, error)
    Create(ctx context.Context, user *User) error
    Update(ctx context.Context, user *User) error
}

type gormUserRepository struct {
    db *gorm.DB
}

func (r *gormUserRepository) GetByID(ctx context.Context, id uuid.UUID) (*User, error) {
    var u User
    result := r.db.WithContext(ctx).First(&u, "id = ?", id)
    if errors.Is(result.Error, gorm.ErrRecordNotFound) {
        return nil, ErrNotFound
    }
    return &u, result.Error
}

func (r *gormUserRepository) Create(ctx context.Context, user *User) error {
    return r.db.WithContext(ctx).Create(user).Error
}
```

## Scaffolder Patterns

```yaml
patterns:
  db_setup: "internal/db/gorm.go"
  migrate: "internal/db/migrate.go"
  model: "internal/model/{entity}.go"
  repository_iface: "internal/repository/{entity}_repository.go"
  repository_impl: "internal/repository/gorm_{entity}_repository.go"
```

## Additional Dos/Don'ts

- DO always call `.WithContext(ctx)` before every query to propagate deadlines and cancellation
- DO define repository interfaces so tests can swap in a fake implementation
- DO use `TranslateError: true` and check with `errors.Is(err, gorm.ErrRecordNotFound)` for not-found cases
- DO enable `PrepareStmt: true` to cache prepared statements and reduce parse overhead
- DON'T use `AutoMigrate` in production deployments — use versioned SQL migrations instead
- DON'T embed `*gorm.DB` directly into handler or service structs — always wrap behind an interface
- DON'T use `db.Raw` for queries that can be expressed with GORM's chainable API; reserve Raw for complex CTEs
