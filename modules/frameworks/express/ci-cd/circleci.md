# CircleCI with Express

> Extends `modules/ci-cd/circleci.md` with Express/Node.js CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  node: circleci/node@6.1

jobs:
  test:
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
      - run: npx eslint .
      - run:
          command: npm test -- --coverage
          environment:
            DATABASE_URL: postgresql://test:test@localhost:5432/test
            NODE_ENV: test
      - store_test_results:
          path: reports

workflows:
  ci:
    jobs:
      - test
```

## Framework-Specific Patterns

### Node Orb Caching

```yaml
- node/install-packages:
    pkg-manager: npm
    cache-path: ~/.npm
```

The CircleCI Node orb handles caching automatically. It caches `~/.npm` keyed by `package-lock.json`.

### Docker Image Publishing

```yaml
publish:
  docker:
    - image: cimg/node:22.0
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: true
    - run: docker build -t $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1 .
    - run: docker push $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use the CircleCI Node orb for standardized caching
- DO use secondary service container for PostgreSQL
- DO use `store_test_results` for CircleCI test insights
- DO set `NODE_ENV=test` in test job environment

## Additional Don'ts

- DON'T use `machine` executor for Node.js builds -- `docker` executor starts faster
- DON'T skip `setup_remote_docker` for Docker image builds
- DON'T cache `node_modules/` directly -- use the npm orb cache strategy
