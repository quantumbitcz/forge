# CircleCI with Go stdlib

> Extends `modules/ci-cd/circleci.md` with Go stdlib CI patterns.
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

The CircleCI Go orb handles module and build caching automatically.

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

### Multi-Architecture Build

```yaml
- run:
    name: Build multi-arch
    command: |
      CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o app-amd64 ./cmd/server
      CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o app-arm64 ./cmd/server
```

Go's cross-compilation makes multi-architecture builds trivial without QEMU or Docker buildx.

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use the CircleCI Go orb for standardized module caching
- DO use secondary service container for integration test databases
- DO run `go vet` and `golangci-lint` before tests
- DO use `-race` flag to detect data races
- DO build with `CGO_ENABLED=0` for static binaries

## Additional Don'ts

- DON'T cache modules manually when using the Go orb
- DON'T skip `go vet` -- it catches common Go mistakes
- DON'T use `machine` executor for Go builds -- `docker` executor is sufficient
- DON'T build with CGO enabled when targeting `scratch` Docker images
