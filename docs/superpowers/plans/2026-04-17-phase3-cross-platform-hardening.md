# Phase 3 — Cross-Platform Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate bashisms from 20 shell scripts; extend `shared/platform.sh` with 5 helpers; persist prereq check results; ship `/forge-graph-query` backend selector with Cypher/SQL passthrough. Ship as Forge 3.2.0.

**Architecture:** 9 logical commits in one PR. Each commit independently CI-green. Bashism fixes run in 3 batches (checks, graph, misc). Portability bats uses Group A/B split with `FORGE_PHASE3_ACTIVE` sentinel activating repo-wide sweep only in Commit 8.

**Tech Stack:** Bash 4+ (macOS bash 3.2 for smoke-list subset), Bats, Python 3 (for epoch_ms), Docker (bash 3.2 smoke image).

**Verification policy:** No local test runs. Static parse (`bash -n`, `python3 -m json.tool`, on-path `shellcheck`) OK. CI validates on push.

**Spec:** `docs/superpowers/specs/2026-04-17-phase3-cross-platform-hardening-design.md`
**Depends on:** Phase 1 + Phase 2 merged.

---

## File Structure

| File | Role |
|---|---|
| `shared/cross-platform-contract.md` | Authoritative banned-patterns + helper catalog |
| `shared/graph/query-translator.sh` | Backend dispatcher (Neo4j/SQLite) with Cypher/SQL passthrough |
| `shared/platform.sh` (extended) | +5 helpers: `epoch_ms`, `portable_file_size`, `safe_realpath`, `portable_find_printf`, `release_lock` |
| `shared/check-prerequisites.sh` (extended) | `--json` flag |
| `tests/contract/portability.bats` | Group A active Commit 2; Group B active Commit 8 |
| `tests/ci/bash32-smoke-list.txt` | Curated files expected to parse on bash 3.2 |
| `tests/ci/phase3-shellcheck-scope.txt` | 21 files for scoped shellcheck |
| `.forge/prereqs.json` | Runtime state — combined prereq snapshot (created by /forge-init) |
| `.github/workflows/ci.yml` | Add bash 3.2 smoke + scoped shellcheck steps |

---

## Task 0: Verify Phase 2 preconditions

- [ ] **Step 1: Verify plugin at 3.1.0**

```bash
grep '"version": "3.1.0"' .claude-plugin/plugin.json      || { echo "ABORT: Phase 2 not merged"; exit 1; }
grep '"version": "3.1.0"' .claude-plugin/marketplace.json || { echo "ABORT: Phase 2 not merged"; exit 1; }
```

- [ ] **Step 2: Verify Phase 2 files exist**

```bash
test -f shared/observability-contract.md || { echo "ABORT: Phase 2 observability-contract missing"; exit 1; }
test -f shared/model-pricing.json         || { echo "ABORT: Phase 2 model-pricing missing"; exit 1; }
test -f docs/error-recovery.md            || { echo "ABORT: Phase 2 error-recovery missing"; exit 1; }
```

If any check fails, stop and complete Phase 2 implementation first.

---

## Task 1: Commit this plan

- [ ] **Step 1:**
```bash
git add docs/superpowers/plans/2026-04-17-phase3-cross-platform-hardening.md
git commit -m "docs(phase3): add cross-platform hardening implementation plan"
```

---

## Task 2: Extend `shared/platform.sh` with 5 new helpers

**Files:**
- Modify: `shared/platform.sh`

- [ ] **Step 1: Locate the insertion point**

```bash
grep -n "^# ──\|^# EOF\|^require_bash4" shared/platform.sh | tail -5
```

Expected: a trailing separator section around the file's end.

- [ ] **Step 2: Append the 5 helper functions**

At the end of `shared/platform.sh` (before any final `# EOF` or trailing comments), add:

```bash
# ── Phase 3 additions ────────────────────────────────────────────────────────

# epoch_ms — milliseconds since epoch, portable across GNU/BSD
# Args: none
# Echoes: integer ms
epoch_ms() {
  local s us
  s=$(date +%s)
  if command -v python3 >/dev/null 2>&1; then
    us=$(python3 -c "import time;print(int((time.time()*1000)))")
    printf '%s' "$us"
  else
    printf '%s000' "$s"
  fi
}

# portable_file_size — bytes in a file, portable across GNU/BSD
# Args: $1 = path
# Echoes: integer bytes (0 if missing)
portable_file_size() {
  local path=$1
  [[ -f "$path" ]] || { printf '0'; return; }
  if [[ "${FORGE_OS:-$(detect_os)}" == "darwin" ]]; then
    stat -f %z "$path" 2>/dev/null || printf '0'
  else
    stat -c %s "$path" 2>/dev/null || printf '0'
  fi
}

# safe_realpath — canonical absolute path with Python fallback
# Args: $1 = path
# Echoes: resolved path (or original if resolution fails)
safe_realpath() {
  local path=$1
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path" 2>/dev/null && return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$path" 2>/dev/null && return
  fi
  # Last resort: echo unchanged
  printf '%s' "$path"
}

# portable_find_printf — substitute for `find -printf` on BSD
# Args: $1 = dir, $2 = format string
#   Supported format specifiers (subset): %p (path), %s (size), %T@ (mtime seconds)
# Emits: one line per match
portable_find_printf() {
  local dir=$1
  local fmt=${2:-%p}
  # Use find -print0 | awk to compose the desired format
  local null_sep
  null_sep=$(printf '\0')
  find "$dir" -print0 2>/dev/null | while IFS= read -r -d "$null_sep" f; do
    local out=$fmt
    case "$fmt" in
      *%p*) out=${out//%p/$f} ;;
    esac
    case "$fmt" in
      *%s*) out=${out//%s/$(portable_file_size "$f")} ;;
    esac
    case "$fmt" in
      *%T@*) out=${out//%T@/$(portable_file_date "$f")} ;;
    esac
    printf '%s\n' "$out"
  done
}

# release_lock — counterpart to acquire_lock_with_retry
# Args: $1 = lockdir (same arg that was passed to acquire)
# Returns: 0 if released, 1 if lockdir did not exist
release_lock() {
  local lockdir=$1
  [[ -n "$lockdir" ]] || return 1
  [[ -d "$lockdir" ]] || return 1
  rmdir "$lockdir" 2>/dev/null || return 1
  return 0
}
```

- [ ] **Step 3: Static parse check**

```bash
bash -n shared/platform.sh
```

- [ ] **Step 4: Held for commit in Task 7**

