# Go Stdlib + Go Variant

> Go-specific patterns for stdlib-based projects. Extends `modules/languages/go.md` and `modules/frameworks/go-stdlib/conventions.md`.

## HTTP Handler Patterns (Go 1.22+)

- Use enhanced `http.ServeMux` with method-based routing: `mux.Handle("GET /users/{id}", ...)`
- Use `http.Request.PathValue("id")` for extracting path parameters
- Use `json.NewDecoder(r.Body).Decode(&input)` for request parsing
- Use `http.Error(w, msg, status)` for simple error responses

## Structured JSON Responses

```go
func writeJSON(w http.ResponseWriter, status int, data any) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    json.NewEncoder(w).Encode(data)
}
```

## Middleware Pattern (stdlib)

```go
func loggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        slog.Info("request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
    })
}
```

## Structured Logging (slog)

- Use `slog` (Go 1.21+) for structured logging
- Create logger with `slog.NewJSONHandler` for production
- Pass logger via context or struct field -- never use package-level logger

## Database Patterns

- Use `database/sql` with `pgx` driver for PostgreSQL
- Transactions via `db.BeginTx(ctx, nil)`
- Use `sqlx` for scan-to-struct convenience
- Connection pool: set `MaxOpenConns`, `MaxIdleConns`, `ConnMaxLifetime`
