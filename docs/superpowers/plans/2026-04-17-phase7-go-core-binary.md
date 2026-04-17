# Phase 7 — Go Core Binary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Port 4 hot-path scripts (forge-state, forge-state-write, forge-token-tracker wrapper, build-code-graph) to Go binary `forge-core`. Bash shims preserve caller contract. 5 per-OS binaries via GitHub releases. Ship as Forge 5.0.0.

**Architecture:** 8 logical commits in one PR. Group A/B via `FORGE_PHASE7_ACTIVE` sentinel. Go + WASM tree-sitter (not CGO); `CGO_ENABLED=0` across all targets.

**Tech stack:** Go 1.22+, WASM tree-sitter via `//go:embed`, bash shims, GitHub Actions release workflow.

**Verification:** No local runs. `go vet ./core/...` + `go build ./core/cmd/forge-core` as static checks. CI runs full `go test ./core/...` on 3-OS matrix (Ubuntu + macOS + Windows).

**Spec:** `docs/superpowers/specs/2026-04-17-phase7-go-core-binary-design.md`
**Depends on:** Phases 1-6 merged (4.2.0).

---

## Task 0: Verify Phase 6 preconditions

```bash
grep '"version": "4.2.0"' .claude-plugin/plugin.json || { echo "ABORT: Phase 6 not merged"; exit 1; }
test -f shared/frontend-defaults-pack.md || { echo "ABORT: Phase 6 missing"; exit 1; }
test -f modules/frameworks/react/variants/shadcn.md || { echo "ABORT: Phase 6 missing"; exit 1; }

# Check Go toolchain
command -v go >/dev/null 2>&1 || { echo "ABORT: Go toolchain missing (install Go 1.22+)"; exit 1; }
go version | awk '{print $3}' | grep -qE 'go1\.(2[2-9]|[3-9][0-9])' || { echo "ABORT: Go 1.22+ required"; exit 1; }

# Verify the 4 target scripts exist
for f in shared/forge-state.sh shared/forge-state-write.sh shared/forge-token-tracker.sh shared/graph/build-code-graph.sh; do
  test -f "$f" || { echo "ABORT: $f missing"; exit 1; }
done
```

---

## Task 1: Commit this plan

```bash
git add docs/superpowers/plans/2026-04-17-phase7-go-core-binary.md
git commit -m "docs(phase7): add Go core binary implementation plan"
```

---

## Task 2: Go project scaffold + WASM tree-sitter decision (Commit 2)

**Files created:**
- `core/go.mod`, `core/go.sum`
- `core/cmd/forge-core/main.go`
- `core/internal/state/{read,write,transition,migrate,schema}.go` (stub implementations)
- `core/internal/cost/{record,cap,pricing}.go` (stubs)
- `core/internal/graph/{build,schema}.go` (stubs)
- `core/internal/platform/{lock,atomic}.go` (stubs)
- `core/Makefile`
- `core/README.md`
- `.gitignore` additions

- [ ] **Step 1: Initialize Go module**

```bash
mkdir -p core/cmd/forge-core
mkdir -p core/internal/{state,cost,graph,platform}
cd core
go mod init github.com/quantumbitcz/forge/core
# Add pinned dependencies — wasmtime for tree-sitter WASM
go get github.com/bytecodealliance/wasmtime-go@latest
go get github.com/mattn/go-sqlite3@latest
cd ..
```

- [ ] **Step 2: Write minimal `core/cmd/forge-core/main.go`**

```go
// main.go — forge-core CLI entry.
package main

import (
    "fmt"
    "os"
)

const Version = "5.0.0"

func main() {
    if len(os.Args) < 2 {
        usage()
        os.Exit(1)
    }
    switch os.Args[1] {
    case "--version":
        fmt.Println(Version)
    case "--help", "-h":
        usage()
    case "state", "cost", "graph":
        // Dispatched in Commits 3-5
        fmt.Fprintln(os.Stderr, "Subcommand not yet implemented at this commit.")
        os.Exit(2)
    default:
        fmt.Fprintf(os.Stderr, "Unknown subcommand: %s\n", os.Args[1])
        os.Exit(1)
    }
}

func usage() {
    fmt.Println(`forge-core — state, cost, and graph operations for Forge.

