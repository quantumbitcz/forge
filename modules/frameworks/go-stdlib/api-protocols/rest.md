# Go stdlib — REST API

> Go net/http REST patterns (Go 1.22+ ServeMux). Extends generic Go conventions.

## Integration Setup

```go
// Standard library only — no extra dependencies for basic REST
// Optional: oapi-codegen for OpenAPI type-safe handlers
// go install github.com/deepmap/oapi-codegen/v2/cmd/oapi-codegen@latest
require (
    github.com/deepmap/oapi-codegen/v2 v2.2.0  // optional
)
```

## ServeMux with Go 1.22+ Method+Path Routing

```go
mux := http.NewServeMux()

// Go 1.22+: method and path variables built in
mux.HandleFunc("GET /api/v1/users/{id}", getUserHandler(svc))
mux.HandleFunc("POST /api/v1/users", createUserHandler(svc))
mux.HandleFunc("PUT /api/v1/users/{id}", updateUserHandler(svc))
mux.HandleFunc("DELETE /api/v1/users/{id}", deleteUserHandler(svc))
```

## Handler Factory Pattern

```go
func getUserHandler(svc UserService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        id, err := uuid.Parse(r.PathValue("id")) // Go 1.22+
        if err != nil {
            writeError(w, http.StatusBadRequest, "invalid id")
            return
        }

        user, err := svc.GetUser(r.Context(), id)
        if errors.Is(err, ErrNotFound) {
            writeError(w, http.StatusNotFound, "user not found")
            return
        }
        if err != nil {
            writeError(w, http.StatusInternalServerError, "internal error")
            return
        }

        writeJSON(w, http.StatusOK, user)
    }
}
```

## JSON Encode/Decode Helpers

```go
func writeJSON(w http.ResponseWriter, status int, v any) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    if err := json.NewEncoder(w).Encode(v); err != nil {
        slog.Error("encode response", "err", err)
    }
}

func writeError(w http.ResponseWriter, status int, msg string) {
    writeJSON(w, status, map[string]string{"error": msg})
}

func readJSON(r *http.Request, v any) error {
    r.Body = http.MaxBytesReader(nil, r.Body, 1<<20) // 1 MB limit
    dec := json.NewDecoder(r.Body)
    dec.DisallowUnknownFields()
    return dec.Decode(v)
}
```

## Middleware Chaining

```go
type Middleware func(http.Handler) http.Handler

func Chain(h http.Handler, middlewares ...Middleware) http.Handler {
    for i := len(middlewares) - 1; i >= 0; i-- {
        h = middlewares[i](h)
    }
    return h
}

func LoggingMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        slog.Info("request", "method", r.Method, "path", r.URL.Path,
            "duration", time.Since(start))
    })
}

// Wire up
handler := Chain(mux, LoggingMiddleware, AuthMiddleware, RecoveryMiddleware)
```

## OpenAPI with oapi-codegen

```bash
# Generate server stubs from openapi.yaml
oapi-codegen -generate types,server -package api openapi.yaml > internal/api/api.gen.go
```

Implement the generated `StrictServerInterface` — all route signatures are enforced by the compiler.

## Scaffolder Patterns

```yaml
patterns:
  handler: "internal/handler/{resource}_handler.go"
  middleware: "internal/middleware/{name}.go"
  server_setup: "internal/server/server.go"
  routes: "internal/server/routes.go"
  api_gen: "internal/api/api.gen.go"
  openapi_spec: "api/openapi.yaml"
```

## Additional Dos/Don'ts

- DO use `r.PathValue("key")` (Go 1.22+) instead of third-party router packages for simple APIs
- DO wrap `r.Body` with `http.MaxBytesReader` to cap request body size and prevent memory exhaustion
- DO use handler factory functions (closures) to inject service dependencies
- DO set `ReadHeaderTimeout` and `WriteTimeout` on the `http.Server` struct
- DON'T call `w.WriteHeader` and then `w.Header().Set` — headers must be set before `WriteHeader`
- DON'T swallow errors from `json.NewEncoder(w).Encode` — log them even if the response is already started
- DON'T use `http.DefaultServeMux` in production — always create a local `http.NewServeMux()`