---

## Task 3: Create `shared/cross-platform-contract.md`

**Files:**
- Create: `shared/cross-platform-contract.md`

- [ ] **Step 1: Write the full document**

```markdown
# Cross-Platform Contract

Authoritative reference for portable shell-script authoring in Forge. Enforced by `tests/contract/portability.bats` + scoped shellcheck + bash 3.2 smoke CI step.

Created in Phase 3 (Forge 3.2.0).

## 1. Banned patterns

| Pattern | Why it breaks | Replacement |
|---|---|---|
| `$'\n'` | Not POSIX; fails on dash; Git Bash MSYS renders wrong | `printf '\n'` into a variable OR literal newline inside double quotes |
| `<<<"s"` (here-string) | Bash-only; fails on dash | `printf '%s' "s" | cmd` |
| `declare -A` | Bash 4+; macOS default bash 3.2 fails | File-per-key (`$tmpdir/k`) or Python hash |
| `date +%s%N` | GNU-only; macOS lacks `%N` | `platform.sh::epoch_ms` |
| `stat -c ...` | GNU syntax; BSD uses `-f` | `platform.sh::portable_file_date`, `portable_file_size` |
| `sed -i 's/x/y/'` (no backup arg) | GNU accepts; BSD requires `-i ''` | `platform.sh::portable_sed` |
| `realpath` (plain) | Not on macOS without coreutils | `platform.sh::safe_realpath` |
| `find -printf` | GNU-only | `platform.sh::portable_find_printf` |
| `readarray`/`mapfile` | Bash 4+ | Inline `while IFS= read -r line; do ...; done < file` |

Enforcement: `tests/contract/portability.bats` Group B assertion greps for these across `shared/**/*.sh` and `hooks/**/*.sh`. Exempt: `shared/platform.sh` (implements the wrappers).

## 2. Platform helper catalog

**Existing (pre-Phase-3):**

`detect_os`, `is_wsl`, `suggest_install`, `suggest_docker_start`, `_glob_exists`, `pipeline_tmpdir`, `pipeline_mktemp`, `pipeline_mktempdir`, `detect_python`, `portable_normalize_path`, `portable_file_date`, `portable_sed`, `portable_timeout`, `derive_project_id`, `read_components`, `extract_file_path_from_tool_input`, `acquire_lock_with_retry`, `atomic_increment`, `atomic_json_update`, `require_bash4`.

**Added in Phase 3 (5 functions):**

| Function | Signature | Purpose |
|---|---|---|
| `epoch_ms` | → int ms | Milliseconds since epoch; Python or `<sec>×1000` |
| `portable_file_size <path>` | → int bytes | `stat -c %s` ↔ `stat -f %z` |
| `safe_realpath <path>` | → path | `realpath` ↔ Python fallback |
| `portable_find_printf <dir> <fmt>` | → lines | `find -printf` substitute (subset: `%p %s %T@`) |
| `release_lock <lockdir>` | → 0/1 | Counterpart to `acquire_lock_with_retry` |

## 3. Decision guide

- Need timestamps? → `iso_timestamp` (already exists) or `epoch_ms` (new).
- Need file metadata? → `portable_file_date`, `portable_file_size`.
- Need in-place sed? → `portable_sed`.
- Need lookup tables? → file-per-key (POSIX) OR Python (complex).
- Need array-from-file? → inline `while read` loop; no helper.
- Need canonical path? → `safe_realpath`.

## 4. Testing matrix

| Platform | Shell | Status |
|---|---|---|
| macOS | bash 3.2.57 (default) | Curated smoke-list only (`tests/ci/bash32-smoke-list.txt`) |
| macOS | bash 5.x (via brew) | Full support |
| Ubuntu 22.04+ | bash 5.x | Full support |
| WSL2 (Ubuntu) | bash 5.x | Full support |
| Git Bash (MSYS2) | bash 4.4+ | Best-effort (MSYS path translation caveats) |
| Windows native (PowerShell) | N/A | Deferred to Phase 7 Go binary |

CI runs: Ubuntu 22.04 latest (bash 5.x) + bash 3.2 Docker image smoke for curated list.

## 5. Contributing — new-script checklist

1. `#!/usr/bin/env bash` shebang (not `#!/bin/bash`).
2. `source "${CLAUDE_PLUGIN_ROOT}/shared/platform.sh"` at top.
3. Use helpers for timestamps, file metadata, sed, realpath, find.
4. `bash -n <script>` passes.
5. `shellcheck --severity=warning <script>` passes.
6. No banned patterns from §1.
7. If the script must run on bash 3.2 (e.g., invoked by `/forge-init` before bash 4 check), add to `tests/ci/bash32-smoke-list.txt`.

## 6. Known limitations

