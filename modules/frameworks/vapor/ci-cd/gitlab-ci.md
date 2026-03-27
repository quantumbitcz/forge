# GitLab CI with Vapor

> Extends `modules/ci-cd/gitlab-ci.md` with Vapor/Swift CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
image: swift:6.0

stages:
  - build
  - test
  - publish

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .build/

build:
  stage: build
  script:
    - swift build -c release

test:
  stage: test
  services:
    - postgres:16-alpine
  variables:
    POSTGRES_DB: test
    POSTGRES_USER: test
    POSTGRES_PASSWORD: test
    DATABASE_URL: postgresql://test:test@postgres:5432/test
  script:
    - swift run App migrate --yes
    - swift test

publish:
  stage: publish
  image: docker:latest
  services:
    - docker:dind
  script:
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

- DO cache `.build/` for faster Swift compilation
- DO run Fluent migrations before tests
- DO use PostgreSQL service for integration tests
- DO build with `-c release` for production binaries

## Additional Don'ts

- DON'T skip migration verification in CI
- DON'T use debug builds for production artifacts
- DON'T cache without key rotation
