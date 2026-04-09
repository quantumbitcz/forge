# P0: Reliability Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the pipeline's "deterministic" state machine actually deterministic by moving transition logic from prose instructions into executable scripts. Protect state.json from corruption. Reduce orchestrator token cost by 60%.

**Architecture:** Three executable bash scripts (`forge-state-write.sh`, `forge-state.sh`, `check-prerequisites.sh`) form a layered state management stack. The orchestrator splits into 4 markdown files (core + boot + execute + ship). Scoring defaults are softened. All changes are backwards-compatible with state schema v1.5.0.

**Tech Stack:** Bash 4.0+, Python 3 (embedded via `python3 -c`), jq (optional, python3 fallback), bats testing framework.

**Spec:** `docs/superpowers/specs/2026-04-09-forge-hardening-design.md` (sections P0-1 through P0-5)

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `shared/check-prerequisites.sh` | Validates bash 4+ and python3 are available |
| Create | `shared/forge-state-write.sh` | Atomic JSON writes with WAL and _seq versioning |
| Create | `shared/forge-state.sh` | State machine transitions, counter management, guard evaluation |
| Modify | `shared/state-schema.md` | Bump to v1.5.0, add `_seq`, `diminishing_count`, `unfixable_info_count` |
| Modify | `shared/state-transitions.md` | Add row 50 for `score_diminishing` event |
| Modify | `shared/scoring.md` | Default `shipping.min_score` to 90, add INFO efficiency policy |
| Modify | `shared/convergence-engine.md` | Default `target_score` to 90, add diminishing returns section |
| Create | `agents/fg-100-orchestrator-core.md` | Identity, forbidden actions, principles, dispatch protocol |
| Create | `agents/fg-100-orchestrator-boot.md` | PREFLIGHT (Stage 0) |
| Create | `agents/fg-100-orchestrator-execute.md` | Stages 1-6 (EXPLORE through REVIEW) |
| Create | `agents/fg-100-orchestrator-ship.md` | Stages 7-9 (DOCS through LEARN) |
| Delete | `agents/fg-100-orchestrator.md` | Replaced by the 4 files above |
| Create | `tests/unit/forge-state-write.bats` | Atomic write + WAL tests |
| Create | `tests/unit/forge-state.bats` | State machine transition tests |
| Create | `tests/scenario/state-transitions.bats` | End-to-end transition scenarios |
| Modify | `tests/validate-plugin.sh` | Add structural checks for new files |

---

## Task 1: check-prerequisites.sh

**Files:**
- Create: `shared/check-prerequisites.sh`

- [ ] **Step 1: Create the prerequisite checker script**

```bash
cat > shared/check-prerequisites.sh << 'SCRIPT'
#!/usr/bin/env bash
# Validates that forge plugin prerequisites are met.
# Exit 0 if all pass, exit N where N = number of failures.
set -uo pipefail

errors=0

# Bash 4.0+ check
BASH_MAJOR="${BASH_VERSINFO[0]}"
if [[ "$BASH_MAJOR" -lt 4 ]]; then
  echo "ERROR: forge plugin requires bash 4.0+ (found ${BASH_VERSION})"
  echo "  Install with: brew install bash"
  errors=$((errors + 1))
fi

# Python 3 check
if ! command -v python3 &>/dev/null; then
  echo "ERROR: forge plugin requires python3 (not found)"
  echo "  Install with: brew install python3"
  errors=$((errors + 1))
fi

if [[ $errors -eq 0 ]]; then
  echo "OK: all prerequisites met (bash ${BASH_VERSION}, python3 $(python3 --version 2>&1 | awk '{print $2}'))"
fi

exit "$errors"
SCRIPT
chmod +x shared/check-prerequisites.sh
```

- [ ] **Step 2: Run it to verify it passes on this machine**

Run: `bash shared/check-prerequisites.sh`
Expected: `OK: all prerequisites met (bash X.Y.Z, python3 X.Y.Z)`

- [ ] **Step 3: Commit**

```bash
git add shared/check-prerequisites.sh
git commit -m "feat: add check-prerequisites.sh for bash 4+ and python3 validation"
```

---

## Task 2: forge-state-write.sh — Atomic Writes with WAL

**Files:**
- Create: `shared/forge-state-write.sh`
- Create: `tests/unit/forge-state-write.bats`

- [ ] **Step 1: Write the failing tests**