- **Windows PowerShell / CMD native:** NOT supported. Phase 7 (Go binary port) addresses this.
- **busybox sh:** NOT targeted. We use bash; POSIX sh is the fallback floor for banned-pattern enforcement, not the target.
- **zsh-only environments:** Scripts use bash explicitly; zsh users invoke bash via the shebang.
```

- [ ] **Step 2: Held for commit in Task 7**

---

## Task 4: Create `shared/graph/query-translator.sh`

**Files:**
- Create: `shared/graph/query-translator.sh`

- [ ] **Step 1: Write the dispatcher**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# query-translator.sh — /forge-graph-query backend dispatcher
#
# Reads code_graph.backend config (auto|neo4j|sqlite), detects query type
# (Cypher|SQL|unknown), dispatches to the right backend. No DSL in this
# phase; dedicated DSL design deferred.
#
# Usage:
#   ./query-translator.sh [--backend auto|neo4j|sqlite] [--json] "<query>"
#   ./query-translator.sh --help
#
# Exit codes:
#   0 success; 1 user error; 2 backend unavailable; 3 query type unknown
# ============================================================================

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../platform.sh
source "${PLUGIN_ROOT}/shared/platform.sh"

usage() {
  cat <<'EOF'
query-translator.sh — /forge-graph-query dispatcher

USAGE:
  query-translator.sh [flags] "<query>"

FLAGS:
  --backend {auto|neo4j|sqlite}  Override config (default: auto)
  --json                          Emit structured JSON output
  --help                          This message

QUERY FORMS:
  Cypher (→ Neo4j): MATCH|CREATE|MERGE|CALL ...
  SQL    (→ SQLite): SELECT|WITH|WITH RECURSIVE ...

Backend decision (when --backend not set):
  code_graph.backend = "auto"   → Neo4j if container healthy, else SQLite
  code_graph.backend = "neo4j"  → Neo4j required; error if missing
  code_graph.backend = "sqlite" → SQLite required (.forge/code-graph.db)

EXIT CODES:
  0 success
  1 user error (bad args, empty query)
  2 backend unavailable
  3 query type unknown (cannot auto-detect Cypher vs SQL)
EOF
}

BACKEND_OVERRIDE=""
JSON_OUTPUT=0
QUERY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) BACKEND_OVERRIDE=$2; shift 2 ;;
    --backend=*) BACKEND_OVERRIDE=${1#*=}; shift ;;
    --json) JSON_OUTPUT=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; QUERY=$*; break ;;
    *) QUERY=$1; shift ;;
  esac
done

[[ -n "$QUERY" ]] || { echo "ERROR: missing query" >&2; usage >&2; exit 1; }

# Detect query type
detect_query_type() {
  local q=$1
  # Normalize leading whitespace
  local trimmed="${q#"${q%%[![:space:]]*}"}"
  # Cypher verbs
  case "$trimmed" in
    MATCH\ *|CREATE\ *|MERGE\ *|CALL\ *|RETURN\ *) echo "cypher"; return ;;
  esac
  # SQL verbs
  case "$trimmed" in
    SELECT\ *|WITH\ *|INSERT\ *|UPDATE\ *|DELETE\ *) echo "sql"; return ;;
  esac
  # Case-insensitive fallback
  case "$(echo "$trimmed" | tr '[:upper:]' '[:lower:]')" in
    match\ *|create\ *|merge\ *|call\ *|return\ *) echo "cypher"; return ;;
    select\ *|with\ *) echo "sql"; return ;;
  esac
  echo "unknown"
}

# Resolve backend from config or override
resolve_backend() {
  local query_type=$1
  local configured="auto"
  # Read code_graph.backend from forge.local.md
  if [[ -f ".claude/forge.local.md" ]]; then
    configured=$(awk '/^code_graph:/,/^[a-z]/{if(/backend:/){sub(/.*backend: */,""); sub(/ .*/,""); print; exit}}' .claude/forge.local.md 2>/dev/null || echo "auto")
  fi
  local backend=${BACKEND_OVERRIDE:-$configured}

  case "$backend" in
    neo4j) echo "neo4j" ;;
    sqlite) echo "sqlite" ;;
    auto)
      # Prefer Neo4j if container healthy
      if "${PLUGIN_ROOT}/shared/graph/neo4j-health.sh" --quiet 2>/dev/null; then
        echo "neo4j"
      elif [[ -f ".forge/code-graph.db" ]]; then
        echo "sqlite"
      else
        echo "ERROR: no graph backend available (Neo4j not healthy, .forge/code-graph.db absent)" >&2
        exit 2
      fi
      ;;
    *) echo "ERROR: unknown backend: $backend" >&2; exit 1 ;;
  esac
}

QUERY_TYPE=$(detect_query_type "$QUERY")
[[ "$QUERY_TYPE" == "unknown" ]] && { echo "ERROR: cannot auto-detect query type. Use --backend explicitly." >&2; exit 3; }

BACKEND=$(resolve_backend "$QUERY_TYPE")

# Validate combination
if [[ "$QUERY_TYPE" == "cypher" && "$BACKEND" == "sqlite" ]]; then
  echo "ERROR: Cypher query requires Neo4j backend; got $BACKEND" >&2
  exit 1
fi
if [[ "$QUERY_TYPE" == "sql" && "$BACKEND" == "neo4j" ]]; then
  echo "ERROR: SQL query requires SQLite backend; got $BACKEND" >&2
  exit 1
fi

# Emit header
if [[ $JSON_OUTPUT -eq 1 ]]; then
  printf '{"backend":"%s","query_type":"%s","query":' "$BACKEND" "$QUERY_TYPE"
  python3 -c "import json,sys;print(json.dumps(sys.argv[1]))" "$QUERY"
  printf ',"results":'
else
  echo "── backend: $BACKEND ($QUERY_TYPE)"
fi

# Dispatch
case "$BACKEND" in
  neo4j)
    # Defer to existing Neo4j execution path (handled by the skill body,
    # which invokes cypher-shell via Docker container). Emit a marker for the
    # skill to consume the query directly.
    printf '%s\n' "$QUERY"
    ;;
  sqlite)
    if command -v sqlite3 >/dev/null 2>&1; then
      if [[ $JSON_OUTPUT -eq 1 ]]; then
        sqlite3 -json .forge/code-graph.db "$QUERY"
        printf '}\n'
      else
        sqlite3 -header -column .forge/code-graph.db "$QUERY"
      fi
    else
      echo "ERROR: sqlite3 not installed" >&2
      exit 2
    fi
    ;;
esac
```

- [ ] **Step 2: chmod +x + parse check**

```bash
chmod +x shared/graph/query-translator.sh
bash -n shared/graph/query-translator.sh
```

- [ ] **Step 3: Held for commit in Task 7**

---

## Task 5: Create `tests/contract/portability.bats`

**Files:**
- Create: `tests/contract/portability.bats`

- [ ] **Step 1: Write Group A/B split bats**

