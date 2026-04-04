---
name: govulncheck
categories: [security-scanner]
languages: [go]
exclusive_group: none
recommendation_score: 90
detection_files: [go.mod, go.sum]
---

# govulncheck

## Overview

`govulncheck` is the official Go vulnerability scanner from the Go security team, querying the Go vulnerability database at vuln.go.dev (backed by the OSV database). Unlike naive dependency scanners that flag all packages containing a vulnerability, govulncheck performs static reachability analysis — it only reports vulnerabilities in functions that are actually called by the project, drastically reducing false positives. It also supports binary analysis mode (`govulncheck -mode binary`) for scanning compiled Go binaries. Run `govulncheck ./...` in CI to catch exploitable CVEs before deployment.

## Architecture Patterns

### Installation & Setup

```bash
# Install govulncheck
go install golang.org/x/vuln/cmd/govulncheck@latest

# Or via go.mod toolchain (Go 1.21+)
# go get golang.org/x/vuln/cmd/govulncheck@latest

# Run against all packages in the module
govulncheck ./...

# Run against a specific package
govulncheck ./internal/api/...

# Binary analysis (scan a compiled binary)
govulncheck -mode binary ./bin/myapp

# JSON output for machine parsing
govulncheck -json ./... > govulncheck-report.json

# Verbose output showing call stack traces
govulncheck -v ./...
```

**`go.mod` toolchain integration (Go 1.21+):**
```
// go.mod — pin govulncheck for team consistency
tool (
    golang.org/x/vuln/cmd/govulncheck
)
```

### Rule Categories

| Finding Type | Description | Pipeline Severity |
|---|---|---|
| Called (vulnerable function reachable) | Vulnerability in a code path actually exercised | CRITICAL |
| Module (vulnerable module imported, path not called) | Vulnerable package imported but the affected function is not called | WARNING |
| Informational | Dependency analysis notes | INFO |

Govulncheck distinguishes between "called" and "module" findings — only "called" findings represent confirmed exploitable paths. "Module" findings indicate the vulnerable module is present in the dependency graph but the affected symbol is not reachable.

### Configuration Patterns

**No configuration file is needed for basic use.** govulncheck reads from `go.mod`/`go.sum` and the vuln.go.dev database.

**Environment variables:**
```bash
# Use a private or mirrored vulnerability database (e.g., for air-gapped environments)
export GONOSUMCHECK="*"
export GOVULNCHECK_DB="https://your-internal-vuln-db/"

# Disable network access for offline use (uses cached data only)
export GONOSUMCHECK="*"
export GOFLAGS="-mod=vendor"
govulncheck -mod vendor ./...

# Proxy configuration (respects standard Go proxy settings)
export GOPROXY="https://proxy.golang.org,direct"
```

**Ignoring specific vulnerabilities** — govulncheck has no native ignore file. Manage accepted risks in a `vuln-ignores.txt` with a custom wrapper script:
```bash
#!/usr/bin/env bash
# scripts/govulncheck-ci.sh
IGNORED_VULNS=("GO-2023-1234" "GO-2024-5678")
OUTPUT=$(govulncheck -json ./... 2>&1)
# Filter out accepted vulns from JSON and fail on remaining
echo "$OUTPUT" | jq --argjson ignored "$(printf '%s\n' "${IGNORED_VULNS[@]}" | jq -R . | jq -s .)" \
  '.findings[] | select(.osv.id as $id | $ignored | index($id) | not)'
```

Document ignored vulnerabilities in a `SECURITY.md` with justification and review dates.

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Install govulncheck
  run: go install golang.org/x/vuln/cmd/govulncheck@latest

- name: Run govulncheck
  run: govulncheck ./...

- name: Run govulncheck (JSON for artifact)
  if: always()
  run: govulncheck -json ./... > govulncheck-report.json || true

- name: Upload vulnerability report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: govulncheck-report
    path: govulncheck-report.json
```

**Cache govulncheck binary between runs:**
```yaml
- name: Cache Go binaries
  uses: actions/cache@v4
  with:
    path: ~/go/bin
    key: go-bin-govulncheck-${{ hashFiles('go.sum') }}
```

## Performance

- govulncheck performs reachability analysis via static callgraph traversal — it is significantly slower than simple `go list`-based scanners but produces far fewer false positives. Expect 5-30 seconds depending on codebase size.
- Binary analysis mode (`-mode binary`) is faster than source analysis and useful for scanning deployed artifacts, but it provides less detail (no source line numbers, no call stacks).
- Running govulncheck with `-json` is slightly faster than human-readable output as it skips terminal rendering.
- In monorepos with multiple modules, run govulncheck per module directory rather than from the root to get accurate per-module results.
- The vulnerability database is cached locally by Go's module cache — first run requires network access, subsequent runs use the cache unless `GONOSUMCHECK` is set.

## Security

- govulncheck only reports vulnerabilities affecting functions actually called — a package that imports a vulnerable module but never calls the affected function will appear as a "module" finding, not "called". Treat "called" findings as blocking and "module" findings as risk-aware.
- Keep `go.sum` in version control — it anchors the exact dependency graph govulncheck analyzes. Never run `go mod tidy` before scanning as it may alter the dependency graph.
- Combine govulncheck with `go mod verify` to detect tampered module content:
  ```bash
  go mod verify && govulncheck ./...
  ```
- For supply chain integrity, run govulncheck against the vendor directory in air-gapped builds:
  ```bash
  govulncheck -mod vendor ./...
  ```
- Binary scanning is critical for catching vulnerabilities introduced after compilation — run against release binaries before publishing to artifact registries.

## Testing

```bash
# Scan all packages
govulncheck ./...

# Scan a compiled binary
govulncheck -mode binary ./bin/myapp

# Verbose output with call stacks
govulncheck -v ./...

# JSON output
govulncheck -json ./...

# Check a specific Go module path
govulncheck -C /path/to/module ./...

# Test that the vulnerability database is reachable
govulncheck -version

# Check govulncheck version
govulncheck -version
```

## Dos

- Run `govulncheck ./...` in CI on every PR — it is the authoritative Go vulnerability scanner backed by the official vuln.go.dev database.
- Treat "called" findings as blocking (CRITICAL) and "module" findings as warnings (WARNING) — the distinction between reachable and imported-but-unreachable is the key advantage of govulncheck.
- Pin govulncheck to a specific version in CI using `go install ...@v0.x.y` rather than `@latest` for reproducible scans.
- Run binary analysis (`-mode binary`) against release artifacts before publishing — catches CVEs from transitively bundled packages not visible in source analysis.
- Combine with `go mod verify` to ensure module integrity before scanning.

## Don'ts

- Don't use `go list -m all | grep vulnerability` as a substitute — it does not perform reachability analysis and generates excessive false positives.
- Don't ignore "module" findings indefinitely — even unreachable vulnerable code becomes reachable when code paths change during refactoring.
- Don't skip govulncheck in favor of only Snyk or Trivy for Go projects — govulncheck uses the authoritative vuln.go.dev database maintained by the Go security team with Go-specific context.
- Don't run govulncheck with `-mod mod` in CI — it may silently update `go.sum` during the scan, creating an inconsistent build artifact.
- Don't pipe govulncheck output directly to `exit 0` to suppress failures — always capture the output as an artifact before determining the exit behavior.
- Don't rely solely on govulncheck for container security — OS-level vulnerabilities in the base image require a separate scanner (Trivy, Grype).
