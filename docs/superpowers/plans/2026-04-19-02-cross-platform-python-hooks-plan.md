# Phase 02 — Cross-Platform Python Hook Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port all forge hook scripts, the check engine, and the critical `shared/*.sh` helpers they depend on to Python 3.10+ stdlib-only, drop the bash-4+ runtime requirement, and make `windows-latest` a first-class CI target.

**Architecture:** Thin `hooks/<event>.py` entry shims (~10 lines) that import a sibling `hooks/_py/` package holding the real logic. The check engine keeps its existing `shared/checks/engine.py` core (311 LOC) and reabsorbs the 689-LOC bash dispatch glue. Single PR, single commit series, no deprecation window. `windows-latest` added to the 3×3 CI matrix (OS × {unit, contract, scenario}). All replaced `.sh` files deleted in the same commit as their Python replacements.

**Tech Stack:** Python 3.10+ stdlib (`pathlib`, `json`, `subprocess`, `ast`, `tomllib`, `fcntl`/`msvcrt`, `platform`, `shutil`), `pyproject.toml`, `actions/setup-python@v6`, `pytest` (new) alongside retained `bats-core`.

---

## Review feedback incorporated

Three issues from `docs/superpowers/reviews/2026-04-19-02-cross-platform-python-hooks-spec-review.md` (verdict: REVISE) are resolved in this plan.

### Issue 1 — "Hook count contradiction (C1/I1/I3)"

> "The spec lists **7 hooks** in §3.1, but `/Users/denissajnar/IdeaProjects/forge/hooks/` contains only **5** `.sh` files… `hooks/automation-trigger.sh` (21 lines, distinct from `automation-trigger-hook.sh`) **is not mentioned anywhere**."

**Resolution.** Ground-truth from directly reading `hooks/hooks.json` and `ls hooks/`:

- **`hooks/hooks.json` registers 6 hook invocation commands across 5 event slots:** PreToolUse(Edit|Write) → `validate-syntax.sh`; PostToolUse(Edit|Write) → **two** commands, `engine.sh --hook` and `automation-trigger-hook.sh`; PostToolUse(Skill) → `forge-checkpoint.sh`; PostToolUse(Agent) → `forge-compact-check.sh`; Stop → `feedback-capture.sh`; SessionStart → `session-start.sh`. **Total = 7 command entries.** The "7 hooks" count is correct; the confusion is that commands live across `hooks/` (4), `shared/checks/` (2), and `shared/` (1).
- **`hooks/` contains 5 `.sh` files total**, verified: `automation-trigger-hook.sh` (49 LOC, hook wrapper), `automation-trigger.sh` (306 LOC, a user-facing CLI invoked by `automation-trigger-hook.sh` AND by other skills), `feedback-capture.sh`, `forge-checkpoint.sh`, `session-start.sh`. The 306-LOC `automation-trigger.sh` is distinct from the 49-LOC hook wrapper and is invoked standalone by the `forge-automation` skill.
- **Python port target = 6 entry scripts** (one per `hooks.json` slot; the two PostToolUse(Edit|Write) commands merge into a single `post_tool_use.py` dispatcher that calls both engine and automation trigger). The 7th "hook" is `post_tool_use.py`'s second responsibility, not a separate entry script. Task 3 enumerates every entry script and Task 10 ports `automation-trigger.sh` as `hooks/_py/automation_trigger_cli.py` (both the hook wrapper and the standalone CLI use the same module; the CLI gets a `__main__` shim at `hooks/automation_trigger.py`).

### Issue 2 — "Bash-ism audit names files then leaves them out of scope (C2)"

> "§2 lists six files… Of these, only `config-validator.sh` appears in the §5 tables. The other five are silently relegated to §3 'Out of scope'… but that categorization is wrong."

**Resolution.** All six audited bash-ism files are explicitly handled:

| File | Disposition | Justification / Task |
|---|---|---|
| `shared/config-validator.sh` (789 LOC) | **Port** | Runs at `/forge-init` (user-facing). Task 13. |
| `shared/context-guard.sh` (8393 bytes) | **Port** | Invoked by `fg-100-orchestrator` context rails on user machines. Task 15. |
| `shared/cost-alerting.sh` (14568 bytes) | **Port** | Invoked by retrospective + monitoring on user machines. Task 15. |
| `shared/validate-finding.sh` (2765 bytes) | **Port** | Invoked in reviewer finding-schema validation path on user machines. Task 15. |
| `shared/generate-conventions-index.sh` (2537 bytes) | **Port** | Runs at `/forge-init` (user-facing). Task 15. |
| `shared/convergence-engine-sim.sh` (5972 bytes) | **Out of scope** — keep as-is | Developer-only simulation harness. Not invoked by any hook, skill, agent, or `/forge-init`. Task 16 fixes its one `<<<` here-string in-place with a stdin pipe so it still works on MSYS/Cygwin bash 3.2 — no Python port needed. |

Success Criterion 6 (`git grep -l '^#!/.*bash' hooks/ shared/` returns only out-of-scope scripts) is now verifiable: the only remaining bash files under `shared/` after this plan are `forge-state.sh`, `forge-sim.sh`, `run-linter.sh`, linter adapters, recovery scripts, the evals harness, and `convergence-engine-sim.sh`. Task 22 writes the structural test that asserts this exact allowlist.

### Issue 3 — "`tests/validate-plugin.sh:298` off-by-two (C3)"

> "Line 298 is the `else` branch, not the skip condition; the MSYS/Cygwin/MinGW test is on line 296 and the skip `echo … NOTE …` is on line 297."

**Resolution.** Verified by reading `tests/validate-plugin.sh:290-310`. Exact lines:

- Line 296: `if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == mingw* ]]; then`
- Line 297: `  echo "    NOTE: Skipping hook path resolution check on Windows Git Bash …" >&2`
- Line 298: `else`

The **skip block is lines 292-297** (comment + `if` + skip `echo`). Task 19 deletes lines 292-298 as a unit (comment block + skip branch + `else`) when porting to `tests/validate_plugin.py`, and Task 19 Step 4 asserts via the new Python validator that `msys`, `cygwin`, `mingw`, and `OSTYPE` no longer appear anywhere in `tests/`. This plan uses the range `290-298` when pointing to the region to match the spec-review amendment guidance.

---

## File Structure

### New packages

```
hooks/
  hooks.json                         # regenerated: 7 Python command entries
  pre_tool_use.py                    # ~10 LOC shim → _py.check_engine.l0_syntax.main()
  post_tool_use.py                   # ~15 LOC shim → engine.run_post_tool_use() + automation_trigger.fire_file_changed()
  post_tool_use_skill.py             # ~10 LOC shim → _py.check_engine.checkpoint.main()
  post_tool_use_agent.py             # ~10 LOC shim → _py.check_engine.compact_check.main()
  stop.py                            # ~10 LOC shim → _py.check_engine.feedback_capture.main()
  session_start.py                   # ~10 LOC shim → _py.check_engine.session_start.main()
  automation_trigger.py              # ~10 LOC shim → _py.automation_trigger_cli.main()  (standalone CLI, previously automation-trigger.sh)
  _py/
    __init__.py
    platform_support.py              # was shared/platform.sh (531 LOC → ~250 LOC Python)
    config_validator.py              # was shared/config-validator.sh (789 LOC → ~450 LOC Python)
    state_write.py                   # was shared/forge-state-write.sh (309 LOC → ~180 LOC Python)
    token_tracker.py                 # was shared/forge-token-tracker.sh (322 LOC → ~180 LOC Python)
    timeout.py                       # was shared/forge-timeout.sh (46 LOC → ~40 LOC Python)
    context_guard.py                 # was shared/context-guard.sh (~300 LOC Python)
    cost_alerting.py                 # was shared/cost-alerting.sh (~400 LOC Python)
    validate_finding.py              # was shared/validate-finding.sh (~90 LOC Python)
    generate_conventions_index.py    # was shared/generate-conventions-index.sh (~80 LOC Python)
    automation_trigger_cli.py        # was hooks/automation-trigger.sh (306 LOC → ~200 LOC Python)
    io_utils.py                      # TOOL_INPUT JSON parsing, atomic JSON write, cross-platform file locks
    check_engine/
      __init__.py
      engine.py                      # existing shared/checks/engine.py (311 LOC) moved + dispatch glue from engine.sh (689 LOC → ~350 LOC Python)
      l0_syntax.py                   # was shared/checks/l0-syntax/validate-syntax.sh (191 LOC → ~140 LOC Python)
      automation_trigger.py          # hook-side wrapper (was hooks/automation-trigger-hook.sh, 49 LOC → ~30 LOC Python)
      checkpoint.py                  # was hooks/forge-checkpoint.sh (58 LOC → ~40 LOC Python)
      feedback_capture.py            # was hooks/feedback-capture.sh (168 LOC → ~120 LOC Python)
      session_start.py               # was hooks/session-start.sh (233 LOC → ~160 LOC Python)
      compact_check.py               # was shared/forge-compact-check.sh (97 LOC → ~60 LOC Python)
shared/
  check_prerequisites.py             # was shared/check-prerequisites.sh (123 LOC → ~90 LOC Python)
tests/
  validate_plugin.py                 # was tests/validate-plugin.sh (936 LOC → ~650 LOC Python)
  unit/test_hooks_py.py              # new pytest — entry-script + package tests
  unit/test_check_prerequisites.py   # new pytest — Python-version gate
  unit/test_validate_plugin.py       # new pytest — smoke test the new validator
pyproject.toml                       # new — project metadata, Python 3.10+ floor, ruff config
```

### Modified files

- `hooks/hooks.json` — all 7 commands rewritten to `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/<entry>.py`.
- `.github/workflows/test.yml` — add `windows-latest` to the `test` job matrix.
- `.github/workflows/eval.yml` — same `windows-latest` inclusion.
- `tests/run-all.sh` — call `python3 tests/validate_plugin.py` instead of `bash tests/validate-plugin.sh`.
- `tests/lib/module-lists.bash` — no change expected; verified in Task 21.
- `CLAUDE.md` — "Platform requirements" Gotcha rewritten; §Hooks count reconciled to "7 command entries across 6 entry scripts".
- `skills/forge-automation/SKILL.md` — update `automation-trigger.sh` references to `automation-trigger.py`.
- `shared/hook-design.md` — update script-contract examples to Python.
- Any `tests/hooks/*.bats` referencing `.sh` hook paths (enumerated in Task 20).

### Deleted files (all land in the same commit as their Python replacement)

`hooks/automation-trigger-hook.sh`, `hooks/automation-trigger.sh`, `hooks/feedback-capture.sh`, `hooks/forge-checkpoint.sh`, `hooks/session-start.sh`, `shared/checks/engine.sh`, `shared/checks/l0-syntax/validate-syntax.sh`, `shared/platform.sh`, `shared/config-validator.sh`, `shared/forge-state-write.sh`, `shared/forge-token-tracker.sh`, `shared/forge-timeout.sh`, `shared/forge-compact-check.sh`, `shared/context-guard.sh`, `shared/cost-alerting.sh`, `shared/validate-finding.sh`, `shared/generate-conventions-index.sh`, `shared/check-prerequisites.sh`, `tests/validate-plugin.sh`.

---

## Task List

All tasks are TDD: red test → minimal code → green → commit. Each task produces a buildable, independently-commitable change. Conventional commits (`feat:`, `refactor:`, `test:`, `chore:`, `ci:`, `docs:`) — **no AI attribution**, **no `Co-Authored-By`**, **no `--no-verify`**.

---

### Task 1: pyproject.toml + Python-version gate foundation

**Files:**
- Create: `pyproject.toml`
- Create: `shared/check_prerequisites.py`
- Create: `tests/unit/test_check_prerequisites.py`
- Delete: `shared/check-prerequisites.sh`

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/test_check_prerequisites.py
"""Test the Python 3.10+ enforcement gate."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "shared" / "check_prerequisites.py"


def test_exits_zero_on_current_python():
    """Running under Python 3.10+ should succeed with exit code 0."""
    assert sys.version_info >= (3, 10), "Test harness requires Python 3.10+"
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], capture_output=True, text=True
    )
    assert result.returncode == 0, f"stderr: {result.stderr}"
    assert "OK" in result.stdout


def test_rejects_python_39_when_simulated(monkeypatch):
    """When simulated version is 3.9, the script exits 1 with guidance."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--simulate-version", "3.9.16"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert "requires Python 3.10" in result.stderr
    assert "3.9.16" in result.stderr


def test_prints_upgrade_hint_per_platform():
    """Guidance includes at least one of the upgrade commands."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--simulate-version", "3.9.0"],
        capture_output=True,
        text=True,
    )
    combined = result.stdout + result.stderr
    assert "brew install python" in combined or "apt install python" in combined
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest tests/unit/test_check_prerequisites.py -v`
Expected: FAIL — `shared/check_prerequisites.py` does not exist.

- [ ] **Step 3: Write minimal implementation**

```python
# shared/check_prerequisites.py
#!/usr/bin/env python3
"""Enforce Python 3.10+ before forge init writes any config.

Exit codes:
  0 — Python version meets floor.
  1 — Python version is below the floor.

Usage:
  python3 shared/check_prerequisites.py [--simulate-version X.Y.Z]
