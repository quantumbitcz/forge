# Phase 7 — Strategic Go Core Binary (Design)

**Status:** Draft for review
**Date:** 2026-04-17
**Target version:** Forge 5.0.0 (SemVer **major** — adds a runtime binary dependency; changes distribution model)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 7 of 7 (final)
**Depends on:** Phases 1-6 merged (4.2.0).

---

## 1. Goal

Port the 4 hot-path shell scripts (`forge-state.sh`, `forge-state-write.sh`, `forge-token-tracker.sh` bash wrapper, `build-code-graph.sh`) to a single cross-platform Go binary `forge-core`. Ship per-OS/arch binaries via GitHub releases. Preserve the bash script interfaces as permanent 1-line exec shims so every caller (agents, hooks, skills) sees zero behavioral change. Unblock native Windows support for state + cost + graph operations (hook scripts still require WSL/Git Bash per Phase 3 scope).

## 2. Context and motivation

Phase 3 hardened bash for cross-platform (bash 4+ on macOS/Linux/WSL/Git-Bash). But bash-gating remains the single largest adoption blocker for Windows developers — they must run WSL or Git Bash. Competitive analysis (`Plandex`, `Goose`, `Claude Code`) shows single-binary Go distributions as the norm for 2026 agent tooling. Additionally:

- **Hot-path performance:** `forge-state-write.sh` is called on every agent transition (often >100×/run). Bash + Python shell-out adds measurable latency; Go is 10-50× faster for small reads/writes.
- **Atomicity guarantees:** Current `forge-state-write.sh` uses `mkdir`-based locking + file rename + WAL. Go's `syscall.Rename` + OS-native file locking is more reliable and simpler.
- **Tree-sitter integration:** `build-code-graph.sh` shells out to tree-sitter CLI per file — thousands of subprocess spawns. Go has mature tree-sitter bindings (`github.com/smacker/go-tree-sitter`) — single-process, orders of magnitude faster.
- **Windows-native state ops:** Today PowerShell/CMD users can't invoke the bash scripts. forge-core provides `forge-core.exe` for native state/cost/graph from any Windows shell.

This phase is strategic: not about features, about platform reach and reliability of the hot path.

## 3. Non-goals

- **No port of hook scripts** (session-start.sh, engine.sh, automation-trigger-hook.sh, validate-syntax.sh). They remain bash-gated. Hooks are non-interactive and invoked by Claude Code harness which runs bash; Windows users still need WSL/Git Bash for hooks.
- **No port of `shared/forge-token-tracker.sh` Python heredoc.** The Go binary calls out to the Python sub-process for the cost-computation math; the bash wrapper becomes a Go-core call. The Python script is unchanged.
- **No port of `shared/forge-resolve-file.sh` (Phase 4)** or other helpers. Scope is 4 scripts, not the whole shared/ directory.
- **No port of `shared/graph/query-translator.sh` (Phase 3)** — query translation is rare, not hot path.
- **No port of agent prompts or skill markdowns.** Those are Claude Code artifacts, not executables.
- **No change to bash script interfaces.** Every caller invokes the same `.sh` path with the same args; the script now execs `forge-core`.
- **No npm/pip distribution.** GitHub releases + per-OS binaries only.
- **No auto-update daemon.** `/forge-init` downloads once; user manually runs `/forge-init --update-core` to refresh.

## 4. Design

### 4.1 Go project layout — `core/` (new top-level)

