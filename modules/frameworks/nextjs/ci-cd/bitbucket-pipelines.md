# Bitbucket Pipelines with Next.js

> Extends `modules/ci-cd/bitbucket-pipelines.md` with Next.js CI patterns.
> Generic Bitbucket Pipelines conventions (step definitions, deployment environments, pipes) are NOT repeated here.

## Integration Setup

```yaml
# bitbucket-pipelines.yml
image: node:22-slim

definitions:
  caches:
    npm: ~/.npm
    nextcache: .next/cache

pipelines:
  default:
    - step:
        name: Build and Test
        caches:
          - npm
          - nextcache
        script:
          - npm ci
          - npm run lint
          - npm run build
          - npm test
```

## Framework-Specific Patterns

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

- DO define custom `nextcache` pointing to `.next/cache`
- DO run `next lint` and `next build` in CI
- DO use `npm ci` for deterministic installs
- DO cache both npm and Next.js build caches

## Additional Don'ts

- DON'T skip the build step -- Next.js validates at compile time
- DON'T cache all of `.next/` -- only `.next/cache`
- DON'T use `npm install` in CI
