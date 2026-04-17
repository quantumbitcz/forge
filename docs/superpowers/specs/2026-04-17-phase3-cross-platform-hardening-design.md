# Phase 3 — Cross-Platform Hardening (Design)

**Status:** Draft v2 for review (v1 review applied)
**Date:** 2026-04-17
**Target version:** Forge 3.2.0 (minor — additive; no breaking user-facing changes)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 3 of 7
**Depends on:** Phase 2 merged (3.1.0 released).

---

## 1. Goal

Eliminate known bashisms from the shell-script surface so Forge runs reliably on macOS/Linux/WSL2/Git Bash; extend `shared/platform.sh` with the helpers missing for that cleanup; persist prereq-check results so `/forge-status` can surface them; ship a backend selector for `/forge-graph-query` so Docker-free users can query their SQLite graph. This phase is the substrate that makes Phase 7 (Go core binary port) tractable.

## 2. Context and motivation

April 2026 UX audit graded cross-platform support **C+**. Actual repo state (verified via grep):

1. **Bashisms scattered across 21 shell scripts.** Banned patterns (`$'\n'`, `<<<`, `declare -A`, `date +%s%N`, GNU-only `stat -c` / `sed -i` forms) appear in:
   - Check engine: `shared/checks/engine.sh`, `l0-syntax/validate-syntax.sh`, `layer-1-fast/run-patterns.sh`, `layer-2-linter/run-linter.sh` (4)
   - Top-level shared: `shared/config-validator.sh`, `context-guard.sh`, `convergence-engine-sim.sh`, `cost-alerting.sh`, `generate-conventions-index.sh`, `state-integrity.sh`, `validate-finding.sh` (7)
   - Graph: `shared/graph/build-code-graph.sh`, `build-project-graph.sh`, `code-graph-query.sh`, `enrich-symbols.sh`, `generate-seed.sh`, `incremental-code-graph.sh`, `incremental-update.sh`, `update-project-graph.sh` (8)
   - Recovery: `shared/recovery/health-checks/pre-stage-health.sh` (1)
   - Platform helper itself: `shared/platform.sh` — **exempt** (it implements the wrappers; intentional conditionals).
   Total: **21 files** (20 fixable + 1 exempt).
2. **Two prereq scripts with different purposes, no persistence.** `shared/check-prerequisites.sh` (blocking: bash+python3; exit N = failure count) and `shared/check-environment.sh` (informational JSON tool inventory: 11 tools across Required/Recommended/Optional tiers; always exit 0). Both are **already invoked** by `/forge-init` step 2+3. Neither writes durable state; `/forge-status` cannot surface prereq status between sessions.
3. **`/forge-graph-query` is Neo4j/Cypher-exclusive.** SQLite primitives exist (`shared/graph/code-graph-query.sh` — 7 subcommands), but the user-facing skill does not offer a SQLite path. Users without Docker hit "Neo4j not running. Run /forge-graph-init first." and stop.
4. **Hook script naming ambiguity.** `hooks/automation-trigger-hook.sh` (PostToolUse wrapper) vs `hooks/automation-trigger.sh` (dispatcher) — reviewers routinely confuse which is which.

v1 review corrections applied:

