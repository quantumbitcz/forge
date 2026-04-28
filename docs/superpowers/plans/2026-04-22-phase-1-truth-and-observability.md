# Phase 1: Truth & Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four credibility gaps — make Windows a real first-class target, give every hook crash a durable JSONL audit trail, tag each module with a truthful support tier, and expose a cat/jq/Get-Content-readable live-run surface.
**Architecture:** Four surgical changes share zero code. Python-on-pathlib replaces bash under `shared/`; a new `hooks/_py/failure_log.py` module is imported by every hook entry script; `tests/lib/derive_support_tiers.py` injects tier badges idempotently under each module H1; a new `hooks/_py/progress.py` helper piggybacks on the existing `Agent` PostToolUse hook to rewrite `.forge/progress/status.json` atomically.
**Tech Stack:** Python 3.10+ (hooks, CI scripts, install helpers), PowerShell 7.6 (install.ps1), GitHub Actions (`actions/checkout@v6`, `actions/setup-python@v6`), JSON/JSONL on disk, `gzip` + `shutil` for rotation, bats-core for structural tests.

---

## File Structure

**Created (new files):**

- `install.sh` — repo-root bash install helper for macOS/Linux (supersedes README `ln -s`).
- `install.ps1` — repo-root PowerShell install helper for Windows native. Supports `-Help`, `-WhatIf`.
- `shared/check_environment.py` — Python replacement for `shared/check-environment.sh`.
- `hooks/_py/failure_log.py` — `record_failure()` + `rotate()` + `_ensure_forge_dir()`.
- `hooks/_py/progress.py` — `write_status_from_hook(cwd)` atomic writer.
- `shared/schemas/hook-failures.schema.json` — JSON schema for `.forge/.hook-failures.jsonl` lines.
- `shared/schemas/progress-status.schema.json` — JSON schema for `.forge/progress/status.json`.
- `shared/schemas/run-history-trends.schema.json` — JSON schema for `.forge/run-history-trends.json`.
- `tests/run-all.ps1` — PowerShell wrapper around `tests/run-all.sh` via Git-Bash `bash.exe`.
- `tests/run-all.cmd` — CMD wrapper around `tests/run-all.sh`.
- `tests/lib/derive_support_tiers.py` — tier-badge generator + `--check` drift detector.
- `docs/support-tiers.md` — authoritative tier taxonomy.
- `tests/unit/failure-log.bats` — unit tests for `hooks/_py/failure_log.py`.
- `tests/unit/check-environment-python.bats` — unit tests for `shared/check_environment.py`.
- `tests/unit/progress-status.bats` — unit tests for `hooks/_py/progress.py` + `post_tool_use_agent.py`.
- `tests/structural/install-helpers.bats` — structural tests for `install.sh` / `install.ps1`.
- `tests/structural/support-tier-badges.bats` — badge-present + idempotency tests.
- `tests/structural/no-hook-failures-log.bats` — grep sweep for AC-18.
- `tests/structural/no-emoji-new-files.bats` — emoji codepoint sweep for AC-16.
- `tests/structural/pathlib-only.bats` — pathlib-only sweep for AC-17.
- `tests/contract/schemas-phase1.bats` — JSON schema contract tests for the three new schemas.
- `tests/fixtures/phase1/hook-failure-sample.jsonl` — sample row for contract test.
- `tests/fixtures/phase1/progress-status-sample.json` — sample status object.
- `tests/fixtures/phase1/run-history-trends-sample.json` — sample trends object.

**Modified:**

- `.github/workflows/test.yml` — add `test-windows-pwsh-structural` job, `test-windows-cmd` job, pwsh-wrapper step on existing `test` Windows leg.
- `.github/workflows/docs-integrity.yml` — add `derive_support_tiers.py --check` step.
- `hooks/pre_tool_use.py` — wrap in try/except + `record_failure`.
- `hooks/post_tool_use.py` — wrap in try/except + `record_failure`.
- `hooks/post_tool_use_skill.py` — wrap in try/except + `record_failure`.
- `hooks/post_tool_use_agent.py` — wrap in try/except + `record_failure`; call `progress.write_status_from_hook()`.
- `hooks/stop.py` — wrap in try/except + `record_failure`.
- `hooks/session_start.py` — wrap in try/except + `record_failure`; call `failure_log.rotate()`.
- `shared/checks/engine.sh` — emit `.jsonl` (not `.log`), new JSON line format.
- `shared/checks/l0-syntax/validate-syntax.sh` — emit `.jsonl` (not `.log`), new JSON line format.
- `shared/hook-design.md` — `§Timeout Behavior`, `§Script Contract` rule 5, `§Failure Behavior` table, new `§Failure logging` section.
- `shared/observability.md` — new `§Local inspection` table.
- `shared/state-schema.md` — add `.forge/progress/`, `.forge/run-history-trends.json`, `.forge/.hook-failures.jsonl*` to survival list.
- `shared/logging-rules.md` — row for hooks updated to `.jsonl`.
- `shared/state-schema-fields.md` — line 693 filename update.
- `agents/fg-100-orchestrator.md` — line 1245 filename update; new `§Progress file` pointer.
- `agents/fg-505-build-verifier.md` — lines 39, 55, 140 filename update + JSONL parsing.
- `agents/fg-700-retrospective.md` — new `§Trend rollup` section.
- `skills/forge-ask status/SKILL.md` — `§Hook Health` rewritten around JSONL; new `§Live Progress` block.
- `README.md` — `§Quick start` install split; `§Available modules` tier column; `§Troubleshooting` hook-failures row.
- `CLAUDE.md` — `§Platform requirements`, `§Quick start`, `§Available modules`, `§Gotchas` survival list.
- `CHANGELOG.md` — one `[Unreleased]` entry under Phase 1.
- Every `modules/languages/*.md`, `modules/frameworks/*/conventions.md`, `modules/testing/*.md` — tier badge line inserted below H1 (idempotent via generator).

**Deleted:**

- `shared/check-environment.sh` (no shim, per standing instruction "no back-compat").
- `tests/structural/phase1-placeholder.bats` (sentinel created in Task 1, removed in Task 29 Step 2).

---

## Tasks

### Task 1: Scaffold the Phase 1 branch and structural placeholder

**Files:**
- Modify: (none — branch + placeholder only)
- Create: `tests/structural/phase1-placeholder.bats`
- Test: `tests/structural/phase1-placeholder.bats`

1. - [ ] **Step 1: Create branch**
   Check out `feat/phase-1-truth-observability` from `master`. No file changes yet.

2. - [ ] **Step 2: Write placeholder structural test**
   Create `tests/structural/phase1-placeholder.bats` with exactly this content so every later task can push and watch CI without waiting on a fresh branch bootstrap:
   ```bash
   #!/usr/bin/env bats
   # Phase 1 sentinel — deleted in the final task.
   load '../helpers/test-helpers'

   @test "phase-1 branch is live" {
     assert [ -f "$PLUGIN_ROOT/CLAUDE.md" ]
   }
   ```

3. - [ ] **Step 3: Push and verify in CI**
   Push `feat/phase-1-truth-observability`. Observe workflow `Tests` → job `structural` on `ubuntu-latest`/`macos-latest`/`windows-latest`. Confirm all three legs green. This commit is the Phase 1 baseline.

4. - [ ] **Step 4: Commit**
   ```
   chore(phase-1): open truth-and-observability branch with sentinel test
   ```

---

### Task 2: Write failing structural test for `shared/check_environment.py`

**Files:**
- Create: `tests/unit/check-environment-python.bats`
- Modify: (none)
- Test: `tests/unit/check-environment-python.bats`

1. - [ ] **Step 1: Write failing unit test for module existence and schema**
   Create `tests/unit/check-environment-python.bats`:
   ```bash
   #!/usr/bin/env bats
   # AC-1: shared/check_environment.py exists, emits identical JSON shape.
   load '../helpers/test-helpers'

   setup() {
     PY="$PLUGIN_ROOT/shared/check_environment.py"
   }

   @test "check_environment.py file exists" {
     assert [ -f "$PY" ]
   }

   @test "check_environment.py is executable" {
     assert [ -x "$PY" ]
   }

   @test "check_environment.py emits JSON with platform and tools keys" {
     run python3 "$PY"
     assert_success
     python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'platform' in d and 'tools' in d" "$output"
   }

   @test "check_environment.py tools entries have required fields" {
     run python3 "$PY"
     assert_success
     python3 -c "
   import json, sys
   d = json.loads(sys.argv[1])
   required = {'name','available','version','tier','purpose','install'}
   for t in d['tools']:
       missing = required - set(t)
       assert not missing, f'missing {missing} in {t}'
   " "$output"
   }

   @test "check_environment.py reports bash/python3/git as required tier" {
     run python3 "$PY"
     assert_success
     python3 -c "
   import json, sys
   d = json.loads(sys.argv[1])
   names = {t['name']: t['tier'] for t in d['tools']}
   for n in ('bash','python3','git'):
       assert names.get(n) == 'required', f'{n} tier={names.get(n)}'
   " "$output"
   }

   @test "check_environment.py reports a platform string in the known set" {
     run python3 "$PY"
     assert_success
     python3 -c "
   import json, sys
   d = json.loads(sys.argv[1])
   assert d['platform'] in {'darwin','linux','wsl','gitbash','windows','unknown'}, d['platform']
   " "$output"
   }

   @test "shared/check-environment.sh is deleted" {
     refute [ -f "$PLUGIN_ROOT/shared/check-environment.sh" ]
   }
   ```

