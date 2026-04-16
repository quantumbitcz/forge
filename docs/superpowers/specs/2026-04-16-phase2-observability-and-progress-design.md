# Phase 2 — Observability & Progress (Design)

**Status:** Draft for review
**Date:** 2026-04-16
**Target version:** Forge 3.1.0 (minor — additive; no breaking changes)
**Author:** Denis Šajnar (authored with Claude Opus 4.7)
**Phase sequence:** 2 of 7
**Depends on:** Phase 1 (3.0.0 skill surface + agent frontmatter contract). Phase 2 assumes `/forge-recover`, `shared/skill-contract.md`, and the revised `shared/agent-ui.md` are in place.

---

## 1. Goal

Make a long-running Forge pipeline observable to the user. Every sub-agent dispatch produces a visible task; every token burn produces a visible cost tick; every silent hook failure surfaces at SessionStart; every error escalation to the user includes inline recovery guidance. Users watching a 30-minute run see every step instead of 20 minutes of silence.

## 2. Context and motivation

The April 2026 UX audit graded observability **C** and identified four structural problems:

1. **Silent sub-agent dispatch.** During `IMPLEMENT` and `REVIEW`, the orchestrator can spend 20+ minutes dispatching 8 reviewer agents or 3 impl tasks with **no user-visible progress** between batch start and completion. Child agents do not appear in the task list.
2. **Invisible cost.** `state.json.tokens` tracks token counts, but nothing streams cost to the user during the run. A pipeline can spend $5+ before the user learns the cumulative spend.
3. **Invisible hook failures.** `.forge/.hook-failures.log` captures every PostToolUse check-engine failure (L0 syntax, L1 regex, L2 linter) but users never see the file. A user whose tree-sitter L0 check has been silently failing for a week has no signal.
4. **Errors escalate without guidance.** When orchestrator emits an `AskUserQuestion` on LINT_FAILURE or CONTEXT_OVERFLOW, the options are correct but no inline recovery guidance appears — user must leave the terminal to understand what each option means.

No backwards compatibility is required (single-user plugin).

Phase 2 stays narrowly scoped: **observability surface only.** No change to recovery logic, no change to convergence, no new agents.

## 3. Non-goals

- **No new agents.** All work uses existing agents and primitives.
- **No change to recovery *logic*.** Recovery engine strategy selection, retry budget, and convergence remain identical. Recovery becomes *visible* (tasks emitted during non-transient recovery) but behaves the same.
- **No change to L0/L1/L2 check-engine *rules*.** Hook failure surfacing is read-only — it displays failures the check engine already logged.
- **No UI framework dependency.** All observability rides on existing `TaskCreate`/`TaskUpdate` tools and `.forge/events.jsonl`. No TUI, no web dashboard in this phase (deferred to Phase 5: `/forge-watch`).
- **No cost-model-routing changes.** `shared/model-routing.md` fast/standard/premium tier selection is unchanged. Cost tracking observes what routing decides.
- **Deferred to later phases:**
  - `/forge-watch` TUI with multi-agent panes → Phase 5
  - Editable plan file + escalation taxonomy → Phase 4
  - Preview-before-apply overlay → Phase 4

## 4. Design

### 4.1 Hierarchical sub-agent `TaskCreate` contract

**New rule (mandatory agent contract, bats-enforced):** Every agent whose `tools:` list includes `Agent` MUST, before every sub-agent dispatch:

1. `TaskCreate` a child task with status `pending` (implicit QUEUED semantic), subject template `{color_dot} {agent_id} {short_purpose}`.
2. Immediately before `Agent` invocation: `TaskUpdate` status → `in_progress`.
3. Immediately after `Agent` return: `TaskUpdate` status → `completed` with `metadata.summary` = agent's exit verdict.