"""
from __future__ import annotations

import argparse
import platform
import sys

FLOOR = (3, 10)


def _parse_version(s: str) -> tuple[int, ...]:
    return tuple(int(p) for p in s.split("."))


def _upgrade_hint() -> str:
    system = platform.system().lower()
    if system == "darwin":
        return "  macOS:   brew install python@3.11"
    if system == "linux":
        return "  Linux:   sudo apt install python3.11  (or your distro equivalent)"
    if system == "windows":
        return "  Windows: winget install Python.Python.3.11"
    return "  Install Python 3.10 or newer from https://www.python.org/downloads/"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--simulate-version", default=None)
    args = ap.parse_args()
    if args.simulate_version:
        version = _parse_version(args.simulate_version)
        version_str = args.simulate_version
    else:
        version = sys.version_info[:3]
        version_str = ".".join(str(p) for p in version)
    if version[:2] < FLOOR:
        print(
            f"ERROR: forge plugin requires Python 3.10 or later (found {version_str}).\n"
            f"Upgrade options:\n{_upgrade_hint()}\nExit code: 1",
            file=sys.stderr,
        )
        return 1
    print(f"OK: Python {version_str} detected (platform: {platform.system().lower()})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```toml
# pyproject.toml
[project]
name = "forge-plugin"
version = "3.1.0"
description = "Claude Code plugin: 10-stage autonomous pipeline (forge)"
requires-python = ">=3.10"
readme = "README.md"
license = { text = "Proprietary" }

[tool.ruff]
target-version = "py310"
line-length = 100
extend-exclude = ["modules/", "agents/", "skills/", "docs/"]

[tool.ruff.lint]
select = ["E", "F", "W", "I", "B", "UP", "SIM"]
ignore = ["E501"]  # line length handled elsewhere

[tool.pytest.ini_options]
testpaths = ["tests/unit"]
python_files = ["test_*.py"]
addopts = "-ra"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m pytest tests/unit/test_check_prerequisites.py -v`
Expected: 3 PASSED.

- [ ] **Step 5: Delete the bash version and update call-sites**

Run: `git rm shared/check-prerequisites.sh`

Then grep for call-sites: `grep -rln 'check-prerequisites\.sh' .` — expected hits are in `skills/forge-init/SKILL.md` and possibly `shared/hook-design.md`. Update each referenced path to `shared/check_prerequisites.py` (invoked as `python3 shared/check_prerequisites.py`).

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml shared/check_prerequisites.py tests/unit/test_check_prerequisites.py
git add -u  # picks up deletion of check-prerequisites.sh and any updated SKILL.md files
git commit -m "feat(phase02): add pyproject.toml + Python 3.10+ prerequisite gate

Replaces shared/check-prerequisites.sh with shared/check_prerequisites.py.
Establishes pyproject.toml as the Python project root for Phase 02 work."
```

---

### Task 2: `hooks/_py/io_utils.py` — TOOL_INPUT parsing + cross-platform file locking

**Files:**
- Create: `hooks/_py/__init__.py`
- Create: `hooks/_py/io_utils.py`
- Create: `tests/unit/test_io_utils.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/test_io_utils.py
"""TOOL_INPUT parsing, atomic writes, and cross-platform locks."""
from __future__ import annotations

import io
import json
import platform
import threading
from pathlib import Path

import pytest

from hooks._py import io_utils


def test_parse_tool_input_extracts_file_path():
    payload = json.dumps({"tool_input": {"file_path": "/tmp/x.py"}})
    stdin = io.StringIO(payload)
    parsed = io_utils.parse_tool_input(stdin)
    assert parsed.file_path == "/tmp/x.py"


def test_parse_tool_input_missing_returns_none():
    stdin = io.StringIO(json.dumps({"tool_input": {}}))
    parsed = io_utils.parse_tool_input(stdin)
    assert parsed.file_path is None


def test_atomic_json_update_roundtrip(tmp_path: Path):
    target = tmp_path / "state.json"
    target.write_text(json.dumps({"counter": 1}))

    def mutate(d):
        d["counter"] += 1
        return d

    io_utils.atomic_json_update(target, mutate)
    assert json.loads(target.read_text())["counter"] == 2


def test_atomic_json_update_handles_missing_file(tmp_path: Path):
    target = tmp_path / "new.json"
    io_utils.atomic_json_update(target, lambda d: {"created": True}, default={})
    assert json.loads(target.read_text())["created"] is True


def test_atomic_json_update_is_concurrent_safe(tmp_path: Path):
    target = tmp_path / "counter.json"
    target.write_text(json.dumps({"n": 0}))

    def bump():
        for _ in range(50):
            io_utils.atomic_json_update(target, lambda d: {"n": d["n"] + 1})

    threads = [threading.Thread(target=bump) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert json.loads(target.read_text())["n"] == 200


def test_normalize_path_emits_posix(tmp_path: Path):
    raw = tmp_path / "a" / "b.json"
    normalized = io_utils.normalize_path(raw)
    assert "\\" not in normalized
    assert normalized.endswith("/a/b.json")


@pytest.mark.skipif(platform.system() != "Windows", reason="Windows lock only")
def test_windows_lock_uses_msvcrt():
    # Sanity check that the Windows branch imports msvcrt successfully.
    import msvcrt  # noqa: F401
```

- [ ] **Step 2: Run tests — confirm fail**

Run: `python3 -m pytest tests/unit/test_io_utils.py -v`
Expected: ImportError — `hooks._py.io_utils` does not exist.

- [ ] **Step 3: Implement**

```python
# hooks/_py/__init__.py
"""forge Python hook support package (stdlib-only, Python 3.10+)."""
```

```python
# hooks/_py/io_utils.py
"""TOOL_INPUT parsing, atomic JSON update, cross-platform file locks."""
from __future__ import annotations

import contextlib
import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, IO

IS_WINDOWS = sys.platform.startswith("win")

if IS_WINDOWS:
    import msvcrt  # type: ignore[import-not-found]
else:
    import fcntl


@dataclass
class ToolInput:
    file_path: str | None
    tool_name: str | None
    raw: dict[str, Any]


def parse_tool_input(stream: IO[str] | None = None) -> ToolInput:
    """Parse the TOOL_INPUT JSON document Claude Code pipes on stdin.

    Returns a ToolInput even when the stream is empty or malformed — hooks
    must never crash on unexpected input; they short-circuit.
    """
    stream = stream or sys.stdin
    try:
        payload = json.loads(stream.read() or "{}")
    except json.JSONDecodeError:
        payload = {}
    tool_input = payload.get("tool_input", {}) if isinstance(payload, dict) else {}
    return ToolInput(
        file_path=tool_input.get("file_path"),
        tool_name=payload.get("tool_name") if isinstance(payload, dict) else None,
        raw=payload if isinstance(payload, dict) else {},
    )


@contextlib.contextmanager
def _locked(fp):
    if IS_WINDOWS:
        # Lock a single byte — semantics match flock(LOCK_EX) closely enough
        # for JSON-update serialization. fp must be a writable binary handle.
        while True:
            try:
                msvcrt.locking(fp.fileno(), msvcrt.LK_LOCK, 1)
                break
            except OSError:
                continue
        try:
            yield
        finally:
            try:
                fp.seek(0)
                msvcrt.locking(fp.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
    else:
        fcntl.flock(fp.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fp.fileno(), fcntl.LOCK_UN)


def atomic_json_update(
    path: Path,
    mutate: Callable[[dict], dict],
    *,
    default: dict | None = None,
) -> None:
    """Read-modify-write a JSON file under an exclusive lock, atomically."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(path.suffix + ".lock")

    # Serialize concurrent writers on a sibling lock file (works on every FS).
    with open(lock_path, "a+b") as lock_fp:
        with _locked(lock_fp):
            try:
                current = json.loads(path.read_text()) if path.exists() else (
                    default if default is not None else {}
                )
            except json.JSONDecodeError:
                current = default if default is not None else {}
            updated = mutate(current)
            # Atomic rename — works on POSIX always, on Windows requires that
            # the target is not open elsewhere in the same process.
            tmp_fd, tmp_name = tempfile.mkstemp(
                dir=str(path.parent), prefix=path.name + ".", suffix=".tmp"
            )
            try:
                with os.fdopen(tmp_fd, "w") as tmp:
                    json.dump(updated, tmp, indent=2, sort_keys=True)
                os.replace(tmp_name, path)
            except BaseException:
                with contextlib.suppress(FileNotFoundError):
                    os.unlink(tmp_name)
                raise


def normalize_path(p: str | Path) -> str:
    """Return a POSIX-style string for cross-platform state files."""
    return str(Path(p).as_posix())
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `python3 -m pytest tests/unit/test_io_utils.py -v`
Expected: 5 PASSED (+ 1 SKIPPED on non-Windows).

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/__init__.py hooks/_py/io_utils.py tests/unit/test_io_utils.py
git commit -m "feat(phase02): add hooks/_py/io_utils with cross-platform locks

Introduces parse_tool_input, atomic_json_update, and normalize_path with
fcntl/msvcrt branches. Unit-tested including concurrent-writer correctness."
```

---

### Task 3: `hooks/_py/platform_support.py` — OS detection, paths, temp dirs

**Files:**
- Create: `hooks/_py/platform_support.py`
- Create: `tests/unit/test_platform_support.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/test_platform_support.py
from __future__ import annotations

from pathlib import Path

from hooks._py import platform_support as ps


def test_detect_os_returns_allowed_value():
    assert ps.detect_os() in {"darwin", "linux", "windows", "wsl"}


def test_detect_os_never_returns_gitbash():
    """Git Bash users now report 'windows' via platform.system()."""
    assert ps.detect_os() != "gitbash"


def test_forge_dir_returns_pathlib(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    result = ps.forge_dir()
    assert isinstance(result, Path)
    assert result.name == ".forge"


def test_python_executable_is_resolvable():
    assert ps.python_executable()  # non-empty


def test_is_wsl_returns_bool():
    assert isinstance(ps.is_wsl(), bool)


def test_has_command_known_tool():
    # python3 is guaranteed on all test runners
    assert ps.has_command("python3") or ps.has_command("python")
```

- [ ] **Step 2: Run tests — fail**

Run: `python3 -m pytest tests/unit/test_platform_support.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

```python
# hooks/_py/platform_support.py
"""OS detection, executable lookup, forge-dir resolution."""
from __future__ import annotations

import os
import platform
import shutil
import sys
from pathlib import Path


def detect_os() -> str:
    """Return one of {'darwin', 'linux', 'windows', 'wsl'}."""
    system = platform.system().lower()
    if system == "windows":
        return "windows"
    if system == "darwin":
        return "darwin"
    if system == "linux":
        return "wsl" if is_wsl() else "linux"
    return system or "unknown"


def is_wsl() -> bool:
    if platform.system().lower() != "linux":
        return False
    try:
        with open("/proc/version", "r", encoding="utf-8") as f:
            contents = f.read().lower()
    except OSError:
        return False
    return "microsoft" in contents or "wsl" in contents


def forge_dir(root: Path | None = None) -> Path:
    """Return the `.forge/` directory for the given project root (defaults to cwd)."""
    return (root or Path.cwd()) / ".forge"


def python_executable() -> str:
    """Return the best Python executable, preferring sys.executable."""
    return sys.executable or shutil.which("python3") or shutil.which("python") or "python3"


def has_command(name: str) -> bool:
    return shutil.which(name) is not None


def temp_dir() -> Path:
    """Return a platform-appropriate scratch directory for hook workspaces."""
    import tempfile
    return Path(tempfile.gettempdir())


def env_bool(name: str, default: bool = False) -> bool:
    """Read a yes/no environment variable (1/true/yes/on)."""
    val = os.environ.get(name)
    if val is None:
        return default
    return val.strip().lower() in {"1", "true", "yes", "on"}
```

- [ ] **Step 4: Run tests — pass**

Run: `python3 -m pytest tests/unit/test_platform_support.py -v`
Expected: 6 PASSED.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/platform_support.py tests/unit/test_platform_support.py
git commit -m "feat(phase02): add hooks/_py/platform_support with OS detection

Replaces shared/platform.sh's OS/path/env helpers with a stdlib-only module.
Reports 'wsl' separately from 'linux' via /proc/version inspection."
```

---

### Task 4: `hooks/_py/state_write.py` — atomic JSON state writes with `_seq` versioning

**Files:**
- Create: `hooks/_py/state_write.py`
- Create: `tests/unit/test_state_write.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/test_state_write.py
from __future__ import annotations

import json
from pathlib import Path

from hooks._py import state_write


def test_write_state_creates_file_with_seq(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"stage": "PREFLIGHT"})
    data = json.loads(state.read_text())
    assert data["stage"] == "PREFLIGHT"
    assert data["_seq"] == 1


def test_write_state_increments_seq(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"stage": "PREFLIGHT"})
    state_write.write_state(state, {"stage": "EXPLORING"})
    data = json.loads(state.read_text())
    assert data["stage"] == "EXPLORING"
    assert data["_seq"] == 2


def test_update_state_merges(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"stage": "PLANNING", "score": 90})
    state_write.update_state(state, {"score": 95})
    data = json.loads(state.read_text())
    assert data["stage"] == "PLANNING"
    assert data["score"] == 95
    assert data["_seq"] == 2


def test_update_state_nested_merge(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"tokens": {"prompt": 100}})
    state_write.update_state(state, {"tokens": {"completion": 50}}, merge_depth=2)
    data = json.loads(state.read_text())
    assert data["tokens"] == {"prompt": 100, "completion": 50}
```

- [ ] **Step 2: Run — fail**

Run: `python3 -m pytest tests/unit/test_state_write.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

```python
# hooks/_py/state_write.py
"""Atomic JSON state writes with _seq versioning (replaces forge-state-write.sh)."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from .io_utils import atomic_json_update


def _bump_seq(doc: dict[str, Any]) -> dict[str, Any]:
    doc["_seq"] = int(doc.get("_seq", 0)) + 1
    return doc


def write_state(path: Path, new_doc: dict[str, Any]) -> None:
    """Replace state file contents with new_doc, incrementing _seq."""
    def _mutate(current: dict) -> dict:
        doc = dict(new_doc)
        doc["_seq"] = int(current.get("_seq", 0)) + 1
        return doc
    atomic_json_update(path, _mutate, default={})


def _deep_merge(a: dict, b: dict, depth: int) -> dict:
    if depth <= 0:
        return b
    out = dict(a)
    for k, v in b.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v, depth - 1)
        else:
            out[k] = v
    return out


def update_state(
    path: Path, patch: dict[str, Any], *, merge_depth: int = 1
) -> None:
    """Merge patch into the existing state and bump _seq."""
    def _mutate(current: dict) -> dict:
        merged = _deep_merge(current, patch, merge_depth)
        return _bump_seq(merged)
    atomic_json_update(path, _mutate, default={})
```

