# Phase 2 — Observability & Progress (Design)

**Status:** Draft v2 for review (v1 review applied)
**Date:** 2026-04-16
**Target version:** Forge 3.1.0 (minor — additive; no breaking changes)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 2 of 7
**Depends on:** Phase 1 (3.0.0 skill surface + agent frontmatter contract). Phase 2 assumes `/forge-recover`, `shared/skill-contract.md`, `shared/agent-colors.md`, and the revised `shared/agent-ui.md` are in place.

---

## 1. Goal

Make a long-running Forge pipeline observable to the user. Every sub-agent dispatch produces a visible task; every token burn produces a visible cost tick; every silent hook failure surfaces at SessionStart; every error escalation to the user includes inline recovery guidance. Users watching a 30-minute run see every step instead of 20 minutes of silence.

## 2. Context and motivation

The April 2026 UX audit graded observability **C** and identified four structural problems:

1. **Silent sub-agent dispatch** during `IMPLEMENT` and `REVIEW` — the orchestrator spends 20+ minutes dispatching child agents with no user-visible progress.
2. **Invisible cost.** `state.json.tokens` tracks token counts; nothing streams cost to the user during the run.
3. **Invisible hook failures.** `.forge/.hook-failures.log` captures every PostToolUse check-engine failure (L0 syntax, L1 regex, L2 linter) but users never see the file.
4. **Errors escalate without guidance.** When orchestrator emits `AskUserQuestion` on LINT_FAILURE or CONTEXT_OVERFLOW, options are correct but no inline recovery guidance appears.

**v1 review corrections applied:**

- Cost tracking infrastructure already exists: `shared/forge-token-tracker.sh` maintains per-model pricing and per-stage cost rollup; `shared/cost-alerting.sh` handles alerts; `tests/contract/cost-observability.bats` enforces the cost surface. Phase 2 **extends** these rather than creating parallel infrastructure.
- Session-start badge format is `[forge] Pipeline: state={stage} mode={mode} score={score} last_active={t}` — Phase 2 appends ` • ${run_cost_usd}` to this existing format.
- Hook log format is **pipe-delimited** (`ts | script | reason | file`), not JSON — Phase 2's banner parses pipe format, no log migration.
- Color-dot palette already defined in `shared/agent-ui.md` (6 dots: 🟢 🔴 🔵 🟡 🟣 🟤). Phase 2 extends via a map of all 18 `shared/agent-colors.md` hues onto the existing 6 dots (cluster-based collapsing) plus 2 neutrals (⚪ ⬜); no existing dot is redefined.
- State schema version is **1.6.0** today; Phase 1 does not bump it; Phase 2 bumps to **1.7.0**.
- Events.jsonl in sprint mode writes to `.forge/runs/{id}/events.jsonl`; Phase 2's cost streaming honors this per-run path convention.

No backwards compatibility required (single-user plugin). Phase 2 stays narrowly scoped: **observability surface only.** No recovery-logic change, no convergence change, no new agents.

## 3. Non-goals

- No new agents.
- No change to recovery *logic* (strategy selection, retry budget, convergence unchanged). Recovery becomes *visible*, behaves the same.
- No change to L0/L1/L2 check-engine *rules*. Hook failure surfacing is read-only.
- No UI framework dependency. All observability rides on `TaskCreate`/`TaskUpdate` + `.forge/events.jsonl`. No TUI in this phase (Phase 5).
- No cost-model-routing changes. Cost tracking observes what routing decides.
- No rewrite of `.forge/.hook-failures.log` schema. Keep pipe-delimited format.
- No silent redefinition of the 6 existing color dots.
- **Deferred to later phases:**
  - `/forge-watch` TUI → Phase 5
  - Editable plan file + escalation taxonomy → Phase 4
  - Preview-before-apply overlay → Phase 4

## 4. Design

### 4.1 Hierarchical sub-agent `TaskCreate` contract

**New rule (mandatory agent contract, bats-enforced):** Every agent whose `tools:` list includes `Agent` MUST, before every sub-agent dispatch:

1. `TaskCreate` a child task with status `pending`, subject template `{dot} {agent_id} {short_purpose}` where `{dot}` is derived from `shared/color-to-emoji-map.json` (§4.1.2 below).
2. Immediately before `Agent` invocation: `TaskUpdate` status → `in_progress`.
3. Immediately after `Agent` return: `TaskUpdate` status → `completed` with `metadata.summary` = agent's exit verdict.

**Affected agents (15 dispatchers today):** `fg-010-shaper`, `fg-015-scope-decomposer`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`, `fg-090-sprint-orchestrator`, `fg-100-orchestrator`, `fg-103-cross-repo-coordinator`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`, `fg-200-planner`, `fg-310-scaffolder`, `fg-400-quality-gate`, `fg-500-test-gate`, `fg-590-pre-ship-verifier`, `fg-600-pr-builder`. Criterion: every agent with `Agent` in `tools:`.

