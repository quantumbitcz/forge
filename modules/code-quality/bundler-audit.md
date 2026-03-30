# bundler-audit

## Overview

`bundler-audit` scans Ruby applications' `Gemfile.lock` against the Ruby Advisory Database (RUBYSEC), covering CVEs and GHSA advisories for Ruby gems. Install as a gem (`gem install bundler-audit`), run `bundle-audit check` from the project root, and update the advisory database with `bundle-audit update`. Use `--ignore GHSA-xxxx-xxxx-xxxx` for accepted false positives — document each with a justification comment. bundler-audit is the standard tool for Ruby dependency security in the Bundler ecosystem.

## Architecture Patterns

### Installation & Setup

```bash
# Install bundler-audit
gem install bundler-audit

# Or add to Gemfile (recommended for version pinning)
# group :development, :test do
#   gem 'bundler-audit', require: false
# end

# Update the local advisory database (run before auditing)
bundle-audit update

# Check for vulnerabilities (exits non-zero if found)
bundle-audit check

# Check with automatic database update
bundle-audit check --update

# Ignore specific advisories
bundle-audit check --ignore GHSA-xxxx-yyyy-zzzz CVE-2023-12345

# Verbose output
bundle-audit check --verbose

# Show only unpatched vulnerabilities
bundle-audit check
```

**Gemfile integration:**
```ruby
# Gemfile
group :development, :test do
  gem 'bundler-audit', require: false
end
```

```bash
# With Bundler integration
bundle exec bundle-audit check --update
```

### Rule Categories

| Advisory Type | Description | Pipeline Severity |
|---|---|---|
| Unpatched vulnerabilities | CVE with a known gem version fix | CRITICAL |
| Insecure gem sources | `http://` source in Gemfile | CRITICAL |
| Insecure git sources | Unverified git references | WARNING |
| Informational advisories | Non-critical security notices | INFO |

### Configuration Patterns

**`.bundler-audit.yml` (or `config/bundler-audit.yml`):**
```yaml
# Ignored advisories with mandatory context
ignore:
  - GHSA-xxxx-yyyy-zzzz  # Reason: Only affects Windows targets, project is Linux-only
  - CVE-2023-12345        # Reason: Patched in our fork, tracking issue: #1234
```

**Integrating bundler-audit with Brakeman for full Ruby security coverage:**
```bash
# bundler-audit: dependency CVEs
bundle-audit check --update

# Brakeman: source code SAST
gem install brakeman
brakeman --format sarif --output brakeman.sarif .
```

**RuboCop integration for gem source policy enforcement:**
```ruby
# .rubocop.yml
Bundler/InsecureGemSource:
  Enabled: true
```

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Set up Ruby
  uses: ruby/setup-ruby@v1
  with:
    ruby-version: "3.3"
    bundler-cache: true

- name: Install bundler-audit
  run: gem install bundler-audit

- name: Update advisory database
  run: bundle-audit update

- name: Run bundler-audit
  run: bundle-audit check

- name: Run bundler-audit (JSON artifact)
  if: failure()
  run: bundle-audit check --format json > bundler-audit-report.json || true

- name: Upload audit report
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: bundler-audit-report
    path: bundler-audit-report.json

# Cache the advisory database to speed up CI
- name: Cache advisory database
  uses: actions/cache@v4
  with:
    path: ~/.local/share/ruby-advisory-db
    key: ruby-advisory-db-${{ github.run_id }}
    restore-keys: ruby-advisory-db-
```

**Pre-commit hook:**
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
bundle-audit check --update
```

**Rake task:**
```ruby
# Rakefile
require 'bundler/audit/task'
Bundler::Audit::Task.new
```

## Performance

- `bundle-audit update` fetches from the rubysec/ruby-advisory-db GitHub repository — cache `~/.local/share/ruby-advisory-db` in CI to avoid repeated clones. The database is ~2MB.
- `bundle-audit check` is fast (< 2 seconds) — it reads `Gemfile.lock` and performs a local lookup against the downloaded database. Always run `bundle-audit update` first to get the latest advisories.
- Use `bundle-audit check --update` to combine the update and check steps into a single command in CI.
- For large Rails applications, bundler-audit performance is not a bottleneck — the limiting factor is the database update network request.

## Security

- Commit `Gemfile.lock` — bundler-audit requires it to determine exact gem versions in use. A missing or .gitignored `Gemfile.lock` prevents security scanning.
- Review all `--ignore` flags in CI scripts — each ignored advisory must be tracked in a project issue and re-evaluated when a fix is available.
- bundler-audit also checks for insecure `http://` gem sources — replace all gem sources with `https://` in `Gemfile`.
- For Rails applications, combine bundler-audit (dependency CVEs) with Brakeman (SAST for Rails-specific vulnerabilities) and `rails_best_practices`.
- Run `bundle-audit check` in the deployment pipeline (not just PR checks) — a newly published CVE may affect code that was previously clean.

## Testing

```bash
# Update database and check
bundle-audit check --update

# Check only (using existing local database)
bundle-audit check

# Ignore a specific advisory for testing
bundle-audit check --ignore GHSA-xxxx-yyyy-zzzz

# Verbose output showing all checked gems
bundle-audit check --verbose

# Check a specific Gemfile.lock
bundle-audit check --gemfile-lock path/to/Gemfile.lock

# Update advisory database only
bundle-audit update

# Show current database version
bundle-audit version
```

## Dos

- Run `bundle-audit check --update` in CI — always fetch the latest advisory database before checking to catch recently published CVEs.
- Commit `Gemfile.lock` — it is required for bundler-audit to determine exact dependency versions and is also needed for reproducible builds.
- Document every `--ignore` flag with a comment in the CI script and a tracking issue — ignored advisories without justification are a compliance risk.
- Use the Rake task (`Bundler::Audit::Task.new`) to integrate bundler-audit into the existing `rake` workflow alongside tests and other quality checks.
- Replace all `http://` gem sources with `https://` — bundler-audit flags insecure sources as vulnerabilities.

## Don'ts

- Don't skip `bundle-audit update` before `bundle-audit check` — the local advisory database may be weeks out of date and miss recent CVEs.
- Don't add `Gemfile.lock` to `.gitignore` — without it, bundler-audit cannot determine which versions are in use and the check cannot run.
- Don't use `--ignore` flags without a comment explaining the rationale — ignored advisories become invisible risks when engineers rotate off the project.
- Don't run bundler-audit without also running Brakeman — bundler-audit covers gem CVEs but not Rails-specific SAST patterns (SQL injection, XSS, mass assignment).
- Don't suppress all advisories for a dependency to unblock a release — upgrade the gem or vendor a patched version instead.
- Don't rely on bundler-audit alone for container security — it only covers gem-level dependencies, not OS packages in the Ruby Docker base image.