- **DSL intent catalog dropped.** Phase 3 does NOT define 6 Cypher/SQL recipes (the v1 draft's recipes referenced non-existent graph-schema labels; correctness would require a dedicated design pass). Phase 3 ships only the **backend selector + Cypher/SQL passthrough**. A future dedicated phase can add a DSL on top.
- **Helper list reconciled against real `platform.sh`.** v1 duplicated existing `portable_sed`/`portable_file_date` under new names. v2 lists only genuine additions.
- **`check-environment.sh` preserved.** v1 folded it into prereqs; that would have lost the tiered 11-tool inventory and non-blocking informational mode. v2 keeps both scripts with distinct purposes; adds `.forge/prereqs.json` persistence that combines their output.
- **`state-integrity.sh` added to bashism-fix list** (v1 missed it — has `stat -c %Y` twice).
- **Explicit commit gating mechanism.** v2 makes each commit independently CI-green by scoping `tests/contract/portability.bats` assertions to **Phase-3-touched files only** in early commits; the repo-wide assertion activates in the final Commit 8.

No backwards compatibility required (single-user plugin, explicit user instruction).

## 3. Non-goals

- **No native Windows PowerShell support.** Deferred to Phase 7 (Go binary).
- **No POSIX sh everywhere.** `#!/usr/bin/env bash` stays; goal is removing patterns that break on BSD `sed`/`stat`, dash, and Git Bash MSYS — not purging bash entirely.
- **No Neo4j removal.** Neo4j remains supported; SQLite gains backend-parity for passthrough queries only.
- **No DSL for `/forge-graph-query`** (v1 removed). Future phase.
- **No changes to L0/L1/L2 check-engine rules.** Only scripts are edited.
- **No rewrite of `shared/forge-token-tracker.sh` Python heredoc** (Phase 2 handled it; Phase 3 only touches bash around Python).
- **No changes to existing `check-prerequisites.sh` exit semantics.** Current "exit 0 pass, exit N where N=failures" is preserved to avoid caller regressions. New features are opt-in flags.

## 4. Design

### 4.1 Bashism fixes — exact surface

**Banned patterns** (enforced by new `tests/contract/portability.bats` once fully activated in Commit 8):

| Pattern | Why it breaks | Replacement |
|---|---|---|
| `$'\n'` | Not POSIX; fails on dash; renders wrong in Git Bash MSYS | `printf '\n'` into a variable OR literal newline inside double quotes |
| `<<<"string"` | Bash-only; fails on dash | `printf '%s' "string" \| cmd` OR `echo "string" \| cmd` |
| `declare -A` | Bash 4+; fails on macOS default bash 3.2 | File-per-key pattern (`$tmpdir/keys/$k`) OR Python hash for complex lookups |
| `date +%s%N` | GNU-only; macOS lacks `%N` | `platform.sh::epoch_ms` helper (new) |
| `stat -c %Y` / `stat -c %s` | GNU-only | Use existing `portable_file_date` (already in platform.sh); add `portable_file_size` (new) |
| `sed -i 's/...'` (no arg) | GNU accepts; BSD requires `-i ''` | Use existing `portable_sed` (already in platform.sh) |
| `realpath` (plain) | Not on macOS without coreutils | New `platform.sh::safe_realpath` (falls back to Python) |
| `find -printf` | GNU-only | `find -print0 | xargs -0` OR Python |
| `readarray`/`mapfile` | Bash 4+ | `while IFS= read -r line; do ...; done < file` inline (no helper needed) |

**Exempt location:** `shared/platform.sh` itself.

**21 files enumerated in §2**; each audited during plan-writing and edited in place.

### 4.2 Extend `shared/platform.sh`

**Existing helpers (preserved, not renamed):** `detect_os`, `is_wsl`, `suggest_install`, `suggest_docker_start`, `_glob_exists`, `pipeline_tmpdir`, `pipeline_mktemp`, `pipeline_mktempdir`, `detect_python`, `portable_normalize_path`, `portable_file_date`, `portable_sed`, `portable_timeout`, `derive_project_id`, `read_components`, `extract_file_path_from_tool_input`, `acquire_lock_with_retry`, `atomic_increment`, `atomic_json_update`, `require_bash4`, plus a handful of internal helpers.

**New helpers added by Phase 3 (5 functions):**

| Function | Purpose | Why not existing helper |
|---|---|---|
| `epoch_ms` | Milliseconds since epoch | `date +%s%N` is GNU-only; combines seconds + microseconds (Python where available) |
| `portable_file_size <path>` | Bytes in a file | No existing wrapper; `stat -c %s` ≠ `stat -f %z` |
| `safe_realpath <path>` | Canonical absolute path | `realpath` not on macOS; Python fallback |
| `portable_find_printf <dir> <format>` | Substitute for `find -printf` | GNU extension; composed from `-print0` + awk |
| `release_lock <lockdir>` | Counterpart to existing `acquire_lock_with_retry` | Current contract says "caller releases via `rmdir`"; helper adds trap-safe cleanup + retry-on-EBUSY |

Callers of `release_lock`: Phase 2 already planned to use it (spec §4.2.2). The v1 review correctly noted this helper does not exist today — this phase is where it lands. Phase 2's implementation defers to this helper (Phase 2 and Phase 3 merge into a single PR-per-phase cycle; plan order accounts for the dependency — Phase 2 will edit against the helper after Phase 3 merges, OR Phase 2's `emit_cost_inc` uses inline `rmdir` until Phase 3 lands and is swapped during Phase 3 Commit 2).