**Parent/child relationship.** The pipeline already emits a stage-parent task (Level 1) at each stage start; sub-agent dispatches become Level 2 tasks. Visual hierarchy is expressed via subject-line tree-drawing characters (`├─`, `└─`) — consistent with `shared/agent-ui.md` existing convention. The `blockedBy`/`blocks` fields are used to express true dispatch dependencies (e.g., test-gate blocked by build-verifier), not hierarchy.

Rendered example during Stage 6 REVIEW:

```
📖 Stage 6: REVIEW • $0.41
  ├─ 🔵 fg-410 code review (in progress)
  ├─ 🔴 fg-411 security review (completed · 0 CRITICAL)
  ├─ 🔵 fg-412 arch review (completed · 1 WARNING)
  ├─ 🟢 fg-419 infra review (queued)
  ├─ 🔵 fg-413 frontend review (queued)
  ├─ 🟡 fg-416 perf review (queued)
  ├─ 🟣 fg-417 dep review (queued)
  └─ ⚪ fg-418 docs review (queued)
```

#### 4.1.1 Color-to-emoji mapping

**Existing `shared/agent-ui.md` defines 6 dots** that map to agent roles. Phase 2 extends the map to cover all 18 hues from `shared/agent-colors.md` by collapsing new hues onto existing dots (closest visual/semantic match). No existing dot is redefined.

**`shared/color-to-emoji-map.json` (new):**

```json
{
  "version": "2026-04-16",
  "map": {
    "green":   "🟢",
    "lime":    "🟢",
    "teal":    "🟢",
    "olive":   "🟢",
    "red":     "🔴",
    "crimson": "🔴",
    "blue":    "🔵",
    "navy":    "🔵",
    "cyan":    "🔵",
    "yellow":  "🟡",
    "amber":   "🟡",
    "magenta": "🟣",
    "pink":    "🟣",
    "orange":  "🟣",
    "coral":   "🟣",
    "purple":  "🟤",
    "brown":   "🟤",
    "white":   "⚪",
    "gray":    "⬜"
  },
  "ascii_fallback": {
    "green":   "[G]",
    "lime":    "[G+]",
    "teal":    "[T]",
    "olive":   "[O]",
    "red":     "[R]",
    "crimson": "[R+]",
    "blue":    "[B]",
    "navy":    "[N]",
    "cyan":    "[C]",
    "yellow":  "[Y]",
    "amber":   "[A]",
    "magenta": "[M]",
    "pink":    "[P]",
    "orange":  "[O+]",
    "coral":   "[C+]",
    "purple":  "[V]",
    "brown":   "[B-]",
    "white":   "[W]",
    "gray":    "[-]"
  }
}
```

ASCII fallback activates when `FORGE_NO_EMOJI=1` env var is set or `TERM=dumb`. Dispatch-agent contract requires lookup via an inline helper (`resolve_dot()` documented in `shared/observability-contract.md §2`).

### 4.2 Cost streaming — 4 channels via **extension** of existing infrastructure

Phase 2 does not introduce `shared/forge-cost-tracker.sh`. It **extends** the existing `shared/forge-token-tracker.sh` which already:
- Maintains per-model pricing (haiku/sonnet/opus at `shared/forge-token-tracker.sh:150`)
- Accumulates `state.cost.estimated_cost_usd`
- Rolls up into `state.cost.per_stage`

Plus `shared/cost-alerting.sh` which already handles alerts.

**Extensions in this phase:**

#### 4.2.1 Externalize model pricing

**New file: `shared/model-pricing.json`** — canonical per-model per-1K-token prices:

```json
{
  "version": "2026-04-16",
  "models": {
    "claude-opus-4-7":         {"input_per_1k": 0.015,  "output_per_1k": 0.075},
    "claude-opus-4-7-1m":      {"input_per_1k": 0.018,  "output_per_1k": 0.090},
    "claude-sonnet-4-6":       {"input_per_1k": 0.003,  "output_per_1k": 0.015},
    "claude-haiku-4-5-20251001": {"input_per_1k": 0.0008, "output_per_1k": 0.004}
  },
  "unknown_model_fallback": {"input_per_1k": 0.015, "output_per_1k": 0.075}
}
```

**`forge-token-tracker.sh` refactored** to load pricing from `shared/model-pricing.json` (replacing the hard-coded `DEFAULT_PRICING_TABLE` at `:150`). User-specific overrides via `shared/model-pricing.local.json` (git-ignored); cost tracker reads `.local.json` first with shallow merge at the `models` level. Override loader code path documented in `shared/cost-tracking.md`.

#### 4.2.2 Emit `cost.inc` events to the right events log

