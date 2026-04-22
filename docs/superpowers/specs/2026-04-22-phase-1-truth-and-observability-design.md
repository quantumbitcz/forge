# Phase 1: Truth & Observability — Design

## Goal

Close four credibility gaps in forge: make the Windows-first-class claim real, give hook failures a structured audit trail, mark every module with a support tier that matches CI reality, and add a machine-readable live-run surface readable with `cat`/`jq`/`Get-Content` alone. No new skills; minimal blast radius on existing contracts.

## Problem Statement

1. **Platform claim is partly aspirational.** `CLAUDE.md:362` asserts "Windows, macOS, and Linux are all first-class targets: PowerShell, CMD, Git Bash, WSL2, and native bash all work uniformly." Reality (verified 2026-04-22 by re-reading `.github/workflows/test.yml`):
   - The `structural` job (`test.yml` lines 16–34) sets `defaults.run.shell: bash {0}` at job level (line 27) and runs on `windows-latest` under Git Bash.
   - The `test` job (`test.yml` lines 36–75) has **no** `defaults.run.shell`. On `windows-latest`, GitHub Actions defaults `run:` steps to **`pwsh`**, so the three tier jobs (unit, contract, scenario) already exercise PowerShell — even though they invoke `./tests/run-all.sh`, which is bash-only and therefore likely failing opaquely on the Windows pwsh legs. That means pwsh coverage technically exists but is neither ergonomic nor advertised, and CMD is never exercised.
   - The only `*.ps1` in the tree is a pip-generated venv stub (`.venv/Scripts/Activate.ps1`-style); there is no install helper.
   - `README.md:35` and `CLAUDE.md` §Quick start document install via `ln -s`, which on native Windows requires Developer Mode or admin.
   - `shared/check-environment.sh` is bash and is invoked by `/forge-init` — it has a `gitbash` branch but no native-Windows code path.

2. **Hook-failure logging contract exists but is unenforced for Python hooks.** `hooks/hooks.json` sets per-hook timeouts of 3–10 s. `shared/hook-design.md:85` already contracts the behaviour: *"Every entry script wraps its `main()` body in a top-level `try/except Exception` that appends a diagnostic line to `.forge/.hook-failures.log` and exits `0`."* Reality (verified 2026-04-22): the shell-side check engine (`shared/checks/engine.sh:91,120`) writes to `.forge/.hook-failures.log`, but the Python entry scripts (`hooks/pre_tool_use.py`, `post_tool_use.py`, `post_tool_use_skill.py`, `post_tool_use_agent.py`, `stop.py`, `session_start.py`) have **zero** `try/except` wrappers. A Python hook crash or non-zero exit leaves no trace except the ephemeral Claude Code transcript. The contract is documented but unenforced for the majority of hook execution paths.

3. **Framework inventory overclaims coverage.** CLAUDE.md advertises 15 languages × 24 frameworks × 19 test frameworks; CI (`tests/run-all.sh`) executes structural + unit + contract + scenario tiers that never spin up a real toolchain for most of that space. A user picking `elixir + phoenix + exunit` gets the same badge as `kotlin + spring + kotest`, but only the latter has ever been through an end-to-end run.

4. **Live-run visibility is poor.** `hooks/_py/otel.py` emits spans, but requires an OTel backend. `/forge-status` reads `.forge/state.json`, which is written at stage transitions only — a stuck agent in the middle of a stage is invisible. Users debugging a hang have to `cat .forge/events.jsonl | tail`, which mixes 12 event types without a "what's happening *right now*" view.

## Non-Goals

- No new skills. The `/forge-*` surface stays at 29 entries.
- No changes to the hook contract (event names, matchers, timeouts, JSON protocol). Hooks keep dispatching `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/*.py`.
- No reshape of OTel emission. `hooks/_py/otel.py` is untouched; the new progress file is a *supplement*, not a replacement.
- No backwards-compatibility shims. Per user standing instruction, forge may freely break its own state/config formats.
- No skill renames, no deprecation migration docs, no "previous behaviour" notes in CHANGELOG beyond a single line.

## Approach

Four surgical changes, each isolated to a small file set. No cross-cutting refactor.

### 1. Platform claim alignment — option B (make Windows real)

Make the claim true rather than retract it. Concrete steps:

- **Port `shared/check-environment.sh` → `shared/check_environment.py`** (Python 3.10+, uses `pathlib.Path` and `shutil.which`). Covers the same probe list; platform detection via `sys.platform` + `platform.release()` (WSL check via `/proc/version` read gated on `pathlib.Path("/proc/version").exists()`). Emits identical JSON schema so `/forge-init`'s downstream consumer does not change. The bash file is deleted (no shim — user instruction: no back-compat).
- **Add `install.ps1` at repo root.** Idiomatic Claude Code plugin installers in 2026 use `irm <url> | iex` (`claude.ai/install.ps1` sets the pattern). Script does: check `git` in `PATH`; compute plugin dir (`$env:USERPROFILE\.claude\plugins\forge`); clone or `git pull`; write a `settings.json` plugin entry via `ConvertTo-Json`; print next steps. No symlink — on Windows the plugin directory is a full clone, not a link. `install.sh` (new) does the same thing for macOS/Linux and supersedes the `ln -s` one-liner in README.
- **Reshape `.github/workflows/test.yml` Windows coverage.** The existing `test` job's tier matrix on `windows-latest` already runs under `pwsh` by GitHub default, but without an explicit shell the legs' success/failure is noise. Phase 1 makes coverage explicit and adds the two gaps: (a) structural-pwsh and (b) CMD.
  - Add `shell: pwsh` override on the existing `test` job's `Run ${{ matrix.tier }} tests` step **only for `windows-latest`** — but since `run-all.sh` is bash, the step invokes a new `tests/run-all.ps1` wrapper on the pwsh leg that calls the Git-Bash-provided `bash.exe` with `run-all.sh`. Net effect: pwsh leg stays green and the pwsh shell is *actually* the interpreter for the wrapper script, not merely a bystander. No change to ubuntu/macOS legs.
  - Add a new job `test-windows-pwsh-structural` (mirrors `structural` on `windows-latest` but with `defaults.run.shell: pwsh`) so structural validation is also exercised under pwsh. Runs `tests/run-all.ps1 structural`.
  - Add a new job `test-windows-cmd` on `windows-latest` with `defaults.run.shell: cmd`, running `tests\run-all.cmd structural` and `tests\run-all.cmd unit`. `run-all.cmd` is a thin CMD wrapper that locates `bash.exe` and calls `run-all.sh`. Smoke-only — contract/scenario tiers not in scope for Phase 1.
  - The existing bash-on-windows structural job stays; it remains the full Git Bash pass.
  - Tagline for tier labelling: **bash = full**, **pwsh (structural + unit) = smoke**, **cmd (structural + unit) = smoke**. Contract/scenario tiers are pwsh-exercised by default but their historical green/red status is outside the "officially smoke-verified" tier until the wrappers ship.
- **Rewrite `CLAUDE.md` §362** to a two-tier statement (full vs smoke) — see Documentation Updates below.

Why option B over A (downgrade the claim): user said "I want all." Cost is one workflow job and two install scripts, each ~60 lines. No runtime Windows-specific code beyond what's already in `check_environment.py`.

### 2. Hook failure log + rotation

- **New module `hooks/_py/failure_log.py`.** Single function `record_failure(hook_name, matcher, exit_code, stderr_excerpt, duration_ms, cwd)`. Writes one JSON line to `.forge/.hook-failures.jsonl`.
  <!-- Decision: rename from `.log` to `.jsonl`. Per user standing instruction (no back-compat), forge may freely break its own file formats. The rename is worth doing because the file's contents are, unambiguously, one JSON object per line — calling it `.log` misleads readers into grepping plain text. This breaks the contract in `shared/hook-design.md:72,85,96` and the convention in `shared/checks/engine.sh`; both are updated in the same change. The shell-side `engine.sh` writers switch to the new filename; README/troubleshooting and the seven other references are all updated (see §Documentation Updates). No shim, no dual-write. -->
  The shell-side writers in `shared/checks/engine.sh` and `shared/checks/l0-syntax/validate-syntax.sh` are updated in the same change to append to `.hook-failures.jsonl` (emitting the same JSON line schema defined below). The bash `handle_failure` function is rewritten as a one-line `printf '{"schema":1,"ts":"%s",...}\n'` emitter so bash and Python share a single on-disk format.