```
forge/                              # plugin repo
├─ core/                            # NEW — Go source
│   ├─ cmd/forge-core/
│   │   └─ main.go                  # CLI entry point; dispatches to subcommands
│   ├─ internal/
│   │   ├─ state/
│   │   │   ├─ read.go              # JSON read + validation
│   │   │   ├─ write.go             # Atomic write + WAL
│   │   │   ├─ transition.go        # State machine (ports forge-state.sh logic)
│   │   │   └─ schema.go            # 1.9.0 schema (generated from state-schema.json)
│   │   ├─ cost/
│   │   │   ├─ record.go            # cost.inc emission
│   │   │   ├─ cap.go               # cap-breach detection
│   │   │   └─ pricing.go           # reads shared/model-pricing.json
│   │   ├─ graph/
│   │   │   ├─ build.go             # tree-sitter → SQLite population
│   │   │   └─ schema.go            # reads shared/graph/code-graph-schema.sql
│   │   └─ platform/
│   │       ├─ lock.go              # file locking (cross-platform)
│   │       └─ atomic.go            # atomic rename + fsync
│   ├─ go.mod
│   ├─ go.sum
│   ├─ Makefile                     # build + release targets
│   └─ README.md                    # developer docs for contributors
├─ shared/
│   ├─ bin/                         # NEW — per-OS binaries (gitignored in source; populated by install)
│   │   └─ .gitkeep
│   ├─ forge-state.sh               # SHIM — 1-line exec forge-core state
│   ├─ forge-state-write.sh         # SHIM
│   ├─ forge-token-tracker.sh       # WRAPPER — bash bash part becomes Go; Python heredoc stays (sub-process)
│   └─ graph/build-code-graph.sh    # SHIM
```

### 4.2 `forge-core` CLI surface

Single binary, subcommand CLI (like `git`):

```
forge-core state read [--json]
forge-core state write --field <path> --value <json>
forge-core state transition --from <state> --to <state> [--reason <str>]

forge-core cost record --agent <id> --model <name> --tokens-in <N> --tokens-out <N> --stage <N> [--run-id <id>]
forge-core cost get [--json]
forge-core cost cap-check                           # exit 0 if under cap, 1 if breached

forge-core graph build [--full | --incremental] [--languages <csv>]
forge-core graph query <sql>                        # SQLite-only; Neo4j still via query-translator.sh

forge-core --version
forge-core --help
```

All subcommands honor `FORGE_DRY_RUN=1` env (writes no state; prints planned operation).

### 4.3 Bash shim pattern (applied to 4 scripts)

**Canonical shim** (permanent — per brainstorming):

```bash
#!/usr/bin/env bash
# forge-state.sh — legacy interface; delegates to forge-core Go binary (5.0.0+).
# DO NOT port to POSIX sh; callers depend on bash error semantics.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect arch
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
esac
ext=""; [[ "$os" == "windows" ]] && ext=".exe"

BIN="${PLUGIN_ROOT}/shared/bin/forge-core-${os}-${arch}${ext}"
[[ -x "$BIN" ]] || { echo "forge-core binary missing: $BIN" >&2; echo "Run: /forge-init --update-core" >&2; exit 127; }

# Legacy interface: forge-state.sh invoked as `forge-state.sh read [args...]`
# → forge-core state read [args...]
exec "$BIN" state "$@"
```

Same shape for `forge-state-write.sh` (→ `state write`), `forge-token-tracker.sh` (→ `cost record` + Python fallback for unknown models), `graph/build-code-graph.sh` (→ `graph build`).

**Critical property:** callers that `source` the scripts break (exec replaces the process). Audit: Phase 3 `state-integrity.sh` sources `platform.sh`, not these 4. Phase 2 `forge-token-tracker.sh` is sourced by nothing — it's invoked as a command. Phase 4 `forge-apply/SKILL.md` calls `forge-state-write.sh patch ...` as a command (not source). Verified safe.

### 4.4 `forge-token-tracker.sh` — hybrid approach

The Python heredoc (`_TOKEN_UPDATE_PY`) stays; it does the pricing lookup + state-update math. Go binary reads `shared/model-pricing.json`, computes the new cost, writes the state update, AND invokes the Python heredoc via subprocess for the embedded by_agent / by_stage / model_distribution rollup. This is a **transitional hybrid** — in a future phase, the Python heredoc can be ported to Go as well, but Phase 7 scope keeps it out to minimize risk.

Bash wrapper becomes:

```bash
#!/usr/bin/env bash
# Invokes forge-core for hot-path cost record; Python sub-process inside
# forge-core for the heredoc math.
exec "${PLUGIN_ROOT}/shared/bin/forge-core-${os}-${arch}${ext}" cost record "$@"
```

### 4.4a `cost-alerting.sh` interaction (v1 review C3 resolved)

`shared/cost-alerting.sh` (431 lines — Phase 2) is the alert emitter for cost-cap breaches + token-budget thresholds. Phase 7's `forge-core cost record` invokes it as a subprocess after every cost update:

```go
// core/internal/cost/record.go (excerpt)
func (r *Recorder) Record(...) error {
    // ... compute new cost + append cost.inc event ...

    // Delegate alerting to bash script (unchanged — stays bash in Phase 7 scope)
    cmd := exec.Command("bash", filepath.Join(PluginRoot, "shared/cost-alerting.sh"),
        "--agent", agent, "--run-cost-usd", fmt.Sprintf("%.4f", runCostUsd),
        "--cap-usd", fmt.Sprintf("%.4f", capUsd))
    return cmd.Run()
}
```

Preserves Phase 2's alert flow exactly. `cost-alerting.sh` remains in bash; Phase 7 does NOT port it (per §3 non-goals — only 4 hot-path scripts). Alerts continue to fire identically.

AC addition: `tests/contract/forge-core.bats` asserts that a cost-cap breach in a Go-tracker-recorded run still produces the same `.forge/alerts.json` entry as pre-Phase-7 runs.

### 4.5 Distribution — GitHub releases

**Per-OS/arch matrix (5 binaries per release):**

- `forge-core-darwin-amd64`
- `forge-core-darwin-arm64`
- `forge-core-linux-amd64`
- `forge-core-linux-arm64`
- `forge-core-windows-amd64.exe`

Each with SHA256 checksum in release notes. Release workflow `.github/workflows/release-core.yml` triggers on tags matching `v5.*.*`; builds via `go build` with `GOOS`/`GOARCH` cross-compilation; uploads to release via `gh release upload`.

### 4.6 `/forge-init` auto-install

Extended to download the matching binary on first run:

```bash
# /forge-init workflow step N (new):
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
ext=""; [[ "$os" == windows* ]] && ext=".exe"

target="${PLUGIN_ROOT}/shared/bin/forge-core-${os}-${arch}${ext}"
if [[ ! -x "$target" ]]; then
  release_url="https://github.com/quantumbitcz/forge/releases/download/v${VERSION}/forge-core-${os}-${arch}${ext}"
  expected_sha=$(get_expected_sha "$os" "$arch")  # from release manifest

  echo "Downloading forge-core ${VERSION} for ${os}-${arch}..."
  curl -sSL "$release_url" -o "$target"
  actual_sha=$(sha256sum "$target" | awk '{print $1}')
  [[ "$actual_sha" == "$expected_sha" ]] || { echo "SHA256 mismatch — abort"; rm -f "$target"; exit 1; }
  chmod +x "$target"
fi
```

New flag: `/forge-init --update-core` re-downloads the binary (bypasses existence check).

**SHA trust anchor (v1 review C1 resolved):** expected checksums ship **inside the plugin itself** (not downloaded from the same release as the binary). New file `shared/bin/checksums.json` is committed to the plugin repo as part of the release PR (written by `release-core.yml` during build, committed back to master via a final commit). At install time, `/forge-init` reads `shared/bin/checksums.json` → `actual_sha = sha256(downloaded_binary)` → compare. An attacker who compromises the release must ALSO compromise the plugin repo (separate attack surface). The checksums file is the trust anchor; the release binary is the verified payload.

```json
{
  "version": "5.0.0",
  "binaries": {
    "darwin-amd64":  "a1b2c3...",
    "darwin-arm64":  "b2c3d4...",
    "linux-amd64":   "c3d4e5...",
    "linux-arm64":   "d4e5f6...",
    "windows-amd64": "e5f6a7..."
  }
}
```

SHA verification non-negotiable (supply-chain defense).

### 4.7 State schema — version read compatibility (v1 review C2 resolved)

Go binary handles state files at 1.6.0 through 1.9.0.

**Explicit per-version migrations** in `core/internal/state/migrate.go`:

| From | To | Transform |
|---|---|---|
| 1.6.0 | 1.7.0 | Add `cost_cap_decisions: []`, `cost.cap_breached: false` (Phase 2) |
| 1.7.0 | 1.8.0 | Add `pending: null`, `plan.sha256: ""`, `abort_context: null`, `e3_overrides: []`, `components[].mid_stage_cursor: null`; add `APPLY_GATE`, `APPLY_GATE_WAIT`, `PLAN_EDIT_WAIT` to story_state enum (Phase 4) |
| 1.8.0 | 1.9.0 | Add `branch: null`, `bestof: null`, `tui: null` (Phase 5) |