`forge-token-tracker.sh` on every `Agent` return:
1. Increments `state.cost.estimated_cost_usd` (existing behavior).
2. Increments `state.cost.per_stage.{N}` (existing behavior).
3. **Appends `cost.inc` event** to the events log — path determined by sprint mode:
   - **Standard run:** `.forge/events.jsonl`
   - **Sprint-child run:** `.forge/runs/{run_id}/events.jsonl`

Event schema:
```json
{"ts":"2026-04-16T10:23:15Z","type":"cost.inc","run_id":"run-17","stage":5,"agent":"fg-300-implementer","model":"claude-sonnet-4-6","tokens_in":12400,"tokens_out":892,"cost_usd":0.0508,"run_cost_usd":0.3243,"cap_usd":5.00}
```

Sprint-mode path selection: read `state.run_id`; if the path `.forge/runs/{run_id}/` exists, write there; else write to `.forge/events.jsonl`. Existing `mkdir`-based locking (per `shared/event-log.md:374`) applies.

#### 4.2.3 Reuse + extend `shared/event-log.md`

Current Event Types count is 12. Phase 2 adds 4 (not 5 — we consolidate the recovery lifecycle under an existing `RECOVERY` event):

- `cost.inc` — new
- `cap.breach` — new
- `hook.failure.surfaced` — new (emitted when the banner is shown, for analytics)
- `dispatch.child` — new (emitted by the dispatch contract, carries `{parent_stage, child_agent, child_task_id}`)

**The existing `RECOVERY` event gets a new optional `phase` field** with values `start | end`. No event split — same event type, optional sub-phase marker. This avoids doubling the event type count.

Header count in `shared/event-log.md` updated: `Event Types (12)` → `Event Types (16)`. Envelope `type` enum description updated.

#### 4.2.4 Per-stage task subject with cost

Orchestrator, when creating the stage-parent task, uses subject:
```
📖 Stage {N}: {NAME}
```
and `TaskUpdate`s the subject on every `cost.inc` event for that stage:
```
📖 Stage {N}: {NAME} • ${stage_cost_usd}
```
`{stage_cost_usd}` sourced from `state.cost.per_stage.{N}` (already maintained by `forge-token-tracker.sh`).

#### 4.2.5 Session-start status badge — extend existing format

Current `hooks/session-start.sh` emits:
```
[forge] Pipeline: state={stage} mode={mode} score={score} last_active={t}
```

Phase 2 extends to:
```
[forge] Pipeline: state={stage} mode={mode} score={score} last_active={t} • ${run_cost_usd}
```

The ` • ${run_cost_usd}` suffix is appended only when `state.cost.estimated_cost_usd > 0` (avoids noise for pristine state). Source: read from `state.json` at hook execution time.

#### 4.2.6 Hard cost cap with escalation

New config fields in `forge.local.md` / `forge-config.md`:

```yaml
cost_cap:
  usd: 5.00                # 0 disables; any positive sets the cap
  action_on_breach: ask    # ask | abort | warn_continue
```

When `run_cost_usd` crosses `cap_usd`, `forge-token-tracker.sh` appends a `cap.breach` event AND sets `state.cost.cap_breached: true` atomically via `forge-state-write.sh`. Orchestrator's main loop checks this flag on each stage boundary and takes action per `action_on_breach`:

- **`ask`** — dispatch `AskUserQuestion` Pattern 3 (safe-default escalation):
  ```json
  {
    "question": "Cost cap $5.00 reached ($5.01 spent). See docs/error-recovery.md#cost_cap_breach. How to proceed?",
    "header": "Cost cap",
    "multiSelect": false,
    "options": [
      {"label": "Raise cap to $10 and continue (Recommended)", "description": "Doubles cap; resets breach. Recorded in state.json.cost_cap_decisions."},
      {"label": "Abort gracefully", "description": "Stops at next stage boundary; preserves state for /forge-recover resume."},
      {"label": "Force-continue without cap", "description": "Removes cap for this run. Dangerous on misconfigured model routing."}
    ]
  }
  ```
- **`abort`** — orchestrator transitions to `ABORTED` immediately; no prompt.
- **`warn_continue`** — orchestrator emits a stderr warning and proceeds.

**Autonomous mode interaction (explicit):**
- `autonomous: true` + `action_on_breach: ask` → auto-resolves to the **Recommended** option (raise cap 2×), logged as `[AUTO: cap breach raised to $N]`. Rationale: autonomous mode explicitly opts into self-resolution; defaulting to `abort` would kill every long run.
- `autonomous: true` + `action_on_breach: abort` → honored; run aborts at breach.
- `autonomous: true` + `action_on_breach: warn_continue` → honored; warning emitted; run continues.

Documented in `shared/cost-tracking.md §4 Autonomous-mode rules`.

Decision recorded in `state.json.cost_cap_decisions` (new field, Phase 2 schema bump):
```json
{
  "cost_cap_decisions": [
    {"ts": "2026-04-16T10:23:15Z", "at_cost_usd": 5.01, "decision": "raise_to_10", "new_cap_usd": 10.00, "autonomous": false}
  ]
}
```

