# Go-stdlib + godoc

> Extends `modules/code-quality/godoc.md` with Go-stdlib-specific integration.
> Generic godoc conventions (comment format, example functions, CI integration) are NOT repeated here.

## Integration Setup

Stdlib projects published on pkg.go.dev require complete documentation — all exported symbols must have doc comments. Enforce via `revive` `exported` rule and `golangci-lint`:

```yaml
# .golangci.yml
linters-settings:
  revive:
    rules:
      - name: exported
        arguments:
          - "checkPrivateReceivers"
          - "sayRepetitiveInsteadOfStutters"
  godot:
    scope: toplevel          # sentences must end with a period
    exclude: []
    capital: false
```

```yaml
# CI — also verify examples run
- name: Run example functions
  run: go test ./... -run ^Example -v

- name: Verify godoc compiles
  run: go vet ./...
```

## Framework-Specific Patterns

### Package-Level Documentation Standard

Every package in a stdlib project must have a package comment that explains purpose, scope, and links to key types:

```go
// Package retry provides exponential backoff and jitter for retrying
// transient operations.
//
// # Basic Usage
//
// Use [Do] for one-shot retries with a default policy:
//
//	err := retry.Do(ctx, func() error {
//	    return callExternalService()
//	})
//
// # Custom Policies
//
// Create a [Policy] for fine-grained control over backoff timing and
// error classification. See [Policy.WithMaxAttempts] and [Policy.WithJitter].
//
// # Error Classification
//
// By default, all non-nil errors trigger a retry. Use [IsRetryable] to
// register custom error classifiers.
package retry
```

### Stdlib-Style Function Documentation

Follow the standard library's own documentation style: start with the function name, describe behavior (not implementation), state preconditions, and use `[Symbol]` links:

```go
// Do retries fn until it succeeds or the context is cancelled.
//
// It uses the default [Policy] which applies exponential backoff with
// full jitter, a 100ms base delay, and up to 5 attempts.
//
// Do returns the last error returned by fn if all attempts fail.
// Do returns [context.Canceled] or [context.DeadlineExceeded] immediately
// if the context is done between attempts.
//
// For custom retry behavior, construct a [Policy] and call [Policy.Do].
func Do(ctx context.Context, fn func() error) error {
```

### Example Functions as Tests

In stdlib projects, example functions are the primary documentation medium. Write at least one example per exported type and one per non-trivial exported function:

```go
// In retry_example_test.go

func ExampleDo() {
    ctx := context.Background()
    attempts := 0
    err := retry.Do(ctx, func() error {
        attempts++
        if attempts < 3 {
            return errors.New("transient error")
        }
        return nil
    })
    fmt.Println(err, attempts)
    // Output:
    // <nil> 3
}

func ExamplePolicy_WithMaxAttempts() {
    p := retry.NewPolicy().WithMaxAttempts(2)
    ctx := context.Background()
    err := p.Do(ctx, func() error {
        return errors.New("always fails")
    })
    fmt.Println(err != nil)
    // Output:
    // true
}
```

### Documenting Errors and Sentinels

Exported error variables and sentinel types must be documented — they are part of the public API contract:

```go
// ErrMaxAttemptsExceeded is returned by [Do] and [Policy.Do] when all
// retry attempts are exhausted without a successful call.
//
// Check for this error to distinguish exhausted retries from context cancellation:
//
//	if errors.Is(err, retry.ErrMaxAttemptsExceeded) {
//	    // All attempts failed — the operation is not retryable
//	}
var ErrMaxAttemptsExceeded = errors.New("max retry attempts exceeded")
```

## Additional Dos

- Write package-level comments for every package — they appear on pkg.go.dev as the package summary and are indexed by search.
- Document all exported error variables with `errors.Is` usage examples — callers need to know how to handle specific error cases.
- Run `go test ./... -run ^Example` in CI — it verifies that every `// Output:` block produces the documented result.

## Additional Don'ts

- Don't leave exported interfaces undocumented — interface methods require individual doc comments explaining the contract, especially for optional behavior.
- Don't use `// TODO:` or `// FIXME:` in doc comments that appear on pkg.go.dev — they project an unfinished impression to module consumers.
- Don't duplicate the type comment in constructor comments — reference the type with `[TypeName]` and describe only what the constructor does differently.
