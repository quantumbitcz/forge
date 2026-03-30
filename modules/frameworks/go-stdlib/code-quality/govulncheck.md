# Go-stdlib + govulncheck

> Extends `modules/code-quality/govulncheck.md` with Go-stdlib-specific integration.
> Generic govulncheck conventions (installation, finding types, CI integration) are NOT repeated here.

## Integration Setup

Stdlib projects have minimal dependencies — govulncheck runs faster and produces cleaner results than in framework-based projects. The small dependency surface makes "called" findings more actionable:

```yaml
# .github/workflows/security.yml
- name: Install govulncheck
  run: go install golang.org/x/vuln/cmd/govulncheck@latest

- name: Run govulncheck
  run: govulncheck ./...

- name: govulncheck JSON artifact
  if: always()
  run: govulncheck -json ./... > govulncheck-report.json || true

- name: Upload report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: govulncheck-report
    path: govulncheck-report.json
```

Pin govulncheck in `go.mod` tools directive for reproducible scanning:

```
// go.mod
tool (
    golang.org/x/vuln/cmd/govulncheck
)
```

## Framework-Specific Patterns

### Minimal Dependency Surface

Stdlib projects should keep `go.mod` minimal — each dependency is a potential vulnerability vector. Review govulncheck output against the full dependency list regularly:

```bash
# View all direct and indirect dependencies
go list -m all

# Run govulncheck and compare against dependency count
govulncheck -json ./... | jq '.finding | length'
```

A high ratio of findings to dependencies in a small dependency graph indicates transitive vulnerabilities requiring upstream updates.

### golang.org/x/* Packages

Even "stdlib-adjacent" projects that import `golang.org/x/net`, `golang.org/x/crypto`, or `golang.org/x/text` are exposed to their vulnerability histories. These packages have active CVE histories:

```bash
# Check for known x/ package vulnerabilities specifically
govulncheck -json ./... | jq '.finding[] | select(.osv.id | startswith("GO-")) | .osv.id, .osv.summary'

# Update x/ packages to latest patch
go get golang.org/x/net@latest golang.org/x/crypto@latest
go mod tidy
```

### Vendor Mode for Offline/Air-Gapped Environments

Stdlib projects in regulated environments may use vendoring. Run govulncheck against the vendor directory:

```bash
go mod vendor
govulncheck -mod vendor ./...

# Verify module integrity before scanning
go mod verify && govulncheck -mod vendor ./...
```

### Library vs Application Scanning Strategy

- **Library (published on pkg.go.dev):** Run govulncheck on every PR. "Module" findings (not called) are still worth investigating — consumers may have code paths that reach the vulnerable function even if the library doesn't.
- **Application (deployed binary):** Run govulncheck on the source (`./...`) AND on the compiled binary (`-mode binary ./bin/app`). Binary analysis catches dynamically linked code not visible in source analysis.

```bash
# Source analysis
govulncheck ./...

# Binary analysis (for deployed applications)
go build -o bin/app ./cmd/app
govulncheck -mode binary ./bin/app
```

## Additional Dos

- Treat every direct dependency addition as a security decision — review its `go.mod` transitive chain and run govulncheck before merging.
- Run `go mod verify && govulncheck ./...` in one script — module integrity check ensures the downloaded sources match `go.sum` before scanning.
- For libraries: document accepted "module" findings in `SECURITY.md` with justification and a scheduled review date.

## Additional Don'ts

- Don't use govulncheck as the only security check — complement with `gosec` (via golangci-lint) for code-level security patterns not covered by CVE databases.
- Don't defer govulncheck runs to release time — run on every PR for the minimal dependency count of stdlib projects; it's fast and catches problems early.
- Don't suppress govulncheck output on dependencies that are "not called today" — code paths change; schedule a quarterly review of all "module" findings.