**Affected agents (15 dispatchers today):** `fg-010-shaper`, `fg-015-scope-decomposer`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`, `fg-090-sprint-orchestrator`, `fg-100-orchestrator`, `fg-103-cross-repo-coordinator`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`, `fg-200-planner`, `fg-310-scaffolder`, `fg-400-quality-gate`, `fg-500-test-gate`, `fg-590-pre-ship-verifier`, `fg-600-pr-builder`.

(The enforcement is criterion-based: "every agent with `Agent` in `tools:`" — future phases that add new dispatch agents inherit the contract automatically.)

**Color-dot prefix** is sourced from the dispatched agent's `color:` frontmatter field (defined in `shared/agent-colors.md` from Phase 1) mapped through a fixed `shared/color-to-emoji-map.json` (new):

| Color | Emoji |
|---|---|
| magenta | 🟣 |
| pink | 🌸 |
| purple | 🟪 |
| orange | 🟧 |
| coral | 🔶 |
| cyan | 🔵 |
| navy | 🟦 |
| teal | 💚 |
| olive | 🫒 |
| blue | 🔷 |
| crimson | 🟥 |
| yellow | 🟡 |
| green | 🟢 |
| lime | 🍋 |
| red | 🔴 |
| amber | 🟠 |
| brown | 🟤 |
| white | ⚪ |
| gray | ⬜ |

Rendered example of what the user sees during Stage 6 REVIEW:

```
📖 Stage 6: REVIEW
  ├─ 🔵 fg-410 code review (in progress)
  ├─ 🔴 fg-411 security review (completed · 0 CRITICAL)
  ├─ 🟦 fg-412 arch review (completed · 1 WARNING)
  ├─ 🟩 fg-419 infra review (queued)
  ├─ ⬜ fg-413 frontend review (queued)
  ├─ 🟠 fg-416 perf review (queued)
  ├─ 🟪 fg-417 dep review (queued)
  └─ ⚪ fg-418 docs review (queued)
📖 Stage 6: REVIEW • $0.41
```

**Parent-child relationship.** Child tasks use the existing `TaskUpdate addBlockedBy: [stageParentTaskId]` mechanism to indicate hierarchy; Claude Code's task renderer uses `blockedBy` chains to indent. No new task field needed.

### 4.2 Cost streaming (4 channels)

All four channels from brainstorming lock in.

#### 4.2.1 New files

- **`shared/forge-cost-tracker.sh`** (bash script, POSIX-safe) — companion to existing `shared/forge-token-tracker.sh`. Called by orchestrator after every `Agent` return. Reads token counts from `state.json.tokens`, looks up per-model pricing in `shared/model-pricing.json`, computes `$cost`, appends to `.forge/events.jsonl`, and updates `state.json.tokens.run_cost_usd` atomically via `forge-state-write.sh`.

- **`shared/model-pricing.json`** (new, versioned with plugin) — authoritative per-model per-1K-token prices:
  ```json
  {
    "version": "2026-04-16",
    "models": {
      "claude-opus-4-7": {"input_per_1k": 0.015, "output_per_1k": 0.075},
      "claude-opus-4-7-1m": {"input_per_1k": 0.018, "output_per_1k": 0.090},
      "claude-sonnet-4-6": {"input_per_1k": 0.003, "output_per_1k": 0.015},
      "claude-haiku-4-5-20251001": {"input_per_1k": 0.0008, "output_per_1k": 0.004}
    },
    "unknown_model_fallback": {"input_per_1k": 0.015, "output_per_1k": 0.075}
  }
  ```
  Price updates ship as plugin minor releases; users can override via `shared/model-pricing.local.json` if they have negotiated rates.

- **`shared/cost-tracking.md`** — contract doc describing emission points, schema, and how `cost_cap` escalation interacts with recovery.

#### 4.2.2 Event schema for `.forge/events.jsonl`

New event type appended by `forge-cost-tracker.sh`:

