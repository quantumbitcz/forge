# GitHub Actions with SvelteKit

> Extends `modules/ci-cd/github-actions.md` with SvelteKit CI patterns.
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
          name: build
          path: build/
```

## Framework-Specific Patterns

### Playwright E2E Tests

```yaml
e2e:
  needs: build
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: oven-sh/setup-bun@v2
    - run: bun install --frozen-lockfile
    - run: bunx playwright install --with-deps chromium
    - uses: actions/download-artifact@v4
      with:
        name: build
        path: build/
    - name: Start server and test
      run: |
        node build/index.js &
        bunx wait-on http://localhost:3000
        bunx playwright test
    - uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: playwright-report
        path: playwright-report/
```

### Static Adapter (GitHub Pages)

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
  steps:
    - uses: actions/download-artifact@v4
      with:
        name: build
        path: build/
    - uses: actions/configure-pages@v5
    - uses: actions/upload-pages-artifact@v3
      with:
        path: build/
    - uses: actions/deploy-pages@v4
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

- DO run `svelte-check` for SvelteKit-generated type validation
- DO use `adapter-node` output (`build/index.js`) for E2E testing in CI
- DO upload Playwright reports on failure
- DO use `--frozen-lockfile` for reproducible builds

## Additional Don'ts

- DON'T use `vite dev` in CI -- build with the target adapter and test the production output
- DON'T skip `svelte-check` -- it validates load function types, $app paths, and $env variables
- DON'T install all Playwright browsers -- use `--with-deps chromium`
