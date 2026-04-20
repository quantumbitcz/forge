# Phase 02 — Cross-Platform Python Hook Migration

**Status:** Draft
**Phase:** 02 (A+ Roadmap)
**Priority:** P0
**Author:** forge maintainers
**Date:** 2026-04-19

---

## 1. Goal

Port all 7 forge hooks, the check engine, and the critical `shared/*.sh` scripts
to Python 3.10+ stdlib-only, drop the bash 4+ requirement, and make
`windows-latest` a first-class CI target.

## 2. Motivation

### Audit W2 findings — bash-isms break Git Bash

Ten+ incompatibilities surfaced in the W2 audit. Every one of these files uses
bash-4+ constructs that MSYS/MinGW bash ships in 3.2 or that Git Bash disables
at runtime:

| File (absolute path) | Line | Construct |
|---|---|---|
| `/Users/denissajnar/IdeaProjects/forge/shared/config-validator.sh` | 673, 747, 761, 766 | process substitution `< <(...)`, here-strings `<<<` |
| `/Users/denissajnar/IdeaProjects/forge/shared/context-guard.sh` | 204 | here-string `<<<` |
| `/Users/denissajnar/IdeaProjects/forge/shared/convergence-engine-sim.sh` | 64 | here-string + `IFS` scope bleed |
| `/Users/denissajnar/IdeaProjects/forge/shared/cost-alerting.sh` | 270 | here-string `<<<` |
| `/Users/denissajnar/IdeaProjects/forge/shared/validate-finding.sh` | 25 | here-string `<<<` |
| `/Users/denissajnar/IdeaProjects/forge/shared/generate-conventions-index.sh` | — | `declare -A` |

### CI coverage gap

`.github/workflows/test.yml` runs the full `unit|contract|scenario` matrix only
on `ubuntu-latest` and `macos-latest`. `windows-latest` is pinned to the
`structural` job only (~73 checks, no hook execution), leaving Windows users
entirely uncovered by functional tests.

### Explicit Windows skip

`tests/validate-plugin.sh:298` explicitly skips hook-script path resolution on
MSYS/Cygwin/MinGW because `/d/a/...` path translation breaks `test -f`. The
comment concedes: "validated in SCRIPTS section above" — but that section also
runs bash-specific checks. Coverage is fictional.

### Industry pivot

The 2026 industry shift toward polyglot hook runtimes (Python, TypeScript) is
documented in Azure Developer CLI's April 2026 release notes:
<https://blog.jongallant.com/2026/04/azd-hooks-languages>. Python 3.10+ is
present on all three GitHub-hosted runner images by default, removing the
install-step friction that kept hooks in bash historically.

## 3. Scope

### In scope

1. Port all 7 hooks to Python 3.10+:
   - `hooks/automation-trigger-hook.sh` (49 LOC)
   - `hooks/feedback-capture.sh` (168 LOC)
   - `hooks/forge-checkpoint.sh` (58 LOC)
   - `hooks/session-start.sh` (233 LOC)
   - `shared/checks/l0-syntax/validate-syntax.sh` (191 LOC) — PreToolUse L0
   - `shared/checks/engine.sh --hook` (689 LOC) — PostToolUse check engine
   - `shared/forge-compact-check.sh` — PostToolUse(Agent) compaction hint
2. Port the check engine and critical shared helpers:
   - `shared/checks/engine.sh` → leverages existing `engine.py` (311 LOC) and
     rewrites the remaining ~380 LOC of hook-dispatch glue
   - `shared/platform.sh` → `hooks/_py/platform_support.py`
   - `shared/config-validator.sh` → `hooks/_py/config_validator.py`
   - `shared/forge-state-write.sh` → `hooks/_py/state_write.py`
   - `shared/forge-token-tracker.sh` → `hooks/_py/token_tracker.py`
   - `shared/forge-timeout.sh` → `hooks/_py/timeout.py`
