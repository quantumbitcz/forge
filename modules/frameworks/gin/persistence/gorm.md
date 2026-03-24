# Gin + GORM

> Gin-specific patterns for GORM. Extends generic Gin conventions.
> Generic Gin patterns (routing, middleware, error handling) are NOT repeated here.

## Integration Setup

`go.mod`:
```go
require (
    gorm.io/gorm v1.25.12
    gorm.io/driver/postgres v1.5.9
)
```

## DB Initialization

```go
// internal/db/db.go
package db

import (
    "gorm.io/driver/postgres"
    "gorm.io/gorm"
    "gorm.io/gorm/logger"
)

func New(dsn string) (*gorm.DB, error) {
    return gorm.Open(postgres.Open(dsn), &gorm.Config{
        Logger: logger.Default.LogMode(logger.Info),
        PrepareStmt: true,   // cache prepared statements
    })
}
```

## DB Middleware

Attach the `*gorm.DB` instance to the Gin context:

```go
// internal/middleware/db.go
func Database(db *gorm.DB) gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Set("db", db)
        c.Next()
    }
}

func GetDB(c *gin.Context) *gorm.DB {
    return c.MustGet("db").(*gorm.DB)
}
```

## Model Definition

```go
// internal/model/user.go
type User struct {
    gorm.Model                       // embeds ID, CreatedAt, UpdatedAt, DeletedAt (soft delete)
    Name  string `gorm:"not null"`
    Email string `gorm:"uniqueIndex;not null"`
}
```

## AutoMigrate

```go
// Run at startup — safe for development; use proper migrations in production
if err := db.AutoMigrate(&User{}, &Order{}); err != nil {
    log.Fatalf("AutoMigrate failed: %v", err)
}
```

Do NOT use AutoMigrate in production — it will not drop columns or indexes.

## Preloading (avoid N+1)

```go
// Bad — N+1
var orders []Order
db.Find(&orders)
for _, o := range orders { db.First(&o.User) } // N queries

// Good — eager load
db.Preload("User").Find(&orders)

// Preload with condition
db.Preload("Orders", "status = ?", "active").Find(&users)
```

## Scopes

```go
func ActiveUsers(db *gorm.DB) *gorm.DB {
    return db.Where("status = ?", "active")
}

func PaginatedScope(page, pageSize int) func(*gorm.DB) *gorm.DB {
    return func(db *gorm.DB) *gorm.DB {
        offset := (page - 1) * pageSize
        return db.Offset(offset).Limit(pageSize)
    }
}

// Usage in handler
db.Scopes(ActiveUsers, PaginatedScope(page, 20)).Find(&users)
```

## Soft Delete

`gorm.Model` includes `DeletedAt gorm.DeletedAt` — records are soft-deleted by default. To hard-delete:

```go
db.Unscoped().Delete(&user)
```

To query soft-deleted records:
```go
db.Unscoped().Where("deleted_at IS NOT NULL").Find(&users)
```

## Repository Pattern

```go
type UserRepository struct{ db *gorm.DB }

func (r *UserRepository) FindByEmail(email string) (*User, error) {
    var u User
    if err := r.db.Where("email = ?", email).First(&u).Error; err != nil {
        if errors.Is(err, gorm.ErrRecordNotFound) {
            return nil, ErrNotFound
        }
        return nil, err
    }
    return &u, nil
}
```

## Scaffolder Patterns

```yaml
patterns:
  db_init: "internal/db/db.go"
  db_middleware: "internal/middleware/db.go"
  model: "internal/model/{entity}.go"
  repository: "internal/repository/{entity}_repository.go"
```

## Additional Dos/Don'ts

- DO use `errors.Is(err, gorm.ErrRecordNotFound)` — do not string-match error messages
- DO use `Preload` for associations — never load them in loops
- DO use `gorm.Model` for standard CRUD models (provides soft delete automatically)
- DON'T use `AutoMigrate` in production — use a migration tool (goose, atlas, or raw SQL)
- DON'T use `db.Raw()` with string concatenation — always use parameterized `?` placeholders
- DON'T use `gorm:"->:false;<-:create"` tags without understanding their effect on updates