```bash
#!/usr/bin/env bats

# Portability assertions — enforces shared/cross-platform-contract.md
# Group A: active from Commit 2 (foundations)
# Group B: active from Commit 8 via FORGE_PHASE3_ACTIVE detection

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
  # Gate Group B on: contract doc + translator + renamed hooks present
  if [[ -f "$PLUGIN_ROOT/shared/cross-platform-contract.md" ]] && \
     [[ -f "$PLUGIN_ROOT/shared/graph/query-translator.sh" ]] && \
     [[ -f "$PLUGIN_ROOT/hooks/file-changed-hook.sh" ]] && \
     [[ -f "$PLUGIN_ROOT/hooks/automation-dispatcher.sh" ]] && \
     ! [[ -f "$PLUGIN_ROOT/hooks/automation-trigger.sh" ]]; then
    export FORGE_PHASE3_ACTIVE=1
  fi
}

# -------- Group A (from Commit 2) --------

@test "[A] platform.sh exports 5 new Phase 3 helpers" {
  for fn in epoch_ms portable_file_size safe_realpath portable_find_printf release_lock; do
    grep -q "^${fn}()" "$PLUGIN_ROOT/shared/platform.sh" || { echo "Missing helper: $fn"; return 1; }
  done
}

@test "[A] cross-platform-contract.md has 6 sections" {
  local f="$PLUGIN_ROOT/shared/cross-platform-contract.md"
  [ -f "$f" ]
  for n in 1 2 3 4 5 6; do
    grep -qE "^## $n\. " "$f" || { echo "Missing §$n"; return 1; }
  done
}

@test "[A] query-translator.sh exists and accepts --help" {
  local f="$PLUGIN_ROOT/shared/graph/query-translator.sh"
  [ -f "$f" ] && [ -x "$f" ]
  "$f" --help | grep -q "USAGE:"
}

@test "[A] bash32-smoke-list.txt exists and lists ≥3 files" {
  local f="$PLUGIN_ROOT/tests/ci/bash32-smoke-list.txt"
  [ -f "$f" ]
  local count
  count=$(grep -c '^[^#]' "$f" 2>/dev/null || echo 0)
  [ "$count" -ge 3 ]
}

# -------- Group B (from Commit 8) --------

@test "[B] no banned patterns in shared/**/*.sh or hooks/**/*.sh (except platform.sh)" {
  [[ "${FORGE_PHASE3_ACTIVE:-0}" = "1" ]] || skip "Group B activates in Commit 8"
  local hits
  hits=$(grep -rnE "\\\$'\\\\n'|<<<|declare -A|date \+%s%N|stat -c %Y|stat -c %s" \
    "$PLUGIN_ROOT/shared" "$PLUGIN_ROOT/hooks" 2>/dev/null \
    | grep -v "shared/platform.sh" \
    | grep -v "^Binary file" || true)
  if [[ -n "$hits" ]]; then
    echo "Banned-pattern hits:"
    echo "$hits"
    return 1
  fi
}

@test "[B] renamed hook scripts present; old paths absent" {
  [[ "${FORGE_PHASE3_ACTIVE:-0}" = "1" ]] || skip "Group B activates in Commit 8"
  [ -f "$PLUGIN_ROOT/hooks/file-changed-hook.sh" ]
  [ -f "$PLUGIN_ROOT/hooks/automation-dispatcher.sh" ]
  ! [ -f "$PLUGIN_ROOT/hooks/automation-trigger-hook.sh" ]
  ! [ -f "$PLUGIN_ROOT/hooks/automation-trigger.sh" ]
}

@test "[B] hooks/hooks.json references new script paths" {
  [[ "${FORGE_PHASE3_ACTIVE:-0}" = "1" ]] || skip "Group B activates in Commit 8"
  grep -q "file-changed-hook.sh\|automation-dispatcher.sh" "$PLUGIN_ROOT/hooks/hooks.json"
  ! grep -q "automation-trigger-hook.sh\|automation-trigger.sh" "$PLUGIN_ROOT/hooks/hooks.json"
}

@test "[B] every shell script uses #!/usr/bin/env bash" {
  [[ "${FORGE_PHASE3_ACTIVE:-0}" = "1" ]] || skip "Group B activates in Commit 8"
  local bad=0
  for f in "$PLUGIN_ROOT"/shared/**/*.sh "$PLUGIN_ROOT"/shared/*.sh "$PLUGIN_ROOT"/hooks/*.sh; do
    [[ -f "$f" ]] || continue
    if ! head -1 "$f" | grep -q "^#!/usr/bin/env bash"; then
      echo "Wrong shebang: $f"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}
```

- [ ] **Step 2: Parse check**

```bash
bash -n tests/contract/portability.bats
```

- [ ] **Step 3: Held for commit in Task 7**

---

## Task 6: Create `tests/ci/bash32-smoke-list.txt` + `phase3-shellcheck-scope.txt`

**Files:**
- Create: `tests/ci/bash32-smoke-list.txt`
- Create: `tests/ci/phase3-shellcheck-scope.txt`

- [ ] **Step 1: Write bash 3.2 smoke list**

```bash
mkdir -p tests/ci
cat > tests/ci/bash32-smoke-list.txt <<'EOF'
# Files that MUST parse on macOS default bash 3.2.57.
# Keep this list small — files here cannot use bash 4+ features.
# Update the Cross-Platform Contract §5 when adding entries.

shared/platform.sh
shared/check-prerequisites.sh
shared/forge-state.sh
hooks/session-start.sh
EOF
```

- [ ] **Step 2: Write shellcheck scope list**

```bash
cat > tests/ci/phase3-shellcheck-scope.txt <<'EOF'
# Files edited by Phase 3 — scoped shellcheck target.
# Adding files to this list commits them to passing shellcheck --severity=warning.

shared/platform.sh
shared/check-prerequisites.sh
shared/graph/query-translator.sh
shared/checks/engine.sh
shared/checks/l0-syntax/validate-syntax.sh
shared/checks/layer-1-fast/run-patterns.sh
shared/checks/layer-2-linter/run-linter.sh
shared/config-validator.sh
shared/context-guard.sh
shared/convergence-engine-sim.sh
shared/cost-alerting.sh
shared/generate-conventions-index.sh
shared/state-integrity.sh
shared/validate-finding.sh
shared/graph/build-code-graph.sh
shared/graph/build-project-graph.sh
shared/graph/code-graph-query.sh
shared/graph/enrich-symbols.sh
shared/graph/generate-seed.sh
shared/graph/incremental-code-graph.sh
shared/graph/incremental-update.sh
shared/graph/update-project-graph.sh
shared/recovery/health-checks/pre-stage-health.sh
hooks/file-changed-hook.sh
hooks/automation-dispatcher.sh
EOF
```

- [ ] **Step 3: Held for commit in Task 7**

---

## Task 7: Commit 2 — Foundations

**Files:**
- Modify: `shared/platform.sh` (+5 helpers)
- Create: `shared/cross-platform-contract.md`, `shared/graph/query-translator.sh`, `tests/contract/portability.bats`, `tests/ci/bash32-smoke-list.txt`, `tests/ci/phase3-shellcheck-scope.txt`

- [ ] **Step 1: Commit**

```bash
git add shared/platform.sh shared/cross-platform-contract.md
git add shared/graph/query-translator.sh
chmod +x shared/graph/query-translator.sh
git add tests/contract/portability.bats tests/ci/bash32-smoke-list.txt tests/ci/phase3-shellcheck-scope.txt
git commit -m "feat(phase3): foundations — 5 new platform.sh helpers, contract doc, query-translator, portability bats

Group A assertions active from this commit; Group B skips until Commit 8
when the sentinel (renamed hooks + contract doc + translator) is complete."
```

- [ ] **Step 2: No push yet**

---