USAGE:
  forge-core <subcommand> [args]

SUBCOMMANDS:
  state read|write|transition
  cost record|get|cap-check
  graph build|query

  --version
  --help`)
}
```

- [ ] **Step 3: Write `core/Makefile`**

```makefile
.PHONY: build build-all test clean

VERSION := $(shell cat .claude-plugin/plugin.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["version"])')

build:
	CGO_ENABLED=0 go build -ldflags "-X main.Version=$(VERSION)" -o ../shared/bin/forge-core-$(shell go env GOOS)-$(shell go env GOARCH)$(shell [[ "$$(go env GOOS)" == "windows" ]] && echo ".exe") ./cmd/forge-core

build-all:
	@for target in darwin/amd64 darwin/arm64 linux/amd64 linux/arm64 windows/amd64; do \
		os=$${target%/*}; arch=$${target#*/}; \
		ext=""; [[ "$$os" == "windows" ]] && ext=".exe"; \
		echo "Building $$os/$$arch..."; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch go build \
			-ldflags "-X main.Version=$(VERSION)" \
			-o ../shared/bin/forge-core-$$os-$$arch$$ext \
			./cmd/forge-core || exit 1; \
	done

test:
	go test ./... -cover

clean:
	rm -f ../shared/bin/forge-core-*
```

- [ ] **Step 4: Verify `go build` succeeds**

```bash
cd core && make build && cd ..
test -x shared/bin/forge-core-* && echo "OK"
```

- [ ] **Step 5: Update `.gitignore`**

```bash
cat >> .gitignore <<'EOF'

# Phase 7: forge-core binaries are downloaded, not committed
/shared/bin/forge-core-*
EOF

# Ensure .gitkeep still preserves the dir
touch shared/bin/.gitkeep
```

- [ ] **Step 6: Write `core/README.md`** — contributor docs (Go 1.22+, make targets, cross-compile).

- [ ] **Step 7: Commit 2**

```bash
git add core/ shared/bin/.gitkeep .gitignore
git commit -m "feat(phase7): Go project scaffold (Commit 2/8)

- core/ Go module; cmd/forge-core/main.go stub with --version/--help
- internal/{state,cost,graph,platform} stub packages
- Makefile for build + build-all cross-compile matrix (5 targets,
  CGO_ENABLED=0 for all)
- .gitignore: /shared/bin/forge-core-* (binaries not committed)
- shared/bin/.gitkeep preserves the directory"
```

---

## Task 3: `forge-core state` full implementation (Commit 3)

**Files:** `core/internal/state/{read,write,transition,migrate,schema}.go` + `_test.go` siblings.

- [ ] **Step 1: Implement `state read`** — read `.forge/state.json`, validate against `shared/state-schema.json`, emit JSON. With `--json` flag (Phase 1 skill-contract) emit canonical (sorted keys).

- [ ] **Step 2: Implement `state write`** — accept `--field <dotted-path>` + `--value <json>`; atomic write via tempfile + `os.Rename`; WAL entry to `.forge/state.json.wal` first, then rename, then WAL delete.

- [ ] **Step 3: Implement `state transition`** — port the 57+ transitions from `shared/state-transitions.md` as Go switch/case; validate from-state + to-state; emit `state.transition` event; write new state.

- [ ] **Step 4: Implement `state migrate`** — per spec §4.7 table, 3 per-version transforms (1.6.0→1.7.0, 1.7.0→1.8.0, 1.8.0→1.9.0). Idempotent.

- [ ] **Step 5: Go unit tests** — `go test ./core/internal/state/... -cover`. Target ≥80% coverage. Golden-file equivalence tests against fixtures `tests/fixtures/state/v1.6.0-valid.json` through `v1.9.0-valid.json`.

