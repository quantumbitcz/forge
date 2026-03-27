# CircleCI with Vue / Nuxt

> Extends `modules/ci-cd/circleci.md` with Vue 3 / Nuxt 3 CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  node: circleci/node@6.1

executors:
  node:
    docker:
      - image: cimg/node:22.0
    resource_class: medium

jobs:
  build-and-test:
    executor: node
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run: npm run lint
      - run: npx nuxi typecheck
      - run: npm run test
      - run: npm run build
      - persist_to_workspace:
          root: .
          paths:
            - .output/

workflows:
  ci:
    jobs:
      - build-and-test
```

## Framework-Specific Patterns

### Playwright E2E Tests

```yaml
e2e:
  docker:
    - image: mcr.microsoft.com/playwright:v1.48.0-noble
  steps:
    - checkout
    - run: npm ci
    - attach_workspace:
        at: .
    - run: |
        npx nuxt preview &
        npx wait-on http://localhost:3000
        npx playwright test
    - store_artifacts:
        path: playwright-report
        destination: e2e-report
```

### Docker Image Publishing

```yaml
publish:
  executor: node
  steps:
    - checkout
    - attach_workspace:
        at: .
    - setup_remote_docker:
        docker_layer_caching: true
    - run: |
        docker build -t $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1 .
        docker push $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use `persist_to_workspace` to pass `.output/` between jobs
- DO run `nuxi typecheck` for Nuxt auto-import type validation
- DO use `nuxt preview` with `wait-on` for E2E testing against production builds
- DO use the Playwright Docker image for E2E test jobs

## Additional Don'ts

- DON'T manually cache `node_modules` when using the Node orb
- DON'T use `nuxt dev` for E2E tests -- build and preview instead
- DON'T use `machine` executor for simple frontend builds
