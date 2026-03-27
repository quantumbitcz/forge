# GitLab CI with React

> Extends `modules/ci-cd/gitlab-ci.md` with React + Vite CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: oven/bun:latest

stages:
  - validate
  - build
  - test

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - node_modules/

validate:
  stage: validate
  script:
    - bun install --frozen-lockfile
    - bun run lint

build:
  stage: build
  script:
    - bun install --frozen-lockfile
    - bun run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 hour

test:
  stage: test
  script:
    - bun install --frozen-lockfile
    - bun run test
```

## Framework-Specific Patterns

### Node.js Alternative

```yaml
image: node:22-alpine

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - node_modules/
    - .npm/

validate:
  stage: validate
  script:
    - npm ci --cache .npm
    - npm run lint
```

### Playwright E2E Tests

```yaml
e2e:
  stage: test
  image: mcr.microsoft.com/playwright:v1.48.0-noble
  script:
    - bun install --frozen-lockfile
    - bun run build
    - bunx playwright test
  artifacts:
    when: on_failure
    paths:
      - playwright-report/
    expire_in: 7 days
```

Use Microsoft's Playwright Docker image which includes pre-installed browsers and system dependencies.

### Docker Image Publishing

```yaml
publish:
  stage: deploy
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO use `oven/bun:latest` image for Bun-based projects or `node:22-alpine` for npm/pnpm
- DO cache `node_modules/` keyed by branch slug to avoid cross-branch pollution
- DO use the official Playwright Docker image for E2E tests -- it avoids browser install issues
- DO upload test artifacts with `when: on_failure` for debugging

## Additional Don'ts

- DON'T install Playwright browsers manually in CI when using the Playwright Docker image
- DON'T cache `dist/` -- use artifacts to pass build output between stages
- DON'T omit `--frozen-lockfile` in CI pipelines