```json
{
  "ts": "2026-04-16T10:23:15Z",
  "type": "cost.inc",
  "run_id": "run-17",
  "stage": 5,
  "agent": "fg-300-implementer",
  "model": "claude-sonnet-4-6",
  "tokens_in": 12400,
  "tokens_out": 892,
  "cost_usd": 0.0508,
  "run_cost_usd": 0.3243,
  "cap_usd": 5.00
}
```

`shared/event-log.md` §`Event types` table gains a `cost.inc` row.

#### 4.2.3 Per-stage TaskCreate with cost

Orchestrator, when creating the stage-parent task, uses subject:
```
📖 Stage {N}: {NAME}
```
and `TaskUpdate`s the subject on every `cost.inc` event during that stage:
```
📖 Stage {N}: {NAME} • ${stage_cost_usd}
```
The `{stage_cost_usd}` is the sum of all `cost.inc` events whose `stage == N` for the current run.

#### 4.2.4 Session-start status badge

`hooks/session-start.sh` already displays a status badge (version + run number + stage). Extension: append cost:

```
Forge 3.1.0 • Run 17 • Stage 5/10 • $0.32
```

Cost sourced from `state.json.tokens.run_cost_usd` (kept live by `forge-cost-tracker.sh`).

#### 4.2.5 Hard cost cap with escalation

New config field in `forge.local.md` / `forge-config.md`:

```yaml
cost_cap:
  usd: 5.00                # 0 disables; any positive sets the cap
  action_on_breach: ask    # ask | abort | warn_continue
```

When `run_cost_usd` reaches `cap_usd` (emitted by `forge-cost-tracker.sh` as `cap.breach` event), orchestrator dispatches `AskUserQuestion` Pattern 3 (safe-default escalation):

```json
{
  "question": "Run has spent $5.01 — hit cost cap. Current stage: 6 REVIEW. How to proceed?",
  "header": "Cost cap",
  "multiSelect": false,
  "options": [
    {"label": "Raise cap to $10 and continue (Recommended)", "description": "Doubles cap; resets breach. Recorded in state.json.cost_cap_decisions for retrospective."},
    {"label": "Abort this run gracefully", "description": "Stops at next stage boundary; preserves state for /forge-recover resume."},
    {"label": "Force-continue with no cap", "description": "Removes cap for this run only. Dangerous on misconfigured model routing."}
  ]
}
```

Decision recorded in `state.json.cost_cap_decisions` (new field in schema):

```json
{
  "cost_cap_decisions": [
    {"ts": "2026-04-16T10:23:15Z", "at_cost_usd": 5.01, "decision": "raise_to_10", "new_cap_usd": 10.00}
  ]
}
```

When `action_on_breach: abort`, orchestrator emits `cap.breach` event and proceeds to `ABORTED` state directly (no `AskUserQuestion`). When `warn_continue`, orchestrator emits a warning event and proceeds without pause.

### 4.3 Hook failure visibility

#### 4.3.1 Session-start banner

`hooks/session-start.sh` extended with new function `print_hook_failure_banner()`:

1. Reads `.forge/.hook-failures.log` if file exists.
2. Filters entries from last `observability.hook_failure_surface_window_hours` hours (default 24, configurable).
3. If ≥1 entry, emits stderr banner:
   ```
   ⚠️  {N} hook {type} failures in last {H}h (last: {summary}).
       Run /forge-recover diagnose --hooks for details.
   ```
4. Log truncation: after emitting banner, if file has >100 lines, truncate to last 50 via `tail -n 50 > ...`. Keeps log bounded.

No new state field; the log file itself is the state.

#### 4.3.2 `/forge-recover diagnose --hooks` flag

`skills/forge-recover/SKILL.md` (from Phase 1) adds `--hooks` to the `diagnose` subcommand's `## Flags` section:

```
- --hooks: include hook-failure analysis in the diagnose report
```

