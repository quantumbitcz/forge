# GitHub Actions with Vapor

> Extends `modules/ci-cd/github-actions.md` with Vapor/Swift CI patterns.
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
    container: swift:6.0
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd "pg_isready -U test"
          --health-interval 10s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Resolve dependencies
        run: swift package resolve

      - name: Build
        run: swift build

      - name: Test
        run: swift test
        env:
          DATABASE_URL: postgresql://test:test@postgres:5432/test
```

## Framework-Specific Patterns

### Swift Package Cache

```yaml
- uses: actions/cache@v4
  with:
    path: .build
    key: swift-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
    restore-keys: |
      swift-${{ runner.os }}-
```

Cache `.build/` keyed by `Package.resolved` for faster dependency resolution.

### Fluent Migration Check

```yaml
- name: Run migrations
  run: swift run App migrate --yes
  env:
    DATABASE_URL: postgresql://test:test@postgres:5432/test
```

### Docker Image Publishing

```yaml
publish:
  needs: test
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
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

- DO use the official Swift Docker image as the CI container
- DO cache `.build/` keyed by `Package.resolved`
- DO run Fluent migrations before tests
- DO use `swift build` before `swift test` for faster compilation

## Additional Don'ts

- DON'T use macOS runners for Linux deployment targets -- use Swift Docker containers
- DON'T skip migration verification in CI
- DON'T cache the entire `.build/` without key rotation
