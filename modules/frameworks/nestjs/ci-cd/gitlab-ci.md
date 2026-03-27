# GitLab CI with NestJS

> Extends `modules/ci-cd/gitlab-ci.md` with NestJS CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: node:22-slim

stages:
  - build
  - test
  - publish

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .npm/

before_script:
  - npm ci --cache .npm --prefer-offline
```

## Framework-Specific Patterns

### Build and Lint

```yaml
build:
  stage: build
  script:
    - npm run lint
    - npm run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 hour
```

### Unit and E2E Tests

```yaml
unit-test:
  stage: test
  script:
    - npm test -- --coverage
  artifacts:
    reports:
      junit: report.xml

e2e-test:
  stage: test
  services:
    - postgres:16-alpine
  variables:
    POSTGRES_DB: test
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://test:test@postgres:5432/test
  script:
    - npm run test:e2e
```

### Docker Image Publishing

```yaml
publish:
  stage: publish
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

- DO run `nest build` in CI to verify compilation and decorator validation
- DO export `dist/` as an artifact between build and test stages
- DO run E2E tests with PostgreSQL service containers
- DO cache `.npm/` for faster dependency installs

## Additional Don'ts

- DON'T skip the build stage -- NestJS modules are wired at compile time
- DON'T cache `node_modules/` directly
- DON'T run E2E tests without database services