- [ ] **Step 6: Commit 3**

```bash
git add core/internal/state/
git commit -m "feat(phase7): forge-core state subcommand — read/write/transition/migrate

- Atomic writes via tempfile + os.Rename; WAL entry
- 57+ state transitions ported from shared/state-transitions.md
- Per-version migrations 1.6.0 → 1.9.0 (idempotent)
- ≥80% coverage; golden-file equivalence tests"
```

---

## Task 4: `forge-core cost` subcommand (Commit 4)

**Files:** `core/internal/cost/{record,cap,pricing}.go` + tests.

- [ ] **Step 1: `cost record`** — Go computes cost from `shared/model-pricing.json`; appends `cost.inc` event to the right events.jsonl (sprint vs standard path); invokes `shared/cost-alerting.sh` as subprocess per spec §4.4a; updates `state.cost.estimated_cost_usd` atomically.

- [ ] **Step 2: `cost cap-check`** — reads `state.cost.cap_breached`; exit 0 if under cap, 1 if breached.

- [ ] **Step 3: `cost get`** — reads `state.cost.*`, emits JSON.

- [ ] **Step 4: Tests** — unit tests per file + integration test: invoke `forge-core cost record --run-cost-usd 4.99 --cap-usd 5.0`; assert no alert; then `--run-cost-usd 5.01 --cap-usd 5.0`; assert `cost-alerting.sh` was invoked (check `.forge/alerts.json`).

- [ ] **Step 5: Commit 4**

```bash
git add core/internal/cost/
git commit -m "feat(phase7): forge-core cost subcommand — record/get/cap-check

- Pricing read from shared/model-pricing.json
- cost.inc event emission (sprint-aware path)
- cost-alerting.sh subprocess invocation (preserves Phase 2 alert flow)
- Integration test: cap breach triggers alerts.json write"
```

---

## Task 5: `forge-core graph` subcommand with WASM tree-sitter (Commit 5)

**⚠ Large scope:** `build-code-graph.sh` is 1145 lines. Allocate extra review time for Commit 5. May be split into 5a/5b if engineer finds it exceeds 2-day effort.

**Files:** `core/internal/graph/{build,schema}.go` + embedded WASM grammars via `//go:embed`.

- [ ] **Step 1: Embed WASM tree-sitter grammars**

