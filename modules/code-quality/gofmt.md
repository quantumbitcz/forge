---
name: gofmt
categories: [formatter]
languages: [go]
exclusive_group: go-formatter
recommendation_score: 70
detection_files: [go.mod, go.sum]
---

# gofmt

## Overview

Go's built-in canonical formatter, shipped with the Go toolchain. Zero configuration — one style for all Go code. `gofmt` reformats code to the official Go style: tabs for indentation, spaces for alignment, canonical blank-line placement. `goimports` is the recommended superset: it runs `gofmt` and also adds missing imports and removes unused ones. In CI, use `gofmt -l` to list unformatted files and fail the build if any are found. All Go code must be `gofmt`-formatted — unformatted code is rejected at code review and by most CI pipelines.

## Architecture Patterns

### Installation & Setup

```bash
# gofmt ships with Go — no separate install needed
go version   # confirms Go (and gofmt) is installed

# goimports (superset — recommended for editor/pre-commit use)
go install golang.org/x/tools/cmd/goimports@latest

# gofumpt (stricter superset — enforces additional rules)
go install mvdan.cc/gofumpt@latest
```

No configuration file — `gofmt` accepts no options beyond `-s` (simplifications) and `-r` (rewrite rules).

### Rule Categories

`gofmt` enforces a single canonical style — not configurable. Key transformations applied:

| Transformation | Example |
|---|---|
| Tab indentation | All indentation uses hard tabs |
| Operator spacing | `x=1` → `x = 1` |
| Bracket placement | Opening `{` on same line, never alone |
| Blank lines | Single blank line between top-level declarations |
| Import grouping | Stdlib first, then third-party (when using `goimports`) |

**`goimports` adds:**
- Auto-add missing `import` statements based on package usage
- Remove unused import statements
- Group imports: stdlib / third-party / local (`-local` flag)

```bash
# Group local imports separately (recommended for projects with internal packages)
goimports -local github.com/myorg/myapp -w ./...
```

### Configuration Patterns

**`gofmt` has no config file.** Project-level conventions go in a `Makefile` or `justfile`:

```makefile
.PHONY: fmt fmt-check lint

fmt:
	gofmt -s -w ./...

fmt-check:
	@test -z "$(shell gofmt -l ./...)" || (echo "Unformatted files:"; gofmt -l ./.; exit 1)

imports:
	goimports -local github.com/myorg/myapp -w ./...
```

**`golangci-lint` integration** — include `gofmt`/`goimports` as linters in `.golangci.yml`:
```yaml
linters:
  enable:
    - gofmt
    - goimports

linters-settings:
  goimports:
    local-prefixes: github.com/myorg/myapp
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Check formatting
  run: |
    unformatted=$(gofmt -l ./...)
    if [ -n "$unformatted" ]; then
      echo "Unformatted files:"
      echo "$unformatted"
      exit 1
    fi
```

**With `golangci-lint` (preferred for unified reporting):**
```yaml
- name: golangci-lint
  uses: golangci/golangci-lint-action@v6
  with:
    version: v1.62.0
```

**Pre-commit hook:**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/dnephin/pre-commit-golang
    rev: v0.5.1
    hooks:
      - id: go-fmt
      - id: go-imports
        args: [-local, github.com/myorg/myapp]
```

## Performance

- `gofmt` processes a 100k-line Go codebase in milliseconds — performance is never a concern.
- `goimports` is slightly slower due to package resolution for import management; still sub-second on most projects.
- Use `./...` to format all packages recursively — Go's tooling handles this natively without shell globbing.
- `gofumpt` is marginally slower than `gofmt` but still under 1 second for typical projects.

## Security

`gofmt` has no security analysis capability. Key practices:

- `gofmt` is part of the official Go distribution — no supply chain risk from the formatter itself.
- `goimports` fetches package metadata from the module cache — ensure `GONOSUMCHECK` and `GONOSUMDB` are not set in CI to maintain checksum verification.
- `gofmt -r` (rewrite rules) can transform code in bulk — review rewrite rules carefully before applying to production code; they operate on AST patterns and can have unintended side effects.

## Testing

```bash
# List files that would be reformatted (dry run — exit 0 even if found)
gofmt -l ./...

# Format all files in place
gofmt -w ./...

# Format with simplifications (-s): composite literals, slice expressions
gofmt -s -w ./...

# Show diff without writing
gofmt -d ./...

# Format stdin and print to stdout
echo 'package main; func main(){println("hi")}' | gofmt

# Verify CI check passes
test -z "$(gofmt -l ./...)" && echo "All files formatted" || echo "Unformatted files found"

# goimports: format + fix imports
goimports -l -w ./...
```

## Dos

- Always run `gofmt -s` (with simplifications) — it applies canonical Go idioms like `[]T{v}` → `{v}` in composite literals.
- Use `goimports` in editor integration instead of bare `gofmt` — it handles import management automatically and prevents "unused import" compile errors during development.
- Set `-local github.com/yourorg/yourrepo` with `goimports` — it groups internal packages separately from third-party, keeping imports readable.
- Fail CI immediately on unformatted files — unformatted Go is universally treated as a code quality issue in the community.
- Use `golangci-lint` with `gofmt`/`goimports` enabled for unified reporting in CI — single tool run, single annotation pass.
- Configure your editor to run `goimports -w` on save — prevents accumulation of formatting fixes in PRs.

## Don'ts

- Don't skip `gofmt` checks in CI because "the editor handles it" — CI is the last gate against inconsistencies from contributors with different editor configs.
- Don't use `gofmt -r` (rewrite rules) in CI without reviewing every transformation it will apply — rewrite rules can introduce semantic changes.
- Don't run both `gofmt` and `goimports` independently on the same files — `goimports` is a superset; running both is redundant and can cause ordering issues.
- Don't add `gofmt` ignores or exceptions — there is no ignore mechanism and no legitimate reason to skip formatting in Go.
- Don't configure tab width in editor to display as something other than 4 spaces — the canonical convention is tabs displayed as 4 spaces; mismatches cause visual inconsistency without affecting the file.
- Don't wrap `gofmt` calls in scripts that silently succeed on failure — always propagate exit codes from `gofmt -l` to the CI step.
