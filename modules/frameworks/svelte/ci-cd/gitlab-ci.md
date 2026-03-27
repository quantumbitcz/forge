# GitLab CI with Svelte 5 (Standalone SPA)

> Extends `modules/ci-cd/gitlab-ci.md` with Svelte 5 + Vite CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: oven/bun:latest

stages:
  - validate
  - build
  - deploy

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - node_modules/

validate:
  stage: validate
  script:
    - bun install --frozen-lockfile
    - bun run lint
    - bunx svelte-check --tsconfig ./tsconfig.json
    - bun run test

build:
  stage: build
  script:
    - bun install --frozen-lockfile
    - bun run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 hour
```

## Framework-Specific Patterns

### GitLab Pages Deployment

```yaml
pages:
  stage: deploy
  script:
    - bun install --frozen-lockfile
    - bun run build
    - mv dist public
  artifacts:
    paths:
      - public
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

Svelte standalone SPAs produce static files. Move `dist/` to `public/` for GitLab Pages.

### Playwright E2E Tests

```yaml
e2e:
  stage: validate
  image: mcr.microsoft.com/playwright:v1.48.0-noble
  script:
    - npm ci
    - npm run build
    - npx playwright test
  artifacts:
    when: on_failure
    paths:
      - playwright-report/
    expire_in: 7 days
```

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

- DO run `svelte-check` in the validate stage for template-level type validation
- DO use `oven/bun:latest` for Bun-based projects
- DO use GitLab Pages for static Svelte SPA deployments
- DO cache `node_modules/` keyed by branch slug

## Additional Don'ts

- DON'T skip `svelte-check` -- `tsc` alone misses `.svelte` template type errors
- DON'T cache `dist/` -- use artifacts to pass build output between stages
- DON'T use `vite dev` in CI -- build and serve the production output