Note: **Phase 3 implements `release_lock` before Phase 2 is implemented** if the user executes phases in-order. If Phase 2 is implemented first (as planned), its `emit_cost_inc` temporarily uses inline `rmdir` and is refactored to use `release_lock` as part of Phase 3 Commit 6 (prereq consolidation also touches that file). The implementation plan will spell this out.

### 4.3 `shared/cross-platform-contract.md` (new)

Authoritative doc. Contents:

- §1 Banned patterns (table from §4.1)
- §2 `platform.sh` helper catalog (full table: existing + 5 new — see §4.2)
- §3 Decision guide — when to use a helper vs inline POSIX
- §4 Testing matrix — macOS bash 3.2 / 5.x, Linux bash 4.x / 5.x, WSL, Git Bash
- §5 Contributing — new-script checklist (source platform.sh, pass bash -n, pass targeted shellcheck, no banned patterns)
- §6 Known limitations — Windows native → Phase 7; busybox sh NOT targeted

Cross-referenced from `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`.

### 4.4 Prereq persistence — NOT a consolidation

v1 review correction: `check-prerequisites.sh` and `check-environment.sh` serve different purposes. Phase 3 keeps BOTH.

**Changes:**

1. **`shared/check-prerequisites.sh`** gains a `--json` flag emitting the same JSON shape as `check-environment.sh` for its required deps. Exit semantics unchanged (exit N = N failures, 0 = pass). No breaking change for existing callers.
2. **`shared/check-environment.sh`** unchanged in content; stays the tool-inventory source.
3. **New: `.forge/prereqs.json`** — combined snapshot of both scripts' outputs, written by `/forge-init` after running both. Gitignored (all `.forge/` is). Schema:
   ```json
   {
     "timestamp": "2026-04-17T12:00:00Z",
     "forge_version": "3.2.0",
     "required": {"bash": "5.2.26", "python3": "3.12.4"},
     "environment": {
       "tier_required": {"bash": "5.2.26", "python3": "3.12.4", "git": "2.45.1"},
       "tier_recommended": {"jq": "1.7.1", "docker": null},
       "tier_optional": {"tree-sitter": null, "gh": "2.55.0"}
     },
     "abort_reasons": []
   }
   ```
4. **`/forge-init` updated** (step 2 stays invoking `check-prerequisites.sh`; step 3 stays invoking `check-environment.sh`; new step 3.5 writes `.forge/prereqs.json` from both outputs).
5. **`/forge-status` updated** — reads `.forge/prereqs.json` if present; adds `## Prerequisites` section showing the snapshot + age (`stale if >7 days`). Suggests `/forge-init` to refresh if stale.

**No deletions in this area.** `check-environment.sh` stays. `check-prerequisites.sh` only gains `--json`. AC wording updated accordingly.

### 4.5 `/forge-graph-query` — backend selector + passthrough (no DSL)

v1 review correction: the 6 DSL intents used wrong Cypher schema. Phase 3 ships only the dispatcher; dedicated DSL design deferred.

**Changes to `skills/forge-graph-query/SKILL.md`:**

1. Description changes from "Cypher query against Neo4j" to "Query the code graph; backend is Neo4j (Cypher) or SQLite (SQL) based on `code_graph.backend` config (auto-detects)."
2. New section `## Backend selection`:
   ```
   code_graph.backend = "auto"  → Neo4j if container healthy, else SQLite
   code_graph.backend = "neo4j" → Neo4j required; error if absent
   code_graph.backend = "sqlite" → SQLite required
   ```