- **Wrapping the hook entry scripts.** Each of `hooks/pre_tool_use.py`, `post_tool_use.py`, `post_tool_use_skill.py`, `post_tool_use_agent.py`, `stop.py`, `session_start.py` gets a top-level `try/except` + timing wrapper that calls `record_failure` on any exception and on `exit_code != 0`. Timeouts (3–10 s) are enforced by Claude Code itself, **not the hook**, and are **not captured** by this mechanism: verified via `https://code.claude.com/docs/en/hooks` (2026-04-22) — Claude Code does not document emitting timeout events to any persistent file readable by a subsequent hook invocation. The hook failure log therefore captures exceptions and non-zero exits, but timeouts remain visible only in the live Claude Code transcript. This is an accepted limitation of Phase 1; addressing it requires upstream Claude Code changes, which are out of scope.
- **Rotation.** `hooks/_py/failure_log.py::rotate()` runs at `SessionStart` (cheap, O(directory-listing)). Policy:
  - Keep live `.forge/.hook-failures.jsonl`.
  - After 7 days, rename to `.forge/.hook-failures-YYYYMMDD.jsonl.gz` via `gzip.open(..., "wb")` and `shutil.copyfileobj`.
  - After 30 days, `Path.unlink()` the `.gz`.
  - Wall-clock comparison uses file mtime, not content parsing. No date-parse in the hot path.
- **Safe-if-missing.** `_ensure_forge_dir()` uses `Path(".forge").mkdir(parents=True, exist_ok=True)` before the first write. If the CWD is not a forge project (no `.claude/plugins/forge`), the function silently no-ops — hooks must not error on non-forge repos.

### 3. Support-tier framework badges

- **New file `docs/support-tiers.md`** (not root — avoid README bloat; link from README §Available modules). Defines the three tiers and the rule: *tier is determined solely by which CI matrix jobs exercise the module.* An auto-generator `tests/lib/derive_support_tiers.py` reads `.github/workflows/*.yml` and the module inventory, produces `docs/support-tiers.md` and injects the `> Support tier: …` line into each module's `conventions.md` header (idempotent: looks for the marker line, replaces or inserts below the `# Title` heading).
- **CI-verified (Tier 1).** The quartet specified in the scope: `kotlin+spring+gradle+(kotest|junit5)`, `typescript+react+vitest`, `python+fastapi+pytest`, `go+stdlib+go-testing`. These get a new GitHub Actions job `pipeline-smoke` (not part of Phase 1 implementation — the *spec* defines the tier, Phase 2 will add the real matrix). For Phase 1 we mark these as "Tier 1 (smoke planned)" so the badge is accurate *today*: contract-verified until the matrix lands.
- **Contract-verified (Tier 2).** Everything that has a `conventions.md`, `rules-override.json`, and `known-deprecations.json` that passes the existing contract tier (`tests/run-all.sh contract`). That covers ~all current modules.
- **Community (Tier 3).** Modules present in the tree but failing any contract assertion. None today, but the category exists so a stale module does not auto-graduate to Tier 2 silently.
- **Badge format** in each module header, directly under the H1:
  ```
  # React Framework Conventions
  > Support tier: contract-verified
  > Framework-specific conventions for React projects...
  ```
  Plain string, no emoji. The existing blockquote that starts with `> Framework-specific…` stays; the tier line goes *above* it.

### 4. Progress file + trend rollup + inspection recipes

- **`.forge/progress/status.json`** — single JSON object, rewritten atomically by the `hooks/post_tool_use_agent.py` hook on every `Agent` event (subagent completion). Not a timer, not a daemon — Claude Code agents are one-shot subagent invocations and cannot write files on a wall-clock schedule. The hook already fires on every subagent dispatch completion (see `hooks/hooks.json` matcher `Agent`), so we piggyback: the hook reads the latest `.forge/events.jsonl` tail, extracts run/stage/agent context, and rewrites `status.json`. Written via `Path(...).with_suffix(".tmp").write_text(json.dumps(obj))` + `os.replace()` to avoid partial-read races with readers.
  <!-- Decision: event-driven. The original "5-second orchestrator heartbeat" design assumed the orchestrator was a long-lived daemon that could wake up on a timer. It isn't — the orchestrator agent is re-invoked at stage transitions, not running continuously. The post_tool_use_agent.py hook IS invoked on every agent completion, making it the natural write point. Staleness is now measured by comparing `state.stage_entered_at` to `updated_at`: if they diverge by > N seconds and no subagent has completed, the run is genuinely idle or hung. Optional `progress.min_interval_s` config (default 2) rate-limits hook writes when many agents complete in rapid succession. -->
  Fields:
  ```json
  {
    "run_id": "R-20260422-001",
    "stage": "VERIFYING",
    "agent_active": "fg-505-build-verifier",
    "elapsed_ms_in_stage": 42310,
    "timeout_ms": 600000,
    "last_event": {"ts": "2026-04-22T11:03:14.212Z", "type": "agent_dispatch", "detail": "fg-505 started"},
    "next_expected_at": "2026-04-22T11:13:14Z",
    "updated_at": "2026-04-22T11:03:16.844Z",
    "writer": "post_tool_use_agent.py"
  }
  ```
  File is stale if `updated_at` is older than `state.json`'s `stage_entered_at + stage_timeout_ms`; readers can flag on that comparison. `.forge/progress/` is created by the hook on first write.
