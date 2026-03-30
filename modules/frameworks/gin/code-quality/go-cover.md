# Gin + go-cover

> Extends `modules/code-quality/go-cover.md` with Gin-specific integration.
> Generic go-cover conventions (flags, CI integration, threshold scripts) are NOT repeated here.

## Integration Setup

Run coverage against application packages only — exclude `cmd/` entry points and generated code from the threshold calculation:

```bash
# Makefile
.PHONY: coverage coverage-html

coverage:
	go test ./internal/... ./handler/... ./service/... ./repository/... \
	  -coverprofile=coverage.out \
	  -covermode=atomic \
	  -coverpkg=./internal/...,./handler/...,./service/...,./repository/...

coverage-html: coverage
	go tool cover -html=coverage.out -o coverage.html
```

```yaml
# .github/workflows/test.yml
- name: Run tests with coverage
  run: |
    go test ./... -coverprofile=coverage.out -covermode=atomic \
      -coverpkg=./internal/...,./handler/...,./service/...,./repository/...
    go tool cover -func=coverage.out
```

## Framework-Specific Patterns

### Testing Gin Handlers with httptest

Use `httptest.NewRecorder()` to test handlers without starting a real server. The recorder captures the response for coverage and assertion:

```go
func TestUserHandler_GetByID(t *testing.T) {
    // Set up router with the handler
    router := gin.New()
    h := NewUserHandler(mockService)
    router.GET("/users/:id", h.GetByID)

    // Record the response
    w := httptest.NewRecorder()
    req := httptest.NewRequest(http.MethodGet, "/users/42", nil)
    router.ServeHTTP(w, req)

    assert.Equal(t, http.StatusOK, w.Code)
}
```

This approach covers the handler function, binding logic, and response writing paths directly.

### Covering Middleware

Middleware registered with `router.Use()` is only exercised when a matching route is hit. To cover middleware, test it through a real route — not in isolation:

```go
func TestAuthMiddleware_RejectsUnauthorized(t *testing.T) {
    router := gin.New()
    router.Use(AuthMiddleware("secret"))
    router.GET("/protected", func(c *gin.Context) {
        c.Status(http.StatusOK)
    })

    w := httptest.NewRecorder()
    req := httptest.NewRequest(http.MethodGet, "/protected", nil)
    // No Authorization header
    router.ServeHTTP(w, req)

    assert.Equal(t, http.StatusUnauthorized, w.Code)
}
```

### Excluding Router Wiring from Thresholds

`router/` packages typically contain only route registration code with no branching logic. Exclude them from threshold checks while still including them in the profile:

```bash
# Filter router wiring from threshold calculation
go tool cover -func=coverage.out | grep -v "router/" | \
  grep "^total:" | awk '{gsub(/%/,""); print $3}'
```

### Coverage for Error Paths

Gin error paths (invalid JSON binding, missing path params, unauthorized) must be explicitly tested. Table-driven tests that cover all HTTP error branches are the most efficient approach:

```go
tests := []struct {
    name       string
    body       string
    wantStatus int
}{
    {"valid request", `{"name":"Alice"}`, http.StatusCreated},
    {"invalid JSON", `{bad json}`, http.StatusBadRequest},
    {"missing required field", `{}`, http.StatusUnprocessableEntity},
}
```

## Additional Dos

- Use `-coverpkg` scoped to `handler/...`, `service/...`, `repository/...` — this ensures that handlers calling services are credited in service coverage, not just the handler file.
- Test middleware via routes, not in isolation — middleware coverage only counts when the handler pipeline executes.
- Write table-driven tests for all HTTP error codes a handler can return — these paths are cheap to cover and represent real failure modes.

## Additional Don'ts

- Don't include `cmd/` in coverage thresholds — entry points contain only wiring code and skew the denominator.
- Don't rely on integration tests alone for coverage — handler unit tests with `httptest` run faster and produce more granular coverage data.
- Don't use `-covermode=set` in tests that use `t.Parallel()` with shared state — use `-covermode=atomic` consistently.
