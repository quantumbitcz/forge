# GitHub Actions with React

> Extends `modules/ci-cd/github-actions.md` with React + Vite CI patterns.
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

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Lint
        run: bun run lint

      - name: Test
        run: bun run test

      - name: Build
        run: bun run build

      - name: Upload build artifact
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
```

## Framework-Specific Patterns

### Node.js / npm / pnpm Alternative

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 22
    cache: npm     # or: pnpm

- run: npm ci      # or: pnpm install --frozen-lockfile
- run: npm run build
```

Use `npm ci` (not `npm install`) in CI for deterministic installs. For pnpm, add `uses: pnpm/action-setup@v4` before `setup-node`.

### Playwright E2E Tests

```yaml
e2e:
  needs: build
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: oven-sh/setup-bun@v2
    - run: bun install --frozen-lockfile
    - run: bunx playwright install --with-deps chromium

    - name: Download build
      uses: actions/download-artifact@v4
      with:
        name: dist
        path: dist/

    - name: Run E2E tests
      run: bunx playwright test
      env:
        BASE_URL: http://localhost:4173

    - uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: playwright-report
        path: playwright-report/
```

### Dependency Caching (Bun)

```yaml
- uses: oven-sh/setup-bun@v2
  with:
    bun-version: latest
# Bun caches are handled automatically by setup-bun
```

The `oven-sh/setup-bun` action caches `~/.bun/install/cache` automatically. No manual cache step needed.

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
  e2e_workflow: ".github/workflows/e2e.yml"
```

## Additional Dos

- DO use `--frozen-lockfile` (Bun/pnpm) or `npm ci` for reproducible CI builds
- DO upload Playwright reports as artifacts on failure for debugging
- DO cache dependencies via the setup action's built-in caching
- DO run lint, test, and build as separate steps for clear failure identification

## Additional Don'ts

- DON'T use `bun install` without `--frozen-lockfile` in CI -- it may update the lockfile
- DON'T install all Playwright browsers when only testing Chromium -- use `--with-deps chromium`
- DON'T skip `tsc --noEmit` in CI -- runtime may work despite type errors