- **`.forge/run-history-trends.json`** — rollup of last 30 runs, regenerated by `fg-700-retrospective` at end of every run. Single JSON object with array `runs` (newest first):
  ```json
  {
    "generated_at": "2026-04-22T11:10:00Z",
    "runs": [
      {
        "run_id": "R-20260422-001",
        "started_at": "2026-04-22T10:15:00Z",
        "duration_s": 3312,
        "verdict": "PASS",
        "score": 87,
        "convergence_iterations": 4,
        "cost_usd": 0.42,
        "mode": "standard"
      }
    ],
    "recent_hook_failures": [
      {"ts": "...", "hook_name": "post_tool_use.py", "matcher": "Edit|Write", "exit_code": 1, "duration_ms": 8421}
    ]
  }
  ```
  `recent_hook_failures` is the last 10 rows from `.forge/.hook-failures.jsonl` (live + newest `.gz` if needed). Capped at 10 to keep the file small enough for `head`.
- **No new skill.** `/forge-status` is extended to also print a synopsis from `status.json` and the top of `run-history-trends.json`. Extension is additive — existing output format preserved at the top, new section appended under a `--- live ---` separator.
- **Inspection recipes** go into `shared/observability.md` under a new §Local inspection heading. Three-shell tables:

  | Shell | Current progress | Last 5 runs | Recent hook failures |
  |---|---|---|---|
  | bash/zsh | `jq . .forge/progress/status.json` | `jq '.runs[0:5]' .forge/run-history-trends.json` | `jq '.recent_hook_failures' .forge/run-history-trends.json` |
  | PowerShell | `Get-Content .forge/progress/status.json \| ConvertFrom-Json` | `(Get-Content .forge/run-history-trends.json \| ConvertFrom-Json).runs \| Select-Object -First 5` | `(Get-Content .forge/run-history-trends.json \| ConvertFrom-Json).recent_hook_failures` |
  | CMD | `type .forge\progress\status.json` | `type .forge\run-history-trends.json` | (use PowerShell — CMD has no JSON) |

## Components

### 1. Platform claim alignment