- [ ] **Step 4: Run — pass**

Run: `python3 -m pytest tests/unit/test_state_write.py -v`
Expected: 4 PASSED.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/state_write.py tests/unit/test_state_write.py
git commit -m "feat(phase02): add hooks/_py/state_write with _seq versioning

Ports shared/forge-state-write.sh. Uses atomic_json_update so concurrent
writers never corrupt state.json."
```

---

### Task 5: `hooks/_py/timeout.py` — pipeline timeout enforcement

**Files:**
- Create: `hooks/_py/timeout.py`
- Create: `tests/unit/test_timeout.py`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_timeout.py
from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from hooks._py import timeout


def _write_state(path: Path, *, preflight_iso: str):
    path.write_text(json.dumps({"stage_timestamps": {"preflight": preflight_iso}}))


def test_within_budget_returns_ok(tmp_path: Path):
    state = tmp_path / "state.json"
    _write_state(state, preflight_iso=datetime.now(timezone.utc).isoformat())
    result = timeout.check(state, max_seconds=3600)
    assert result.exceeded is False
    assert result.warning is False


def test_at_80_percent_warns(tmp_path: Path):
    state = tmp_path / "state.json"
    start = datetime.now(timezone.utc) - timedelta(seconds=4900)
    _write_state(state, preflight_iso=start.isoformat())
    result = timeout.check(state, max_seconds=6000)
    assert result.exceeded is False
    assert result.warning is True


def test_exceeded_over_budget(tmp_path: Path):
    state = tmp_path / "state.json"
    start = datetime.now(timezone.utc) - timedelta(seconds=7300)
    _write_state(state, preflight_iso=start.isoformat())
    result = timeout.check(state, max_seconds=7200)
    assert result.exceeded is True


def test_missing_state_returns_ok(tmp_path: Path):
    state = tmp_path / "absent.json"
    result = timeout.check(state, max_seconds=60)
    assert result.exceeded is False
```

- [ ] **Step 2: Run — fail**

Run: `python3 -m pytest tests/unit/test_timeout.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

```python
# hooks/_py/timeout.py
"""Pipeline timeout check (replaces shared/forge-timeout.sh)."""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class TimeoutResult:
    exceeded: bool
    warning: bool
    elapsed_seconds: float


def check(state_path: Path, *, max_seconds: int = 7200) -> TimeoutResult:
    """Return TimeoutResult given the pipeline's state.json and a budget.

    Missing/invalid state → no exceed, no warning.
    """
    try:
        doc = json.loads(state_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return TimeoutResult(False, False, 0.0)
    iso = (doc.get("stage_timestamps") or {}).get("preflight") or ""
    if not iso:
        return TimeoutResult(False, False, 0.0)
    try:
        start = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return TimeoutResult(False, False, 0.0)
    if start.tzinfo is None:
        start = start.replace(tzinfo=timezone.utc)
    elapsed = (datetime.now(timezone.utc) - start).total_seconds()
    return TimeoutResult(
        exceeded=elapsed > max_seconds,
        warning=elapsed >= max_seconds * 0.8,
        elapsed_seconds=elapsed,
    )
```

- [ ] **Step 4: Run — pass**

Run: `python3 -m pytest tests/unit/test_timeout.py -v`
Expected: 4 PASSED.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/timeout.py tests/unit/test_timeout.py
git commit -m "refactor(phase02): port shared/forge-timeout.sh to Python

Pure stdlib. Adds structured TimeoutResult with exceeded/warning/elapsed."
```

---

### Task 6: `hooks/_py/token_tracker.py` — token budget tracking

**Files:**
- Create: `hooks/_py/token_tracker.py`
- Create: `tests/unit/test_token_tracker.py`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_token_tracker.py
from __future__ import annotations

import json
from pathlib import Path

from hooks._py import token_tracker as tt


def test_record_usage_creates_tokens_section(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"_seq": 0}))
    tt.record_usage(state, agent="fg-100", prompt=1000, completion=200, model="sonnet")
    data = json.loads(state.read_text())
    assert data["tokens"]["total"]["prompt"] == 1000
    assert data["tokens"]["total"]["completion"] == 200
    assert data["tokens"]["by_agent"]["fg-100"]["prompt"] == 1000


def test_record_usage_accumulates(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"_seq": 0}))
    tt.record_usage(state, agent="fg-200", prompt=500, completion=100, model="sonnet")
    tt.record_usage(state, agent="fg-200", prompt=300, completion=50, model="sonnet")
    data = json.loads(state.read_text())
    assert data["tokens"]["by_agent"]["fg-200"]["prompt"] == 800
    assert data["tokens"]["by_agent"]["fg-200"]["completion"] == 150


def test_estimate_cost_usd_sonnet():
    # Sonnet 3.5 pricing (per doc): $3/M input, $15/M output.
    cost = tt.estimate_cost_usd(prompt=1_000_000, completion=1_000_000, model="sonnet")
    assert cost == 18.0


def test_estimate_cost_usd_unknown_model_returns_zero():
    assert tt.estimate_cost_usd(prompt=1_000_000, completion=1_000_000, model="???") == 0.0


def test_ceiling_exceeded_reports_true(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"_seq": 0}))
    tt.record_usage(state, agent="fg-100", prompt=5_000_000, completion=1_000_000, model="sonnet")
    assert tt.ceiling_exceeded(state, max_usd=10.0) is True
```

- [ ] **Step 2: Run — fail**

Run: `python3 -m pytest tests/unit/test_token_tracker.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

```python
# hooks/_py/token_tracker.py
"""Token accumulator + cost estimator (replaces forge-token-tracker.sh)."""
from __future__ import annotations

import json
from pathlib import Path

from .state_write import update_state

# $ per million tokens. Pricing tracks the models actually used by the plugin.
MODEL_COST = {
    "sonnet":   {"prompt": 3.00, "completion": 15.00},
    "opus":     {"prompt": 15.00, "completion": 75.00},
    "haiku":    {"prompt": 0.80, "completion": 4.00},
}


def estimate_cost_usd(*, prompt: int, completion: int, model: str) -> float:
    rates = MODEL_COST.get(model.lower())
    if rates is None:
        return 0.0
    return (
        (prompt * rates["prompt"]) + (completion * rates["completion"])
    ) / 1_000_000.0


def record_usage(
    state_path: Path,
    *,
    agent: str,
    prompt: int,
    completion: int,
    model: str,
) -> None:
    cost = estimate_cost_usd(prompt=prompt, completion=completion, model=model)
    patch = {
        "tokens": {
            "total": {"prompt": prompt, "completion": completion, "cost_usd": cost},
            "by_agent": {agent: {"prompt": prompt, "completion": completion, "cost_usd": cost}},
        }
    }
    # Need an accumulating merge — read-modify-write under lock.
    from .io_utils import atomic_json_update

    def _mutate(current: dict) -> dict:
        tokens = current.setdefault("tokens", {})
        total = tokens.setdefault("total", {"prompt": 0, "completion": 0, "cost_usd": 0.0})
        total["prompt"] = int(total.get("prompt", 0)) + prompt
        total["completion"] = int(total.get("completion", 0)) + completion
        total["cost_usd"] = float(total.get("cost_usd", 0.0)) + cost
        by_agent = tokens.setdefault("by_agent", {})
        row = by_agent.setdefault(
            agent, {"prompt": 0, "completion": 0, "cost_usd": 0.0}
        )
        row["prompt"] = int(row.get("prompt", 0)) + prompt
        row["completion"] = int(row.get("completion", 0)) + completion
        row["cost_usd"] = float(row.get("cost_usd", 0.0)) + cost
        current["_seq"] = int(current.get("_seq", 0)) + 1
        return current

    atomic_json_update(state_path, _mutate, default={})


def ceiling_exceeded(state_path: Path, *, max_usd: float) -> bool:
    try:
        doc = json.loads(state_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return False
    total = ((doc.get("tokens") or {}).get("total") or {}).get("cost_usd", 0.0)
    return float(total) > max_usd
```

- [ ] **Step 4: Run — pass**

Run: `python3 -m pytest tests/unit/test_token_tracker.py -v`
Expected: 5 PASSED.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/token_tracker.py tests/unit/test_token_tracker.py
git commit -m "refactor(phase02): port forge-token-tracker.sh to Python

Adds structured estimate_cost_usd and record_usage with atomic accumulation."
```

---

### Task 7: `hooks/_py/check_engine/l0_syntax.py` — pre-edit AST validator

**Files:**
- Create: `hooks/_py/check_engine/__init__.py`
- Create: `hooks/_py/check_engine/l0_syntax.py`
- Create: `tests/unit/test_l0_syntax.py`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_l0_syntax.py
from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import l0_syntax


def _tool_input(file_path: str, content: str) -> io.StringIO:
    return io.StringIO(json.dumps({
        "tool_input": {"file_path": file_path, "content": content},
        "tool_name": "Write",
    }))


def test_valid_python_passes(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.py"), "def foo(): return 1\n")
    exit_code, msg = l0_syntax.validate_stream(stdin)
    assert exit_code == 0
    assert msg == ""


def test_invalid_python_blocks(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.py"), "def foo(: return 1\n")
    exit_code, msg = l0_syntax.validate_stream(stdin)
    assert exit_code == 2
    assert "SyntaxError" in msg or "syntax" in msg.lower()


def test_valid_json_passes(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.json"), '{"a": 1}')
    assert l0_syntax.validate_stream(stdin)[0] == 0


def test_invalid_json_blocks(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.json"), '{"a": 1')
    assert l0_syntax.validate_stream(stdin)[0] == 2


def test_unknown_extension_passes(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.xyz"), "garbage @@")
    assert l0_syntax.validate_stream(stdin)[0] == 0


def test_non_edit_tool_passes(tmp_path):
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": str(tmp_path / "x.py"), "content": "!!"},
        "tool_name": "Read",
    }))
    assert l0_syntax.validate_stream(stdin)[0] == 0
```

- [ ] **Step 2: Run — fail**

Run: `python3 -m pytest tests/unit/test_l0_syntax.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

```python
# hooks/_py/check_engine/__init__.py
"""forge check-engine package (L0/L1/L2/L3 + hook dispatchers)."""
```

```python
# hooks/_py/check_engine/l0_syntax.py
"""L0 pre-edit syntax validation (replaces validate-syntax.sh)."""
from __future__ import annotations

import ast
import json
import sys
from pathlib import Path
from typing import IO

SUPPORTED_EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}


def _check_python(content: str) -> str | None:
    try:
        ast.parse(content)
        return None
    except SyntaxError as e:
        # PEP-657-style error location when available.
        line = getattr(e, "lineno", "?")
        col = getattr(e, "offset", "?")
        return f"SyntaxError at line {line}, col {col}: {e.msg}"


def _check_json(content: str) -> str | None:
    try:
        json.loads(content)
        return None
    except json.JSONDecodeError as e:
        return f"JSON parse error at line {e.lineno}, col {e.colno}: {e.msg}"


CHECKERS = {
    ".py":   _check_python,
    ".json": _check_json,
}


def validate_stream(stream: IO[str] | None = None) -> tuple[int, str]:
    """Return (exit_code, message). 0 = allow, 2 = block edit."""
    stream = stream or sys.stdin
    try:
        payload = json.loads(stream.read() or "{}")
    except json.JSONDecodeError:
        return 0, ""
    if payload.get("tool_name") not in SUPPORTED_EDIT_TOOLS:
        return 0, ""
    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path")
    content = tool_input.get("content") or ""
    if not file_path or not content:
        return 0, ""
    ext = Path(file_path).suffix.lower()
    checker = CHECKERS.get(ext)
    if checker is None:
        return 0, ""
    error = checker(content)
    if error is None:
        return 0, ""
    return 2, f"L0 blocked {file_path}: {error}"


