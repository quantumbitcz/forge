# Phase 3 — Cross-Platform Hardening (Design)

**Status:** Draft for review
**Date:** 2026-04-17
**Target version:** Forge 3.2.0 (minor — additive; no breaking user-facing changes)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 3 of 7
**Depends on:** Phase 2 merged (3.1.0 released).

---

## 1. Goal

Eliminate known bashisms from the shell-script surface so Forge runs reliably on macOS/Linux/WSL2/Git Bash; add a cross-platform helper library; introduce a prereq check at `/forge-init` that separates required from optional dependencies with install hints; consolidate the two existing prereq scripts; add functional parity in the SQLite graph backend so `/forge-graph-query` works without Neo4j. This phase is the substrate that makes Phase 7 (Go core binary port) tractable.

## 2. Context and motivation

April 2026 UX audit graded cross-platform support **C+**. Three structural gaps:

1. **Bashisms scattered across 20 shell scripts.** Grep confirms `$'\n'`, `<<<`, `declare -A`, `date +%s%N` in:
   - `shared/checks/engine.sh`, `shared/checks/l0-syntax/validate-syntax.sh`, `shared/checks/layer-1-fast/run-patterns.sh`, `shared/checks/layer-2-linter/run-linter.sh`
   - `shared/config-validator.sh`, `shared/context-guard.sh`, `shared/convergence-engine-sim.sh`, `shared/cost-alerting.sh`
   - `shared/generate-conventions-index.sh`
   - `shared/graph/build-code-graph.sh`, `build-project-graph.sh`, `code-graph-query.sh`, `enrich-symbols.sh`, `generate-seed.sh`, `incremental-code-graph.sh`, `incremental-update.sh`, `update-project-graph.sh`
   - `shared/recovery/health-checks/pre-stage-health.sh`
   - `shared/validate-finding.sh`
   - `shared/platform.sh` itself (acceptable — it implements the wrappers).
2. **Two redundant prereq scripts.** `shared/check-prerequisites.sh` and `shared/check-environment.sh` both exist. No single entry point; `/forge-init` does not invoke either; users on fresh macOS hit cryptic errors instead of `brew install bash`.
3. **SQLite graph backend is not functional-parity with Neo4j for `/forge-graph-query`.** Low-level SQLite primitives exist (`shared/graph/code-graph-query.sh` — 7 subcommands like `search_class`, `search_method`). The user-facing `/forge-graph-query` skill is currently Neo4j/Cypher-only. Users without Docker cannot query their code graph.

The Phase 1 user constraint stands: **no backwards compatibility**. Phase 3 changes are additive to the user — no commands removed — but the internal shell-script API surface is refactored liberally where bashisms are entrenched.

## 3. Non-goals

- **No native Windows PowerShell support.** That's Phase 7's Go binary port territory. Phase 3 targets macOS/Linux/WSL2/Git Bash (where bash is available).
- **No strict POSIX sh everywhere.** `#!/usr/bin/env bash` stays; bash 4+ features remain usable *selectively*. The goal is to **eliminate bashisms that break on BSD `sed`/`stat`, dash, and Git Bash MSYS**, not to purge bash itself.
- **No Neo4j removal.** Neo4j remains supported; SQLite becomes a viable alternative for users without Docker.
- **No changes to L0/L1/L2 check-engine rules.** Only the scripts that implement them are edited to remove bashisms.
- **No rewrite of `shared/forge-token-tracker.sh` Python heredoc** (Phase 2 territory; Phase 3 only touches the bash-around-Python, not the Python itself).
- **Deferred to later phases:**
  - Go core binary → Phase 7
  - Live observation UX (TUI) → Phase 5
  - Preview-before-apply → Phase 4

## 4. Design

### 4.1 Bashism fixes — exact surface

**Banned patterns** (enforced by new `tests/contract/portability.bats`):

