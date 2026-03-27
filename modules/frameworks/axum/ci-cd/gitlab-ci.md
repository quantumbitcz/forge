# GitLab CI with Axum

> Extends `modules/ci-cd/gitlab-ci.md` with Axum/Rust CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: rust:latest

stages:
  - lint
  - test
  - publish

cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - target/
    - .cargo/

variables:
  CARGO_HOME: "$CI_PROJECT_DIR/.cargo"

lint:
  stage: lint
  script:
    - rustup component add clippy
    - cargo clippy -- -D warnings

test:
  stage: test
  script:
    - cargo test

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

## Framework-Specific Patterns

### Cargo Caching

```yaml
cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths:
    - target/
    - .cargo/registry/
    - .cargo/git/
```

Cache both `target/` (compiled dependencies) and `.cargo/` (downloaded crate sources).

### Static Binary Build

```yaml
build-static:
  stage: test
  image: rust:latest
  script:
    - rustup target add x86_64-unknown-linux-musl
    - cargo build --release --target x86_64-unknown-linux-musl
  artifacts:
    paths:
      - target/x86_64-unknown-linux-musl/release/app
```

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO cache `target/` and `.cargo/` for faster builds
- DO set `CARGO_HOME` to the project directory for caching
- DO run `cargo clippy` in a separate lint stage
- DO build static binaries for minimal Docker images

## Additional Don'ts

- DON'T skip clippy -- it catches unsafe patterns and performance issues
- DON'T cache the entire target directory across branches without key rotation
- DON'T build in debug mode for production artifacts
