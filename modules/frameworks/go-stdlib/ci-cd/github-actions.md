# GitHub Actions with Go stdlib

> Extends `modules/ci-cd/github-actions.md` with Go stdlib CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'
          cache: true

      - run: go vet ./...
      - run: staticcheck ./...
      - run: go test ./... -race -coverprofile=coverage.out
      - run: CGO_ENABLED=0 go build -o /dev/null ./...
```

## Framework-Specific Patterns

### Go Module Caching

```yaml
- uses: actions/setup-go@v5
  with:
    go-version: '1.23'
    cache: true
```

### staticcheck for stdlib Projects

```yaml
- name: Install staticcheck
  run: go install honnef.co/go/tools/cmd/staticcheck@latest
- run: staticcheck ./...
```

`staticcheck` is the recommended linter for stdlib-only Go projects. No framework-specific linter configuration needed.

### Docker Image Publishing

```yaml
publish:
  needs: test
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO use `actions/setup-go` with `cache: true`
- DO run `go vet` and `staticcheck` before tests
- DO use `-race` flag to detect data races
- DO build with `CGO_ENABLED=0` for static binaries

## Additional Don'ts

- DON'T cache modules manually when using `setup-go` caching
- DON'T skip `go vet` -- it catches common Go mistakes
- DON'T build with CGO when targeting `scratch` images
