# GitLab CI with Angular

> Extends `modules/ci-cd/gitlab-ci.md` with Angular CLI CI patterns.
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
    - npx ng lint

build:
  stage: build
  script:
    - npm ci --cache .npm
    - npx ng build --configuration production
  artifacts:
    paths:
      - dist/
    expire_in: 1 hour

test:
  stage: test
  image: node:22
  before_script:
    - apt-get update && apt-get install -y chromium
    - export CHROME_BIN=/usr/bin/chromium
  script:
    - npm ci --cache .npm
    - npx ng test --no-watch --browsers=ChromeHeadless
```

## Framework-Specific Patterns

### Chromium for Karma Tests

Angular's default test runner (Karma) requires a browser. In GitLab CI, install Chromium and set `CHROME_BIN`. Use the full `node:22` image (not `alpine`) for browser compatibility.

### Playwright E2E Tests

```yaml
e2e:
  stage: test
  image: mcr.microsoft.com/playwright:v1.48.0-noble
  script:
    - npm ci
    - npx ng build --configuration production
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

- DO install Chromium explicitly for Karma tests in CI -- Alpine images lack browser binaries
- DO use `--configuration production` for AOT builds in the build stage
- DO use the Playwright Docker image for E2E tests to avoid browser installation issues
- DO cache `.npm/` alongside `node_modules/` for faster installs

## Additional Don'ts

- DON'T use `node:22-alpine` for test stages that need Chromium -- Alpine lacks browser deps
- DON'T run Karma with `--watch` in CI -- use `--no-watch` for single-run execution
- DON'T cache `dist/` -- use artifacts to pass build output between stages
