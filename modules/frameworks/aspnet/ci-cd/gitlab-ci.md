# GitLab CI with ASP.NET

> Extends `modules/ci-cd/gitlab-ci.md` with ASP.NET Core CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: mcr.microsoft.com/dotnet/sdk:9.0

stages:
  - build
  - test
  - publish

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - .nuget/

variables:
  NUGET_PACKAGES: "$CI_PROJECT_DIR/.nuget"

build:
  stage: build
  script:
    - dotnet restore
    - dotnet build --no-restore -c Release
  artifacts:
    paths:
      - "**/bin/Release/"
    expire_in: 1 hour

test:
  stage: test
  script:
    - dotnet test --no-build -c Release --logger "junit;LogFilePath=report.xml"
  artifacts:
    reports:
      junit: "**/report.xml"
```

## Framework-Specific Patterns

### Docker Image Publishing

```yaml
publish:
  stage: publish
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
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

- DO cache the NuGet packages directory via `NUGET_PACKAGES` variable
- DO use `--logger junit` for GitLab test result integration
- DO build in Release configuration for test accuracy
- DO export build artifacts between stages

## Additional Don'ts

- DON'T use Debug configuration in CI -- test against Release builds
- DON'T cache `bin/` and `obj/` across branches
- DON'T skip `dotnet restore` -- it validates package integrity