```bash
cat > tests/unit/forge-state-write.bats << 'TESTS'
#!/usr/bin/env bats
# Unit tests: forge-state-write.sh — atomic JSON writes with WAL and versioning.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state-write.sh"

# ---------------------------------------------------------------------------
# 1. Script existence and structure
# ---------------------------------------------------------------------------

@test "forge-state-write: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-state-write: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. Write operation
# ---------------------------------------------------------------------------

@test "forge-state-write: write creates state.json from JSON input" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","story_state":"PREFLIGHT"}' --forge-dir "$forge_dir"
  assert_success

  assert [ -f "$forge_dir/state.json" ]
  local state
  state=$(cat "$forge_dir/state.json")
  echo "$state" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['story_state']=='PREFLIGHT'"
}

@test "forge-state-write: write increments _seq counter" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success
  local seq1
  seq1=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['_seq'])")
  assert_equal "$seq1" "1"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":1}' --forge-dir "$forge_dir"
  assert_success
  local seq2
  seq2=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['_seq'])")
  assert_equal "$seq2" "2"
}

@test "forge-state-write: write appends to WAL" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/state.wal" ]

  local wal_entries
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  assert_equal "$wal_entries" "1"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":1}' --forge-dir "$forge_dir"
  assert_success
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  assert_equal "$wal_entries" "2"
}

@test "forge-state-write: rejects stale writes (lower _seq)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success

  # Try to write with _seq=0 again (stale — current file has _seq=1)
  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_failure
  assert_output --partial "stale"
}

# ---------------------------------------------------------------------------
# 3. Read operation
# ---------------------------------------------------------------------------

@test "forge-state-write: read returns valid JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0,"story_state":"EXPLORING"}' --forge-dir "$forge_dir"

  run bash "$SCRIPT" read --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['story_state']=='EXPLORING'"
}

@test "forge-state-write: read fails when neither state.json nor WAL exists" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" read --forge-dir "$forge_dir"
  assert_failure
}

# ---------------------------------------------------------------------------
# 4. Recovery
# ---------------------------------------------------------------------------

@test "forge-state-write: recover restores from WAL when state.json missing" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" write '{"version":"1.5.0","_seq":0,"story_state":"IMPLEMENTING"}' --forge-dir "$forge_dir"
  assert [ -f "$forge_dir/state.wal" ]

  # Delete state.json, simulating corruption
  rm "$forge_dir/state.json"

  run bash "$SCRIPT" recover --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/state.json" ]

  local restored_state
  restored_state=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['story_state'])")
  assert_equal "$restored_state" "IMPLEMENTING"
}

# ---------------------------------------------------------------------------
# 5. WAL truncation
# ---------------------------------------------------------------------------

@test "forge-state-write: WAL truncates at 50 entries" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  for i in $(seq 0 54); do
    bash "$SCRIPT" write "{\"version\":\"1.5.0\",\"_seq\":$i}" --forge-dir "$forge_dir"
  done

  local wal_entries
  wal_entries=$(grep -c "^--- SEQ:" "$forge_dir/state.wal")
  assert [ "$wal_entries" -le 50 ]
}

# ---------------------------------------------------------------------------
# 6. Concurrent write safety
# ---------------------------------------------------------------------------

@test "forge-state-write: no .tmp file left after successful write" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" write '{"version":"1.5.0","_seq":0}' --forge-dir "$forge_dir"
  assert_success
  assert [ ! -f "$forge_dir/state.json.tmp" ]
}
TESTS
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/unit/forge-state-write.bats`
Expected: All tests FAIL (script does not exist yet)

- [ ] **Step 3: Implement forge-state-write.sh**

