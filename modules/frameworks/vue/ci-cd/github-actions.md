# GitHub Actions with Vue / Nuxt

> Extends `modules/ci-cd/github-actions.md` with Vue 3 / Nuxt 3 CI patterns.
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
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci

      - name: Lint
        run: npm run lint

      - name: Type Check
        run: npx nuxi typecheck

      - name: Test
        run: npm run test

      - name: Build
        run: npm run build

      - uses: actions/upload-artifact@v4
        with:
          name: output
          path: .output/
```

## Framework-Specific Patterns

### Nuxt Type Checking

```yaml
- name: Type Check
  run: npx nuxi typecheck
```

Nuxt generates types from auto-imports, composables, and server routes. Run `nuxi typecheck` (not just `tsc`) to include Nuxt-generated types in validation.

### Nuxt Static Generation

```yaml
generate:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: 22
        cache: npm
    - run: npm ci
    - run: npx nuxt generate
    - uses: actions/upload-artifact@v4
      with:
        name: static-site
        path: .output/public/
```

For static sites, `nuxt generate` pre-renders all routes. Deploy `.output/public/` to any static host.

### Playwright E2E Tests

```yaml
e2e:
  needs: build
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: 22
        cache: npm
    - run: npm ci
    - run: npx playwright install --with-deps chromium
    - uses: actions/download-artifact@v4
      with:
        name: output
        path: .output/
    - name: Start preview and test
      run: |
        npx nuxt preview &
        npx wait-on http://localhost:3000
        npx playwright test
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
    - uses: actions/checkout@v4
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

- DO run `nuxi typecheck` instead of plain `tsc` for Nuxt-generated types
- DO upload `.output/` as an artifact for downstream deployment
- DO use `nuxt preview` with `wait-on` for E2E testing against the built app
- DO use `npm ci` for deterministic installs

## Additional Don'ts

- DON'T skip `nuxi typecheck` -- plain `tsc` misses Nuxt auto-import types
- DON'T use `nuxt dev` for E2E tests in CI -- build and preview the production output
- DON'T install all Playwright browsers -- use `--with-deps chromium`
