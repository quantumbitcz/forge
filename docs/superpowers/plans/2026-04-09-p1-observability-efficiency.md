# P1: Observability & Efficiency — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add token budget tracking, LLM decision quality observability, extract Phase A to a dedicated agent, consolidate Linear operations, introduce mode config overlays, fix hook architecture, and add INFO efficiency policy.

**Architecture:** Builds on P0's `forge-state.sh` and `forge-state-write.sh` for state management. New scripts (`forge-token-tracker.sh`, `forge-linear-sync.sh`) follow the same bash+python3 pattern. Mode overlays are YAML-frontmatter markdown files in `shared/modes/`. Hook fixes modify `engine.sh` in-place.

**Tech Stack:** Bash 4.0+, Python 3 (embedded), bats testing framework.

**Spec:** `docs/superpowers/specs/2026-04-09-forge-hardening-design.md` (sections P1-1 through P1-7)

**Depends on:** P0 (Reliability Foundation) must be complete.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `shared/forge-token-tracker.sh` | Token estimation, recording, budget checking |
| Create | `shared/forge-linear-sync.sh` | Event-driven Linear sync (fire-and-forget) |
| Create | `agents/fg-505-build-verifier.md` | Build + lint verification with fix loop |
| Create | `shared/modes/standard.md` | Standard mode overlay (no overrides) |
| Create | `shared/modes/bugfix.md` | Bugfix mode stage overrides |
| Create | `shared/modes/migration.md` | Migration mode stage overrides |
| Create | `shared/modes/bootstrap.md` | Bootstrap mode stage overrides |
| Create | `shared/modes/testing.md` | Testing mode stage overrides |
| Create | `shared/modes/refactor.md` | Refactor mode stage overrides |
| Create | `shared/modes/performance.md` | Performance mode stage overrides |
| Modify | `shared/state-schema.md` | Add `tokens`, `decision_quality` sections |
| Modify | `shared/state-transitions.md` | Add row E8 (token_budget_exhausted) |
| Modify | `shared/checks/output-format.md` | Add confidence field |
| Modify | `shared/checks/engine.sh` | File locks, failure logging |
| Modify | `shared/state-integrity.sh` | Decision log validation |
| Modify | `shared/decision-log.md` | Confidence and agreement fields |
| Modify | `shared/scoring.md` | INFO efficiency policy |
| Modify | `shared/convergence-engine.md` | unfixable_info_count field |
| Modify | `hooks/hooks.json` | Increase engine.sh timeout to 10s |
| Modify | `agents/fg-400-quality-gate.md` | Reviewer agreement tracking |
| Modify | `agents/fg-700-retrospective.md` | Decision quality section |
| Modify | `agents/fg-200-planner.md` | Decision log instruction |
| Modify | `agents/fg-210-validator.md` | Decision log instruction |
| Modify | `agents/fg-300-implementer.md` | Decision log instruction |
| Modify | `agents/fg-100-orchestrator-execute.md` | Update §5.1 for fg-505 dispatch |
| Create | `tests/unit/forge-token-tracker.bats` | Token tracker tests |
| Create | `tests/contract/mode-overlay-contract.bats` | Mode overlay validation |

---

## Task 1: Token Budget Tracker

**Files:**
- Create: `shared/forge-token-tracker.sh`
- Create: `tests/unit/forge-token-tracker.bats`
- Modify: `shared/state-schema.md` (add `tokens` section)
- Modify: `shared/state-transitions.md` (add row E8)

- [ ] **Step 1: Write failing tests for forge-token-tracker.sh**

