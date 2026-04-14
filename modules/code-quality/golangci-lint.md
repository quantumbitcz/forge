---
name: golangci-lint
categories: [linter]
languages: [go]
exclusive_group: go-linter
recommendation_score: 90
detection_files: [.golangci.yml, .golangci.yaml, .golangci.toml, .golangci.json]
---

# golangci-lint

## Overview

Go meta-linter that runs 100+ linters in parallel with a single configuration file. Replaces running `go vet`, `staticcheck`, `errcheck`, `gosec`, `revive`, and others individually. The canonical tool for Go static analysis in CI — the `golangci-lint` GitHub Action handles caching automatically and is the recommended CI integration path. Configuration lives in `.golangci.yml`. Run `golangci-lint run` locally and in CI for identical results.

## Architecture Patterns

### Installation & Setup

```bash
# Binary install (recommended — do NOT use `go install` for golangci-lint)
curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(go env GOPATH)/bin v1.63.x

# Homebrew (MacOS)
brew install golangci-lint

# Verify
golangci-lint --version
```

Do not use `go install github.com/golangci/golangci-lint/cmd/golangci-lint` — it bypasses version pinning and may pull in incompatible module dependencies.

### Rule Categories

Linters are grouped by function. Enable selectively — running all 100+ linters is rarely appropriate:

| Category | Key Linters | What They Check | Pipeline Severity |
|---|---|---|---|
| Bugs | `errcheck`, `govet`, `staticcheck` | Unchecked errors, incorrect `go vet` patterns, static analysis bugs | CRITICAL |
| Security | `gosec` | Hardcoded credentials, weak crypto, path traversal, unsafe operations | CRITICAL |
| Complexity | `gocognit`, `cyclop`, `funlen` | Cognitive complexity, cyclomatic complexity, function length | WARNING |
| Style | `revive`, `stylecheck` | Naming conventions, exported symbols, comment format | WARNING |
| Unused | `unused`, `deadcode` | Unreachable code, unused exported symbols | WARNING |
| Performance | `prealloc`, `noctx` | Slice preallocation, missing context in HTTP calls | WARNING |
| Imports | `goimports`, `gci` | Import grouping, stdlib vs third-party ordering | INFO |
| SQL | `rowserrcheck`, `sqlclosecheck` | Unchecked `rows.Err()`, unclosed SQL resources | CRITICAL |
| Test | `tparallel`, `thelper`, `testifylint` | Missing `t.Parallel()`, incorrect test helpers, testify assertions | WARNING |
| Modules | `gomodguard`, `depguard` | Banned dependencies, module proxy enforcement | WARNING |

### Configuration Patterns

**`.golangci.yml` — recommended starting point:**
```yaml
version: "2"

linters:
  default: none    # disable all by default, enable explicitly
  enable:
    # Bugs (always enable)
    - errcheck
    - govet
    - staticcheck
    - ineffassign
    - typecheck
    # Security
    - gosec
    # Style
    - revive
    - gofmt
    - goimports
    # Complexity
    - gocognit
    # SQL safety
    - rowserrcheck
    - sqlclosecheck
    # Unused code
    - unused

linters-settings:
  errcheck:
    check-type-assertions: true    # flag unchecked type assertions
    check-blank: true             # flag `_ = func()` that discards errors
  gosec:
    excludes:
      - G404   # math/rand — acceptable for non-crypto use
  gocognit:
    min-complexity: 15
  revive:
    rules:
      - name: exported
        arguments:
          - "checkPrivateReceivers"
          - "sayRepetitiveInsteadOfStutters"
      - name: var-naming
      - name: unused-parameter
  goimports:
    local-prefixes: "github.com/yourorg/yourrepo"

issues:
  exclude-rules:
    # Relax rules in test files
    - path: "_test\\.go"
      linters:
        - errcheck
        - gosec
    # Ignore generated files
    - path: "\\.pb\\.go"
      linters:
        - all
    - path: "mock_.*\\.go"
      linters:
        - all
  max-issues-per-linter: 50
  max-same-issues: 10
  new-from-rev: HEAD~1    # only lint changed code (remove for full scan)

run:
  timeout: 5m
  tests: true
  build-tags:
    - integration
```

