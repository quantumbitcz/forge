# Bitbucket Pipelines with Vue / Nuxt

> Extends `modules/ci-cd/bitbucket-pipelines.md` with Vue 3 / Nuxt 3 CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: node:22-alpine

definitions:
  caches:
    npm: ~/.npm

pipelines:
  default:
    - step:
        name: Lint and Test
        caches:
          - npm
        script:
          - npm ci
          - npm run lint
          - npx nuxi typecheck
          - npm run test

    - step:
        name: Build
        caches:
          - npm
        script:
          - npm ci
          - npm run build
        artifacts:
          - .output/**
```

## Framework-Specific Patterns

### Docker Image Publishing

```yaml
pipelines:
  branches:
    main:
      - step:
          name: Build
          caches:
            - npm
          script:
            - npm ci
            - npm run build
          artifacts:
            - .output/**

      - step:
          name: Build and Push Image
          services:
            - docker
          script:
            - docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
            - docker build -t $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT .
            - docker push $DOCKER_REGISTRY/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT
```

### Parallel Lint and Test

```yaml
- parallel:
    - step:
        name: Lint & Type Check
        caches:
          - npm
        script:
          - npm ci
          - npm run lint
          - npx nuxi typecheck
    - step:
        name: Test
        caches:
          - npm
        script:
          - npm ci
          - npm run test
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "bitbucket-pipelines.yml"
```

## Additional Dos

- DO define custom cache for npm (`~/.npm`)
- DO use `parallel` steps for independent lint and test jobs
- DO run `nuxi typecheck` alongside linting for Nuxt auto-import types
- DO use `npm ci` for deterministic installs

## Additional Don'ts

- DON'T cache `node_modules/` directly -- cache the npm global cache
- DON'T forget `services: [docker]` when building Docker images
- DON'T skip `nuxi typecheck` -- plain `tsc` misses Nuxt-generated types