3. New section `## Query forms`:
   - Cypher → Neo4j backend. Example: `MATCH (f:ProjectFile) WHERE f.bug_fix_count > 3 RETURN f`.
   - SQL → SQLite backend. Example: `SELECT path, bug_fix_count FROM project_files WHERE bug_fix_count > 3`.
   - Auto-detect: query starts with `MATCH|CREATE|MERGE|CALL` → Cypher; starts with `SELECT|WITH|WITH RECURSIVE` → SQL. Ambiguous → error with suggestion.
4. Prerequisites updated: "Either Docker+Neo4j OR `.forge/code-graph.db` (SQLite)" — not strict Docker requirement anymore.

**New: `shared/graph/query-translator.sh`** — thin dispatcher (no translation logic). Responsibilities:

1. Read `code_graph.backend` config.
2. Detect query type (Cypher vs SQL vs unknown).
3. If auto: prefer Neo4j when healthy.
4. Dispatch to existing `shared/graph/neo4j-health.sh` + Cypher runner, OR to `sqlite3 .forge/code-graph.db "<query>"`.
5. Emit header: `── backend: {neo4j|sqlite} (source: {container|.forge/code-graph.db})` followed by query output.
6. `--json` flag → structured output.

No schema translation. No DSL. Cypher and SQL are written directly by the user (or LLM). When Phase 6+ adds a DSL, this dispatcher is the integration point.

### 4.6 Hook script renames

```
hooks/automation-trigger-hook.sh  →  hooks/file-changed-hook.sh
hooks/automation-trigger.sh       →  hooks/automation-dispatcher.sh
```

**External references to update (8 files — v1 missed these):**

- `CHANGELOG.md` — historical entries preserved; add 3.2.0 rename note
- `CLAUDE.md` — Hook entry table
- `shared/platform.sh` — L356 comment reference
- `shared/hook-design.md` — narrative reference
- `skills/forge-automation/SKILL.md` — mentions script paths
- `tests/unit/automation-cooldown.bats` — sources the script
- `tests/hooks/automation-trigger-behavior.bats` — invokes directly
- `tests/hooks/automation-trigger.bats` — invokes directly
- `hooks/hooks.json` — config entries

All 8 updated in the same commit as the rename (plus `git mv` for the scripts themselves).

**Bats test files may need rename too** to match new script names:
- `tests/hooks/automation-trigger.bats` → `tests/hooks/automation-dispatcher.bats`
- `tests/hooks/automation-trigger-behavior.bats` → `tests/hooks/file-changed-hook.bats`

Decided during plan-writing; bats renames preserve content, only names change.

### 4.7 Portability bats test — `tests/contract/portability.bats` (new)

**Phased activation (Group A vs Group B, analogous to Phase 2 v2):**

- **Group A (active from Commit 2):** existence of platform.sh helpers, shebang checks on the 4 new or extended scripts, `--help`-parse checks on new scripts.
- **Group B (active from Commit 8 via `FORGE_PHASE3_ACTIVE=1` env var set by CI at HEAD):** repo-wide banned-pattern sweep across `shared/**/*.sh` and `hooks/**/*.sh` excluding `platform.sh`.

Gate detection: `setup()` checks for presence of `shared/cross-platform-contract.md` file AND the final commit's renamed hook files. If all present → set `FORGE_PHASE3_ACTIVE=1` locally. Intermediate commits lack one of these → Group B `skip`s cleanly.

Assertions:

1. Group A: `shared/platform.sh` exports `epoch_ms`, `portable_file_size`, `safe_realpath`, `portable_find_printf`, `release_lock` (5 new).
2. Group A: `shared/cross-platform-contract.md` has 6 sections per §4.3.
3. Group A: `shared/graph/query-translator.sh` exists, executable, accepts `--help`.
4. Group A: `hooks/file-changed-hook.sh` + `hooks/automation-dispatcher.sh` exist post-rename commit; old paths absent.
5. Group B: repo-wide banned-pattern grep returns empty (excluding `shared/platform.sh`).
6. Group B: every shell script in `shared/` and `hooks/` has `#!/usr/bin/env bash`; `bash -n` parses clean.
7. Group B: `shellcheck --severity=warning` passes on the 21 Phase-3-touched files (scoped, not repo-wide — avoids pre-existing warning noise per v1 I7).

