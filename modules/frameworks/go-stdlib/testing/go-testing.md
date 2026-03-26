# Go stdlib + Go Testing Patterns

> Go-specific testing patterns for stdlib-based projects (net/http, chi, echo, etc.).
> Extends `modules/languages/go.md` and `modules/frameworks/go-stdlib/conventions.md`.

## Handler Testing with httptest

Use `httptest.NewRecorder()` and `httptest.NewRequest()` to test handlers without a running server.

```go
func TestUserHandler_GetByID(t *testing.T) {
    t.Parallel()

    tests := []struct {
        name       string
        id         string
        svcReturn  User
        svcErr     error
        wantStatus int
    }{
        {
            name:       "returns user when found",
            id:         "user-1",
            svcReturn:  User{ID: "user-1", Name: "Alice"},
            wantStatus: http.StatusOK,
        },
        {
            name:       "returns 404 when not found",
            id:         "missing",
            svcErr:     ErrNotFound,
            wantStatus: http.StatusNotFound,
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            t.Parallel()

            svc := &mockUserService{
                getByIDFn: func(_ context.Context, id string) (User, error) {
                    return tc.svcReturn, tc.svcErr
                },
            }
            h := NewUserHandler(svc, slog.Default())

            w := httptest.NewRecorder()
            req := httptest.NewRequest(http.MethodGet, "/users/"+tc.id, nil)

            h.GetByID(w, req)

            assert.Equal(t, tc.wantStatus, w.Code)
        })
    }
}
```

## Router-Level Integration Tests

For tests that exercise the full middleware chain:

```go
func newTestServer(t *testing.T, h *UserHandler) *httptest.Server {
    t.Helper()
    mux := http.NewServeMux()
    mux.HandleFunc("GET /users/{id}", h.GetByID)
    mux.HandleFunc("POST /users", h.Create)
    return httptest.NewServer(mux)
}

func TestUserHandler_Create_ValidatesInput(t *testing.T) {
    svc := &mockUserService{}
    h := NewUserHandler(svc, slog.Default())
    srv := newTestServer(t, h)
    defer srv.Close()

    body := `{"name": "", "email": "not-an-email"}`
    resp, err := http.Post(srv.URL+"/users", "application/json", strings.NewReader(body))
    require.NoError(t, err)
    defer resp.Body.Close()

    assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
}
```

## Middleware Testing in Isolation

```go
func TestAuthMiddleware_RejectsInvalidToken(t *testing.T) {
    inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
    })
    handler := AuthMiddleware("secret")(inner)

    w := httptest.NewRecorder()
    req := httptest.NewRequest(http.MethodGet, "/protected", nil)
    req.Header.Set("Authorization", "invalid-token")

    handler.ServeHTTP(w, req)

    assert.Equal(t, http.StatusUnauthorized, w.Code)
}
```

## Service Testing (Unit)

Services are plain Go — no HTTP dependency. Test with mock repositories.

```go
type mockUserRepository struct {
    createFn   func(ctx context.Context, u User) (User, error)
    findByIDFn func(ctx context.Context, id string) (User, error)
}

func (m *mockUserRepository) Create(ctx context.Context, u User) (User, error) {
    if m.createFn != nil {
        return m.createFn(ctx, u)
    }
    return User{}, nil
}

func TestUserService_Create_RejectsEmptyName(t *testing.T) {
    svc := NewUserService(&mockUserRepository{})
    _, err := svc.Create(context.Background(), "", "alice@example.com")
    require.Error(t, err)
    assert.ErrorIs(t, err, ErrValidation)
}
```

## testify Assertions

Use `github.com/stretchr/testify/assert` and `testify/require`:

```go
import (
    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

// require stops the test on failure (use for preconditions)
require.NoError(t, err)
require.Equal(t, http.StatusOK, w.Code)

// assert continues the test (use for result checks)
assert.Equal(t, "Alice", user.Name)
assert.Empty(t, errors)
```

## Test Database with Testcontainers

For repository tests, use `github.com/testcontainers/testcontainers-go` to spin up a real database:

```go
func setupTestDB(t *testing.T) *sql.DB {
    t.Helper()
    ctx := context.Background()

    container, err := postgres.Run(ctx,
        "postgres:16-alpine",
        postgres.WithDatabase("testdb"),
        postgres.WithUsername("test"),
        postgres.WithPassword("test"),
        testcontainers.WithWaitStrategy(
            wait.ForLog("database system is ready to accept connections"),
        ),
    )
    require.NoError(t, err)
    t.Cleanup(func() { _ = container.Terminate(ctx) })

    dsn, err := container.ConnectionString(ctx, "sslmode=disable")
    require.NoError(t, err)

    db, err := sql.Open("pgx", dsn)
    require.NoError(t, err)

    runMigrations(t, db)
    return db
}
```

## What to Test

- Handler status codes and response shapes for all success/error paths
- Input validation: missing fields, invalid types, boundary values
- Middleware acceptance/rejection logic
- Service business rules (unit tests with mocked repositories)
- Repository queries (integration tests with Testcontainers)
- Error propagation from service to handler to HTTP response

## What NOT to Test

- That `net/http` routing works (stdlib behavior)
- That `encoding/json` marshals correctly (stdlib behavior)
- Internal struct fields or private methods
- Implementation details that can change without changing behavior