```bash
cat > shared/forge-state-write.sh << 'SCRIPT'
#!/usr/bin/env bash
# Atomic JSON state writer with WAL (write-ahead log) and _seq versioning.
# Usage:
#   forge-state-write.sh write <json> [--forge-dir <path>]
#   forge-state-write.sh read [--forge-dir <path>]
#   forge-state-write.sh recover [--forge-dir <path>]
set -uo pipefail

FORGE_DIR=".forge"
CMD=""
JSON_CONTENT=""
WAL_MAX_ENTRIES=50

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    write)   CMD="write"; shift; JSON_CONTENT="${1:-}"; shift ;;
    read)    CMD="read"; shift ;;
    recover) CMD="recover"; shift ;;
    --forge-dir) shift; FORGE_DIR="${1:?--forge-dir requires a path}"; shift ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$CMD" ]] && { echo "Usage: forge-state-write.sh {write|read|recover} [--forge-dir <path>]" >&2; exit 2; }

STATE_FILE="${FORGE_DIR}/state.json"
WAL_FILE="${FORGE_DIR}/state.wal"
TMP_FILE="${FORGE_DIR}/state.json.tmp"

# ── Write ─────────────────────────────────────────────────────────────────

do_write() {
  [[ -z "$JSON_CONTENT" ]] && { echo "ERROR: write requires JSON content" >&2; exit 2; }

  # Validate input is valid JSON
  if ! echo "$JSON_CONTENT" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    echo "ERROR: invalid JSON input" >&2
    exit 2
  fi

  # Read current _seq from existing state.json (0 if not present)
  local current_seq=0
  if [[ -f "$STATE_FILE" ]]; then
    current_seq=$(python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f:
        print(json.load(f).get('_seq', 0))
except:
    print(0)
" 2>/dev/null || echo "0")
  fi

  # Read input _seq
  local input_seq
  input_seq=$(echo "$JSON_CONTENT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('_seq', 0))")

  # Reject stale writes
  if [[ -f "$STATE_FILE" ]] && [[ "$input_seq" -lt "$current_seq" ]]; then
    echo "ERROR: stale write rejected (_seq $input_seq < current $current_seq)" >&2
    exit 1
  fi

  # Increment _seq
  local new_seq=$((current_seq + 1))
  local updated_json
  updated_json=$(echo "$JSON_CONTENT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
d['_seq'] = $new_seq
json.dump(d, sys.stdout, indent=2)
")

  # Append to WAL
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)
  {
    echo "--- SEQ:${new_seq} TS:${ts} ---"
    echo "$updated_json"
  } >> "$WAL_FILE"

  # Truncate WAL if over limit
  local wal_count
  wal_count=$(grep -c "^--- SEQ:" "$WAL_FILE" 2>/dev/null || echo "0")
  if [[ "$wal_count" -gt "$WAL_MAX_ENTRIES" ]]; then
    # Keep last WAL_MAX_ENTRIES entries
    python3 -c "
import re, sys
with open('$WAL_FILE') as f:
    content = f.read()
entries = re.split(r'(?=^--- SEQ:)', content, flags=re.MULTILINE)
entries = [e for e in entries if e.strip()]
keep = entries[-$WAL_MAX_ENTRIES:]
with open('$WAL_FILE', 'w') as f:
    f.write(''.join(keep))
"
  fi

  # Atomic write: tmp + mv
  echo "$updated_json" > "$TMP_FILE"
  mv "$TMP_FILE" "$STATE_FILE"

  echo "$updated_json"
}

# ── Read ──────────────────────────────────────────────────────────────────

do_read() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
    return 0
  fi

  if [[ -f "$WAL_FILE" ]]; then
    echo "WARNING: state.json missing, recovering from WAL" >&2
    do_recover
    return $?
  fi

  echo "ERROR: no state.json or WAL found in $FORGE_DIR" >&2
  return 1
}

# ── Recover ───────────────────────────────────────────────────────────────

do_recover() {
  if [[ ! -f "$WAL_FILE" ]]; then
    echo "ERROR: no WAL file found at $WAL_FILE" >&2
    return 1
  fi

  # Extract last valid JSON entry from WAL
  local recovered
  recovered=$(python3 -c "
import re, json, sys
with open('$WAL_FILE') as f:
    content = f.read()
entries = re.split(r'^--- SEQ:\d+ TS:\S+ ---$', content, flags=re.MULTILINE)
entries = [e.strip() for e in entries if e.strip()]
if not entries:
    sys.exit(1)
# Try from last entry backwards to find valid JSON
for entry in reversed(entries):
    try:
        d = json.loads(entry)
        json.dump(d, sys.stdout, indent=2)
        sys.exit(0)
    except json.JSONDecodeError:
        continue
sys.exit(1)
")

  if [[ $? -ne 0 ]] || [[ -z "$recovered" ]]; then
    echo "ERROR: no valid JSON found in WAL" >&2
    return 1
  fi

  echo "$recovered" > "$TMP_FILE"
  mv "$TMP_FILE" "$STATE_FILE"
  cat "$STATE_FILE"
}

# ── Dispatch ──────────────────────────────────────────────────────────────

case "$CMD" in
  write)   do_write ;;
  read)    do_read ;;
  recover) do_recover ;;
esac
SCRIPT
chmod +x shared/forge-state-write.sh
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/unit/forge-state-write.bats`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add shared/forge-state-write.sh tests/unit/forge-state-write.bats
git commit -m "feat: add forge-state-write.sh with atomic writes, WAL, and _seq versioning"
```

---

## Task 3: forge-state.sh — Executable State Machine

**Files:**
- Create: `shared/forge-state.sh`
- Create: `tests/unit/forge-state.bats`

This is the largest task. The script encodes the complete transition table from `shared/state-transitions.md`.

- [ ] **Step 1: Write the core failing tests (init + query + basic transitions)**

```bash
cat > tests/unit/forge-state.bats << 'TESTS'
#!/usr/bin/env bats
# Unit tests: forge-state.sh — executable state machine for pipeline transitions.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state.sh"

# ---------------------------------------------------------------------------
# 1. Script existence and structure
# ---------------------------------------------------------------------------

@test "forge-state: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-state: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. Init command
# ---------------------------------------------------------------------------

@test "forge-state: init creates valid state.json with all required fields" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" init "feat-test" "Add test feature" --mode standard --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/state.json" ]

  python3 -c "
import json, sys
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['version'] == '1.5.0', f'version: {d[\"version\"]}'
assert d['complete'] == False
assert d['story_id'] == 'feat-test'
assert d['story_state'] == 'PREFLIGHT'
assert d['mode'] == 'standard'
assert d['total_retries'] == 0
assert d['total_retries_max'] == 10
assert d['_seq'] >= 1
assert 'convergence' in d
assert d['convergence']['phase'] == 'correctness'
assert d['convergence']['convergence_state'] == 'IMPROVING'
assert d['convergence']['diminishing_count'] == 0
"
}