### 4.8 CI addition — scoped shellcheck + bash 3.2 smoke

**Shellcheck (scoped):** `.github/workflows/ci.yml` (verify existence during plan; create if missing) gets a new step:
```yaml
- name: shellcheck (Phase-3-touched files)
  run: |
    shellcheck --severity=warning \
      shared/platform.sh \
      shared/check-prerequisites.sh shared/check-environment.sh \
      shared/graph/query-translator.sh \
      hooks/file-changed-hook.sh hooks/automation-dispatcher.sh \
      $(cat tests/ci/phase3-shellcheck-scope.txt)
```

The scope file lists exactly the 21 bashism-fix target files. Pre-existing warnings outside this scope are untouched.

**bash 3.2 smoke:** GitHub Actions Linux runner step:
```yaml
- name: bash 3.2 smoke
  run: |
    docker run --rm -v "$PWD:/work" -w /work bash:3.2@sha256:<pinned-digest> \
      bash -c 'for f in $(cat tests/ci/bash32-smoke-list.txt); do
                 bash -n "$f" || exit 1
               done'
```

Digest pinning avoids v1 risk-row-6 (image-pull flake).

`tests/ci/bash32-smoke-list.txt` is a **curated opt-in list** — files that MUST work on bash 3.2 (small set: `shared/platform.sh`, `shared/check-prerequisites.sh`, `shared/forge-state.sh`, `hooks/session-start.sh`). New scripts decide-in via the cross-platform contract doc's checklist.

### 4.9 Documentation updates

- `README.md` — new "Cross-platform support" section; mentions bash 3.2 support via fallbacks; mentions SQLite backend for graph.
- `CLAUDE.md` — add 3 Key Entry Points (`cross-platform-contract.md`, `query-translator.sh`, `.forge/prereqs.json` schema reference); update rename references.
- `CONTRIBUTING.md` — point new-script contributors at `cross-platform-contract.md`.
- `CHANGELOG.md` — 3.2.0 entry listing all changes (bashism removal, helpers added, prereq persistence, SQLite backend, 2 script renames).
- `DEPRECATIONS.md` — **no entries** (v1 suggested one; v1-v2 change: no deletions this phase, so no deprecations).
- `.claude-plugin/plugin.json` — `"3.1.0"` → `"3.2.0"`.
- `.claude-plugin/marketplace.json` — `"3.1.0"` → `"3.2.0"`.
- `skills/forge-init/SKILL.md` — add `.forge/prereqs.json` write step (post-existing prereq invocations).
- `skills/forge-status/SKILL.md` — add Prerequisites section reading `.forge/prereqs.json`.
- `skills/forge-graph-query/SKILL.md` — rewrite per §4.5.

## 5. File manifest (authoritative)

### 5.1 Delete

**None.** v1 proposed deleting `check-environment.sh`; v2 preserves it. Zero deletions this phase.

### 5.2 Create (5 files)

```
shared/cross-platform-contract.md
shared/graph/query-translator.sh
tests/contract/portability.bats
tests/ci/bash32-smoke-list.txt
tests/ci/phase3-shellcheck-scope.txt
```

### 5.3 Rename (4 files — 2 hook scripts + 2 bats tests)

```
hooks/automation-trigger-hook.sh          → hooks/file-changed-hook.sh
hooks/automation-trigger.sh               → hooks/automation-dispatcher.sh
tests/hooks/automation-trigger.bats       → tests/hooks/automation-dispatcher.bats
tests/hooks/automation-trigger-behavior.bats → tests/hooks/file-changed-hook.bats
```

### 5.4 Update in place

**Shell scripts — bashism fixes (20 files; `platform.sh` exempt from bashism fixes but is extended separately):**