| Pattern | Why it breaks | Replacement |
|---|---|---|
| `$'\n'` | Not POSIX; fails on dash; renders wrong in Git Bash MSYS | `printf '\n'` into a variable, OR literal newline inside double quotes |
| `<<<"string"` (here-string) | Bash-only; fails on dash | `printf '%s' "string" \| cmd`, or `echo "string" \| cmd` |
| `declare -A` | Bash 4+ only; fails on macOS default bash 3.2 | File-per-key pattern: `mkdir -p "$tmpdir/keys"; echo "$value" > "$tmpdir/keys/$key"` OR Python hash when complex lookups needed |
| `date +%s%N` | GNU-only; macOS `date` doesn't support `%N` | `platform.sh::epoch_ms` helper (Python-based where nanoseconds needed) |
| `stat -c %Y` or `stat -c %s` | GNU-only syntax; BSD uses `-f %m` / `-f %z` | `platform.sh::file_mtime` / `platform.sh::file_size` |
| `sed -i 's/x/y/'` | GNU accepts no arg; BSD requires `-i ''` | `platform.sh::portable_sed_i` OR `sed -i.bak ... && rm -f *.bak` |
| `realpath` (plain) | Not on macOS without coreutils | `platform.sh::safe_realpath` |
| `find -printf` | GNU-only | Substitute with `-print` + `xargs` or Python |
| `readarray` / `mapfile` | Bash 4+ only | `while IFS= read -r line; do ...; done < file` |

**Exempt location:** `shared/platform.sh` itself — it implements the wrappers and necessarily contains the OS-detection conditionals.

**Exact file-by-file fix plan** (20 files with bashisms detected by grep):

Each file is audited in the plan stage; bashisms are replaced in-place with either the platform.sh wrapper call (if the wrapper exists) or the POSIX alternative. The `tests/contract/portability.bats` asserts zero matches across all `shared/**/*.sh` and `hooks/**/*.sh` (except `platform.sh`).

### 4.2 Extend `shared/platform.sh`

Existing `shared/platform.sh` has OS detection. Phase 3 adds:

| Function | Returns / side-effect |
|---|---|
| `iso_timestamp` | Portable `date -u +%Y-%m-%dT%H:%M:%SZ` — already correct on all platforms |
| `epoch_s` | `date +%s` — seconds since epoch |
| `epoch_ms` | Milliseconds since epoch. `date +%s` × 1000 + Python microsecond fraction when Python present; else just seconds × 1000 |
| `file_mtime <path>` | GNU `stat -c %Y` ↔ BSD `stat -f %m` via `$FORGE_OS` switch |
| `file_size <path>` | GNU `stat -c %s` ↔ BSD `stat -f %z` via `$FORGE_OS` switch |
| `portable_sed_i <file> <expr>` | `sed -i` on GNU, `sed -i ''` on BSD (detected via `FORGE_OS`) |
| `safe_realpath <path>` | `realpath` if available; `python3 -c "import os;print(os.path.realpath(...))"` fallback |
| `has_bash_4` | `[[ ${BASH_VERSINFO[0]} -ge 4 ]]` wrapped in a function for dependency checks |
| `portable_find_mtime <dir> <minutes>` | `find <dir> -mmin -<minutes>` — identical on GNU/BSD for this flag; wrapped for consistency |
| `acquire_lock_with_retry <lockdir> <max-tries> <sleep-ms>` | Already exists in platform.sh per §Phase 2; unchanged |
| `release_lock <lockdir>` | Already exists; unchanged |

`shared/platform.sh` is source-once-per-script; all consumers `source "${PLUGIN_ROOT}/shared/platform.sh"` at top. `FORGE_OS` is cached in the environment to avoid repeated detection.

### 4.3 `shared/cross-platform-contract.md` (new)

Authoritative doc. Contents:

- §1 Banned patterns (Table from §4.1 above)
- §2 `platform.sh` helper catalog (Table from §4.2 above)
- §3 When to use helpers vs POSIX alternatives (decision guide)
- §4 Testing — bash 3.2 smoke, BSD sed compat, Git Bash caveats
- §5 Adding new scripts — checklist (must `source platform.sh`, must `bash -n` pass, must `shellcheck --severity=warning` pass, must not introduce banned patterns)
- §6 Known limitations — Windows native (deferred to Phase 7), busybox sh, zsh-only environments

