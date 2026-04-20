# GitHub Actions with Axum

> Extends `modules/ci-cd/github-actions.md` with Axum/Rust CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2

      - run: cargo clippy -- -D warnings
      - run: cargo test
      - run: cargo build --release
```

## Framework-Specific Patterns

### Rust Cache

```yaml
- uses: Swatinem/rust-cache@v2
  with:
    cache-on-failure: true
```

`Swatinem/rust-cache` caches `~/.cargo` and `target/`. Enable `cache-on-failure` so failed builds still populate the cache for the next run.

### sccache for Distributed Caching

```yaml
- name: Install sccache
  uses: mozilla-actions/sccache-action@v0.0.4
- run: cargo build --release
  env:
    SCCACHE_GHA_ENABLED: true
    RUSTC_WRAPPER: sccache
```

### Docker Image Publishing

```yaml
publish:
  needs: test
  if: github.ref == 'refs/heads/main'
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: docker/build-push-action@v6
      with:
        context: .
        push: true
        tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

### Static Binary Build

```yaml
- run: cargo build --release --target x86_64-unknown-linux-musl
  env:
    RUSTFLAGS: '-C target-feature=+crt-static'
```

Static linking produces a single binary that runs on `scratch` or `distroless` Docker images.

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
```

## Additional Dos

- DO use `Swatinem/rust-cache` for cargo build caching
- DO run `cargo clippy -- -D warnings` to enforce lint-free code
- DO use `sccache` for shared compilation caching across workflows
- DO build with `--release` for production binaries

## Additional Don'ts

- DON'T skip `cargo clippy` -- it catches common Rust pitfalls
- DON'T cache `target/debug` in CI -- only cache dependencies
- DON'T use `cargo build` without `--release` for production images
