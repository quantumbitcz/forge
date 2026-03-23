# Go stdlib Testing Conventions

## Test Structure

Tests live in the same package as the code under test (`_test.go` suffix). Use `package foo` (white-box) or `package foo_test` (black-box) — prefer black-box for exported APIs. One `_test.go` file per source file is the common convention; split only when the file grows large.

```go
func TestUserService_Create(t *testing.T) {
    t.Parallel()
    // ...
}
```

## Naming

- Function: `Test{Subject}_{Method}` or `Test{Subject}_{Scenario}`
- Subtest name (in `t.Run`): plain English description — `"returns error when email is blank"`
- Benchmark: `Benchmark{Subject}_{Method}`

## Table-Driven Tests

The idiomatic Go pattern — group all cases, then range over them:

```go
tests := []struct {
    name  string
    input string
    want  int
    err   bool
}{
    {"valid input",   "hello", 5,  false},
    {"empty string",  "",      0,  true},
}

for _, tc := range tests {
    t.Run(tc.name, func(t *testing.T) {
        t.Parallel()
        got, err := Parse(tc.input)
        if tc.err {
            require.Error(t, err)
            return
        }
        require.NoError(t, err)
        assert.Equal(t, tc.want, got)
    })
}
```

## Assertions

Use `testify/assert` and `testify/require`:

```go
assert.Equal(t, expected, actual)       // non-fatal — test continues
assert.Contains(t, slice, item)
assert.NoError(t, err)
require.NoError(t, err)                 // fatal — stops test immediately
require.NotNil(t, obj)
```

Use `require` when subsequent assertions would panic on nil/error.

## HTTP Testing

```go
// Handler unit test
rec := httptest.NewRecorder()
req := httptest.NewRequest(http.MethodGet, "/users/1", nil)
handler.ServeHTTP(rec, req)
assert.Equal(t, http.StatusOK, rec.Code)

// Integration test
srv := httptest.NewServer(router)
defer srv.Close()
resp, err := http.Get(srv.URL + "/users/1")
```

## Mocking

No built-in mock library. Options:
- **Interface stubs** — implement the interface manually for simple cases
- **`testify/mock`** — for complex expectations and call verification
- **`gomock`** — for strict call-order verification

Prefer interface stubs for readability; reach for `testify/mock` only when call assertions matter.

## Benchmarks

```go
func BenchmarkParse(b *testing.B) {
    for i := 0; i < b.N; i++ {
        Parse("input")
    }
}
```

Use `b.ResetTimer()` after expensive setup. Run with `go test -bench=. -benchmem`.

## Parallel Tests

Call `t.Parallel()` at the top of every test and subtest that has no shared mutable state. This is the default for new tests — opt out only when isolation requires it.

## What NOT to Test

- Exported constants and enum values with no logic
- `String()` methods on simple enums — trust the implementation
- Third-party HTTP client retry logic
- OS-level file operations (use `io/fs` abstractions and inject them)

## Anti-Patterns

- `time.Sleep()` in tests — use channels or `require.Eventually`
- Global state mutation without `t.Cleanup` restoration
- Skipping `t.Parallel()` by default without a documented reason
- Using `log.Fatal` or `os.Exit` in test helpers — use `t.Fatal`
- Test helper functions that don't accept `t *testing.T` as first arg