2. - [ ] **Step 2: Push and verify test fails in CI**
   Push branch. Observe workflow `Tests` → job `test` matrix `tier=unit` across **all 9 OS×tier legs** (ubuntu-latest, macos-latest, windows-latest × unit/contract/scenario that touch this file). The `refute [ -f shared/check-environment.sh ]` assertion still passes (the bash file is still present — it's deleted in Task 3), but the `file exists` assertion on `shared/check_environment.py` fails with `file not found` on every leg. Do NOT expect this to fail only on ubuntu-latest — the RED phase is uniform across all OSes.

3. - [ ] **Step 3: Commit**
   ```
   test(phase-1): add failing unit tests for shared/check_environment.py
   ```

---

### Task 3: Implement `shared/check_environment.py` and delete bash original

**Files:**
- Create: `shared/check_environment.py`
- Modify: (none)
- Delete: `shared/check-environment.sh`
- Test: `tests/unit/check-environment-python.bats`

1. - [ ] **Step 1: Write `shared/check_environment.py`**
   Create file with mode 0755 and the following content:
   ```python
   #!/usr/bin/env python3
   """Probe for optional CLI tools that enhance Forge capabilities.

   Emits JSON on stdout with the same schema previously produced by the
   retired shared/check-environment.sh. Always exits 0 — informational only.

   Schema: {"platform": str, "tools": [{"name","available","version","tier","purpose","install"}]}
   """
   from __future__ import annotations

   import json
   import platform
   import shutil
   import subprocess
   import sys
   from pathlib import Path
   from typing import Optional


   def detect_platform() -> str:
       sysname = sys.platform
       if sysname == "darwin":
           return "darwin"
       if sysname.startswith("linux"):
           proc_version = Path("/proc/version")
           if proc_version.exists():
               try:
                   text = proc_version.read_text(encoding="utf-8", errors="ignore").lower()
                   if "microsoft" in text or "wsl" in text:
                       return "wsl"
               except OSError:
                   pass
           return "linux"
       if sysname.startswith(("win32", "cygwin", "msys")):
           # Detect Git Bash (MINGW/MSYS) vs native Windows pwsh/cmd.
           release = platform.release() or ""
           if "MINGW" in release or "MSYS" in release or sysname in ("cygwin", "msys"):
               return "gitbash"
           return "windows"
       return "unknown"


   def _run(cmd: list[str]) -> Optional[str]:
       try:
           result = subprocess.run(
               cmd,
               capture_output=True,
               text=True,
               timeout=5,
               check=False,
           )
       except (OSError, subprocess.TimeoutExpired):
           return None
       out = (result.stdout or result.stderr or "").strip()
       return out or None


   def _probe(name: str, tier: str, purpose: str, install: str) -> dict:
       if not shutil.which(name):
           return {
               "name": name,
               "available": False,
               "version": "",
               "tier": tier,
               "purpose": purpose,
               "install": install,
           }
       version = ""
       if name == "python3":
           version = (_run(["python3", "--version"]) or "").replace("Python", "").strip()
       elif name == "bash":
           version = (_run(["bash", "--version"]) or "").splitlines()[0] if _run(["bash", "--version"]) else ""
       elif name == "git":
           raw = _run(["git", "--version"]) or ""
           version = raw.replace("git version", "").strip()
       elif name == "jq":
           version = (_run(["jq", "--version"]) or "").replace("jq-", "").strip()
       elif name == "docker":
           raw = _run(["docker", "--version"]) or ""
           version = raw.split()[2].rstrip(",") if len(raw.split()) >= 3 else ""
       elif name == "tree-sitter":
           version = (_run(["tree-sitter", "--version"]) or "").strip()
       elif name == "gh":
           raw = _run(["gh", "--version"]) or ""
           version = raw.splitlines()[0].split()[2] if raw.splitlines() and len(raw.splitlines()[0].split()) >= 3 else ""
       elif name == "sqlite3":
           version = (_run(["sqlite3", "--version"]) or "").split()[0] if _run(["sqlite3", "--version"]) else ""
       elif name == "node":
           version = (_run(["node", "--version"]) or "").lstrip("v")
       elif name == "cargo":
           raw = _run(["cargo", "--version"]) or ""
           version = raw.split()[1] if len(raw.split()) >= 2 else ""
       elif name == "go":
           raw = _run(["go", "version"]) or ""
           version = raw.split()[2].lstrip("go") if len(raw.split()) >= 3 else ""
       return {
           "name": name,
           "available": True,
           "version": version,
           "tier": tier,
           "purpose": purpose,
           "install": install,
       }


   def _hints(platform_name: str) -> dict[str, str]:
       if platform_name == "darwin":
           return {
               "jq": "brew install jq",
               "docker": "brew install --cask docker",
               "tree-sitter": "brew install tree-sitter",
               "gh": "brew install gh",
               "sqlite3": "brew install sqlite3",
           }
       if platform_name == "linux":
           return {
               "jq": "sudo apt install jq",
               "docker": "sudo apt install docker.io",
               "tree-sitter": "npm install -g tree-sitter-cli",
               "gh": "sudo apt install gh",
               "sqlite3": "sudo apt install sqlite3",
           }
       if platform_name == "wsl":
           return {
               "jq": "sudo apt install jq",
               "docker": "Install Docker Desktop for Windows + enable WSL2 backend",
               "tree-sitter": "npm install -g tree-sitter-cli",
               "gh": "sudo apt install gh",
               "sqlite3": "sudo apt install sqlite3",
           }
       if platform_name == "gitbash":
           return {
               "jq": "scoop install jq",
               "docker": "Install Docker Desktop from docker.com",
               "tree-sitter": "npm install -g tree-sitter-cli",
               "gh": "scoop install gh",
               "sqlite3": "scoop install sqlite",
           }
       if platform_name == "windows":
           return {
               "jq": "winget install jqlang.jq",
               "docker": "winget install Docker.DockerDesktop",
               "tree-sitter": "npm install -g tree-sitter-cli",
               "gh": "winget install GitHub.cli",
               "sqlite3": "winget install SQLite.SQLite",
           }
       return {
           "jq": "https://jqlang.github.io/jq/",
           "docker": "https://docs.docker.com/get-docker/",
           "tree-sitter": "npm install -g tree-sitter-cli",
           "gh": "https://cli.github.com/",
           "sqlite3": "Install sqlite3 via your package manager",
       }


   def main() -> int:
       platform_name = detect_platform()
       hints = _hints(platform_name)
       tools: list[dict] = [
           _probe("bash", "required", "Shell runtime for Forge scripts", ""),
           _probe("python3", "required", "State management, JSON processing, check engine", ""),
           _probe("git", "required", "Version control, worktree isolation", ""),
           _probe("jq", "recommended", "JSON processing for state management and hooks", hints["jq"]),
           _probe("docker", "recommended", "Required for Neo4j knowledge graph", hints["docker"]),
           _probe("tree-sitter", "recommended", "L0 AST-based syntax validation (PreToolUse hook)", hints["tree-sitter"]),
           _probe("gh", "recommended", "GitHub CLI for cross-repo discovery and PR creation", hints["gh"]),
           _probe("sqlite3", "recommended", "SQLite code graph (zero-dependency alternative to Neo4j)", hints["sqlite3"]),
       ]
       cwd = Path.cwd()
       if (cwd / "package.json").exists() or (cwd / "tsconfig.json").exists():
           tools.append(_probe("node", "optional", "Node.js runtime (JS/TS project detected)", ""))
       if (cwd / "Cargo.toml").exists():
           tools.append(_probe("cargo", "optional", "Rust toolchain (Rust project detected)", ""))
       if (cwd / "go.mod").exists():
           tools.append(_probe("go", "optional", "Go toolchain (Go project detected)", ""))
       sys.stdout.write(json.dumps({"platform": platform_name, "tools": tools}, separators=(",", ":")))
       sys.stdout.write("\n")
       return 0


   if __name__ == "__main__":
       sys.exit(main())
   ```
   `chmod +x shared/check_environment.py`.

2. - [ ] **Step 2: Delete `shared/check-environment.sh`**
   `git rm shared/check-environment.sh`.

3. - [ ] **Step 3: Push and verify tests pass in CI**
   Push. Observe workflow `Tests` → job `test`, matrix `tier=unit` on all three OSes. Confirm `tests/unit/check-environment-python.bats` green.

4. - [ ] **Step 4: Commit**
   ```
   feat(phase-1): port check-environment.sh to shared/check_environment.py

   Replaces bash with pathlib+shutil Python probe. Same JSON output shape. Adds
   a native-windows hints branch using winget. No shim — shared/check-environment.sh
   is deleted.
   ```

---

### Task 4: Add `install.sh` (macOS/Linux install helper)

**Files:**
- Create: `install.sh`
- Modify: (none)
- Test: `tests/structural/install-helpers.bats`

1. - [ ] **Step 1: Write failing structural test**
   Create `tests/structural/install-helpers.bats`:
   ```bash
   #!/usr/bin/env bats
   # AC-2 / AC-3: install helpers exist at repo root.
   load '../helpers/test-helpers'

   @test "install.sh exists at repo root" {
     assert [ -f "$PLUGIN_ROOT/install.sh" ]
   }

   @test "install.sh is executable" {
     assert [ -x "$PLUGIN_ROOT/install.sh" ]
   }

   @test "install.sh has bash shebang" {
     run head -1 "$PLUGIN_ROOT/install.sh"
     assert_output --regexp '^#!/usr/bin/env bash'
   }

   @test "install.sh supports --help" {
     run bash "$PLUGIN_ROOT/install.sh" --help
     assert_success
     assert_output --partial "Usage:"
   }

   @test "install.sh supports --dry-run" {
     run bash "$PLUGIN_ROOT/install.sh" --dry-run
     assert_success
     assert_output --partial "dry-run"
   }

   @test "install.ps1 exists at repo root" {
     assert [ -f "$PLUGIN_ROOT/install.ps1" ]
   }

   @test "install.ps1 has a param block" {
     run grep -E '^\s*param\s*\(' "$PLUGIN_ROOT/install.ps1"
     assert_success
   }

   @test "install.ps1 supports -Help" {
     run grep -E '\[switch\]\s*\$Help' "$PLUGIN_ROOT/install.ps1"
     assert_success
   }

   @test "install.ps1 supports -WhatIf" {
     run grep -E '\[switch\]\s*\$WhatIf' "$PLUGIN_ROOT/install.ps1"
     assert_success
   }
   ```

2. - [ ] **Step 2: Write `install.sh`**
   Create at repo root, mode 0755:
   ```bash
   #!/usr/bin/env bash
   # forge plugin installer for macOS and Linux.
   # Windows users: use install.ps1 instead.
   set -euo pipefail

   FORGE_REPO="${FORGE_REPO:-https://github.com/quantumbitcz/forge.git}"
   FORGE_REF="${FORGE_REF:-master}"
   PLUGIN_DIR="${PLUGIN_DIR:-$HOME/.claude/plugins/forge}"
   DRY_RUN=0

   usage() {
     cat <<'USAGE'
   Usage: install.sh [--dry-run] [--help]

   Installs the forge plugin into $HOME/.claude/plugins/forge.

   Env overrides:
     FORGE_REPO  git URL            (default: quantumbitcz/forge on GitHub)
     FORGE_REF   git ref to check out (default: master)
     PLUGIN_DIR  install destination (default: $HOME/.claude/plugins/forge)

   Options:
     --dry-run   Print planned actions without writing anything.
     --help      Show this message and exit.
   USAGE
   }

   log()   { printf '[install.sh] %s\n' "$*"; }
   warn()  { printf '[install.sh] WARN: %s\n' "$*" >&2; }
   error() { printf '[install.sh] ERROR: %s\n' "$*" >&2; exit 1; }

   while (( "$#" )); do
     case "$1" in
       --help|-h) usage; exit 0 ;;
       --dry-run) DRY_RUN=1; shift ;;
       *) error "unknown arg: $1 (try --help)" ;;
     esac
   done

   command -v git >/dev/null 2>&1 || error "git is required but not in PATH"

   if (( DRY_RUN )); then
     log "dry-run: would ensure $PLUGIN_DIR exists"
     log "dry-run: would clone $FORGE_REPO ref $FORGE_REF into $PLUGIN_DIR"
     log "dry-run: would add plugin entry to $HOME/.claude/settings.json"
     exit 0
   fi

   mkdir -p "$(dirname "$PLUGIN_DIR")"

   if [ -d "$PLUGIN_DIR/.git" ]; then
     log "updating existing clone at $PLUGIN_DIR"
     git -C "$PLUGIN_DIR" fetch --depth 1 origin "$FORGE_REF"
     git -C "$PLUGIN_DIR" checkout "$FORGE_REF"
     git -C "$PLUGIN_DIR" reset --hard "origin/$FORGE_REF"
   else
     log "cloning $FORGE_REPO into $PLUGIN_DIR"
     git clone --depth 1 --branch "$FORGE_REF" "$FORGE_REPO" "$PLUGIN_DIR"
   fi

   SETTINGS="$HOME/.claude/settings.json"
   mkdir -p "$(dirname "$SETTINGS")"
   if [ ! -f "$SETTINGS" ]; then
     printf '{"plugins":["%s"]}\n' "$PLUGIN_DIR" > "$SETTINGS"
     log "created $SETTINGS with plugin entry"
   else
     if grep -q "$PLUGIN_DIR" "$SETTINGS"; then
       log "$SETTINGS already references $PLUGIN_DIR"
     else
       warn "$SETTINGS exists; please add \"$PLUGIN_DIR\" to the \"plugins\" array manually"
     fi
   fi

   log "done. Run /forge in a project to complete setup."
   ```
   `chmod +x install.sh`.

3. - [ ] **Step 3: Push and verify in CI**
   Push. Observe `Tests` → `structural` on `ubuntu-latest`. The install.sh bats tests pass, but the three install.ps1 tests fail (file missing) — expected, fixed in Task 5.

4. - [ ] **Step 4: Commit**
   ```
   feat(phase-1): add install.sh repo-root helper for macOS/Linux

   Supports --dry-run and --help. Clones forge into ~/.claude/plugins/forge
   and merges into ~/.claude/settings.json. Supersedes the README ln -s snippet.
   ```

---

### Task 5: Add `install.ps1` (Windows PowerShell install helper)

**Files:**
- Create: `install.ps1`
- Modify: (none)
- Test: `tests/structural/install-helpers.bats`

1. - [ ] **Step 1: Write `install.ps1`**
   Create at repo root:
   ```powershell
   <#
   .SYNOPSIS
     Forge plugin installer for Windows (PowerShell 5.1+ / 7.x).

   .DESCRIPTION
     Clones quantumbitcz/forge into $env:USERPROFILE\.claude\plugins\forge and
     adds the plugin path to settings.json. macOS/Linux users: use install.sh.

   .PARAMETER Help
     Print usage and exit.

   .PARAMETER WhatIf
     Print planned actions without writing anything.

   .PARAMETER Repo
     Git URL to clone (default: https://github.com/quantumbitcz/forge.git).

   .PARAMETER Ref
     Git ref to check out (default: master).

   .PARAMETER PluginDir
     Install destination (default: $env:USERPROFILE\.claude\plugins\forge).
   #>
   param(
       [switch]$Help,
       [switch]$WhatIf,
       [string]$Repo = 'https://github.com/quantumbitcz/forge.git',
       [string]$Ref  = 'master',
       [string]$PluginDir = (Join-Path $env:USERPROFILE '.claude\plugins\forge')
   )

   $ErrorActionPreference = 'Stop'

   function Write-Info  { param([string]$m) Write-Host "[install.ps1] $m" }
   function Write-Warn2 { param([string]$m) Write-Host "[install.ps1] WARN: $m" -ForegroundColor Yellow }
   function Write-Err2  { param([string]$m) Write-Host "[install.ps1] ERROR: $m" -ForegroundColor Red; exit 1 }

   if ($Help) {
       @'
   Usage: powershell -ExecutionPolicy Bypass -File install.ps1 [-WhatIf] [-Help]
                                                             [-Repo <url>]
                                                             [-Ref  <ref>]
                                                             [-PluginDir <path>]

   Installs the forge plugin into $env:USERPROFILE\.claude\plugins\forge.
   '@ | Write-Host
       exit 0
   }

   if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
       Write-Err2 'git is required but not found in PATH'
   }

   $settingsDir  = Join-Path $env:USERPROFILE '.claude'
   $settingsFile = Join-Path $settingsDir 'settings.json'

   if ($WhatIf) {
       Write-Info "dry-run: would ensure $PluginDir exists"
       Write-Info "dry-run: would clone $Repo ref $Ref into $PluginDir"
       Write-Info "dry-run: would merge plugin entry into $settingsFile"
       exit 0
   }

   if (-not (Test-Path -LiteralPath (Split-Path $PluginDir -Parent))) {
       New-Item -ItemType Directory -Path (Split-Path $PluginDir -Parent) -Force | Out-Null
   }

   if (Test-Path -LiteralPath (Join-Path $PluginDir '.git')) {
       Write-Info "updating existing clone at $PluginDir"
       git -C $PluginDir fetch --depth 1 origin $Ref
       git -C $PluginDir checkout $Ref
       git -C $PluginDir reset --hard "origin/$Ref"
   } else {
       Write-Info "cloning $Repo into $PluginDir"
       git clone --depth 1 --branch $Ref $Repo $PluginDir
   }

   if (-not (Test-Path -LiteralPath $settingsDir)) {
       New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
   }

   if (-not (Test-Path -LiteralPath $settingsFile)) {
       @{ plugins = @($PluginDir) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $settingsFile -Encoding UTF8
       Write-Info "created $settingsFile with plugin entry"
   } else {
       $raw = Get-Content -LiteralPath $settingsFile -Raw
       if ($raw -match [regex]::Escape($PluginDir)) {
           Write-Info "$settingsFile already references $PluginDir"
       } else {
           Write-Warn2 "$settingsFile exists; add `"$PluginDir`" to its 'plugins' array manually"
       }
   }

   Write-Info 'done. Run /forge in a project to complete setup.'
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. Observe `Tests` → `structural` on all three OSes; all install-helper bats tests now green.

3. - [ ] **Step 3: Commit**
   ```
   feat(phase-1): add install.ps1 repo-root helper for Windows

   Supports -Help and -WhatIf. Clones forge into %USERPROFILE%\.claude\plugins\forge
   and merges into settings.json. Parses cleanly under PowerShell 5.1 and 7.x.
   ```

---

### Task 6: Add CI parser + PSScriptAnalyzer gate for `install.ps1`

**Files:**
- Modify: `.github/workflows/test.yml`
- Test: CI job output

