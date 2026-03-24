# Gin + Redis (go-redis)

> Gin-specific Redis patterns using `go-redis/redis`.
> Generic Redis patterns are in `modules/frameworks/go-stdlib/caching/redis.md`.

## Integration Setup

```go
// go.mod
require (
    github.com/gin-gonic/gin v1.10.0
    github.com/redis/go-redis/v9 v9.5.0
)
```

## Redis Client as Gin Middleware

```go
func RedisMiddleware(rdb *redis.Client) gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Set("redis", rdb)
        c.Next()
    }
}
```

## Cache Middleware for GET Endpoints

```go
func HTTPCacheMiddleware(rdb *redis.Client, ttl time.Duration) gin.HandlerFunc {
    return func(c *gin.Context) {
        if c.Request.Method != http.MethodGet {
            c.Next()
            return
        }

        cacheKey := "http:" + c.Request.URL.RequestURI()
        cached, err := rdb.Get(c.Request.Context(), cacheKey).Bytes()
        if err == nil {
            c.Data(http.StatusOK, "application/json; charset=utf-8", cached)
            c.Abort()
            return
        }

        // Capture response body via a response writer wrapper
        blw := &bodyLogWriter{body: bytes.NewBufferString(""), ResponseWriter: c.Writer}
        c.Writer = blw
        c.Next()

        if c.Writer.Status() == http.StatusOK {
            _ = rdb.Set(c.Request.Context(), cacheKey, blw.body.Bytes(), ttl).Err()
        }
    }
}

type bodyLogWriter struct {
    gin.ResponseWriter
    body *bytes.Buffer
}

func (w bodyLogWriter) Write(b []byte) (int, error) {
    w.body.Write(b)
    return w.ResponseWriter.Write(b)
}
```

## Cache-Aside in Handler

```go
func GetProductHandler(rdb *redis.Client, repo ProductRepository) gin.HandlerFunc {
    return func(c *gin.Context) {
        id := c.Param("id")
        cacheKey := "product:" + id
        ctx := c.Request.Context()

        if cached, err := rdb.Get(ctx, cacheKey).Bytes(); err == nil {
            c.Data(http.StatusOK, "application/json", cached)
            return
        }

        product, err := repo.GetByID(ctx, id)
        if errors.Is(err, ErrNotFound) {
            c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
            return
        }
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
            return
        }

        data, _ := json.Marshal(product)
        _ = rdb.Set(ctx, cacheKey, data, 5*time.Minute).Err()
        c.Data(http.StatusOK, "application/json", data)
    }
}
```

## Scaffolder Patterns

```yaml
patterns:
  redis_setup: "internal/cache/redis.go"
  cache_middleware: "internal/middleware/cache.go"
  cache_service: "internal/cache/{entity}_cache.go"
```

## Additional Dos/Don'ts

- DO prefer closure injection of `*redis.Client` over retrieving it from `c.MustGet` — type-safe and testable
- DO scope the HTTP cache middleware to specific route groups only — not the entire router
- DO use `c.Request.Context()` for all Redis calls inside Gin handlers
- DO invalidate cache keys explicitly on mutation (PUT/PATCH/DELETE handlers)
- DON'T cache responses that contain user-specific data on a shared key — include the user ID in the cache key
- DON'T apply the response-body capture middleware to large file/stream endpoints
