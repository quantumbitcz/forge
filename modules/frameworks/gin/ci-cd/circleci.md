# CircleCI with Gin

> Extends `modules/ci-cd/circleci.md` with Gin/Go CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  go: circleci/go@1.11

jobs:
  test:
    docker:
      - image: cimg/go:1.23
      - image: cimg/postgres:16.0
        environment:
          POSTGRES_DB: test
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
    steps:
      - checkout
      - go/load-cache
      - go/mod-download
      - go/save-cache
      - run: go vet ./...
      - run: golangci-lint run
      - run:
          command: go test ./... -race -coverprofile=coverage.out
          environment:
            DATABASE_URL: postgresql://test:test@localhost:5432/test
      - store_test_results:
          path: reports

workflows:
  ci:
    jobs:
      - test
```

## Framework-Specific Patterns

### Go Module Caching

```yaml
- go/load-cache
- go/mod-download
- go/save-cache
```

The CircleCI Go orb caches `~/go/pkg/mod` and `~/.cache/go-build` automatically.

### Docker Image Publishing

```yaml
publish:
  docker:
    - image: cimg/go:1.23
  steps:
    - checkout
    - setup_remote_docker:
        docker_layer_caching: true
    - run: docker build -t $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1 .
    - run: docker push $CIRCLE_PROJECT_REPONAME:$CIRCLE_SHA1
```

### Static Binary Build

```yaml
- run:
    name: Build static binary
    command: CGO_ENABLED=0 GOOS=linux go build -o app ./cmd/server
```

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use the CircleCI Go orb for standardized caching
- DO use secondary service container for PostgreSQL
- DO run `go vet` and `golangci-lint` before tests
- DO use `-race` flag to detect data races

## Additional Don'ts

- DON'T cache `~/go/pkg/mod` manually when using the Go orb
- DON'T skip `go vet` -- it catches common Go mistakes
- DON'T build with CGO enabled when targeting `scratch` Docker images
- DON'T use `machine` executor for Go builds -- `docker` executor is sufficient
