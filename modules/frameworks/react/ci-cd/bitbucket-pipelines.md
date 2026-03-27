# Bitbucket Pipelines with React

> Extends `modules/ci-cd/bitbucket-pipelines.md` with React + Vite CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: node:22-alpine

definitions:
  caches:
    npm: ~/.npm
    bun: ~/.bun/install/cache

pipelines:
  default:
    - step:
        name: Lint and Test
        caches:
          - npm
        script:
          - npm ci
          - npm run lint
          - npm run test

    - step:
        name: Build
        caches:
          - npm
        script:
          - npm ci
          - npm run build
        artifacts:
          - dist/**
```

## Framework-Specific Patterns

### Bun Alternative

```yaml
image: oven/bun:latest

definitions:
  caches:
    bun: ~/.bun/install/cache

pipelines:
  default:
    - step:
        caches:
          - bun
        script:
          - bun install --frozen-lockfile
          - bun run lint
          - bun run test
          - bun run build
        artifacts:
          - dist/**
```

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
            - dist/**

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
        name: Lint
        caches:
          - npm
        script:
          - npm ci
          - npm run lint
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

- DO define custom cache for npm (`~/.npm`) or Bun (`~/.bun/install/cache`)
- DO use `parallel` steps for independent lint and test jobs
- DO pass build output between steps via `artifacts`
- DO use `npm ci` (not `npm install`) for deterministic CI builds

## Additional Don'ts

- DON'T cache `node_modules/` directly -- cache the package manager's global cache instead
- DON'T exceed the 2GB artifact limit -- use `dist/**` not the entire project
- DON'T forget `services: [docker]` when building Docker images
