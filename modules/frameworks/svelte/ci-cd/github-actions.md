# GitHub Actions with Svelte 5 (Standalone SPA)

> Extends `modules/ci-cd/github-actions.md` with Svelte 5 + Vite CI patterns.
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

      - run: bun install --frozen-lockfile

      - name: Lint
        run: bun run lint

      - name: Svelte Check
        run: bunx svelte-check --tsconfig ./tsconfig.json

      - name: Test
        run: bun run test

      - name: Build
        run: bun run build

      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: dist/
```

## Framework-Specific Patterns

### Svelte Check as a Separate Step

Run `svelte-check` as its own step so template type errors are clearly visible in the CI log. It validates `.svelte` file types that `tsc` cannot check.

### Static Site Deployment (GitHub Pages)

```yaml
deploy:
  needs: build
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  permissions:
    pages: write
    id-token: write
  environment:
    name: github-pages
    url: ${{ steps.deployment.outputs.page_url }}
  steps:
    - uses: actions/download-artifact@v4
      with:
        name: dist
        path: dist/
    - uses: actions/configure-pages@v5
    - uses: actions/upload-pages-artifact@v3
      with:
        path: dist/
    - id: deployment
      uses: actions/deploy-pages@v4
```

Svelte standalone SPAs produce static files ideal for GitHub Pages, Netlify, or Vercel.

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
    - uses: actions/download-artifact@v4
      with:
        name: dist
        path: dist/
    - run: bunx playwright test
    - uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: playwright-report
        path: playwright-report/
```

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO run `svelte-check` as a dedicated CI step for clear error visibility
- DO upload `dist/` artifacts for downstream deployment
- DO use `--frozen-lockfile` for reproducible builds
- DO use GitHub Pages deployment for static Svelte SPAs

## Additional Don'ts

- DON'T skip `svelte-check` -- it catches template-level type errors that `tsc` misses
- DON'T use `vite dev` in CI -- build and preview for testing
- DON'T install all Playwright browsers -- use `--with-deps chromium`