### 4.3 Hook failure visibility

#### 4.3.1 Session-start banner

`hooks/session-start.sh` extended with `print_hook_failure_banner()`:

1. Reads `.forge/.hook-failures.log` if present.
2. Parses the **pipe-delimited** format (existing schema, unchanged):
   ```
   2026-04-16T10:23:15Z | engine.sh | L0_TIMEOUT:src/big.ts | duration_ms=5012
   ```
   Fields: `ts | script | reason[:context] | detail`.
3. Filters entries newer than `observability.hook_failure_surface_window_hours` (default 24).
4. If ≥1 entry matches, emits stderr banner:
   ```
   ⚠️  3 hook check-engine failures in last 24h (last: L0_TIMEOUT on src/big.ts).
       Run /forge-recover diagnose --hooks for details.
   ```
5. **Log truncation:** after emitting, if file has >100 lines, truncate to last 50 via `tail -n 50 > $log.tmp && mv $log.tmp $log`. Keeps log bounded.

No schema migration; no new source change to `shared/checks/engine.sh`.

#### 4.3.2 `/forge-recover diagnose --hooks` flag

`skills/forge-recover/SKILL.md` (from Phase 1) adds `--hooks` to the `diagnose` subcommand's `## Flags` section:

```
- --hooks: include hook-failure analysis in the diagnose report
```

`agents/fg-100-orchestrator.md` §Recovery op dispatch gains a branch: when `recovery_op == "diagnose"` AND `--hooks` set:
- Loads `.forge/.hook-failures.log`, parses pipe format.
- Groups failures by `{script, reason_prefix}`. `reason_prefix` is the substring before `:` (e.g., `L0_TIMEOUT`, `skip`).
- Identifies top failing hook by count.
- For `L0_TIMEOUT` reasons, lists "problem files" (files appearing in `context` field with >3 failures).
- Emits remediation suggestions:
  - `L0_TIMEOUT` on specific files → suggest excluding those paths in `check_engine.l0_exclude_patterns` OR increasing `check_engine.l0_timeout_ms`.
  - `skip:bash_version_*` → suggest `brew install bash` on macOS.
  - `skip:tool_missing` → list missing tools with install hints.

Output is human-readable by default; `--json` (already on diagnose from Phase 1) returns structured.

### 4.4 Error recovery docs + inline guidance

#### 4.4.1 `docs/error-recovery.md` (new)

Human-readable mapping of all 22 error types from `shared/error-taxonomy.md`. Format per entry:

```markdown
## {ERROR_NAME}

**Symptom.** What the user sees (terminal text, stage outcome).

**Severity.** CRITICAL | HIGH | MEDIUM | LOW.

**What Forge tried.** Auto-retry behavior + reference to recovery strategy in `shared/recovery/recovery-engine.md`.

**What to do now.** Step-by-step user action with exact commands.

**Example log line.** One concrete example.
```

**Anchor slug rule (important, bats-checkable):** Headings use the taxonomy name verbatim (case-preserving). GitHub-flavored-Markdown slug is lowercase with underscores preserved: `LINT_FAILURE` → `#lint_failure`, `CONTEXT_OVERFLOW` → `#context_overflow`.

All 22 entries land in one document; long (~500 lines). Grep-able by error name.

#### 4.4.2 Inline guidance in `AskUserQuestion` escalations

Every error-triggered `AskUserQuestion` emitted by any dispatch agent (`fg-100-orchestrator`, `fg-400-quality-gate`, `fg-500-test-gate`, `fg-210-validator` when in Phase 4+) MUST include in its `question` field:
- A link to the matching section of `docs/error-recovery.md` (format `docs/error-recovery.md#<slug>`)
- A 2-sentence inline summary of cause + what the recommended option does

**Bats enforcement (precise, not heuristic):** Escalation `AskUserQuestion` calls are identified by `header:` being in the error-escalation allowlist defined in `shared/observability-contract.md §6`:

```
"Cost cap", "Quality gate", "Lint fail", "Test fail", "Feedback loop", "Build fail",
"Context overflow", "MCP down", "Recovery", "Escalation"
```

For each allowlist match, the `question:` field MUST contain a literal `docs/error-recovery.md#` substring. Happy-path `AskUserQuestion` examples with non-allowlist headers (like Phase 1 `Shape axes`, `Stack`, `Commits`) are exempt.

#### 4.4.3 Update to `shared/error-taxonomy.md`

Add a `user_guide:` inline link in the `Meaning` column of each error row (existing table has 5 columns — adding an inline link to the Meaning column avoids widening the table). Example:

```markdown
| LINT_FAILURE | MEDIUM | Agent-reported | Lint/format disagreement after auto-fix. ([User guide](/docs/error-recovery.md#lint_failure)) | 3-retry auto-fix |
```