`shared/checks/engine.sh`, `shared/checks/l0-syntax/validate-syntax.sh`, `shared/checks/layer-1-fast/run-patterns.sh`, `shared/checks/layer-2-linter/run-linter.sh`, `shared/config-validator.sh`, `shared/context-guard.sh`, `shared/convergence-engine-sim.sh`, `shared/cost-alerting.sh`, `shared/generate-conventions-index.sh`, `shared/state-integrity.sh`, `shared/validate-finding.sh`, `shared/graph/build-code-graph.sh`, `shared/graph/build-project-graph.sh`, `shared/graph/code-graph-query.sh`, `shared/graph/enrich-symbols.sh`, `shared/graph/generate-seed.sh`, `shared/graph/incremental-code-graph.sh`, `shared/graph/incremental-update.sh`, `shared/graph/update-project-graph.sh`, `shared/recovery/health-checks/pre-stage-health.sh`.

**`shared/platform.sh`** — add 5 new helper functions per §4.2.

**`shared/check-prerequisites.sh`** — add `--json` flag; no exit-code change.

**`hooks/hooks.json`** — update 2 script paths.

**Content references to renamed hooks (8 files):**

`CHANGELOG.md`, `CLAUDE.md`, `shared/platform.sh` (L356 comment), `shared/hook-design.md`, `skills/forge-automation/SKILL.md`, `tests/unit/automation-cooldown.bats`, plus 2 renamed bats files (content updated to match new script names).

Note: `shared/platform.sh` is touched in both the helper-extension pass AND the rename-reference pass — same file, two content-distinct edits in different commits.

**Skills (3 files):**

`skills/forge-init/SKILL.md` (write `.forge/prereqs.json`), `skills/forge-status/SKILL.md` (read it), `skills/forge-graph-query/SKILL.md` (backend selector + passthrough).

**Top-level (5 files):**

`README.md`, `CLAUDE.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`.

**CONTRIBUTING (1 file):**

`CONTRIBUTING.md`.

**CI (1 file):**

`.github/workflows/ci.yml` (verify existence; create if missing).

### 5.5 File-count arithmetic

| Category | Count |
|---|---|
| Deletions | 0 |
| Creations | 5 |
| Renames | 4 |
| Bashism fixes | 20 |
| `shared/platform.sh` extension | 1 |
| `shared/check-prerequisites.sh` extension | 1 |
| `hooks/hooks.json` | 1 |
| Rename-ref updates (excluding already-counted renamed bats) | 6 (CHANGELOG, CLAUDE.md, platform.sh — rename pass only, hook-design, skills/forge-automation, tests/unit/automation-cooldown) |
| Skill updates | 3 |
| Top-level doc + version | 5 |
| CONTRIBUTING | 1 |
| CI workflow | 1 |
| **Unique file operations** | **48** |

(Note: `shared/platform.sh` contributes 2 operations — extension + rename-ref — but is counted once in "unique files touched". Spec uses "operations" not "unique files" to match Phase-2 style.)

## 6. Acceptance criteria

All verified by CI on push.

