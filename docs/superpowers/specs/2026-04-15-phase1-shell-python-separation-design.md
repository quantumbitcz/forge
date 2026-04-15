# Phase 1: Shell/Python Separation

**Status:** Approved  
**Date:** 2026-04-15  
**Depends on:** Nothing (foundation layer)  
**Unlocks:** Phase 2, Phase 3

## Problem

`shared/forge-state.sh` contains ~425 lines of Python embedded as shell strings across 3 blocks:
- Lines 76-161: State initialization (`do_init()`)
- Lines 214-233: Guard JSON parser
- Lines 238-782: 57+9 row transition engine with counter/convergence logic

This creates:
- **Unmaintainability:** Changes require shell quoting discipline; no syntax checking until runtime
- **No IDE support:** Python embedded in bash strings gets no linting, no autocomplete, no type checking
- **Testing friction:** Cannot unit-test Python logic independently of shell wrapper

Additionally, `shared/forge-state-write.sh` hardcodes `python3` in 8 locations (lines 72, 105, 124, 135, 147, 184, 257, 290) with no fallback to `python` for systems where only `python` exists.

## Solution

### 1. Extract Python to standalone files

Create `shared/python/` directory with 3 files:

#### `shared/python/state_init.py`
- Extract from `forge-state.sh` lines 76-161
- **Interface:** `state_init.py <story_id> <requirement> <mode> <dry_run>`
- **Output:** JSON to stdout (complete v1.5.0 state object)
- **Exit codes:** 0 = success, 1 = invalid args, 2 = JSON serialization failure
- Add `if __name__ == '__main__':` guard with `sys.argv` parsing
- Add argument validation (story_id non-empty, mode in allowed set)

#### `shared/python/guard_parser.py`
- Extract from `forge-state.sh` lines 214-233
- **Interface:** `guard_parser.py key1=value1 key2=value2 ...`
- **Output:** JSON dict to stdout with type coercion (bool, int, float, string)
- **Exit codes:** 0 = success, 1 = malformed arg (no `=`)

#### `shared/python/state_transitions.py`
- Extract from `forge-state.sh` lines 238-722
- **Interface:** `state_transitions.py <event> <guards_json> <forge_dir>` — reads state JSON from **stdin** (avoids ARG_MAX for large states). Event, guards, and forge_dir are small strings passed as argv.
- **Exit codes:** 0 = transition matched and applied, 1 = no matching transition (error JSON to stderr — this is a valid runtime condition when an event is sent in a state that doesn't handle it; the caller should log and escalate)
- **Output:** JSON result to stdout containing:
  ```json
  {
    "new_state": "IMPLEMENTING",
    "row_id": "10",
    "description": "verdict_GO (risk <= auto_proceed)",
    "counters_changed": {},
    "updated_state": { ... }
  }
  ```
- **Exit codes:** 0 = transition found, 1 = no matching transition (error JSON to stderr)
- Contains: `match_transition()`, `risk_le()`, `g()` helper, full transition table, counter/convergence application logic
- The transition table itself is a Python list of tuples — fully lintable, testable

### 2. Modify `shared/forge-state.sh`

Replace embedded Python blocks with invocations:

```bash
# At top of file, after sourcing platform.sh:
PYTHON="${FORGE_PYTHON:-python3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# In do_init():
init_json=$("$PYTHON" "$SCRIPT_DIR/python/state_init.py" "$STORY_ID" "$REQUIREMENT" "$MODE" "$dry_run_val")

# In guard parsing:
guards_json=$("$PYTHON" "$SCRIPT_DIR/python/guard_parser.py" "${GUARDS[@]}")

# In transition execution:
result=$(printf '%s' "$current_state_json" | "$PYTHON" "$SCRIPT_DIR/python/state_transitions.py" "$EVENT" "$guards_json" "$FORGE_DIR")
```

Shell logic that wraps these calls (error handling, state writing) stays in bash.

### 3. Modify `shared/forge-state-write.sh`

Replace all 8 `python3` hardcodings:

```bash
# At top, after sourcing platform.sh:
PYTHON="${FORGE_PYTHON:-python3}"
```

Then replace every `python3 -c "..."` with `"$PYTHON" -c "..."` at lines 72, 105, 124, 135, 147, 184, 257, 290.

### 4. Ensure `FORGE_PYTHON` is exported in `shared/platform.sh`

Current `detect_python()` (lines 200-210) caches in `FORGE_PYTHON` but may not export it. Change to:
```bash
detect_python() {
  if command -v python3 &>/dev/null; then
    printf 'python3'
  elif command -v python &>/dev/null; then
    printf 'python'
  else
    printf ''
  fi
}
export FORGE_PYTHON="${FORGE_PYTHON:-$(detect_python)}"
```

All scripts that source `platform.sh` get `FORGE_PYTHON` automatically. Scripts that don't source `platform.sh` use `PYTHON="${FORGE_PYTHON:-python3}"` as a local fallback.

### 5. Scan for other `python3` hardcodings

Grep entire codebase for `python3` calls in `.sh` files. Any found must be converted to use `"$FORGE_PYTHON"` or `"$(detect_python)"`.

## Files Changed

| File | Action |
|------|--------|
| `shared/python/state_init.py` | **Create** — state initialization logic |
| `shared/python/state_transitions.py` | **Create** — transition table + engine |
| `shared/python/guard_parser.py` | **Create** — guard key=value to JSON |
| `shared/forge-state.sh` | **Modify** — replace 3 embedded Python blocks with invocations |
| `shared/forge-state-write.sh` | **Modify** — replace 8 `python3` with `"$PYTHON"` |
| `shared/platform.sh` | **Modify** — ensure `FORGE_PYTHON` is exported |

## Testing

- All existing tests in `tests/scenario/state-transitions-per-row.bats` (46 tests) must pass unchanged
- All existing tests in `tests/unit/forge-state.bats` (33 tests) must pass unchanged
- New tests:
  - `tests/unit/python-state-init.bats`: Verify `state_init.py` produces valid v1.5.0 JSON, handles missing args gracefully
  - `tests/unit/python-state-transitions.bats`: Verify `state_transitions.py` can be invoked standalone, returns valid JSON for a known transition, returns error for unknown transition
  - `tests/unit/python-guard-parser.bats`: Verify type coercion (bool, int, float, string)

## Risks

- **Shell argument passing:** State JSON can be large. Passing via command arg (`sys.argv[1]`) may hit ARG_MAX on very large states. Mitigation: `state_transitions.py` reads state JSON from stdin (not argv) to avoid ARG_MAX. Event and guards remain as argv (small strings). `state_init.py` and `guard_parser.py` use argv only (small inputs).
- **Python path resolution:** `$SCRIPT_DIR/python/` assumes scripts are invoked from a context where `BASH_SOURCE` resolves correctly. This is already the pattern used throughout forge.
- **No Python found:** If `detect_python()` returns empty (no python3 or python on PATH), `forge-state.sh` must fail with a clear error: `"ERROR: Python 3 is required. Install python3 and ensure it is on PATH."` and exit 2. This is a hard dependency — state management cannot function without Python.

## Success Criteria

1. `forge-state.sh` contains zero lines of embedded Python
2. `forge-state-write.sh` contains zero hardcoded `python3` references
3. All 79+ existing state tests pass
4. New Python files are independently executable and testable
5. `validate-plugin.sh` passes (structural checks)
