# GitHub Actions with NestJS

> Extends `modules/ci-cd/github-actions.md` with NestJS CI patterns.
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
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci
      - run: npm run lint
      - run: npm run build
      - run: npm test -- --coverage
```

## Framework-Specific Patterns

### Nest Build + Swagger Generation

```yaml
- name: Build
  run: npm run build

- name: Generate OpenAPI spec
  run: node dist/swagger-cli.js > openapi.json

- uses: actions/upload-artifact@v4
  with:
    name: openapi-spec
    path: openapi.json
```

Generate the OpenAPI spec from Nest decorators at build time. Upload as an artifact for downstream consumers (docs, SDK generation).

### E2E Tests

```yaml
e2e-test:
  runs-on: ubuntu-latest
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
        --health-retries 5
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: 22
        cache: npm
    - run: npm ci
    - run: npm run test:e2e
      env:
        DATABASE_URL: postgresql://test:test@localhost:5432/test
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
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO run `nest build` in CI to verify TypeScript compilation
- DO generate and archive OpenAPI specs as build artifacts
- DO run E2E tests with database service containers
- DO use `npm ci` for deterministic installs

## Additional Don'ts

- DON'T skip the build step -- NestJS decorators are validated at compile time
- DON'T run E2E tests without a database service when using TypeORM/Prisma
- DON'T cache `node_modules/` directly -- use `actions/setup-node` cache