Each transform is idempotent (running twice produces same output). All transforms run in sequence; version < 1.6.0 is rejected as "too old; reinitialize via /forge-recover reset".

**Equivalence testing (AC addition):** `tests/fixtures/state/v1.6.0-valid.json`, `v1.7.0-valid.json`, `v1.8.0-valid.json`, `v1.9.0-valid.json` fixtures exist. Go migration of each older fixture produces byte-identical output (after `jq -S` canonicalization) to the existing bash-plus-python migration pipeline run against the same fixture. `tests/contract/forge-core.bats` enforces this.

Schema file `shared/state-schema.json` is the source of truth for the *target* (1.9.0) shape; Go binary reads it at startup to stay in sync without a rebuild.

### 4.8 Performance targets

Measured against current bash implementation on a ~500-file project:

| Op | Current | Target |
|---|---|---|
| `forge-state.sh read` | ~180ms | ≤ 20ms |
| `forge-state-write.sh patch ...` | ~280ms | ≤ 30ms |
| `forge-token-tracker.sh record` (incl Python) | ~350ms | ≤ 100ms (most stays in Python) |
| `build-code-graph.sh --full` (500 files) | ~90s | ≤ 15s |
| Binary startup | N/A | ≤ 10ms |

Benchmarked via `core/cmd/forge-core/benchmarks/` + `go test -bench`. Published in release notes.

### 4.9 Contract doc — `shared/forge-core-contract.md` (new)

Sections:

- §1 CLI surface + subcommand inventory
- §2 Bash shim pattern (reference for the 4 scripts)
- §3 Binary distribution + SHA verification
- §4 State schema read compatibility (1.6.0 → 1.9.0)
- §5 Python heredoc interop (`forge-token-tracker.sh`)
- §6 `FORGE_DRY_RUN` semantics
- §7 Performance targets (§4.8 table)
- §8 Testing matrix (Go unit tests + bats integration tests against shim)
- §9 Enforcement map

### 4.10 Documentation updates

- `README.md` — new "Native Windows support (5.0.0+)" section; installation via `/forge-init` auto-download; checksum verification.
- `CLAUDE.md` — new "Go core binary" entry in Key Entry Points; note 4 shimmed scripts.
- `CONTRIBUTING.md` — new section on contributing to `core/` (Go toolchain requirements, `make test`, cross-compile matrix).
- `CHANGELOG.md` — 5.0.0 entry.
- `docs/frontend-guide.md` (from Phase 6) — add Windows-native caveat if any affects FE workflow (none expected).
- `DEPRECATIONS.md` — new `## Changed in 5.0.0` section documenting the shim approach + binary dependency.
- `.claude-plugin/plugin.json`, `marketplace.json` — `4.2.0 → 5.0.0`.

### 4.11 Testing

**Unit tests (Go):** `core/internal/state/*_test.go` etc. Run via `go test ./core/...` in a new CI job.

**Integration tests (bats):** extend `tests/unit/skill-execution/` with fixtures that invoke the shims (`forge-state.sh`, etc.) and assert they return the same output as the pre-5.0.0 bash versions (golden-file diffing against a pre-Phase-7 snapshot).

**Cross-platform CI matrix:** GitHub Actions builds + tests on `ubuntu-latest`, `macos-latest`, `windows-latest` (this one runs forge-core.exe directly via PowerShell, not through bash).

**Release verification:** a smoke job downloads each released binary, checksum-verifies, runs `forge-core --version` + `forge-core state read` against a fixture `.forge/state.json`.

## 5. File manifest

### 5.1 Delete

None. Bash scripts are permanent shims, not deleted.

### 5.2 Create

**Go source (~20 files):**

```
core/cmd/forge-core/main.go
core/internal/state/{read,write,transition,migrate,schema}.go
core/internal/cost/{record,cap,pricing}.go
core/internal/graph/{build,schema}.go
core/internal/platform/{lock,atomic}.go
core/go.mod
core/go.sum
core/Makefile
core/README.md
# Plus _test.go siblings: ~10 test files
```