**Cross-link validator (bats):** `tests/validate-plugin.sh` gains a check that every `user_guide:` link in `shared/error-taxonomy.md` resolves to a real heading in `docs/error-recovery.md`. Slug rule per §4.4.1.

### 4.5 Recovery-engine `TaskCreate` emission rule

`shared/recovery/recovery-engine.md` extended with:

**Rule.** For every recovery **strategy** (not every retry), the agent applying the strategy MUST emit `RECOVERY` event with `phase: start` + `TaskCreate` a task with subject `🛟 Recovering from {error_type}: {strategy_name}` at `pending`, `TaskUpdate` to `in_progress` when the strategy begins, `TaskUpdate` to `completed` on return, and emit `RECOVERY` event with `phase: end`.

**Exception — NOT emitted as tasks:**
- `FLAKY_TEST` single-retry
- Any recovery with `strategy: wait_and_retry` AND `wait_ms < 1000`

Bats-enforced in `tests/contract/recovery-engine.bats` (already exists, confirmed) via assertion extension.

### 4.6 Deferred Phase 1 item — runtime integration test

Phase 1 deferred true runtime `--dry-run` verification of `/forge-recover`. Phase 2 adds the fixtures.

**New file: `tests/helpers/forge-fixture.sh`** — bash library (invoked as a command, not sourced — hence `.sh`) for creating a deterministic `.forge/` fixture. API:

```
forge-fixture.sh create <dest-path>    # seeds <dest-path>/.forge/ with fixture state; prints path
forge-fixture.sh destroy <path>         # rm -rf <path>
forge-fixture.sh snapshot <path>        # writes <path>.snapshot with sha256 of sorted file list
forge-fixture.sh diff <path>            # diff <path>.snapshot against current; exit 0 if identical
```

Executable (`chmod +x`), shebang `#!/usr/bin/env bash`, validated by existing `tests/validate-plugin.sh` hook-script check (extended).

**New file: `tests/unit/skill-execution/forge-recover-runtime.bats`** — invokes `/forge-recover repair --dry-run` and `/forge-recover reset --dry-run` against a fixture; snapshots before and after; asserts zero writes. Closes Phase 1 AC #23.

### 4.7 Observability contract doc

**New file: `shared/observability-contract.md`** — authoritative reference:

- §1 Hierarchical `TaskCreate` rule (§4.1 above)
- §2 Color-to-emoji mapping reference (§4.1.1 + ASCII fallback)
- §3 Event types + schemas (`cost.inc`, `cap.breach`, `hook.failure.surfaced`, `dispatch.child`, `RECOVERY.phase`)
- §4 Cost cap + escalation flow (§4.2.6)
- §5 Hook failure banner mechanics (§4.3)
- §6 Error-escalation `AskUserQuestion` allowlist + slug rule (§4.4.2)
- §7 Recovery-engine `TaskCreate` rule (§4.5)
- §8 Sprint-mode events.jsonl per-run-path rule (§4.2.2)
- §9 Enforcement map (which bats file enforces each rule)

### 4.8 Configuration additions

`forge.local.md` / `forge-config.md`:

```yaml
observability:
  sub_agent_tasks: hierarchical              # hierarchical | flat | off
  hook_failure_surface_window_hours: 24
  hook_failure_log_max_entries: 100
  hook_failure_log_truncate_to: 50
  cost_streaming: true
  recovery_tasks: non_transient              # non_transient | all | off
  ascii_fallback_on_term_dumb: true

cost_cap:
  usd: 5.00                                  # 0 disables
  action_on_breach: ask                      # ask | abort | warn_continue
```

`shared/config-schema.json` (confirmed to exist; verified via `ls shared/config-schema.json`) gains these fields with defaults. Schema validation is already wired into `tests/contract/config-schema.bats` (assume exists; verify in plan).

### 4.9 Documentation updates

- `README.md` — new section "Observability" linking to `shared/observability-contract.md`; version bump.
- `CLAUDE.md` — 5 new Key Entry Points (`observability-contract.md`, `cost-tracking.md`, `model-pricing.json`, `color-to-emoji-map.json`, `docs/error-recovery.md`); version bump.
- `CHANGELOG.md` — 3.1.0 entry.
- `.claude-plugin/plugin.json` — `"3.0.0"` → `"3.1.0"`.
- `.claude-plugin/marketplace.json` — `"3.0.0"` → `"3.1.0"`.
- `DEPRECATIONS.md` — no changes.

## 5. File manifest (authoritative)

### 5.1 Create (7 files)

```
docs/error-recovery.md                                     # 22-error user guide
shared/observability-contract.md                           # authoritative contract
shared/cost-tracking.md                                    # cost stream + cap contract
shared/model-pricing.json                                  # per-model per-1K rates
shared/color-to-emoji-map.json                             # 18-hue → 8-dot (with ASCII fallback)
tests/unit/skill-execution/forge-recover-runtime.bats      # closes Phase 1 AC #23
tests/helpers/forge-fixture.sh                             # fixture helpers
```