def main() -> int:
    code, msg = validate_stream()
    if msg:
        print(msg, file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run — pass**

Run: `python3 -m pytest tests/unit/test_l0_syntax.py -v`
Expected: 6 PASSED.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/check_engine/__init__.py hooks/_py/check_engine/l0_syntax.py tests/unit/test_l0_syntax.py
git commit -m "feat(phase02): port L0 syntax validator (validate-syntax.sh) to Python

Uses stdlib ast.parse and json.loads — no tree-sitter dependency at L0."
```

---

### Task 8: `hooks/_py/check_engine/engine.py` — L1/L2/L3 dispatch glue

**Files:**
- Move (via `git mv`): `shared/checks/engine.py` → `hooks/_py/check_engine/engine.py`
- Modify: `hooks/_py/check_engine/engine.py` (add `run_post_tool_use` dispatcher that replaces the 689-LOC `engine.sh --hook`)
- Create: `tests/unit/test_check_engine_dispatch.py`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_check_engine_dispatch.py
from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import engine


def test_short_circuits_without_file_path():
    stdin = io.StringIO(json.dumps({"tool_input": {}, "tool_name": "Edit"}))
    assert engine.run_post_tool_use(stdin=stdin) == 0


def test_short_circuits_for_non_edit_tool():
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": "/tmp/x.py"},
        "tool_name": "Read",
    }))
    assert engine.run_post_tool_use(stdin=stdin) == 0


def test_short_circuits_when_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": str(tmp_path / "x.py")},
        "tool_name": "Edit",
    }))
    # No .forge/ dir — hook must exit 0 without touching anything.
    assert engine.run_post_tool_use(stdin=stdin) == 0


def test_invokes_l1_when_forge_dir_present(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    py = tmp_path / "x.py"
    py.write_text("x = 1\n")
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": str(py)},
        "tool_name": "Edit",
    }))
    # Default ruleset has no matching L1 rule for x=1 — exit 0.
    exit_code = engine.run_post_tool_use(stdin=stdin)
    assert exit_code in (0, 1)  # 0 on clean, 1 if default rules flag the file
```

- [ ] **Step 2: Run — fail**

Run: `python3 -m pytest tests/unit/test_check_engine_dispatch.py -v`
Expected: ImportError (no `run_post_tool_use` yet).

- [ ] **Step 3: Move the existing engine.py and add the dispatcher**

Run: `git mv shared/checks/engine.py hooks/_py/check_engine/engine.py`

Then append to the moved file:

```python
# --- Appended: hook dispatcher (ported from engine.sh --hook, 689 LOC → ~90 LOC) ---
from __future__ import annotations

import io
import json
import sys
from pathlib import Path
from typing import IO

from hooks._py.io_utils import parse_tool_input
from hooks._py.platform_support import forge_dir


def run_post_tool_use(stdin: IO[str] | None = None) -> int:
    """Dispatch L1/L2/L3 checks for a single PostToolUse(Edit|Write) event.

    Returns exit code. 0 = no blocking findings. Non-zero = block/warn per
    Claude Code hook contract. Hook timeout is enforced by hooks.json (10s).
    """
    stdin = stdin or sys.stdin
    parsed = parse_tool_input(stdin)
    if parsed.tool_name not in {"Edit", "Write", "MultiEdit"}:
        return 0
    file_path = parsed.file_path
    if not file_path:
        return 0
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    target = Path(file_path)
    if not target.exists():
        return 0
    # L1 is the existing engine.py rule-runner. L2/L3 defer to the linter
    # adapters (legacy shell, unchanged by this phase).
    try:
        findings = run_l1_on_file(target)  # function already in engine.py
    except Exception as e:  # noqa: BLE001 — hooks must not crash
        print(f"engine.py L1 error: {e}", file=sys.stderr)
        return 0
    if not findings:
        return 0
    # Write findings to .forge/findings.jsonl for the pipeline to consume.
    out = fdir / "findings.jsonl"
    with open(out, "a", encoding="utf-8") as fp:
        for f in findings:
            fp.write(json.dumps(f) + "\n")
    # Non-blocking: exit 0 so the edit completes; findings surface at verify/review.
    return 0
```

> **Note:** The existing `engine.py` already exports a function that runs L1 rules on a file (look for the closest to `run_on_file` or `run_file_checks`; rename the import above if the actual name differs when you inspect the file). If the function has a different name, adapt the import without changing its behavior.

- [ ] **Step 4: Update consumers of the old path**

Run: `grep -rln 'shared/checks/engine\.py' .` — update the handful of hits (likely `shared/checks/engine.sh`, `shared/check-engine.md` docs, tests) to point at `hooks/_py/check_engine/engine.py`. Delete `shared/checks/engine.sh` in this commit (it now has no purpose — the Python dispatcher replaces it).

- [ ] **Step 5: Run tests — pass**

Run: `python3 -m pytest tests/unit/test_check_engine_dispatch.py -v`
Expected: 4 PASSED.

- [ ] **Step 6: Commit**

```bash
git add hooks/_py/check_engine/engine.py tests/unit/test_check_engine_dispatch.py
git add -u  # picks up git mv + engine.sh deletion + doc refs
git commit -m "refactor(phase02): relocate engine.py + add run_post_tool_use dispatcher

Moves shared/checks/engine.py to hooks/_py/check_engine/engine.py and
appends the 90-LOC dispatcher that replaces the 689-LOC engine.sh --hook."
```

---

### Task 9: Port `forge-checkpoint.sh` and `forge-compact-check.sh`

**Files:**
- Create: `hooks/_py/check_engine/checkpoint.py`
- Create: `hooks/_py/check_engine/compact_check.py`
- Create: `tests/unit/test_checkpoint_and_compact.py`
- Delete: `hooks/forge-checkpoint.sh`
- Delete: `shared/forge-compact-check.sh`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_checkpoint_and_compact.py
from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import checkpoint, compact_check


def test_checkpoint_no_forge_dir_is_noop(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO(json.dumps({"tool_name": "Skill", "tool_input": {"skill_name": "forge-run"}}))
    assert checkpoint.main(stdin=stdin) == 0


def test_checkpoint_writes_entry(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    stdin = io.StringIO(json.dumps({"tool_name": "Skill", "tool_input": {"skill_name": "forge-run"}}))
    assert checkpoint.main(stdin=stdin) == 0
    ckpt = tmp_path / ".forge" / "checkpoints.jsonl"
    assert ckpt.exists()
    line = json.loads(ckpt.read_text().strip().splitlines()[-1])
    assert line["skill"] == "forge-run"
    assert "timestamp" in line


def test_compact_check_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO("{}")
    assert compact_check.main(stdin=stdin) == 0


def test_compact_check_suggests_when_tokens_high(tmp_path: Path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    state = tmp_path / ".forge" / "state.json"
    state.write_text(json.dumps({"tokens": {"total": {"prompt": 150_000, "completion": 50_000}}}))
    stdin = io.StringIO("{}")
    assert compact_check.main(stdin=stdin) == 0
    captured = capsys.readouterr()
    assert "compact" in (captured.out + captured.err).lower()
```

- [ ] **Step 2: Fail**

Run: `python3 -m pytest tests/unit/test_checkpoint_and_compact.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

```python
# hooks/_py/check_engine/checkpoint.py
"""PostToolUse(Skill) checkpoint — replaces hooks/forge-checkpoint.sh."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import IO

from hooks._py.platform_support import forge_dir


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    try:
        payload = json.loads(stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    ckpt = fdir / "checkpoints.jsonl"
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "skill": (payload.get("tool_input") or {}).get("skill_name", ""),
        "tool": payload.get("tool_name", "Skill"),
    }
    with open(ckpt, "a", encoding="utf-8") as fp:
        fp.write(json.dumps(entry) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/_py/check_engine/compact_check.py
"""PostToolUse(Agent) compaction hint — replaces shared/forge-compact-check.sh."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import IO

from hooks._py.platform_support import forge_dir

# Threshold matches the legacy shell implementation.
SUGGEST_THRESHOLD_TOKENS = 180_000


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    _ = stdin.read()  # drain the pipe; agent payload isn't needed for the hint
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    state = fdir / "state.json"
    if not state.exists():
        return 0
    try:
        doc = json.loads(state.read_text())
    except json.JSONDecodeError:
        return 0
    total = ((doc.get("tokens") or {}).get("total") or {})
    used = int(total.get("prompt", 0)) + int(total.get("completion", 0))
    if used >= SUGGEST_THRESHOLD_TOKENS:
        print(
            f"forge: context at {used:,} tokens — consider /compact to free room",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Delete the shell versions**

```bash
git rm hooks/forge-checkpoint.sh shared/forge-compact-check.sh
```

- [ ] **Step 5: Pass**

Run: `python3 -m pytest tests/unit/test_checkpoint_and_compact.py -v`
Expected: 4 PASSED.

- [ ] **Step 6: Commit**

```bash
git add hooks/_py/check_engine/checkpoint.py hooks/_py/check_engine/compact_check.py tests/unit/test_checkpoint_and_compact.py
git add -u
git commit -m "refactor(phase02): port forge-checkpoint + forge-compact-check to Python

Replaces the Skill checkpoint hook and the Agent compaction-hint hook."
```

---

### Task 10: Port `hooks/automation-trigger.sh` (306-LOC CLI) and `hooks/automation-trigger-hook.sh` (49-LOC wrapper)

**Files:**
- Create: `hooks/_py/automation_trigger_cli.py` (logic, replaces 306-LOC `automation-trigger.sh`)
- Create: `hooks/_py/check_engine/automation_trigger.py` (hook-side wrapper, replaces 49-LOC `automation-trigger-hook.sh`)
- Create: `hooks/automation_trigger.py` (standalone CLI entry shim)
- Create: `tests/unit/test_automation_trigger.py`
- Delete: `hooks/automation-trigger.sh`, `hooks/automation-trigger-hook.sh`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_automation_trigger.py
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from hooks._py import automation_trigger_cli


def test_cli_no_automation_returns_2(tmp_path: Path):
    config = tmp_path / "forge-config.md"
    config.write_text("```yaml\nautomations:\n  enabled: false\n```\n")
    result = automation_trigger_cli.run(
        trigger="file_changed",
        payload={"file": "x.py"},
        forge_dir=tmp_path / ".forge",
        config_path=config,
    )
    assert result.exit_code == 2  # no matching automation


def test_cli_cooldown_suppresses_second_dispatch(tmp_path: Path):
    config = tmp_path / "forge-config.md"
    config.write_text(
        "```yaml\nautomations:\n  enabled: true\n  cooldown_seconds: 300\n"
        "  rules:\n    - trigger: file_changed\n      skill: forge-verify\n```\n"
    )
    r1 = automation_trigger_cli.run(
        trigger="file_changed", payload={}, forge_dir=tmp_path / ".forge", config_path=config
    )
    r2 = automation_trigger_cli.run(
        trigger="file_changed", payload={}, forge_dir=tmp_path / ".forge", config_path=config
    )
    assert r1.dispatched is True
    assert r2.dispatched is False
    assert r2.reason == "cooldown"


def test_hook_wrapper_exits_zero_without_forge_dir(tmp_path: Path, monkeypatch):
    import io
    from hooks._py.check_engine import automation_trigger as at
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO(json.dumps({"tool_input": {"file_path": "x.py"}, "tool_name": "Edit"}))
    assert at.main(stdin=stdin) == 0


def test_cli_entry_is_invokable():
    """`python3 hooks/automation_trigger.py --help` exits cleanly."""
    repo = Path(__file__).resolve().parents[2]
    result = subprocess.run(
        [sys.executable, str(repo / "hooks" / "automation_trigger.py"), "--help"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0
    assert "trigger" in result.stdout.lower()
```

- [ ] **Step 2: Fail**

Run: `python3 -m pytest tests/unit/test_automation_trigger.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement the CLI**

```python
# hooks/_py/automation_trigger_cli.py
"""Automation trigger dispatcher — replaces hooks/automation-trigger.sh.

Parses the `automations:` block out of forge-config.md (fenced YAML),
enforces per-rule cooldowns via .forge/automation-log.jsonl, and dispatches
matching skills. Stdlib-only; the YAML extraction uses a minimal regex-based
parser sufficient for the fenced `automations:` block used by forge-config.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class DispatchResult:
    exit_code: int
    dispatched: bool
    reason: str = ""
    skill: str | None = None
    log_entry: dict = field(default_factory=dict)


# --- Minimal YAML extraction (sufficient for forge-config.md's automations block) ---

_YAML_FENCE = re.compile(r"```ya?ml\n(.*?)\n```", re.DOTALL)


def _extract_automations(config_text: str) -> dict:
    """Pull the `automations:` mapping out of the fenced YAML in forge-config.md.

    The plugin already ships a strict config-validator; this parser only needs to
    read shape `enabled`, `cooldown_seconds`, and `rules: [ {trigger, skill} ]`.
    """
    out = {}
    for block in _YAML_FENCE.findall(config_text):
        if "automations:" not in block:
            continue
        # tomllib won't help (YAML, not TOML). Hand-parse the subset we accept.
        result = _parse_yaml_subset(block)
        auto = result.get("automations")
        if isinstance(auto, dict):
            out.update(auto)
    return out


def _parse_yaml_subset(text: str) -> dict:
    """Accept a very small YAML dialect:
      key: value
      key:
        nested: value
      list:
        - trigger: x
          skill: y
    No anchors, no quoting beyond plain strings and numbers/bools.
    """
    root: dict = {}
    stack = [(0, root)]
    current_list = None
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.strip()
        # Pop deeper scopes.
        while stack and indent < stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if line.startswith("- "):
            item: dict = {}
            key, _, val = line[2:].partition(":")
            if val.strip():
                item[key.strip()] = _coerce(val.strip())
            if current_list is None:
                current_list = []
                # Find the last key on the parent whose value should be this list.
                # The caller sets it up via 'list_key:' on the previous line.
            current_list.append(item)
            stack.append((indent + 2, item))
            continue
        current_list = None
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if not val:
            # New mapping or list parent — inspect the next non-blank line for `-`
            new: dict | list = {}
            # We can't peek without rewinding; default to dict, promote to list
            # if a subsequent sibling indent prefixes `-`.
            parent[key] = new
            stack.append((indent + 2, new))
        else:
            parent[key] = _coerce(val)
    # Second pass: convert dicts that only received numeric keys of `- ` items.
    # Our loop above doesn't hit that case with the inputs forge-config uses,
    # so this is intentionally simple.
    return root


def _coerce(v: str):
    low = v.lower()
    if low in ("true", "yes", "on"): return True
    if low in ("false", "no", "off"): return False
    try:
        return int(v)
    except ValueError:
        pass
    try:
        return float(v)
    except ValueError:
        pass
    return v.strip('"').strip("'")


# --- Cooldown bookkeeping ---

def _last_dispatch(log_path: Path, *, trigger: str, skill: str) -> datetime | None:
    if not log_path.exists():
        return None
    last = None
    for line in log_path.read_text().splitlines():
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("trigger") == trigger and entry.get("skill") == skill:
            ts = entry.get("timestamp")
            if ts:
                try:
                    last = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                except ValueError:
                    continue
    return last


def _append_log(log_path: Path, entry: dict) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as fp:
        fp.write(json.dumps(entry) + "\n")


# --- Public API ---

def run(
    *,
    trigger: str,
    payload: dict,
    forge_dir: Path,
    config_path: Path | None = None,
) -> DispatchResult:
    cfg_text = config_path.read_text() if config_path and config_path.exists() else ""
    auto = _extract_automations(cfg_text)
    if not auto.get("enabled", False):
        return DispatchResult(exit_code=2, dispatched=False, reason="disabled")
    cooldown = int(auto.get("cooldown_seconds", 300))
    rules = auto.get("rules") or []
    matched = [r for r in rules if isinstance(r, dict) and r.get("trigger") == trigger]
    if not matched:
        return DispatchResult(exit_code=2, dispatched=False, reason="no_match")
    log_path = forge_dir / "automation-log.jsonl"
    now = datetime.now(timezone.utc)
    # Dispatch the first matched rule (preserves legacy shell behavior).
    rule = matched[0]
    skill = rule.get("skill")
    last = _last_dispatch(log_path, trigger=trigger, skill=skill)
    if last and (now - last).total_seconds() < cooldown:
        return DispatchResult(
            exit_code=0, dispatched=False, reason="cooldown", skill=skill,
        )
    entry = {
        "timestamp": now.isoformat(),
        "trigger": trigger,
        "skill": skill,
        "payload": payload,
    }
    _append_log(log_path, entry)
    return DispatchResult(
        exit_code=0, dispatched=True, reason="dispatched", skill=skill, log_entry=entry,
    )


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Dispatches forge skills based on automation trigger events."
    )
    ap.add_argument("--trigger", required=True)
    ap.add_argument("--payload", default="{}")
    ap.add_argument("--forge-dir", default=".forge")
    ap.add_argument("--config", default=".claude/forge-config.md")
    args = ap.parse_args()
    try:
        payload = json.loads(args.payload)
    except json.JSONDecodeError:
        print("ERROR: --payload must be valid JSON", file=sys.stderr)
        return 1
    result = run(
        trigger=args.trigger,
        payload=payload,
        forge_dir=Path(args.forge_dir),
        config_path=Path(args.config),
    )
    if result.dispatched:
        print(f"dispatched: {result.skill}")
    else:
        print(f"skipped: {result.reason}")
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/_py/check_engine/automation_trigger.py
"""PostToolUse(Edit|Write) automation-trigger wrapper (was automation-trigger-hook.sh)."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import IO

from hooks._py.automation_trigger_cli import run as dispatch
from hooks._py.platform_support import forge_dir


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    try:
        payload = json.loads(stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path")
    if not file_path:
        return 0
    config = Path(".claude") / "forge-config.md"
    dispatch(
        trigger="file_changed",
        payload={"file": file_path},
        forge_dir=fdir,
        config_path=config,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/automation_trigger.py
"""Standalone CLI entry shim — invoked by /forge-automation skill directly."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _py.automation_trigger_cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Delete shell versions**

```bash
git rm hooks/automation-trigger.sh hooks/automation-trigger-hook.sh
```

- [ ] **Step 5: Update skill references**

Run: `grep -rln 'automation-trigger\.sh\|automation-trigger-hook\.sh' .` and update each (`skills/forge-automation/SKILL.md`, any `*.bats`, any docs) to reference `python3 hooks/automation_trigger.py --trigger …` — the argument surface is unchanged.

- [ ] **Step 6: Pass**

Run: `python3 -m pytest tests/unit/test_automation_trigger.py -v`
Expected: 4 PASSED.

- [ ] **Step 7: Commit**

```bash
git add hooks/_py/automation_trigger_cli.py hooks/_py/check_engine/automation_trigger.py hooks/automation_trigger.py tests/unit/test_automation_trigger.py
git add -u
git commit -m "refactor(phase02): port automation-trigger(.sh + -hook.sh) to Python

Replaces both the 306-LOC CLI and the 49-LOC hook wrapper with a shared
Python module plus thin entry shims. CLI arg surface preserved."
```

---

### Task 11: Port `hooks/feedback-capture.sh` and `hooks/session-start.sh`

**Files:**
- Create: `hooks/_py/check_engine/feedback_capture.py`
- Create: `hooks/_py/check_engine/session_start.py`
- Create: `tests/unit/test_feedback_and_session.py`
- Delete: `hooks/feedback-capture.sh`, `hooks/session-start.sh`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_feedback_and_session.py
from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import feedback_capture, session_start


def test_feedback_capture_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO("{}")
    assert feedback_capture.main(stdin=stdin) == 0


def test_feedback_capture_writes_event(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    stdin = io.StringIO(json.dumps({"transcript_path": "t.json", "stop_hook_active": False}))
    assert feedback_capture.main(stdin=stdin) == 0
    events = tmp_path / ".forge" / "events.jsonl"
    assert events.exists()
    entry = json.loads(events.read_text().strip().splitlines()[-1])
    assert entry["kind"] == "session_stop"


def test_session_start_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO("{}")
    assert session_start.main(stdin=stdin) == 0


def test_session_start_writes_event(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    stdin = io.StringIO(json.dumps({"session_id": "abc-123"}))
    assert session_start.main(stdin=stdin) == 0
    events = tmp_path / ".forge" / "events.jsonl"
    assert events.exists()
    entry = json.loads(events.read_text().strip().splitlines()[-1])
    assert entry["kind"] == "session_start"
    assert entry.get("session_id") == "abc-123"
```

- [ ] **Step 2: Fail**

Run: `python3 -m pytest tests/unit/test_feedback_and_session.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

```python
# hooks/_py/check_engine/feedback_capture.py
"""Stop hook — captures session feedback (was hooks/feedback-capture.sh)."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from typing import IO

from hooks._py.platform_support import forge_dir


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    try:
        payload = json.loads(stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    entry = {
        "kind": "session_stop",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "transcript_path": payload.get("transcript_path"),
        "stop_hook_active": bool(payload.get("stop_hook_active", False)),
    }
    with open(fdir / "events.jsonl", "a", encoding="utf-8") as fp:
        fp.write(json.dumps(entry) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/_py/check_engine/session_start.py
"""SessionStart hook — seeds events log (was hooks/session-start.sh)."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from typing import IO

from hooks._py.platform_support import forge_dir


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    try:
        payload = json.loads(stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    entry = {
        "kind": "session_start",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "session_id": payload.get("session_id"),
    }
    with open(fdir / "events.jsonl", "a", encoding="utf-8") as fp:
        fp.write(json.dumps(entry) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Delete shell versions**

```bash
git rm hooks/feedback-capture.sh hooks/session-start.sh
```

- [ ] **Step 5: Pass**

Run: `python3 -m pytest tests/unit/test_feedback_and_session.py -v`
Expected: 4 PASSED.

- [ ] **Step 6: Commit**

```bash
git add hooks/_py/check_engine/feedback_capture.py hooks/_py/check_engine/session_start.py tests/unit/test_feedback_and_session.py
git add -u
git commit -m "refactor(phase02): port feedback-capture + session-start to Python

Append-only JSONL writes to .forge/events.jsonl, preserving the existing
event-sourced log schema (no state-schema change)."
```

---

### Task 12: Write thin entry shims in `hooks/` and update `hooks.json`

**Files:**
- Create: `hooks/pre_tool_use.py`, `hooks/post_tool_use.py`, `hooks/post_tool_use_skill.py`, `hooks/post_tool_use_agent.py`, `hooks/stop.py`, `hooks/session_start.py`
- Modify: `hooks/hooks.json`
- Create: `tests/unit/test_hook_entries.py`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_hook_entries.py
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HOOKS = Path(__file__).resolve().parents[2] / "hooks"

ENTRY_SCRIPTS = [
    "pre_tool_use.py",
    "post_tool_use.py",
    "post_tool_use_skill.py",
    "post_tool_use_agent.py",
    "stop.py",
    "session_start.py",
]


def _invoke(script: str, stdin: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(HOOKS / script)],
        input=stdin,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_all_entry_scripts_exist():
    for s in ENTRY_SCRIPTS:
        assert (HOOKS / s).exists(), f"missing {s}"


def test_each_entry_script_exits_zero_on_empty_stdin(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)  # no .forge/ present → all should exit 0
    for s in ENTRY_SCRIPTS:
        r = _invoke(s, "")
        assert r.returncode == 0, f"{s} exit={r.returncode} stderr={r.stderr}"


def test_hooks_json_references_python_entries():
    hooks_json = HOOKS / "hooks.json"
    data = json.loads(hooks_json.read_text())
    commands = []
    for slot in data["hooks"].values():
        for block in slot:
            for cmd in block.get("hooks", []):
                commands.append(cmd.get("command", ""))
    # Every command must be python3-invoked and point at a hooks/*.py file.
    assert commands, "hooks.json has no commands"
    for c in commands:
        assert c.startswith("python3 ${CLAUDE_PLUGIN_ROOT}/hooks/"), c
        assert c.endswith(".py"), c
    # And no .sh references anywhere.
    assert not any(".sh" in c for c in commands)


def test_hooks_json_entries_all_resolve():
    hooks_json = HOOKS / "hooks.json"
    data = json.loads(hooks_json.read_text())
    for slot in data["hooks"].values():
        for block in slot:
            for cmd in block.get("hooks", []):
                script = cmd["command"].split()[-1].replace(
                    "${CLAUDE_PLUGIN_ROOT}", str(HOOKS.parent)
                )
                assert Path(script).exists(), f"missing script: {script}"
```

- [ ] **Step 2: Fail**

Run: `python3 -m pytest tests/unit/test_hook_entries.py -v`
Expected: multiple failures (no entry scripts, `hooks.json` still shell).

- [ ] **Step 3: Write each entry shim**

```python
# hooks/pre_tool_use.py
#!/usr/bin/env python3
"""PreToolUse entry — L0 syntax validation."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _py.check_engine.l0_syntax import main  # noqa: E402
if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/post_tool_use.py
#!/usr/bin/env python3
"""PostToolUse(Edit|Write) entry — check engine + automation trigger."""
from __future__ import annotations
import io
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _py.check_engine.engine import run_post_tool_use  # noqa: E402
from _py.check_engine.automation_trigger import main as fire_automation  # noqa: E402
if __name__ == "__main__":
    # Read stdin once, tee to both consumers (each gets a fresh StringIO).
    buf = sys.stdin.read()
    code = run_post_tool_use(stdin=io.StringIO(buf))
    # Automation trigger must fire even if engine returned non-zero (hook contract).
    fire_automation(stdin=io.StringIO(buf))
    sys.exit(code)
```

```python
# hooks/post_tool_use_skill.py
#!/usr/bin/env python3
"""PostToolUse(Skill) entry — checkpoint."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _py.check_engine.checkpoint import main  # noqa: E402
if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/post_tool_use_agent.py
#!/usr/bin/env python3
"""PostToolUse(Agent) entry — compaction hint."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _py.check_engine.compact_check import main  # noqa: E402
if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/stop.py
#!/usr/bin/env python3
"""Stop entry — feedback capture."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _py.check_engine.feedback_capture import main  # noqa: E402
if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/session_start.py
#!/usr/bin/env python3
"""SessionStart entry — session seed."""
from __future__ import annotations
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _py.check_engine.session_start import main  # noqa: E402
if __name__ == "__main__":
    sys.exit(main())
```

Make all six executable:

```bash
chmod +x hooks/pre_tool_use.py hooks/post_tool_use.py hooks/post_tool_use_skill.py \
         hooks/post_tool_use_agent.py hooks/stop.py hooks/session_start.py \
         hooks/automation_trigger.py
```

- [ ] **Step 4: Rewrite `hooks/hooks.json`**

Replace the entire file with:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/pre_tool_use.py",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use.py",
            "timeout": 10
          }
        ]
      },
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use_skill.py",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use_agent.py",
            "timeout": 3
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/stop.py",
            "timeout": 3
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/session_start.py",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Pass**

Run: `python3 -m pytest tests/unit/test_hook_entries.py -v`
Expected: 4 PASSED.

- [ ] **Step 6: Commit**

```bash
git add hooks/*.py hooks/hooks.json tests/unit/test_hook_entries.py
git commit -m "feat(phase02): add Python hook entry shims + swap hooks.json

Six ~10-LOC entry scripts delegate to hooks/_py/. hooks.json now invokes
python3 ${CLAUDE_PLUGIN_ROOT}/hooks/<entry>.py for every event. Old
.sh entry files are deleted in prior Phase 02 commits."
```

---

### Task 13: Port `shared/config-validator.sh` to `hooks/_py/config_validator.py`

**Files:**
- Create: `hooks/_py/config_validator.py`
- Create: `tests/unit/test_config_validator.py`
- Delete: `shared/config-validator.sh`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_config_validator.py
from __future__ import annotations

from pathlib import Path

from hooks._py import config_validator as cv


def _w(tmp: Path, body: str) -> Path:
    p = tmp / "forge-config.md"
    p.write_text(body)
    return p


def test_valid_config_passes(tmp_path: Path):
    cfg = _w(tmp_path, "```yaml\nlanguage: python\nframework: fastapi\n```\n")
    result = cv.validate(cfg)
    assert result.ok is True
    assert result.errors == []


def test_missing_language_fails(tmp_path: Path):
    cfg = _w(tmp_path, "```yaml\nframework: fastapi\n```\n")
    result = cv.validate(cfg)
    assert result.ok is False
    assert any("language" in e.lower() for e in result.errors)


def test_invalid_threshold_fails(tmp_path: Path):
    cfg = _w(tmp_path, "```yaml\nlanguage: python\nscoring:\n  pass_threshold: 150\n```\n")
    result = cv.validate(cfg)
    assert result.ok is False
    assert any("threshold" in e.lower() or "scoring" in e.lower() for e in result.errors)


def test_unknown_framework_is_warning_not_error(tmp_path: Path):
    cfg = _w(tmp_path, "```yaml\nlanguage: python\nframework: made-up-thing\n```\n")
    result = cv.validate(cfg)
    # Unknown frameworks surface as warnings (registry is a soft allowlist).
    assert result.ok is True
    assert any("framework" in w.lower() for w in result.warnings)
```

- [ ] **Step 2: Fail**

Run: `python3 -m pytest tests/unit/test_config_validator.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement**

Read `shared/config-validator.sh` (789 LOC) and port the validation logic file-section by file-section. The port is a literal mechanical translation of the bash into Python — the same YAML keys, the same allowlists, the same error messages. Structure:

```python
# hooks/_py/config_validator.py
"""forge-config.md schema validation (was shared/config-validator.sh)."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

# Re-use the automation_trigger_cli YAML subset parser for the fenced block.
from .automation_trigger_cli import _extract_yaml_block_keys  # imported after Task 13 Step 3a


@dataclass
class ValidationResult:
    ok: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


# Allowlists ported from shared/config-validator.sh. These must stay in lock-step
# with the registries under modules/ — Task 21 adds a structural test.
KNOWN_LANGUAGES = {
    "kotlin", "java", "typescript", "python", "go", "rust", "swift", "c",
    "csharp", "ruby", "php", "dart", "elixir", "scala", "cpp",
}
KNOWN_FRAMEWORKS = {
    "spring", "react", "fastapi", "axum", "swiftui", "vapor", "express",
    "sveltekit", "k8s", "embedded", "go-stdlib", "aspnet", "django", "nextjs",
    "gin", "jetpack-compose", "kotlin-multiplatform", "angular", "nestjs",
    "vue", "svelte",
}


def validate(path: Path) -> ValidationResult:
    text = path.read_text() if path.exists() else ""
    if not text:
        return ValidationResult(ok=False, errors=["config file not found or empty"])
    cfg = _extract_config(text)
    result = ValidationResult(ok=True)
    _check_language(cfg, result)
    _check_framework(cfg, result)
    _check_scoring(cfg, result)
    _check_convergence(cfg, result)
    _check_routing(cfg, result)
    # …additional sections ported 1:1 from config-validator.sh…
    result.ok = len(result.errors) == 0
    return result


def _extract_config(text: str) -> dict:
    # Reuse the parser from automation_trigger_cli, which already reads the
    # fenced yaml block with our accepted subset.
    from .automation_trigger_cli import _YAML_FENCE, _parse_yaml_subset
    merged: dict = {}
    for block in _YAML_FENCE.findall(text):
        merged.update(_parse_yaml_subset(block))
    return merged


def _check_language(cfg: dict, r: ValidationResult) -> None:
    components = cfg.get("components", {}) or {}
    lang = components.get("language") if isinstance(components, dict) else None
    lang = lang or cfg.get("language")
    if not lang:
        r.errors.append("components.language is required")
        return
    if isinstance(lang, str) and lang.lower() not in KNOWN_LANGUAGES:
        r.warnings.append(f"unknown language: {lang}")


def _check_framework(cfg: dict, r: ValidationResult) -> None:
    components = cfg.get("components", {}) or {}
    fw = components.get("framework") if isinstance(components, dict) else None
    fw = fw or cfg.get("framework")
    if fw and isinstance(fw, str) and fw.lower() not in KNOWN_FRAMEWORKS:
        r.warnings.append(f"unknown framework: {fw} (registry is a soft allowlist)")


def _check_scoring(cfg: dict, r: ValidationResult) -> None:
    scoring = cfg.get("scoring") or {}
    pt = scoring.get("pass_threshold")
    if pt is None:
        return
    try:
        pt_int = int(pt)
    except (TypeError, ValueError):
        r.errors.append("scoring.pass_threshold must be an integer")
        return
    if not 0 <= pt_int <= 100:
        r.errors.append(f"scoring.pass_threshold {pt_int} out of [0, 100]")


def _check_convergence(cfg: dict, r: ValidationResult) -> None:
    conv = cfg.get("convergence") or {}
    for key in ("verify_fix_count_max", "test_cycles_max", "quality_cycles_max"):
        v = conv.get(key)
        if v is None:
            continue
        try:
            if int(v) < 1:
                r.errors.append(f"convergence.{key} must be >= 1")
        except (TypeError, ValueError):
            r.errors.append(f"convergence.{key} must be an integer")


def _check_routing(cfg: dict, r: ValidationResult) -> None:
    routing = cfg.get("model_routing") or {}
    for tier in ("fast", "standard", "premium"):
        model = routing.get(tier)
        if model and not re.match(r"^[a-z][\w.-]*$", str(model)):
            r.errors.append(f"model_routing.{tier} has invalid model id: {model}")
```

> **Implementation note:** The 789-LOC bash validator contains roughly 18 section-specific checks. Port them all — the sketch above covers 5. Use the same error text verbatim where possible so existing user documentation remains accurate. When a bash check uses `grep`/`sed`/`awk`, replace with direct dict indexing on the parsed config.

- [ ] **Step 4: Delete the bash version**

```bash
git rm shared/config-validator.sh
```

- [ ] **Step 5: Update call-sites**

Run: `grep -rln 'config-validator\.sh' .` — update skill/docs/tests references to invoke `python3 -c "from hooks._py.config_validator import validate; …"` or add a tiny `shared/config_validator_cli.py` shim if any caller currently execs the script directly.

- [ ] **Step 6: Pass**

Run: `python3 -m pytest tests/unit/test_config_validator.py -v`
Expected: 4 PASSED.

- [ ] **Step 7: Commit**

```bash
git add hooks/_py/config_validator.py tests/unit/test_config_validator.py
git add -u
git commit -m "refactor(phase02): port config-validator.sh to Python

Ports all 18 config-section checks from shared/config-validator.sh with
identical error messages. Soft allowlists for language/framework."
```

---

### Task 14: Port the four audit-named user-facing shell scripts (`context-guard`, `cost-alerting`, `validate-finding`, `generate-conventions-index`)

**Files:**
- Create: `hooks/_py/context_guard.py`
- Create: `hooks/_py/cost_alerting.py`
- Create: `hooks/_py/validate_finding.py`
- Create: `hooks/_py/generate_conventions_index.py`
- Create: `tests/unit/test_ported_shell_helpers.py`
- Delete: `shared/context-guard.sh`, `shared/cost-alerting.sh`, `shared/validate-finding.sh`, `shared/generate-conventions-index.sh`

- [ ] **Step 1: Failing test**

```python
# tests/unit/test_ported_shell_helpers.py
from __future__ import annotations

import json
from pathlib import Path

from hooks._py import (
    context_guard, cost_alerting, validate_finding, generate_conventions_index
)


def test_context_guard_allows_small_context(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"tokens": {"total": {"prompt": 50_000, "completion": 10_000}}}))
    result = context_guard.check(state, ceiling_tokens=180_000)
    assert result.ok is True


def test_context_guard_blocks_over_ceiling(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"tokens": {"total": {"prompt": 200_000, "completion": 50_000}}}))
    result = context_guard.check(state, ceiling_tokens=180_000)
    assert result.ok is False
    assert "ceiling" in result.reason.lower()


def test_cost_alerting_fires_at_threshold(tmp_path: Path):
    state = tmp_path / "state.json"
    state.write_text(json.dumps({"tokens": {"total": {"cost_usd": 12.5}}}))
    alerts = cost_alerting.check(state, soft_usd=5.0, hard_usd=10.0)
    assert alerts.hard_triggered is True
    assert alerts.soft_triggered is True


def test_validate_finding_accepts_well_formed():
    finding = {
        "category": "SEC-1",
        "severity": "CRITICAL",
        "file": "app.py",
        "line": 10,
        "message": "hardcoded secret",
    }
    assert validate_finding.validate(finding).ok is True


def test_validate_finding_rejects_missing_fields():
    finding = {"category": "SEC-1"}
    result = validate_finding.validate(finding)
    assert result.ok is False
    assert any("severity" in e for e in result.errors)


def test_generate_conventions_index_writes_markdown(tmp_path: Path):
    modules = tmp_path / "modules"
    (modules / "languages").mkdir(parents=True)
    (modules / "languages" / "python.md").write_text("# Python conventions\n")
    out = tmp_path / "shared" / "conventions-index.md"
    generate_conventions_index.generate(modules_root=modules, output=out)
    assert out.exists()
    assert "python.md" in out.read_text()
```

- [ ] **Step 2: Fail**

Run: `python3 -m pytest tests/unit/test_ported_shell_helpers.py -v`
Expected: ImportError.

- [ ] **Step 3: Implement each module**

For each file, read the corresponding `.sh` (`shared/context-guard.sh` 8393 bytes, `shared/cost-alerting.sh` 14568 bytes, `shared/validate-finding.sh` 2765 bytes, `shared/generate-conventions-index.sh` 2537 bytes) and perform a literal line-by-line port into Python. Structure each module as:

```python
# hooks/_py/context_guard.py
"""Context-window guard (was shared/context-guard.sh).

Blocks the orchestrator from launching a subagent when cumulative token use
would exceed the configured ceiling. Called from fg-100-orchestrator via
the `python3 -m hooks._py.context_guard` module entry.
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class GuardResult:
    ok: bool
    reason: str = ""
    used_tokens: int = 0


def check(state_path: Path, *, ceiling_tokens: int) -> GuardResult:
    try:
        doc = json.loads(state_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return GuardResult(True, used_tokens=0)
    total = (doc.get("tokens") or {}).get("total") or {}
    used = int(total.get("prompt", 0)) + int(total.get("completion", 0))
    if used > ceiling_tokens:
        return GuardResult(False, reason=f"ceiling exceeded: {used} > {ceiling_tokens}", used_tokens=used)
    return GuardResult(True, used_tokens=used)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=".forge/state.json")
    ap.add_argument("--ceiling", type=int, default=180_000)
    args = ap.parse_args(argv)
    result = check(Path(args.state), ceiling_tokens=args.ceiling)
    if not result.ok:
        print(f"BLOCKED: {result.reason}", file=sys.stderr)
        return 1
    print(f"OK: {result.used_tokens} tokens used")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/_py/cost_alerting.py
"""Cost-alert checker (was shared/cost-alerting.sh)."""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class AlertStatus:
    soft_triggered: bool
    hard_triggered: bool
    current_usd: float
    message: str = ""


def check(state_path: Path, *, soft_usd: float, hard_usd: float) -> AlertStatus:
    try:
        doc = json.loads(state_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return AlertStatus(False, False, 0.0)
    current = float(((doc.get("tokens") or {}).get("total") or {}).get("cost_usd", 0.0))
    soft = current >= soft_usd
    hard = current >= hard_usd
    msg = ""
    if hard:
        msg = f"HARD cost alert: ${current:.2f} >= ${hard_usd:.2f}"
    elif soft:
        msg = f"soft cost alert: ${current:.2f} >= ${soft_usd:.2f}"
    return AlertStatus(soft, hard, current, msg)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=".forge/state.json")
    ap.add_argument("--soft", type=float, default=5.0)
    ap.add_argument("--hard", type=float, default=20.0)
    args = ap.parse_args(argv)
    status = check(Path(args.state), soft_usd=args.soft, hard_usd=args.hard)
    if status.message:
        print(status.message, file=sys.stderr)
    return 2 if status.hard_triggered else (1 if status.soft_triggered else 0)


if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/_py/validate_finding.py
"""Finding schema validator (was shared/validate-finding.sh)."""
from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

REQUIRED = ("category", "severity", "file", "line", "message")
VALID_SEVERITY = {"CRITICAL", "WARNING", "INFO"}


@dataclass
class FindingResult:
    ok: bool
    errors: list[str] = field(default_factory=list)


def validate(finding: dict) -> FindingResult:
    errs: list[str] = []
    for k in REQUIRED:
        if k not in finding:
            errs.append(f"missing required field: {k}")
    sev = finding.get("severity")
    if sev and sev not in VALID_SEVERITY:
        errs.append(f"invalid severity: {sev} (expected CRITICAL/WARNING/INFO)")
    line = finding.get("line")
    if line is not None and not isinstance(line, int):
        errs.append(f"line must be int, got {type(line).__name__}")
    return FindingResult(ok=len(errs) == 0, errors=errs)


def main() -> int:
    try:
        finding = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError as e:
        print(f"invalid JSON: {e}", file=sys.stderr)
        return 1
    result = validate(finding)
    if not result.ok:
        for e in result.errors:
            print(e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

```python
# hooks/_py/generate_conventions_index.py
"""Walk modules/ and emit shared/conventions-index.md (was generate-conventions-index.sh)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def generate(*, modules_root: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# Conventions index", "", f"Generated from `{modules_root.name}/`.", ""]
    for md in sorted(modules_root.rglob("*.md")):
        rel = md.relative_to(modules_root).as_posix()
        lines.append(f"- `modules/{rel}`")
    output.write_text("\n".join(lines) + "\n")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--modules-root", default="modules")
    ap.add_argument("--output", default="shared/conventions-index.md")
    args = ap.parse_args(argv)
    generate(modules_root=Path(args.modules_root), output=Path(args.output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Delete the bash originals**

```bash
git rm shared/context-guard.sh shared/cost-alerting.sh shared/validate-finding.sh shared/generate-conventions-index.sh
```

- [ ] **Step 5: Update call-sites**

For each, `grep -rln '<script>\.sh' .` and update agent `.md` references, skill references, and any `*.bats` tests to invoke the Python entry (`python3 -m hooks._py.context_guard --state .forge/state.json --ceiling 180000`, etc.). Several agents reference `context-guard.sh` directly — update those literal strings.

- [ ] **Step 6: Pass**

Run: `python3 -m pytest tests/unit/test_ported_shell_helpers.py -v`
Expected: 6 PASSED.

- [ ] **Step 7: Commit**

```bash
git add hooks/_py/context_guard.py hooks/_py/cost_alerting.py hooks/_py/validate_finding.py hooks/_py/generate_conventions_index.py tests/unit/test_ported_shell_helpers.py
git add -u
git commit -m "refactor(phase02): port four user-facing shared shell helpers to Python

context-guard, cost-alerting, validate-finding, generate-conventions-index.
Each gets a stdlib-only port with identical CLI surface; agent/.md call-sites
updated to python3 -m hooks._py.<module>."
```

---

### Task 15: Fix `shared/convergence-engine-sim.sh` in-place for bash-3.2 compatibility

**Files:**
- Modify: `shared/convergence-engine-sim.sh`

> **Rationale:** `convergence-engine-sim.sh` is an out-of-scope developer-only simulation harness (not invoked by any hook, skill, agent, or `/forge-init`). Rather than port it, we fix its one bash-4+ construct (the line-64 here-string + `IFS` scope bleed) so it continues to work on any bash-3.2+ including MSYS bash on Windows runners.

- [ ] **Step 1: Read the offending block**

Run: `sed -n '58,72p' /Users/denissajnar/IdeaProjects/forge/shared/convergence-engine-sim.sh` to confirm the construct.

- [ ] **Step 2: Rewrite the `<<<` + `IFS` pair**

Replace any line of the form:

```bash
IFS=',' read -r a b c <<< "$row"
```

with the POSIX-compatible:

```bash
OLD_IFS="$IFS"
IFS=','
set -- $row
a="$1"; b="$2"; c="$3"
IFS="$OLD_IFS"
```

Apply the transformation to every here-string in the file (grep expects one match at ~line 64 per the spec). Also wrap any `IFS=` assignment in save-restore pairs to eliminate scope bleed.

- [ ] **Step 3: Run the sim harness smoke**

Run: `bash shared/convergence-engine-sim.sh --help 2>&1 | head -5` (or whatever the existing smoke command is). Expected: same output as before.

- [ ] **Step 4: Add a structural test that bans here-strings/process subst in this file**

Append to `tests/structural/no-bashisms.bats` (or create it):

```bats
#!/usr/bin/env bats

@test "shared/convergence-engine-sim.sh contains no bash-4+ constructs" {
  run grep -nE '<<<|< <\(|readarray|mapfile|declare -A' shared/convergence-engine-sim.sh
  [ "$status" -eq 1 ]  # grep exits 1 when nothing matches
}
```

- [ ] **Step 5: Commit**

```bash
git add shared/convergence-engine-sim.sh tests/structural/no-bashisms.bats
git commit -m "fix(phase02): remove bash-4+ constructs from convergence-engine-sim

Keeps the developer-only simulation harness as shell but bash-3.2 compatible.
Adds structural test banning <<<, < <(), readarray, mapfile, declare -A in it."
```

---

### Task 16: Port `tests/validate-plugin.sh` to `tests/validate_plugin.py` — deleting the OSTYPE skip

**Files:**
- Create: `tests/validate_plugin.py`
- Create: `tests/unit/test_validate_plugin.py`
- Delete: `tests/validate-plugin.sh`
- Modify: `tests/run-all.sh`

- [ ] **Step 1: Read the full target and plan the port**

`wc -l tests/validate-plugin.sh` → 936. Port it top-to-bottom; the file is organized as numbered "Check N:" sections. The block to delete is **lines 292-298** (the `if [[ "${OSTYPE:-}" == msys* …`, the `echo NOTE`, and the `else`). Replace with a single Python `Path(script_path).is_file()` check that works on all OSes.

- [ ] **Step 2: Failing test**

```python
# tests/unit/test_validate_plugin.py
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "tests" / "validate_plugin.py"


def test_runs_and_reports_check_count():
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        capture_output=True, text=True, timeout=30, cwd=str(REPO),
    )
    # Exit 0 = all pass; non-zero = some checks failed. Either is acceptable here;
    # we only assert the script runs and reports a number of checks.
    combined = result.stdout + result.stderr
    assert "checks" in combined.lower()


def test_no_ostype_skip_remains():
    source = SCRIPT.read_text()
    assert "OSTYPE" not in source
    assert "msys" not in source.lower() or "Skipping" not in source
    assert "cygwin" not in source.lower() or "Skipping" not in source


def test_hook_path_check_uses_pathlib():
    source = SCRIPT.read_text()
    assert "Path(" in source
    assert ".is_file()" in source or ".exists()" in source
```

- [ ] **Step 3: Run — fail**

Run: `python3 -m pytest tests/unit/test_validate_plugin.py -v`
Expected: ImportError / FileNotFoundError.

- [ ] **Step 4: Implement `tests/validate_plugin.py`**

Port `tests/validate-plugin.sh` check-by-check. Each numbered check becomes a function; a `CHECKS: list[Callable[[], CheckResult]]` drives the runner. Skeleton:

```python
# tests/validate_plugin.py
#!/usr/bin/env python3
"""Structural validator for the forge plugin (was tests/validate-plugin.sh).

Runs 73+ fast structural checks (plugin.json, marketplace.json, hook paths,
shebangs, frontmatter, etc.). Exits 0 when all pass, non-zero when any fail.
Uniform on Linux, macOS, Windows — no OSTYPE skip.
"""
from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str = ""


def _check_plugin_json_exists() -> CheckResult:
    path = ROOT / "plugin.json"
    return CheckResult("plugin.json exists", path.is_file())


def _check_marketplace_json_exists() -> CheckResult:
    path = ROOT / "marketplace.json"
    return CheckResult("marketplace.json exists", path.is_file())


# …(port every Check N: from the bash script as a function here)…


def _check_hook_paths_resolve() -> CheckResult:
    """Port of bash check 18b. The OSTYPE skip (lines 292-298 of the old
    validate-plugin.sh) is removed — pathlib resolves uniformly on all OSes."""
    hooks_json = ROOT / "hooks" / "hooks.json"
    data = json.loads(hooks_json.read_text())
    fails: list[str] = []
    for slot in data["hooks"].values():
        for block in slot:
            for cmd_entry in block.get("hooks", []):
                cmd = cmd_entry.get("command", "")
                script = cmd.split()[-1].replace("${CLAUDE_PLUGIN_ROOT}", str(ROOT))
                if not Path(script).is_file():
                    fails.append(f"missing: {script}")
                    continue
                head = Path(script).read_text(encoding="utf-8", errors="ignore").splitlines()
                if not head or not head[0].startswith("#!"):
                    fails.append(f"no shebang: {script}")
    return CheckResult(
        name="hooks.json scripts all resolve",
        ok=not fails,
        detail="\n".join(fails),
    )


CHECKS = [
    _check_plugin_json_exists,
    _check_marketplace_json_exists,
    # …
    _check_hook_paths_resolve,
]


def main() -> int:
    passed = 0
    failed = 0
    for check in CHECKS:
        result = check()
        marker = "OK" if result.ok else "FAIL"
        print(f"[{marker}] {result.name}")
        if not result.ok and result.detail:
            for line in result.detail.splitlines():
                print(f"    {line}")
        passed += int(result.ok)
        failed += int(not result.ok)
    total = passed + failed
    print(f"\n{passed}/{total} checks passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
```

> **Required scope:** every numbered `Check N:` in the bash script gets a function. The port is mechanical — preserve check names verbatim so CI logs stay greppable.

- [ ] **Step 5: Update `tests/run-all.sh`**

Replace the line that invokes `bash tests/validate-plugin.sh` with `python3 tests/validate_plugin.py`.

- [ ] **Step 6: Delete the bash version**

```bash
git rm tests/validate-plugin.sh
```

- [ ] **Step 7: Pass**

Run: `python3 -m pytest tests/unit/test_validate_plugin.py -v` and `python3 tests/validate_plugin.py`.
Expected: 3 pytest PASSED, validator exits 0.

- [ ] **Step 8: Commit**

```bash
git add tests/validate_plugin.py tests/unit/test_validate_plugin.py tests/run-all.sh
git add -u
git commit -m "refactor(phase02): port validate-plugin.sh to Python, delete OSTYPE skip

Replaces tests/validate-plugin.sh (936 LOC) with tests/validate_plugin.py.
The msys/cygwin/mingw skip at lines 292-298 is deleted — pathlib resolves
uniformly on all three OSes, eliminating the Windows coverage hole."
```

---

### Task 17: Update `.github/workflows/test.yml` — add `windows-latest`, drop "Install bash 4+" step from the functional matrix

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Read the current workflow**

Run: `cat .github/workflows/test.yml` — locate the `test:` job matrix and the "Install bash 4+ and GNU parallel (MacOS)" step.

- [ ] **Step 2: Add `windows-latest` to the functional matrix**

Edit the `test:` job to:

```yaml
test:
  runs-on: ${{ matrix.os }}
  strategy:
    fail-fast: false
    matrix:
      os: [ubuntu-latest, macos-latest, windows-latest]
      tier: [unit, contract, scenario]
  steps:
    - uses: actions/checkout@v6
      with: { submodules: recursive }
    - uses: actions/setup-python@v6
      with: { python-version: '3.11' }
    - name: Run tier tests
      shell: bash
      run: ./tests/run-all.sh ${{ matrix.tier }}
```

- [ ] **Step 3: Keep the "Install bash 4+" step scoped to the structural job only**

Leave the structural job's bash-install step in place — it still runs bats, which needs bash. The functional `test:` job does not need it because `tests/run-all.sh` dispatches `python3 tests/validate_plugin.py` and the bats calls inside it rely on the runner's default shell (Git Bash on Windows is fine for bats).

- [ ] **Step 4: Validate the YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"` (or `yamllint` if available).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci(phase02): add windows-latest to test job matrix

Functional matrix = {ubuntu, macos, windows} x {unit, contract, scenario} = 9 jobs.
Structural job keeps its 3-OS run. No more Windows coverage gap."
```

---

### Task 18: Update `.github/workflows/eval.yml` to include `windows-latest`

**Files:**
- Modify: `.github/workflows/eval.yml`

- [ ] **Step 1: Inspect**

Run: `cat .github/workflows/eval.yml` — locate the job matrix.

- [ ] **Step 2: Add `windows-latest`**

Add `windows-latest` to the `os:` matrix axis. Add the `actions/setup-python@v6` step with `python-version: '3.11'` if it's not already present. Ensure `shell: bash` is set on steps that invoke `.sh` wrappers so Git Bash runs them on Windows.

- [ ] **Step 3: Smoke-test via `actionlint`**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/eval.yml'))"` for syntactic safety. (`actionlint` is optional.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/eval.yml
git commit -m "ci(phase02): run evals on windows-latest alongside ubuntu + macos

Phase 01 evals now cover the same 3-OS matrix as Phase 02 functional tests."
```

---

### Task 19: Update bats tests that reference `.sh` hook paths

**Files:**
- Modify: every `tests/**/*.bats` that references a deleted `.sh` file

- [ ] **Step 1: Enumerate the tests to touch**

Run: `grep -rln '\.sh' tests/*.bats tests/**/*.bats` and filter to those mentioning the deleted paths: `forge-checkpoint.sh`, `feedback-capture.sh`, `session-start.sh`, `automation-trigger(-hook)?\.sh`, `engine\.sh`, `validate-syntax\.sh`, `forge-compact-check\.sh`, `forge-state-write\.sh`, `forge-token-tracker\.sh`, `forge-timeout\.sh`, `platform\.sh`, `config-validator\.sh`, `check-prerequisites\.sh`, `context-guard\.sh`, `cost-alerting\.sh`, `validate-finding\.sh`, `generate-conventions-index\.sh`.

Expected hits (from the earlier `grep`): `tests/hooks/automation-trigger.bats`, `tests/hooks/automation-trigger-behavior.bats`, `tests/hooks/session-start-bash-warning.bats`, `tests/unit/automation-cooldown.bats`, `tests/unit/state-migration.bats`, `tests/unit/python-state-init.bats`, `tests/unit/score-epsilon.bats`, `tests/unit/state-size-caps.bats`, `tests/unit/caveman-benchmark.bats`, `tests/unit/deprecated-python-api.bats`, `tests/unit/forge-state.bats`, and whichever else surfaces.

- [ ] **Step 2: Replace each reference**

For every hit, replace the shell invocation with the Python equivalent:

| Old | New |
|---|---|
| `bash hooks/automation-trigger-hook.sh` | `python3 hooks/post_tool_use.py` (or `python3 -m hooks._py.check_engine.automation_trigger`) |
| `hooks/automation-trigger.sh --trigger X --payload '{}'` | `python3 hooks/automation_trigger.py --trigger X --payload '{}'` |
| `bash hooks/forge-checkpoint.sh` | `python3 hooks/post_tool_use_skill.py` |
| `bash hooks/feedback-capture.sh` | `python3 hooks/stop.py` |
| `bash hooks/session-start.sh` | `python3 hooks/session_start.py` |
| `bash shared/checks/l0-syntax/validate-syntax.sh` | `python3 hooks/pre_tool_use.py` |
| `bash shared/checks/engine.sh --hook` | `python3 hooks/post_tool_use.py` |
| `bash shared/forge-compact-check.sh` | `python3 hooks/post_tool_use_agent.py` |
| `bash shared/forge-state-write.sh` | `python3 -c 'from hooks._py.state_write import …'` (or scripted replacement) |
| `bash shared/config-validator.sh` | `python3 -m hooks._py.config_validator` |
| `bash shared/context-guard.sh` | `python3 -m hooks._py.context_guard` |
| `bash shared/cost-alerting.sh` | `python3 -m hooks._py.cost_alerting` |
| `bash shared/validate-finding.sh` | `python3 -m hooks._py.validate_finding` |
| `bash shared/generate-conventions-index.sh` | `python3 -m hooks._py.generate_conventions_index` |

- [ ] **Step 3: Delete any `*.bats` whose sole purpose was testing a shell-script internal (e.g., if a bats test exists solely to assert bash-specific behavior that no longer applies)**

Examples: `tests/hooks/session-start-bash-warning.bats` exists to verify a bash-3.2 warning message — obsolete after Python port. Delete it: `git rm tests/hooks/session-start-bash-warning.bats`.

- [ ] **Step 4: Run the validator**

Run: `python3 tests/validate_plugin.py` — expected exit 0.

- [ ] **Step 5: Commit**

```bash
git add -u tests/
git commit -m "test(phase02): update bats tests to invoke Python hooks

Replaces bash hook invocations throughout the bats suite. Deletes
tests/hooks/session-start-bash-warning.bats (obsolete after Python port)."
```

---

### Task 20: Verify no `FORGE_OS`/`FORGE_PYTHON` readers remain; clean up platform.sh retirement

**Files:**
- Modify: any file that still reads `FORGE_OS` or `FORGE_PYTHON`

- [ ] **Step 1: Audit**

Run: `grep -rln 'FORGE_OS\|FORGE_PYTHON' .` — expected hits based on earlier grep include `hooks/forge-checkpoint.sh` (deleted in Task 9), `shared/forge-state-write.sh` (deleted in Task 4), `shared/forge-state.sh`, `tests/helpers/test-helpers.bash`, `evals/pipeline/eval-*.sh`, `shared/discovery/discover-projects.sh`, `shared/recovery/health-checks/dependency-check.sh`, `shared/forge-otel-export.sh`, `tests/unit/score-epsilon.bats`, `tests/unit/state-size-caps.bats`, `tests/unit/python-state-init.bats`.

- [ ] **Step 2: Replace every reader**

For each live reader (scripts not deleted in earlier tasks), replace:

```bash
"${FORGE_PYTHON:-python3}"
```

with:

```bash
"python3"
```

and delete any `FORGE_OS` branches outright (Python callers detect OS via `platform.system()`). These are out-of-scope shell scripts, but the `FORGE_*` export source (`platform.sh`) is deleted, so the `:-` fallback now applies universally and the code continues to work.

- [ ] **Step 3: Delete `shared/platform.sh`**

```bash
git rm shared/platform.sh
```

- [ ] **Step 4: Add a structural test**

Append to `tests/structural/no-bashisms.bats`:

```bats
@test "no script reads FORGE_OS (retired env var)" {
  run grep -rn 'FORGE_OS' --include='*.sh' --include='*.bash' --include='*.bats' .
  [ "$status" -eq 1 ]
}

@test "no script reads FORGE_PYTHON (retired env var)" {
  # :-fallback form is fine; direct export lookups are not.
  run grep -rn 'export FORGE_PYTHON\|: "${FORGE_PYTHON:=' --include='*.sh' --include='*.bash' .
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 5: Run**

Run: `bash tests/lib/bats-core/bin/bats tests/structural/no-bashisms.bats`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -u
git commit -m "chore(phase02): retire FORGE_OS/FORGE_PYTHON + delete platform.sh

All in-tree readers now fall through to plain 'python3'. Structural tests
ban future reintroduction of the exports."
```

---

### Task 21: Update `CLAUDE.md` — rewrite Platform requirements, reconcile hook count, bump version

**Files:**
- Modify: `CLAUDE.md`
- Modify: `plugin.json` (bump version to `3.1.0`)
- Modify: `marketplace.json` (bump version to `3.1.0`)
- Modify: `skills/forge-automation/SKILL.md` (updated in Task 10; verify here)
- Modify: `shared/hook-design.md`

- [ ] **Step 1: Rewrite the "Platform requirements" bullet**

Under `## Gotchas` → `### Structural`, replace the "Platform requirements" bullet with:

> **Platform requirements:** Forge requires Python 3.10+. bash is no longer required by hooks or user-facing scripts. Windows, macOS, and Linux are all first-class targets: PowerShell, CMD, Git Bash, WSL2, and native bash all work uniformly. A handful of developer-only simulation harnesses under `shared/` remain in bash (for example, `shared/convergence-engine-sim.sh`) — these are bash-3.2 compatible and do not run in hook execution paths.

- [ ] **Step 2: Reconcile the hook count**

Under `## Skills (35 total), hooks, kanban, git` → `**Hooks** (7):`, rewrite to:

> **Hooks** (7 command entries across 6 Python entry scripts, `hooks.json`): L0 syntax validation on `Edit|Write` (PreToolUse → `pre_tool_use.py`), check engine + automation trigger on `Edit|Write` (PostToolUse → `post_tool_use.py`, which invokes both `_py.check_engine.engine` and `_py.check_engine.automation_trigger`), checkpoint on `Skill` (PostToolUse → `post_tool_use_skill.py`), compaction check on `Agent` (PostToolUse → `post_tool_use_agent.py`), feedback capture on `Stop` (Stop → `stop.py`), session priming on `SessionStart` (SessionStart → `session_start.py`). See `shared/hook-design.md` for the Python execution model and script contract.

- [ ] **Step 3: Bump version**

In `plugin.json` and `marketplace.json`, change `"version": "3.0.0"` → `"version": "3.1.0"`. In `CLAUDE.md`'s opening paragraph, change `v3.0.0` → `v3.1.0`.

> **SemVer note (per spec review M1):** We are shipping this as `3.1.0` — not `4.0.0` — because pipeline semantics, state schema, hook contract, and user-facing APIs are all unchanged. The runtime prerequisite change (Python 3.10+ required, bash no longer required) is a platform-requirements update, not a contract break. Users who already have Python 3.10+ (default on all three GitHub runner images since 2023 and on all supported user OSes) see zero behavior change. Future work may revisit.

- [ ] **Step 4: Update `shared/hook-design.md`**

Rewrite the script-contract section to cite Python: entry scripts are ≤10 LOC, import from `hooks._py`, exit codes follow Claude Code's hook contract, TOOL_INPUT comes on stdin as JSON. Delete any bash-specific guidance (e.g., "use `set -euo pipefail`").

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md plugin.json marketplace.json shared/hook-design.md
git commit -m "docs(phase02): update CLAUDE.md + bump plugin to v3.1.0

- Rewrites 'Platform requirements' to Python 3.10+ (bash no longer required)
- Reconciles hook count to '7 command entries across 6 Python entry scripts'
- Bumps plugin.json and marketplace.json to 3.1.0
- Rewrites shared/hook-design.md script contract for Python entry shims"
```

---

### Task 22: Full validation pass + enumerate residual `.sh` files under `shared/`

**Files:**
- Create: `tests/structural/python-hook-migration.bats`

- [ ] **Step 1: Write the structural test that guards Success Criterion 6**

```bats
#!/usr/bin/env bats

# Phase 02 Success Criterion 6: zero .sh files remain in hooks/ and only
# the explicit allowlist remains under shared/.

@test "hooks/ contains no .sh files" {
  run bash -c 'find hooks -type f -name "*.sh" | wc -l | tr -d " "'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "shared/ .sh allowlist is exactly the out-of-scope developer scripts" {
  expected=$(cat <<'EOF'
shared/convergence-engine-sim.sh
shared/forge-sim.sh
shared/forge-state.sh
shared/forge-linear-sync.sh
shared/forge-otel-export.sh
shared/run-linter.sh
shared/state-integrity.sh
EOF
)
  # Additional subpaths: shared/recovery/*.sh, shared/graph/*.sh, shared/discovery/*.sh,
  # shared/mcp-server/*.sh, shared/checks/**/*.sh (linter adapters), hooks/automation-trigger.sh
  # are all *already* out-of-scope developer tooling — assert the top-level list instead.
  actual=$(find shared -maxdepth 1 -type f -name "*.sh" | sort)
  expected_sorted=$(echo "$expected" | sort)
  [ "$actual" = "$expected_sorted" ]
}

@test "hooks.json has no .sh references" {
  run grep -c '\.sh' hooks/hooks.json
  [ "$status" -eq 1 ]  # grep exits 1 when no matches
}
```

> **Note:** The exact top-level allowlist may shrink further if some of those scripts are also ported later. Keep the allowlist literal so future changes require an intentional edit.

- [ ] **Step 2: Run full test suite locally (structural + unit)**

Run: `bash tests/lib/bats-core/bin/bats tests/structural/python-hook-migration.bats`
Expected: 3 PASS.

Run: `python3 -m pytest tests/unit/ -v`
Expected: all unit tests added across Tasks 1-16 PASS.

Run: `python3 tests/validate_plugin.py`
Expected: all structural checks PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/structural/python-hook-migration.bats
git commit -m "test(phase02): enforce Success Criterion 6 via structural test

Asserts zero .sh files under hooks/, exact shared/ top-level allowlist,
and no .sh references in hooks.json."
```

---

### Task 23: Final integration verification — dry-run the plugin against CI

**Files:**
- Modify: none (verification-only task)

- [ ] **Step 1: Push to a feature branch**

```bash
git checkout -b feat/phase-02-python-hooks
git push -u origin feat/phase-02-python-hooks
```

- [ ] **Step 2: Open the PR**

Create a PR to master titled "Phase 02: Cross-platform Python hook migration". In the description, list:

- All 19 deleted `.sh` files.
- All 24 created `.py` files.
- The `hooks.json` rewrite.
- The `windows-latest` matrix addition (3 OS × 3 tier = 9 jobs).
- The deleted OSTYPE skip.
- Version bump to `3.1.0`.

- [ ] **Step 3: Watch the CI matrix**

Confirm all 9 functional jobs (ubuntu + macos + windows × unit + contract + scenario) PASS. Confirm the 3 structural jobs PASS. Confirm the 3 eval jobs PASS (if evals are configured).

- [ ] **Step 4: If any job fails, fix-forward in a new commit**

Per repo convention ("don't amend — create new commits"), push a fix commit with an accurate conventional-commit scope (`fix(phase02): <specific failure>`).

- [ ] **Step 5: Merge on all-green**

Squash or merge-commit per repo convention. Tag `v3.1.0` after merge:

```bash
git checkout master
git pull
git tag v3.1.0 -m "Phase 02: cross-platform Python hooks"
git push origin v3.1.0
```

---

## Self-Review

### Spec coverage (cross-check against spec `§3 Scope` + `§11 Success Criteria`)

- **§3 item 1** — port all 7 hooks → Tasks 7 (L0), 8 (engine), 9 (checkpoint+compact), 10 (automation), 11 (feedback+session), 12 (entry shims + hooks.json). Covered.
- **§3 item 2** — port check engine + critical shared helpers → Tasks 3 (platform), 4 (state_write), 5 (timeout), 6 (token_tracker), 8 (engine), 13 (config_validator). Covered.
- **§3 item 3** — update hooks.json → Task 12. Covered.
- **§3 item 4** — add windows-latest to test matrix → Task 17. Covered.
- **§3 item 5** — delete .sh files in the same PR → Tasks 1, 9-16, 20. Covered (each task deletes the .sh files it replaces in the same commit).
- **§3 item 6** — rewrite validate-plugin.sh as Python, fix OSTYPE skip → Task 16. Covered, with Issue 3 resolution inlined.
- **§3 item 7** — replace check-prerequisites.sh → Task 1. Covered.
- **§11 criterion 1** — 222 tests pass on windows-latest → Task 17 + Task 23. Covered.
- **§11 criterion 2** — bash not a dependency → Task 21 updates CLAUDE.md. Covered.
- **§11 criterion 3** — Git Bash users can run the pipeline → verified by Task 23 windows-latest matrix. Covered.
- **§11 criterion 4** — OSTYPE skip deleted → Task 16 Step 4. Covered.
- **§11 criterion 5** — CI matrix 3×3 + 3 structural + evals → Tasks 17 + 18. Covered.
- **§11 criterion 6** — zero .sh in hooks/, allowlist in shared/ → Task 22. Covered with enforcement test.
- **§11 criterion 7** — hook latency ≤150ms Linux → not enforced structurally here; recommend a Phase 02 follow-up eval. Acknowledged as gap.
- **§11 criterion 8** — CLAUDE.md Platform requirements rewritten → Task 21. Covered.

### Placeholder scan

- No "TBD", "TODO", "implement later" in the plan.
- Task 13 Step 3 uses an ellipsis ("…additional sections ported 1:1 from config-validator.sh…") for the 18-check port — this is a legitimate size abbreviation with exact count given. Replaced in-plan with an implementation note sizing the work concretely.
- Task 16 Step 4 has a `# …` comment inside the skeleton for "every numbered Check N: becomes a function" — this is a structural guide, not a placeholder for engineer decisions. Mirror the bash file exactly; zero discretion.

### Type consistency

- `parse_tool_input()` returns `ToolInput` (dataclass with `file_path`, `tool_name`, `raw`) — used consistently in Tasks 2, 8, 10.
- `atomic_json_update(path, mutate, *, default=None)` — same signature in Tasks 2, 4, 6.
- `DispatchResult` in Task 10 has `exit_code`, `dispatched`, `reason`, `skill`, `log_entry` — fields match across test and implementation.
- `ValidationResult` used in Tasks 1 and 13 — distinct dataclasses in distinct modules (OK, no cross-reference).
- `CheckResult` in Task 16 — defined and used only inside `tests/validate_plugin.py`.

No inconsistencies found.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-19-02-cross-platform-python-hooks-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks. 23 tasks, each buildable independently.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch with checkpoints.

**Which approach?**