The orchestrator's recovery-diagnose handler (`fg-100-orchestrator.md §Recovery op dispatch`) gains a branch: when `recovery_op == "diagnose" && --hooks is set`:
- Loads `.forge/.hook-failures.log`
- Groups failures by `{hook_script, error_type}`
- Identifies top failing hook by count
- For L0 (tree-sitter) failures, lists "problem files" (files with >3 failures)
- Emits recommendation: if L0 is timing out on N files, suggest `check_engine.l0_timeout_ms` increase
- If L2 linter adapter is missing (e.g., `ruff` not installed), suggests installation command

Output is human-readable by default; `--json` (already advertised on diagnose in Phase 1) returns structured.

#### 4.3.3 Hook log schema

`.forge/.hook-failures.log` format (append-only, one JSON per line):

```json
{"ts": "2026-04-16T10:23:15Z", "hook": "engine.sh", "type": "L0_TIMEOUT", "file": "src/big.ts", "duration_ms": 5012, "message": "tree-sitter parse exceeded 5s"}
```

This format is the schema the new banner consumer expects. Plan-writing step will verify — by reading `shared/checks/engine.sh` — that hooks already emit this exact schema; if not, add a thin conversion pass in `engine.sh` to match.

### 4.4 Error recovery docs + inline guidance

#### 4.4.1 `docs/error-recovery.md` (new)

Human-readable mapping of all 22 error types from `shared/error-taxonomy.md`. Format per entry:

```markdown
## {ERROR_NAME}

**Symptom.** What the user sees (terminal text, stage outcome).

**Severity.** CRITICAL | HIGH | MEDIUM | LOW (from taxonomy).

**What Forge tried.** Auto-retry behavior. Reference to recovery strategy (from `shared/recovery/recovery-engine.md`).

**What to do now.**
- Step-by-step user action.
- Command suggestions with exact invocation.
- Links to the relevant taxonomy, recovery-engine, or learnings file.

**Example log line.** One concrete example of the error appearing in stage notes or events.
```

All 22 entries land in one document — a flat catalog, grep-able by error name. Long (~500 lines expected) but reference-quality.

#### 4.4.2 Inline guidance in `AskUserQuestion` escalations

Every error-triggered `AskUserQuestion` emitted by `fg-100-orchestrator` (and `fg-400-quality-gate`, `fg-500-test-gate`, `fg-210-validator` if it owns any in future phases) MUST include in its `question` field:
- A link to the matching section of `docs/error-recovery.md` (format `docs/error-recovery.md#error_name`)
- A 2-sentence inline summary of cause + what the recommended option does

Example already shown in design section 4 of the brainstorming — full LINT_FAILURE example.

Bats assertion: scan Phase 2-and-later agent `.md` files for `AskUserQuestion` payloads whose `question` field contains `"failed"` or `"error"` but no `docs/error-recovery.md#` reference — flag as a DOC-MISSING violation. Existing Phase 1 payloads (happy-path examples) are exempt.

#### 4.4.3 Update to `shared/error-taxonomy.md`

Add a new column `user_guide:` to each of the 22 error entries pointing at the anchor in `docs/error-recovery.md`. Example:
```markdown
| LINT_FAILURE | MEDIUM | Agent-reported | 3-retry auto-fix | docs/error-recovery.md#lint_failure |
```

### 4.5 Recovery-engine `TaskCreate` for non-transient recoveries

`shared/recovery/recovery-engine.md` extended with the emission rule:

**Rule.** For every recovery **strategy** (not every retry), the agent applying the strategy MUST `TaskCreate` a task with subject `🛟 Recovering from {error_type}: {strategy_name}` at `pending`, `TaskUpdate` to `in_progress` when the strategy begins, `TaskUpdate` to `completed` with outcome in `metadata.outcome`.

**Exception — transient recoveries NOT emitted as tasks:**
- `FLAKY_TEST` single-retry (picked up by mutation analyzer OR quarantine)
- Any recovery with `strategy: wait_and_retry` and `wait_ms < 1000`