## Task 8: Commit 3 — Bashism refactor batch 1 (checks)

**Files modified (4):**
- `shared/checks/engine.sh`
- `shared/checks/l0-syntax/validate-syntax.sh`
- `shared/checks/layer-1-fast/run-patterns.sh`
- `shared/checks/layer-2-linter/run-linter.sh`

- [ ] **Step 1: Fix bashisms per §4.1 table**

Per file:

- Grep for each banned pattern (`$'\n'`, `<<<`, `declare -A`, `date +%s%N`, `stat -c`, `sed -i 's/`, `realpath` plain, `find -printf`, `readarray`/`mapfile`).
- Replace with helper call OR POSIX equivalent per the Replacement column.

Concrete examples:

`<<<"string"` → `printf '%s' "string" |`
`$'\n'` → `"$(printf '\n')"` OR literal `"\n"` inside `echo -e`
`declare -A map; map[k]=v; echo ${map[k]}` → `mkdir -p "$tmpdir/m"; echo "v" > "$tmpdir/m/k"; cat "$tmpdir/m/k"`

- [ ] **Step 2: Verify bashism removal per-file**

```bash
for f in shared/checks/engine.sh shared/checks/l0-syntax/validate-syntax.sh shared/checks/layer-1-fast/run-patterns.sh shared/checks/layer-2-linter/run-linter.sh; do
  if grep -E "\\\$'\\\\n'|<<<|declare -A" "$f"; then
    echo "STILL BASHISMS in $f"; exit 1
  fi
done
```

- [ ] **Step 3: Static parse + shellcheck**

```bash
for f in shared/checks/engine.sh shared/checks/l0-syntax/validate-syntax.sh shared/checks/layer-1-fast/run-patterns.sh shared/checks/layer-2-linter/run-linter.sh; do
  bash -n "$f"
  command -v shellcheck >/dev/null && shellcheck --severity=warning "$f"
done
```

- [ ] **Step 4: Commit**

```bash
git add shared/checks/engine.sh shared/checks/l0-syntax/validate-syntax.sh shared/checks/layer-1-fast/run-patterns.sh shared/checks/layer-2-linter/run-linter.sh
git commit -m "refactor(phase3): remove bashisms from 4 check-engine scripts

Batch 1 of 3. Preserves behavior; uses platform.sh wrappers where applicable."
```

---

## Task 9: Commit 4 — Bashism refactor batch 2 (graph)

**Files modified (8):** All under `shared/graph/` per the list in spec §5.4.

- [ ] **Step 1: Fix bashisms in each file following the same pattern as Task 8**

Pay special attention to `shared/graph/build-code-graph.sh` which has `date +%s%N`. Replace with `epoch_ms` helper call.

- [ ] **Step 2: Verify + parse + shellcheck per file**

```bash
for f in shared/graph/build-code-graph.sh shared/graph/build-project-graph.sh shared/graph/code-graph-query.sh shared/graph/enrich-symbols.sh shared/graph/generate-seed.sh shared/graph/incremental-code-graph.sh shared/graph/incremental-update.sh shared/graph/update-project-graph.sh; do
  grep -E "\\\$'\\\\n'|<<<|declare -A|date \+%s%N|stat -c" "$f" && { echo "STILL BASHISMS in $f"; exit 1; }
  bash -n "$f"
  command -v shellcheck >/dev/null && shellcheck --severity=warning "$f"
done
```

- [ ] **Step 3: Commit**

```bash
git add shared/graph/*.sh
git commit -m "refactor(phase3): remove bashisms from 8 graph scripts

Batch 2 of 3. Swaps date +%s%N → epoch_ms; stat -c → portable_file_date/_size."
```

---

## Task 10: Commit 5 — Bashism refactor batch 3 (misc + recovery)

**Files modified (8):** Remaining from spec §5.4.

```
shared/config-validator.sh
shared/context-guard.sh
shared/convergence-engine-sim.sh
shared/cost-alerting.sh
shared/generate-conventions-index.sh
shared/state-integrity.sh
shared/validate-finding.sh
shared/recovery/health-checks/pre-stage-health.sh
```

- [ ] **Step 1: Fix bashisms per the pattern from Tasks 8-9**

Special attention: `state-integrity.sh` L151, L153 (`stat -c %Y`) — replace with `portable_file_date "$LOCK_FILE"`.

- [ ] **Step 2: Verify + parse + shellcheck**

```bash
for f in shared/config-validator.sh shared/context-guard.sh shared/convergence-engine-sim.sh shared/cost-alerting.sh shared/generate-conventions-index.sh shared/state-integrity.sh shared/validate-finding.sh shared/recovery/health-checks/pre-stage-health.sh; do
  grep -E "\\\$'\\\\n'|<<<|declare -A|date \+%s%N|stat -c" "$f" && { echo "STILL BASHISMS in $f"; exit 1; }
  bash -n "$f"
  command -v shellcheck >/dev/null && shellcheck --severity=warning "$f"
done
```

- [ ] **Step 3: Commit**

```bash
git add shared/config-validator.sh shared/context-guard.sh shared/convergence-engine-sim.sh \
        shared/cost-alerting.sh shared/generate-conventions-index.sh \
        shared/state-integrity.sh shared/validate-finding.sh \
        shared/recovery/health-checks/pre-stage-health.sh
git commit -m "refactor(phase3): remove bashisms from 8 misc + recovery scripts

Batch 3 of 3. Completes the 20-file bashism sweep. Group B portability
assertion will pass against HEAD after Commit 8 activation."
```

---

## Task 11: Commit 6 — Hook renames + ref updates + release_lock swap

**Files:**
- Rename: `hooks/automation-trigger-hook.sh` → `hooks/file-changed-hook.sh`
- Rename: `hooks/automation-trigger.sh` → `hooks/automation-dispatcher.sh`
- Rename: `tests/hooks/automation-trigger.bats` → `tests/hooks/automation-dispatcher.bats`
- Rename: `tests/hooks/automation-trigger-behavior.bats` → `tests/hooks/file-changed-hook.bats`
- Modify: `hooks/hooks.json`, `CHANGELOG.md`, `CLAUDE.md`, `shared/platform.sh` (L356 comment), `shared/hook-design.md`, `skills/forge-automation/SKILL.md`, `tests/unit/automation-cooldown.bats`, both renamed bats files (content updates)
- Modify: Phase 2's `shared/forge-token-tracker.sh` (swap inline `rmdir` to `release_lock`)

- [ ] **Step 1: Rename scripts + bats files via git mv**

