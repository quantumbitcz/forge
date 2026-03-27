# GitLab CI with Vue / Nuxt

> Extends `modules/ci-cd/gitlab-ci.md` with Vue 3 / Nuxt 3 CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: node:22-alpine

stages:
  - validate
  - build
  - test

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
    - npx nuxi typecheck

build:
  stage: build
  script:
    - npm ci --cache .npm
    - npm run build
  artifacts:
    paths:
      - .output/
    expire_in: 1 hour

test:
  stage: test
  script:
    - npm ci --cache .npm
    - npm run test
```

## Framework-Specific Patterns

### Playwright E2E Tests

```yaml
e2e:
  stage: test
  image: mcr.microsoft.com/playwright:v1.48.0-noble
  script:
    - npm ci
    - npm run build
    - npx nuxt preview &
    - npx wait-on http://localhost:3000
    - npx playwright test
  artifacts:
    when: on_failure
    paths:
      - playwright-report/
    expire_in: 7 days
```

### Static Site Deployment

```yaml
pages:
  stage: deploy
  script:
    - npm ci
    - npx nuxt generate
    - mv .output/public public
  artifacts:
    paths:
      - public
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

Use `nuxt generate` for GitLab Pages deployment. The output goes to `.output/public/`.

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

- DO run `nuxi typecheck` in the validate stage for Nuxt-generated types
- DO use the Playwright Docker image for E2E tests
- DO use `nuxt generate` for static site deployments (GitLab Pages, CDN)
- DO cache `node_modules/` and `.npm/` for faster installs

## Additional Don'ts

- DON'T use `nuxt dev` in CI -- build and preview the production output for testing
- DON'T cache `.output/` -- use artifacts to pass build output between stages
- DON'T skip `nuxi typecheck` -- plain `tsc` misses Nuxt auto-import types
