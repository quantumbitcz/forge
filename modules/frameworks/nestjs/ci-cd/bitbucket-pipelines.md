# Bitbucket Pipelines with NestJS

> Extends `modules/ci-cd/bitbucket-pipelines.md` with NestJS CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: node:22-slim

definitions:
  caches:
    npm: ~/.npm

pipelines:
  default:
    - step:
        name: Build and Test
        caches:
          - npm
        script:
          - npm ci
          - npm run lint
          - npm run build
          - npm test -- --coverage
        artifacts:
          - dist/**
```

## Framework-Specific Patterns

### Parallel Build and E2E

```yaml
- parallel:
    - step:
        name: Unit Tests
        caches:
          - npm
        script:
          - npm ci
          - npm run build
          - npm test -- --coverage
    - step:
        name: E2E Tests
        caches:
          - npm
        services:
          - postgres
        script:
          - npm ci
          - npm run build
          - npm run test:e2e
        environment:
          DATABASE_URL: postgresql://test:test@localhost:5432/test

definitions:
  services:
    postgres:
      image: postgres:16-alpine
      variables:
        POSTGRES_DB: test
        POSTGRES_USER: test
        POSTGRES_PASSWORD: test
```

### Docker Image Publishing

```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build and Push Image
          services:
            - docker
          script:
            - docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
            - docker build -t $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT .
            - docker push $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "bitbucket-pipelines.yml"
```

## Additional Dos

- DO define a custom `npm` cache for dependency caching
- DO run `nest build` before tests in every step
- DO use `parallel` steps for independent unit and E2E tests
- DO export `dist/` as artifacts for downstream steps

## Additional Don'ts

- DON'T skip the build step -- NestJS requires compilation
- DON'T forget `services: [postgres]` for E2E tests
- DON'T cache `node_modules/` -- use npm download cache
