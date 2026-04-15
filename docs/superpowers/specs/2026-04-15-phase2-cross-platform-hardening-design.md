# Phase 2: Cross-Platform Hardening

**Status:** Approved  
**Date:** 2026-04-15  
**Depends on:** Phase 1 (`$FORGE_PYTHON` is exported by platform.sh after Phase 1)  
**Unlocks:** Phase 3

## Problem

1. **WSL misclassified:** `detect_os()` in `platform.sh` returns `"windows"` for WSL, causing `suggest_install()` to recommend `winget`/`choco` instead of `apt`/`dnf`. WSL is Linux with Windows interop — it should be its own category.

2. **Silent bash degradation:** On macOS with system bash 3.2, the check engine silently skips L1-L3 checks, logging only to `.forge/.hook-failures.log`. Users have no idea their checks are disabled.

3. **No timeout fallback:** All 5 hook scripts use `timeout`/`gtimeout` but if neither exists, hooks run without any time limit. On slow/broken checks, this can hang indefinitely.

4. **Temp cascade inconsistency:** `evals/pipeline/eval-runner.sh` uses `${TMPDIR:-/tmp}` instead of the portable `${TMPDIR:-${TMP:-${TEMP:-/tmp}}}` cascade.

## Solution

### 1. Fix `detect_os()` to return `wsl`

**File:** `shared/platform.sh` lines 8-36

Change both WSL detection branches (lines 13-14 and lines 25-26):
```bash
# Before:
printf 'windows'

# After:
printf 'wsl'
```

### 2. Update downstream `FORGE_OS` consumers

Grep for all `FORGE_OS` or `detect_os` usage. Categorize each:

**WSL should behave like Linux (package management, paths):**
- `suggest_install()` — WSL uses `apt`/`dnf`, not `winget`. Add `wsl)` case that falls through to `linux)`.
- `suggest_docker_start()` — WSL uses `sudo service docker start` or Docker Desktop WSL integration. Already has `is_wsl()` check; update to also match `FORGE_OS == "wsl"`.
- Path handling — WSL uses Unix paths natively; no MSYS translation needed.

**WSL should behave like Windows (Docker socket, some integrations):**
- Docker socket path may differ on WSL. The `is_wsl()` function already handles this — keep it.

**Pattern for downstream code:**
```bash
case "$FORGE_OS" in
  darwin)  ... ;;
  linux|wsl)  ... ;;  # WSL uses Linux tooling
  windows)  ... ;;     # Native Windows only (MSYS/Cygwin/MinGW)
  *)  ... ;;
esac
```

### 3. Surface bash version warning in `session-start.sh`

**File:** `hooks/session-start.sh`

After the forge project detection (line 23), add:
```bash
# --- Bash version check ---
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "WARNING: Bash ${BASH_VERSION} detected. Forge check engine L1-L3 disabled."
  case "$FORGE_OS" in
    darwin) echo "  Fix: brew install bash" ;;
    *)      echo "  Fix: Install bash 4.0+ via your package manager" ;;
  esac
fi
```

This outputs via the hook's stdout, which Claude Code surfaces to the user on session start. It fires once per session — not per edit.

### 4. Add sleep-based timeout fallback to all hooks

**Files:** All 5 hook scripts that use the self-enforcing timeout pattern:
- `hooks/automation-trigger-hook.sh`
- `hooks/feedback-capture.sh`
- `hooks/forge-checkpoint.sh`
- `hooks/session-start.sh`
- `shared/checks/engine.sh`

After the `gtimeout` elif block, add:
```bash
# Fallback: background watchdog kill
_SELF_PID=$$
( sleep "$_HOOK_TIMEOUT" && kill -TERM "$_SELF_PID" 2>/dev/null ) &
_WATCHDOG_PID=$!
trap "kill '$_WATCHDOG_PID' 2>/dev/null" EXIT
```

This starts a background process that kills the hook after the timeout. The `trap EXIT` ensures the watchdog is cleaned up when the hook exits normally (even if `_WATCHDOG_PID` is already dead — `kill` with `2>/dev/null` handles that). Uses `kill -TERM` (not `-9`) so cleanup traps in the hook can still fire. The `_HOOK_TIMEOUT` value comes from the existing per-hook `FORGE_HOOK_TIMEOUT` variable (already defined in each hook's header, e.g., `_HOOK_TIMEOUT="${FORGE_HOOK_TIMEOUT:-3}"` for session-start).

### 5. Fix eval-runner.sh temp cascade

**File:** `evals/pipeline/eval-runner.sh` line 255

```bash
# Before:
task_results_dir="$(mktemp -d "${TMPDIR:-/tmp}/forge-eval.XXXXXX")"

# After:
task_results_dir="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/forge-eval.XXXXXX")"
```

### 6. Audit all shell files for temp cascade

Run `grep -rn 'TMPDIR:-/tmp' --include='*.sh'` across the entire codebase. Fix every occurrence to use the full cascade `${TMPDIR:-${TMP:-${TEMP:-/tmp}}}`. Document the audit results in the PR.

## Files Changed

| File | Action |
|------|--------|
| `shared/platform.sh` | **Modify** — `detect_os()` returns `wsl`; update `suggest_install()` and related functions |
| `hooks/session-start.sh` | **Modify** — add bash version warning block |
| `hooks/automation-trigger-hook.sh` | **Modify** — add sleep-based timeout fallback |
| `hooks/feedback-capture.sh` | **Modify** — add sleep-based timeout fallback |
| `hooks/forge-checkpoint.sh` | **Modify** — add sleep-based timeout fallback |
| `shared/checks/engine.sh` | **Modify** — add sleep-based timeout fallback |
| `evals/pipeline/eval-runner.sh` | **Modify** — fix temp cascade |

## Testing

- `tests/structural/platform-portability.bats` (14 tests) — must still pass; may need update if any test checks for `detect_os` returning `"windows"` on WSL
- New test in `tests/unit/platform-wsl.bats`:
  - Mock `/proc/version` containing "Microsoft" → verify `detect_os` returns `wsl`
  - Verify `suggest_install` returns `apt` for `wsl` platform
- New test in `tests/hooks/session-start-bash-warning.bats`:
  - Mock `BASH_VERSINFO[0]=3` → verify warning output contains "Bash" and "L1-L3 disabled"
  - Mock `BASH_VERSINFO[0]=5` → verify no warning
- Existing `tests/hooks/` suite must pass unchanged

## Risks

- **WSL string change ripple:** Any script that checks `FORGE_OS == "windows"` expecting WSL will break. Mitigation: exhaustive grep before change; test on actual WSL if available.
- **Watchdog PID leak:** If the hook is killed externally (not via normal exit), the watchdog process may outlive it. The `sleep + kill` combo is lightweight (sleep exits after timeout regardless), so the leak is bounded to `$_HOOK_TIMEOUT` seconds max.

## Success Criteria

1. `detect_os()` returns `wsl` on WSL systems, `windows` only for native MSYS/Cygwin/MinGW
2. Users see bash version warning on session start if bash < 4
3. All hooks have a timeout mechanism even without `timeout`/`gtimeout` commands
4. No `${TMPDIR:-/tmp}` patterns remain (all use full cascade)
5. All existing tests pass; new platform tests added