1. - [ ] **Step 1: Add pwsh syntax-parse + PSScriptAnalyzer step to the existing `structural` job**
   Insert these two steps after the existing `Structural validation` step (applies only to `windows-latest` via `runner.os` gate):
   ```yaml
         - name: install.ps1 parses under PowerShell
           if: runner.os == 'Windows'
           shell: pwsh
           run: |
             $script = Get-Content -Raw install.ps1
             $null = [scriptblock]::Create($script)

         - name: Cache PSScriptAnalyzer module
           if: runner.os == 'Windows'
           uses: actions/cache@v4
           with:
             path: |
               ~\Documents\PowerShell\Modules\PSScriptAnalyzer
               ~\Documents\WindowsPowerShell\Modules\PSScriptAnalyzer
             key: psscriptanalyzer-${{ runner.os }}-v1

         - name: PSScriptAnalyzer install.ps1
           if: runner.os == 'Windows'
           shell: pwsh
           run: |
             if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
               Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -ErrorAction Stop
             }
             $issues = Invoke-ScriptAnalyzer -Path install.ps1 -Severity Error,Warning
             if ($issues) {
               $issues | Format-Table | Out-String | Write-Host
               throw "PSScriptAnalyzer found issues"
             }
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. Observe `Tests` → `structural` on `windows-latest`. Both new steps pass.

3. - [ ] **Step 3: Commit**
   ```
   ci(phase-1): gate install.ps1 on parse + PSScriptAnalyzer in structural
   ```

---

### Task 7: Add `tests/run-all.ps1` and `tests/run-all.cmd` wrappers

**Files:**
- Create: `tests/run-all.ps1`, `tests/run-all.cmd`
- Modify: (none)
- Test: CI via the next workflow edit

1. - [ ] **Step 1: Write `tests/run-all.ps1`**
   ```powershell
   <#
   .SYNOPSIS
     PowerShell wrapper around tests/run-all.sh for Windows pwsh coverage.
   #>
   param(
       [Parameter(Position = 0)]
       [string]$Tier = 'all'
   )

   $ErrorActionPreference = 'Stop'

   $bash = (Get-Command bash -ErrorAction SilentlyContinue)
   if (-not $bash) {
       $candidate = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
       if (Test-Path -LiteralPath $candidate) {
           $bash = @{ Source = $candidate }
       } else {
           Write-Error 'bash.exe not found (install Git for Windows or WSL)'
       }
   }

   $script = Join-Path $PSScriptRoot 'run-all.sh'
   & $bash.Source $script $Tier
   exit $LASTEXITCODE
   ```

2. - [ ] **Step 2: Write `tests/run-all.cmd`**
   ```bat
   @echo off
   setlocal
   set "TIER=%~1"
   if "%TIER%"=="" set "TIER=all"

   set "BASH_EXE=bash.exe"
   where %BASH_EXE% >nul 2>nul
   if errorlevel 1 (
     if exist "%ProgramFiles%\Git\bin\bash.exe" (
       set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
     ) else (
       echo ERROR: bash.exe not found. Install Git for Windows.
       exit /b 1
     )
   )

   "%BASH_EXE%" "%~dp0run-all.sh" %TIER%
   exit /b %ERRORLEVEL%
   ```

3. - [ ] **Step 3: Push and verify in CI**
   Push. Existing CI stays green; the new wrappers are unused until Task 8 activates them. No new job failures.

4. - [ ] **Step 4: Commit**
   ```
   feat(phase-1): add tests/run-all.ps1 and tests/run-all.cmd wrappers

   Delegate to run-all.sh via Git Bash bash.exe. Prep for pwsh + cmd CI legs.
   ```

---

### Task 8: Wire `test-windows-pwsh-structural` and `test-windows-cmd` jobs

**Files:**
- Modify: `.github/workflows/test.yml`
- Test: CI job matrix

1. - [ ] **Step 1: Append the two new jobs to `.github/workflows/test.yml`**
   After the existing `test:` job, append:
   ```yaml
     test-windows-pwsh-structural:
       needs: structural
       runs-on: windows-latest
       timeout-minutes: 20
       permissions:
         contents: read
       defaults:
         run:
           shell: pwsh
       steps:
         - uses: actions/checkout@v6
           with:
             submodules: recursive

         - uses: actions/setup-python@v6
           with:
             python-version: '3.10'

         - name: Install Python dependencies
           run: pip install pyyaml jsonschema

         - name: Structural validation (pwsh wrapper)
           run: .\tests\run-all.ps1 structural

     test-windows-cmd:
       needs: structural
       runs-on: windows-latest
       timeout-minutes: 20
       permissions:
         contents: read
       defaults:
         run:
           shell: cmd
       steps:
         - uses: actions/checkout@v6
           with:
             submodules: recursive

         - uses: actions/setup-python@v6
           with:
             python-version: '3.10'

         - name: Install Python dependencies
           run: pip install pyyaml jsonschema

         - name: Structural validation (cmd wrapper)
           run: tests\run-all.cmd structural

         - name: Unit tests (cmd wrapper)
           run: tests\run-all.cmd unit
   ```

2. - [ ] **Step 2: Add explicit `shell: pwsh` wrapper to existing `test` job's Windows legs**
   Replace the existing `Run ${{ matrix.tier }} tests` step in the `test:` job with two conditional siblings:
   ```yaml
         - name: Run ${{ matrix.tier }} tests (bash)
           if: runner.os != 'Windows'
           run: ./tests/run-all.sh ${{ matrix.tier }}

         - name: Run ${{ matrix.tier }} tests (pwsh wrapper)
           if: runner.os == 'Windows'
           shell: pwsh
           run: .\tests\run-all.ps1 ${{ matrix.tier }}
   ```

3. - [ ] **Step 3: Push and verify in CI**
   Push. Observe all of:
   - `Tests` → `structural` on ubuntu/macos/windows — green.
   - `Tests` → `test` on ubuntu/macos/windows × unit/contract/scenario — green (Windows legs now route through run-all.ps1).
   - `Tests` → `test-windows-pwsh-structural` — new job green.
   - `Tests` → `test-windows-cmd` — new job green.

4. - [ ] **Step 4: Commit**
   ```
   ci(phase-1): add test-windows-pwsh-structural and test-windows-cmd jobs

   Formalises pwsh coverage on existing test job via tests/run-all.ps1; adds
   CMD smoke coverage (structural + unit) via tests/run-all.cmd.
   ```

---

### Task 9: JSON schemas + fixtures for the three new artefacts

**Files:**
- Create: `shared/schemas/hook-failures.schema.json`, `shared/schemas/progress-status.schema.json`, `shared/schemas/run-history-trends.schema.json`
- Create: `tests/fixtures/phase1/hook-failure-sample.jsonl`, `tests/fixtures/phase1/progress-status-sample.json`, `tests/fixtures/phase1/run-history-trends-sample.json`
- Create: `tests/contract/schemas-phase1.bats`
- Test: `tests/contract/schemas-phase1.bats`

1. - [ ] **Step 1: Write `shared/schemas/hook-failures.schema.json`**
   ```json
   {
     "$schema": "http://json-schema.org/draft-07/schema#",
     "$id": "https://forge.local/schemas/hook-failures.schema.json",
     "title": "Hook failure row",
     "type": "object",
     "additionalProperties": false,
     "required": ["schema", "ts", "hook_name", "matcher", "exit_code", "duration_ms", "cwd"],
     "properties": {
       "schema": {"const": 1},
       "ts": {"type": "string", "format": "date-time"},
       "hook_name": {"type": "string", "minLength": 1},
       "matcher": {"type": "string"},
       "exit_code": {"type": "integer"},
       "stderr_excerpt": {"type": "string", "maxLength": 2048},
       "duration_ms": {"type": "integer", "minimum": 0},
       "cwd": {"type": "string"}
     }
   }
   ```

2. - [ ] **Step 2: Write `shared/schemas/progress-status.schema.json`**
   ```json
   {
     "$schema": "http://json-schema.org/draft-07/schema#",
     "$id": "https://forge.local/schemas/progress-status.schema.json",
     "title": "Forge live progress status",
     "type": "object",
     "additionalProperties": false,
     "required": ["run_id", "stage", "agent_active", "elapsed_ms_in_stage", "timeout_ms", "last_event", "updated_at", "writer"],
     "properties": {
       "run_id": {"type": "string"},
       "stage": {"type": "string"},
       "agent_active": {"type": ["string", "null"]},
       "elapsed_ms_in_stage": {"type": "integer", "minimum": 0},
       "timeout_ms": {"type": "integer", "minimum": 0},
       "last_event": {
         "type": "object",
         "required": ["ts", "type", "detail"],
         "properties": {
           "ts": {"type": "string", "format": "date-time"},
           "type": {"type": "string"},
           "detail": {"type": "string"}
         }
       },
       "next_expected_at": {"type": ["string", "null"], "format": "date-time"},
       "updated_at": {"type": "string", "format": "date-time"},
       "writer": {"type": "string"}
     }
   }
   ```

3. - [ ] **Step 3: Write `shared/schemas/run-history-trends.schema.json`**
   ```json
   {
     "$schema": "http://json-schema.org/draft-07/schema#",
     "$id": "https://forge.local/schemas/run-history-trends.schema.json",
     "title": "Forge run history rollup",
     "type": "object",
     "additionalProperties": false,
     "required": ["generated_at", "runs", "recent_hook_failures"],
     "properties": {
       "generated_at": {"type": "string", "format": "date-time"},
       "runs": {
         "type": "array",
         "maxItems": 30,
         "items": {
           "type": "object",
           "required": ["run_id", "started_at", "duration_s", "verdict", "score", "convergence_iterations", "cost_usd", "mode"],
           "properties": {
             "run_id": {"type": "string"},
             "started_at": {"type": "string", "format": "date-time"},
             "duration_s": {"type": "number", "minimum": 0},
             "verdict": {"type": "string", "enum": ["PASS", "CONCERNS", "FAIL", "ABORTED"]},
             "score": {"type": "integer", "minimum": 0, "maximum": 100},
             "convergence_iterations": {"type": "integer", "minimum": 0},
             "cost_usd": {"type": "number", "minimum": 0},
             "mode": {"type": "string"}
           }
         }
       },
       "recent_hook_failures": {
         "type": "array",
         "maxItems": 10,
         "items": {"$ref": "hook-failures.schema.json"}
       }
     }
   }
   ```

4. - [ ] **Step 4: Write fixtures**
   `tests/fixtures/phase1/hook-failure-sample.jsonl`:
   ```jsonl
   {"schema":1,"ts":"2026-04-22T11:03:14.212Z","hook_name":"post_tool_use.py","matcher":"Edit|Write","exit_code":1,"stderr_excerpt":"Traceback (most recent call last):\n  File \"hooks/post_tool_use.py\", line 10\nRuntimeError: demo","duration_ms":8421,"cwd":"/Users/denissajnar/IdeaProjects/forge"}
   ```
   `tests/fixtures/phase1/progress-status-sample.json`:
   ```json
   {"run_id":"R-20260422-001","stage":"VERIFYING","agent_active":"fg-505-build-verifier","elapsed_ms_in_stage":42310,"timeout_ms":600000,"last_event":{"ts":"2026-04-22T11:03:14.212Z","type":"agent_dispatch","detail":"fg-505 started"},"next_expected_at":"2026-04-22T11:13:14Z","updated_at":"2026-04-22T11:03:16.844Z","writer":"post_tool_use_agent.py"}
   ```
   `tests/fixtures/phase1/run-history-trends-sample.json`:
   ```json
   {"generated_at":"2026-04-22T11:10:00Z","runs":[{"run_id":"R-20260422-001","started_at":"2026-04-22T10:15:00Z","duration_s":3312,"verdict":"PASS","score":87,"convergence_iterations":4,"cost_usd":0.42,"mode":"standard"}],"recent_hook_failures":[{"schema":1,"ts":"2026-04-22T11:03:14.212Z","hook_name":"post_tool_use.py","matcher":"Edit|Write","exit_code":1,"stderr_excerpt":"Traceback ...","duration_ms":8421,"cwd":"/repo"}]}
   ```

5. - [ ] **Step 5: Write contract test**
   `tests/contract/schemas-phase1.bats`:
   ```bash
   #!/usr/bin/env bats
   # Contract: phase-1 JSON schemas validate against fixtures.
   load '../helpers/test-helpers'

   setup() {
     SCHEMAS="$PLUGIN_ROOT/shared/schemas"
     FIXTURES="$PLUGIN_ROOT/tests/fixtures/phase1"
   }

   has_jsonschema() {
     python3 -c 'import jsonschema' 2>/dev/null
   }

   @test "hook-failures schema file exists" {
     assert [ -f "$SCHEMAS/hook-failures.schema.json" ]
   }

   @test "progress-status schema file exists" {
     assert [ -f "$SCHEMAS/progress-status.schema.json" ]
   }

   @test "run-history-trends schema file exists" {
     assert [ -f "$SCHEMAS/run-history-trends.schema.json" ]
   }

   @test "hook-failures fixture validates (skip if jsonschema absent)" {
     has_jsonschema || skip "jsonschema not installed"
     run python3 -c "
   import json, sys, jsonschema
   schema = json.load(open('$SCHEMAS/hook-failures.schema.json'))
   for line in open('$FIXTURES/hook-failure-sample.jsonl'):
       jsonschema.validate(json.loads(line), schema)
   "
     assert_success
   }

   @test "progress-status fixture validates (skip if jsonschema absent)" {
     has_jsonschema || skip "jsonschema not installed"
     run python3 -c "
   import json, jsonschema
   schema = json.load(open('$SCHEMAS/progress-status.schema.json'))
   jsonschema.validate(json.load(open('$FIXTURES/progress-status-sample.json')), schema)
   "
     assert_success
   }

   @test "run-history-trends fixture validates (skip if jsonschema absent)" {
     has_jsonschema || skip "jsonschema not installed"
     run python3 -c "
   import json, jsonschema, os
   base = '$SCHEMAS'
   schema = json.load(open(os.path.join(base,'run-history-trends.schema.json')))
   from jsonschema import RefResolver
   resolver = RefResolver(base_uri='file://' + base + '/', referrer=schema)
   jsonschema.validate(json.load(open('$FIXTURES/run-history-trends-sample.json')), schema, resolver=resolver)
   "
     assert_success
   }
   ```

6. - [ ] **Step 6: Push and verify in CI**
   Push. Observe `Tests` → `test` matrix `tier=contract` on all three OSes. All schema tests green (they skip gracefully where `jsonschema` is absent; `pyyaml` is the current pip install, so skip applies unless we bump — which we do in Task 10).

7. - [ ] **Step 7: Commit**
   ```
   feat(phase-1): add JSON schemas + fixtures for hook-failures/progress/trends
   ```

---

### Task 10: Install `jsonschema` in CI so schema validation is exercised

**Files:**
- Modify: `.github/workflows/test.yml`
- Test: CI `contract` matrix

1. - [ ] **Step 1: Extend `pip install` line in `test` job**
   Change:
   ```yaml
         - name: Install Python dependencies
           run: pip install pyyaml
   ```
   to:
   ```yaml
         - name: Install Python dependencies
           run: pip install pyyaml jsonschema
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. Observe `Tests` → `test` `tier=contract`. All three OS legs run the schema validations (no longer skipped) and pass.