**No `forge-cost-tracker.sh`** (reviewer v1: cost tracking extends the existing `forge-token-tracker.sh`).

### 5.2 Update in place

**Agent `.md` files — 15 dispatchers, each gets a new `## Sub-agent dispatch` section:**

`fg-010-shaper.md`, `fg-015-scope-decomposer.md`, `fg-020-bug-investigator.md`, `fg-050-project-bootstrapper.md`, `fg-090-sprint-orchestrator.md`, `fg-100-orchestrator.md`, `fg-103-cross-repo-coordinator.md`, `fg-150-test-bootstrapper.md`, `fg-160-migration-planner.md`, `fg-200-planner.md`, `fg-310-scaffolder.md`, `fg-400-quality-gate.md`, `fg-500-test-gate.md`, `fg-590-pre-ship-verifier.md`, `fg-600-pr-builder.md`.

**`agents/fg-100-orchestrator.md` additional changes** (same file, not counted twice):
- `## Cost cap escalation` section (§4.2.6)
- `## Hook-failure diagnose branch` section (extends Phase 1 `## Recovery op dispatch`)

**Shared docs (6 files):**

- `shared/event-log.md` — extend Event Types (12 → 16); update envelope description; add `RECOVERY.phase` optional field.
- `shared/state-schema.md` — add `cost_cap_decisions` + `cost.cap_breached` fields; bump 1.6.0 → 1.7.0; update `schema_version_history`.
- `shared/error-taxonomy.md` — add inline `user_guide:` link to Meaning column of each of 22 entries.
- `shared/recovery/recovery-engine.md` — add `## Task emission rule` section (§4.5).
- `shared/agent-ui.md` — cross-reference `shared/observability-contract.md §1`; no dot-palette change.
- `shared/forge-token-tracker.sh` — refactor to load pricing from `shared/model-pricing.json`; add `cost.inc` event emission + sprint-mode path selection.

**Hook (1 file):**

- `hooks/session-start.sh` — add `print_hook_failure_banner()`; extend status-badge format with ` • ${run_cost_usd}` suffix.

**Skill (1 file):**

- `skills/forge-recover/SKILL.md` — add `--hooks` flag to `diagnose` subcommand's `## Flags` section.

**Tests (3 files):**

- `tests/contract/cost-observability.bats` — **extend** (do not duplicate) with Phase 2 assertions: `cost.inc` event emission, cap-breach event, stage-subject cost format.
- `tests/contract/recovery-engine.bats` — extend with task-emission-rule assertion.
- `tests/contract/ui-frontmatter-consistency.bats` — extend with sub-agent-dispatch assertion (every agent with `Agent` in tools references `shared/observability-contract.md §1`).
- `tests/validate-plugin.sh` — extend with cross-link validator (error-taxonomy ↔ error-recovery.md anchors); also check `tests/helpers/forge-fixture.sh` has shebang + chmod +x.

**New bats (1, moved from Creations):**

- `tests/contract/observability-contract.bats` (new, distinct name from existing `cost-observability.bats`) — covers AC #2, #3, #5, #7, #17.

Adjusting §5.1: the new bats file is `tests/contract/observability-contract.bats` (7 creations stands, one of them is this bats file).

**Top-level (5 files):**

