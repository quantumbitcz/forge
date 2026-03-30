# rustdoc

## Overview

Rustdoc is the built-in Rust documentation generator. Run it via `cargo doc`. All `///` (outer doc) and `//!` (inner doc / module-level) comments are compiled into HTML. Intra-doc links (`[StructName]`, `[fn@function]`) resolve at compile time — broken links are compile errors with `--deny rustdoc::broken_intra_doc_links`. Doc tests are compiled and executed as part of `cargo test`, making every code example a first-class test. Published crates are automatically hosted on `docs.rs`.

## Architecture Patterns

### Installation & Setup

```bash
# Built-in with Rust/Cargo — no installation required

# Generate docs for the current crate and all dependencies
cargo doc --open

# Docs only for the current crate (faster)
cargo doc --no-deps --open

# Fail on broken intra-doc links and missing docs
RUSTDOCFLAGS="-D warnings -D rustdoc::broken_intra_doc_links -D rustdoc::missing_docs" \
  cargo doc --no-deps
```

**`Cargo.toml` — enforce doc coverage:**
```toml
[package]
name = "mylib"
version = "0.1.0"
edition = "2021"

[lints.rustdoc]
broken_intra_doc_links = "deny"
private_intra_doc_links = "deny"
missing_crate_level_docs = "warn"
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing crate-level docs | No `//!` comment in `lib.rs` | WARNING |
| Broken intra-doc link | `[Foo]` pointing to non-existent item | CRITICAL |
| Doc test failure | ```` ```rust ```` block that fails to compile/run | CRITICAL |
| Missing `# Errors` section | Public function returning `Result` without errors documented | WARNING |
| Missing `# Panics` section | Public function that can panic without documenting it | WARNING |
| Missing `# Safety` section | `unsafe fn` without safety contract | CRITICAL |

### Configuration Patterns

**Crate-level documentation (`src/lib.rs`):**
```rust
//! # MyLib
//!
//! `mylib` provides high-performance serialization utilities.
//!
//! ## Quick Start
//!
//! ```rust
//! use mylib::Serializer;
//!
//! let s = Serializer::new();
//! let bytes = s.serialize(&42u32);
//! assert_eq!(bytes.len(), 4);
//! ```
//!
//! ## Feature Flags
//!
//! - `serde` — enables Serde integration (enabled by default)
//! - `async` — enables async serialization via Tokio
```

**Item-level documentation with all standard sections:**
```rust
/// Serializes a value into a byte vector.
///
/// Uses little-endian byte order for primitive types.
///
/// # Arguments
///
/// * `value` — The value to serialize. Must implement [`Serialize`].
///
/// # Returns
///
/// A heap-allocated byte vector containing the serialized representation.
///
/// # Errors
///
/// Returns [`SerializeError::Overflow`] if the serialized size exceeds
/// `usize::MAX / 2`, which prevents allocation failures on 32-bit targets.
///
/// # Panics
///
/// Panics if the internal buffer cannot grow (out of memory).
///
/// # Examples
///
/// ```rust
/// # use mylib::serialize;
/// let bytes = serialize(&0xDEAD_BEEFu32).unwrap();
/// assert_eq!(bytes, vec![0xEF, 0xBE, 0xAD, 0xDE]);
/// ```
pub fn serialize<T: Serialize>(value: &T) -> Result<Vec<u8>, SerializeError> {
```

**Intra-doc links:**
```rust
/// Wraps a [`Serializer`] with a buffer size hint.
///
/// See also [`Serializer::with_capacity`] and [`DeserializeError`].
pub struct BufferedSerializer { ... }
```

**Hidden doc test setup (`# ` prefix hides line from rendered output but includes in test):**
```rust
/// ```rust
/// # use mylib::Serializer;  // hidden setup line
/// let s = Serializer::new();
/// assert!(s.is_empty());
/// ```
```

**`#[doc(hidden)]` — exclude from public docs:**
```rust
#[doc(hidden)]
pub fn __private_macro_helper() {}
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Check docs build (deny warnings)
  run: |
    RUSTDOCFLAGS="-D warnings -D rustdoc::broken_intra_doc_links" \
      cargo doc --no-deps --all-features

- name: Run doc tests
  run: cargo test --doc

- name: Deploy to GitHub Pages (on main)
  if: github.ref == 'refs/heads/main'
  run: |
    cp -r target/doc ./public
    echo '<meta http-equiv="refresh" content="0; url=mylib">' > public/index.html
```

## Performance

- `cargo doc --no-deps` skips regenerating dependency docs and is 5-10x faster than the full `cargo doc`.
- Doc tests compile each example as a separate binary — 50+ doc tests add noticeable CI time. Group related examples in fewer blocks using `#` hidden setup.
- Use `cargo doc --target-dir /tmp/target` in CI to avoid polluting the project's `target/` directory.
- On `docs.rs`, feature flags are available via `[package.metadata.docs.rs]` in `Cargo.toml`:
  ```toml
  [package.metadata.docs.rs]
  all-features = true
  rustdoc-args = ["--cfg", "docsrs"]
  ```

## Security

- Doc tests execute arbitrary Rust code at test time — ensure examples don't make network calls or write to the filesystem in CI.
- `#[doc(cfg(...))]` attribute gates can reveal internal feature combinations. Audit which features are documented publicly on `docs.rs`.
- Avoid embedding secrets, internal hostnames, or production credentials in doc examples — they appear on `docs.rs` for published crates.

## Testing

```bash
# Generate docs without opening browser
cargo doc --no-deps

# Run all doc tests
cargo test --doc

# Run doc tests for a specific module
cargo test --doc -- serializer

# Deny all rustdoc warnings (use in CI)
RUSTDOCFLAGS="-D warnings" cargo doc --no-deps

# Deny broken links specifically
RUSTDOCFLAGS="-D rustdoc::broken_intra_doc_links" cargo doc --no-deps

# Generate docs with all features
cargo doc --no-deps --all-features
```

## Dos

- Start `lib.rs` with `//!` module-level docs introducing the crate's purpose, quick-start example, and feature flag inventory.
- Document `# Errors`, `# Panics`, and `# Safety` sections on every public function where they apply — these are the most critical contracts for callers.
- Write doc tests for every major code path — they are compiled and run by `cargo test`, preventing stale examples.
- Enable `rustdoc::broken_intra_doc_links = "deny"` in `Cargo.toml` — broken links are caught at compile time before CI.
- Use `#` prefix to hide boilerplate setup in doc examples — keep the visible portion minimal and focused on the demonstrated behavior.
- Set `[package.metadata.docs.rs]` with `all-features = true` to ensure all feature-gated APIs appear on `docs.rs`.

## Don'ts

- Don't skip the `# Safety` section on `unsafe fn` — it is the only documentation of the invariants callers must uphold.
- Don't use `````rust,ignore````` on examples that could realistically compile — `ignore` hides broken examples from `cargo test`.
- Don't rely only on `cargo doc` to check for issues — run `cargo test --doc` separately to catch runtime failures in examples.
- Don't use `#[doc(hidden)]` on items that are part of public macros' expansion — they must remain accessible for macro users even if undocumented.
- Don't commit `target/doc/` to the repository — it is large and regenerated on every build.
- Don't document panics or errors as "should not happen" — document the actual condition that triggers each; if it truly cannot happen, explain why.
