# go-cover

## Overview

Go has built-in coverage support via the `go test` toolchain — no third-party tool required. Run `go test -cover` for a quick percentage summary or `-coverprofile=coverage.out` to write detailed coverage data. Visualize with `go tool cover -html=coverage.out`. Use `-coverpkg=./...` to measure coverage across all packages, including packages called by tests in other packages. Go 1.20+ introduced `go build -cover` for binary-level coverage of integration tests. The built-in approach measures statement (not branch) coverage.

## Architecture Patterns

### Installation & Setup

No installation needed — coverage is part of the standard `go test` toolchain.

```bash
# Quick coverage percentage
go test ./... -cover

# Write coverage profile
go test ./... -coverprofile=coverage.out

# Generate HTML report
go tool cover -html=coverage.out -o coverage.html

# Print per-function coverage
go tool cover -func=coverage.out
```

**Cross-package coverage (`-coverpkg`):**
```bash
# Without -coverpkg: only packages directly tested appear in profile
# With -coverpkg: includes all packages that are executed during tests
go test ./... -coverprofile=coverage.out -coverpkg=./...

# Target specific packages for coverage, test all
go test ./... -coverprofile=coverage.out -coverpkg=./internal/...,./pkg/...
```

**Makefile integration:**
```makefile
.PHONY: test coverage coverage-html

test:
	go test ./... -race

coverage:
	go test ./... -coverprofile=coverage.out -coverpkg=./... -covermode=atomic
	go tool cover -func=coverage.out | grep -E "^total" | awk '{print "Total coverage: " $$3}'

coverage-html: coverage
	go tool cover -html=coverage.out -o coverage.html
	open coverage.html

coverage-check: coverage
	@COVERAGE=$$(go tool cover -func=coverage.out | grep "^total" | awk '{gsub(/%/, "", $$3); print $$3}'); \
	echo "Coverage: $$COVERAGE%"; \
	if [ $$(echo "$$COVERAGE < 80" | bc -l) -eq 1 ]; then \
		echo "FAIL: coverage $$COVERAGE% is below threshold 80%"; exit 1; \
	fi
```

### Rule Categories

| Flag | Effect |
|---|---|
| `-cover` | Print total coverage percentage only |
| `-coverprofile=file` | Write coverage profile for `go tool cover` |
| `-coverpkg=pattern` | Include packages matching pattern in coverage data |
| `-covermode=set` | Track which statements were run (default) |
| `-covermode=count` | Count how many times each statement ran |
| `-covermode=atomic` | Like count but safe for parallel tests (use with `-race`) |

### Configuration Patterns

**Coverage thresholds via shell script:**
```bash
#!/usr/bin/env bash
# scripts/check-coverage.sh
set -euo pipefail

THRESHOLD="${COVERAGE_THRESHOLD:-80}"

go test ./... -coverprofile=coverage.out -covermode=atomic -coverpkg=./...

COVERAGE=$(go tool cover -func=coverage.out | grep "^total:" | awk '{gsub(/%/,""); print $3}')
echo "Total coverage: ${COVERAGE}%"

if (( $(echo "$COVERAGE < $THRESHOLD" | bc -l) )); then
    echo "ERROR: Coverage ${COVERAGE}% is below threshold ${THRESHOLD}%"
    exit 1
fi
echo "OK: Coverage ${COVERAGE}% >= ${THRESHOLD}%"
```

**Excluding files from coverage (no built-in exclusion mechanism):**
```go
// build tag approach — exclude generated files:
//go:build ignore
// +build ignore

// Or by naming convention: files ending in _gen.go, _mock.go
// Filter them out in report:
grep -v "_gen.go\|_mock.go\|_test.go" coverage.out > coverage.filtered.out
go tool cover -func=coverage.filtered.out
```

**Integration test binary coverage (Go 1.20+):**
```bash
# Build a coverage-instrumented binary
go build -cover -o bin/myapp-cov ./cmd/myapp

# Run integration tests against the binary
GOCOVERDIR=./coverage-data ./bin/myapp-cov &
# ... run integration tests ...
kill %1

# Convert to profile and report
go tool covdata textfmt -i=./coverage-data -o=coverage.out
go tool cover -func=coverage.out
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Run tests with coverage
  run: |
    go test ./... -coverprofile=coverage.out -covermode=atomic -coverpkg=./...
    go tool cover -func=coverage.out

- name: Check coverage threshold
  run: |
    COVERAGE=$(go tool cover -func=coverage.out | grep "^total:" | awk '{gsub(/%/,""); print $3}')
    echo "Coverage: ${COVERAGE}%"
    if (( $(echo "$COVERAGE < 80" | bc -l) )); then echo "Below threshold"; exit 1; fi

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage.out
    fail_ci_if_error: true
```

## Performance

- `-covermode=atomic` is required for `-race` tests — use it in CI. `-covermode=set` is faster for local coverage checks without the race detector.
- `-coverpkg=./...` adds instrumentation to all packages, increasing binary size and test compilation time by 20-50% on large repos. Scope it to relevant packages if compilation time is a concern.
- `go test -count=1` disables the test cache — use in CI to always re-run tests. Omit locally to benefit from caching.
- Integration test binary coverage (Go 1.20+) has negligible runtime overhead — the instrumentation writes to `GOCOVERDIR` only after the process exits.

## Security

- `coverage.out` is a plain text file with package paths and statement counts — safe to store as CI artifacts.
- Do not ship coverage-instrumented binaries (`go build -cover`) to production — they collect coverage data to `GOCOVERDIR` which may expose runtime paths.
- HTML coverage reports embed source code — do not publish publicly for proprietary packages.

## Testing

```bash
# Run all tests with coverage
go test ./... -cover

# Full profile for reporting
go test ./... -coverprofile=coverage.out -covermode=atomic -coverpkg=./...

# Per-function breakdown
go tool cover -func=coverage.out

# Open HTML in browser
go tool cover -html=coverage.out

# Check total without opening browser
go tool cover -func=coverage.out | tail -1

# Single package with verbose output
go test -v -coverprofile=coverage.out ./internal/service/...
go tool cover -func=coverage.out
```

## Dos

- Use `-coverpkg=./...` to capture coverage from packages exercised indirectly — without it, only the directly tested package appears in the profile.
- Use `-covermode=atomic` whenever running with `-race` — the default `set` mode is not safe for concurrent test execution.
- Enforce thresholds via a CI shell script — Go's built-in toolchain does not have a `--fail-under` flag.
- Generate both `cover -func` (machine-parseable) and `cover -html` (human-readable) reports — the `func` output is easy to parse in shell scripts.
- Use `go build -cover` (Go 1.20+) for integration tests running real binaries — it captures coverage from code paths that unit tests cannot reach.
- Store `coverage.out` as a CI artifact for historical trend analysis and Codecov uploads.

## Don'ts

- Don't use `-covermode=set` in parallel test runs with `-race` — it produces incorrect counts for concurrently accessed statements.
- Don't omit `-coverpkg=./...` for packages that are pure libraries tested by other packages' tests — they will appear as 0% covered without this flag.
- Don't rely on Go's coverage percentage in the `go test -cover` summary without a profile — it only shows the directly tested package and does not catch gaps in called packages.
- Don't use `// +build ignore` to hide files from coverage if the code is actually executed at runtime — hiding coverage gaps with build constraints is misleading.
- Don't set an 80% threshold for packages that consist primarily of auto-generated code, CLI wiring, or `main()` functions — apply thresholds to business logic packages only.
