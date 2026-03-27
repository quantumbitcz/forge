# Bitbucket Pipelines with Angular

> Extends `modules/ci-cd/bitbucket-pipelines.md` with Angular CLI CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: node:22

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
          - npx ng lint
          - npx ng test --no-watch --browsers=ChromeHeadless

    - step:
        name: Build
        caches:
          - npm
        script:
          - npm ci
          - npx ng build --configuration production
        artifacts:
          - dist/**
```

Note: Use `node:22` (not Alpine) because Karma requires Chromium and its system libraries.

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
            - npx ng build --configuration production
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
        image: node:22-alpine
        caches:
          - npm
        script:
          - npm ci
          - npx ng lint
    - step:
        name: Test
        image: node:22
        caches:
          - npm
        script:
          - npm ci
          - npx ng test --no-watch --browsers=ChromeHeadless
```

Use Alpine for lint (no browser needed) and full Node image for tests (Chromium required).

## Scaffolder Patterns

```yaml
patterns:
  pipeline: "bitbucket-pipelines.yml"
```

## Additional Dos

- DO use `node:22` (not Alpine) for test steps that need Chromium
- DO use `parallel` for independent lint and test steps
- DO build with `--configuration production` for AOT compilation
- DO define custom npm cache path for faster installs

## Additional Don'ts

- DON'T use `node:22-alpine` for Karma tests -- it lacks browser dependencies
- DON'T forget `services: [docker]` when building Docker images
- DON'T exceed the 2GB artifact limit -- use `dist/**` specifically