**Rationale.** Transient retries would flood the task list with `🛟 Recovering from NETWORK_TIMEOUT` entries. Non-transient recoveries (state-reconstruction, resource-cleanup, tool-diagnosis) are infrequent and high-signal.

Bats-enforced at the recovery-engine contract level (`tests/contract/recovery-engine.bats` — assume exists; extend with new assertion).

### 4.6 Deferred Phase 1 item — runtime integration test

Phase 1 deferred true runtime `--dry-run` verification of `/forge-recover`. Phase 2 adds the fixtures.

**New file: `tests/helpers/forge-fixture.sh`** — helper library for creating a temporary `.forge/` directory seeded with deterministic state. Used by runtime integration tests across later phases.

Helper API:
```bash
forge_fixture_create       # creates ./forge-fixture.{random}/.forge/ with seed state, returns path
forge_fixture_destroy PATH  # rm -rf the fixture
forge_fixture_snapshot PATH # writes PATH.snapshot with sorted file list + hashes
forge_fixture_diff PATH     # diff PATH.snapshot against current state; returns 0 if identical
```

**New file: `tests/unit/skill-execution/forge-recover-runtime.bats`** — invokes `/forge-recover repair --dry-run` and `/forge-recover reset --dry-run` against a fixture, snapshots before and after, asserts zero writes.

This closes Phase 1 AC #23's original scope (runtime verification).

### 4.7 Observability contract doc

**New file: `shared/observability-contract.md`** — authoritative reference:

- §1 Hierarchical `TaskCreate` rule (from §4.1 above)
- §2 Color-to-emoji mapping reference
- §3 Event types + schemas (`cost.inc`, `cap.breach`, `task.create`, `task.update`, `hook.failure`, `recovery.start`, `recovery.end`)
- §4 Cost cap + escalation flow
- §5 Hook failure banner mechanics
- §6 Error-recovery doc + inline guidance rule
- §7 Recovery-engine `TaskCreate` rule
- §8 Enforcement map (which bats file enforces each rule)

This is the single entry point an agent author reads when implementing a new dispatching agent in Phase 6+.

### 4.8 Configuration additions

`forge.local.md` / `forge-config.md` gains:

```yaml
observability:
  sub_agent_tasks: hierarchical   # hierarchical | flat | off
  hook_failure_surface_window_hours: 24
  hook_failure_log_max_entries: 100
  hook_failure_log_truncate_to: 50
  cost_streaming: true
  recovery_tasks: non_transient   # non_transient | all | off

cost_cap:
  usd: 5.00
  action_on_breach: ask           # ask | abort | warn_continue
```

All defaults match the audit recommendations. Sensible starting values.

### 4.9 Documentation updates

- `README.md` — add section "Observability" linking to `shared/observability-contract.md`; note cost streaming + hook banner features; version bump.
- `CLAUDE.md` — add 4 new rows to Key Entry Points table (`observability-contract.md`, `cost-tracking.md`, `model-pricing.json`, `docs/error-recovery.md`); note 3.1.0 version; no skill table changes.
- `CHANGELOG.md` — 3.1.0 entry.
- `.claude-plugin/plugin.json` — `"3.0.0"` → `"3.1.0"`.
- `.claude-plugin/marketplace.json` — `"3.0.0"` → `"3.1.0"`.
- `DEPRECATIONS.md` — no changes (no removals this phase).

## 5. File manifest (authoritative)

### 5.1 Create (9 files)

```
docs/error-recovery.md                                     # user-facing 22-error map
shared/observability-contract.md                           # authoritative contract
shared/cost-tracking.md                                    # cost stream contract
shared/model-pricing.json                                  # per-model per-1K rates
shared/color-to-emoji-map.json                             # hue → emoji lookup
shared/forge-cost-tracker.sh                               # companion to forge-token-tracker.sh
tests/contract/observability.bats                          # hierarchical TaskCreate + event schema assertions
tests/unit/skill-execution/forge-recover-runtime.bats      # closes Phase 1 AC #23
tests/helpers/forge-fixture.sh                             # fixture helpers for runtime tests
```