Create `tests/unit/forge-token-tracker.bats` with tests for:
- Script exists and is executable
- `estimate` command: counts chars/4 from a file, outputs integer
- `record` command: updates `state.json.tokens.by_stage[stage]` and `by_agent[agent]` via `forge-state-write.sh`
- `record` command: increments `tokens.estimated_total`
- `check` command: exits 0 when under budget, exit 1 at 80%, exit 2 when exceeded
- `check` command: works when `tokens.budget_ceiling` is 0 (no limit → always exit 0)

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/unit/forge-token-tracker.bats`

- [ ] **Step 3: Implement forge-token-tracker.sh**

Script accepts: `estimate <file>`, `record <stage> <agent> <input> <output> [--forge-dir]`, `check [--forge-dir]`. Uses `forge-state-write.sh` for atomic state updates.

- [ ] **Step 4: Update state-schema.md with tokens section**

Add the `tokens` object with all fields documented, defaults, and field reference.

- [ ] **Step 5: Add row E8 to state-transitions.md**

```
| E8 | ANY | token_budget_exhausted | tokens.estimated_total >= budget_ceiling AND budget_ceiling > 0 | ESCALATED | Token budget exceeded, escalate to user |
```

- [ ] **Step 6: Update forge-state.sh to handle E8 transition**

Add the `token_budget_exhausted` event to the error transitions in `forge-state.sh`.

- [ ] **Step 7: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 8: Commit**

```bash
git add shared/forge-token-tracker.sh tests/unit/forge-token-tracker.bats shared/state-schema.md shared/state-transitions.md shared/forge-state.sh
git commit -m "feat: add token budget tracking with ceiling enforcement"
```

---

## Task 2: LLM Decision Quality Observability

**Files:**
- Modify: `shared/checks/output-format.md` (confidence field)
- Modify: `shared/decision-log.md` (confidence + agreement fields)
- Modify: `shared/state-integrity.sh` (decision log validation)
- Modify: `shared/state-schema.md` (decision_quality section)
- Modify: `agents/fg-400-quality-gate.md` (agreement tracking)
- Modify: `agents/fg-700-retrospective.md` (decision quality section)
- Modify: `agents/fg-200-planner.md` (decision log instruction)
- Modify: `agents/fg-210-validator.md` (decision log instruction)
- Modify: `agents/fg-300-implementer.md` (decision log instruction)

- [ ] **Step 1: Add confidence field to output-format.md**

Append `| confidence:HIGH` as optional 6th pipe-separated field. Document HIGH/MEDIUM/LOW values. Note: default HIGH if omitted (backwards compatible).

- [ ] **Step 2: Add decision_quality section to state-schema.md**

Add the `decision_quality` object with `reviewer_agreement_rate`, `findings_with_low_confidence`, `overridden_findings`, `total_decisions_logged`. All default 0.

- [ ] **Step 3: Update decision-log.md with confidence and agreement fields**

Add `confidence` (HIGH/MEDIUM/LOW) to the decision entry schema. Add `agreement` field for quality gate conflict resolutions.

- [ ] **Step 4: Add decision log validation to state-integrity.sh**

After section 9 (evidence freshness), add section 10 that validates `decisions.jsonl` lines are valid JSON with required fields (`ts`, `decision`).

- [ ] **Step 5: Add reviewer agreement tracking to fg-400-quality-gate.md**

Add a section after deduplication that compares findings on same (file, line) from different reviewers. Record agreement rate in stage notes and `state.json.decision_quality`.

- [ ] **Step 6: Add decision quality section to fg-700-retrospective.md**

Add the "Decision Quality" report section per the spec (P1-2 A6d).

- [ ] **Step 7: Add decision log instruction to fg-200, fg-210, fg-300**

One-line addition to each agent: `"Append decisions to .forge/decisions.jsonl per shared/decision-log.md."`

- [ ] **Step 8: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 9: Commit**

```bash
git add shared/checks/output-format.md shared/decision-log.md shared/state-integrity.sh shared/state-schema.md agents/fg-400-quality-gate.md agents/fg-700-retrospective.md agents/fg-200-planner.md agents/fg-210-validator.md agents/fg-300-implementer.md
git commit -m "feat: add LLM decision quality observability (confidence, agreement, validation)"
```

---

## Task 3: Extract Phase A Build Verifier Agent

**Files:**
- Create: `agents/fg-505-build-verifier.md`
- Modify: `agents/fg-100-orchestrator-execute.md` (update §5.1)

- [ ] **Step 1: Create fg-505-build-verifier.md**

Write the agent with frontmatter (`name: fg-505-build-verifier`, tools: Read/Write/Edit/Grep/Glob/Bash/TaskCreate/TaskUpdate, ui.tasks: true). Body: accept commands.build, commands.lint, inline_checks, max_fix_loops. Run build → lint → inline checks. On failure: analyze, fix, re-run (up to max_fix_loops). Return structured JSON verdict.

- [ ] **Step 2: Update orchestrator execute §5.1**

Replace the inline build+lint fallback with: "Dispatch `fg-505-build-verifier`" as the primary path. Remove the "if available" condition since the agent now exists.

- [ ] **Step 3: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 4: Commit**

```bash
git add agents/fg-505-build-verifier.md agents/fg-100-orchestrator-execute.md
git commit -m "feat: extract Phase A verification to fg-505-build-verifier agent"
```

---

## Task 4: Linear Event Consolidation

**Files:**
- Create: `shared/forge-linear-sync.sh`
- Modify: `agents/fg-100-orchestrator-boot.md` (replace Linear blocks)
- Modify: `agents/fg-100-orchestrator-execute.md` (replace Linear blocks)
- Modify: `agents/fg-100-orchestrator-ship.md` (replace Linear blocks)

- [ ] **Step 1: Create forge-linear-sync.sh**

Script accepts `emit <event-type> <event-json> [--forge-dir]`. Checks Linear availability from `state.json.integrations.linear.available`. If available: processes via Linear MCP. If not: logs to `.forge/linear-events.jsonl` and exits 0. Truncates log at 100 entries. Never returns non-zero.

- [ ] **Step 2: Replace Linear blocks in all 3 orchestrator phase files**

Search for all `If integrations.linear.available` blocks. Replace each with a single `forge-linear-sync.sh emit` call matching the event type table from the spec.

- [ ] **Step 3: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 4: Commit**

```bash
git add shared/forge-linear-sync.sh agents/fg-100-orchestrator-boot.md agents/fg-100-orchestrator-execute.md agents/fg-100-orchestrator-ship.md
git commit -m "feat: consolidate Linear tracking into event-driven forge-linear-sync.sh"
```

---

## Task 5: Mode Config Overlays

**Files:**
- Create: `shared/modes/standard.md`
- Create: `shared/modes/bugfix.md`
- Create: `shared/modes/migration.md`
- Create: `shared/modes/bootstrap.md`
- Create: `shared/modes/testing.md`
- Create: `shared/modes/refactor.md`
- Create: `shared/modes/performance.md`
- Create: `tests/contract/mode-overlay-contract.bats`

- [ ] **Step 1: Write contract tests for mode overlays**

Create `tests/contract/mode-overlay-contract.bats` that validates:
- All 7 mode files exist in `shared/modes/`
- Each has valid YAML frontmatter with `mode` field
- Each `mode` field matches the filename
- Referenced agents in `stages.*.agent` exist in `agents/` directory
- `stages` keys are valid stage names (explore, plan, validate, implement, review, ship)

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Create all 7 mode overlay files**

Each file has YAML frontmatter with stage overrides extracted from the orchestrator's `if mode ==` branches. **Note:** By this point, the monolithic orchestrator has been deleted (P0 Task 9). The mode-specific content is now in the split files (`fg-100-orchestrator-execute.md` and `fg-100-orchestrator-boot.md`). Extract overrides from those files. The `standard.md` file has empty `stages:` (no overrides — default behavior). The `bugfix.md` file has the overrides per the spec example. Extract migration, bootstrap, testing, refactor, performance overrides from the split orchestrator files.

- [ ] **Step 4: Remove mode-specific if/else branches from orchestrator execute file**

Replace all `if mode == "bugfix"` / `if mode == "migration"` etc. blocks with references to `state.json.mode_config.stages.{stage}`.

- [ ] **Step 5: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 6: Commit**

```bash
git add shared/modes/ tests/contract/mode-overlay-contract.bats agents/fg-100-orchestrator-execute.md agents/fg-100-orchestrator-boot.md
git commit -m "feat: add mode config overlays, remove orchestrator if/else branching"
```

---

## Task 6: Hook Architecture Fixes

**Files:**
- Modify: `shared/checks/engine.sh` (file locks + failure logging)
- Modify: `hooks/hooks.json` (timeout increase)

- [ ] **Step 1: Replace _ENGINE_RUNNING env var with flock in engine.sh**

Find the `_ENGINE_RUNNING` guard and replace with flock-based file lock per spec.

- [ ] **Step 2: Add handle_failure function to engine.sh**

Add the `handle_failure` function that writes to `.forge/.hook-failures.log`. Wire it into existing timeout/error paths.

- [ ] **Step 3: Increase engine.sh timeout in hooks.json**

Change `"timeout": 5` to `"timeout": 10` for the Edit|Write PostToolUse hook.

- [ ] **Step 4: Run existing engine tests**

Run: `./tests/lib/bats-core/bin/bats tests/unit/check-engine.bats`

- [ ] **Step 5: Commit**

```bash
git add shared/checks/engine.sh hooks/hooks.json
git commit -m "fix: replace env var guard with flock, add hook failure logging, increase timeout"
```

---

## Task 7: INFO "Fix if Easy" Policy

**Files:**
- Modify: `shared/scoring.md`
- Modify: `shared/convergence-engine.md`
- Modify: `shared/state-schema.md` (unfixable_info_count already added in P0)

- [ ] **Step 1: Add INFO Efficiency Policy section to scoring.md**

After the Aim-for-100 Policy section, add the "INFO Efficiency Policy" per spec P1-7: first iteration attempts all findings, subsequent iterations mark unfixed INFOs as `unfixable_info`, compute `effective_target = min(target_score, 100 - 2 * unfixable_info_count)`.

- [ ] **Step 2: Update convergence-engine.md with unfixable_info_count tracking**

Add tracking of `unfixable_info_count` in the perfection phase. Document the effective_target computation.

- [ ] **Step 3: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 4: Commit**

```bash
git add shared/scoring.md shared/convergence-engine.md
git commit -m "feat: add INFO 'fix if easy' policy with effective_target computation"
```

---

## Execution Order Summary

| Task | Depends On | Deliverable |
|------|-----------|------------|
| 1 | P0 complete | `forge-token-tracker.sh` + state schema + transition E8 |
| 2 | P0 complete | Decision quality: confidence, agreement, validation |
| 3 | P0 Task 7 (execute file) | `fg-505-build-verifier.md` + orchestrator update |
| 4 | P0 Task 5-8 (all split files) | `forge-linear-sync.sh` + orchestrator updates |
| 5 | P0 Task 5-8 (all split files) | 7 mode overlay files + orchestrator update |
| 6 | — | Hook fixes (independent) |
| 7 | P0 Task 4 (scoring changes) | INFO efficiency policy |

Tasks 1, 2, 6 are independent (can parallelize).
Tasks 3, 4, 5 depend on P0 orchestrator split.
**WARNING: Tasks 3, 4, 5 all modify `fg-100-orchestrator-execute.md` — they MUST be serialized (3 → 4 → 5) to avoid merge conflicts.**
Task 7 depends on P0 scoring changes.