Cross-referenced from `README.md`, `CLAUDE.md`, and `CONTRIBUTING.md`.

### 4.4 Consolidated prereq check — `shared/check-prerequisites.sh`

**Existing state:** two scripts (`check-prerequisites.sh`, `check-environment.sh`). Phase 3 keeps `check-prerequisites.sh` as the canonical entry point, folds `check-environment.sh`'s content into it, and deletes the latter.

**API:**

```bash
./shared/check-prerequisites.sh [--json] [--strict]
```

- Default: human-readable report + exit code (0 = all required present, 1 = required missing, 2 = required present but optional missing).
- `--json`: structured output `{required: {...}, optional: {...}, abort_reason: null|string}`.
- `--strict`: treat optional-missing as exit 1 instead of 2.

**Required dependencies (abort if missing):**

| Tool | Check | Install hint (per platform) |
|---|---|---|
| `bash` ≥4.0 | `has_bash_4` | macOS: `brew install bash`. Linux: already present. WSL: already present. |
| `python3` | `command -v python3` | macOS: pre-installed. Linux: `apt/dnf install python3`. |
| `jq` | `command -v jq` | macOS: `brew install jq`. Linux: `apt/dnf install jq`. |

**Optional dependencies (warn + record):**

| Tool | Used for | Install hint |
|---|---|---|
| `docker` | Neo4j graph backend | macOS: Docker Desktop. Linux: `docker-ce` or Podman. |
| `gh` | GitHub CLI for PR creation, release | `brew install gh` or `apt install gh` |
| `tree-sitter` | L0 syntax checks in PreToolUse hook | `npm install -g tree-sitter-cli` |
| `sqlite3` | Ad-hoc `.forge/code-graph.db` queries | pre-installed on macOS and most Linux |
| `shellcheck` | Dev-time shell linting | `brew install shellcheck` |

**Integration with `/forge-init`:**

New Stage 0 in `skills/forge-init/SKILL.md` runs `./shared/check-prerequisites.sh`. If exit code 1: print abort-reason + install hints + exit. If exit code 2: print warnings + proceed. On success: record `{required, optional}` map in `.forge/prereqs.json` (new file; gitignored under `.forge/`).

**Integration with `/forge-status`:**

Read `.forge/prereqs.json` if present; include a "Prerequisites" section in the status output showing what's installed / missing.

### 4.5 SQLite graph functional parity for `/forge-graph-query`

**Current state:**
- `shared/graph/code-graph-query.sh` provides 7 low-level SQLite subcommands (`search_class`, `search_method`, `search_method_in_class`, `search_references`, `search_implementations`, `search_callers`, `stats`)
- `skills/forge-graph-query/SKILL.md` accepts only **Cypher** strings and requires Neo4j

**Phase 3 addition: DSL + backend selector.**

New file: `shared/graph/query-translator.sh` — thin dispatcher that accepts either:
- A Cypher query (if backend is Neo4j) — passthrough to existing Cypher executor
- A DSL intent (6 pre-built) — resolves to Cypher OR a composition of `code-graph-query.sh` subcommands
- A raw SQL query (if backend is SQLite) — passthrough to `sqlite3`

**DSL intents (6 pre-built):**

| Intent | Description | Cypher recipe | SQLite recipe (via code-graph-query.sh) |
|---|---|---|---|
| `bug_hotspots [limit]` | Files with most recent bugfix commits | `MATCH (f:File)-[:FIXED_IN]->(c:Commit) WHERE c.type = 'fix' ...` | `search_references` on `BUG_FIX` tags; aggregate |
| `module_dependencies <module>` | What a module depends on | `MATCH (m:Module {name: $n})-[:DEPENDS_ON*]->(d) ...` | SQL join on `module_deps` table |
| `test_coverage_gaps` | Public functions without test references | `MATCH (f:Function {visibility: 'public'}) WHERE NOT (f)<-[:CALLS]-(:Function {test: true}) ...` | SQL `LEFT JOIN ... WHERE test_fn IS NULL` |
| `orphan_functions` | Functions with no callers | `MATCH (f:Function) WHERE NOT (f)<-[:CALLS]-(:Function) AND f.exported = false ...` | `search_callers` + negation |
| `circular_imports` | Cycles in import graph | `MATCH p=(m:Module)-[:IMPORTS*]->(m) ...` | SQL recursive CTE on `imports` |
| `dead_code` | Symbols not referenced anywhere | `MATCH (s:Symbol) WHERE NOT (s)<-[:REFERENCES]-() ...` | `search_references` with zero results |