3. Update `hooks/hooks.json` to invoke `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/<event>.py`.
4. Add `windows-latest` to the `test` job matrix alongside `ubuntu-latest` /
   `macos-latest`.
5. Delete the original `.sh` files in the same PR (no dual paths).
6. Rewrite `tests/validate-plugin.sh` in Python (`tests/validate_plugin.py`) and
   fix the OSTYPE skip at line 298.
7. Replace `shared/check-prerequisites.sh` with `shared/check_prerequisites.py`
   that enforces Python 3.10+ and warns on missing bash (informational only).

### Out of scope

- The bats test framework itself. Tests are executable documentation; keep them.
- Internal orchestrator shell scripts never invoked by users (`forge-state.sh`,
  `forge-sim.sh`, linter adapters). Document as **legacy shell** — acceptable
  because they run on developer machines, not in hook execution paths.
- The MCP server at `shared/mcp-server/` (already Python).
- Any change to agent `.md` files, scoring, or pipeline semantics.

## 4. Architecture

### Package layout

```
hooks/
  hooks.json                         # updated: invokes python3 entry scripts
  pre_tool_use.py                    # PreToolUse entry (L0 syntax validation)
  post_tool_use.py                   # PostToolUse entry (check engine + automation-trigger)
  post_tool_use_skill.py             # PostToolUse matcher=Skill (checkpoint)
  post_tool_use_agent.py             # PostToolUse matcher=Agent (compact-check)
  stop.py                            # Stop entry (feedback-capture)
  session_start.py                   # SessionStart entry
  _py/
    __init__.py
    platform_support.py              # was shared/platform.sh
    config_validator.py              # was shared/config-validator.sh
    state_write.py                   # was shared/forge-state-write.sh
    token_tracker.py                 # was shared/forge-token-tracker.sh
    timeout.py                       # was shared/forge-timeout.sh
    check_engine/
      __init__.py
      engine.py                      # existing engine.py + dispatch glue
      l0_syntax.py                   # was validate-syntax.sh (delegates to existing .py helpers)
      automation_trigger.py          # was automation-trigger-hook.sh
      checkpoint.py                  # was forge-checkpoint.sh
      feedback_capture.py            # was feedback-capture.sh
      session_start.py               # was session-start.sh
      compact_check.py               # was forge-compact-check.sh
    io_utils.py                      # TOOL_INPUT JSON parsing, atomic write, locks
```

**Rule:** each `hooks/<event>.py` entry script is a thin `~10-line` shim that
imports the corresponding module from `hooks/_py/` and calls its `main()`.
The entry script is the stable contract for `hooks.json`; the `_py/` package
holds reusable logic that tests import directly.

### Entry script contract

Every entry script follows this template:

```python
#!/usr/bin/env python3
"""PostToolUse hook — dispatches check engine + automation trigger."""
from __future__ import annotations
import sys
from pathlib import Path

# Ensure _py/ is importable when invoked via ${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use.py
sys.path.insert(0, str(Path(__file__).resolve().parent))

from _py.check_engine.engine import run_post_tool_use

if __name__ == "__main__":
    sys.exit(run_post_tool_use())
```

All I/O conventions (stdin JSON TOOL_INPUT → stdout/stderr → exit code) match
Claude Code's existing hook protocol. No changes required on the harness side.