**Docs + CI + shim infrastructure:**

```
shared/forge-core-contract.md
shared/bin/.gitkeep
.github/workflows/release-core.yml
tests/contract/forge-core.bats
tests/fixtures/state/v1.9.0-valid.json       # (already created in Phase 4, but reused)
```

Total creation: **~25 files**.

### 5.3 Update in place

- `shared/forge-state.sh` → 1-line shim
- `shared/forge-state-write.sh` → 1-line shim
- `shared/forge-token-tracker.sh` → hybrid wrapper (bash calls forge-core, Python heredoc stays)
- `shared/graph/build-code-graph.sh` → 1-line shim
- `skills/forge-init/SKILL.md` — add auto-download step + `--update-core` flag
- `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `DEPRECATIONS.md`
- `.claude-plugin/plugin.json`, `marketplace.json`
- `.gitignore` — add `shared/bin/forge-core-*` (binaries not committed)

**Total updates:** 12 files.

### 5.4 Total

~37 file operations (25 create + 12 update). Significant by count; bounded by clear file-list.

## 6. Acceptance criteria

All verified by CI on push.

1. `core/` directory exists with Go module structure per §4.1.
2. `go test ./core/...` passes on macOS, Linux, Windows CI runners.
3. `forge-core --version` prints the plugin version.
4. `forge-core state read` returns same JSON as pre-5.0.0 `forge-state.sh read` against identical `.forge/state.json` fixtures.
5. `forge-core state write` and `state transition` subcommands honor `FORGE_DRY_RUN=1`.
6. `forge-core cost record` writes `cost.inc` event matching Phase 2 schema.
7. `forge-core graph build --full` populates `.forge/code-graph.db` per Phase 1/2/3 SQL schema.
8. The 4 bash shims (`forge-state.sh`, `forge-state-write.sh`, `forge-token-tracker.sh`, `build-code-graph.sh`) exec forge-core and return identical output to the pre-5.0.0 versions for the golden-file test corpus.
9. `.github/workflows/release-core.yml` exists; triggers on `v5.*` tags; builds 5 binaries; uploads to release.
10. `/forge-init` auto-downloads the matching binary + SHA-verifies; `--update-core` flag refreshes.
11. `shared/forge-core-contract.md` exists with 9 sections per §4.9.
12. `DEPRECATIONS.md` documents the shim approach + binary dependency in 5.0.0 section.
13. `.gitignore` excludes `shared/bin/forge-core-*` binaries.
14. Benchmarks publish to release notes; all meet §4.8 targets.
15. `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `CHANGELOG.md` updated per §4.10.
16. `.claude-plugin/plugin.json` + `marketplace.json` set to `5.0.0`.
17. CI green; native Windows runner tests pass.

## 7. Test strategy

**Go unit tests:** `go test ./core/... -cover` with ≥80% coverage target on `internal/state`, `internal/cost`, `internal/graph`.

**Cross-platform CI matrix:** GitHub Actions `.github/workflows/release-core.yml` + extension to `tests/` workflow building and testing on `ubuntu-latest` + `macos-latest` + `windows-latest`.

**Integration tests (bats):** `tests/contract/forge-core.bats` runs each shim against a golden-file state fixture and diffs output against `tests/fixtures/forge-core/expected/*.json`.

**Release verification:** separate CI job downloads each released binary from GitHub release, checksum-verifies, runs `forge-core --version` + `forge-core state read` against fixture. Prevents silent release-binary corruption.

