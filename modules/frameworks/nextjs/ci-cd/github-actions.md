# GitHub Actions with Next.js

> Extends `modules/ci-cd/github-actions.md` with Next.js CI patterns.
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
      - run: npm run lint
      - run: npm run build
      - run: npm test
```

## Framework-Specific Patterns

### Next.js Build Cache

```yaml
- uses: actions/cache@v4
  with:
    path: .next/cache
    key: nextjs-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}-${{ hashFiles('**/*.ts', '**/*.tsx') }}
    restore-keys: |
      nextjs-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}-
      nextjs-${{ runner.os }}-
```

Cache `.next/cache` to speed up subsequent builds. The cache key includes both dependency and source file hashes.

### Vercel Deployment

```yaml
deploy:
  needs: build
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: amondnet/vercel-action@v25
      with:
        vercel-token: ${{ secrets.VERCEL_TOKEN }}
        vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
        vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
        vercel-args: '--prod'
```

### Self-Hosted Docker Publish

```yaml
publish:
  needs: build
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

- DO cache `.next/cache` for faster incremental builds
- DO run `next lint` in CI -- it catches Next.js-specific issues
- DO run `next build` to validate Server Components, metadata, and route segments
- DO use GHA cache for both npm dependencies and Next.js build cache

## Additional Don'ts

- DON'T skip the build step -- Next.js validates Server/Client component boundaries at build time
- DON'T cache `.next/` (the full output) -- only cache `.next/cache`
- DON'T deploy without running `next build` -- it catches SSR/SSG errors