- `README.md`
- `CLAUDE.md`
- `CHANGELOG.md`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`

### 5.3 File-count arithmetic

| Category | Files | Notes |
|---|---|---|
| Creations | 7 | `docs/error-recovery.md`, 4 new `shared/` files, 2 new test files |
| Dispatch agent `.md` updates | 15 | includes `fg-100-orchestrator.md` (3 new sections in same file — counted once) |
| Shared doc updates | 6 | event-log, state-schema, error-taxonomy, recovery-engine, agent-ui, forge-token-tracker |
| Hook update | 1 | session-start.sh |
| Skill update | 1 | forge-recover/SKILL.md |
| Test updates | 4 | cost-observability, recovery-engine, ui-frontmatter-consistency bats + validate-plugin.sh |
| Top-level updates | 5 | README, CLAUDE, CHANGELOG, plugin.json, marketplace.json |
| **Unique files touched** | **7 + 15 + 6 + 1 + 1 + 4 + 5 = 39** | |

### 5.4 File breakdown sanity check

- All 7 creations are net-new (confirmed via `ls`).
- `forge-token-tracker.sh` is an existing file — counted in "Shared doc updates" (6) not Creations.
- `cost-observability.bats` is EXTENDED, not replaced.
- `recovery-engine.bats` and `config-schema.json` are existing (confirmed).

## 6. Acceptance criteria

All verified by CI on push.

1. `docs/error-recovery.md` exists with all 22 error entries matching `shared/error-taxonomy.md` names.
2. `shared/observability-contract.md` exists with §1-§9 as specified.
3. `shared/cost-tracking.md` exists and is referenced from `shared/event-log.md`.
4. `shared/model-pricing.json` parses as valid JSON and lists ≥4 models.
5. `shared/color-to-emoji-map.json` parses as valid JSON; covers all 18 palette colors from `shared/agent-colors.md`; provides `ascii_fallback` map of equal size.
6. `shared/forge-token-tracker.sh` loads pricing from `shared/model-pricing.json` (grep confirms no hardcoded `DEFAULT_PRICING_TABLE` remaining).
7. Each of the 15 dispatch agent `.md` files contains a `## Sub-agent dispatch` section referencing `shared/observability-contract.md §1`.
8. `agents/fg-100-orchestrator.md` contains `## Cost cap escalation` section and the extended `## Recovery op dispatch` (now including `--hooks` branch).
9. `shared/event-log.md` Event Types header reads "16" (was "12"); envelope description updated; `RECOVERY` event documents optional `phase: start|end` field.
10. `shared/state-schema.md` documents `cost_cap_decisions` and `cost.cap_breached` fields; `version` is `1.7.0`; `schema_version_history` has new entry.
11. `shared/error-taxonomy.md` has inline `user_guide:` link in Meaning column of all 22 entries; all links resolve to real `docs/error-recovery.md` anchors per the lowercase-underscore slug rule (`LINT_FAILURE` → `#lint_failure`).
12. `shared/recovery/recovery-engine.md` contains `## Task emission rule` section.
13. `shared/agent-ui.md` cross-references `shared/observability-contract.md §1`.
14. `hooks/session-start.sh` contains `print_hook_failure_banner()`; static parse check passes.
15. `hooks/session-start.sh` status-badge output includes ` • $` suffix when `state.cost.estimated_cost_usd > 0`.
16. `skills/forge-recover/SKILL.md` `## Flags` section lists `--hooks`.
17. `tests/contract/observability-contract.bats` exists with ≥8 assertions.
18. `tests/contract/cost-observability.bats` extended with Phase 2 assertions (cost.inc emission, cap-breach, stage-subject cost format).
19. `tests/contract/ui-frontmatter-consistency.bats` extended with sub-agent-dispatch assertion.
20. `tests/contract/recovery-engine.bats` extended with task-emission-rule assertion.
21. `tests/unit/skill-execution/forge-recover-runtime.bats` exists and uses `tests/helpers/forge-fixture.sh`.
22. `tests/helpers/forge-fixture.sh` exists with `#!/usr/bin/env bash` shebang + `chmod +x`; verified by `tests/validate-plugin.sh`.
23. `tests/validate-plugin.sh` extended with error-taxonomy ↔ error-recovery.md cross-link validator.
24. `shared/config-schema.json` documents `observability.*` and `cost_cap.*` fields.
25. `forge-token-tracker.sh` honors sprint-mode per-run path — writes to `.forge/runs/{run_id}/events.jsonl` when state.run_id matches a sprint child.
26. Autonomous mode + `action_on_breach: ask` auto-resolves to Recommended option, logged as `[AUTO: cap breach raised to $N]`.
27. `README.md`, `CLAUDE.md`, `CHANGELOG.md` updated per §4.9.
28. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions set to `3.1.0`.
29. CI green on push — no local test runs permitted.

## 7. Test strategy

**Static validation (bats, CI-only):**

- New `tests/contract/observability-contract.bats` covers AC #2, #3, #5, #7, #17 (and is distinct from existing `cost-observability.bats`).
- Extended `tests/contract/cost-observability.bats` covers AC #18.
- Extended `tests/contract/ui-frontmatter-consistency.bats` covers AC #7, #19.
- Extended `tests/contract/recovery-engine.bats` covers AC #12, #20.
- Extended `tests/validate-plugin.sh` covers AC #11, #22, #23.

**Runtime validation (bats):**

- New `tests/unit/skill-execution/forge-recover-runtime.bats` exercises real `--dry-run` behavior using fixture helpers; closes Phase 1 AC #23.