Per user: no local test runs. All verification via CI.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Binary size (Go ~7MB vs bash 4KB) inflates repo | Low | Low | Binaries gitignored; downloaded via release, not source |
| Cross-compile for Windows breaks due to CGO (tree-sitter) | High | High | **WASM tree-sitter is the path (v1 review I1 correction).** `smacker/go-tree-sitter` actually uses CGO despite prior claims. Phase 7 uses WASM tree-sitter via `wasmtime-go` or pure-Go implementations like `forest/tree-sitter` (WASM-embedded grammars via `//go:embed`). Build-matrix runs `CGO_ENABLED=0 go build` across all 5 targets — single Linux runner cross-compiles everything. Locked at plan-stage Commit 2 before any tree-sitter code is written. |
| State-schema version migration logic has bugs for older v1.6 files | Medium | High | Extensive fixture-based tests per version; golden-file regression tests against pre-5.0.0 bash output |
| Supply-chain attack on binary download | Low | High | SHA256 checksum verification mandatory; GitHub releases served over HTTPS; checksums in release notes |
| User has custom bash scripts that source the shims | Low | Low | Audit during Phase 7 plan execution; document in DEPRECATIONS.md that scripts must be invoked, not sourced |
| Python heredoc in forge-token-tracker.sh becomes a stale layer | Medium | Medium | Documented as transitional in §4.4; tracked in `shared/forge-core-contract.md §5` as future Go port candidate |
| Go version drift in contributor environments | Low | Low | `core/go.mod` pins minor Go version (1.22+); `core/README.md` documents the version |
| GitHub releases rate-limit `/forge-init` auto-download | Low | Low | Add retry-with-backoff; document fallback manual-download path |
| Windows PowerShell path handling differs from Unix | Medium | Medium | forge-core uses `filepath.Join` (Go stdlib, cross-platform); CI tests on Windows runner verify paths |
| tree-sitter grammar loading differs cross-platform | Medium | Medium | Bundle grammars as embedded assets via `//go:embed`; verified on Windows CI |
| User has no internet at `/forge-init` | Medium | Low | Document offline install: "download forge-core-$OS-$ARCH from GitHub releases, place in shared/bin/, chmod +x" |
| Permanent shim adds indirection cost | Low | Low | Bash exec is O(1); measured overhead <5ms |

## 9. Rollout (one PR, multi-commit; CI gates on HEAD)

1. **Commit 1 — Specs land.** This spec + plan.
2. **Commit 2 — Go project scaffold.** `core/` directory with `main.go`, `go.mod`, `Makefile`, internal package structure. All TODO-placeholder implementations but `go build` succeeds. CI green.
3. **Commit 3 — `forge-core state` subcommand.** Full read/write/transition implementation + Go unit tests. `tests/contract/forge-core.bats` Group A. CI green.
4. **Commit 4 — `forge-core cost` subcommand.** cost record/get/cap-check + Python heredoc integration. CI green.
5. **Commit 5 — `forge-core graph` subcommand.** Tree-sitter SQLite population. CI green.
6. **Commit 6 — Bash shims + `.gitignore`.** 4 shim files; `shared/bin/.gitkeep`; `.gitignore` update. Shims activate on HEAD; prior bash behavior preserved via delegation. CI green.
7. **Commit 7 — Release workflow + `/forge-init` auto-download.** `.github/workflows/release-core.yml`; `skills/forge-init/SKILL.md` extended with download step. CI green.
8. **Commit 8 — Contract doc + top-level docs + version bump.** `shared/forge-core-contract.md`, README, CLAUDE.md, CONTRIBUTING.md, CHANGELOG.md, DEPRECATIONS.md, plugin.json, marketplace.json → 5.0.0. CI green.
9. **Push → CI matrix (Ubuntu + macOS + Windows) green → tag `v5.0.0` → release workflow builds + uploads 5 binaries → release verification job passes.**

## 10. Versioning rationale

SemVer **major** because:
1. New runtime dependency (forge-core binary).
2. Distribution model changes (GitHub releases required for binary download).
3. Plugin cache layout changes (`shared/bin/` populated at install time).
4. User-visible behavior change: `/forge-init` downloads a binary.

No API breaks (shims preserve interfaces). But the dependency shift alone warrants 5.0.0.

## 11. Open questions

None. All decisions locked in brainstorming.

## 12. References

- Phases 1-6 specs (same directory).
- `shared/state-schema.md` + `.json` (1.9.0 target).
- `shared/graph/code-graph-schema.sql` (SQLite schema forge-core reads).
- `shared/model-pricing.json` (cost pricing forge-core reads).
- `shared/forge-token-tracker.sh` (Python heredoc kept as sub-process callee).
- Plandex (Go single-binary reference; pure-Go tree-sitter usage).
- `github.com/smacker/go-tree-sitter` (Go tree-sitter binding; evaluate at plan stage).
- User instruction: "I want it all except the backwards compatibility" + scope selection in brainstorming (4 hot-path scripts).