**Custom query passthrough:**
- If query looks like Cypher (`MATCH`, `CREATE`, `MERGE`) → require Neo4j; fail fast if SQLite backend
- If query starts with `sql:` or `SELECT` → force SQLite backend
- Otherwise → parse as DSL intent; fail with "unknown intent" if no match

**Backend selection rule:**

Reads `code_graph.backend` config (per existing `CLAUDE.md`):
- `neo4j` → require Docker + Neo4j container running
- `sqlite` → require `.forge/code-graph.db` present
- `auto` (default) → prefer Neo4j if container healthy; fall back to SQLite

Reports chosen backend in every invocation's output:
```
── backend: sqlite (.forge/code-graph.db)
── query: bug_hotspots 10
── results: 3 files
```

**Update `skills/forge-graph-query/SKILL.md`:**
- Description changes from "Cypher query against Neo4j" to "query the code graph via DSL, Cypher, or SQL; backend auto-selects"
- New `## DSL intents` section enumerating the 6 pre-built
- `## Backend selection` section
- `--json` flag preserves existing behavior but now works against both backends

### 4.6 Script renames

Two hook scripts renamed for clarity:

```
hooks/automation-trigger-hook.sh  →  hooks/file-changed-hook.sh
hooks/automation-trigger.sh       →  hooks/automation-dispatcher.sh
```

`hooks/hooks.json` updated to reference the new paths. `git mv` preserves history.