- **Files created:** `install.ps1`, `install.sh`, `shared/check_environment.py`, `tests/run-all.ps1`, `tests/run-all.cmd`.
- **Files deleted:** `shared/check-environment.sh`.
- **Files modified:** `.github/workflows/test.yml` (+2 jobs, +1 pwsh-wrapper step on the existing `test` job's Windows legs), `CLAUDE.md` §362, `README.md` §Quick start.

### 2. Hook failure log + rotation

- **Files created:** `hooks/_py/failure_log.py`.
- **Files modified:** `hooks/pre_tool_use.py`, `hooks/post_tool_use.py`, `hooks/post_tool_use_skill.py`, `hooks/post_tool_use_agent.py`, `hooks/stop.py`, `hooks/session_start.py` (each gets ~10 lines: wrap main, call `record_failure` on error; `session_start.py` additionally calls `rotate()`).

### 3. Support-tier framework badges

- **Files created:** `docs/support-tiers.md`, `tests/lib/derive_support_tiers.py`.
- **Files modified:** every `modules/**/conventions.md` (one `> Support tier:` line inserted; tooling is idempotent), `README.md` §Available modules (tier column in the table), `CLAUDE.md` §Available modules introductory paragraph (mention of the tier system).
- **CI integration:** `docs-integrity.yml` gains a step that runs `derive_support_tiers.py --check` and fails if tier badges are out of sync with the workflows.

### 4. Progress file + trend rollup + inspection recipes

- **Files created:** `.forge/progress/status.json` and `.forge/run-history-trends.json` are runtime artefacts — not created by the spec, but by the orchestrator and retrospective agents.
- **Files modified:** `hooks/post_tool_use_agent.py` (adds progress-file writer — ~15 LOC calling a new `hooks/_py/progress.py` helper), `hooks/_py/progress.py` (new — `write_status(run_id, stage, agent, event)` helper), `agents/fg-100-orchestrator.md` (new §Progress file section documenting that the `Agent` hook is the writer, not the orchestrator), `agents/fg-700-retrospective.md` (new §Trend rollup section: last-30 aggregation + hook-failure tail), `skills/forge-status.md` (new `--- live ---` section), `shared/observability.md` (+ §Local inspection), `shared/state-schema.md` (note that `.forge/progress/` and `.forge/run-history-trends.json` survive `/forge-recover reset`).

## Data Flow / File Layout

```
.forge/
├─ .hook-failures.jsonl               # live; append-only; hot path
├─ .hook-failures-20260415.jsonl.gz   # rotated (> 7 d); gzipped
├─ progress/
│  └─ status.json                     # 5s-refresh; orchestrator owns
├─ run-history-trends.json            # end-of-run; retrospective owns
├─ events.jsonl                       # (existing)
├─ state.json                         # (existing)
└─ runs/<id>/...                      # (existing)
```

All paths built with `pathlib.Path(".forge") / "progress" / "status.json"` etc. Never string-concatenated. Never `/tmp`-relative.

**`.hook-failures.jsonl` schema (one object per line):**
```json
{
  "schema": 1,
  "ts": "2026-04-22T11:03:14.212Z",
  "hook_name": "post_tool_use.py",
  "matcher": "Edit|Write",
  "exit_code": 1,
  "stderr_excerpt": "Traceback (most recent call last):\n  File ...",
  "duration_ms": 8421,
  "cwd": "/Users/denissajnar/IdeaProjects/forge"
}
```

`stderr_excerpt` is truncated to 2 KB (`stderr[:2048]`) to bound line size. `schema` field lets future phases migrate without ambiguity; forge has no back-compat rule so we'll just bump the number.

**Ownership & concurrency.** Only one writer per file:

- `.hook-failures.jsonl` — hooks append with `open(path, "a", encoding="utf-8")`; single-line writes are POSIX atomic under 4 KB; we truncate `stderr_excerpt` to 2 KB to stay under that ceiling.
- `progress/status.json` — orchestrator only. Temp-file + `os.replace()` atomic swap. Readers may see either old or new, never a partial object.
- `run-history-trends.json` — retrospective only, once per run. Same temp+replace pattern.

JSON Schemas live at `shared/schemas/hook-failures.schema.json`, `shared/schemas/progress-status.schema.json`, `shared/schemas/run-history-trends.schema.json`. Enforcement optional: `jsonschema` package is *not* a runtime dependency. The schemas are treated as documentation; CI may load them if the package is present but skips silently otherwise.

## Error Handling

- **`.forge/` missing.** `_ensure_forge_dir()` creates it. If creation fails (permission, read-only mount, etc.), `record_failure` catches `OSError`, writes to `sys.stderr`, and returns. Hook does *not* error — hook behaviour is lossy-observability, never a hard fail.
- **Rotation fails mid-gzip.** `failure_log.rotate()` uses a temp file (`.gz.tmp`) and `os.replace()` at the end. On exception, the temp file is `Path.unlink(missing_ok=True)`-ed; the live `.jsonl` is untouched. Next session retries.
- **Progress file race with `state.json` write.** No race — they are separate files, separate writers. `status.json` is written by the `post_tool_use_agent.py` hook on subagent-completion events; `state.json` is written by the orchestrator at stage transitions. Readers must not assume they are synchronous — `state.json` is authoritative for stage, `status.json` is advisory for "what's happening right now."
- **Corrupt `.jsonl` (partial line from a killed hook).** Readers skip lines that do not parse; `record_failure` writer flushes+closes per call. Append-mode-single-write keeps each line atomic; the failure mode would be a killed process mid-`write()`, which on Linux/macOS leaves a trailing incomplete line — we accept that and make readers tolerant.
- **Windows file locking.** Append-open on Windows uses exclusive lock on the handle only during the syscall. Multiple concurrent writers would serialise but not corrupt. With only six hook scripts, contention is negligible.
- **`.forge/` deleted mid-run.** Existing contract (CLAUDE.md §Gotchas: "unrecoverable") — we do not try to heroically recover. Next write fails in `record_failure`, which no-ops per above.

## Testing Strategy

All tests run in CI; none run locally. (User standing instruction: no local test suite.)

- **Structural tier (`tests/run-all.sh structural`):** asserts `install.ps1`, `install.sh`, `shared/check_environment.py` exist and are executable where applicable; asserts `shared/check-environment.sh` is *removed*; asserts every `modules/**/conventions.md` has a `> Support tier:` line; asserts `docs/support-tiers.md` exists.
- **Unit tier (`tests/run-all.sh unit`):** Python unit tests for `hooks/_py/failure_log.py` — write + rotate + safe-if-missing; Python unit tests for `shared/check_environment.py` — platform detection returns the expected string for each `sys.platform` value (mocked).
- **Contract tier:** JSON schema validation of fixture `.hook-failures.jsonl`, `progress/status.json`, `run-history-trends.json` samples against `shared/schemas/*.schema.json`. Skipped if `jsonschema` is absent (doc-schemas, not hard contract).
- **Platform matrix (CI).** `test.yml` already runs `ubuntu-latest`, `macos-latest`, `windows-latest`. On `windows-latest` the `structural` job is bash-on-Git-Bash; the `test` job's tier legs run under pwsh by GitHub default. Phase 1 formalises the pwsh legs via `tests/run-all.ps1` wrapper, adds `test-windows-pwsh-structural` (pwsh structural), and adds `test-windows-cmd` (cmd structural + unit via `tests/run-all.cmd`). Contract/scenario tiers remain bash/pwsh (not CMD).
- **Accessibility of error messages.** No emoji anywhere — plain ASCII. `install.ps1` and `install.sh` error messages use `ERROR:` / `WARN:` prefixes, not symbols. `failure_log.py` stderr output is plain ASCII. Verified by a structural test that greps for emoji codepoints in new files.

## Documentation Updates

- **`README.md`:**
  - §Quick start — replace `ln -s` with platform-split install (`install.sh` on mac/linux, `install.ps1` on Windows). Link to both.
  - §Available modules — add tier column; point at `docs/support-tiers.md`.
  - §Troubleshooting row "Check engine errors" (line 261) — update `.forge/.hook-failures.log` to `.forge/.hook-failures.jsonl`.
- **All other `.hook-failures.log` callsites** get the filename updated to `.hook-failures.jsonl` in the same PR (no shim, no dual-write):
  - `agents/fg-100-orchestrator.md:1245`
  - `agents/fg-505-build-verifier.md:39, 55, 140` (three mentions; also update the parsing logic since it's now JSON per line rather than pipe-delimited)
  - `shared/logging-rules.md:47`
  - `shared/hook-design.md:72, 85, 96` (contract update — §Failure Behavior table, §Timeout Behavior bullet, §Script Contract rule 5)
  - `shared/state-schema-fields.md:693`
  - `CHANGELOG.md:451` (historical entry — factual update, not rewrite of history: add a `NOTE: renamed to .hook-failures.jsonl in <next-version>` inline marker)
  - `skills/forge-status/SKILL.md:91–97` (four mentions; parsing switches to `jq`/JSON)
  - `shared/checks/engine.sh:91, 112, 120` and `shared/checks/l0-syntax/validate-syntax.sh:32, 37` (writers themselves — switch filename and emit JSON line)
- An AC enforces that a post-change `grep -rn "\.hook-failures\.log" --include="*.md" --include="*.json" --include="*.py" --include="*.sh" --include="*.ps1" --include="*.cmd"` returns zero matches (see AC-18).
- **`CLAUDE.md`:**
  - §362 Platform requirements — rewrite to: "Forge requires Python 3.10+. Full CI coverage: macOS, Linux, Windows (Git Bash). Smoke CI coverage: Windows (PowerShell 7, CMD). Installation: `install.sh` (macOS/Linux) or `install.ps1` (Windows native). WSL2 runs as Linux."
  - §Quick start — mirror README update.
  - §Available modules / feature matrix — add one line noting support tiers, link to `docs/support-tiers.md`.
  - §Gotchas — `.forge/` survival list (currently CLAUDE.md line 355) adds `.forge/progress/`, `.forge/run-history-trends.json`, live `.forge/.hook-failures.jsonl`, and rotated `.forge/.hook-failures-*.jsonl.gz`. All survive `/forge-recover reset`; only manual `rm -rf .forge/` removes them.
- **`shared/observability.md`** — add §Local inspection (recipes table above).
- **`shared/hook-design.md`** — add §Failure logging describing `.forge/.hook-failures.jsonl`, rotation policy, and the `failure_log` module.
- **`shared/state-schema.md`** — note new runtime paths that survive reset.
- **`docs/support-tiers.md`** — new file, authoritative tier definition + module matrix.
- **Each `modules/**/conventions.md`** — `> Support tier: <tier>` line injected by `derive_support_tiers.py`.
- **`CHANGELOG.md`** — one entry under next version: "Phase 1: Truth & Observability. `.hook-failures.log` → `.jsonl`; `check-environment.sh` → `check_environment.py`; Windows install helper; support-tier badges; progress file."

## Acceptance Criteria

1. **AC-1.** `shared/check-environment.sh` does not exist. `shared/check_environment.py` exists, is Python 3.10+, uses `pathlib.Path`, and emits the same JSON shape that `/forge-init` consumes.
2. **AC-2.** `install.ps1` exists at repo root, parses without syntax errors under PowerShell 5.1+ and PowerShell 7+ (verified in CI by `powershell -NoProfile -Command "$null = [scriptblock]::Create((Get-Content -Raw install.ps1))"`), passes `PSScriptAnalyzer -Severity Error,Warning` with no violations, supports a `-Help` switch that prints usage and exits 0, and supports a `-WhatIf` switch that performs no filesystem writes and prints the planned actions. End-to-end install on a fresh Windows runner is deferred — AC-4's `test-windows-pwsh-structural` job covers the interpreter path; a full install E2E belongs in a later phase once the script's surface stabilises.
3. **AC-3.** `install.sh` exists at repo root and replaces the README `ln -s` snippet for macOS/Linux install flows.
4. **AC-4.** `.github/workflows/test.yml` gains: (a) a `test-windows-pwsh-structural` job running structural tier on `windows-latest` under `defaults.run.shell: pwsh`; (b) a `test-windows-cmd` job running structural + unit tiers on `windows-latest` under `defaults.run.shell: cmd`; (c) an explicit pwsh-wrapped step on the existing `test` job's Windows legs via `tests/run-all.ps1`. The existing `test` job's implicit pwsh coverage is not *duplicated* — it's *formalised* by adding the wrapper. `tests/run-all.ps1` and `tests/run-all.cmd` exist and invoke `run-all.sh` via Git-Bash-provided `bash.exe`.
5. **AC-5.** `hooks/_py/failure_log.py` exists, exposes `record_failure(...)` and `rotate()`, and has unit tests covering safe-if-missing, append-after-existing, gzip-after-7d, delete-after-30d.
6. **AC-6.** Every script referenced from `hooks/hooks.json` (currently: `pre_tool_use.py`, `post_tool_use.py`, `post_tool_use_skill.py`, `post_tool_use_agent.py`, `stop.py`, `session_start.py`) wraps its `main()` in a try/except that invokes `record_failure` on non-zero exit or uncaught exception. Non-hook CLIs under `hooks/` (e.g. `hooks/automation_trigger.py`, which is imported as a library by `post_tool_use.py` rather than dispatched from `hooks.json`) are out of scope for AC-6 but may adopt the same wrapper at the author's discretion.
7. **AC-7.** After a session where any hook fails, `.forge/.hook-failures.jsonl` contains at least one row conforming to `shared/schemas/hook-failures.schema.json`.
8. **AC-8.** `docs/support-tiers.md` exists and documents three tiers (CI-verified, contract-verified, community) with the rule "tier is determined by which CI matrix jobs exercise the module."
9. **AC-9.** `tests/lib/derive_support_tiers.py` run with `--check` passes; every `modules/**/conventions.md` has exactly one `> Support tier:` line directly beneath its H1.
9a. **AC-9a (idempotency).** Running `tests/lib/derive_support_tiers.py` (write mode, no `--check`) twice consecutively on a clean tree produces no diff on the second run. Verified by a structural test that runs the script twice and asserts `git diff --exit-code` between invocations.
10. **AC-10.** `docs-integrity.yml` fails CI if support-tier badges drift from the workflow matrix.
11. **AC-11.** `hooks/post_tool_use_agent.py` rewrites `.forge/progress/status.json` on every subagent-completion `Agent` event, via atomic rename. Verified by a unit test that invokes the hook's `main()` with a synthetic `Agent` event payload and asserts `status.json` is created/updated on disk with the expected schema.
12. **AC-12.** `agents/fg-700-retrospective.md` describes generation of `.forge/run-history-trends.json` with last-30-runs aggregate and last-10 hook-failure tail.
13. **AC-13.** `shared/observability.md` contains the three-shell inspection recipe table (bash/zsh, PowerShell, CMD) with best-effort recipes for status, recent runs, recent hook failures. bash/zsh and PowerShell rows provide executable one-liners; the CMD row provides `type` commands for raw viewing and directs users to open the files in a text editor or use PowerShell for structured inspection — CMD has no built-in JSON parsing.
14. **AC-14.** `shared/state-schema.md` lists `.forge/progress/`, `.forge/run-history-trends.json`, and `.forge/.hook-failures*.jsonl*` as paths that survive `/forge-recover reset`.
15. **AC-15.** `CLAUDE.md` §362 no longer claims uniform Windows support; it specifies full-CI (bash) vs smoke-CI (pwsh/cmd) tiers.
16. **AC-16.** Grep for emoji codepoints (U+1F300–U+1FAFF, U+2600–U+27BF) in any new or modified file returns zero matches.
17. **AC-17.** All new file paths in Python are constructed via `pathlib.Path` — structural test greps new `.py` files for hardcoded `/` separators in string literals and fails if found.
18. **AC-18.** A structural test runs `grep -rn "\.hook-failures\.log" --include="*.md" --include="*.json" --include="*.py" --include="*.sh" --include="*.ps1" --include="*.cmd" .` (excluding the spec file itself and any archived historical changelogs) and asserts zero matches. This guarantees no stray references to the old filename remain after the rename.

## Open Questions

- **Q1 (resolved).** *Should `install.ps1` use `irm | iex` or a static-download-and-run pattern?* Decision: ship a repo-local `install.ps1` invoked directly (`powershell -ExecutionPolicy Bypass -File install.ps1`). The `irm | iex` pattern is Anthropic's convention for their own Claude Code CLI installer (per `https://code.claude.com/docs/en/setup` and community guides such as smartscope.blog's Windows install walkthrough, interworks.com's January 2026 Windows 11 guide, and claudelab.net's PowerShell Tool guide); forge as a *plugin* is checked out via git, so the helper just wraps `git clone` + `settings.json` edit. Users can still one-liner it with `irm https://raw.githubusercontent.com/quantumbitcz/forge/master/install.ps1 | iex` if they prefer.
- **Q2 (resolved).** *Should the progress file live in `.forge/progress/status.json` or flatten to `.forge/progress.json`?* Keep the directory; it leaves room for per-stage files (`.forge/progress/stage-verifying.log`) without another migration.
- **Q3 (resolved).** *Rename `.hook-failures.log` → `.jsonl` — breaking change OK?* Yes per standing instruction; README troubleshooting row updated, no shim.
- **Q4 (resolved).** *Tier 1 "CI-verified" label when the pipeline-smoke matrix does not yet exist — lie?* No. Phase 1 ships the tier system and labels those four stacks as `contract-verified` today; the label graduates to `CI-verified` only when Phase 2's pipeline-smoke matrix lands. The spec is truthful about what CI actually runs.
- **Q5 (still open, for user review).** *Should `derive_support_tiers.py --check` fail the build on drift, or just warn?* Spec assumes fail (AC-10). If the user prefers warn-only to avoid blocking merges while tiers churn, flip `--check` to exit-0-with-stderr-message. Default: fail.
- **Q6 (resolved by redesign).** *Progress file cadence.* Moot — Critical review correctly flagged that the 5-second timer assumed a long-lived orchestrator daemon, which doesn't exist. The redesigned writer is the `post_tool_use_agent.py` hook, which fires on every subagent completion (naturally event-driven). Optional `progress.min_interval_s` config (default 2) rate-limits writes on rapid-completion bursts.
