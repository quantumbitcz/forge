# CircleCI with React

> Extends `modules/ci-cd/circleci.md` with React + Vite CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  node: circleci/node@6.1
  docker: circleci/docker@2.6

executors:
  bun:
    docker:
      - image: oven/bun:latest
    resource_class: medium

jobs:
  build-and-test:
    executor: bun
    steps:
      - checkout
      - run: bun install --frozen-lockfile
      - run: bun run lint
      - run: bun run test
      - run: bun run build
      - persist_to_workspace:
          root: .
          paths:
            - dist/

workflows:
  ci:
    jobs:
      - build-and-test
```

## Framework-Specific Patterns

### Node.js with CircleCI Node Orb

```yaml
jobs:
  build:
    executor:
      name: node/default
      tag: "22"
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run: npm run build
```

The Node orb handles caching and package installation automatically.

### Playwright E2E Tests

```yaml
e2e:
  docker:
    - image: mcr.microsoft.com/playwright:v1.48.0-noble
  steps:
    - checkout
    - run: npm ci
    - run: npx playwright test
    - store_artifacts:
        path: playwright-report
        destination: e2e-report
```

### Docker Image Publishing

```yaml
publish:
  executor: bun
  steps:
    - checkout
    - attach_workspace:
        at: .
    - setup_remote_docker:
        docker_layer_caching: true
    - docker/build:
        image: $CIRCLE_PROJECT_REPONAME
        tag: $CIRCLE_SHA1
    - docker/push:
        image: $CIRCLE_PROJECT_REPONAME
        tag: $CIRCLE_SHA1
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use `persist_to_workspace` to pass build artifacts between jobs
- DO use the Playwright Docker image for E2E jobs -- it includes all browser dependencies
- DO use `setup_remote_docker` with layer caching for Docker builds
- DO store test reports and Playwright artifacts for debugging failures

## Additional Don'ts

- DON'T manually cache `node_modules` when using the Node orb -- it handles caching
- DON'T install browsers in the build executor -- use a pre-built Playwright image
- DON'T use `machine` executor for simple frontend builds -- Docker executor is faster
