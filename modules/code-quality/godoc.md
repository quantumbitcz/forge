# godoc

## Overview

Go documentation is built into the toolchain — `go doc` reads package-level and symbol-level comments and renders them in the terminal. The `pkg.go.dev` website automatically indexes public Go modules from VCS. No configuration file or extra tooling is required: correctly formatted comments adjacent to exported declarations produce complete documentation. Example functions (`func ExampleFoo()`) are compiled, run, and verified as part of `go test`, and they appear verbatim in the generated docs.

## Architecture Patterns

### Installation & Setup

```bash
# Built-in — ships with the Go toolchain
go doc fmt.Println          # View symbol doc in terminal
go doc -all ./...           # View all docs for the current module

# Local doc server (mirrors pkg.go.dev locally)
go install golang.org/x/tools/cmd/godoc@latest
godoc -http=:6060
# Then open http://localhost:6060/pkg/your/module/path/
```

No configuration file required. Documentation is entirely comment-driven.

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing package comment | Package without `// Package name ...` or `/* Package ... */` | WARNING |
| Missing exported symbol doc | Exported func/type/var without preceding comment | WARNING |
| Comment not starting with symbol name | `// DoSomething` → comment not prefixed with `DoSomething` | INFO |
| Stuttering package prefix | `// Package foo defines a foo.Foo` repeated unnecessarily | INFO |
| Example function compilation failure | `func ExampleFoo()` that fails `go test` | CRITICAL |

### Configuration Patterns

**Package comment (required on every package):**
```go
// Package httputil provides HTTP utility functions for parsing and
// building HTTP requests and responses.
//
// # HTTP Client Helpers
//
// Use [NewRetryClient] for requests that should be retried on transient errors.
// Use [ParseJSONResponse] to decode a typed response body.
//
// # Request Building
//
// [RequestBuilder] provides a fluent API for constructing requests with
// custom headers, query parameters, and bodies.
package httputil
```

**Exported function documentation:**
```go
// ParseJSONResponse decodes the JSON body of resp into v.
//
// It closes resp.Body after reading regardless of error.
// v must be a non-nil pointer to a value that can receive the JSON.
//
// Returns [ErrNonJSONContentType] if the response Content-Type is not
// application/json, and [ErrBadStatus] if the status code is >= 400.
func ParseJSONResponse(resp *http.Response, v any) error {
```

**Example functions (compiled + run by `go test`):**
```go
// In httputil_example_test.go (or httputil_test.go)
func ExampleParseJSONResponse() {
    body := `{"name":"Alice","age":30}`
    resp := &http.Response{
        StatusCode: 200,
        Header:     http.Header{"Content-Type": []string{"application/json"}},
        Body:       io.NopCloser(strings.NewReader(body)),
    }
    var user struct{ Name string; Age int }
    if err := ParseJSONResponse(resp, &user); err != nil {
        log.Fatal(err)
    }
    fmt.Println(user.Name)
    // Output:
    // Alice
}
```

**Doc links using `[Symbol]` syntax (Go 1.19+):**
```go
// NewRetryClient returns an [http.Client] configured with [RetryTransport].
// See [RetryTransport.MaxAttempts] to configure the retry budget.
func NewRetryClient(opts ...Option) *http.Client {
```

**Deprecated symbols (Go 1.21+):**
```go
// Deprecated: Use [NewRetryClient] instead, which provides automatic retries.
func NewClient() *http.Client {
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Verify docs compile (vet includes doc link checking)
  run: go vet ./...

- name: Run example functions
  run: go test ./... -run ^Example

- name: Check godoc locally (smoke test)
  run: |
    go install golang.org/x/tools/cmd/godoc@latest
    godoc -http=:6060 &
    sleep 3
    curl -sf http://localhost:6060/pkg/$(go list -m)/
```

**golangci-lint** includes `godot` (sentence ending) and `godox` (TODO/FIXME detection) which enforce comment style in CI:
```yaml
- uses: golangci/golangci-lint-action@v6
  with:
    args: --enable godot,godox
```

## Performance

- `go doc` is near-instant — it reads source files without compiling.
- Example functions execute as part of `go test` — their runtime is part of the test suite, not a separate doc generation step.
- `godoc -http` server starts in under a second and serves docs from local source. No build step required.
- `pkg.go.dev` re-indexes automatically on new module versions published to the module proxy. No manual trigger needed.

## Security

- Godoc is read-only and runs in-process with `go test` for example verification — no network access or file system writes.
- Avoid documenting internal implementation details, debug endpoints, or auth secrets in exported symbol comments — they appear on `pkg.go.dev` for public modules.
- `// Deprecated:` comments are rendered with a deprecation notice on `pkg.go.dev`, alerting consumers immediately.

## Testing

```bash
# View package docs in terminal
go doc ./...

# View specific symbol
go doc http.Client.Do

# Run only example functions
go test ./... -run ^Example -v

# Verify all examples produce expected output
go test ./... -run ^Example

# Start local doc server
godoc -http=:6060

# List all exported symbols with docs
go doc -all . | head -100
```

## Dos

- Start every package with a `// Package name ...` comment — it appears as the package summary on `pkg.go.dev` and in IDE tooltips.
- Begin each exported symbol's doc comment with the symbol name — Go tooling and `pkg.go.dev` use this convention for search and rendering.
- Write example functions in `_test.go` files with `// Output:` blocks — they are both documentation and runnable tests.
- Use `[Symbol]` cross-reference syntax (Go 1.19+) instead of backtick references — they render as hyperlinks on `pkg.go.dev`.
- Mark deprecated symbols with `// Deprecated: Use [NewSymbol] instead.` — IDEs display the deprecation notice inline.
- Document error return contracts explicitly — state which sentinel errors are returned and under what conditions.

## Don'ts

- Don't leave exported functions undocumented — `golint` and `revive` flag them as warnings, and they produce empty entries on `pkg.go.dev`.
- Don't write doc comments that just repeat the function signature — describe behavior, inputs, edge cases, and returned errors.
- Don't use `//nolint` to suppress godoc lints — fix the underlying comment instead.
- Don't write example functions without an `// Output:` block unless the example is intentionally non-deterministic — `go test` cannot verify unordered output automatically.
- Don't duplicate documentation between a type and its constructor — document the type thoroughly and have the constructor's comment reference it.
- Don't use `/* */` block comments for symbol documentation — Go convention uses `//` line comments; block comments are for package headers only in some styles.
