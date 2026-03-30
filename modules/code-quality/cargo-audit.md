# cargo-audit

## Overview

`cargo-audit` scans Rust project dependencies against the RustSec Advisory Database (rustsec.org), which contains CVEs and security advisories specific to the Rust ecosystem. Install via `cargo install cargo-audit` and run `cargo audit` in the project root — it reads `Cargo.lock` and checks each dependency version against the advisory database. Use `.cargo-audit.toml` to configure ignore lists with mandatory justification. `cargo audit fix` automates safe upgrades. Generate SARIF output for GitHub Advanced Security integration.

## Architecture Patterns

### Installation & Setup

```bash
# Install cargo-audit
cargo install cargo-audit --features=fix

# Update advisory database (happens automatically on first run)
cargo audit

# Run audit (requires Cargo.lock)
cargo audit

# Fail with non-zero exit code on any advisory (default behavior)
cargo audit

# JSON output
cargo audit --json > cargo-audit-report.json

# SARIF output for GitHub Security tab
cargo audit --output sarif > cargo-audit.sarif

# Auto-fix vulnerabilities by upgrading dependencies
cargo audit fix

# Preview fixes without applying
cargo audit fix --dry-run
```

**`Cargo.lock` must be committed** for application crates (binaries) — library crates typically do not commit `Cargo.lock`, but auditing still works if it exists. Run `cargo generate-lockfile` to create it for libraries in CI.

### Rule Categories

| Advisory Type | Description | Pipeline Severity |
|---|---|---|
| vulnerability | Known CVE with a published fix | CRITICAL |
| unsound | Unsafe Rust usage violating soundness guarantees | CRITICAL |
| yanked | Crate version pulled from crates.io (often security-related) | WARNING |
| notice | Non-security informational advisories | INFO |

### Configuration Patterns

**`.cargo-audit.toml` (project root):**
```toml
[advisories]
# Ignore specific advisory IDs with mandatory justification
ignore = ["RUSTSEC-2023-0001"]

# Deny unsound advisories
deny = ["unsound"]

# Inform (don't fail) on yanked crates
informational_warnings = ["yanked", "notice"]

[output]
# Show denial reasons in output
deny-warnings = true

[target]
# Only audit dependencies for specific target triples
# Useful for cross-compilation projects
# triple = ["x86_64-unknown-linux-gnu"]
```

**Workspace-level audit configuration:**
For workspaces, `.cargo-audit.toml` at the workspace root applies to all members. Per-crate overrides are not supported — maintain a single workspace-level policy.

**Integrating with `cargo-deny` for broader policy enforcement:**
```bash
cargo install cargo-deny
```
```toml
# deny.toml — enforces advisories + license policies + duplicate crates
[advisories]
vulnerability = "deny"
unsound = "deny"
yanked = "warn"
notice = "warn"
ignore = [
  { id = "RUSTSEC-2023-0001", reason = "False positive — only affects 32-bit targets" }
]
```
`cargo-deny` is recommended alongside `cargo-audit` — it adds license compliance and dependency duplication checks.

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Install cargo-audit
  run: cargo install cargo-audit --features=fix

- name: Run cargo audit
  run: cargo audit

- name: Run cargo audit (SARIF)
  if: always()
  run: cargo audit --output sarif > cargo-audit.sarif || true

- name: Upload SARIF to GitHub Security
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: cargo-audit.sarif
    category: cargo-audit

# Cache cargo-audit installation
- name: Cache cargo-audit
  uses: actions/cache@v4
  with:
    path: ~/.cargo/bin/cargo-audit
    key: cargo-audit-${{ runner.os }}-0.20
```

**Combined audit + deny in CI:**
```yaml
- name: cargo deny (advisories + licenses)
  uses: EmbarkStudios/cargo-deny-action@v1
  with:
    command: check advisories licenses
```

## Performance

- `cargo audit` is fast (< 3 seconds) — it reads `Cargo.lock` and performs a local lookup against a cached advisory database (stored in `~/.cargo/advisory-db`).
- Cache `~/.cargo/advisory-db` between CI runs to avoid re-fetching the database on every run. The database is ~5MB and updates frequently.
- `cargo install cargo-audit` takes 30-60 seconds to compile on first install. Use pre-built binaries from GitHub releases or the `cargo-binstall` tool for faster CI setup:
  ```bash
  cargo binstall cargo-audit --no-confirm
  ```
- For workspaces with many crates, `cargo audit` is still fast as it scans a single `Cargo.lock` at the workspace root.

## Security

- Commit `Cargo.lock` for application crates (binaries) — it pins the exact dependency versions audited and prevents version drift between CI and production builds.
- `cargo audit fix` only applies safe upgrades within semver constraints — run `cargo test` after applying fixes to verify nothing broke.
- Review `.cargo-audit.toml` ignores in every PR — any new ignore entry requires an explanation comment and a tracking issue for resolution.
- The RustSec database includes "unsound" advisories for crates with unsafe code that violates Rust's safety guarantees — these are as important as CVEs for Rust codebases.
- Combine `cargo audit` with `cargo-deny` to additionally enforce license compliance and prevent duplicate dependency versions that can hide vulnerabilities.

## Testing

```bash
# Basic audit
cargo audit

# Generate JSON report
cargo audit --json

# Generate SARIF report
cargo audit --output sarif

# Show detailed advisory information
cargo audit --explain RUSTSEC-2023-0001

# Preview auto-fixes
cargo audit fix --dry-run

# Apply fixes
cargo audit fix

# Force update advisory database
cargo audit --db ~/.cargo/advisory-db fetch

# Audit with cargo-deny
cargo deny check advisories
```

## Dos

- Commit `Cargo.lock` for binary crates — `cargo audit` analyzes the lock file and pinned versions are required for reproducible security scanning.
- Run `cargo audit` with `-D warnings` equivalent (`deny = ["vulnerability", "unsound"]` in `.cargo-audit.toml`) to fail on any advisory, not just CRITICAL.
- Use `cargo-deny` alongside `cargo-audit` — deny provides richer policy control (license compliance, duplicate detection) while audit focuses on CVEs.
- Cache `~/.cargo/advisory-db` in CI — the database fetch from rustsec.org adds 5-10 seconds per run without caching.
- Review and rotate `.cargo-audit.toml` ignores quarterly — old ignores for long-patched advisories should be removed.

## Don'ts

- Don't use `.cargo-audit.toml` ignore entries without a justification comment — vague suppression of security advisories undermines the audit.
- Don't skip `cargo audit` for library crates — while libraries don't ship binaries, their consumers inherit vulnerabilities. Generate a `Cargo.lock` with `cargo generate-lockfile` for CI auditing.
- Don't rely on `cargo audit fix` without running the test suite immediately after — automated version bumps can introduce behavioral changes.
- Don't ignore "unsound" advisories — they indicate that a crate can cause undefined behavior even in safe Rust code, which is a correctness and security issue.
- Don't install cargo-audit without `--features=fix` if you plan to use `cargo audit fix` — the fix feature requires the `--features=fix` flag during installation.
- Don't skip auditing `[patch]` and `[replace]` overrides in `Cargo.toml` — patched dependencies are still included in `Cargo.lock` and must be audited.
