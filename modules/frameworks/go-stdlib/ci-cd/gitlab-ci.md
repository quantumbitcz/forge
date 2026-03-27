# GitLab CI with Go stdlib

> Extends `modules/ci-cd/gitlab-ci.md` with Go stdlib CI patterns.
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
    - go install honnef.co/go/tools/cmd/staticcheck@latest
    - staticcheck ./...

test:
  stage: test
  script:
    - go test ./... -race -coverprofile=coverage.out

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

- DO set `GOMODCACHE` for caching module downloads
- DO use `staticcheck` as the primary linter for stdlib projects
- DO use `-race` for test execution

## Additional Don'ts

- DON'T cache the entire `GOPATH`
- DON'T skip `go vet` in CI