@test "forge-state: init with --dry-run sets dry_run flag" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" init "feat-test" "Test" --mode standard --dry-run --forge-dir "$forge_dir"
  assert_success

  local dry_run
  dry_run=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['dry_run'])")
  assert_equal "$dry_run" "True"
}

@test "forge-state: init with --mode bugfix sets mode" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" init "fix-bug" "Fix bug" --mode bugfix --forge-dir "$forge_dir"
  assert_success

  local mode
  mode=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['mode'])")
  assert_equal "$mode" "bugfix"
}

# ---------------------------------------------------------------------------
# 3. Query command
# ---------------------------------------------------------------------------

@test "forge-state: query returns current state as JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['story_state']=='PREFLIGHT'"
}

# ---------------------------------------------------------------------------
# 4. Normal flow transitions
# ---------------------------------------------------------------------------

@test "forge-state: PREFLIGHT + preflight_complete (dry_run=false) → EXPLORING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  run bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='EXPLORING'"
}

@test "forge-state: EXPLORING + explore_complete (scope < threshold) → PLANNING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='PLANNING'"
}

@test "forge-state: EXPLORING + explore_complete (scope >= threshold) → DECOMPOSED" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition explore_complete --guard "scope=5" --guard "decomposition_threshold=3" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='DECOMPOSED'"
}

@test "forge-state: PLANNING + plan_complete → VALIDATING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VALIDATING'"
}

@test "forge-state: VALIDATING + verdict_GO (risk <= auto_proceed) → IMPLEMENTING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='IMPLEMENTING'"
}

@test "forge-state: VALIDATING + verdict_REVISE (retries < max) → PLANNING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition verdict_REVISE --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['new_state'] == 'PLANNING', d['new_state']
assert d['counters_changed']['validation_retries'] == 1
assert d['counters_changed']['total_retries'] == 1
"
}

@test "forge-state: IMPLEMENTING + implement_complete (at_least_one_passed) → VERIFYING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VERIFYING'"
}

@test "forge-state: VERIFYING + verify_pass (phase=correctness) → REVIEWING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['new_state'] == 'REVIEWING', d['new_state']
"

  # Verify convergence phase transitioned
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['phase'] == 'perfection', d['convergence']['phase']
assert d['convergence']['phase_iterations'] == 0
"
}

@test "forge-state: REVIEWING + score_target_reached → VERIFYING (safety_gate)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  # Fast-forward to REVIEWING with convergence.phase=perfection
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition score_target_reached --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VERIFYING'"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['phase'] == 'safety_gate', d['convergence']['phase']
"
}

@test "forge-state: VERIFYING + verify_pass (phase=safety_gate) → DOCUMENTING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VERIFYING'
d['convergence']['phase'] = 'safety_gate'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='DOCUMENTING'"
}

@test "forge-state: DOCUMENTING + docs_complete → SHIPPING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'DOCUMENTING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition docs_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='SHIPPING'"
}

@test "forge-state: SHIPPING + user_approve_pr → LEARNING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'SHIPPING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition user_approve_pr --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='LEARNING'"
}

@test "forge-state: LEARNING + retrospective_complete → COMPLETE" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'LEARNING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition retrospective_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['new_state'] == 'COMPLETE', d['new_state']
"
}

# ---------------------------------------------------------------------------
# 5. Counter management
# ---------------------------------------------------------------------------

@test "forge-state: phase_a_failure increments verify_fix_count + total_iterations + total_retries" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VERIFYING'
d['convergence']['phase'] = 'correctness'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition phase_a_failure \
    --guard "verify_fix_count=0" --guard "max_fix_loops=3" \
    --guard "total_iterations=0" --guard "max_iterations=8" \
    --forge-dir "$forge_dir"
  assert_success

  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
c = d['counters_changed']
assert c['verify_fix_count'] == 1, f'verify_fix_count: {c[\"verify_fix_count\"]}'
assert c['total_iterations'] == 1
assert c['total_retries'] == 1
"
}

@test "forge-state: score_improving resets plateau_count to 0" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['convergence']['plateau_count'] = 1
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition score_improving \
    --guard "total_iterations=2" --guard "max_iterations=8" \
    --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['plateau_count'] == 0
"
}

@test "forge-state: pr_rejected (implementation) resets quality_cycles + test_cycles" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'SHIPPING'
d['quality_cycles'] = 3
d['test_cycles'] = 2
d['total_retries'] = 5
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition pr_rejected --guard "feedback_classification=implementation" --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
assert d['total_retries'] == 6
assert d['story_state'] == 'IMPLEMENTING'
"
}

# ---------------------------------------------------------------------------
# 6. Error transitions
# ---------------------------------------------------------------------------

@test "forge-state: ANY + budget_exhausted → ESCALATED" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['total_retries'] = 10
d['total_retries_max'] = 10
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition budget_exhausted \
    --guard "total_retries=10" --guard "total_retries_max=10" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='ESCALATED'"
}

# ---------------------------------------------------------------------------
# 7. Invalid transitions
# ---------------------------------------------------------------------------