**No alias for the old paths** (per user's "no BC" rule). Anyone referencing the old names in external tooling updates their references.

### 4.7 Portability bats test — new `tests/contract/portability.bats`

Assertions:

1. Zero banned-pattern occurrences across `shared/**/*.sh` and `hooks/**/*.sh`, excluding `shared/platform.sh`:
   ```bash
   grep -rnE "\\$'\\\\n'|<<<|declare -A|date \+%s%N|stat -c %Y|stat -c %s" \
     shared/ hooks/ \
     | grep -v "shared/platform.sh"
   ```
   Expected: empty output. Each match fails the test.
2. Every shell script in `shared/` and `hooks/` sources `platform.sh` if it uses any helper (detected by grep for helper names).
3. Every shell script has `#!/usr/bin/env bash` shebang (not `#!/bin/bash`).
4. Every shell script `bash -n`-parses without error.
5. Every shell script passes `shellcheck --severity=warning` (if shellcheck is available in CI; skip otherwise).
6. `shared/check-prerequisites.sh` exists, executable, returns non-zero when `python3` missing (simulated via `PATH=/nonexistent`).
7. `shared/graph/query-translator.sh` exists, executable, advertises all 6 DSL intents (`--help` output).

### 4.8 CI additions — bash 3.2 smoke

New CI step (GitHub Actions matrix): run a subset of scripts through `bash-3.2` Docker image on Linux runner.

```yaml
- name: bash 3.2 smoke test
  run: |
    docker run --rm -v $PWD:/work -w /work bash:3.2 \
      bash -c 'for f in shared/platform.sh shared/check-prerequisites.sh shared/forge-state.sh; do
                bash -n "$f" || exit 1
              done'
```

Scoped to files expected to run on macOS default bash 3.2 (not every script). Gate defined in `tests/ci/bash32-smoke-list.txt`.

### 4.9 Documentation updates

- `README.md` — new "Cross-platform support" section; link to `shared/cross-platform-contract.md`.
- `CLAUDE.md` — add 2 Key Entry Points (`cross-platform-contract.md`, `query-translator.sh`); note bash 3.2 smoke CI step.
- `CHANGELOG.md` — 3.2.0 entry.
- `skills/forge-init/SKILL.md` — new Stage 0 prereq check.
- `skills/forge-graph-query/SKILL.md` — rewrite description + new DSL/backend sections.
- `skills/forge-status/SKILL.md` — read `.forge/prereqs.json` and surface prereq state.
- `.claude-plugin/plugin.json` — `"3.1.0"` → `"3.2.0"`.
- `.claude-plugin/marketplace.json` — `"3.1.0"` → `"3.2.0"`.
- `CONTRIBUTING.md` — cross-reference `cross-platform-contract.md` for new-script contributors.

## 5. File manifest (authoritative)

### 5.1 Delete (1 file)

```
shared/check-environment.sh   # folded into check-prerequisites.sh
```

### 5.2 Create (4 files)

```
shared/cross-platform-contract.md
shared/graph/query-translator.sh
tests/contract/portability.bats
tests/ci/bash32-smoke-list.txt
```

Note: `shared/check-prerequisites.sh` already exists — it is **extended**, not created.

### 5.3 Rename (2 files)

```
hooks/automation-trigger-hook.sh  →  hooks/file-changed-hook.sh
hooks/automation-trigger.sh       →  hooks/automation-dispatcher.sh
```

### 5.4 Update in place

**Shell scripts — bashism fixes (19 files; 20th `platform.sh` is exempt but extended):**

`shared/checks/engine.sh`, `shared/checks/l0-syntax/validate-syntax.sh`, `shared/checks/layer-1-fast/run-patterns.sh`, `shared/checks/layer-2-linter/run-linter.sh`, `shared/config-validator.sh`, `shared/context-guard.sh`, `shared/convergence-engine-sim.sh`, `shared/cost-alerting.sh`, `shared/generate-conventions-index.sh`, `shared/graph/build-code-graph.sh`, `shared/graph/build-project-graph.sh`, `shared/graph/code-graph-query.sh`, `shared/graph/enrich-symbols.sh`, `shared/graph/generate-seed.sh`, `shared/graph/incremental-code-graph.sh`, `shared/graph/incremental-update.sh`, `shared/graph/update-project-graph.sh`, `shared/recovery/health-checks/pre-stage-health.sh`, `shared/validate-finding.sh`.

**Platform helpers (1 file):**

`shared/platform.sh` — add 9 new helper functions per §4.2.

**Prereq consolidation (1 file):**

`shared/check-prerequisites.sh` — extend with `--json`, `--strict`, required/optional split per §4.4.

**Hook config (1 file):**

`hooks/hooks.json` — update 2 script paths.

**Skills (3 files):**

`skills/forge-init/SKILL.md` (new Stage 0), `skills/forge-graph-query/SKILL.md` (rewrite description + new sections), `skills/forge-status/SKILL.md` (prereq section).

**Top-level (5 files):**

`README.md`, `CLAUDE.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`.

**Contributing docs (1 file):**

`CONTRIBUTING.md`.

**CI (1 file):**

`.github/workflows/*.yml` — add bash 3.2 smoke step (path determined during plan-writing; if no existing workflow, create `.github/workflows/ci.yml`).

### 5.5 File-count arithmetic

| Category | Count |
|---|---|
| Deletions | 1 |
| Creations | 4 |
| Renames | 2 |
| Shell-script bashism fixes | 19 |
| platform.sh extension | 1 |
| check-prerequisites.sh extension | 1 |
| hooks.json update | 1 |
| Skill updates | 3 |
| Top-level doc + version updates | 5 |
| CONTRIBUTING update | 1 |
| CI workflow update | 1 |
| **Unique file operations** | **39** |

## 6. Acceptance criteria

All verified by CI on push.

1. `tests/contract/portability.bats` exists and passes: zero banned-pattern occurrences across `shared/**/*.sh` and `hooks/**/*.sh` (excluding `shared/platform.sh`).
2. `shared/platform.sh` exports functions: `iso_timestamp`, `epoch_s`, `epoch_ms`, `file_mtime`, `file_size`, `portable_sed_i`, `safe_realpath`, `has_bash_4`, `portable_find_mtime`, `acquire_lock_with_retry`, `release_lock`.
3. `shared/cross-platform-contract.md` exists with 6 sections per §4.3.
4. `shared/check-prerequisites.sh` extended: `--json` and `--strict` flags honored; required/optional dep split matches §4.4 table.
5. `shared/check-environment.sh` removed; all references in other scripts updated to `check-prerequisites.sh`.
6. `shared/graph/query-translator.sh` exists, executable, advertises 6 DSL intents via `--help`.
7. `/forge-graph-query` (skill description + body) documents DSL intents + backend selection rule.
8. `hooks/file-changed-hook.sh` exists (renamed); `hooks/automation-dispatcher.sh` exists (renamed); old paths no longer present.
9. `hooks/hooks.json` references new script paths.
10. `/forge-init` Stage 0 invokes `check-prerequisites.sh`; records `.forge/prereqs.json` on success; aborts with install hints on missing required.
11. `/forge-status` reads `.forge/prereqs.json` when present and includes a Prerequisites section.
12. `tests/ci/bash32-smoke-list.txt` exists and enumerates files expected to pass bash 3.2 parse check.
13. `.github/workflows/*.yml` contains a bash 3.2 smoke step that sources files from `bash32-smoke-list.txt`.
14. All 19 bashism-fix targets under `shared/**/*.sh` pass `bash -n` parse check and `shellcheck --severity=warning` on GitHub Actions Linux runner.
15. `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `CONTRIBUTING.md` updated per §4.9.
16. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions set to `3.2.0`.
17. CI green on push; no local test runs permitted.

## 7. Test strategy

**Static validation (bats, CI-only):**

- New `tests/contract/portability.bats` — covers AC #1, #2.
- `tests/validate-plugin.sh` — extend to assert `shared/check-prerequisites.sh` is executable (already does for hooks/; extend to shared/check-*).

**Runtime validation (bats):**

- `tests/unit/` gains a small script that invokes `shared/check-prerequisites.sh --json` against a sandboxed `PATH` where `jq` is missing; expects exit 1 and a `jq` entry in `abort_reason`.
- `tests/unit/graph-query-translator.bats` — invokes `query-translator.sh` against a seed SQLite `.forge/code-graph.db` fixture (built from `shared/graph/code-graph-schema.sql`) for each of 6 DSL intents; expects exit 0 and at least one result row OR explicit empty-result marker.

**CI runtime:**

- `bash -n` parse check for all shell scripts (already present; extend to new files).
- `shellcheck --severity=warning` (new step; fail on warnings in Phase-3-touched files).
- bash 3.2 smoke matrix step (GitHub Actions) runs the smoke-list through `bash:3.2` Docker image.

Per user instruction: no local test runs. Static parse checks (`bash -n`, `python3 -m json.tool`, `shellcheck` on-path availability check) are permitted.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Bashism refactor introduces regression in check-engine (skipped check or wrong exit code) | Medium | High | Per-file bats smoke test BEFORE refactor (snapshot current behavior); compare after. New tests/contract/engine-regression.bats compares skipped-check count on a fixture repo |
| `declare -A` fix via file-per-key pattern is slow in tight loops | Low | Medium | Profile `layer-2-linter/run-linter.sh` against 100-file project; if regression > 2×, switch that file to Python instead of bash |
| Neo4j→SQLite query translator DSL has poor coverage for non-enumerated intents | Medium | Medium | Documented 6 intents cover ~80% of observed `/forge-graph-query` usage in `.forge/run-history.db`. Custom Cypher passthrough preserved for power users; SQL passthrough added for SQLite experts |
| `check-environment.sh` deletion breaks external tooling that sourced it | Low | Low | No BC per user; update all internal references; document removal in `DEPRECATIONS.md` (new `## Removed in 3.2.0` section mirroring Phase 1 pattern) |
| `/forge-init` Stage 0 fails for users with non-`command -v`-locatable installs (e.g., tools in `~/.local/bin` missing from PATH) | Medium | Medium | `check-prerequisites.sh` also tries `type`, `which`, and a small search in common install roots (`~/.local/bin`, `~/bin`, `/opt/homebrew/bin`); diagnostic output includes `PATH` on failure |
| bash 3.2 smoke CI step flakes due to Docker image pull | Low | Low | Pin image digest; cache on GitHub Actions; retry once on network error |
| `portable_sed_i` wrapper hides platform behavior differences that matter (e.g., sed `\n` handling differs GNU vs BSD) | Medium | Medium | Document in contract doc; advise Python substitution for non-trivial regex; bats case-test for one known-divergent pattern |
| Query translator's 6 DSL intents drift from the underlying schema as `shared/graph/code-graph-schema.sql` evolves | Low | Medium | Bats assertion runs each intent against seed fixture built from live schema; schema change without intent update fails CI |
| `FORGE_OS` caching misfires on WSL where `OSTYPE` may be `linux-gnu` but `/proc/version` contains `microsoft` | Low | Low | Existing `detect_os` in platform.sh already handles WSL via `/proc/version` grep; verified |
| CONTRIBUTING.md changes discourage new contributors from ad-hoc scripts | Low | Low | Framing: "use these helpers so your script works everywhere"; not punitive |

## 9. Rollout (one PR, multi-commit; CI gates on HEAD)

1. **Commit 1 — Specs land.** This spec + plan.
2. **Commit 2 — Foundations.** `shared/platform.sh` extended with 9 helpers. `shared/cross-platform-contract.md` created. `tests/contract/portability.bats` skeleton (assertions inactive until `FORGE_PHASE3_ACTIVE=1` — same pattern as Phase 2 Group-A/B split). `tests/ci/bash32-smoke-list.txt` created. CI green.
3. **Commit 3 — Bashism refactor (batch 1: checks).** 4 files in `shared/checks/**/*.sh`. `bash -n` + `shellcheck` pass. CI green.
4. **Commit 4 — Bashism refactor (batch 2: graph).** 8 files in `shared/graph/*.sh`. CI green.
5. **Commit 5 — Bashism refactor (batch 3: misc).** 7 remaining files in `shared/*.sh` and `shared/recovery/`. CI green.
6. **Commit 6 — Prereq consolidation + hook renames.** Delete `check-environment.sh`; extend `check-prerequisites.sh`; rename 2 hook scripts; update `hooks/hooks.json`; update `/forge-init`, `/forge-status` SKILL.md. CI green.
7. **Commit 7 — SQLite graph parity.** `shared/graph/query-translator.sh` created; `/forge-graph-query` SKILL.md rewritten; `tests/unit/graph-query-translator.bats` created. CI green.
8. **Commit 8 — CI workflow + top-level docs + version bump.** bash 3.2 smoke step; README, CLAUDE, CHANGELOG, CONTRIBUTING, plugin.json, marketplace.json. Activate `FORGE_PHASE3_ACTIVE=1` in portability.bats setup. CI green.
9. **Push → CI → tag `v3.2.0` → release.**

## 10. Versioning rationale

All changes are additive to the user (no command removed; no config field removed; no default changed that would alter behavior without opt-in). `check-environment.sh` removal is internal API (not user-facing). SemVer minor: `3.1.0 → 3.2.0`.

## 11. Open questions

None. All decisions locked in brainstorming.

## 12. References

- Phase 1 spec (§2 of this doc assumes 3.0.0 artifacts present)
- Phase 2 spec (§2 of this doc assumes 3.1.0 artifacts present)
- `shared/platform.sh` (existing — extended)
- `shared/check-prerequisites.sh` (existing — extended)
- `shared/check-environment.sh` (existing — deleted, folded in)
- `shared/graph/code-graph-query.sh` (existing — underlying SQLite primitives)
- `shared/graph/code-graph-schema.sql` (existing — SQLite schema)
- `skills/forge-graph-query/SKILL.md` (rewritten)
- April 2026 UX audit (conversation memory)
- User instructions: "I want it all except the backwards compatibility"; "Do not run tests locally"
