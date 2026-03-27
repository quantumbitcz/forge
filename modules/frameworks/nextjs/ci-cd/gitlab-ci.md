# GitLab CI with Next.js

> Extends `modules/ci-cd/gitlab-ci.md` with Next.js CI patterns.
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
    - .next/cache/

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
      - .next/
    expire_in: 1 hour
```

### Test

```yaml
test:
  stage: test
  script:
    - npm test
  artifacts:
    reports:
      junit: report.xml
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

- DO cache both `.npm/` and `.next/cache/` for faster builds
- DO run `next lint` to catch framework-specific issues
- DO export `.next/` as artifacts between stages
- DO run `next build` to validate SSR/SSG correctness

## Additional Don'ts

- DON'T skip the build stage -- Next.js validates at compile time
- DON'T cache all of `.next/` in the cache config -- only `.next/cache/`
- DON'T use the build output from a different Node.js version