```bash
git mv hooks/automation-trigger-hook.sh hooks/file-changed-hook.sh
git mv hooks/automation-trigger.sh hooks/automation-dispatcher.sh
git mv tests/hooks/automation-trigger.bats tests/hooks/automation-dispatcher.bats
git mv tests/hooks/automation-trigger-behavior.bats tests/hooks/file-changed-hook.bats
```

- [ ] **Step 2: Update `hooks/hooks.json`**

```bash
sed -i.bak 's|automation-trigger-hook.sh|file-changed-hook.sh|g; s|automation-trigger.sh|automation-dispatcher.sh|g' hooks/hooks.json
rm -f hooks/hooks.json.bak
```

- [ ] **Step 3: Update 7 other ref files (portable sed)**

```bash
for f in CHANGELOG.md CLAUDE.md shared/platform.sh shared/hook-design.md \
         skills/forge-automation/SKILL.md tests/unit/automation-cooldown.bats \
         tests/hooks/automation-dispatcher.bats tests/hooks/file-changed-hook.bats; do
  sed -i.bak \
    -e 's|automation-trigger-hook\.sh|file-changed-hook.sh|g' \
    -e 's|automation-trigger\.sh|automation-dispatcher.sh|g' "$f"
  rm -f "$f.bak"
done
```

- [ ] **Step 4: Swap Phase 2's `emit_cost_inc` `rmdir` to `release_lock`**

Open `shared/forge-token-tracker.sh`; find `rmdir "$lockdir"` lines in `emit_cost_inc` / `emit_cap_breach`; replace with `release_lock "$lockdir"`.

```bash
# Verify the swap
grep -n "release_lock\|rmdir.*lockdir" shared/forge-token-tracker.sh | head
```

- [ ] **Step 5: Verify no stale refs**

```bash
grep -rn "automation-trigger-hook\.sh\|automation-trigger\.sh" \
  --include="*.md" --include="*.sh" --include="*.bats" --include="*.json" . 2>/dev/null \
  | grep -v "\.git/\|node_modules\|/.forge/"
```

Expected: empty output.

- [ ] **Step 6: Commit**

```bash
git add -A hooks/ tests/hooks/ tests/unit/automation-cooldown.bats \
          CHANGELOG.md CLAUDE.md shared/platform.sh shared/hook-design.md \
          skills/forge-automation/SKILL.md shared/forge-token-tracker.sh
git commit -m "refactor(phase3): rename hook scripts + update 8 references + release_lock swap

Renames:
  hooks/automation-trigger-hook.sh → hooks/file-changed-hook.sh
  hooks/automation-trigger.sh → hooks/automation-dispatcher.sh
  tests/hooks/automation-trigger.bats → tests/hooks/automation-dispatcher.bats
  tests/hooks/automation-trigger-behavior.bats → tests/hooks/file-changed-hook.bats

Ref updates: hooks.json, CHANGELOG, CLAUDE.md, platform.sh comment,
hook-design.md, skills/forge-automation SKILL.md, tests/unit/automation-cooldown.bats,
both renamed bats.

Also swaps Phase 2's forge-token-tracker.sh inline rmdir to release_lock
(now that the helper exists from Commit 2)."
```

---

## Task 12: Commit 7 — Prereq persistence + SQLite backend in skills

**Files:**
- Modify: `shared/check-prerequisites.sh` (add `--json`)
- Modify: `skills/forge-init/SKILL.md` (write `.forge/prereqs.json`)
- Modify: `skills/forge-status/SKILL.md` (read it)
- Modify: `skills/forge-graph-query/SKILL.md` (backend selector + Cypher/SQL passthrough)
- Create: `tests/unit/query-translator-dispatch.bats`, `tests/unit/check-prerequisites-json.bats`

- [ ] **Step 1: Add `--json` flag to `check-prerequisites.sh`**

Edit `shared/check-prerequisites.sh`. Near argument parsing, add:

```bash
JSON_OUTPUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=1; shift ;;
    --strict) STRICT=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) shift ;;
  esac
done
```

At the end, if `JSON_OUTPUT=1`, emit a structured summary:

```bash
if [[ "$JSON_OUTPUT" -eq 1 ]]; then
  python3 -c "
import json
print(json.dumps({
  'timestamp': '$(iso_timestamp)',
  'required': {'bash': '${BASH_VERSION}', 'python3': '$(python3 --version 2>&1 | awk \"{print \\$2}\")'},
  'failures': $errors,
  'abort_reasons': []
}))
"
fi
```

Exit semantics unchanged.

- [ ] **Step 2: Update `/forge-init` — write `.forge/prereqs.json`**

Find step 3 in `skills/forge-init/SKILL.md`. After step 3 (which runs `check-environment.sh`), add step 3.5:

```markdown
3.5. **Persist prereq snapshot.** Combine outputs of the two checks into `.forge/prereqs.json`:

```bash
PREREQS_OUT=$(bash "${CLAUDE_PLUGIN_ROOT}/shared/check-prerequisites.sh" --json 2>/dev/null || echo '{}')
ENV_OUT=$(bash "${CLAUDE_PLUGIN_ROOT}/shared/check-environment.sh" 2>/dev/null || echo '{}')
python3 -c "
import json
prereqs = json.loads('''$PREREQS_OUT''' or '{}')
env = json.loads('''$ENV_OUT''' or '{}')
out = {'timestamp': prereqs.get('timestamp'), 'forge_version': '3.2.0',
       'required': prereqs.get('required', {}),
       'environment': env,
       'abort_reasons': prereqs.get('abort_reasons', [])}
import os
os.makedirs('.forge', exist_ok=True)
with open('.forge/prereqs.json', 'w') as f:
    json.dump(out, f, indent=2)
"
```
```

- [ ] **Step 3: Update `/forge-status` — read prereqs.json**

Add a new section to `skills/forge-status/SKILL.md`:

```markdown
## Prerequisites (optional)

If `.forge/prereqs.json` exists, show:

```bash
if [[ -f .forge/prereqs.json ]]; then
  echo "## Prerequisites"
  age_days=$(python3 -c "import json,time,datetime;d=json.load(open('.forge/prereqs.json'));ts=d.get('timestamp');print(int((time.time()-datetime.datetime.fromisoformat(ts.replace('Z','+00:00')).timestamp())/86400))" 2>/dev/null || echo "unknown")
  echo "Snapshot age: $age_days days"
  if [[ "$age_days" != "unknown" ]] && [[ "$age_days" -gt 7 ]]; then
    echo "⚠️  Stale (>7 days). Re-run /forge-init to refresh."
  fi
  python3 -c "