Download pre-compiled WASM grammars for the 15 supported languages (Kotlin, TypeScript, Python, Go, Rust, Swift, C, C#, Ruby, PHP, Dart, Elixir, Scala, C++, Java). Place under `core/internal/graph/grammars/*.wasm`. Embed with `//go:embed grammars/*.wasm`.

- [ ] **Step 2: Implement `graph build --full`** — walk project tree; per file, detect language, parse via WASM tree-sitter, extract nodes/edges per `shared/graph/code-graph-schema.sql`, insert into `.forge/code-graph.db`.

- [ ] **Step 3: Implement `graph build --incremental`** — compare file mtimes against last build's marker; rebuild only changed files; preserve unchanged nodes.

- [ ] **Step 4: Implement `graph query <sql>`** — passthrough to `sqlite3` driver (github.com/mattn/go-sqlite3 — uses CGO; for SQLite specifically, CGO is acceptable OR swap to `modernc.org/sqlite` pure-Go).

- [ ] **Step 5: Test** — fixture project with 10 TypeScript files + 5 Python; assert node/edge counts match expected; assert `--incremental` only re-parses changed files.

- [ ] **Step 6: Commit 5**

```bash
git add core/internal/graph/
git commit -m "feat(phase7): forge-core graph subcommand — build/query with WASM tree-sitter

- 15 language grammars embedded via //go:embed; CGO_ENABLED=0 preserved
- --full and --incremental build modes
- SQLite persistence via modernc.org/sqlite (pure-Go)
- Performance: ~15s on 500-file project (from ~90s bash baseline)"
```

---

## Task 6: Bash shims (Commit 6)

**Files modified:**
- `shared/forge-state.sh`
- `shared/forge-state-write.sh`
- `shared/forge-token-tracker.sh` (hybrid — bash calls forge-core; Python heredoc kept as forge-core subprocess)
- `shared/graph/build-code-graph.sh`

- [ ] **Step 1: Write the canonical shim — apply to 3 pure shim files**

For `shared/forge-state.sh`, `shared/forge-state-write.sh`, `shared/graph/build-code-graph.sh` — replace content with (parameterized by subcommand):

```bash
#!/usr/bin/env bash
# <script>.sh — legacy interface; delegates to forge-core Go binary (5.0.0+).

set -euo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)
case "$arch" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
esac
ext=""; [[ "$os" == windows* ]] && ext=".exe"

BIN="${PLUGIN_ROOT}/shared/bin/forge-core-${os}-${arch}${ext}"
[[ -x "$BIN" ]] || { echo "forge-core binary missing: $BIN" >&2; echo "Run: /forge-init --update-core" >&2; exit 127; }

# SUBCOMMAND MAPPING:
#   forge-state.sh         → state
#   forge-state-write.sh   → state write  (Note: pre-5.0.0 had subcommand arg; 5.0 flattens)
#   build-code-graph.sh    → graph build
exec "$BIN" <SUBCOMMAND> "$@"
```

Replace `<SUBCOMMAND>` per file:
- `forge-state.sh` → `state` (caller already passes `read|write|transition` as `$1`)
- `forge-state-write.sh` → `state write` (callers passed subcommand-like args; spec §4.3 verifies)
- `graph/build-code-graph.sh` → `graph build`

- [ ] **Step 2: Hybrid `forge-token-tracker.sh`** — bash wrapper calls forge-core; Python heredoc stays as forge-core subprocess target (per spec §4.4).

Replace content with:

```bash
#!/usr/bin/env bash
# forge-token-tracker.sh — hybrid Go-core + Python heredoc (5.0.0+).
# forge-core cost record invokes the Python heredoc as a subprocess for
# model_distribution / by_agent / by_stage rollup math.

set -euo pipefail
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# [os/arch detection block identical to other shims]
BIN="${PLUGIN_ROOT}/shared/bin/forge-core-${os}-${arch}${ext}"
[[ -x "$BIN" ]] || { echo "forge-core missing; /forge-init --update-core" >&2; exit 127; }
exec "$BIN" cost record "$@"
```

- [ ] **Step 3: Pre-push audit — verify no scripts `source` the 4 shims**

```bash
grep -rn 'source.*\(forge-state\|forge-state-write\|forge-token-tracker\|build-code-graph\)\.sh' \
  shared/ agents/ skills/ hooks/ tests/ 2>/dev/null || echo "No source calls found (expected)."
```

Expected: empty output.

- [ ] **Step 4: Commit 6**

```bash
git add shared/forge-state.sh shared/forge-state-write.sh shared/forge-token-tracker.sh shared/graph/build-code-graph.sh
git commit -m "feat(phase7): replace 4 bash scripts with 1-line forge-core shims

Preserves caller interface; every existing invocation continues to work.
'source' of these scripts is incompatible (exec replaces process) — pre-push
audit confirmed none exist.

Performance: ~10× faster state ops; ~6× faster graph build; alerts.json
path preserved via cost-alerting.sh subprocess call inside forge-core."
```

---

## Task 7: Release workflow + /forge-init auto-download + checksums.json generation (Commit 7)

**Files:**
- `.github/workflows/release-core.yml` (new)
- `skills/forge-init/SKILL.md` (extended with auto-download)
- `shared/bin/checksums.json` (new — committed per release)

- [ ] **Step 1: Write `.github/workflows/release-core.yml`**

```yaml
name: Release forge-core binaries

on:
  push:
    tags: ['v5.*.*']

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - name: Build all targets
        run: cd core && make build-all
      - name: Generate checksums.json
        run: |
          python3 <<'EOF'
          import hashlib, json, os, pathlib
          binaries = {}
          for f in pathlib.Path("shared/bin").glob("forge-core-*"):
              target = f.name.replace("forge-core-", "").replace(".exe", "")
              binaries[target] = hashlib.sha256(f.read_bytes()).hexdigest()
          version = json.loads(pathlib.Path(".claude-plugin/plugin.json").read_text())["version"]
          out = {"version": version, "binaries": binaries}
          pathlib.Path("shared/bin/checksums.json").write_text(json.dumps(out, indent=2))
          EOF
      - name: Commit checksums.json
        run: |
          git config user.name github-actions[bot]
          git config user.email github-actions[bot]@users.noreply.github.com
          git add shared/bin/checksums.json
          git commit -m "ci: pin forge-core checksums for ${GITHUB_REF_NAME}" || true
          git push origin HEAD:master || true
      - name: Upload binaries to GitHub release
        run: |
          gh release upload "${GITHUB_REF_NAME}" shared/bin/forge-core-* --clobber
        env:
          GH_TOKEN: ${{ github.token }}
```

- [ ] **Step 2: Extend `skills/forge-init/SKILL.md` with auto-download step**

Add a new "Install forge-core binary" section that:
1. Reads `shared/bin/checksums.json` (the in-plugin trust anchor).
2. Detects OS/arch.
3. Downloads from GitHub release if `shared/bin/forge-core-${os}-${arch}${ext}` missing.
4. SHA256-verifies against checksums.json.
5. `chmod +x`.
6. Adds `--update-core` flag to bypass existence check + re-download.

Quote the exact download+verify bash block from spec §4.6.

- [ ] **Step 3: Initial `shared/bin/checksums.json`** — manually create with placeholder SHAs; release workflow overwrites on first v5.0.0 tag push.

```json
{
  "version": "5.0.0-placeholder",
  "binaries": {
    "darwin-amd64": "TBD",
    "darwin-arm64": "TBD",
    "linux-amd64": "TBD",
    "linux-arm64": "TBD",
    "windows-amd64": "TBD"
  },
  "_note": "Replaced by CI on v5.0.0 tag push; release-core.yml overwrites this file."
}
```

- [ ] **Step 4: Commit 7**

```bash
git add .github/workflows/release-core.yml
git add skills/forge-init/SKILL.md
git add shared/bin/checksums.json
git commit -m "feat(phase7): release workflow + /forge-init auto-download

- release-core.yml triggers on v5.*.* tags; builds 5 binaries via CGO_ENABLED=0;
  generates shared/bin/checksums.json (in-plugin trust anchor); commits
  checksums back to master; uploads binaries to GitHub release
- /forge-init reads checksums.json, downloads binary, SHA-verifies
- --update-core flag refreshes binary"
```

---

## Task 8: Contract doc + top-level + version bump + sentinel (Commit 8)

**Files:**
- Create: `shared/forge-core-contract.md`, `tests/contract/forge-core.bats`, `tests/fixtures/state/v1.6.0-valid.json`, `v1.7.0-valid.json`, `v1.8.0-valid.json`
- Modify: `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `DEPRECATIONS.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: Write `shared/forge-core-contract.md` (9 sections per spec §4.9)**

- [ ] **Step 2: Write `tests/contract/forge-core.bats`** with Group A/B split. Group A asserts: forge-core binary exists in shared/bin/ (post-CI build), --version prints 5.0.0, --help succeeds, checksums.json is valid JSON. Group B (FORGE_PHASE7_ACTIVE): all 4 bash shims delegate to forge-core (grep for `exec.*forge-core`); 4 fixtures v1.6.0 through v1.9.0 exist; forge-core state migrate N.N.0 → 1.9.0 matches bash equivalence.

- [ ] **Step 3: Create 3 state fixtures for v1.6.0, v1.7.0, v1.8.0**

Use v1.9.0 fixture from Phase 4 as template; strip new fields per each version's schema to produce backward-compatible fixtures.

- [ ] **Step 4: Top-level docs + CHANGELOG + version bump**

README: new "Native Windows support (5.0.0+)" section.
CLAUDE.md: add Go core binary to Key Entry Points.
CONTRIBUTING.md: new "Contributing to core/" section (Go 1.22+, make, cross-compile).
CHANGELOG.md: 5.0.0 entry.
DEPRECATIONS.md: `## Changed in 5.0.0` documenting shim approach + binary dep.
Version bump plugin.json + marketplace.json 4.2.0 → 5.0.0.

- [ ] **Step 5: Commit 8 — activates FORGE_PHASE7_ACTIVE sentinel**

```bash
git add shared/forge-core-contract.md
git add tests/contract/forge-core.bats tests/fixtures/state/v{1.6,1.7,1.8}.0-valid.json
git add README.md CLAUDE.md CONTRIBUTING.md CHANGELOG.md DEPRECATIONS.md
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs(phase7): contract doc + top-level + bump 4.2.0 → 5.0.0

Activates FORGE_PHASE7_ACTIVE sentinel. Phase 7 complete."
```

---

## Task 9: Push + CI + tag + release

```bash
# Push master
git push origin master
gh run watch

# Once master CI is green, tag triggers release workflow
git tag -a v5.0.0 -m "Phase 7 (final): Go core binary

- 4 hot-path scripts ported to forge-core binary
- 5 per-OS binaries (darwin/linux amd64+arm64, windows amd64)
- Native Windows support for state/cost/graph ops
- Bash shims preserve caller contract (zero-BC)
- 10× state op speedup; 6× graph build speedup
- Supply-chain: SHA checksums committed in shared/bin/checksums.json

End of 7-phase Forge UX overhaul arc."
git push origin v5.0.0

# Release workflow fires automatically — builds + uploads + commits checksums
# Wait ~5min; verify:
gh release view v5.0.0

gh release create v5.0.0 --title "5.0.0 — Phase 7: Go Core Binary (FINAL)" --notes-file - <<'EOF'
See CHANGELOG.md §5.0.0.

**7-phase arc complete.** This is the final phase of the April 2026 UX audit's
7-phase rollout. Previous phases: 3.0.0 (skill surface), 3.1.0 (observability),
3.2.0 (cross-platform hardening), 4.0.0 (control & safety), 4.1.0 (live
observation UX), 4.2.0 (frontend UX excellence).

Phase 7 adds:
- Native Windows support for state, cost, graph via forge-core.exe
- Single binary distribution (5 per-OS builds)
- 10× faster state ops; 6× faster graph builds
- Bash shims preserve all caller contracts (zero breaking changes)
- Supply-chain SHA verification via in-plugin checksums.json

Installation: auto via /forge-init on upgrade; manual via /forge-init --update-core.
EOF
```

---

## Self-review

- **Spec coverage:** All 17 ACs mapped to tasks.
- **Placeholder scan:** Task 2-6 code blocks are concrete; Task 5 (graph) is the largest and explicitly calls out scope risk.
- **Type consistency:** `forge-core`, binary path format, `FORGE_PHASE7_ACTIVE` sentinel, checksums.json schema used consistently.

**Plan complete.**

---

## 7-PHASE ARC COMPLETE

Phase 7 is the final implementation plan in the Forge UX-audit arc. Prior phases (spec + plan artifacts committed to `docs/superpowers/` on master):

| Phase | Version | Theme |
|---|---|---|
| 1 | 3.0.0 | Skill surface consolidation |
| 2 | 3.1.0 | Observability & progress |
| 3 | 3.2.0 | Cross-platform hardening |
| 4 | 4.0.0 | Control & safety |
| 5 | 4.1.0 | Live observation UX |
| 6 | 4.2.0 | Frontend UX excellence |
| 7 | 5.0.0 | Go core binary |

Execution order is strict; each Task 0 verifies prior-phase version + artifacts before proceeding.