### hooks.json update

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [
        { "type": "command",
          "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/pre_tool_use.py",
          "timeout": 5 }
      ]}
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [
        { "type": "command",
          "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use.py",
          "timeout": 10 }
      ]},
      { "matcher": "Skill", "hooks": [
        { "type": "command",
          "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use_skill.py",
          "timeout": 5 }
      ]},
      { "matcher": "Agent", "hooks": [
        { "type": "command",
          "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/post_tool_use_agent.py",
          "timeout": 3 }
      ]}
    ],
    "Stop": [ { "hooks": [
      { "type": "command",
        "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/stop.py",
        "timeout": 3 }
    ]}],
    "SessionStart": [ { "hooks": [
      { "type": "command",
        "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/session_start.py",
        "timeout": 3 }
    ]}]
  }
}
```

`python3` resolves via `PATH` on all three runner OSes. On Windows, the
Python.org installer and the `setup-python` action both register `python3` and
`python` aliases.

### Test harness platform detection

`tests/validate_plugin.py` uses `platform.system()` (already normalized across
Windows/Linux/Darwin) and `shutil.which("python3")`. The OSTYPE skip becomes
unnecessary because Python resolves paths uniformly — no `/d/a/` translation.

### Alternatives considered

**TypeScript (Node 20+).** Rejected. Hooks would gain a ~45 MB dependency
footprint and require `npm install` during `/forge-init`. TypeScript also
inherits the same async-runtime surface-area bugs that plague Node CLI tools
(unhandled rejections swallowed, `process.exit` racing pending writes). Python
stdlib is already a dependency (MCP server, `engine.py`, `atomic_json_update`).

**Go (compiled binary).** Rejected. Produces a 10-15 MB binary per platform, or
requires a `go run` compile step per hook invocation (~200ms overhead, exceeds
the `PostToolUse` 10s budget when multiplied by rapid Edit sequences).
Cross-compiling three binaries and distributing them via the plugin markeplace
complicates submodule updates and signing.

**Python 3.10+ stdlib-only** (selected). Already present on every runner,
single-file entry scripts, same `subprocess`/`json`/`pathlib` surface used by
`engine.py`. Zero additional dependencies; no install step.

## 5. Components

### Files created

| Path | Purpose | Replaces |
|---|---|---|
| `hooks/pre_tool_use.py` | PreToolUse entry | `shared/checks/l0-syntax/validate-syntax.sh` |
| `hooks/post_tool_use.py` | PostToolUse(Edit/Write) entry | `shared/checks/engine.sh --hook` + `hooks/automation-trigger-hook.sh` |
| `hooks/post_tool_use_skill.py` | PostToolUse(Skill) entry | `hooks/forge-checkpoint.sh` |
| `hooks/post_tool_use_agent.py` | PostToolUse(Agent) entry | `shared/forge-compact-check.sh` |
| `hooks/stop.py` | Stop entry | `hooks/feedback-capture.sh` |
| `hooks/session_start.py` | SessionStart entry | `hooks/session-start.sh` |
| `hooks/_py/__init__.py` | Package marker | — |
| `hooks/_py/platform_support.py` | OS detection, path normalization, temp dirs | `shared/platform.sh` |
| `hooks/_py/config_validator.py` | `forge-config.md` schema validation | `shared/config-validator.sh` |
| `hooks/_py/state_write.py` | Atomic JSON state writes | `shared/forge-state-write.sh` |
| `hooks/_py/token_tracker.py` | Token budget tracking | `shared/forge-token-tracker.sh` |
| `hooks/_py/timeout.py` | Pipeline timeout enforcement | `shared/forge-timeout.sh` |
| `hooks/_py/check_engine/__init__.py` | Package marker | — |
| `hooks/_py/check_engine/engine.py` | L1/L2/L3 dispatch | `shared/checks/engine.sh` |
| `hooks/_py/check_engine/l0_syntax.py` | L0 AST validation | `shared/checks/l0-syntax/validate-syntax.sh` |
| `hooks/_py/check_engine/automation_trigger.py` | Event dispatch | `hooks/automation-trigger-hook.sh` |
| `hooks/_py/check_engine/checkpoint.py` | State checkpoint | `hooks/forge-checkpoint.sh` |
| `hooks/_py/check_engine/feedback_capture.py` | Run feedback | `hooks/feedback-capture.sh` |
| `hooks/_py/check_engine/session_start.py` | Session-start priming | `hooks/session-start.sh` |
| `hooks/_py/check_engine/compact_check.py` | Compaction hint | `shared/forge-compact-check.sh` |
| `hooks/_py/io_utils.py` | TOOL_INPUT parse, file locks, atomic writes | extracted from `platform.sh` |
| `shared/check_prerequisites.py` | Enforce Python 3.10+ | `shared/check-prerequisites.sh` |
| `tests/validate_plugin.py` | Structural validator | `tests/validate-plugin.sh` |
| `pyproject.toml` | Project metadata, Python 3.10+ declaration, ruff config | — |

### Files modified

| Path | Change |
|---|---|
| `hooks/hooks.json` | Invoke `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/<event>.py` for all hooks |
| `.github/workflows/test.yml` | Add `windows-latest` to `test` job matrix (line 45); drop the "Install bash 4+ and GNU parallel (MacOS)" step as it is no longer required for hooks (structural tests still need it — keep there) |
| `.github/workflows/eval.yml` | Same windows-latest inclusion for evals |
| `tests/run-all.sh` | Call `python3 tests/validate_plugin.py` instead of `bash tests/validate-plugin.sh` |
| `CLAUDE.md` §Gotchas | Rewrite "Platform requirements" bullet (see §7) |
| `CLAUDE.md` §Cross-platform | Rewrite to "Python 3.10+ required; bash no longer a dependency" |
| `shared/check-prerequisites.sh` | Deleted; replaced by `shared/check_prerequisites.py` (call site in `/forge-init` updated) |

### Files deleted

| Path | Rationale |
|---|---|
| `hooks/automation-trigger-hook.sh` | Ported |
| `hooks/feedback-capture.sh` | Ported |
| `hooks/forge-checkpoint.sh` | Ported |
| `hooks/session-start.sh` | Ported |
| `shared/checks/engine.sh` | Ported (glue around engine.py) |
| `shared/checks/l0-syntax/validate-syntax.sh` | Ported |
| `shared/platform.sh` | Ported |
| `shared/config-validator.sh` | Ported |
| `shared/forge-state-write.sh` | Ported |
| `shared/forge-token-tracker.sh` | Ported |
| `shared/forge-timeout.sh` | Ported |
| `shared/forge-compact-check.sh` | Ported |
| `shared/check-prerequisites.sh` | Replaced by `check_prerequisites.py` |
| `tests/validate-plugin.sh` | Replaced by `tests/validate_plugin.py` |

All deletions land in the **same commit** as the Python replacements. No
`.sh.deprecated` zombies.

## 6. Data / State / Config

- **No state-schema change.** `state.json` v1.6.0, `.forge/events.jsonl`,
  `run-history.db`, and all other state files remain byte-identical.
- **No change to `finding-schema.json`** or `category-registry.json`.
- **New forge-config keys:**
  ```yaml
  python:
    version_min: "3.10"   # informational; enforced by check_prerequisites.py
  ```
  Added to `forge-config-template.md` and the generated `.claude/forge.local.md`
  at `/forge-init`. The key is read-only to users; setting it has no runtime
  effect (the hook invocation line is pinned to `python3` which already
  resolves correctly on every OS). It exists so that future PREFLIGHT checks
  or retrospective reports can reference "configured Python floor" rather than
  hardcoding `"3.10"`.
- **Retirement:** the `FORGE_OS` and `FORGE_PYTHON` exported envs from
  `platform.sh` are removed. Consuming shell scripts (legacy, out-of-scope) are
  not affected — they were the only readers and continue to source their
  shell-local copy.

## 7. Compatibility

**This is a HARD break.** No deprecation window. No dual paths.

| User cohort | Before | After |
|---|---|---|
| macOS with bash 3.2 default | Required `brew install bash` | No bash requirement; needs `python3 >= 3.10` (ships since Monterey via Xcode CLT, or `brew install python@3.11`) |
| macOS with Homebrew bash | Worked | Works; Homebrew bash now optional |
| Linux (any distro) | Worked (bash 4+ standard) | Works; Python 3.10+ standard on all distros since 2022 |
| WSL2 | Worked | Works unchanged; still recommended for Docker-heavy flows |
| Windows + Git Bash | Partially worked (10+ bash-isms broke silently) | **Works fully**; Python invokes natively, no MSYS translation issues |
| Windows + PowerShell / CMD | Did not work | **Works** — hooks are `python3 script.py` which runs in any shell |
| Windows + WSL2 | Worked | Works unchanged |

### Python 3.10+ enforcement

`shared/check_prerequisites.py` runs at `/forge-init` and prints one of:

```
OK: Python 3.11.9 detected (platform: darwin)
```

or

```
ERROR: forge plugin requires Python 3.10 or later (found 3.9.16).
Upgrade options:
  macOS:   brew install python@3.11
  Linux:   sudo apt install python3.11
  Windows: winget install Python.Python.3.11
