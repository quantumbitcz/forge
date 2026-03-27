# GitLab CI with Express

> Extends `modules/ci-cd/gitlab-ci.md` with Express/Node.js CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: node:22-slim

stages:
  - lint
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

### Lint Stage

```yaml
lint:
  stage: lint
  script:
    - npx eslint .
    - npx prettier --check .
```

### Test with Service

```yaml
test:
  stage: test
  services:
    - postgres:16-alpine
  variables:
    POSTGRES_DB: test
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://test:test@postgres:5432/test
    NODE_ENV: test
  script:
    - npm test -- --coverage
  artifacts:
    reports:
      junit: report.xml
    expire_in: 1 hour
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

- DO cache `.npm/` directory keyed by branch slug for faster installs
- DO use `npm ci --cache .npm --prefer-offline` for deterministic installs
- DO set `NODE_ENV=test` for test stages
- DO export JUnit XML for GitLab test result integration

## Additional Don'ts

- DON'T cache `node_modules/` directly -- cache the npm download cache instead
- DON'T use `npm install` in CI -- use `npm ci` for lockfile-based installs
- DON'T skip `--prefer-offline` when caching -- it avoids redundant network requests