1. `shared/cross-platform-contract.md` exists with 6 sections (§4.3).
2. `shared/platform.sh` exports 5 new functions: `epoch_ms`, `portable_file_size`, `safe_realpath`, `portable_find_printf`, `release_lock`.
3. `shared/check-prerequisites.sh` accepts `--json` flag; exit semantics unchanged (exit N = N failures).
4. `shared/graph/query-translator.sh` exists, executable, supports auto/neo4j/sqlite backend selection; advertises Cypher and SQL passthrough via `--help`.
5. `tests/contract/portability.bats` exists with Group A assertions active from Commit 2 and Group B assertions activating at Commit 8 via `FORGE_PHASE3_ACTIVE` detection.
6. `tests/ci/bash32-smoke-list.txt` enumerates the curated opt-in bash 3.2 compat set.
7. `tests/ci/phase3-shellcheck-scope.txt` enumerates Phase-3-touched files (25 entries: 20 bashism-fix targets + `shared/platform.sh` extension + `shared/check-prerequisites.sh` extension + `shared/graph/query-translator.sh` new + 2 renamed hook scripts).
8. Group B portability assertion: zero banned-pattern occurrences across `shared/**/*.sh` and `hooks/**/*.sh` (excluding `shared/platform.sh`) at HEAD.
9. 20 bashism-fix files pass `shellcheck --severity=warning` (scoped via `phase3-shellcheck-scope.txt`).
10. `state-integrity.sh` bashisms (`stat -c %Y` at L151, L153) replaced with `portable_file_date` calls.
11. `hooks/file-changed-hook.sh` exists post-rename; `hooks/automation-trigger-hook.sh` does not.
12. `hooks/automation-dispatcher.sh` exists post-rename; `hooks/automation-trigger.sh` does not.
13. `hooks/hooks.json` references new paths.
14. All 8 rename-reference files updated to new script names.
15. `tests/hooks/` bats files renamed + content updated.
16. `.forge/prereqs.json` written by `/forge-init` after both prereq scripts run.
17. `/forge-status` includes a `## Prerequisites` section when `.forge/prereqs.json` is present.
18. `/forge-graph-query` SKILL.md documents backend selector + Cypher/SQL passthrough; Neo4j is no longer a hard requirement.
19. CI workflow contains bash 3.2 smoke step (pinned image digest) and scoped shellcheck step.
20. `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `CONTRIBUTING.md` updated per §4.9.
21. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` set to `3.2.0`.
22. CI green on push; no local test runs permitted.

## 7. Test strategy

**Static validation (bats, CI-only):**

- New `tests/contract/portability.bats` — AC #1, #2, #5, #8.
- `tests/validate-plugin.sh` extended to cover new helper function presence checks.

**Runtime validation (bats):**

- `tests/unit/query-translator-dispatch.bats` (new) — invokes `query-translator.sh` with auto/neo4j/sqlite backends against a seed SQLite fixture; asserts correct dispatch decision + `── backend:` header.
- `tests/unit/check-prerequisites-json.bats` (new) — invokes `check-prerequisites.sh --json` against sandboxed PATH; expects structured JSON output with missing-tool entries.

**CI runtime:**

- Existing `bash -n` parse check extended to new files.
- New scoped `shellcheck --severity=warning` step (21 files).
- New bash 3.2 smoke step (curated list).

Per user instruction: no local test runs.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Bashism refactor regresses check-engine behavior | Medium | High | Per-commit bats smoke on touched files BEFORE refactor (snapshot current L0/L1/L2 behavior), compare after |
| `declare -A` → file-per-key pattern is slow in `layer-2-linter/run-linter.sh` | Low | Medium | Profile against 100-file fixture; if regression > 2×, Python port for that file |
| Backend selector in `query-translator.sh` misroutes ambiguous queries | Medium | Low | `--backend=neo4j|sqlite` explicit flag overrides auto; `--help` documents detection heuristic |
| `release_lock` helper introduced in Phase 3 but Phase 2 code expects it | Medium | Medium | Phase 2 implementation plan uses inline `rmdir` until Phase 3 lands; Phase 3 Commit 6 swaps the callsite |
| `check-environment.sh` and `check-prerequisites.sh` diverge in dep coverage | Low | Low | `.forge/prereqs.json` schema combines both; `/forge-init` runs both so drift surfaces in the combined snapshot |
| bash 3.2 smoke CI step flakes due to Docker image pull | Low | Low | Pinned digest (v1 risk-row mitigation carried over) |
| Scoped shellcheck misses regressions in untouched files | Medium | Low | Accepted trade-off: avoids CI red on pre-existing warnings; repo-wide shellcheck is a separate, later workstream |
| Hook-script rename breaks external documentation links | Low | Low | Grep-verified all 8 references updated; `CHANGELOG.md` 3.2.0 entry documents the rename |
| `/forge-status` Prerequisites section is stale when user updates tools but doesn't re-init | Low | Low | Section reports snapshot age; >7 days emits "stale; re-run /forge-init" |
| Group B portability assertion activates prematurely (detects transient banned patterns between batches) | Medium | High | `FORGE_PHASE3_ACTIVE` detection requires ALL Phase 3 sentinel files + the rename to be present; intermediate commits fail the check and skip Group B. Verified during plan-writing. |
| `portable_find_printf` has subtly different output format than GNU `-printf` | Medium | Low | Document exact format contract in helper comment + contract doc §2; bats unit test on one known format |
| Phase 2's `emit_cost_inc` uses inline `rmdir` pending Phase 3's `release_lock` | Low | Low | Documented in Phase 2 plan + Phase 3 Commit 6 task (swap callsite to new helper) |

