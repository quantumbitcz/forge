# GitLab CI with Gin

> Extends `modules/ci-cd/gitlab-ci.md` with Gin/Go CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
image: golang:1.23

stages:
  - lint
  - test
  - publish

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .go/pkg/mod/

variables:
  GOPATH: "$CI_PROJECT_DIR/.go"
  GOMODCACHE: "$CI_PROJECT_DIR/.go/pkg/mod"

lint:
  stage: lint
  script:
    - go vet ./...
    - go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    - golangci-lint run

test:
  stage: test
  script:
    - go test ./... -race -coverprofile=coverage.out
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage.out

publish:
  stage: publish
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO set `GOMODCACHE` to a project-local directory for caching
- DO run `go vet` and `golangci-lint` in a dedicated lint stage
- DO use `-race` flag for test execution
- DO cache Go module downloads

## Additional Don'ts

- DON'T cache the entire `GOPATH` -- only cache module downloads
- DON'T skip `go vet` in CI
- DON'T build with CGO when targeting static binaries
