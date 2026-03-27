# CircleCI with Axum

> Extends `modules/ci-cd/circleci.md` with Axum/Rust CI patterns.
> Generic CircleCI conventions (orbs, executors, workspace persistence) are NOT repeated here.

## Integration Setup

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  rust: circleci/rust@1.6

jobs:
  test:
    docker:
      - image: cimg/rust:1.80
    resource_class: large
    steps:
      - checkout
      - rust/clippy:
          flags: -- -D warnings
      - rust/test
      - rust/build:
          release: true

workflows:
  ci:
    jobs:
      - test
```

## Framework-Specific Patterns

### Cargo Cache

```yaml
steps:
  - restore_cache:
      keys:
        - cargo-{{ checksum "Cargo.lock" }}
        - cargo-
  - run: cargo build --release
  - save_cache:
      key: cargo-{{ checksum "Cargo.lock" }}
      paths:
        - ~/.cargo/registry
        - ~/.cargo/git
        - target/
```

The Rust CircleCI orb handles caching automatically. For manual control, cache `~/.cargo` and `target/` keyed by `Cargo.lock`.

### Docker Image Publishing

```yaml
publish:
  docker:
    - image: cimg/rust:1.80
  resource_class: large
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
    command: |
      rustup target add x86_64-unknown-linux-musl
      cargo build --release --target x86_64-unknown-linux-musl
    environment:
      RUSTFLAGS: '-C target-feature=+crt-static'
```

Static linking with musl produces a single binary for `scratch` Docker images.

## Scaffolder Patterns

```yaml
patterns:
  config: ".circleci/config.yml"
```

## Additional Dos

- DO use `resource_class: large` -- Rust compilation is CPU-intensive
- DO use the CircleCI Rust orb for standardized toolchain setup
- DO cache `~/.cargo` and `target/` keyed by `Cargo.lock`
- DO run `cargo clippy -- -D warnings` to enforce lint-free code

## Additional Don'ts

- DON'T use `resource_class: small` for Rust builds -- they will timeout
- DON'T skip `setup_remote_docker` for Docker image builds
- DON'T cache `target/debug` in CI -- only cache release builds and dependencies
- DON'T build with `--release` for test runs unless measuring performance
