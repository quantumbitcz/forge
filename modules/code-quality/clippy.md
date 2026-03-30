# clippy

## Overview

Rust's built-in linter, shipped with the Rust toolchain via `rustup`. Runs as `cargo clippy` and provides 700+ lints covering correctness, performance, style, complexity, and pedantic patterns. Clippy is mandatory for any Rust codebase — it catches misuse of iterators, incorrect lifetime usage, suspicious code patterns, and performance anti-patterns that `rustc` itself does not flag. It integrates natively into the Cargo build system with zero configuration overhead for basic use.

## Architecture Patterns

### Installation & Setup

Clippy ships with `rustup` — no separate install required:

```bash
rustup component add clippy   # ensure clippy is present (default in stable toolchain)
cargo clippy                  # run with default lint set
cargo clippy --all-targets    # include tests, benchmarks, examples
cargo clippy -- -D warnings   # treat warnings as errors (recommended for CI)
```

Pin clippy behavior to a specific channel in `rust-toolchain.toml`:
```toml
[toolchain]
channel = "stable"
components = ["clippy", "rustfmt"]
```

### Rule Categories

| Lint Group | What It Checks | Default | Pipeline Severity |
|---|---|---|---|
| `clippy::correctness` | Logic errors, incorrect API usage, UB-adjacent patterns | Deny | CRITICAL |
| `clippy::suspicious` | Code that is probably wrong but not guaranteed | Warn | CRITICAL |
| `clippy::perf` | Heap allocations, iterator inefficiency, redundant clones | Warn | WARNING |
| `clippy::style` | Idiomatic Rust patterns, readability | Warn | WARNING |
| `clippy::complexity` | Overly complex expressions, unnecessary nesting | Warn | WARNING |
| `clippy::pedantic` | Strict correctness, exhaustive documentation | Allow (opt-in) | INFO |
| `clippy::nursery` | Experimental lints, not yet stable | Allow (opt-in) | INFO |
| `clippy::restriction` | Opinionated bans (e.g., no `unwrap`, no `std::println`) | Allow (opt-in) | INFO |

### Configuration Patterns

Configure in `Cargo.toml` (workspace or per-crate) or `clippy.toml`:

```toml
# Cargo.toml — workspace-level lint configuration
[workspace.lints.clippy]
pedantic = "warn"
nursery = "warn"
# Allow specific pedantic lints that are too noisy
module_name_repetitions = "allow"
must_use_candidate = "allow"

[workspace.lints.rust]
unsafe_code = "forbid"
```

Per-file suppression (use sparingly):
```rust
#[allow(clippy::too_many_arguments)]
fn build_request(a: &str, b: &str, c: u32, d: bool, e: Option<String>, f: Vec<u8>, g: u64) -> Request {
    // ...
}

// Suppress for a whole module
#![allow(clippy::wildcard_imports)]
```

`clippy.toml` for threshold customization:
```toml
# clippy.toml
too-many-arguments-threshold = 8
too-many-lines-threshold = 150
cognitive-complexity-threshold = 25
msrv = "1.75"   # minimum supported Rust version — version-gates newer lints
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Run Clippy
  run: cargo clippy --all-targets --all-features -- -D warnings

- name: Upload SARIF (optional)
  uses: actions/upload-artifact@v4
  with:
    name: clippy-results
    path: clippy-results.json
```

With SARIF output for GitHub Security tab:
```bash
cargo clippy --message-format=json 2>&1 | \
  cargo-clippy-sarif | \
  tee clippy-results.sarif
```

For workspaces, always pass `--workspace`:
```bash
cargo clippy --workspace --all-targets --all-features -- -D warnings
```

## Performance

- Clippy runs on top of the `rustc` compilation pipeline — the first run is as slow as a full compile. Subsequent runs use incremental compilation.
- `--message-format=json` skips the human-readable renderer and reduces I/O in CI.
- Disable `clippy::nursery` in CI if compile times are critical — nursery lints can be slow due to experimental analysis passes.
- In monorepos, use `cargo clippy -p <crate>` to lint a single crate during development; use `--workspace` only in CI.
- Cargo's incremental compilation cache (`target/`) must be preserved between CI runs to avoid re-analyzing unchanged crates.

## Security

Key correctness and security lints:

- `clippy::unwrap_used` (restriction) — `unwrap()` on `Option`/`Result` panics in production; prefer `?` or explicit error handling.
- `clippy::expect_used` (restriction) — same as above for `.expect()`.
- `clippy::panic` (restriction) — explicit `panic!()` calls in library code.
- `clippy::integer_arithmetic` (restriction) — arithmetic that can overflow/underflow.
- `clippy::indexing_slicing` (restriction) — array indexing that can panic on out-of-bounds.
- `clippy::transmute_ptr_to_ref` (correctness) — unsound pointer-to-reference transmutation.

Enable restriction lints selectively for library crates where panics are unacceptable:
```toml
[lib]
# In Cargo.toml for a library crate
[lints.clippy]
unwrap_used = "deny"
expect_used = "deny"
panic = "deny"
```

## Testing

```bash
# Lint all targets (including tests)
cargo clippy --all-targets -- -D warnings

# Lint only the library/binary, not tests
cargo clippy --lib -- -D warnings

# Show machine-readable output
cargo clippy --message-format=json 2>&1 | jq '.message.level'

# List all available lints
cargo clippy --list

# Check a specific lint
cargo clippy -- -W clippy::pedantic

# Suppress a lint for entire project temporarily
cargo clippy -- -A clippy::too_many_arguments
```

## Dos

- Run `cargo clippy --all-targets --all-features -- -D warnings` in CI — `--all-targets` catches issues in tests and examples, `--all-features` ensures feature-gated code is analyzed.
- Enable `clippy::pedantic` as warn (not deny) in new projects — it improves code quality without blocking the build on every minor style issue.
- Set `msrv` in `clippy.toml` to your minimum supported Rust version — it prevents clippy from suggesting APIs unavailable on older toolchains.
- Use `Cargo.toml` `[workspace.lints]` for consistent lint configuration across all crates in a workspace rather than duplicating per-crate.
- Suppress specific lints with `#[allow(clippy::lint_name)]` at the smallest scope and add a comment explaining why.

## Don'ts

- Don't run `cargo clippy` without `-- -D warnings` in CI — warnings that don't fail the build are ignored by developers and accumulate as technical debt.
- Don't use `#![allow(clippy::all)]` — it disables all lints and defeats the purpose of having clippy.
- Don't enable `clippy::restriction` as a blanket deny without reviewing each lint — restriction lints include highly opinionated rules (e.g., `else_if_without_else`) that may not apply to your codebase.
- Don't suppress `clippy::correctness` lints — they indicate genuine bugs. Investigate before suppressing.
- Don't ignore `clippy::perf` lints in hot paths — iterator chain optimizations and clone reduction can have measurable performance impact.
- Don't pin the Rust toolchain to a version older than 6 months — newer stable releases include additional correctness lints that catch real bugs.