### 5.2 Update in place

**Agent `.md` files — 15 dispatchers:**

`fg-010-shaper.md`, `fg-015-scope-decomposer.md`, `fg-020-bug-investigator.md`, `fg-050-project-bootstrapper.md`, `fg-090-sprint-orchestrator.md`, `fg-100-orchestrator.md`, `fg-103-cross-repo-coordinator.md`, `fg-150-test-bootstrapper.md`, `fg-160-migration-planner.md`, `fg-200-planner.md`, `fg-310-scaffolder.md`, `fg-400-quality-gate.md`, `fg-500-test-gate.md`, `fg-590-pre-ship-verifier.md`, `fg-600-pr-builder.md`.

Each receives a new `## Sub-agent dispatch (mandatory pre/post TaskCreate)` section citing `shared/observability-contract.md §1`.

**Agent `.md` — orchestrator (additional changes):**

`agents/fg-100-orchestrator.md` — additionally gets:
- `## Cost cap escalation` section
- `## Hook-failure diagnose branch` section (for `/forge-recover diagnose --hooks`)
- Existing `## Recovery op dispatch` section (from Phase 1) extended with the `--hooks` branch

**Shared docs:**

- `shared/event-log.md` — extend Event types table with `cost.inc`, `cap.breach`, `hook.failure`, `recovery.start`, `recovery.end`.
- `shared/state-schema.md` — add `cost_cap_decisions` field to state payload; bump schema version 1.7.0 → 1.8.0.
- `shared/error-taxonomy.md` — add `user_guide:` column pointing to `docs/error-recovery.md#` anchors for each of 22 entries.
- `shared/recovery/recovery-engine.md` — add `## Task emission rule` section.
- `shared/agent-ui.md` — cross-reference `shared/observability-contract.md §1` from the tier table (stage 1/2 agents inherit hierarchical task requirement).

**Hooks:**

- `hooks/session-start.sh` — add `print_hook_failure_banner()` function + integrate cost into existing status badge.

**Skill:**

- `skills/forge-recover/SKILL.md` — add `--hooks` flag description under `diagnose` subcommand.

**Tests:**

- `tests/contract/recovery-engine.bats` (assume exists — verify during plan-writing) — extend with task-emission rule assertion.
- `tests/contract/ui-frontmatter-consistency.bats` — extend with sub-agent-dispatch assertion: every agent whose `tools:` includes `Agent` must reference `shared/observability-contract.md` in body.

**Top-level:**