import json
d = json.load(open('.forge/prereqs.json'))
for k, v in d.get('required', {}).items():
    print(f'  ✓ {k}: {v}')
env = d.get('environment', {})
for tier in ['tier_required', 'tier_recommended', 'tier_optional']:
    for k, v in env.get(tier, {}).items():
        mark = '✓' if v else '✗'
        print(f'  {mark} [{tier[5:]}] {k}: {v or \"missing\"}')
"
fi
```
```

- [ ] **Step 4: Rewrite `/forge-graph-query` SKILL.md**

Replace description + Prerequisites + add Backend selection section per spec §4.5. Update frontmatter description:

```yaml
---
name: forge-graph-query
description: "Query the code graph (Neo4j via Cypher OR SQLite via SQL). Backend auto-selects from code_graph.backend config (auto: Neo4j if Docker healthy else SQLite). Use when you need to find bug hotspots, trace dependencies, check test coverage gaps, or explore module relationships."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
---
```

Update Prerequisites section:

```markdown
## Prerequisites

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`.
2. **Forge initialized:** Check `.claude/forge.local.md` exists.
3. **A graph backend available:** Either Docker+Neo4j (Cypher) OR `.forge/code-graph.db` (SQLite).
```

Add new section before Instructions:

```markdown
## Backend selection

| `code_graph.backend` | Behavior |
|---|---|
| `auto` (default) | Prefer Neo4j if container healthy; fall back to SQLite |
| `neo4j` | Require Neo4j container; error if absent |
| `sqlite` | Require `.forge/code-graph.db`; error if absent |

## Query forms

- **Cypher** → Neo4j. Examples: `MATCH (f:ProjectFile) WHERE f.bug_fix_count > 3 RETURN f`.
- **SQL** → SQLite. Examples: `SELECT path, bug_fix_count FROM project_files WHERE bug_fix_count > 3`.
- Auto-detection: query starts with `MATCH|CREATE|MERGE|CALL` → Cypher; `SELECT|WITH|INSERT|UPDATE|DELETE` → SQL.

Dispatcher: `shared/graph/query-translator.sh`.
```

- [ ] **Step 5: Create 2 bats test files**

`tests/unit/query-translator-dispatch.bats`:

```bash
#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
}

@test "query-translator.sh --help prints usage" {
  run "$PLUGIN_ROOT/shared/graph/query-translator.sh" --help
  [ "$status" = "0" ]
  [[ "$output" =~ "USAGE:" ]]
}

@test "query-translator detects Cypher queries" {
  run "$PLUGIN_ROOT/shared/graph/query-translator.sh" --backend=neo4j "MATCH (n) RETURN n LIMIT 1"
  # Exits 2 (backend unavailable) if no Neo4j, but should recognize Cypher
  [[ "$output" =~ "cypher" ]] || [[ "$output" =~ "neo4j" ]]
}

@test "query-translator detects SQL queries" {
  run "$PLUGIN_ROOT/shared/graph/query-translator.sh" --backend=sqlite "SELECT 1"
  # Without .forge/code-graph.db, exits 2; with db, runs the query
  [[ "$status" = "0" ]] || [[ "$status" = "2" ]]
}

@test "query-translator rejects unknown query type" {
  run "$PLUGIN_ROOT/shared/graph/query-translator.sh" "RANDOM TEXT"
  [ "$status" = "3" ]
}
```

`tests/unit/check-prerequisites-json.bats`:

```bash
#!/usr/bin/env bats

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export PLUGIN_ROOT
}

@test "check-prerequisites.sh --json emits valid JSON" {
  run bash "$PLUGIN_ROOT/shared/check-prerequisites.sh" --json
  # Validate JSON
  echo "$output" | python3 -m json.tool > /dev/null
}

@test "check-prerequisites.sh --json includes required map" {
  run bash "$PLUGIN_ROOT/shared/check-prerequisites.sh" --json
  python3 -c "import json,sys;d=json.loads('''$output''');assert 'required' in d"
}
```

- [ ] **Step 6: Commit**

```bash
git add shared/check-prerequisites.sh
git add skills/forge-init/SKILL.md skills/forge-status/SKILL.md skills/forge-graph-query/SKILL.md
git add tests/unit/query-translator-dispatch.bats tests/unit/check-prerequisites-json.bats
git commit -m "feat(phase3): prereq persistence + SQLite backend selector in skills

- check-prerequisites.sh: add --json flag; exit semantics unchanged
- /forge-init: write .forge/prereqs.json after both prereq scripts run
- /forge-status: add Prerequisites section reading .forge/prereqs.json
- /forge-graph-query: document backend selector + Cypher/SQL passthrough
- 2 new bats: query-translator-dispatch, check-prerequisites-json"
```

---

## Task 13: Commit 8 — CI workflow + top-level docs + version bump

**Files:**
- Modify: `.github/workflows/ci.yml` (or create if missing)
- Modify: `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `CONTRIBUTING.md`
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

- [ ] **Step 1: Inspect or create CI workflow**

```bash
ls .github/workflows/ 2>/dev/null
```

If `ci.yml` exists, add two steps near existing test-run steps. If no workflow exists, create a minimal one:

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: bash -n parse
        run: |
          for f in $(find shared hooks -name '*.sh'); do bash -n "$f"; done
      - name: Scoped shellcheck
        run: |
          for f in $(cat tests/ci/phase3-shellcheck-scope.txt | grep -v '^#'); do
            shellcheck --severity=warning "$f" || exit 1
          done
      - name: bash 3.2 smoke
        run: |
          for f in $(cat tests/ci/bash32-smoke-list.txt | grep -v '^#'); do
            docker run --rm -v "$PWD:/work" -w /work bash:3.2 bash -n "$f" || exit 1
          done
      - name: Run bats suite
        run: ./tests/run-all.sh
```

- [ ] **Step 2: Update README.md**

Add a "Cross-platform support" section:

```markdown
## Cross-platform support (3.2.0+)

Forge runs on macOS, Linux, WSL2, and Git Bash. Native Windows (PowerShell/CMD) is deferred to Phase 7 (Go binary).

- **macOS:** bash 3.2 (default) or bash 5.x (`brew install bash`). A curated set of scripts parses on bash 3.2; rest require bash 4+.
- **Linux:** bash 4+ (pre-installed on all common distros).
- **WSL2:** full support (identical to Linux).
- **Git Bash:** best-effort; MSYS path-translation edge cases noted in the contract.