Exit code: 1
```

`/forge-init` refuses to write config if the check fails. Hooks likewise
short-circuit with a clear error if invoked on an older Python (the `__future__`
import fails at parse time on 3.9, producing a deterministic failure mode).

### Backcompat promise

**None.** Per the phase directive: "No backwards compatibility. No local test
execution. Rely on CI." Users on the old plugin version keep working until they
`/plugin update forge`; after update, bash is no longer a dependency at all.

## 8. Testing Strategy

### CI-only, three-OS matrix

```yaml
# .github/workflows/test.yml (post-change, abridged)
test:
  strategy:
    matrix:
      os: [ubuntu-latest, macos-latest, windows-latest]
      tier: [unit, contract, scenario]
  steps:
    - uses: actions/checkout@v6
      with: { submodules: recursive }
    - uses: actions/setup-python@v6
      with: { python-version: '3.11' }
    - run: pip install pyyaml
    - run: ./tests/run-all.sh ${{ matrix.tier }}
```

Nine jobs total (3 OS × 3 tiers). Structural job stays at three OSes as well.

### Evals

`.github/workflows/eval.yml` gains the same `windows-latest` inclusion so Phase
01's `tests/evals/` harness runs on all three OSes.

### Unit tests for the Python port

`tests/unit/test_hooks_py.py` (new, pytest) verifies:

1. Each entry script's `main()` is callable with a synthetic TOOL_INPUT JSON and
   returns an integer exit code.
2. `hooks/_py/platform_support.detect_os()` returns one of
   `{"darwin", "linux", "windows", "wsl"}` (no `"gitbash"` — Git Bash users now
   report `"windows"` via `platform.system()`).
3. `hooks/_py/io_utils.atomic_json_update()` round-trips JSON on
   POSIX (flock) and Windows (file lock via `msvcrt.locking`).
4. `hooks/_py/check_engine/engine.run_post_tool_use()` short-circuits with
   exit 0 when `TOOL_INPUT` lacks `file_path` (hook contract).

### Bats tests retained

bats unit / contract / scenario tests remain — they test pipeline semantics,
not hook plumbing. They will invoke Python hooks via the updated `hooks.json`
and must pass unchanged. (A few bats tests that reference `.sh` hook paths are
updated in the same PR; this is covered by the structural check that every
path in `hooks.json` resolves to a real file.)

### Removed OSTYPE skip

`tests/validate_plugin.py` (replacement) implements check 18b using
`pathlib.Path(...).resolve()` which is uniform across all OSes. The skip
branch is deleted outright.

## 9. Rollout

**Single PR. No staged migration.**

1. Branch `feat/phase-02-python-hooks` off master.
2. All file creations, modifications, and deletions land in one commit series.
3. CI matrix runs the full nine-job test against the new Python hooks.
4. Merge when ubuntu + macOS + windows all green.
5. Cut `v3.1.0` tag (major-feature minor bump; pipeline semantics unchanged).
6. Release notes call out the HARD break: "bash no longer required; Python
   3.10+ required."

Existing runs in flight on pre-v3.1.0 plugins continue to work because hook
invocation is read from the user's installed `hooks.json` — which is only
swapped when they pull the new plugin version.

## 10. Risks

### R1 — Python version drift

**Risk:** A user on Python 3.9 (e.g., macOS Big Sur, Debian 11, CentOS 7)
installs the new plugin and every hook fails.

**Mitigation:**
- `check_prerequisites.py` runs at `/forge-init` and blocks setup with a
  platform-specific upgrade command.
- Every `hooks/_py/**/*.py` module starts with
  `from __future__ import annotations` — a no-op on 3.10+, but on 3.9 Python's
  type-annotation parser raises a clear `SyntaxError: future feature ...` (the
  `match`/`case` statements in `engine.py` already break on 3.9 with a similar
  error).
- Release notes pin the floor; the `python.version_min` config key makes the
  requirement discoverable without reading source.

### R2 — Windows path semantics

**Risk:** Windows uses `\` separators and drive letters; existing state files
written by POSIX runs may confuse Python's `pathlib.PureWindowsPath`.

**Mitigation:**
- Use `pathlib.PurePosixPath` inside state files (normalize on write).
- `io_utils.normalize_path()` always emits forward-slash POSIX strings.
- `tests/unit/test_hooks_py.py::test_windows_path_roundtrip` verifies that a
  state file written on Windows is readable on Linux and vice versa.

## 11. Success Criteria

1. **All 222 tests pass on `windows-latest`** in CI's full matrix (structural +
   unit + contract + scenario). Baseline: 73 structural checks currently.
2. **bash is no longer listed as a forge plugin dependency** anywhere in
   `CLAUDE.md`, `README.md`, or `marketplace.json`. `check_prerequisites.py`
   does not check for bash.
3. **Git Bash users can run the full pipeline** without the 10+ bash-isms
   failing. Verified by the windows-latest CI matrix, which uses Git Bash for
   `shell: bash` steps.
4. **`tests/validate-plugin.sh:298` OSTYPE skip is deleted** and the equivalent
   Python check runs uniformly on all three OSes.
5. **CI matrix = {ubuntu, macos, windows} × {unit, contract, scenario}** = 9
   jobs, plus 3 structural jobs, plus evals on all 3 OSes.
6. **Zero `.sh` files remain in `hooks/`** and the six migrated `shared/*.sh`
   files are deleted (verified by `git grep -l '^#!/.*bash' hooks/ shared/`
   returning only out-of-scope legacy scripts).
7. **Hook invocation latency p50 ≤ 150ms** on Linux (measured via
   `tests/evals/hook_latency.py`) — Python 3.10 startup is ~35ms, L0 AST parse
   is ~60ms; well within the 5s/10s hook timeouts.
8. **`CLAUDE.md` §Gotchas "Platform requirements" bullet** rewritten to read
   approximately: *"Forge requires Python 3.10+. bash is no longer required.
   Windows, macOS, and Linux are all first-class; PowerShell, CMD, Git Bash,
   WSL2, and native bash all work uniformly."*

## 12. References

- **Audit W2 report:** in-repo, referenced by Phase 02 roadmap entry
  (`docs/superpowers/reviews/` once filed)
- **Azure azd polyglot hooks (April 2026):**
  <https://blog.jongallant.com/2026/04/azd-hooks-languages>
- **Claude Code hook contract:**
  <https://code.claude.com/docs/en/hooks>
- **Python 3.10 availability on GitHub runners:**
  <https://github.com/actions/runner-images> (all three images ship ≥3.10 since
  2023)
- **PEP 657 — Enhanced error locations** (drives our L0 AST error formatting):
  <https://peps.python.org/pep-0657/>
- **Current engine.py** (311 LOC, already Python): in-repo
  `/Users/denissajnar/IdeaProjects/forge/shared/checks/engine.py`
- **hooks.json** (pre-change):
  `/Users/denissajnar/IdeaProjects/forge/hooks/hooks.json`
- **OSTYPE skip to delete:**
  `/Users/denissajnar/IdeaProjects/forge/tests/validate-plugin.sh:298`
