# CircleCI with Angular

> Extends `modules/ci-cd/circleci.md` with Angular CLI CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  node: circleci/node@6.1
  browser-tools: circleci/browser-tools@1.4

executors:
  node-browser:
    docker:
      - image: cimg/node:22.0-browsers
    resource_class: medium

jobs:
  build-and-test:
    executor: node-browser
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run: npx ng lint
      - run: npx ng test --no-watch --browsers=ChromeHeadless
      - run: npx ng build --configuration production
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

### Browser Image for Karma

Use `cimg/node:22.0-browsers` which includes Chrome. This avoids manual Chromium installation and ensures browser compatibility for Karma tests.

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
    - run: npx playwright test
    - store_artifacts:
        path: playwright-report
        destination: e2e-report
```

### Docker Image Publishing

```yaml
publish:
  executor: node-browser
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

- DO use `cimg/node:22.0-browsers` for Karma tests -- it includes Chrome
- DO use `persist_to_workspace` to pass build artifacts between jobs
- DO use the Playwright Docker image for E2E test jobs
- DO use `--configuration production` for AOT builds

## Additional Don'ts

- DON'T use the bare `cimg/node` image for Karma tests -- it lacks browser binaries
- DON'T install Chrome manually when `cimg/node:*-browsers` is available
- DON'T use `machine` executor for Angular builds -- Docker executor is faster
