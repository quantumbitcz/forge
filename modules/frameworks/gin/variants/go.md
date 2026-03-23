# Gin + Go Variant

> Go-specific patterns for Gin projects. Extends `modules/languages/go.md` and `modules/frameworks/gin/conventions.md`.

## gin.Context vs stdlib http.Request

Gin's `*gin.Context` wraps `*http.Request` and `http.ResponseWriter` with convenience methods. Key differences:

| Task | stdlib | Gin |
|------|--------|-----|
| Read JSON body | `json.NewDecoder(r.Body).Decode(&v)` | `c.ShouldBindJSON(&v)` |
| Read path param | `r.PathValue("id")` (Go 1.22+) | `c.Param("id")` |
| Read query param | `r.URL.Query().Get("q")` | `c.Query("q")` |
| Set response header | `w.Header().Set(k, v)` | `c.Header(k, v)` |
| Write JSON response | `json.NewEncoder(w).Encode(v)` | `c.JSON(status, v)` |
| Abort chain | N/A | `c.Abort()` / `c.AbortWithStatusJSON(...)` |
| Store request-scoped data | Context values | `c.Set(key, value)` / `c.Get(key)` |

Always prefer `c.Request.Context()` for propagating the request context to service calls — do not create a new `context.Background()` in handlers.

## Middleware vs HandlerFunc

```go
// Middleware (wraps the chain)
func RequestIDMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        id := uuid.New().String()
        c.Set("requestID", id)
        c.Header("X-Request-ID", id)
        c.Next()  // continue chain
    }
}

// Terminal handler (no c.Next() needed)
func (h *UserHandler) GetByID(c *gin.Context) {
    id := c.Param("id")
    // ... no c.Next()
}
```

- Middleware always calls `c.Next()` to continue (or `c.Abort()` to stop)
- Terminal handlers do not call `c.Next()` — they write the response and return

## Structured Error Responses

```go
type ErrorResponse struct {
    Error   string            `json:"error"`
    Details map[string]string `json:"details,omitempty"`
}

func respondError(c *gin.Context, status int, msg string) {
    c.JSON(status, ErrorResponse{Error: msg})
}

func respondValidationError(c *gin.Context, err error) {
    var ve validator.ValidationErrors
    if errors.As(err, &ve) {
        details := make(map[string]string, len(ve))
        for _, fe := range ve {
            details[fe.Field()] = fe.Tag()
        }
        c.JSON(http.StatusBadRequest, ErrorResponse{Error: "validation failed", Details: details})
        return
    }
    respondError(c, http.StatusBadRequest, err.Error())
}
```

## Typed Response Structs

Define typed response structs, not `gin.H{}` maps, for all non-trivial responses:

```go
type UserResponse struct {
    ID        string `json:"id"`
    Name      string `json:"name"`
    Email     string `json:"email"`
    CreatedAt string `json:"created_at"`
}

type ListUsersResponse struct {
    Users  []UserResponse `json:"users"`
    Total  int            `json:"total"`
    Cursor string         `json:"cursor,omitempty"`
}
```

## Service Interface Pattern

```go
// Defined in the handler package (consumer side)
type UserService interface {
    Create(ctx context.Context, name, email string) (User, error)
    GetByID(ctx context.Context, id string) (User, error)
    List(ctx context.Context, cursor string, limit int) ([]User, string, error)
}

type UserHandler struct {
    svc    UserService
    logger *slog.Logger
}

func NewUserHandler(svc UserService, logger *slog.Logger) *UserHandler {
    return &UserHandler{svc: svc, logger: logger}
}
```

## Graceful Shutdown

```go
srv := &http.Server{Addr: addr, Handler: router}

go func() {
    if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
        slog.Error("server error", "err", err)
        os.Exit(1)
    }
}()

quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
<-quit

ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()
if err := srv.Shutdown(ctx); err != nil {
    slog.Error("forced shutdown", "err", err)
}
```
