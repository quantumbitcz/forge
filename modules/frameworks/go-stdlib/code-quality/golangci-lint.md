# Go-stdlib + golangci-lint

> Extends `modules/code-quality/golangci-lint.md` with Go-stdlib-specific integration.
> Generic golangci-lint conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Go-stdlib projects have no framework dependencies — apply a stricter linter set that enforces pure idiomatic Go. Use `gocritic`, `govet`, and `staticcheck` as the core trio:

```yaml
# .golangci.yml
version: "2"

linters:
  default: none
  enable:
    # Core correctness (always on)
    - errcheck
    - govet
    - staticcheck
    - ineffassign
    - typecheck
    # Security
    - gosec
    # Idiomatic Go (stricter in stdlib projects)
    - gocritic       # 100+ checks for idiomatic patterns
    - revive
    - gofmt
    - goimports
    # Complexity (strict — stdlib code should be readable without framework context)
    - gocognit
    - cyclop
    - funlen
    # Unused code
    - unused
    - deadcode
    # SQL safety (if database/sql is used)
    - rowserrcheck
    - sqlclosecheck
    # Test quality
    - tparallel
    - thelper

linters-settings:
  gocognit:
    min-complexity: 10    # stricter than default — stdlib code must be clear
  cyclop:
    max-complexity: 10
  funlen:
    lines: 60
    statements: 40
  gocritic:
    enabled-tags:
      - diagnostic
      - style
      - performance
    disabled-checks:
      - commentFormatting  # handled by revive
  revive:
    rules:
      - name: exported
        arguments: ["checkPrivateReceivers", "sayRepetitiveInsteadOfStutters"]
      - name: var-naming
      - name: unused-parameter
      - name: error-return
      - name: error-strings
      - name: increment-decrement
  goimports:
    local-prefixes: "github.com/yourorg/yourapp"

issues:
  exclude-rules:
    - path: "_test\\.go"
      linters: [errcheck, gosec, funlen]
    - path: ".*\\.pb\\.go"
      linters: [all]
```

## Framework-Specific Patterns

### Stricter Complexity for Pure Go

Without a framework providing scaffolding, all complexity is application logic. Set lower thresholds than framework-based projects:

- `gocognit.min-complexity: 10` (vs 15 for framework projects)
- `funlen.lines: 60` — long functions signal missing abstractions, not framework boilerplate
- `cyclop.max-complexity: 10` — cyclomatic complexity above 10 in stdlib code is a design smell

### gocritic for Idiomatic Patterns

`gocritic` catches patterns that are technically correct but not idiomatic. For stdlib projects where idiom is the only guide, enable the full `diagnostic`, `style`, and `performance` tag sets:

```go
// gocritic catches these in stdlib projects:

// appendAssign — append result not assigned back (silent no-op)
s = append(s, x) // OK
append(s, x)     // flagged: result discarded

// rangeValCopy — large value copied in range
for _, v := range largeStructSlice { // flagged if v > 128 bytes
    process(v)
}
// Fix:
for i := range largeStructSlice {
    process(&largeStructSlice[i])
}
```

### Error Wrapping Conventions

`revive`'s `error-strings` rule enforces that error strings are lowercase and do not end with punctuation — the stdlib convention when errors are wrapped with `fmt.Errorf`:

```go
// Bad — flagged by revive error-strings
return fmt.Errorf("Failed to read config file.") // uppercase, punctuation

// Good
return fmt.Errorf("failed to read config file: %w", err)
```

### SQL Safety for database/sql Users

Stdlib projects often use `database/sql` directly. Enable `rowserrcheck` and `sqlclosecheck` — they are CRITICAL category findings:

```go
rows, err := db.QueryContext(ctx, query, args...)
if err != nil { return err }
defer rows.Close()       // sqlclosecheck requires this
// ...
if err := rows.Err(); err != nil { // rowserrcheck requires this
    return err
}
```

## Additional Dos

- Enable `gocritic` with `diagnostic` + `style` + `performance` tags — stdlib projects benefit most from idiomatic-pattern enforcement since there is no framework convention to fall back on.
- Set `funlen.lines: 60` — stdlib handler/service functions with more than 60 lines signal missing helper abstractions.
- Enable `tparallel` — pure Go tests should use `t.Parallel()` extensively; flagging missing parallel declarations improves CI performance.

## Additional Don'ts

- Don't disable `staticcheck` — it has near-zero false positive rate and catches real bugs. Stdlib projects have no framework magic that could confuse it.
- Don't set `new-from-rev: HEAD~1` for stdlib library repos published on pkg.go.dev — it hides issues from new contributors reviewing the public API.
- Don't enable `wsl` (whitespace linter) — it enforces highly opinionated blank-line rules that conflict with Go community norms in stdlib-style packages.