@test "forge-state: rejects PREFLIGHT + verify_pass (invalid event for state)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  run bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir"
  assert_failure
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'error' in d"
}

# ---------------------------------------------------------------------------
# 8. Reset command
# ---------------------------------------------------------------------------

@test "forge-state: reset implementation clears quality_cycles + test_cycles" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['quality_cycles'] = 3
d['test_cycles'] = 2
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" reset implementation --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
"
}

# ---------------------------------------------------------------------------
# 9. Decision logging
# ---------------------------------------------------------------------------

@test "forge-state: transitions append to decisions.jsonl" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null

  assert [ -f "$forge_dir/decisions.jsonl" ]
  local line_count
  line_count=$(wc -l < "$forge_dir/decisions.jsonl" | tr -d ' ')
  assert [ "$line_count" -ge 1 ]

  # Validate JSON format
  python3 -c "
import json
with open('$forge_dir/decisions.jsonl') as f:
    for line in f:
        line = line.strip()
        if line:
            d = json.loads(line)
            assert 'ts' in d, 'missing ts'
            assert 'decision' in d, 'missing decision'
            assert d['decision'] == 'state_transition', d['decision']
"
}

# ---------------------------------------------------------------------------
# 10. Diminishing returns (row 50)
# ---------------------------------------------------------------------------

@test "forge-state: score_diminishing (count >= 2) → VERIFYING (safety_gate)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['convergence']['diminishing_count'] = 2
d['score_history'] = [85, 86, 87]
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition score_diminishing \
    --guard "diminishing_count=2" --guard "score=87" --guard "pass_threshold=80" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VERIFYING'"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['phase'] == 'safety_gate'
"
}
TESTS
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/unit/forge-state.bats`
Expected: All tests FAIL (script does not exist yet)

- [ ] **Step 3: Implement forge-state.sh (this is the core deliverable — ~400 lines)**

The implementation is large. The script must:
1. Parse arguments (init/query/transition/reset + --guard + --forge-dir)
2. For `init`: create a full state.json v1.5.0 with all defaults using `forge-state-write.sh`
3. For `query`: read and output current state via `forge-state-write.sh read`
4. For `transition`: read state, look up `(current_state, event, guards)` in the encoded transition table, apply counter changes, write new state via `forge-state-write.sh write`, append to decisions.jsonl
5. For `reset`: read state, zero specified counter group, write back

The transition table is encoded as a Python data structure embedded in the bash script. Each row is a tuple of `(current_state, event, guard_fn, next_state, counter_changes, convergence_changes)`.

Create the script at `shared/forge-state.sh`. This script is ~400 lines (too large for inline plan code). The implementation MUST satisfy all tests in step 1 — the tests are the specification. The subagent implementing this task should:
1. Read `shared/state-transitions.md` for the complete transition table
2. Read `shared/forge-state-write.sh` to understand the write API
3. Implement the script following the interface and constraints below
4. Run the tests after each major section (init, query, transition, reset)

Key implementation constraints:
- Use `shared/forge-state-write.sh` for all reads/writes (never write state.json directly)
- Encode ALL 48 normal rows + 7 error rows + 1 dry-run row + 1 diminishing returns row (total: 57 transitions)
- Guard evaluation: compare provided `--guard` values against state.json values and transition table requirements
- Counter changes: increment/reset atomically within the Python embedded block
- Decision logging: append one JSON line per transition to `.forge/decisions.jsonl`

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/unit/forge-state.bats`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add shared/forge-state.sh tests/unit/forge-state.bats
git commit -m "feat: add forge-state.sh executable state machine with 57 transitions"
```

---

## Task 4: Scoring & Convergence Document Updates

**Files:**
- Modify: `shared/scoring.md`
- Modify: `shared/convergence-engine.md`
- Modify: `shared/state-transitions.md`
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Update scoring.md — change min_score default to 90**

In `shared/scoring.md`, find the shipping configuration section and change:

```
shipping:
  min_score: 100
```

to:

```
shipping:
  min_score: 90             # Default 90. Minimum score to create PR. Range: pass_threshold-100.
```

- [ ] **Step 2: Update convergence-engine.md — change target_score default to 90**

In `shared/convergence-engine.md`, find the configuration section and change:

```
  target_score: 100        # Score to aim for (convergence target)
```

to:

```
  target_score: 90         # Score to aim for (convergence target). Default 90.
```

- [ ] **Step 3: Add diminishing returns section to convergence-engine.md**

After the "Oscillation Detection" or plateau detection section in `shared/convergence-engine.md`, add:

```markdown
### Diminishing Returns Detection

After each convergence iteration in Phase 2 (perfection), check for diminishing returns:

1. Compute `gain = score_current - score_previous`
2. If `gain > 0 AND gain <= 2 AND score_current >= pass_threshold`:
   - This is a diminishing returns cycle — progress is real but minimal
   - Increment `convergence.diminishing_count` (default 0)
   - If `diminishing_count >= 2`: treat as PLATEAUED — apply score escalation ladder
   - Log: "Diminishing returns: gained {gain} points in last {diminishing_count} iterations"
