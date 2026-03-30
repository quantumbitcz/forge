# Axum + cargo-audit

> Extends `modules/code-quality/cargo-audit.md` with Axum-specific integration.
> Generic cargo-audit conventions (installation, advisory database, CI integration) are NOT repeated here.

## Integration Setup

Run `cargo audit` on every PR alongside govulncheck for defense in depth — cargo-audit uses the RustSec advisory database while govulncheck uses the Go vuln DB. They cover different data sources:

```yaml
# .github/workflows/security.yml
- name: Install cargo-audit
  run: cargo install cargo-audit --locked

- name: Run cargo audit
  run: cargo audit

- name: Run cargo audit (JSON artifact)
  if: always()
  run: cargo audit --json > cargo-audit-report.json || true

- name: Upload audit report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: cargo-audit-report
    path: cargo-audit-report.json
```

## Framework-Specific Patterns

### Axum Dependency Surface

Axum's dependency tree includes Tower, Tokio, Hyper, and several `tower-http` crates. These are active packages with periodic security advisories. Key packages to monitor:

| Crate | Role | Advisory History |
|---|---|---|
| `axum` | HTTP framework | HTTP parsing, routing |
| `hyper` | HTTP/1+2 client/server | HTTP request smuggling, H2 frame parsing |
| `tokio` | Async runtime | Race conditions, task scheduling |
| `tower-http` | HTTP middleware | CORS bypass, compression bomb |
| `rustls` / `openssl` | TLS | Certificate validation, cipher weaknesses |
| `serde` / `serde_json` | Serialization | Stack overflow on deeply nested input |

After `cargo update`, run `cargo audit` immediately to check for newly introduced advisories in the updated dependency graph.

### Ignoring Advisories

When a vulnerability is not exploitable in the Axum application context, document the ignore in `.cargo/audit.toml`:

```toml
# .cargo/audit.toml
[advisories]
ignore = [
    # RUSTSEC-2024-XXXX: hyper HTTP/2 DoS — not exploitable because
    # this service is behind a load balancer that terminates HTTP/2.
    # Scheduled for remediation in Q3 2024.
    "RUSTSEC-2024-XXXX",
]
```

Never add ignores without a comment explaining the rationale and a scheduled remediation date.

### Checking for Unmaintained Crates

`cargo audit` reports `unmaintained` advisories for crates that are no longer receiving security updates. In Axum projects, common unmaintained transitive dependencies come from the `tower` ecosystem:

```bash
# Check for unmaintained crates specifically
cargo audit --deny unmaintained

# Show all advisories including informational
cargo audit --show-stats
```

For unmaintained dependencies that are transitive, check if a newer version of the direct dependency drops the unmaintained transitive:

```bash
cargo tree -i <unmaintained-crate>     # show which crates depend on it
cargo update <direct-dep> --precise <version>   # try updating direct dep
```

### Cargo Deny as a Complement

For Axum services with strict supply chain requirements, complement `cargo-audit` with `cargo-deny` for license checking and dependency allow/deny lists:

```toml
# deny.toml
[licenses]
allow = ["MIT", "Apache-2.0", "BSD-3-Clause"]
deny = ["GPL-3.0"]

[bans]
deny = [
    { name = "openssl" },      # require rustls only
]
```

```yaml
- name: Run cargo deny
  uses: EmbarkStudios/cargo-deny-action@v1
```

## Additional Dos

- Run `cargo audit` after every `cargo update` — dependency updates frequently introduce previously advisory-covered versions.
- Use `.cargo/audit.toml` for documented ignores rather than passing `--ignore` on the command line — the file is version-controlled and shows rationale.
- Monitor `hyper` and `rustls` advisories closely — they are in the critical path of every Axum HTTP request.

## Additional Don'ts

- Don't use `cargo audit --ignore-source` — source replacement entries in `.cargo/config.toml` may mask patched crates or introduce unaudited versions.
- Don't delay remediation for `hyper` CVEs — even advisories rated "moderate" in HTTP parsing can become critical when Axum is directly internet-facing.
- Don't skip `cargo audit` for internal services not exposed to the internet — supply chain compromise (typosquatting, dependency confusion) affects all services regardless of exposure.