**Inline suppression (use sparingly):**
```go
result, err := riskyOperation() //nolint:errcheck -- intentionally ignored, non-critical path
```

For multi-file suppressions, use `issues.exclude-rules` in `.golangci.yml` rather than scattering `//nolint` comments.

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: golangci-lint
  uses: golangci/golangci-lint-action@v6
  with:
    version: v1.63.x          # pin version — never use "latest"
    args: --out-format=github-actions --timeout=5m
    only-new-issues: false     # set true during gradual adoption
```

The `golangci-lint-action` handles binary download caching and result annotation natively. `--out-format=github-actions` emits inline PR annotations.

**Manual CI (non-GitHub):**
```yaml
- name: Install golangci-lint
  run: |
    curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
      | sh -s -- -b /usr/local/bin v1.63.x

- name: Run golangci-lint
  run: golangci-lint run --out-format=tab --timeout=5m
```

## Performance

- Parallel linter execution is automatic — golangci-lint runs multiple linters concurrently on the same parsed AST.
- Result caching (`.golangci-lint-cache/`) stores results per file hash — incremental runs skip unchanged packages.
- `new-from-rev: HEAD~1` limits analysis to changed files — reduces CI time from minutes to seconds on large repos, but masks pre-existing issues.
- Avoid enabling `scopelint`, `maligned`, or deprecated linters — they are removed or superseded and slow down the run.
- Set `timeout: 5m` — default is 1m which may time out on large monorepos with many linters enabled.
- Use `golangci-lint cache clean` to reset cache if results appear stale after config changes.

## Security

`gosec` (G-prefixed rules) covers Go-specific security patterns:

- `G101` — hardcoded credentials detected via pattern matching
- `G204` — subprocess with variable arguments — potential command injection
- `G304` — file path from variable — potential path traversal
- `G401` / `G501` — use of weak cryptographic hash functions
- `G501` — import of `crypto/md5` or `crypto/sha1`
- `G601` — implicit memory aliasing in for-range (fixed in Go 1.22, safe to exclude on newer versions)

Enable `gosec` with targeted excludes rather than disabling it entirely. Exclude `G404` (math/rand) only when non-cryptographic randomness is intentional.

## Testing

```bash
# Run all configured linters
golangci-lint run

# Run with verbose output
golangci-lint run -v

# Run on specific packages
golangci-lint run ./internal/...

# Run a specific linter only
golangci-lint run --disable-all --enable=gosec

# Show configured linters
golangci-lint linters

# Show all available linters
golangci-lint linters --all

# Validate config file
golangci-lint config verify

# Clear result cache
golangci-lint cache clean

# Format output for GitHub Actions (local testing)
golangci-lint run --out-format=github-actions
```

## Dos

- Pin the version in CI via `golangci-lint-action` `version` field — minor releases regularly change default-enabled linters and can break CI unexpectedly.
- Use `linters.default: none` and enable explicitly — it makes the enabled set visible in code review and avoids surprise from newly added defaults.
- Enable `errcheck` with `check-type-assertions: true` — unchecked type assertions `.(Type)` panic at runtime.
- Exclude `_test.go` from `gosec` and `errcheck` — test code legitimately ignores some error patterns.
- Configure `goimports.local-prefixes` with your module path — it separates stdlib, third-party, and internal imports with blank lines.
- Use `//nolint:lintername -- reason` format (with reason) — bare `//nolint` suppresses all linters on that line and hides future issues.

## Don'ts

- Don't enable all 100+ linters indiscriminately — many are experimental, deprecated, or produce high false-positive rates on idiomatic Go. Enable by category, evaluate each.
- Don't set `new-from-rev` as a permanent configuration — it masks pre-existing issues. Use it temporarily during initial adoption, then remove.
- Don't use `go install` for golangci-lint installation — it may pull a different version of the binary depending on the module graph.
- Don't skip `config verify` after modifying `.golangci.yml` — malformed config silently falls back to defaults rather than erroring.
- Don't suppress `staticcheck` findings without investigation — staticcheck has very low false positive rates; suppressing it usually means hiding a real bug.
- Don't run golangci-lint without `--timeout` in CI — the default 1m timeout fails silently on large repos, reporting zero issues rather than an error.
