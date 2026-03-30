# mix-audit

## Overview

`mix_audit` is the standard Elixir dependency security scanner, checking project dependencies in `mix.lock` against the Hex Security Advisory Database. Add `mix_audit` to `mix.exs` as a dev dependency and run `mix deps.audit` from the project root. Use `--format json` for machine-readable output suitable for CI artifacts and SARIF conversion. `mix_audit` is designed to integrate seamlessly into the existing Mix toolchain alongside `credo` (SAST) and `dialyzer` (type checking).

## Architecture Patterns

### Installation & Setup

```elixir
# mix.exs
defp deps do
  [
    {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
  ]
end
```

```bash
# Install dependency
mix deps.get

# Run audit (exits non-zero if vulnerabilities found)
mix deps.audit

# JSON output for CI artifact
mix deps.audit --format json

# Update the advisory database and audit
mix deps.audit --fetch

# Show verbose output (include package details)
mix deps.audit --verbose
```

### Rule Categories

| Advisory Type | Description | Pipeline Severity |
|---|---|---|
| High severity CVE | Exploitable vulnerability with known CVE | CRITICAL |
| Medium severity CVE | Vulnerability with limited exploitability | WARNING |
| Low severity advisory | Informational or minor security notice | INFO |
| Retired / abandoned package | Package no longer maintained with no fix | WARNING |

### Configuration Patterns

**`.mix_audit.json` configuration (project root):**
```json
{
  "ignore": [
    {
      "id": "2023-001",
      "reason": "CVE only affects custom_package < 1.0.0; project uses 1.2.0",
      "expires": "2025-12-31"
    }
  ]
}
```

**`mix.exs` audit task integration:**
```elixir
# mix.exs — add audit to the default check task
defp aliases do
  [
    check: [
      "compile --warnings-as-errors",
      "format --check-formatted",
      "credo --strict",
      "deps.audit",
      "dialyzer"
    ]
  ]
end
```

**Combining with `sobelow` for full Elixir/Phoenix security coverage:**
```elixir
# mix.exs
defp deps do
  [
    {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
    {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
  ]
end
```

```bash
# Full security scan
mix deps.audit && mix sobelow --config
```

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Set up Elixir
  uses: erlef/setup-beam@v1
  with:
    elixir-version: "1.16"
    otp-version: "26"

- name: Install dependencies
  run: mix deps.get

- name: Run mix deps.audit
  run: mix deps.audit

- name: Run mix deps.audit (JSON artifact)
  if: always()
  run: mix deps.audit --format json > mix-audit-report.json || true

- name: Upload audit report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: mix-audit-report
    path: mix-audit-report.json

# Cache Mix dependencies and build artifacts
- name: Cache Mix deps
  uses: actions/cache@v4
  with:
    path: |
      deps
      _build
    key: mix-${{ runner.os }}-${{ hashFiles('mix.lock') }}
```

**GitLab CI integration:**
```yaml
audit:
  stage: test
  script:
    - mix deps.get
    - mix deps.audit --format json > gl-sast-report.json
  artifacts:
    reports:
      dependency_scanning: gl-sast-report.json
```

## Performance

- `mix deps.audit` is fast (< 3 seconds) — it reads `mix.lock` and queries the Hex advisory database via the Hex API. No large local database download required.
- The Hex advisory database is small and fetched on-demand — no caching of the database itself is needed, though `deps/` and `_build/` should be cached for overall CI speed.
- `mix deps.audit --fetch` explicitly refreshes the advisory list before scanning — use this in nightly builds or release pipelines for the most current data.
- For umbrella applications, run `mix deps.audit` from the umbrella root — it scans the aggregated `mix.lock` covering all child apps.

## Security

- Commit `mix.lock` — it pins exact Hex package versions and is required for reproducible security scanning. Never `.gitignore` the lock file.
- Any advisory in `.mix_audit.json` ignores must include a `reason` and `expires` field — undocumented ignores accumulate as silent risks.
- Combine `mix deps.audit` with `sobelow` for Phoenix applications — sobelow catches source-level vulnerabilities (SQL injection, XSS, CSRF misconfigurations) that dep auditing cannot detect.
- Review direct dependencies weekly — Elixir's Hex ecosystem is smaller than npm/PyPI, and new CVEs in popular packages (Ecto, Phoenix, Oban) can affect many projects.
- Use `mix hex.outdated` to identify stale dependencies beyond known CVEs — outdated packages may have unreported vulnerabilities.

## Testing

```bash
# Basic audit
mix deps.audit

# Audit with fresh advisory data
mix deps.audit --fetch

# JSON output
mix deps.audit --format json

# Verbose output
mix deps.audit --verbose

# Combined check with credo and sobelow
mix deps.audit && mix credo --strict && mix sobelow --config

# Check hex.outdated for stale packages (complementary)
mix hex.outdated
```

## Dos

- Add `mix deps.audit` to the `check` Mix alias alongside `credo`, `dialyzer`, and `mix format` — it should be part of every local and CI quality check.
- Commit `mix.lock` — it is required for reproducible dependency resolution and accurate security scanning.
- Use `--fetch` in nightly builds and release pipelines to ensure the latest advisory data is used before shipping.
- Document every advisory in `.mix_audit.json` ignores with a `reason` and `expires` — quarterly reviews should remove expired ignores.
- Combine with `sobelow` for Phoenix projects to cover both dependency CVEs and source-level security patterns.

## Don'ts

- Don't skip `mix deps.audit` in CI — Elixir's compile-time metaprogramming can obscure dependency usage, making runtime-only discovery unreliable.
- Don't add `mix.lock` to `.gitignore` — without it, dependency versions are non-deterministic and security scanning is unreliable.
- Don't ignore advisories for convenience — if a fix is unavailable, open a tracking issue and document the accepted risk with an expiry.
- Don't rely on `mix_audit` alone for umbrella apps with multiple databases — run `sobelow` on each Phoenix child app separately to catch app-specific SAST findings.
- Don't run `mix deps.audit` without `mix deps.get` first — the lock file must reflect the actual resolved dependencies, not a hypothetical resolution.
- Don't treat `WARNING` severity advisories as informational — medium-severity CVEs can be critical in Elixir applications processing untrusted input (Phoenix LiveView, API endpoints).