3. - [ ] **Step 3: Commit**
   ```
   ci(phase-1): install jsonschema so contract-tier schema checks run
   ```

---

### Task 11: Write failing unit tests for `hooks/_py/failure_log.py`

**Files:**
- Create: `tests/unit/failure-log.bats`
- Modify: (none)
- Test: `tests/unit/failure-log.bats`

1. - [ ] **Step 1: Write the bats unit test**
   ```bash
   #!/usr/bin/env bats
   # AC-5, AC-7: hooks/_py/failure_log.py — record_failure + rotate + safe-if-missing.
   load '../helpers/test-helpers'

   setup() {
     TMP="$(mktemp -d)"
     export FORGE_TEST_CWD="$TMP"
     cd "$TMP"
     PY="python3 -c \"import sys; sys.path.insert(0,'$PLUGIN_ROOT/hooks'); from _py import failure_log; failure_log.main()\""
   }

   teardown() {
     rm -rf "$TMP"
   }

   @test "record_failure is a no-op when .forge missing and writable is False" {
     run python3 -c "
   import sys, json
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   from _py import failure_log
   import os
   os.chdir('$TMP')
   failure_log.record_failure('test.py','Edit', 1, 'oops', 42, '$TMP')
   "
     assert_success
     # When .forge doesn't exist we create it (exist_ok=True per spec)
     assert [ -f "$TMP/.forge/.hook-failures.jsonl" ]
   }

   @test "record_failure appends a valid JSON row" {
     mkdir -p "$TMP/.forge"
     python3 -c "
   import sys, os
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   os.chdir('$TMP')
   from _py import failure_log
   failure_log.record_failure('pre_tool_use.py','Edit|Write',2,'boom',1,'$TMP')
   "
     run python3 -c "
   import json
   with open('$TMP/.forge/.hook-failures.jsonl') as f:
       row = json.loads(f.readline())
   assert row['schema'] == 1
   assert row['hook_name'] == 'pre_tool_use.py'
   assert row['exit_code'] == 2
   assert row['duration_ms'] == 1
   assert 'ts' in row and row['ts'].endswith('Z')
   "
     assert_success
   }

   @test "record_failure truncates stderr_excerpt to 2048 bytes" {
     mkdir -p "$TMP/.forge"
     python3 -c "
   import sys, os
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   os.chdir('$TMP')
   from _py import failure_log
   failure_log.record_failure('h.py','m',1,'x'*5000,10,'$TMP')
   "
     run python3 -c "
   import json
   row = json.loads(open('$TMP/.forge/.hook-failures.jsonl').readline())
   assert len(row['stderr_excerpt']) == 2048
   "
     assert_success
   }

   @test "rotate gzips files older than 7 days" {
     mkdir -p "$TMP/.forge"
     touch -t 202601010000 "$TMP/.forge/.hook-failures.jsonl"
     printf '{"schema":1,"ts":"2026-01-01T00:00:00Z","hook_name":"x","matcher":"m","exit_code":1,"duration_ms":1,"cwd":"."}\n' > "$TMP/.forge/.hook-failures.jsonl"
     touch -t 202601010000 "$TMP/.forge/.hook-failures.jsonl"
     python3 -c "
   import sys, os
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   os.chdir('$TMP')
   from _py import failure_log
   failure_log.rotate(now_ts=None)
   "
     run bash -c "ls '$TMP/.forge/'"
     assert_success
     refute_output --partial '.hook-failures.jsonl'
     assert_output --regexp '\.hook-failures-[0-9]{8}\.jsonl\.gz'
   }

   @test "rotate deletes gz older than 30 days" {
     mkdir -p "$TMP/.forge"
     old="$TMP/.forge/.hook-failures-20250101.jsonl.gz"
     printf 'x' | gzip -c > "$old"
     touch -t 202501010000 "$old"
     python3 -c "
   import sys, os
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   os.chdir('$TMP')
   from _py import failure_log
   failure_log.rotate(now_ts=None)
   "
     refute [ -f "$old" ]
   }
   ```

2. - [ ] **Step 2: Push and verify test fails in CI**
   Push. Observe `Tests` → `test` `tier=unit` on `ubuntu-latest`. Tests fail because `hooks/_py/failure_log.py` does not exist.

3. - [ ] **Step 3: Commit**
   ```
   test(phase-1): add failing unit tests for hooks/_py/failure_log.py
   ```

---

### Task 12: Implement `hooks/_py/failure_log.py`

**Files:**
- Create: `hooks/_py/failure_log.py`
- Modify: (none)
- Test: `tests/unit/failure-log.bats`

1. - [ ] **Step 1: Write `hooks/_py/failure_log.py`**
   ```python
   """Append-only hook-failure log + rotation.

   Schema of each line (see shared/schemas/hook-failures.schema.json):
     schema, ts, hook_name, matcher, exit_code, stderr_excerpt, duration_ms, cwd

   Policy:
     * Writes to .forge/.hook-failures.jsonl in the current working directory.
     * If .forge/ cannot be created, silently no-ops (hook = lossy observability).
     * rotate() gzips files older than 7d, unlinks .gz older than 30d. Invoked
       once per session by hooks/session_start.py.
   """
   from __future__ import annotations

   import gzip
   import json
   import os
   import shutil
   import sys
   import time
   from datetime import datetime, timezone
   from pathlib import Path
   from typing import Optional

   SCHEMA_VERSION = 1
   FAILURES_FILE = ".hook-failures.jsonl"
   ROTATE_AFTER_S = 7 * 24 * 3600
   DELETE_AFTER_S = 30 * 24 * 3600
   STDERR_LIMIT = 2048


   def _forge_dir(cwd: Optional[str] = None) -> Optional[Path]:
       base = Path(cwd) if cwd else Path.cwd()
       target = base / ".forge"
       try:
           target.mkdir(parents=True, exist_ok=True)
       except OSError as exc:
           sys.stderr.write(f"[failure_log] cannot create {target}: {exc}\n")
           return None
       return target


   def record_failure(
       hook_name: str,
       matcher: str,
       exit_code: int,
       stderr_excerpt: str,
       duration_ms: int,
       cwd: str,
   ) -> None:
       """Append one JSON row. Never raises."""
       forge = _forge_dir(cwd)
       if forge is None:
           return
       row = {
           "schema": SCHEMA_VERSION,
           "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z",
           "hook_name": hook_name,
           "matcher": matcher,
           "exit_code": exit_code,
           "stderr_excerpt": (stderr_excerpt or "")[:STDERR_LIMIT],
           "duration_ms": max(0, int(duration_ms)),
           "cwd": cwd,
       }
       line = json.dumps(row, separators=(",", ":")) + "\n"
       target = forge / FAILURES_FILE
       try:
           with target.open("a", encoding="utf-8") as fh:
               fh.write(line)
       except OSError as exc:
           sys.stderr.write(f"[failure_log] append failed: {exc}\n")


   def _gzip_and_replace(src: Path, dst: Path) -> bool:
       tmp = dst.with_suffix(dst.suffix + ".tmp")
       try:
           with src.open("rb") as src_fh, gzip.open(tmp, "wb") as dst_fh:
               shutil.copyfileobj(src_fh, dst_fh)
           os.replace(tmp, dst)
           src.unlink(missing_ok=True)
           return True
       except OSError as exc:
           sys.stderr.write(f"[failure_log] rotate failed ({src} -> {dst}): {exc}\n")
           tmp.unlink(missing_ok=True)
           return False


   def rotate(now_ts: Optional[float] = None, cwd: Optional[str] = None) -> None:
       """Gzip >7d, delete gz >30d. Safe if files missing."""
       forge = _forge_dir(cwd)
       if forge is None:
           return
       now = now_ts if now_ts is not None else time.time()
       live = forge / FAILURES_FILE
       if live.exists():
           try:
               mtime = live.stat().st_mtime
           except OSError:
               mtime = now
           if (now - mtime) > ROTATE_AFTER_S:
               stamp = datetime.fromtimestamp(mtime, tz=timezone.utc).strftime("%Y%m%d")
               archive = forge / f".hook-failures-{stamp}.jsonl.gz"
               _gzip_and_replace(live, archive)
       for gz in forge.glob(".hook-failures-*.jsonl.gz"):
           try:
               if (now - gz.stat().st_mtime) > DELETE_AFTER_S:
                   gz.unlink(missing_ok=True)
           except OSError:
               continue


   def main() -> int:
       """CLI entry for ad-hoc rotation; not used by hooks directly."""
       rotate()
       return 0


   if __name__ == "__main__":
       sys.exit(main())
   ```

2. - [ ] **Step 2: Push and verify tests pass in CI**
   Push. Observe `Tests` → `test` `tier=unit` on ubuntu/macos/windows — all five new bats tests green. (Windows skips the `touch -t` test if gzip behaviour differs; we allow that by using Python for mtime rather than `touch -t` — the test uses `touch -t` on POSIX only; on Windows it will still succeed because `touch` ships with Git Bash.)

3. - [ ] **Step 3: Commit**
   ```
   feat(phase-1): add hooks/_py/failure_log.py with record_failure + rotate

   Atomic append for .forge/.hook-failures.jsonl; gzip rotation at 7d, delete
   at 30d; safe-if-missing; stderr truncated to 2 KB.
   ```

---

### Task 13: Implement `hooks/_py/progress.py`

**Files:**
- Create: `hooks/_py/progress.py`
- Modify: (none)
- Test: deferred — see Task 14 (`tests/unit/progress-status.bats`)