Per user instruction: no local test runs; CI on push is the source of truth.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `forge-token-tracker.sh` refactor breaks existing cost-observability bats | Medium | High | Refactor preserves external interface (state fields unchanged); Phase 2 plan includes a regression check against existing assertions BEFORE extending them |
| Sprint-mode per-run path write miss | Medium | High | Explicit sprint-mode check in `forge-token-tracker.sh`; `mkdir`-based lock (existing `event-log.md` mechanism) prevents corruption; bats assertion (AC #25) verifies path selection |
| Pipe-delimited hook log parser breaks on edge cases | Medium | Low | Test fixture in `tests/unit/` with known-problematic lines (multi-pipe in filenames, missing fields); parser falls back to "1 failure: unparseable entry" rather than crash |
| Color-dot collapse (18→8) loses visual distinction | Low | Low | Within any dispatch cluster, Phase 1's color assignment ensures unique `color:` fields; the 18→8 collapse means some clusters show identical dots for different agents (e.g., `green` and `lime` both render 🟢). Documented in `observability-contract.md §2`; agent-id in subject disambiguates |
| Model pricing drift as Anthropic prices change | Low | Low | Versioned `shared/model-pricing.json`; user override at `shared/model-pricing.local.json`; CHANGELOG notes price changes |
| Cost cap escalation in autonomous mode is contentious default | Low | Medium | Explicit rule in §4.2.6 + `shared/cost-tracking.md §4`; can be overridden to `abort` for strict autonomous; bats assertion (AC #26) |
| `docs/error-recovery.md` drifts from taxonomy | High | Medium | `validate-plugin.sh` cross-link validator fails CI on missing anchors or orphan entries (AC #11, #23) |
| ASCII fallback is needed but `FORGE_NO_EMOJI` env var is not honored | Low | Low | Bats unit test: set `FORGE_NO_EMOJI=1`, invoke the resolver helper, assert ASCII returned |
| Event-type count bump (12→16) breaks external event consumers | Low | Low | Consumer count in Forge is 1 (`/forge-ask` in Phase 6 will add another); new event types are additive; existing consumers ignore unknown types per envelope spec |
| `cost-observability.bats` and `observability-contract.bats` are confusable by authors | Low | Low | `observability-contract.md §9` Enforcement map names each file with its scope (contract-file for meta-contract assertions; cost-observability for cost-specific runtime assertions) |

## 9. Rollout (one PR, multi-commit; CI gates on HEAD)

Order preserves CI-green per commit:

1. **Commit 1 — Specs land.** This spec + implementation plan.
2. **Commit 2 — New docs + foundations.** `docs/error-recovery.md`, `shared/observability-contract.md`, `shared/cost-tracking.md`, `shared/model-pricing.json`, `shared/color-to-emoji-map.json`. `tests/helpers/forge-fixture.sh`, `tests/unit/skill-execution/forge-recover-runtime.bats`, `tests/contract/observability-contract.bats` (skeleton, assertions inactive until referenced files exist). CI green.
3. **Commit 3 — Token tracker refactor.** `shared/forge-token-tracker.sh` loads pricing from JSON; adds `cost.inc` emission + sprint-mode path selection. Existing `cost-observability.bats` assertions must still pass (regression check). CI green.
4. **Commit 4 — Agent dispatch contract.** 15 dispatch agent `.md` updates + `shared/agent-ui.md` cross-reference. `tests/contract/ui-frontmatter-consistency.bats` extended. CI green.
5. **Commit 5 — Orchestrator + hook + skill + recovery + schema.** `fg-100-orchestrator.md` (2 new sections + extended one), `hooks/session-start.sh` (banner + cost suffix), `skills/forge-recover/SKILL.md` (`--hooks` flag), `shared/event-log.md` (16 types + RECOVERY.phase), `shared/state-schema.md` (1.6.0 → 1.7.0), `shared/error-taxonomy.md` (user_guide links), `shared/recovery/recovery-engine.md` (task emission rule), `tests/contract/recovery-engine.bats` extension, `tests/contract/cost-observability.bats` Phase 2 extension, `tests/validate-plugin.sh` cross-link validator. CI green.
6. **Commit 6 — Config schema + top-level docs + version bump.** `shared/config-schema.json` (observability + cost_cap fields), `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`. CI green.
7. **Push → CI gate on HEAD → on green, tag `v3.1.0` → release.**

## 10. Versioning rationale (SemVer minor)

Phase 2 is additive: new files, new agent sections, new config fields with safe defaults, new event types, new bats assertions. Token-tracker refactor preserves external interface. No breaking changes. → `3.0.0` → `3.1.0`.

## 11. Open questions

None. All decisions locked during brainstorming + v1 review.

## 12. References

- Phase 1 spec
- `shared/forge-token-tracker.sh` — extended in this phase
- `shared/cost-alerting.sh` — unchanged, referenced
- `shared/event-log.md` — event taxonomy extension target
- `shared/error-taxonomy.md` — 22-entry catalog
- `shared/recovery/recovery-engine.md` — strategies unchanged
- `shared/agent-ui.md` — 6-dot palette preserved
- `shared/agent-colors.md` — 18-hue palette (Phase 1 deliverable)
- `shared/state-schema.md` — v1.6.0 current; bumped to v1.7.0
- `shared/config-schema.json` — schema-validated config
- `tests/contract/cost-observability.bats` — existing coverage extended
- `tests/contract/recovery-engine.bats` — existing coverage extended
- April 2026 UX audit (conversation memory)
- v1 code-review (this conversation) — all 6 critical + 7 important findings applied
- User instruction: "I want it all except the backwards compatibility"
