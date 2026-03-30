# Go-stdlib + go-cover

> Extends `modules/code-quality/go-cover.md` with Go-stdlib-specific integration.
> Generic go-cover conventions (flags, CI integration, threshold scripts) are NOT repeated here.

## Integration Setup

Stdlib projects test all packages directly — use `-coverpkg=./...` without scoping exclusions. There are no framework layers to exclude:

```bash
# Makefile
.PHONY: test coverage coverage-html

test:
	go test ./... -race -count=1

coverage:
	go test ./... \
	  -coverprofile=coverage.out \
	  -covermode=atomic \
	  -coverpkg=./...

coverage-html: coverage
	go tool cover -html=coverage.out -o coverage.html

coverage-check: coverage
	@COVERAGE=$$(go tool cover -func=coverage.out | grep "^total" | awk '{gsub(/%/, "", $$3); print $$3}'); \
	echo "Coverage: $$COVERAGE%"; \
	if [ $$(echo "$$COVERAGE < 85" | bc -l) -eq 1 ]; then \
		echo "FAIL: coverage $$COVERAGE% is below 85% threshold for stdlib project"; exit 1; \
	fi
```

Higher threshold (85%) is appropriate for stdlib projects — no framework abstractions inflate the denominator.

## Framework-Specific Patterns

### Table-Driven Tests Are the Standard

Stdlib projects should use table-driven tests for all functions with multiple input cases. Coverage of all table rows is the primary driver of high coverage:

```go
func TestParseAddress(t *testing.T) {
    t.Parallel()
    tests := []struct {
        name    string
        input   string
        want    Address
        wantErr bool
    }{
        {"valid IPv4", "192.168.1.1:8080", Address{Host: "192.168.1.1", Port: 8080}, false},
        {"valid hostname", "example.com:443", Address{Host: "example.com", Port: 443}, false},
        {"missing port", "example.com", Address{}, true},
        {"invalid port", "example.com:abc", Address{}, true},
        {"empty string", "", Address{}, true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()
            got, err := ParseAddress(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("ParseAddress(%q) error = %v, wantErr = %v", tt.input, err, tt.wantErr)
            }
            if !tt.wantErr && got != tt.want {
                t.Errorf("ParseAddress(%q) = %v, want %v", tt.input, got, tt.want)
            }
        })
    }
}
```

### Covering Error Branches

In stdlib projects, every `if err != nil` branch is a coverage opportunity. Use `errors.As`/`errors.Is` in tests to trigger specific error types:

```go
// Force the "file not found" branch
_, err := ReadConfig("/nonexistent/path")
var pathErr *os.PathError
if !errors.As(err, &pathErr) {
    t.Errorf("expected PathError, got %T: %v", err, err)
}
```

### Integration Test Binary Coverage (Go 1.20+)

For stdlib services (servers, CLIs), instrument the binary to measure coverage from integration tests:

```bash
# Build coverage-instrumented binary
go build -cover -o bin/server-cov ./cmd/server

# Run integration tests
GOCOVERDIR=./coverage-data ./bin/server-cov &
go test ./integration/... -run TestServerIntegration
kill %1

# Merge with unit test coverage
go tool covdata textfmt -i=./coverage-data -o=integration.out
```

### Excluding Generated Code

Stdlib projects using `go generate` for mocks or parsers should filter generated files from the threshold:

```bash
# Filter generated files from threshold calculation
grep -v "_gen.go\|_mock.go\|\.pb\.go" coverage.out > coverage.filtered.out
go tool cover -func=coverage.filtered.out | grep "^total:"
```

## Additional Dos

- Use 85% as the minimum threshold for stdlib projects — the absence of framework boilerplate means the coverage denominator is pure application logic.
- Always run with `-race` alongside coverage in CI (`-covermode=atomic`) — stdlib code frequently uses concurrency primitives that only fail under the race detector.
- Write `func Example*()` functions in `_test.go` — they are compiled, run, and counted in coverage while also serving as documentation.

## Additional Don'ts

- Don't set coverage thresholds on `cmd/` packages — `main()` functions contain only wiring and are impractical to unit test meaningfully.
- Don't omit `-count=1` in CI runs — the test cache can return cached passing results even after code changes, masking coverage regressions.
- Don't combine stdlib project coverage with vendor or `internal/testutil` packages — they skew the total and obscure real coverage gaps.
