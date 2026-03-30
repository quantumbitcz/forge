# Gin + govulncheck

> Extends `modules/code-quality/govulncheck.md` with Gin-specific integration.
> Generic govulncheck conventions (installation, finding types, CI integration) are NOT repeated here.

## Integration Setup

Run govulncheck scoped to the module root. Gin projects typically have a single `go.mod` — run from there:

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

## Framework-Specific Patterns

### Key Gin Dependency Surface

Gin pulls in a set of transitive dependencies that are common vulnerability targets. Monitor these packages in addition to `gin-gonic/gin` itself:

| Package | Role | Vulnerability Risk |
|---|---|---|
| `github.com/gin-gonic/gin` | HTTP router | HTTP parsing, route injection |
| `github.com/go-playground/validator` | Request binding validation | ReDoS in complex regex rules |
| `golang.org/x/net` | HTTP/2, net utilities | HTTP/2 request smuggling, HPACK |
| `golang.org/x/crypto` | TLS, bcrypt | Weak curve, timing attacks |
| `github.com/ugorji/go/codec` | JSON/msgpack codec | Deserialization vulnerabilities |

Govulncheck's reachability analysis will only flag these if the vulnerable function is actually called — `golang.org/x/net` is particularly prone to false positives because many utilities are imported but not all affected code paths are reachable.

### Scanning After Dependency Updates

Run govulncheck immediately after updating `go.mod` to catch newly introduced CVEs before they reach CI:

```bash
# After running go get github.com/gin-gonic/gin@latest
go mod tidy && govulncheck ./...
```

### Handling golang.org/x/* Module Findings

`golang.org/x/net`, `golang.org/x/crypto`, and `golang.org/x/text` are frequently updated to patch vulnerabilities. Keep them at the latest patch within the minor version:

```bash
# Update only x/ packages to latest patch
go get golang.org/x/net@latest golang.org/x/crypto@latest golang.org/x/text@latest
go mod tidy
```

### Binary Scanning for Deployed Artifacts

For Gin services deployed as Docker images or binaries, scan the compiled artifact before publishing:

```yaml
- name: Build binary
  run: go build -o bin/api ./cmd/api

- name: govulncheck binary scan
  run: govulncheck -mode binary ./bin/api
```

Binary scanning catches vulnerabilities in statically linked dependencies that would not appear in `go.mod` (e.g., CGO-linked libraries).

## Additional Dos

- Run govulncheck on the compiled binary in addition to source — it detects vulnerabilities in statically linked code that source analysis may miss.
- Prioritize fixing `golang.org/x/net` and `golang.org/x/crypto` vulnerabilities — these are directly in the HTTP request path of every Gin handler.
- Keep `go.sum` in version control and run `go mod verify` before govulncheck to detect tampered modules.

## Additional Don'ts

- Don't ignore "module" findings for `gin-gonic/gin` itself — even if the vulnerable function is not directly called today, Gin's internal routing code may reach it.
- Don't update only `gin-gonic/gin` when a vulnerability is found in a transitive dependency — use `go get <vulnerable-pkg>@<fixed-version>` to patch the specific package.
- Don't rely solely on govulncheck for container security — OS-level vulnerabilities in the Go base image require Trivy or Grype scanning in addition.
