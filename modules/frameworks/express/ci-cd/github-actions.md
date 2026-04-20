# GitHub Actions with Express

> Extends `modules/ci-cd/github-actions.md` with Express/Node.js CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
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

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci

      - name: Lint
        run: npx eslint .

      - name: Test
        run: npm test -- --coverage
```

## Framework-Specific Patterns

### npm ci Caching

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 22
    cache: npm
```

`actions/setup-node` caches `~/.npm` automatically when `cache: npm` is set. `npm ci` uses the lockfile for deterministic installs.

### Database Service for Integration Tests

```yaml
services:
  postgres:
    image: postgres:16-alpine
    env:
      POSTGRES_DB: test
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    ports:
      - 5432:5432
    options: >-
      --health-cmd "pg_isready -U test"
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5

steps:
  - run: npm test
    env:
      DATABASE_URL: postgresql://test:test@localhost:5432/test
      NODE_ENV: test
```

### Docker Image Publishing

```yaml
publish:
  needs: test
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO use `npm ci` (not `npm install`) in CI for deterministic, lockfile-based installs
- DO use `actions/setup-node` with `cache: npm` for automatic dependency caching
- DO set `NODE_ENV=test` when running tests to load test-specific configuration
- DO use GHA cache backend for Docker layer caching

## Additional Don'ts

- DON'T use `npm install` in CI -- it modifies `package-lock.json` and breaks reproducibility
- DON'T cache `node_modules/` directly -- cache the npm global cache and let `npm ci` install
- DON'T skip the lockfile (`--no-package-lock`) in CI environments