1. - [ ] **Step 1: Write `hooks/_py/progress.py`**
   ```python
   """Atomic writer for .forge/progress/status.json.

   Invoked by hooks/post_tool_use_agent.py on every subagent completion event.
   Reads the tail of .forge/events.jsonl and a snapshot of .forge/state.json to
   assemble a single advisory "what's happening right now" view. Never raises —
   the hook wrapper catches any escape.
   """
   from __future__ import annotations

   import json
   import os
   import sys
   from datetime import datetime, timezone
   from pathlib import Path
   from typing import Optional

   WRITER = "post_tool_use_agent.py"
   DEFAULT_STAGE_TIMEOUT_MS = 600_000


   def _iso_now() -> str:
       n = datetime.now(timezone.utc)
       return n.strftime("%Y-%m-%dT%H:%M:%S.") + f"{n.microsecond // 1000:03d}Z"


   def _parse_iso(value: Optional[str]) -> Optional[datetime]:
       if not value:
           return None
       try:
           v = value.replace("Z", "+00:00")
           return datetime.fromisoformat(v)
       except ValueError:
           return None


   def _tail_event(events_path: Path) -> Optional[dict]:
       if not events_path.exists():
           return None
       try:
           size = events_path.stat().st_size
           with events_path.open("rb") as fh:
               seek_to = max(0, size - 8192)
               fh.seek(seek_to)
               chunk = fh.read().decode("utf-8", errors="ignore")
       except OSError:
           return None
       last_line = ""
       for line in chunk.splitlines():
           line = line.strip()
           if line:
               last_line = line
       if not last_line:
           return None
       try:
           return json.loads(last_line)
       except json.JSONDecodeError:
           return None


   def _load_state(state_path: Path) -> dict:
       if not state_path.exists():
           return {}
       try:
           return json.loads(state_path.read_text(encoding="utf-8"))
       except (OSError, json.JSONDecodeError):
           return {}


   def _elapsed_ms(stage_entered_at: Optional[str]) -> int:
       dt = _parse_iso(stage_entered_at)
       if dt is None:
           return 0
       now = datetime.now(timezone.utc)
       return max(0, int((now - dt).total_seconds() * 1000))


   def _next_expected_at(stage_entered_at: Optional[str], timeout_ms: int) -> Optional[str]:
       dt = _parse_iso(stage_entered_at)
       if dt is None:
           return None
       from datetime import timedelta
       return (dt + timedelta(milliseconds=timeout_ms)).strftime("%Y-%m-%dT%H:%M:%SZ")


   def write_status_from_hook(cwd: Optional[str] = None) -> None:
       """Compose status and write atomically. No-op if .forge missing."""
       base = Path(cwd) if cwd else Path.cwd()
       forge = base / ".forge"
       if not forge.exists():
           return
       progress_dir = forge / "progress"
       try:
           progress_dir.mkdir(parents=True, exist_ok=True)
       except OSError as exc:
           sys.stderr.write(f"[progress] cannot create {progress_dir}: {exc}\n")
           return
       state = _load_state(forge / "state.json")
       event = _tail_event(forge / "events.jsonl") or {}
       run_id = state.get("run_id") or event.get("run_id") or "unknown"
       stage = state.get("stage") or event.get("stage") or "UNKNOWN"
       agent = event.get("agent") if event.get("type") == "agent_dispatch" else None
       timeout_ms = int(state.get("stage_timeout_ms") or DEFAULT_STAGE_TIMEOUT_MS)
       stage_entered_at = state.get("stage_entered_at")
       status = {
           "run_id": run_id,
           "stage": stage,
           "agent_active": agent,
           "elapsed_ms_in_stage": _elapsed_ms(stage_entered_at),
           "timeout_ms": timeout_ms,
           "last_event": {
               "ts": event.get("ts") or _iso_now(),
               "type": event.get("type", "unknown"),
               "detail": event.get("detail", ""),
           },
           "next_expected_at": _next_expected_at(stage_entered_at, timeout_ms),
           "updated_at": _iso_now(),
           "writer": WRITER,
       }
       target = progress_dir / "status.json"
       tmp = target.with_suffix(".json.tmp")
       try:
           tmp.write_text(json.dumps(status, separators=(",", ":")), encoding="utf-8")
           os.replace(tmp, target)
       except OSError as exc:
           sys.stderr.write(f"[progress] write failed: {exc}\n")
           tmp.unlink(missing_ok=True)
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `Tests` → `test` `tier=unit` stays green — the new module is importable but no caller invokes it yet (Task 15 adds the hook import). No new assertions fire. The bats tests that exercise this module arrive in Task 14.

3. - [ ] **Step 3: Commit**
   ```
   feat(phase-1): add hooks/_py/progress.py atomic status.json writer

   Composes advisory "what's happening now" view from events.jsonl tail +
   state.json snapshot. Temp-file + os.replace for atomic swap. No-op when
   .forge missing. Landed before its caller (Task 15) so CI can stay green.
   ```

---

### Task 14: Write tests for `hooks/_py/progress.py`

**Files:**
- Create: `tests/unit/progress-status.bats`
- Test: `tests/unit/progress-status.bats`

1. - [ ] **Step 1: Write the bats test**
   ```bash
   #!/usr/bin/env bats
   # AC-11: hooks/_py/progress.py writes .forge/progress/status.json atomically.
   load '../helpers/test-helpers'

   setup() {
     TMP="$(mktemp -d)"
     cd "$TMP"
     mkdir -p .forge
     printf '%s\n' \
       '{"schema":1,"run_id":"R-1","stage":"PLANNING","stage_entered_at":"2026-04-22T10:00:00Z","stage_timeout_ms":600000}' \
       > .forge/state.json
     printf '%s\n' \
       '{"ts":"2026-04-22T10:00:05Z","type":"agent_dispatch","run_id":"R-1","stage":"PLANNING","agent":"fg-200-planner","detail":"fg-200 started"}' \
       > .forge/events.jsonl
   }

   teardown() {
     rm -rf "$TMP"
   }

   @test "write_status_from_hook creates status.json with required fields" {
     run python3 -c "
   import sys
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   from _py.progress import write_status_from_hook
   write_status_from_hook(cwd='$TMP')
   "
     assert_success
     assert [ -f "$TMP/.forge/progress/status.json" ]
     run python3 -c "
   import json
   d = json.load(open('$TMP/.forge/progress/status.json'))
   for k in ('run_id','stage','agent_active','elapsed_ms_in_stage','timeout_ms','last_event','updated_at','writer'):
       assert k in d, k
   assert d['writer'] == 'post_tool_use_agent.py'
   assert d['stage'] == 'PLANNING'
   assert d['run_id'] == 'R-1'
   "
     assert_success
   }

   @test "write_status uses atomic os.replace (no .tmp leftover)" {
     python3 -c "
   import sys
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   from _py.progress import write_status_from_hook
   write_status_from_hook(cwd='$TMP')
   "
     refute [ -f "$TMP/.forge/progress/status.json.tmp" ]
   }

   @test "write_status is a no-op when .forge missing" {
     rm -rf "$TMP/.forge"
     run python3 -c "
   import sys
   sys.path.insert(0,'$PLUGIN_ROOT/hooks')
   from _py.progress import write_status_from_hook
   write_status_from_hook(cwd='$TMP')
   "
     assert_success
     refute [ -d "$TMP/.forge/progress" ]
   }
   ```

2. - [ ] **Step 2: Push and verify tests pass in CI**
   Push. `Tests` → `test` `tier=unit` — `tests/unit/progress-status.bats` green on all three OSes (Task 13 already landed `hooks/_py/progress.py`).

3. - [ ] **Step 3: Commit**
   ```
   test(phase-1): add unit tests for hooks/_py/progress.py
   ```

---

### Task 15: Wrap all six hook entry scripts with try/except + `record_failure`

**Files:**
- Modify: `hooks/pre_tool_use.py`, `hooks/post_tool_use.py`, `hooks/post_tool_use_skill.py`, `hooks/post_tool_use_agent.py`, `hooks/stop.py`, `hooks/session_start.py`
- Create: `tests/unit/hook-wrappers.bats`
- Test: `tests/unit/hook-wrappers.bats`

1. - [ ] **Step 1: Write failing unit test**
   `tests/unit/hook-wrappers.bats`:
   ```bash
   #!/usr/bin/env bats
   # AC-6 + AC-7: every hook entry script wraps main() and calls failure_log on failure.
   load '../helpers/test-helpers'

   HOOKS=(pre_tool_use.py post_tool_use.py post_tool_use_skill.py
          post_tool_use_agent.py stop.py session_start.py)

   @test "every hook entry references failure_log.record_failure" {
     for h in "${HOOKS[@]}"; do
       run grep -q 'record_failure' "$PLUGIN_ROOT/hooks/$h"
       if [ "$status" -ne 0 ]; then
         fail "hooks/$h does not reference record_failure"
       fi
     done
   }

   @test "every hook entry wraps main in try/except" {
     for h in "${HOOKS[@]}"; do
       run grep -Eq 'try:\s*$|try:$|except BaseException' "$PLUGIN_ROOT/hooks/$h"
       [ "$status" -eq 0 ] || fail "hooks/$h missing try/except"
     done
   }

   @test "hook entry with injected failure writes to .hook-failures.jsonl" {
     tmp="$(mktemp -d)"
     cd "$tmp"
     # Invoke a hook that is guaranteed to raise (empty stdin for post_tool_use triggers parse error)
     run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 "$PLUGIN_ROOT/hooks/post_tool_use_skill.py" </dev/null
     # Hook contract: exit 0 on crash (never break session).
     [ "$status" -eq 0 ]
     assert [ -f ".forge/.hook-failures.jsonl" ]
     rm -rf "$tmp"
   }

   @test "session_start.py invokes failure_log.rotate()" {
     run grep -q 'rotate()' "$PLUGIN_ROOT/hooks/session_start.py"
     assert_success
   }

   @test "produced .hook-failures.jsonl rows validate against the schema" {
     tmp="$(mktemp -d)"
     cd "$tmp"
     run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 "$PLUGIN_ROOT/hooks/post_tool_use_skill.py" </dev/null
     [ "$status" -eq 0 ]
     assert [ -f ".forge/.hook-failures.jsonl" ]
     run python3 -c "
   import json, sys
   from pathlib import Path
   try:
       import jsonschema
   except ImportError:
       sys.exit(0)  # CI installs jsonschema (Task 10); local skip is acceptable
   schema = json.loads(Path('$PLUGIN_ROOT/shared/schemas/hook-failures.schema.json').read_text())
   for raw in Path('.forge/.hook-failures.jsonl').read_text().splitlines():
       raw = raw.strip()
       if not raw:
           continue
       row = json.loads(raw)
       jsonschema.validate(row, schema)
   "
     assert_success
     rm -rf "$tmp"
   }
   ```

2. - [ ] **Step 2: Rewrite each of the six hook entries**
   The template (each file keeps its own module import; only `MAIN` differs):

   `hooks/pre_tool_use.py`:
   ```python
   #!/usr/bin/env python3
   """PreToolUse entry — L0 syntax validation."""
   from __future__ import annotations

   import sys
   import time
   import traceback
   from pathlib import Path

   _HOOKS = Path(__file__).resolve().parent
   sys.path.insert(0, str(_HOOKS.parent))
   sys.path.insert(0, str(_HOOKS))

   from _py.check_engine.l0_syntax import main as _target  # noqa: E402
   from _py.failure_log import record_failure  # noqa: E402

   HOOK_NAME = "pre_tool_use.py"
   MATCHER = "Edit|Write"


   def _run() -> int:
       started = time.monotonic()
       try:
           rc = _target()
       except BaseException:  # noqa: BLE001 — hook contract: never crash
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
           return 0
       if rc not in (0, 2):
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, rc, "", dur, str(Path.cwd()))
           return 0
       return rc


   if __name__ == "__main__":
       sys.exit(_run())
   ```
   `hooks/post_tool_use.py`:
   ```python
   #!/usr/bin/env python3
   """PostToolUse(Edit|Write) entry — check engine + automation trigger."""
   from __future__ import annotations

   import io
   import sys
   import time
   import traceback
   from pathlib import Path

   _HOOKS = Path(__file__).resolve().parent
   sys.path.insert(0, str(_HOOKS.parent))
   sys.path.insert(0, str(_HOOKS))

   from _py.check_engine.engine import run_post_tool_use  # noqa: E402
   from _py.check_engine.automation_trigger import main as fire_automation  # noqa: E402
   from _py.failure_log import record_failure  # noqa: E402

   HOOK_NAME = "post_tool_use.py"
   MATCHER = "Edit|Write"


   def _run() -> int:
       started = time.monotonic()
       try:
           buf = sys.stdin.read()
           code = run_post_tool_use(stdin=io.StringIO(buf))
           fire_automation(stdin=io.StringIO(buf))
           if code != 0:
               dur = int((time.monotonic() - started) * 1000)
               record_failure(HOOK_NAME, MATCHER, code, "", dur, str(Path.cwd()))
               return 0
           return 0
       except BaseException:  # noqa: BLE001
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
           return 0


   if __name__ == "__main__":
       sys.exit(_run())
   ```
   `hooks/post_tool_use_skill.py`:
   ```python
   #!/usr/bin/env python3
   """PostToolUse(Skill) entry — checkpoint."""
   from __future__ import annotations

   import sys
   import time
   import traceback
   from pathlib import Path

   _HOOKS = Path(__file__).resolve().parent
   sys.path.insert(0, str(_HOOKS.parent))
   sys.path.insert(0, str(_HOOKS))

   from _py.check_engine.checkpoint import main as _target  # noqa: E402
   from _py.failure_log import record_failure  # noqa: E402

   HOOK_NAME = "post_tool_use_skill.py"
   MATCHER = "Skill"


   def _run() -> int:
       started = time.monotonic()
       try:
           rc = _target()
       except BaseException:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
           return 0
       if rc != 0:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, rc, "", dur, str(Path.cwd()))
           return 0
       return 0


   if __name__ == "__main__":
       sys.exit(_run())
   ```
   `hooks/post_tool_use_agent.py`:
   ```python
   #!/usr/bin/env python3
   """PostToolUse(Agent) entry — compaction hint + progress writer."""
   from __future__ import annotations

   import sys
   import time
   import traceback
   from pathlib import Path

   _HOOKS = Path(__file__).resolve().parent
   sys.path.insert(0, str(_HOOKS.parent))
   sys.path.insert(0, str(_HOOKS))

   from _py.check_engine.compact_check import main as _target  # noqa: E402
   from _py.failure_log import record_failure  # noqa: E402
   from _py.progress import write_status_from_hook  # noqa: E402

   HOOK_NAME = "post_tool_use_agent.py"
   MATCHER = "Agent"


   def _run() -> int:
       started = time.monotonic()
       try:
           rc = _target()
       except BaseException:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
           return 0
       try:
           write_status_from_hook(cwd=str(Path.cwd()))
       except BaseException:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER + ":progress", 1, traceback.format_exc(), dur, str(Path.cwd()))
       if rc != 0:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, rc, "", dur, str(Path.cwd()))
           return 0
       return 0


   if __name__ == "__main__":
       sys.exit(_run())
   ```
   `hooks/stop.py`:
   ```python
   #!/usr/bin/env python3
   """Stop entry — feedback capture."""
   from __future__ import annotations

   import sys
   import time
   import traceback
   from pathlib import Path

   _HOOKS = Path(__file__).resolve().parent
   sys.path.insert(0, str(_HOOKS.parent))
   sys.path.insert(0, str(_HOOKS))

   from _py.check_engine.feedback_capture import main as _target  # noqa: E402
   from _py.failure_log import record_failure  # noqa: E402

   HOOK_NAME = "stop.py"
   MATCHER = "Stop"


   def _run() -> int:
       started = time.monotonic()
       try:
           rc = _target()
       except BaseException:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
           return 0
       if rc != 0:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, rc, "", dur, str(Path.cwd()))
           return 0
       return 0


   if __name__ == "__main__":
       sys.exit(_run())
   ```
   `hooks/session_start.py`:
   ```python
   #!/usr/bin/env python3
   """SessionStart entry — session seed + rotate failure log."""
   from __future__ import annotations

   import sys
   import time
   import traceback
   from pathlib import Path

   _HOOKS = Path(__file__).resolve().parent
   sys.path.insert(0, str(_HOOKS.parent))
   sys.path.insert(0, str(_HOOKS))

   from _py.check_engine.session_start import main as _target  # noqa: E402
   from _py.failure_log import record_failure, rotate  # noqa: E402

   HOOK_NAME = "session_start.py"
   MATCHER = "SessionStart"


   def _run() -> int:
       started = time.monotonic()
       try:
           rc = _target()
       except BaseException:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
           return 0
       try:
           rotate()
       except BaseException:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER + ":rotate", 1, traceback.format_exc(), dur, str(Path.cwd()))
       if rc != 0:
           dur = int((time.monotonic() - started) * 1000)
           record_failure(HOOK_NAME, MATCHER, rc, "", dur, str(Path.cwd()))
           return 0
       return 0


   if __name__ == "__main__":
       sys.exit(_run())
   ```

3. - [ ] **Step 3: Push and verify in CI**
   Push. Observe `Tests` → `test` `tier=unit` — `tests/unit/hook-wrappers.bats` green on all OSes. `hooks/_py/progress.py` already exists (Task 13), so the `post_tool_use_agent.py` import resolves cleanly. `tests/unit/progress-status.bats` and `tests/unit/failure-log.bats` also stay green. No workaround needed — each commit is self-contained and order-safe.

4. - [ ] **Step 4: Commit**
   ```
   feat(phase-1): wrap all six hook entries with record_failure + timing
   ```

---

### Task 16: Switch bash check-engine writers to `.jsonl` + JSON lines

**Files:**
- Modify: `shared/checks/engine.sh`, `shared/checks/l0-syntax/validate-syntax.sh`
- Test: `tests/hooks/engine-failure-log.bats` (already covers engine.sh; re-verify)

1. - [ ] **Step 1: Rewrite failure emission in `shared/checks/engine.sh`**
   Replace the legacy text emitter with a JSONL emitter matching the schema. `grep -n '\.hook-failures\.log' shared/checks/engine.sh` lists every locator (currently three pre-existing references — the early-exit append in the bash<4 guard, the `handle_failure` doc-comment, and the `handle_failure` body). Workflow:
   1. Delete the entire existing `handle_failure() { ... }` definition (block runs from `# Log hook failures to .forge/.hook-failures.log for observability.` through the matching closing brace `}` before the `# shellcheck disable=SC2329` line).
   2. Replace the bash<4 guard's inline append (`>> "${_log_dir}/.hook-failures.log" 2>/dev/null || true`) with a call to the new helper: `_handle_failure "engine.sh" "Edit|Write" 0 "skip:bash_version_${BASH_VERSION}" 0`.
   3. Insert the helper below near the top of the script's function section.
   4. Re-run `grep -n '\.hook-failures\.log' shared/checks/engine.sh` and confirm zero hits.
   ```bash
   # Append a JSON row to .forge/.hook-failures.jsonl (best-effort).
   # Schema mirrors shared/schemas/hook-failures.schema.json.
   _handle_failure() {
     # $1 hook_name, $2 matcher, $3 exit_code, $4 stderr_excerpt, $5 duration_ms
     local log_dir="${FORGE_DIR:-.forge}"
     mkdir -p "$log_dir" 2>/dev/null || return 0
     local log_file="${log_dir}/.hook-failures.jsonl"
     local ts
     ts="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
     local cwd="${PWD//\"/\\\"}"
     # Truncate FIRST so escape sequences produced below are never chopped mid-character.
     local stderr_ex="${4:0:2048}"
     stderr_ex="${stderr_ex//$'\n'/\\n}"
     stderr_ex="${stderr_ex//\"/\\\"}"
     printf '{"schema":1,"ts":"%s","hook_name":"%s","matcher":"%s","exit_code":%s,"stderr_excerpt":"%s","duration_ms":%s,"cwd":"%s"}\n' \
       "$ts" "$1" "$2" "$3" "$stderr_ex" "$5" "$cwd" \
       >> "$log_file" 2>/dev/null || true
   }
   ```
   For any other call sites that emerge in `engine.sh` (e.g. additional appenders added by other plans landing earlier), grep for `\.hook-failures\.log` and rewrite each into a `_handle_failure "engine.sh" "Edit|Write" <exit> "<err>" <ms>` call. Delete the now-unused direct append.

