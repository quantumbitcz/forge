# CircleCI with NestJS

> Extends `modules/ci-cd/circleci.md` with NestJS CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  node: circleci/node@6.1

jobs:
  build-and-test:
    docker:
      - image: cimg/node:22.0
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run: npm run lint
      - run: npm run build
      - run:
          command: npm test -- --coverage
      - store_test_results:
          path: reports

  e2e-test:
    docker:
      - image: cimg/node:22.0
      - image: cimg/postgres:16.0
        environment:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run:
          command: npm run test:e2e
          environment:
            DATABASE_URL: postgresql://test:test@localhost:5432/test

workflows:
  ci:
    jobs:
      - build-and-test
      - e2e-test:
          requires:
            - build-and-test
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use the CircleCI Node orb for standardized caching
- DO run `nest build` to verify compilation before tests
- DO use secondary service container for PostgreSQL E2E tests
- DO use `store_test_results` for CircleCI test insights

## Additional Don'ts

- DON'T skip E2E tests that validate NestJS module wiring
- DON'T use `machine` executor for Node.js builds
- DON'T cache `node_modules/` directly