- `README.md`, `CLAUDE.md`, `CHANGELOG.md`
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`

### 5.3 File-count arithmetic

| Category | Count |
|---|---|
| Creations | 9 |
| Dispatch agent updates | 15 |
| Orchestrator additional updates | 1 (overlap with above — counted once; 3 new sections added) |
| Shared doc updates | 5 |
| Hook update | 1 |
| Skill update | 1 |
| Test updates | 2 |
| Top-level docs + config | 5 |
| **Total unique files touched** | **9 + 15 + 5 + 1 + 1 + 2 + 5 = 38 unique files** |

## 6. Acceptance criteria

All verified by CI on push. No local test runs permitted.

1. `docs/error-recovery.md` exists with all 22 error entries matching `shared/error-taxonomy.md` names.
2. `shared/observability-contract.md` exists with 8 sections (§1-§8 per design §4.7).
3. `shared/cost-tracking.md` exists and is referenced from `shared/event-log.md`.
4. `shared/model-pricing.json` parses as valid JSON and lists at least 4 models (`claude-opus-4-7`, `claude-opus-4-7-1m`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`).
5. `shared/color-to-emoji-map.json` parses as valid JSON and covers all 18 palette colors from `shared/agent-colors.md`.
6. `shared/forge-cost-tracker.sh` exists with `#!/usr/bin/env bash` shebang and `chmod +x`.
7. Each of the 15 dispatch agent `.md` files contains a `## Sub-agent dispatch` section referencing `shared/observability-contract.md §1`.
8. `agents/fg-100-orchestrator.md` contains `## Cost cap escalation` and `## Hook-failure diagnose branch` sections.
9. `shared/event-log.md` Event types table contains `cost.inc`, `cap.breach`, `hook.failure`, `recovery.start`, `recovery.end`.
10. `shared/state-schema.md` documents `cost_cap_decisions` field; schema version is 1.8.0.
11. `shared/error-taxonomy.md` has `user_guide:` column for all 22 entries; every anchor resolves (link-checker assertion in bats).
12. `shared/recovery/recovery-engine.md` contains `## Task emission rule` section.
13. `shared/agent-ui.md` cross-references `shared/observability-contract.md §1`.
14. `hooks/session-start.sh` contains `print_hook_failure_banner()` function; static parse check passes.
15. `hooks/session-start.sh` status badge output (example) includes `$` character (cost indicator).
16. `skills/forge-recover/SKILL.md` `## Flags` section lists `--hooks`.
17. `tests/contract/observability.bats` contains ≥6 assertions (one per observability subsection).
18. `tests/contract/ui-frontmatter-consistency.bats` gains the sub-agent-dispatch assertion; every agent with `Agent` in tools passes.
19. `tests/contract/recovery-engine.bats` contains the task-emission-rule assertion.
20. `tests/unit/skill-execution/forge-recover-runtime.bats` exists and uses `tests/helpers/forge-fixture.sh`.
21. `tests/helpers/forge-fixture.sh` exists with `chmod +x` and exports `forge_fixture_create`, `forge_fixture_destroy`, `forge_fixture_snapshot`, `forge_fixture_diff`.
22. Configuration schema (`shared/config-schema.json` — assume exists; verify during plan) documents new `observability.*` and `cost_cap.*` fields.
23. `README.md`, `CLAUDE.md`, `CHANGELOG.md` updated per §4.9.
24. `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions set to `3.1.0`.
25. CI green on push — no local test runs permitted.

## 7. Test strategy

**Static validation (bats, CI-only):**

- **New `tests/contract/observability.bats`** covers AC #2, #4, #5, #7, #9, #17.
- **Extended `tests/contract/ui-frontmatter-consistency.bats`** covers AC #7, #18.
- **Extended `tests/contract/recovery-engine.bats`** covers AC #12, #19.
- **Extended `tests/validate-plugin.sh`** gets a cross-link validator: every anchor in `docs/error-recovery.md` must resolve to a real heading; every `user_guide:` entry in taxonomy must hit a real anchor.

**Runtime validation (bats, CI-only):**

- **New `tests/unit/skill-execution/forge-recover-runtime.bats`** — actual end-to-end test of `--dry-run` behavior using the fixture helpers. This closes Phase 1 AC #23.

Per user instruction: no local test runs; CI on push is the source of truth.

## 8. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Hierarchical TaskCreate overhead inflates agent prompts significantly | Medium | Medium | Per-dispatch overhead ≤50 tokens (TaskCreate + TaskUpdate calls). 15 dispatch agents × ~30 dispatches/run avg = ~22,500 tokens. <2% of typical run. Acceptable. |
| Cost streaming misfires when model name not in `model-pricing.json` | Medium | Low | `unknown_model_fallback` price in pricing.json (conservative — opus-equivalent). Emits warning event `cost.model_unknown`. |
| Hook failure banner is noisy when project has transient tree-sitter issues | Medium | Low | Banner collapses multiple failures by type; shows count + last. User can raise `observability.hook_failure_surface_window_hours` to reduce sensitivity. |
| `docs/error-recovery.md` drifts from `shared/error-taxonomy.md` entries | High | Medium | Cross-link validator in `validate-plugin.sh` (AC #11); fails CI on missing anchors or entries. |
| `.forge/events.jsonl` grows unbounded under cost streaming | Low | Medium | Existing `events.jsonl` retention config (F07) applies; Phase 2 does not change retention. Document event-rate estimate (~100 events per typical run). |
| Cost cap escalation interacts badly with autonomous mode | Low | Medium | Autonomous config honors `cost_cap.action_on_breach`; if `ask`, logs as `[AUTO: cap breach deferred]` and proceeds with `abort` fallback. Documented in `shared/modes/` overlay notes. |
| Fixture helpers (`tests/helpers/forge-fixture.sh`) need platform-specific stat for snapshot hashing | Medium | Low | Use `shasum` (cross-platform), fall back to `sha256sum`. Helper file's own shebang + chmod checked in AC #21. |
| `shared/model-pricing.json` needs regular updates as prices change | Low | Low | Versioned file; plugin minor releases update it; users can override via `shared/model-pricing.local.json`. |

## 9. Rollout (one PR, multi-commit; CI gates on HEAD)

Order chosen so every commit is independently CI-green.

1. **Commit 1 — Specs land.** This spec + implementation plan into `docs/superpowers/`.
2. **Commit 2 — Foundations.** `shared/observability-contract.md`, `shared/cost-tracking.md`, `shared/model-pricing.json`, `shared/color-to-emoji-map.json`, `shared/forge-cost-tracker.sh`, `docs/error-recovery.md`, `tests/contract/observability.bats` (skeleton, assertions inactive until referenced files exist), `tests/helpers/forge-fixture.sh`, `tests/unit/skill-execution/forge-recover-runtime.bats`. CI green.
3. **Commit 3 — Agent contract.** 15 dispatch agent `.md` updates + `shared/agent-ui.md` cross-reference. `tests/contract/ui-frontmatter-consistency.bats` extended with sub-agent-dispatch assertion. CI green.
4. **Commit 4 — Orchestrator + hook + skill.** `agents/fg-100-orchestrator.md` gets 3 new sections. `hooks/session-start.sh` adds banner + cost. `skills/forge-recover/SKILL.md` gets `--hooks` flag. `shared/event-log.md` and `shared/state-schema.md` updated for new event types and `cost_cap_decisions`. `shared/error-taxonomy.md` gets `user_guide:` column. `shared/recovery/recovery-engine.md` gets task-emission rule. `tests/contract/recovery-engine.bats` extended. `tests/validate-plugin.sh` gets cross-link validator. CI green.
5. **Commit 5 — Config schema.** `shared/config-schema.json` (or equivalent — verify during plan-writing) gains `observability.*` and `cost_cap.*` fields with defaults. CI green.
6. **Commit 6 — Top-level docs + version bump.** `README.md`, `CLAUDE.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`. CI green.
7. **Push → CI gate on HEAD → on green, tag `v3.1.0` → release.**

## 10. Versioning rationale (SemVer minor)

Phase 2 is purely additive. New files, new agent sections, new config fields (all with safe defaults), new event types, new bats assertions. No breaking changes. → `3.0.0` → `3.1.0`.

## 11. Open questions

None. All decisions locked during brainstorming.

## 12. References

- Phase 1 spec (`docs/superpowers/specs/2026-04-16-phase1-skill-surface-consolidation-design.md`) — depends on `/forge-recover` and `shared/agent-colors.md`
- `shared/error-taxonomy.md` — source of the 22 error entries
- `shared/recovery/recovery-engine.md` — 7 strategies + retry budget
- `shared/event-log.md` (F07) — event schema extension target
- `shared/agent-ui.md` — UI tier contract (post-Phase-1)
- `shared/agent-colors.md` — 42-agent color map (Phase 1 deliverable)
- April 2026 UX audit (conversation memory) — originated Phase 2 deliverables
- User instruction: "I want it all except the backwards compatibility"