## 9. Rollout (one PR, multi-commit; CI gates on HEAD)

1. **Commit 1 — Specs land.** This spec + plan.
2. **Commit 2 — Foundations.** `shared/platform.sh` extended with 5 helpers. `shared/cross-platform-contract.md` created. `shared/graph/query-translator.sh` created. `tests/contract/portability.bats` skeleton with Group A active, Group B skipping (gated on `FORGE_PHASE3_ACTIVE` which requires Commit 8 sentinels). `tests/ci/bash32-smoke-list.txt`, `phase3-shellcheck-scope.txt`. CI green.
3. **Commit 3 — Bashism refactor batch 1 (checks).** 4 files in `shared/checks/**/*.sh`. bash -n + scoped shellcheck pass. CI green.
4. **Commit 4 — Bashism refactor batch 2 (graph).** 8 files in `shared/graph/*.sh`. CI green.
5. **Commit 5 — Bashism refactor batch 3 (misc).** 7 remaining files in `shared/*.sh` and `shared/recovery/`. Includes `state-integrity.sh`. CI green.
6. **Commit 6 — Hook script renames + ref updates.** `git mv` both scripts; rename 2 bats files; update `hooks/hooks.json`; update 6 content-ref files (CHANGELOG, CLAUDE.md, platform.sh comment, hook-design.md, skills/forge-automation, tests/unit/automation-cooldown). Also: swap Phase 2's `emit_cost_inc` inline `rmdir` to new `release_lock` helper. CI green.
7. **Commit 7 — Prereq persistence + SQLite backend + skill updates.** `check-prerequisites.sh` gains `--json`; `/forge-init` writes `.forge/prereqs.json`; `/forge-status` reads it; `/forge-graph-query` SKILL.md rewritten for backend selector. New bats files for dispatch + prereq-json. CI green.
8. **Commit 8 — CI workflow + top-level docs + activation sentinel.** `.github/workflows/ci.yml` adds bash 3.2 smoke + scoped shellcheck. README, CLAUDE.md, CHANGELOG, CONTRIBUTING, plugin.json, marketplace.json, 3.2.0 version. `FORGE_PHASE3_ACTIVE=1` sentinel in `portability.bats setup()` activates Group B (now passes because all refactor work landed in Commits 3–7). CI green.
9. **Push → CI → tag `v3.2.0` → release.**

## 10. Versioning rationale

All changes are additive to users. Internal API changes (helper additions, prereq JSON persistence, backend selector) don't alter user-facing commands or configuration defaults. `3.1.0 → 3.2.0`.

## 11. Open questions

None. v1 review corrections applied.

## 12. References

- Phase 1 + 2 specs (same directory)
- `shared/platform.sh` (existing — extended with 5 new helpers)
- `shared/check-prerequisites.sh` + `check-environment.sh` (both preserved)
- `shared/graph/code-graph-query.sh` (existing SQLite primitives — unchanged)
- `shared/graph/code-graph-schema.sql` (existing schema — referenced by passthrough)
- `shared/graph/schema.md` (Neo4j schema — referenced by passthrough)
- `skills/forge-graph-query/SKILL.md` (rewritten)
- `skills/forge-init/SKILL.md` (prereq persistence step)
- `skills/forge-status/SKILL.md` (prereq section)
- April 2026 UX audit (conversation memory)
- User instructions: "I want it all except the backwards compatibility"; "Do not run tests locally"
- v1 code-review (this conversation) — 6 critical + 8 important findings applied
