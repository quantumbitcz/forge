# Testing Patterns (Go)

## table-driven-tests

**Instead of:**
```go
func TestAdd(t *testing.T) {
    if Add(1, 2) != 3 { t.Fatal("1+2") }
    if Add(0, 0) != 0 { t.Fatal("0+0") }
    if Add(-1, 1) != 0 { t.Fatal("-1+1") }
}
```

**Do this:**
```go
func TestAdd(t *testing.T) {
    tests := []struct{ a, b, want int }{
        {1, 2, 3},
        {0, 0, 0},
        {-1, 1, 0},
    }
    for _, tt := range tests {
        got := Add(tt.a, tt.b)
        if got != tt.want {
            t.Errorf("Add(%d,%d) = %d, want %d", tt.a, tt.b, got, tt.want)
        }
    }
}
```

**Why:** Table-driven tests eliminate duplication, make adding cases trivial, and produce clear failure messages.

## test-helpers

**Instead of:**
```go
func TestHandler(t *testing.T) {
    db, err := sql.Open("postgres", os.Getenv("DB_URL"))
    if err != nil { t.Fatal(err) }
    defer db.Close()
    // ... repeat in every test
}
```

**Do this:**
```go
func newTestDB(t *testing.T) *sql.DB {
    t.Helper()
    db, err := sql.Open("postgres", os.Getenv("DB_URL"))
    if err != nil { t.Fatal(err) }
    t.Cleanup(func() { db.Close() })
    return db
}
```

**Why:** `t.Helper()` attributes failures to the caller and `t.Cleanup` guarantees teardown, reducing boilerplate across tests.

## httptest

**Instead of:**
```go
func TestAPI(t *testing.T) {
    go http.ListenAndServe(":9999", handler)
    time.Sleep(100 * time.Millisecond)
    resp, _ := http.Get("http://localhost:9999/health")
    // ...
}
```

**Do this:**
```go
func TestAPI(t *testing.T) {
    srv := httptest.NewServer(handler)
    defer srv.Close()
    resp, err := http.Get(srv.URL + "/health")
    if err != nil { t.Fatal(err) }
    defer resp.Body.Close()
    // ...
}
```

**Why:** `httptest.NewServer` picks a free port, avoids collisions, and cleans up automatically on close.

## subtests

**Instead of:**
```go
func TestUser(t *testing.T) {
    // create test ...
    // update test ...
    // delete test ... (skipped if update panics)
}
```

**Do this:**
```go
func TestUser(t *testing.T) {
    t.Run("Create", func(t *testing.T) {
        // ...
    })
    t.Run("Update", func(t *testing.T) {
        // ...
    })
    t.Run("Delete", func(t *testing.T) {
        // ...
    })
}
```

**Why:** Subtests run independently, can be filtered with `-run`, and report failures with clear hierarchical names.
