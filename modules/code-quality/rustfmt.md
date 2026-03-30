# rustfmt

## Overview

Rust's official code formatter, distributed with the Rust toolchain via `rustup`. Enforces the Rust style guide with minimal configuration. Run via `cargo fmt` (formats the entire workspace) or `rustfmt` directly (single file). Use `cargo fmt -- --check` in CI to fail on unformatted code without writing. Some advanced options (e.g., `format_code_in_doc_comments`, `imports_granularity`) require nightly Rust — mark these with `# [unstable feature]` in `rustfmt.toml` and ensure the CI toolchain matches. Rustfmt is idempotent and the output is always valid Rust.

## Architecture Patterns

### Installation & Setup

```bash
# rustfmt ships with the default Rust toolchain
rustup component add rustfmt

# Verify
rustfmt --version   # e.g., rustfmt 1.8.0-stable

# For nightly-only options
rustup toolchain install nightly
rustup component add rustfmt --toolchain nightly
```

**`rustfmt.toml` (project root):**
```toml
edition = "2021"
max_width = 100
tab_spaces = 4
newline_style = "Unix"
use_small_heuristics = "Default"
imports_granularity = "Module"   # group imports by module
group_imports = "StdExternalCrate"  # stdlib, then external, then crate

# Stable options
trailing_comma = "Vertical"
match_block_trailing_comma = true
use_field_init_shorthand = true
use_try_shorthand = true
```

**Nightly-only options (require `unstable_features = true`):**
```toml
unstable_features = true
format_code_in_doc_comments = true
format_strings = false   # aggressive string formatting — evaluate carefully
wrap_comments = true
comment_width = 100
```

### Rule Categories

Rustfmt options fall into stable and unstable (nightly-only) categories:

| Option | Stability | Default | Recommendation |
|---|---|---|---|
| `edition` | Stable | `"2015"` | Set to your Cargo.toml `edition` |
| `max_width` | Stable | `100` | Keep at `100` |
| `imports_granularity` | Stable | `"Preserve"` | `"Module"` for clean import blocks |
| `group_imports` | Stable | `"Preserve"` | `"StdExternalCrate"` |
| `trailing_comma` | Stable | `"Vertical"` | Keep default |
| `format_code_in_doc_comments` | Nightly | `false` | Enable if on nightly |
| `format_strings` | Nightly | `false` | Leave `false` — often disruptive |

### Configuration Patterns

**`Cargo.toml` workspace formatting:**
```bash
# Format all crates in the workspace
cargo fmt --all

# Check only (no writes)
cargo fmt --all -- --check
```

**Per-file opt-out:**
```rust
#[rustfmt::skip]
fn manually_formatted_table() {
    let matrix = [
        [1, 0, 0],
        [0, 1, 0],
        [0, 0, 1],
    ];
}
```

**Per-expression opt-out:**
```rust
let x = #[rustfmt::skip] {
    some + manually + aligned + expression
};
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Check formatting
  run: cargo fmt --all -- --check
```

**With nightly for unstable features:**
```yaml
- name: Install nightly rustfmt
  run: rustup toolchain install nightly --component rustfmt

- name: Check formatting (nightly)
  run: cargo +nightly fmt --all -- --check
```

**Pre-commit hook:**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/doublify/pre-commit-rust
    rev: v1.0
    hooks:
      - id: fmt
        args: [--all, --, --check]
```

## Performance

- `cargo fmt --all` on a typical workspace (50 files) completes in under 1 second.
- Rustfmt processes files in parallel — multi-crate workspaces benefit from all CPU cores.
- No caching is needed — rustfmt is fast enough to run on every file unconditionally.
- `--check` is slightly faster than `--write` — it short-circuits on the first difference found per file.

## Security

Rustfmt has no security analysis capability. Key practices:

- Rustfmt is distributed as part of the official Rust toolchain — no third-party supply chain risk.
- Pin the Rust toolchain version in `rust-toolchain.toml` — this ensures consistent `rustfmt` behavior across developer machines and CI:
  ```toml
  [toolchain]
  channel = "1.82.0"
  components = ["rustfmt", "clippy"]
  ```
- Nightly options: using `unstable_features = true` requires a nightly toolchain in CI — ensure the CI pipeline installs the same nightly version to avoid formatting drift.

## Testing

```bash
# Format all workspace crates in place
cargo fmt --all

# Check all workspace crates (CI mode)
cargo fmt --all -- --check

# Format a single file
rustfmt src/lib.rs

# Show diff without writing
rustfmt --check src/lib.rs

# Format with nightly toolchain
cargo +nightly fmt --all

# Dump the full resolved config
rustfmt --print-config current .

# Show default config
rustfmt --print-config default .
```

## Dos

- Set `edition` in `rustfmt.toml` to match `Cargo.toml` — the edition affects syntax rules (e.g., `2021` enables `use` path shorthand).
- Pin the Rust toolchain in `rust-toolchain.toml` — rustfmt output can change between Rust versions, causing spurious CI failures on upgrade.
- Use `cargo fmt --all` rather than `rustfmt src/**/*.rs` — the `--all` flag respects workspace members and their source layouts correctly.
- Enable `group_imports = "StdExternalCrate"` — separates stdlib, external crates, and internal modules for readability.
- Use `#[rustfmt::skip]` for alignment-sensitive code (e.g., lookup tables, matrices) where manual formatting conveys structure.
- Run `rustfmt --print-config current .` to verify the resolved config in CI — catches missing `rustfmt.toml` or toolchain mismatches.

## Don'ts

- Don't use nightly-only `rustfmt.toml` options without pinning the nightly toolchain — stable Rust ignores unknown options silently, producing different output than intended.
- Don't run `rustfmt` directly on files in CI without `--check` — writing files in CI is a side effect that can mask test results.
- Don't set `max_width` above `120` — very long lines reduce readability in side-by-side diffs and on GitHub's PR view.
- Don't enable `format_strings = true` without reviewing the output — rustfmt's string formatting can collapse multi-line string literals in ways that reduce readability.
- Don't add `#[rustfmt::skip]` to entire modules — it silently prevents future formatting improvements. Limit skips to specific functions or blocks.
- Don't commit `rustfmt.toml` with `unstable_features = true` if your team uses stable Rust — the config silently becomes a no-op and developers see different output than CI.
