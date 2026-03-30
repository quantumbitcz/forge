# Gin + golangci-lint

> Extends `modules/code-quality/golangci-lint.md` with Gin-specific integration.
> Generic golangci-lint conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Enable Gin-aware linters alongside the standard bug/security set. Scope analysis to application packages and exclude generated code:

```yaml
# .golangci.yml
version: "2"

linters:
  default: none
  enable:
    - errcheck
    - govet
    - staticcheck
    - gosec
    - revive
    - goimports
    - gocognit
    - unused
    - bodyclose      # flag unclosed HTTP response bodies in handler tests
    - contextcheck   # ensure gin.Context is propagated correctly
    - noctx          # flag http calls without context

linters-settings:
  gocognit:
    min-complexity: 12    # lower threshold — Gin handlers should stay thin
  goimports:
    local-prefixes: "github.com/yourorg/yourapp"
  revive:
    rules:
      - name: exported
      - name: unused-parameter
      - name: var-naming

issues:
  exclude-rules:
    - path: "_test\\.go"
      linters: [errcheck, gosec]
    - path: "mock_.*\\.go"
      linters: [all]
    - path: ".*\\.pb\\.go"
      linters: [all]
```

## Framework-Specific Patterns

### Handler Complexity

Gin handlers that inline binding, business logic, and response writing trigger `gocognit`. Keep handlers thin by delegating to services:

```go
// Bad — handler does too much, triggers gocognit
func (h *Handler) CreateOrder(c *gin.Context) {
    var req CreateOrderRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    // ... 30 lines of business logic ...
}

// Good — handler delegates, stays under complexity threshold
func (h *Handler) CreateOrder(c *gin.Context) {
    var req CreateOrderRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    order, err := h.orderService.Create(c.Request.Context(), req)
    if err != nil {
        h.handleError(c, err)
        return
    }
    c.JSON(http.StatusCreated, order)
}
```

### bodyclose for Handler Tests

`bodyclose` catches unclosed response bodies in test code that uses `httptest.NewRecorder()` and real HTTP clients. Enable it — tests that call external services via `http.Client` must close bodies:

```go
resp, err := http.Get(url) //nolint:noctx -- test helper, context not needed
if err != nil { ... }
defer resp.Body.Close() // required — bodyclose will flag missing defer
```

### contextcheck and gin.Context Propagation

`contextcheck` verifies that `context.Context` is passed down call chains. In Gin, always pass `c.Request.Context()` to service calls rather than `context.Background()`:

```go
// Bad — contextcheck flags this
result, err := h.service.DoWork(context.Background(), id)

// Good
result, err := h.service.DoWork(c.Request.Context(), id)
```

### Suppress revive unused-parameter for Gin Signatures

Middleware and handler functions must match Gin's `gin.HandlerFunc` signature even when some parameters go unused. Suppress per function:

```go
func noopMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) { //nolint:revive -- required Gin signature
        c.Next()
    }
}
```

## Additional Dos

- Enable `bodyclose` — unclosed response bodies in handler integration tests cause goroutine leaks that are invisible until load testing.
- Set `gocognit.min-complexity: 12` for Gin projects — standard handlers should be simple; higher complexity signals business logic leaking into the handler layer.
- Exclude `router/` package from `unused` if route registration functions are only called from `main` — the linter may flag them as unused in package-scope analysis.

## Additional Don'ts

- Don't disable `contextcheck` globally — passing `context.Background()` in handlers breaks request cancellation and timeout propagation.
- Don't suppress `errcheck` on `c.ShouldBindJSON` and `c.ShouldBindQuery` return values — unhandled binding errors silently use zero values.
- Don't set `new-from-rev: HEAD~1` permanently in Gin service repos — the optimization hides pre-existing handler complexity issues from new contributors.
