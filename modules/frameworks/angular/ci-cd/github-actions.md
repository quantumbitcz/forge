# GitHub Actions with Angular

> Extends `modules/ci-cd/github-actions.md` with Angular CLI CI patterns.
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
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci

      - name: Lint
        run: npx ng lint

      - name: Test
        run: npx ng test --no-watch --browsers=ChromeHeadless

      - name: Build
        run: npx ng build --configuration production

      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
```

## Framework-Specific Patterns

### AOT Compilation Verification

The `--configuration production` flag enables AOT compilation. AOT catches template errors that JIT misses. Always build with production config in CI even if tests pass.

### Angular Universal SSR Build

```yaml
ssr-build:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: actions/setup-node@v4
      with:
        node-version: 22
        cache: npm
    - run: npm ci
    - name: Build SSR
      run: npx ng build --configuration production
    - name: Verify server bundle
      run: node dist/app/server/server.mjs --dry-run || true
```

### Playwright E2E Tests

```yaml
e2e:
  needs: build
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: actions/setup-node@v4
      with:
        node-version: 22
        cache: npm
    - run: npm ci
    - run: npx playwright install --with-deps chromium
    - uses: actions/download-artifact@v4
      with:
        name: dist
        path: dist/
    - run: npx playwright test
    - uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: playwright-report
        path: playwright-report/
```

### Docker Image Publishing

```yaml
publish:
  needs: build
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
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO always build with `--configuration production` in CI for AOT compilation
- DO run `ng test` with `--no-watch --browsers=ChromeHeadless` for headless CI execution
- DO upload Playwright reports as artifacts on failure
- DO use `npm ci` for deterministic installs

## Additional Don'ts

- DON'T skip AOT builds in CI -- JIT-only testing misses template binding errors
- DON'T use `ng serve` in CI -- use `ng build` and serve the output for E2E tests
- DON'T install all Playwright browsers -- use `--with-deps chromium` for faster setup
