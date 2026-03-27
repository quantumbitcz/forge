# CircleCI with Next.js

> Extends `modules/ci-cd/circleci.md` with Next.js CI patterns.
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
      - restore_cache:
          keys:
            - nextjs-cache-{{ checksum "package-lock.json" }}
      - run: npm run lint
      - run: npm run build
      - save_cache:
          key: nextjs-cache-{{ checksum "package-lock.json" }}
          paths:
            - .next/cache
      - run: npm test
      - store_test_results:
          path: reports

workflows:
  ci:
    jobs:
      - build-and-test
```

## Framework-Specific Patterns

### Next.js Build Cache

```yaml
- restore_cache:
    keys:
      - nextjs-cache-{{ checksum "package-lock.json" }}
      - nextjs-cache-
- run: npm run build
- save_cache:
    key: nextjs-cache-{{ checksum "package-lock.json" }}
    paths:
      - .next/cache
```

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

- DO cache `.next/cache` for faster incremental builds
- DO use the Node orb for standardized dependency caching
- DO run `next lint` and `next build` in CI
- DO use `store_test_results` for test insights

## Additional Don'ts

- DON'T skip the build step -- it validates SSR/SSG correctness
- DON'T cache all of `.next/` -- only cache `.next/cache`
- DON'T use `machine` executor for Node.js builds