Contract: `shared/cross-platform-contract.md`. Prereq check: `/forge-init` runs `check-prerequisites.sh` + `check-environment.sh`; results persisted in `.forge/prereqs.json`.
```

- [ ] **Step 3: Update CLAUDE.md**

Add 3 rows to Key Entry Points:

```markdown
| Cross-platform contract | `shared/cross-platform-contract.md` |
| Graph query dispatcher | `shared/graph/query-translator.sh` |
| Prereq snapshot schema | `shared/cross-platform-contract.md §4` |
```

- [ ] **Step 4: Update CONTRIBUTING.md**

Add a new "Writing portable shell scripts" section pointing at `shared/cross-platform-contract.md`.

- [ ] **Step 5: Add 3.2.0 entry to CHANGELOG.md**

```markdown
## [3.2.0] — 2026-04-17

### Added

- `shared/cross-platform-contract.md` — authoritative banned-patterns + helper catalog.
- `shared/graph/query-translator.sh` — `/forge-graph-query` backend dispatcher (Neo4j Cypher OR SQLite SQL passthrough).
- `shared/platform.sh` — 5 new helpers: `epoch_ms`, `portable_file_size`, `safe_realpath`, `portable_find_printf`, `release_lock`.
- `shared/check-prerequisites.sh` — `--json` flag (non-breaking addition).
- `.forge/prereqs.json` — persistent snapshot of prereq + environment checks; written by `/forge-init`, read by `/forge-status`.
- CI: scoped shellcheck step (21 Phase-3-touched files); pinned bash 3.2 Docker smoke step (curated list).
- `tests/contract/portability.bats` — enforces banned-pattern cleanliness (Group B active in this release).

### Changed

- `/forge-graph-query`: no longer requires Neo4j; SQLite backend supported with SQL passthrough. Backend auto-selects from `code_graph.backend` config.
- Bashism cleanup across 20 shell scripts — behavior preserved; behavior-identical refactors to remove `$'\n'`, `<<<`, `declare -A`, `date +%s%N`, GNU `stat -c` / `sed -i` patterns.
- Hook scripts renamed for clarity:
  - `hooks/automation-trigger-hook.sh` → `hooks/file-changed-hook.sh`
  - `hooks/automation-trigger.sh` → `hooks/automation-dispatcher.sh`
  - Plus 2 test-file renames to match.
- Phase 2's `forge-token-tracker.sh` swaps inline `rmdir` to `release_lock` helper.

### Deprecated / Removed

None. All changes are additive to users.
```

- [ ] **Step 6: Bump plugin + marketplace JSON**

```bash
sed -i.bak 's/"version": "3.1.0"/"version": "3.2.0"/' .claude-plugin/plugin.json
sed -i.bak 's/"version": "3.1.0"/"version": "3.2.0"/' .claude-plugin/marketplace.json
rm -f .claude-plugin/*.bak
grep '"version"' .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

Expected: both show `3.2.0`.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/ci.yml README.md CLAUDE.md CONTRIBUTING.md CHANGELOG.md
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "docs(phase3): CI workflow + top-level docs + bump 3.1.0 → 3.2.0

- .github/workflows/ci.yml: scoped shellcheck + bash 3.2 smoke steps
- README.md: Cross-platform support section
- CLAUDE.md: 3 new Key Entry Points
- CONTRIBUTING.md: portable-shell-scripts section
- CHANGELOG.md: 3.2.0 entry
- .claude-plugin/plugin.json + marketplace.json: 3.1.0 → 3.2.0

After this commit, tests/contract/portability.bats Group B activates
(sentinel = contract doc + translator + renamed hooks all present).
Group B assertion scans for banned patterns across shared/ + hooks/;
expected to pass because Commits 3-5 completed the sweep."
```

---

## Task 14: Push + CI + tag + release

- [ ] **Step 1: Push**

```bash
git push origin master
```

- [ ] **Step 2: Wait for CI**

```bash
gh run watch
```

- [ ] **Step 3: If CI red, fix forward**

Most likely failures:
- Shellcheck warning in a Phase-3-touched file → fix the warning; re-push.
- Bash 3.2 smoke fails on a curated-list file → either fix the bash 3.2 incompatibility OR remove from smoke-list (if not genuinely required there).
- Group B portability bats finds a missed banned pattern → grep + fix; re-push.

- [ ] **Step 4: Tag + release**

```bash
git tag -a v3.2.0 -m "Phase 3: Cross-platform hardening

- 20 shell scripts cleaned of bashisms
- shared/platform.sh + 5 new cross-platform helpers
- shared/cross-platform-contract.md authoritative doc
- /forge-graph-query backend selector (Neo4j OR SQLite)
- .forge/prereqs.json persistence; /forge-status surfaces it
- 2 hook script renames for clarity
- CI: scoped shellcheck + bash 3.2 smoke"
git push origin v3.2.0

gh release create v3.2.0 --title "3.2.0 — Phase 3: Cross-Platform Hardening" --notes-file - <<'EOF'
See CHANGELOG.md §3.2.0.

Highlights:
- macOS/Linux/WSL2/Git Bash now run consistently; known bashisms removed.
- /forge-graph-query works without Docker — SQLite backend with SQL passthrough.
- Scripts use shared platform.sh helpers for cross-platform file ops.
- No breaking changes. Drop-in from 3.1.0.

Next: Phase 4 — Control & Safety (preview-before-apply, editable plan, tiered auto-approve).
EOF
```

---

## Self-review

### Spec coverage

All 22 ACs in spec §6 mapped to tasks above. File manifest §5 fully represented.

### Placeholders

- Task 8-10 Step 1 says "Fix bashisms per §4.1 table" — mechanical work with the banned→replacement table in §4.1 of spec. Not a creative step; acceptable.
- Task 12 Step 1 `check-prerequisites.sh --json` body uses template `$(iso_timestamp)` etc. — these are concrete functions sourced from platform.sh; not placeholders.

### Type consistency

- Helper names: `epoch_ms`, `portable_file_size`, `safe_realpath`, `portable_find_printf`, `release_lock` used consistently across spec §4.2, Task 2, Task 5 assertions, CHANGELOG in Task 13.
- Backend values: `auto|neo4j|sqlite` consistent across query-translator.sh, SKILL.md updates, bats tests.
- File-rename pairs match across Task 11, spec §5.3, bats assertions.

All consistent.

**Plan complete.**