3. If `gain > 2`: reset `diminishing_count = 0`

This prevents the pipeline from spending 3-4 iterations to squeeze out the last 2-3 INFO fixes
when the score is already above pass_threshold.

The `score_diminishing` event is Row 50 in the transition table (`shared/state-transitions.md`).
```

- [ ] **Step 4: Add row 50 to state-transitions.md**

In `shared/state-transitions.md`, after row 49 (LEARNING → COMPLETE), add:

```markdown
| 50 | `REVIEWING` | `score_diminishing` | `diminishing_count >= 2 AND score >= pass_threshold` | `VERIFYING` | Treat as plateau, transition convergence to "safety_gate", document unfixable findings |
```

- [ ] **Step 5: Update state-schema.md to v1.5.0**

In `shared/state-schema.md`:

1. Change `"version": "1.4.0"` to `"version": "1.5.0"` in the schema example
2. Add `"_seq": 1` field after `"version"`
3. Add `"diminishing_count": 0` inside the `convergence` object
4. Add `"unfixable_info_count": 0` inside the `convergence` object
5. Update the version field reference to mention v1.5.0 changes
6. Add field references for `_seq`, `diminishing_count`, `unfixable_info_count`

- [ ] **Step 6: Run existing tests to verify nothing broke**

Run: `./tests/run-all.sh`
Expected: All existing tests still PASS

- [ ] **Step 7: Commit**

```bash
git add shared/scoring.md shared/convergence-engine.md shared/state-transitions.md shared/state-schema.md
git commit -m "feat: soften scoring to min_score=90, add diminishing returns detection, bump state schema to v1.5.0"
```

---

## Task 5: Orchestrator Phase Split — Core File

**Files:**
- Create: `agents/fg-100-orchestrator-core.md`

This task creates the core file only. The full section-to-file mapping is defined in the spec (P0-3).

- [ ] **Step 1: Read the current orchestrator to extract sections for core**

Read `agents/fg-100-orchestrator.md` and extract these sections:
- §1 Identity & Purpose → core §1
- §21 Forbidden Actions → core §2 (MOVED TO FRONT)
- §18 Pipeline Principles → core §3 (MOVED TO FRONT)
- §14 Agent Dispatch Rules + §26 Task Blueprint → core §4 Dispatch Protocol
- §2 Argument Parsing → core §5
- §15 State Tracking → core §6 (rewritten for forge-state.sh usage)
- §13 Context Management + §16 Timeout + §19 Large Codebase + §25 Observability → core §7
- Phase Loading mechanism (NEW) → core §8
- §22 Autonomy + §24 Escalation → core §9
- Mode Resolution (NEW) → core §10
- §20 Worktree & Cross-Repo → core §10 (reference)
- §27 Reference Documents → core §11

- [ ] **Step 2: Create fg-100-orchestrator-core.md**

Create the file with frontmatter + all sections listed above. The file should be ~300 lines. Key changes from the original:
- Forbidden actions and principles are §2 and §3 (front-loaded)
- §6 State Management references `forge-state.sh` instead of manual JSON editing
- §8 Phase Loading describes how to load boot/execute/ship docs
- §10 Mode Resolution describes how to load `shared/modes/*.md` overlays
- All Linear tracking replaced with `forge-linear-sync.sh emit` pattern (placeholder until P1-4)

- [ ] **Step 3: Verify the core file has correct frontmatter**

The frontmatter must be:

```yaml
---
name: fg-100-orchestrator
description: |
  Autonomous pipeline orchestrator — coordinates the 10-stage development lifecycle.
  Reads forge.local.md for config. Dispatches fg-* agents per stage. Manages .forge/ state for recovery.

  <example>
  Context: Developer wants to implement a feature
  user: "Implement plan comment feature"
  assistant: "I'll dispatch the pipeline orchestrator to handle the full development lifecycle."
  </example>
model: inherit
color: cyan
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'TaskCreate', 'TaskUpdate', 'AskUserQuestion', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: false
---
```

Note: the `name` stays `fg-100-orchestrator` (not `fg-100-orchestrator-core`) because this is the file that gets loaded when the agent is dispatched. The other files are read by the orchestrator itself via the Read tool at phase boundaries.

- [ ] **Step 4: Commit**

```bash
git add agents/fg-100-orchestrator-core.md
git commit -m "feat: create orchestrator core file with front-loaded constraints"
```

---

## Task 6: Orchestrator Phase Split — Boot File

**Files:**
- Create: `agents/fg-100-orchestrator-boot.md`

- [ ] **Step 1: Extract PREFLIGHT sections from current orchestrator**

From `agents/fg-100-orchestrator.md`, extract §3 (PREFLIGHT) — all sub-sections §3.0 through §3.12. Renumber to §0.1 through §0.19 per the section-to-file mapping in the spec.

- [ ] **Step 2: Create fg-100-orchestrator-boot.md**

No frontmatter (this is a reference document, not an agent). Start with:

```markdown
# Pipeline Orchestrator — Boot Phase (PREFLIGHT)

> This document is loaded by the orchestrator at pipeline start.
> Follow the core document (`fg-100-orchestrator-core.md`) for principles and forbidden actions.
> After PREFLIGHT completes, load `fg-100-orchestrator-execute.md` for stages 1-6.
```

Then all PREFLIGHT sections renumbered §0.1-§0.19.

Key changes from original:
- All state writes use `forge-state.sh init` and `forge-state.sh transition preflight_complete`
- MCP detection (§23 → §0.18) moved here
- Graph context (from top of orchestrator → §0.19)

- [ ] **Step 3: Commit**

```bash
git add agents/fg-100-orchestrator-boot.md
git commit -m "feat: create orchestrator boot file (PREFLIGHT stage)"
```

---

## Task 7: Orchestrator Phase Split — Execute File

**Files:**
- Create: `agents/fg-100-orchestrator-execute.md`

- [ ] **Step 1: Extract stages 1-6 from current orchestrator**

From `agents/fg-100-orchestrator.md`, extract §4 (EXPLORE), §5 (PLAN), §6 (VALIDATE), §7 (IMPLEMENT), §8 (VERIFY), §9 (REVIEW). Renumber to §1.x through §6.x.

- [ ] **Step 2: Create fg-100-orchestrator-execute.md**

No frontmatter. Start with:

```markdown
# Pipeline Orchestrator — Execute Phase (Stages 1-6)

> This document is loaded after PREFLIGHT completes.
> Follow the core document (`fg-100-orchestrator-core.md`) for principles and forbidden actions.
> After REVIEW passes, load `fg-100-orchestrator-ship.md` for stages 7-9.
> On re-entry (PR rejection, evidence BLOCK), re-read this document.
```

Key changes from original:
- §5.1 VERIFY Phase A: "Dispatch `fg-505-build-verifier` if available, else inline build+lint with fix loop"
- §5.3 Convergence: Replaced ~150 lines of algorithm prose with "Call `forge-state.sh transition <event>` and follow returned action"
- §6.2 Score and Verdict: Uses `forge-state.sh transition score_improving|score_plateau|score_regressing|score_target_reached|score_diminishing`
- All `if mode == "bugfix"` branches replaced with "Check `state.json.mode_config.stages.{stage_name}` for overrides"
- All Linear blocks replaced with `forge-linear-sync.sh emit` calls

- [ ] **Step 3: Commit**

```bash
git add agents/fg-100-orchestrator-execute.md
git commit -m "feat: create orchestrator execute file (stages 1-6)"
```

---

## Task 8: Orchestrator Phase Split — Ship File

**Files:**
- Create: `agents/fg-100-orchestrator-ship.md`

- [ ] **Step 1: Extract stages 7-9 from current orchestrator**

From `agents/fg-100-orchestrator.md`, extract §10 (DOCS), §10.5 (Pre-Ship), §11 (SHIP), §12 (LEARN), §17 (Final Report). Renumber to §7.x through §9.x.

- [ ] **Step 2: Create fg-100-orchestrator-ship.md**

No frontmatter. Start with:

```markdown
# Pipeline Orchestrator — Ship Phase (Stages 7-9)

> This document is loaded after REVIEW passes (score accepted).
> Follow the core document (`fg-100-orchestrator-core.md`) for principles and forbidden actions.
```

Key changes: same pattern as execute file (forge-state.sh for transitions, mode overlays, Linear sync).

- [ ] **Step 3: Commit**

```bash
git add agents/fg-100-orchestrator-ship.md
git commit -m "feat: create orchestrator ship file (stages 7-9)"
```

---

## Task 9: Delete Old Orchestrator + Validate

**Files:**
- Delete: `agents/fg-100-orchestrator.md`
- Modify: `tests/validate-plugin.sh`

- [ ] **Step 1: Delete the old orchestrator file**

```bash
git rm agents/fg-100-orchestrator.md
```

- [ ] **Step 2: Add structural checks to validate-plugin.sh**

Add these checks to `tests/validate-plugin.sh`:

```bash
# --- Orchestrator split files ---
orch_split_fail=0
for f in fg-100-orchestrator-core.md fg-100-orchestrator-boot.md fg-100-orchestrator-execute.md fg-100-orchestrator-ship.md; do
  if [[ ! -f "$ROOT/agents/$f" ]]; then
    echo "    Missing: agents/$f"
    orch_split_fail=1
  fi
done
check "Orchestrator split files exist" "$orch_split_fail"

# Core file has frontmatter with name=fg-100-orchestrator
core_name_fail=0
if ! grep -q "^name: fg-100-orchestrator$" "$ROOT/agents/fg-100-orchestrator-core.md"; then
  core_name_fail=1
fi
check "Orchestrator core has correct name in frontmatter" "$core_name_fail"

# Old monolithic orchestrator does not exist
old_orch_fail=0
if [[ -f "$ROOT/agents/fg-100-orchestrator.md" ]]; then
  old_orch_fail=1
fi
check "Old monolithic orchestrator removed" "$old_orch_fail"

# New scripts exist and are executable
for script in forge-state.sh forge-state-write.sh check-prerequisites.sh; do
  script_fail=0
  if [[ ! -f "$ROOT/shared/$script" ]] || [[ ! -x "$ROOT/shared/$script" ]]; then
    script_fail=1
  fi
  check "shared/$script exists and is executable" "$script_fail"
done
```

- [ ] **Step 3: Run full test suite**

Run: `./tests/run-all.sh`
Expected: All tests PASS (including new structural checks)

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete monolithic orchestrator, add structural validation for split"
```

---

## Task 10: End-to-End Transition Scenarios

**Files:**
- Create: `tests/scenario/state-transitions.bats`

- [ ] **Step 1: Write scenario tests**

```bash
cat > tests/scenario/state-transitions.bats << 'TESTS'
#!/usr/bin/env bats
# Scenario tests: state machine end-to-end transition flows.
# Tests multi-step paths through forge-state.sh to verify the complete pipeline.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state.sh"

# ---------------------------------------------------------------------------
# 1. Happy path: PREFLIGHT → COMPLETE
# ---------------------------------------------------------------------------

@test "scenario: happy path transitions PREFLIGHT through COMPLETE" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition score_target_reached --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition docs_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition evidence_SHIP --guard "evidence_fresh=true" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition pr_created --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition user_approve_pr --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition retrospective_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='COMPLETE'"

  # Verify all counters are 0 (no retries in happy path)
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['total_retries'] == 0
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
assert d['verify_fix_count'] == 0
"
}

# ---------------------------------------------------------------------------
# 2. Convergence: correctness → perfection → safety_gate → DOCUMENTING
# ---------------------------------------------------------------------------

@test "scenario: convergence phases transition correctly" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  # Fast-forward to VERIFYING with correctness phase
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VERIFYING'
d['convergence']['phase'] = 'correctness'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  # correctness → perfection
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir" > /dev/null
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='perfection'"

  # perfection → safety_gate (via score_target_reached)
  bash "$SCRIPT" transition score_target_reached --forge-dir "$forge_dir" > /dev/null
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='safety_gate'"

  # safety_gate → DOCUMENTING (via verify_pass)
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$forge_dir" > /dev/null
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['story_state'] == 'DOCUMENTING'
assert d['convergence']['safety_gate_passed'] == True
"
}

# ---------------------------------------------------------------------------
# 3. Budget exhaustion stops the pipeline
# ---------------------------------------------------------------------------

@test "scenario: total_retries budget prevents infinite loops" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VERIFYING'
d['total_retries'] = 10
d['total_retries_max'] = 10
d['convergence']['phase'] = 'correctness'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition budget_exhausted \
    --guard "total_retries=10" --guard "total_retries_max=10" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='ESCALATED'"
}

# ---------------------------------------------------------------------------
# 4. Dry-run stops at VALIDATING
# ---------------------------------------------------------------------------

@test "scenario: dry-run stops at VALIDATING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --dry-run --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=true" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition validate_complete --guard "dry_run=true" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='COMPLETE'"
}

# ---------------------------------------------------------------------------
# 5. Diminishing returns stops early
# ---------------------------------------------------------------------------

@test "scenario: diminishing returns stops after 2 low-gain iterations" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['convergence']['diminishing_count'] = 2
d['score_history'] = [85, 86, 87]
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition score_diminishing \
    --guard "diminishing_count=2" --guard "score=87" --guard "pass_threshold=80" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VERIFYING'"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='safety_gate'"
}
TESTS
```

- [ ] **Step 2: Run scenario tests**

Run: `./tests/lib/bats-core/bin/bats tests/scenario/state-transitions.bats`
Expected: All tests PASS

- [ ] **Step 3: Run full test suite**

Run: `./tests/run-all.sh`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add tests/scenario/state-transitions.bats
git commit -m "test: add end-to-end state transition scenario tests"
```

---

## Execution Order Summary

| Task | Depends On | Deliverable |
|------|-----------|------------|
| 1 | — | `check-prerequisites.sh` |
| 2 | 1 | `forge-state-write.sh` + tests |
| 3 | 2 | `forge-state.sh` + tests |
| 4 | — | Scoring/convergence doc updates |
| 5 | 3, 4 | `fg-100-orchestrator-core.md` |
| 6 | 5 | `fg-100-orchestrator-boot.md` |
| 7 | 5 | `fg-100-orchestrator-execute.md` |
| 8 | 5 | `fg-100-orchestrator-ship.md` |
| 9 | 5, 6, 7, 8 | Delete old orchestrator + structural validation |
| 10 | 3 | Scenario tests |

Tasks 1-4 are independent (can parallelize 1→2→3 with 4).
Tasks 5-8 depend on 3+4 being complete.
Task 9 depends on 5-8.
Task 10 depends on 3 only (can run in parallel with 5-8).
