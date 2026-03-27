# Bitbucket Pipelines with Express

> Extends `modules/ci-cd/bitbucket-pipelines.md` with Express/Node.js CI patterns.
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
        name: Lint and Test
        caches:
          - npm
        script:
          - npm ci
          - npx eslint .
          - npm test -- --coverage
```

## Framework-Specific Patterns

### Parallel Lint and Test

```yaml
- parallel:
    - step:
        name: Lint
        caches:
          - npm
        script:
          - npm ci
          - npx eslint .
          - npx prettier --check .
    - step:
        name: Test
        caches:
          - npm
        script:
          - npm ci
          - npm test -- --coverage
        environment:
          NODE_ENV: test
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

- DO define a custom `npm` cache pointing to `~/.npm`
- DO use `parallel` steps for independent lint and test jobs
- DO use `npm ci` for deterministic installs
- DO set `NODE_ENV=test` for test steps

## Additional Don'ts

- DON'T cache `node_modules/` -- cache `~/.npm` and let `npm ci` install
- DON'T use `npm install` in CI pipelines
- DON'T exceed the 2GB artifact limit -- export only test reports