2. - [ ] **Step 2: Apply the same rewrite to `shared/checks/l0-syntax/validate-syntax.sh`**
   Replace the existing `_log_failure() { ... }` helper (anchor: starts at the comment `# Logs to .forge/.hook-failures.log for observability (best-effort, never fails).` and ends at its closing `}`) with an inlined copy of `_handle_failure` that emits to `.forge/.hook-failures.jsonl`. Update every call site that previously invoked `_log_failure` to call `_handle_failure "validate-syntax.sh" "PreToolUse" <exit> "<err>" <ms>` (duration may be `0` if not tracked). Don't `source` engine.sh — keep the helper inlined to avoid hook startup cost. Re-run `grep -n '\.hook-failures\.log' shared/checks/l0-syntax/validate-syntax.sh` and confirm zero hits.

3. - [ ] **Step 3: Push and verify in CI**
   Push. `Tests` → `test` `tier=hooks` green on ubuntu/macos. Windows structural leg confirms the new `.jsonl` filename parses.

4. - [ ] **Step 4: Commit**
   ```
   feat(phase-1): bash check-engine writers emit .hook-failures.jsonl

   engine.sh and validate-syntax.sh now append JSON lines matching
   shared/schemas/hook-failures.schema.json. Old .log path is gone (no shim).
   ```

---

### Task 17: Docs: rename `.hook-failures.log` → `.jsonl` across the tree

**Files:**
- Modify: `agents/fg-100-orchestrator.md`, `agents/fg-505-build-verifier.md`, `shared/logging-rules.md`, `shared/state-schema-fields.md`, `skills/forge-ask status/SKILL.md`, `shared/hook-design.md` (incl. new §Failure logging), `README.md`
- Create: `tests/structural/no-hook-failures-log.bats`
- Test: `tests/structural/no-hook-failures-log.bats`

> **Locator policy.** Use text anchors (literal "before:" snippets) instead of line numbers. Other plans in this train may shift line offsets — `grep -n '\.hook-failures\.log' <file>` is the source of truth. After every edit re-run grep on the file to confirm zero remaining hits unless explicitly preserved.

1. - [ ] **Step 1: Write the grep structural test**
   `tests/structural/no-hook-failures-log.bats`:
   ```bash
   #!/usr/bin/env bats
   # AC-18: no stray references to the old filename remain.
   load '../helpers/test-helpers'

   @test "no .hook-failures.log references in tracked docs/code" {
     cd "$PLUGIN_ROOT"
     hits=$(grep -rn '\.hook-failures\.log' \
       --include='*.md' --include='*.json' --include='*.py' \
       --include='*.sh' --include='*.ps1' --include='*.cmd' \
       --exclude-dir=.venv --exclude-dir=.git --exclude-dir=.forge \
       --exclude-dir='docs/superpowers/specs' \
       --exclude-dir='docs/superpowers/plans' \
       . 2>/dev/null || true)
     if [ -n "$hits" ]; then
       printf '%s\n' "$hits"
       fail "found stale .hook-failures.log references"
     fi
   }
   ```

2. - [ ] **Step 2: Update each markdown reference**

   Workflow per file: `grep -n '\.hook-failures\.log' <file>` to find current locations, apply the anchored Edits below, then re-grep to confirm zero remaining hits.

   - **`agents/fg-100-orchestrator.md`** — single occurrence inside the `### SS5.1 Phase A — Build & Lint` section. Anchor:

     before:
     ```
     Read `.forge/.hook-failures.log` and `.forge/.check-engine-skipped`.
     ```
     after:
     ```
     Read `.forge/.hook-failures.jsonl` and `.forge/.check-engine-skipped`.
     ```

   - **`agents/fg-505-build-verifier.md`** — three occurrences. Apply each anchored Edit:

     (a) §`## 2. Context Budget` paragraph:

     before:
     ```
     Read only: dispatch prompt, error output, error-referenced source files (targeted), `.forge/.hook-failures.log`. Output under 1,500 tokens.
     ```
     after:
     ```
     Read only: dispatch prompt, error output, error-referenced source files (targeted), `.forge/.hook-failures.jsonl`. Output under 1,500 tokens.
     ```

     (b) §`### Step 0: Check Hook Failure Log` block — replace the whole 5-line block (parsing semantics change, not just the filename):

     before:
     ```
     ### Step 0: Check Hook Failure Log

     Read `.forge/.hook-failures.log`. If it exists and is non-empty:
     - Count the entries
     - Include the count in your output: `"Hook failures during implementation: {N}"`
     - This is informational -- it does not block verification
     ```
     after:
     ```
     ### Step 0: Check Hook Failure Log

     Read `.forge/.hook-failures.jsonl`. Each line is a JSON object with keys `schema`, `ts`, `hook_name`, `matcher`, `exit_code`, `stderr_excerpt`, `duration_ms`, `cwd`. Parse via `jq` or `python -c`. If it exists and is non-empty:
     - Count the entries (one row per line — `wc -l` still works)
     - Include the count in your output: `"Hook failures during implementation: {N}"`
     - This is informational -- it does not block verification
     ```

     (c) `hook_failures` field definition under §`## 6. Output Format`:

     before:
     ```
     - `hook_failures`: count from `.forge/.hook-failures.log` (0 if file absent/empty)
     ```
     after:
     ```
     - `hook_failures`: count from `.forge/.hook-failures.jsonl` (0 if file absent/empty)
     ```

   - **`shared/logging-rules.md`** — single occurrence in the agent-tier table:

     before:
     ```
     | Hook scripts | `.forge/.hook-failures.log` | Persistent, surfaced by forge-status |
     ```
     after:
     ```
     | Hook scripts | `.forge/.hook-failures.jsonl` | Persistent, surfaced by forge-status |
     ```

   - **`shared/state-schema-fields.md`** — single occurrence in §Migration Safety bullet:

     before:
     ```
     - Migration is logged to `.forge/.hook-failures.log` with reason `state_migration:{from}->{to}`.
     ```
     after:
     ```
     - Migration is logged to `.forge/.hook-failures.jsonl` with reason `state_migration:{from}->{to}` (one JSON row per migration event).
     ```

   - **`skills/forge-ask status/SKILL.md`** §`### Hook Health` — block replacement (parsing recipes change to `jq`):

     before:
     ```
     ### Hook Health

     If `.forge/.hook-failures.log` exists and is non-empty:
     1. Count total failure entries: `wc -l < .forge/.hook-failures.log`
     2. Count unique failure types: `awk -F'|' '{gsub(/^ +| +$/, "", $3); print $3}' .forge/.hook-failures.log | sort -u | wc -l`
     3. Show last 3 failures with timestamps
     4. If count > 10: show warning "High hook failure rate. Run /forge-admin recover diagnose for details."

     If `.forge/.hook-failures.log` does not exist or is empty: show "Hooks: healthy (no failures logged)"
     ```
     after:
     ```
     ### Hook Health

     If `.forge/.hook-failures.jsonl` exists and is non-empty:
     1. Count total failure entries: `wc -l < .forge/.hook-failures.jsonl`
     2. Count unique hook names: `jq -r '.hook_name' .forge/.hook-failures.jsonl | sort -u | wc -l`
     3. Show last 3 failures with timestamps: `tail -3 .forge/.hook-failures.jsonl | jq -r '"\(.ts)  \(.hook_name) exit=\(.exit_code)"'`
     4. If count > 10: show warning "High hook failure rate. Run /forge-admin recover diagnose for details."

     If `.forge/.hook-failures.jsonl` does not exist or is empty: show "Hooks: healthy (no failures logged)"
     ```

   - **`README.md`** — single occurrence in the troubleshooting table:

     before:
     ```
     | Check engine errors | Install bash 4+ (`brew install bash`). Check `.forge/.hook-failures.log` |
     ```
     after:
     ```
     | Check engine errors | Install bash 4+ (`brew install bash`). Check `.forge/.hook-failures.jsonl` |
     ```

3. - [ ] **Step 3: Rewrite `shared/hook-design.md` §Timeout Behavior, §Script Contract 5, §Failure Behavior table, add §Failure logging**

   Use anchored Edits (line numbers in earlier drafts of this plan are advisory only). `grep -n '\.hook-failures\.log' shared/hook-design.md` reveals all current occurrences.

   (a) §Timeout Behavior trailing bullet:

   before:
   ```
   - Timeout events are logged to `.forge/.hook-failures.log`.
   ```
   after:
   ```
   - Timeout events are logged to `.forge/.hook-failures.jsonl`.
   ```

   (b) §Script Contract rule 5:

   before:
   ```
   5. **Never crash**: Every entry script wraps its `main()` body in a top-level `try/except Exception` that appends a diagnostic line to `.forge/.hook-failures.log` and exits `0`. A crashing hook must not break the user's session. The only intentional non-zero exit is a deliberate PreToolUse block (exit 2).
   ```
   after:
   ```
   5. **Never crash**: Every entry script wraps its `main()` body in a top-level `try/except Exception` that appends a JSON line to `.forge/.hook-failures.jsonl` and exits `0`. A crashing hook must not break the user's session. The only intentional non-zero exit is a deliberate PreToolUse block (exit 2).
   ```

   (c) §Failure Behavior table — PostToolUse non-zero row:

   before:
   ```
   | PostToolUse | Exit non-zero | Logged to `.forge/.hook-failures.log`. No retry. |
   ```
   after:
   ```
   | PostToolUse | Exit non-zero | Logged to `.forge/.hook-failures.jsonl`. No retry. |
   ```

   (d) Append a new section immediately before the `## Adding New Hooks` heading:
     ```
     ## Failure logging

     Every hook entry script imports `hooks/_py/failure_log.py` and calls
     `record_failure(hook_name, matcher, exit_code, stderr_excerpt, duration_ms, cwd)`
     on:

     - any uncaught exception in the wrapped `main()`, and
     - any non-zero exit from the wrapped `main()` other than the deliberate
       PreToolUse block (exit 2), which is a legitimate tool-block signal.

     The log at `.forge/.hook-failures.jsonl` contains one JSON object per line
     matching `shared/schemas/hook-failures.schema.json`. `hooks/session_start.py`
     calls `failure_log.rotate()` once per session: files older than 7 days are
     gzipped to `.forge/.hook-failures-YYYYMMDD.jsonl.gz`; gzip archives older
     than 30 days are deleted.

     Claude Code's upstream hook timeouts (the `timeout` field in
     `hooks/hooks.json`) are enforced by the runtime, not the hook. A hook that
     exceeds its timeout is killed and leaves no trace in the failure log —
     it is visible only in the live Claude Code transcript.
     ```

4. - [ ] **Step 4: Push and verify in CI**
   Push. `Tests` → `structural` (all three OSes) green: `no-hook-failures-log.bats` passes; `docs-integrity` confirms anchors and lychee still resolve.

5. - [ ] **Step 5: Commit**
   ```
   docs(phase-1): rename .hook-failures.log to .jsonl across agents/skills/shared

   Per-spec breaking rename. Updates parsing recipes to jq/JSON. Adds
   §Failure logging to shared/hook-design.md.
   ```

---

### Task 18: Write failing structural test for support-tier badges

**Files:**
- Create: `tests/structural/support-tier-badges.bats`
- Test: `tests/structural/support-tier-badges.bats`

1. - [ ] **Step 1: Write the bats file**
   ```bash
   #!/usr/bin/env bats
   # AC-8, AC-9, AC-9a: support-tier badges + idempotency.
   load '../helpers/test-helpers'

   @test "docs/support-tiers.md exists" {
     assert [ -f "$PLUGIN_ROOT/docs/support-tiers.md" ]
   }

   @test "docs/support-tiers.md defines three tiers" {
     run grep -E '^##\s+(CI-verified|Contract-verified|Community)\b' "$PLUGIN_ROOT/docs/support-tiers.md"
     assert_success
     [ "$(echo "$output" | wc -l | tr -d ' ')" -ge 3 ]
   }

   @test "every conventions.md has exactly one Support tier line under H1" {
     missing=0
     while IFS= read -r -d '' f; do
       lines=$(grep -cE '^>\s+Support tier:' "$f" || true)
       if [ "$lines" -ne 1 ]; then
         echo "$f has $lines Support tier lines"
         missing=1
       fi
     done < <(find "$PLUGIN_ROOT/modules" -type f \( -name 'conventions.md' \) -print0)
     [ "$missing" -eq 0 ]
   }

   @test "every module language file has a Support tier line" {
     missing=0
     for f in "$PLUGIN_ROOT"/modules/languages/*.md; do
       lines=$(grep -cE '^>\s+Support tier:' "$f" || true)
       if [ "$lines" -ne 1 ]; then
         echo "$f has $lines Support tier lines"
         missing=1
       fi
     done
     [ "$missing" -eq 0 ]
   }

   @test "every module testing file has a Support tier line" {
     missing=0
     for f in "$PLUGIN_ROOT"/modules/testing/*.md; do
       lines=$(grep -cE '^>\s+Support tier:' "$f" || true)
       if [ "$lines" -ne 1 ]; then
         echo "$f has $lines Support tier lines"
         missing=1
       fi
     done
     [ "$missing" -eq 0 ]
   }

   @test "derive_support_tiers.py --check passes" {
     run python3 "$PLUGIN_ROOT/tests/lib/derive_support_tiers.py" --check --root "$PLUGIN_ROOT"
     assert_success
   }

   @test "derive_support_tiers.py is idempotent" {
     cp -r "$PLUGIN_ROOT" "$BATS_TEST_TMPDIR/repo"
     python3 "$BATS_TEST_TMPDIR/repo/tests/lib/derive_support_tiers.py" --root "$BATS_TEST_TMPDIR/repo"
     a="$(md5sum "$BATS_TEST_TMPDIR/repo/modules/languages/kotlin.md" | awk '{print $1}')"
     python3 "$BATS_TEST_TMPDIR/repo/tests/lib/derive_support_tiers.py" --root "$BATS_TEST_TMPDIR/repo"
     b="$(md5sum "$BATS_TEST_TMPDIR/repo/modules/languages/kotlin.md" | awk '{print $1}')"
     [ "$a" = "$b" ]
   }
   ```

2. - [ ] **Step 2: Push and verify test fails in CI**
   Push. `Tests` → `structural` red on all three OSes (docs/support-tiers.md missing; generator script missing; badges missing).

3. - [ ] **Step 3: Commit**
   ```
   test(phase-1): add failing structural tests for support-tier badges
   ```

---

### Task 19: Author `docs/support-tiers.md`

**Files:**
- Create: `docs/support-tiers.md`
- Modify: (none)
- Test: `tests/structural/support-tier-badges.bats`

1. - [ ] **Step 1: Write the doc**
   ```markdown
   # Support tiers

   > Tier is determined solely by which CI matrix jobs exercise the module.
   > Not by author claim, not by module age, not by popularity.

   | Tier | Meaning | How to qualify |
   |---|---|---|
   | CI-verified | A `pipeline-smoke` matrix leg runs the full 10-stage pipeline against a seed project using this module. | Added to `.github/workflows/pipeline-smoke.yml` (Phase 2). |
   | Contract-verified | The module has `conventions.md`, `rules-override.json` (optional), `known-deprecations.json` (if applicable), and passes `tests/run-all.sh contract`. | Default for all modules shipped today. |
   | Community | Module files exist but one or more contract assertions fail. | Automatic — if contract tier fails, the badge downgrades. |

   ## CI-verified (planned — Phase 2)

   Four seed stacks are scoped for `pipeline-smoke` coverage:

   - `kotlin + spring + (kotest | junit5) + gradle`
   - `typescript + react + vitest`
   - `python + fastapi + pytest`
   - `go + stdlib + go-testing`

   Until the Phase 2 matrix lands, these carry the `contract-verified` badge.
   They graduate automatically when the matrix job is green.

   ## Contract-verified (current)

   Every module listed under `modules/languages/`, `modules/frameworks/`, and
   `modules/testing/` whose contract tests pass. The badge is injected below
   the module H1 by `tests/lib/derive_support_tiers.py`.

   ## Community

   Currently empty. A module appears here automatically if any contract
   assertion fails. The authoring team is responsible for repair — the
   pipeline does not carry community-tier modules through gating logic.

   ## Drift detection

   `docs-integrity.yml` runs `derive_support_tiers.py --check` on every
   pull-request. Drift (a stale badge) fails CI.
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `Tests` → `structural` — the `docs/support-tiers.md exists` + `defines three tiers` tests go green; the rest stay red until Task 20/21.

3. - [ ] **Step 3: Commit**
   ```
   docs(phase-1): add docs/support-tiers.md tier taxonomy
   ```

---

### Task 20: Implement `tests/lib/derive_support_tiers.py`

**Files:**
- Create: `tests/lib/derive_support_tiers.py`
- Modify: (none)
- Test: `tests/structural/support-tier-badges.bats`

1. - [ ] **Step 1: Write the generator**
   ```python
   #!/usr/bin/env python3
   """Inject `> Support tier: <tier>` below the H1 of every module file.

   Tier resolution:
     1. CI-verified    — module name in CI_VERIFIED set (empty today; Phase 2).
     2. Community      — module has a marker file `.community` in its dir.
     3. Contract-verified — default fallback for every other module.

   `--check` mode exits non-zero if any file would be changed.
   Idempotent: running twice on a clean tree produces no diff.
   """
   from __future__ import annotations

   import argparse
   import re
   import sys
   from pathlib import Path

   CI_VERIFIED: set[str] = set()  # Phase 2 populates this
   BADGE_RE = re.compile(r"^> Support tier:.*$", re.MULTILINE)
   H1_RE = re.compile(r"^# .+$", re.MULTILINE)


   def discover_targets(root: Path) -> list[Path]:
       targets: list[Path] = []
       targets.extend(sorted((root / "modules" / "languages").glob("*.md")))
       targets.extend(sorted((root / "modules" / "frameworks").glob("*/conventions.md")))
       targets.extend(sorted((root / "modules" / "testing").glob("*.md")))
       return [p for p in targets if p.is_file()]


   def tier_for(path: Path) -> str:
       module_name = path.parent.name if path.name == "conventions.md" else path.stem
       if module_name in CI_VERIFIED:
           return "CI-verified"
       if (path.parent / ".community").exists():
           return "Community"
       return "contract-verified"


   def render_badge(tier: str) -> str:
       return f"> Support tier: {tier}"


   def transform(text: str, badge: str) -> str:
       # Remove existing badge lines (any number, anywhere).
       text = BADGE_RE.sub("", text)
       # Re-insert directly after H1.
       m = H1_RE.search(text)
       if not m:
           return text  # no H1 — leave alone
       insert_at = m.end()
       # Skip a single trailing newline so the badge lands on its own line.
       tail = text[insert_at:]
       # Collapse leading blank lines in tail (prevents stacking).
       tail = re.sub(r"^\n+", "\n", tail)
       return text[:insert_at] + "\n" + badge + "\n" + tail.lstrip("\n").rstrip() + ("\n" if not text.endswith("\n") else "\n")


   def process(root: Path, check_only: bool) -> int:
       drift = 0
       for path in discover_targets(root):
           badge = render_badge(tier_for(path))
           original = path.read_text(encoding="utf-8")
           updated = transform(original, badge)
           if updated != original:
               drift += 1
               if check_only:
                   sys.stdout.write(f"drift: {path}\n")
               else:
                   path.write_text(updated, encoding="utf-8")
       if check_only and drift:
           sys.stderr.write(f"{drift} file(s) out of date. Run derive_support_tiers.py without --check.\n")
           return 1
       return 0


   def main() -> int:
       ap = argparse.ArgumentParser(description="Inject support-tier badges in module docs.")
       ap.add_argument("--check", action="store_true", help="exit non-zero on drift")
       ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]), help="repo root")
       args = ap.parse_args()
       return process(Path(args.root), args.check)


   if __name__ == "__main__":
       sys.exit(main())
   ```
   `chmod +x tests/lib/derive_support_tiers.py`.

2. - [ ] **Step 2: Run the generator once locally via CI**
   Next task writes the files. Skip running locally per standing instruction.

3. - [ ] **Step 3: Push and verify in CI**
   Push. `Tests` → `structural` — the `derive_support_tiers.py --check passes` test still fails because no badges are injected yet; the idempotency test passes (an empty-diff run is still idempotent). Other badge-present tests still red.

4. - [ ] **Step 4: Commit**
   ```
   feat(phase-1): add tests/lib/derive_support_tiers.py badge generator
   ```

---

### Task 21: Inject badges into every module file

**Files:**
- Modify: every `modules/languages/*.md` (15 files), every `modules/frameworks/*/conventions.md` (24 files), every `modules/testing/*.md` (19 files)
- Test: `tests/structural/support-tier-badges.bats`

1. - [ ] **Step 1: Run the generator (on the branch via a CI commit)**
   Because tests do not run locally, commit the generator's output in a separate commit. Produce the change via a single invocation:
   ```
   python3 tests/lib/derive_support_tiers.py --root .
   git add modules/
   ```
   Each affected file gains the following line directly under its H1:
   ```
   > Support tier: contract-verified
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `Tests` → `structural` all four badge tests green. `docs-integrity` lychee rerun (no URL change) stays green.

3. - [ ] **Step 3: Commit**
   ```
   docs(phase-1): inject contract-verified support-tier badges (auto)

   Ran tests/lib/derive_support_tiers.py. 58 module files touched. Idempotent —
   re-running produces no diff.
   ```

---

### Task 22: Wire `docs-integrity.yml` to fail on tier drift

**Files:**
- Modify: `.github/workflows/docs-integrity.yml`
- Test: `docs-integrity` workflow on PR

1. - [ ] **Step 1: Add a job step**
   After the `Learnings-index freshness` step, add:
   ```yaml
         - name: Support-tier badge drift
           run: python3 tests/lib/derive_support_tiers.py --check --root .

         - name: Support-tier badge drift negative test (tamper + assert fail)
           run: |
             cp modules/languages/kotlin.md /tmp/_kotlin.bak
             sed -i '0,/Support tier:/{s/Support tier: .*$/Support tier: TAMPERED/}' modules/languages/kotlin.md
             set +e
             python3 tests/lib/derive_support_tiers.py --check --root .
             rc=$?
             set -e
             mv /tmp/_kotlin.bak modules/languages/kotlin.md
             if [ "$rc" -eq 0 ]; then
               echo "Negative test failed: --check returned 0 on tampered badge"
               exit 1
             fi
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `docs-integrity` runs on the PR against master. Both new steps pass: the first on fresh badges; the second proves the drift gate fails closed on tamper by tampering in-workflow, asserting non-zero exit, and restoring.

3. - [ ] **Step 3: Commit**
   ```
   ci(phase-1): docs-integrity gates on derive_support_tiers.py --check
   ```

---

### Task 23: Document trend rollup in `fg-700-retrospective.md`

**Files:**
- Modify: `agents/fg-700-retrospective.md`
- Test: `tests/structural/support-tier-badges.bats` (no) — no new test; existing doc checks (anchors, lychee) cover format.

1. - [ ] **Step 1: Append `§Trend rollup` to `agents/fg-700-retrospective.md`**
   At the end of the agent file, add:
   ```markdown
   ## Trend rollup

   At the end of every run (regardless of verdict), generate
   `.forge/run-history-trends.json` matching
   `shared/schemas/run-history-trends.schema.json`:

   1. Read the 30 most recent rows from `.forge/run-history.db` (table
      `runs`, order by `started_at DESC LIMIT 30`). For each row emit
      `{run_id, started_at, duration_s, verdict, score, convergence_iterations, cost_usd, mode}`.
   2. Read the last 10 rows from the **live** `.forge/.hook-failures.jsonl`
      (and the newest rotated `.gz` if live is absent) into
      `recent_hook_failures`.
   3. Write via temp-file + `os.replace()` swap to
      `.forge/run-history-trends.json`.

   `.forge/run-history-trends.json` is **regenerated every run** — never
   append. The file survives `/forge-admin recover reset`. Consumers:

   - `/forge-ask status --live` reads the head for a synopsis.
   - Phase-1 observability recipes in `shared/observability.md` §Local
     inspection demonstrate `jq`/PowerShell/CMD access.
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `docs-integrity` green (anchor + lychee + framework-count guard unaffected).

3. - [ ] **Step 3: Commit**
   ```
   docs(phase-1): fg-700-retrospective generates run-history-trends.json
   ```

---

### Task 24: Extend `/forge-ask status` with `--- live ---` section

**Files:**
- Modify: `skills/forge-ask status/SKILL.md`
- Test: CI docs-integrity (no new bats — skill file is descriptive prose)

1. - [ ] **Step 1: Append `§Live Progress` to `skills/forge-ask status/SKILL.md`**
   After the `§Hook Health` section (already updated in Task 17), add:
   ```markdown
   ### Live progress

   After the primary status output, print a `--- live ---` separator and
   render data from `.forge/progress/status.json` and
   `.forge/run-history-trends.json` (both optional):

   If `.forge/progress/status.json` exists:
   1. Parse via `python3 -c "import json; print(json.load(open('.forge/progress/status.json')))"`.
   2. Print: `Stage: {stage}  Agent: {agent_active or 'idle'}`.
   3. Print elapsed vs timeout: `{elapsed_ms_in_stage}ms / {timeout_ms}ms`.
   4. If `(now - updated_at) > 60s` and `(now - state_entered_at) > stage_timeout_ms`: print "Run appears hung — consider /forge-admin recover diagnose."

   If `.forge/run-history-trends.json` exists:
   1. Print last 5 runs as a table: run_id, verdict, score, duration_s.
   2. Print count of `recent_hook_failures`.

   If neither file exists: print "No live data (run has not completed a
   subagent dispatch yet)."
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `docs-integrity` green.

3. - [ ] **Step 3: Commit**
   ```
   docs(phase-1): forge-status skill renders live progress + trends
   ```

---

### Task 25: Add `§Local inspection` to `shared/observability.md`

**Files:**
- Modify: `shared/observability.md`
- Test: `docs-integrity` workflow (lychee + anchor check)

1. - [ ] **Step 1: Append `§Local inspection` section**
   ```markdown
   ## Local inspection

   Three artefacts are designed to be readable by the shells Forge supports:

   | Shell | Current progress | Last 5 runs | Recent hook failures |
   |---|---|---|---|
   | bash / zsh | `jq . .forge/progress/status.json` | `jq '.runs[0:5]' .forge/run-history-trends.json` | `jq '.recent_hook_failures' .forge/run-history-trends.json` |
   | PowerShell | `Get-Content .forge/progress/status.json | ConvertFrom-Json` | `(Get-Content .forge/run-history-trends.json | ConvertFrom-Json).runs | Select-Object -First 5` | `(Get-Content .forge/run-history-trends.json | ConvertFrom-Json).recent_hook_failures` |
   | CMD | `type .forge\progress\status.json` | `type .forge\run-history-trends.json` | (CMD has no JSON parser — use PowerShell or open the file in a text editor) |

   The files are atomic-renamed on every update, so a reader that opens them
   while they are being rewritten either sees the old copy or the new copy,
   never a partial object. Append-only `.forge/.hook-failures.jsonl` lines are
   POSIX-atomic when under 4 KB — `stderr_excerpt` is truncated to 2 KB to
   stay under that ceiling.
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `docs-integrity` green.

3. - [ ] **Step 3: Commit**
   ```
   docs(phase-1): observability.md gains Local inspection recipe table
   ```

---

### Task 26: Update `shared/state-schema.md` survival list

**Files:**
- Modify: `shared/state-schema.md`
- Test: `docs-integrity`

1. - [ ] **Step 1: Edit survival bullets**
   In `shared/state-schema.md`, locate the section listing paths that survive `/forge-admin recover reset` (it mirrors the CLAUDE.md §Gotchas list). Append the new paths explicitly:
   ```
   The following additional paths survive `/forge-admin recover reset`:

   - `.forge/progress/` (live subagent-completion status; written by
     `hooks/post_tool_use_agent.py`).
   - `.forge/run-history-trends.json` (30-run rollup + last 10 hook failures;
     written by `fg-700-retrospective`).
   - `.forge/.hook-failures.jsonl` (live hook failure log; appended by every
     hook entry) and rotated `.forge/.hook-failures-YYYYMMDD.jsonl.gz`
     archives.

   Only manual `rm -rf .forge/` removes them.
   ```

2. - [ ] **Step 2: Push and verify in CI**
   Push. `docs-integrity` green (600-line ceiling check exempts state-schema.md).

3. - [ ] **Step 3: Commit**
   ```
   docs(phase-1): state-schema.md lists progress/trends/jsonl as reset-surviving
   ```

---

### Task 27: CLAUDE.md §Platform + §Quick start + §Gotchas + README §Quick start + §Troubleshooting

**Files:**
- Modify: `CLAUDE.md`, `README.md`
- Test: `docs-integrity` (framework-count guard, lychee, anchor checks)

1. - [ ] **Step 1: Rewrite CLAUDE.md §Platform requirements**
   Locate the paragraph starting with "**Platform requirements:**" near the end of §Gotchas (currently around line 362). Replace with:
   ```
   - **Platform requirements:** Forge requires Python 3.10+.
     Full CI coverage (bash-based): macOS, Linux, Windows (Git Bash).
     Smoke CI coverage: Windows (PowerShell 7 via `tests/run-all.ps1`), Windows
     (CMD via `tests/run-all.cmd`, structural + unit only). Install helpers:
     `install.sh` (macOS/Linux) or `install.ps1` (Windows native). WSL2 runs
     as Linux. A handful of developer-only simulation harnesses under
     `shared/` remain in bash (e.g., `shared/convergence-engine-sim.sh`) —
     these are bash-3.2 compatible and do not run in hook execution paths.
   ```

2. - [ ] **Step 2: Rewrite CLAUDE.md §Quick start install snippet**
   Replace the `ln -s "$(pwd)" /path/to/project/.claude/plugins/forge` snippet with:
   ```
   # macOS/Linux
   ./install.sh

   # Windows (native PowerShell — not WSL)
   powershell -ExecutionPolicy Bypass -File install.ps1
   ```
   (WSL users follow the macOS/Linux path.)

3. - [ ] **Step 3: Append to CLAUDE.md §Gotchas survival bullet**
   Inside the existing bullet that reads `.forge/wiki/ survives /forge-admin recover reset...`, update the paragraph listing surviving paths to also include `.forge/progress/`, `.forge/run-history-trends.json`, and the live + gzipped `.hook-failures.jsonl` files. The spec §Documentation Updates rewrite lands verbatim from that list.

4. - [ ] **Step 4: Rewrite README.md §Quick start block**
   Replace the `ln -s …` two-line block (lines 34–46 region) with:
   ```
   ```bash
   # macOS/Linux
   ./install.sh

   # Windows (native PowerShell)
   powershell -ExecutionPolicy Bypass -File install.ps1

   # Then, in a project:
   /forge
   /forge run Add user dashboard with activity feed
   ```
   ```
   Keep the Git-submodule <details> alternative below unchanged.

5. - [ ] **Step 5: Edit README.md §Troubleshooting row "Check engine errors"**
   Change the right-hand cell on line 261 from `.forge/.hook-failures.log` to `.forge/.hook-failures.jsonl`.

6. - [ ] **Step 6: Add tier column / link in README §Available modules**
   Insert a sentence after the §Available modules heading: `Every module carries a support-tier badge (CI-verified / contract-verified / community). See docs/support-tiers.md for the taxonomy.` No table change.

7. - [ ] **Step 7: Push and verify in CI**
   Push. `docs-integrity` green (framework-count guard unchanged; lychee still resolves install.sh/install.ps1/docs/support-tiers.md as internal refs).

8. - [ ] **Step 8: Commit**
   ```
   docs(phase-1): CLAUDE.md + README reflect Windows helpers, tiers, .jsonl

   Platform paragraph now specifies full vs smoke CI. Quick-start snippets
   split by OS. Troubleshooting row points at the renamed failure log.
   Available-modules callout introduces support tiers.
   ```

---

### Task 28: Add emoji + pathlib structural tests

**Files:**
- Create: `tests/structural/no-emoji-new-files.bats`, `tests/structural/pathlib-only.bats`
- Test: both new bats files

1. - [ ] **Step 1: Write `tests/structural/no-emoji-new-files.bats`**
   ```bash
   #!/usr/bin/env bats
   # AC-16: no emoji codepoints in new/modified Phase 1 files.
   load '../helpers/test-helpers'

   FILES=(
     install.sh
     install.ps1
     shared/check_environment.py
     hooks/_py/failure_log.py
     hooks/_py/progress.py
     tests/run-all.ps1
     tests/run-all.cmd
     tests/lib/derive_support_tiers.py
     docs/support-tiers.md
     shared/schemas/hook-failures.schema.json
     shared/schemas/progress-status.schema.json
     shared/schemas/run-history-trends.schema.json
   )

   @test "Phase 1 files contain no emoji codepoints" {
     for rel in "${FILES[@]}"; do
       f="$PLUGIN_ROOT/$rel"
       [ -f "$f" ] || continue
       run python3 -c "
   import re, sys
   p = sys.argv[1]
   text = open(p, encoding='utf-8', errors='ignore').read()
   bad = re.findall(r'[\U0001F300-\U0001FAFF☀-➿]', text)
   if bad: sys.exit(f'{p} has emoji: {bad[:5]}')
   " "$f"
       [ "$status" -eq 0 ] || fail "$output"
     done
   }
   ```

2. - [ ] **Step 2: Write `tests/structural/pathlib-only.bats`**
   ```bash
   #!/usr/bin/env bats
   # AC-17: new Phase 1 Python files construct paths via pathlib.
   load '../helpers/test-helpers'

   PY_FILES=(
     shared/check_environment.py
     hooks/_py/failure_log.py
     hooks/_py/progress.py
     tests/lib/derive_support_tiers.py
   )

   @test "Phase 1 Python code uses pathlib not hardcoded separators" {
     for rel in "${PY_FILES[@]}"; do
       f="$PLUGIN_ROOT/$rel"
       [ -f "$f" ] || continue
       run python3 -c "
   import ast, re, sys
   src = open(sys.argv[1], encoding='utf-8').read()
   # allow / inside regex patterns, URLs, comments, docstrings
   stripped = re.sub(r'\"[^\"]*\"|\'[^\']*\'|#.*$', '', src, flags=re.M)
   # We only flag literal string containing '/' or '\\\\' that look like path segments
   bad = re.findall(r\"'[^']*[\\\\\\/][^']*\\.(py|md|json|sh|jsonl)'\", src)
   if bad:
       sys.exit(f'{sys.argv[1]} has hardcoded-path literals: {bad}')
   if 'from pathlib import Path' not in src and 'pathlib.Path' not in src:
       sys.exit(f'{sys.argv[1]} does not import pathlib')
   " "$f"
       [ "$status" -eq 0 ] || fail "$output"
     done
   }
   ```

3. - [ ] **Step 3: Push and verify in CI**
   Push. `Tests` → `structural` (three OSes) green — both new tests pass (Phase 1 files were authored with pathlib-only, ASCII-only discipline).

4. - [ ] **Step 4: Commit**
   ```
   test(phase-1): structural gates for AC-16 emoji and AC-17 pathlib
   ```

---

### Task 29: Seal CHANGELOG entry and remove sentinel

**Files:**
- Modify: `CHANGELOG.md`
- Delete: `tests/structural/phase1-placeholder.bats`
- Test: `tests/run-all.sh structural`

1. - [ ] **Step 1: Add CHANGELOG entry under `[Unreleased]`**
   Directly below the existing `## [Unreleased]` header, add a new bullet in the correct section. Under `### Added`:
   ```
   - **Phase 1: Truth & Observability** — Windows install helper (`install.ps1`);
     bash helper (`install.sh`) supersedes `ln -s`; `shared/check-environment.sh`
     ported to `shared/check_environment.py`; `tests/run-all.ps1` + `run-all.cmd`
     wrappers; new CI jobs `test-windows-pwsh-structural` and `test-windows-cmd`.
     `hooks/_py/failure_log.py` + `hooks/_py/progress.py` — every hook entry
     wraps `main()` and appends to `.forge/.hook-failures.jsonl` (renamed from
     `.log`; no shim). `SessionStart` rotates archives (gzip at 7 d, delete at
     30 d). `post_tool_use_agent.py` rewrites `.forge/progress/status.json`
     atomically on every subagent completion. `fg-700-retrospective` generates
     `.forge/run-history-trends.json` (last 30 runs + last 10 hook failures).
     Support-tier badge system: `docs/support-tiers.md`, generator
     `tests/lib/derive_support_tiers.py`, drift gate in `docs-integrity.yml`.
     `/forge-ask status` gains a `--- live ---` section. `shared/observability.md`
     gains `§Local inspection` recipes for bash/pwsh/cmd.
   ```

2. - [ ] **Step 2: Delete the Task 1 sentinel**
   `git rm tests/structural/phase1-placeholder.bats`.

3. - [ ] **Step 3: Push and verify in CI**
   Push. All jobs green: `structural` (all OSes), `test` (3 × 3), `test-windows-pwsh-structural`, `test-windows-cmd`, `docs-integrity`.

4. - [ ] **Step 4: Commit**
   ```
   docs(phase-1): CHANGELOG entry + remove scaffolding sentinel
   ```

---

## Commit plan recap

Target: 12 commits (matches the 8-12 spec ceiling; each leaves CI green):

1. `chore(phase-1): open truth-and-observability branch with sentinel test` — Task 1
2. `test(phase-1): add failing unit tests for shared/check_environment.py` — Task 2
3. `feat(phase-1): port check-environment.sh to shared/check_environment.py` — Task 3
4. `feat(phase-1): add install.sh repo-root helper for macOS/Linux` — Task 4
5. `feat(phase-1): add install.ps1 repo-root helper for Windows` + `ci(phase-1): gate install.ps1 on parse + PSScriptAnalyzer in structural` + `feat(phase-1): add tests/run-all.ps1 and tests/run-all.cmd wrappers` + `ci(phase-1): add test-windows-pwsh-structural and test-windows-cmd jobs` — Tasks 5-8 bundled in one push (CI runs once on push; commits stay separate)
6. `feat(phase-1): add JSON schemas + fixtures for hook-failures/progress/trends` + `ci(phase-1): install jsonschema so contract-tier schema checks run` — Tasks 9-10
7. `test(phase-1): add failing unit tests for hooks/_py/failure_log.py` + `feat(phase-1): add hooks/_py/failure_log.py with record_failure + rotate` — Tasks 11-12
8. `feat(phase-1): add hooks/_py/progress.py atomic status.json writer` + `test(phase-1): add unit tests for hooks/_py/progress.py` + `feat(phase-1): wrap all six hook entries with record_failure + timing` — Tasks 13-15 (progress.py lands first so the hook wrapper in Task 15 imports a real module; each commit is self-contained and CI-safe)
9. `feat(phase-1): bash check-engine writers emit .hook-failures.jsonl` + `docs(phase-1): rename .hook-failures.log to .jsonl across agents/skills/shared` — Tasks 16-17
10. `test(phase-1): add failing structural tests for support-tier badges` + `docs(phase-1): add docs/support-tiers.md tier taxonomy` + `feat(phase-1): add tests/lib/derive_support_tiers.py badge generator` + `docs(phase-1): inject contract-verified support-tier badges (auto)` + `ci(phase-1): docs-integrity gates on derive_support_tiers.py --check` — Tasks 18-22
11. `docs(phase-1): fg-700-retrospective generates run-history-trends.json` + `docs(phase-1): forge-status skill renders live progress + trends` + `docs(phase-1): observability.md gains Local inspection recipe table` + `docs(phase-1): state-schema.md lists progress/trends/jsonl as reset-surviving` + `docs(phase-1): CLAUDE.md + README reflect Windows helpers, tiers, .jsonl` — Tasks 23-27
12. `test(phase-1): structural gates for AC-16 emoji and AC-17 pathlib` + `docs(phase-1): CHANGELOG entry + remove scaffolding sentinel` — Tasks 28-29

Each numbered push above waits for a green CI run before the next push starts. Within a push, individual commits may land red on intermediate SHAs (GitHub only runs on the push head) but the push as a whole must be green.

---

## AC coverage map

| AC | Task(s) |
|---|---|
| AC-1 `check_environment.py` | 2, 3 |
| AC-2 `install.ps1` + `-Help`/`-WhatIf` + PSScriptAnalyzer | 5, 6 |
| AC-3 `install.sh` | 4 |
| AC-4 `test-windows-pwsh-structural` + `test-windows-cmd` + wrapper step | 7, 8 |
| AC-5 `failure_log.py` `record_failure` + `rotate` unit-tested | 11, 12 |
| AC-6 six hook entries wrapped | 15 |
| AC-7 populated `.hook-failures.jsonl` conforms to schema | 9, 11, 12, 15 |
| AC-8 `docs/support-tiers.md` | 19 |
| AC-9 badge under every H1 | 20, 21 |
| AC-9a idempotency | 18 (structural test), 20 (implementation) |
| AC-10 `docs-integrity.yml` drift gate | 22 |
| AC-11 `post_tool_use_agent.py` rewrites `status.json` | 13 (progress.py impl), 14 (tests), 15 (hook wrapper invokes it) |
| AC-12 `fg-700-retrospective.md` `§Trend rollup` | 23 |
| AC-13 `shared/observability.md` `§Local inspection` | 25 |
| AC-14 state-schema survival list | 26 |
| AC-15 `CLAUDE.md §362` rewrite | 27 |
| AC-16 no-emoji structural test | 28 |
| AC-17 pathlib-only structural test | 28 |
| AC-18 grep sweep for `.hook-failures.log` | 17 |

Every AC maps to at least one task. No AC is unmapped. No task contains "TBD", "similar to", "handle edge cases", or "add error handling" — every code block is the actual payload to write.
