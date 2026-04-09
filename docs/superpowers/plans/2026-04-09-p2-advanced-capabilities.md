# P2: Advanced Capabilities — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add simulation harness for pipeline testing, improve cross-repo coordination with contract-first protocol, consolidate frontend reviewers, add retrospective guardrails, compress agent prompts, add compaction hook, fix miscellaneous issues, and update all tests/docs.

**Architecture:** Builds on P0 (state machine, orchestrator split) and P1 (token tracking, mode overlays, hooks). The simulation harness uses `forge-state.sh` to validate transition traces. Cross-repo improvements extend existing sprint orchestrator patterns. Reviewer consolidation merges agent markdown files.

**Tech Stack:** Bash 4.0+, Python 3, bats testing framework.

**Spec:** `docs/superpowers/specs/2026-04-09-forge-hardening-design.md` (sections P2-1 through P2-10)

**Depends on:** P0 + P1 must be complete.

**Deferred items:** P2-6 (State Splitting) and P2-7 (Session Boundaries) have explicit trigger conditions and are NOT implemented in this plan.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `shared/forge-sim.sh` | Pipeline simulation harness |
| Create | `shared/forge-timeout.sh` | Pipeline timeout enforcement |
| Create | `shared/forge-compact-check.sh` | Compaction suggestion hook |
| Create | `shared/cross-repo-contracts.md` | Contract-first protocol spec |
| Create | `tests/fixtures/sim/happy-path.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/convergence-improving.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/convergence-plateau.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/convergence-regressing.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/convergence-diminishing.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/pr-rejection-impl.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/pr-rejection-design.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/budget-exhaustion.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/safety-gate-failure.yaml` | Simulation scenario |
| Create | `tests/fixtures/sim/dry-run.yaml` | Simulation scenario |
| Create | `tests/scenario/simulation.bats` | Simulation scenario tests |
| Modify | `agents/fg-413-frontend-reviewer.md` | Absorb fg-414 content with modes |
| Delete | `agents/fg-414-frontend-quality-reviewer.md` | Merged into fg-413 |
| Modify | `agents/fg-700-retrospective.md` | Tuning guardrails |
| Modify | `agents/fg-103-cross-repo-coordinator.md` | Integration verification phase |
| Modify | `shared/sprint-state-schema.md` | Bi-directional dependency support |
| Modify | `hooks/hooks.json` | Add compaction hook |
| Modify | `agents/fg-100-orchestrator-execute.md` | Clean git checkpoints |
| Modify | `tests/validate-plugin.sh` | Structural checks for all new files |
| Modify | `CLAUDE.md` | Reflect new architecture |

---

## Task 1: Simulation Harness

**Files:**
- Create: `shared/forge-sim.sh`
- Create: `tests/fixtures/sim/*.yaml` (10 files)
- Create: `tests/scenario/simulation.bats`

- [ ] **Step 1: Define YAML scenario format**

Each scenario file:
```yaml
name: "happy-path-simple-feature"
requirement: "Add a health check endpoint"
mode: standard
mock_events:
  - { event: preflight_complete, guards: { dry_run: "false" } }
  - { event: explore_complete, guards: { scope: "1", decomposition_threshold: "3" } }
  # ... full event sequence
expected_trace:
  - "PREFLIGHT → EXPLORING"
  - "EXPLORING → PLANNING"
  # ... expected state transitions
expected_counters:
  total_retries: 0
```

- [ ] **Step 2: Create all 10 scenario YAML files**

Create each file in `tests/fixtures/sim/` per the spec list (happy-path, convergence-improving, convergence-plateau, convergence-regressing, convergence-diminishing, pr-rejection-impl, pr-rejection-design, budget-exhaustion, safety-gate-failure, dry-run).

- [ ] **Step 3: Write forge-sim.sh**

Script accepts `run <scenario.yaml> [--forge-dir <temp>]`. For each mock_event: calls `forge-state.sh transition` with the event and guards. Captures the trace. Compares against `expected_trace`. Verifies `expected_counters`. Exits 0 on match, 1 on mismatch with diff output.

- [ ] **Step 4: Write simulation.bats**

One test per scenario file:
```bash
@test "simulation: happy-path scenario matches expected trace" {
  run bash "$PLUGIN_ROOT/shared/forge-sim.sh" run "$PLUGIN_ROOT/tests/fixtures/sim/happy-path.yaml" --forge-dir "$TEST_TEMP/.forge"
  assert_success
}
```

- [ ] **Step 5: Run tests**

Run: `./tests/lib/bats-core/bin/bats tests/scenario/simulation.bats`

- [ ] **Step 6: Commit**

```bash
git add shared/forge-sim.sh tests/fixtures/sim/ tests/scenario/simulation.bats
git commit -m "feat: add simulation harness with 10 pipeline scenarios"
```

---

## Task 2: Cross-Repo Improvements

**Files:**
- Create: `shared/cross-repo-contracts.md`
- Modify: `agents/fg-103-cross-repo-coordinator.md`
- Modify: `shared/sprint-state-schema.md`

- [ ] **Step 1: Create cross-repo-contracts.md**

Write the contract-first protocol spec per P2-2: contract stub generation at PLAN, CONTRACT_AGREEMENT sub-step within VALIDATING, contract checkpoint at VERIFY. Include state machine integration note (sub-step within VALIDATING, not new top-level state).

- [ ] **Step 2: Add bi-directional dependency support to sprint-state-schema.md**

Add `dependencies` object with `type: contract`, `contract_file`, `producer`, `consumer`, `checkpoint` fields.

- [ ] **Step 3: Add integration verification phase to fg-103**

Add "Integration Verification (pre-SHIP gate)" section: check for `commands.integration_test`, run if available, report findings.

- [ ] **Step 4: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 5: Commit**

```bash
git add shared/cross-repo-contracts.md agents/fg-103-cross-repo-coordinator.md shared/sprint-state-schema.md
git commit -m "feat: add contract-first protocol and integration smoke tests for cross-repo"
```

---

## Task 3: Reviewer Consolidation

**Files:**
- Modify: `agents/fg-413-frontend-reviewer.md`
- Delete: `agents/fg-414-frontend-quality-reviewer.md`
- Modify: `agents/fg-400-quality-gate.md` (batch config references)

- [ ] **Step 1: Read fg-414-frontend-quality-reviewer.md to extract content**

Read the full content. Identify: a11y review sections, performance review sections, tool declarations.

- [ ] **Step 2: Merge fg-414 content into fg-413-frontend-reviewer.md**

Add a `## Review Modes` section with `full | conventions-only | performance-only | a11y-only`. Add the a11y and performance review criteria from fg-414. Update the description in frontmatter.

- [ ] **Step 3: Update fg-400-quality-gate.md batch references**

Replace any `fg-414-frontend-quality-reviewer` references with `fg-413-frontend-reviewer` with mode parameter.

- [ ] **Step 4: Delete fg-414**

```bash
git rm agents/fg-414-frontend-quality-reviewer.md
```

- [ ] **Step 5: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 6: Commit**

```bash
git add agents/fg-413-frontend-reviewer.md agents/fg-400-quality-gate.md
git commit -m "refactor: merge fg-414 into fg-413-frontend-reviewer with review modes"
```

---

## Task 4: Retrospective Guardrails

**Files:**
- Modify: `agents/fg-700-retrospective.md`

- [ ] **Step 1: Add Auto-Tuning Guardrails section**

Add the tuning bounds table (max_iterations: 3-20, ±2 per run; plateau_patience: 1-5, ±1; etc.) and the rollback-on-regression logic per spec P2-4.

- [ ] **Step 2: Add fix cost per point tracking**

Add the A4d retrospective calculation: `tokens consumed in last convergence iteration ÷ score points gained`. If ratio > 50,000 tokens/point, propose increasing `shipping.min_score` by 5 (subject to guardrails).

- [ ] **Step 3: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 4: Commit**

```bash
git add agents/fg-700-retrospective.md
git commit -m "feat: add retrospective auto-tuning guardrails and fix-cost-per-point tracking"
```

---

## Task 5: Agent Prompt Compression

**Files:**
- Modify: Multiple agents (up to 36 files)

- [ ] **Step 1: Audit all agents for inline copies of shared rules**

Grep for known shared text patterns (Forbidden Actions bullet points, output format definitions, convention drift check instructions, MCP degradation instructions) across all `agents/*.md` files. List agents with >3 lines of duplicated content.

- [ ] **Step 2: Replace inline copies with references**

For each agent with duplicated content, replace the inline block with a one-line reference:
```markdown
**Constraints:** Follow `shared/agent-defaults.md` §Standard Reviewer Constraints.
```

- [ ] **Step 3: Verify no agent has >50% overlap with agent-defaults.md**

Run a verification grep to ensure all inline copies are removed.

- [ ] **Step 4: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 5: Commit**

```bash
git add agents/
git commit -m "refactor: replace inline shared rules with references to agent-defaults.md"
```

---

## Task 6: Compaction Hook + Miscellaneous Fixes

**Files:**
- Create: `shared/forge-compact-check.sh`
- Create: `shared/forge-timeout.sh`
- Modify: `hooks/hooks.json` (add compaction hook)
- Modify: `agents/fg-100-orchestrator-execute.md` (clean git checkpoints)

- [ ] **Step 1: Create forge-compact-check.sh**

Script increments `.forge/.token-estimate` counter, writes compaction suggestion to `.forge/.compact-suggestion` every 5 dispatches.

- [ ] **Step 2: Create forge-timeout.sh**

Script reads `stage_timestamps.preflight` from state.json, computes elapsed seconds, exits 1 if over limit (default 7200s), exits 0 with warning at 80%.

- [ ] **Step 3: Add compaction hook to hooks.json**

Add PostToolUse hook on `Agent` matcher calling `forge-compact-check.sh` with 3s timeout.

- [ ] **Step 4: Fix clean git checkpoints in orchestrator execute §4.1**

Replace `git commit --allow-empty` with conditional commit (only if staged changes exist).

- [ ] **Step 5: Make scripts executable**

```bash
chmod +x shared/forge-compact-check.sh shared/forge-timeout.sh
```

- [ ] **Step 6: Run all tests**

Run: `./tests/run-all.sh`

- [ ] **Step 7: Commit**

```bash
git add shared/forge-compact-check.sh shared/forge-timeout.sh hooks/hooks.json agents/fg-100-orchestrator-execute.md
git commit -m "feat: add compaction hook, timeout enforcement, fix empty git checkpoints"
```

---

## Task 7: Structural Validation + CLAUDE.md Update

**Files:**
- Modify: `tests/validate-plugin.sh`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add structural checks for all P1+P2 deliverables**

Add checks to `validate-plugin.sh`:
- `forge-token-tracker.sh` exists and is executable
- `forge-linear-sync.sh` exists and is executable
- `forge-sim.sh` exists and is executable
- `forge-timeout.sh` exists and is executable
- `forge-compact-check.sh` exists and is executable
- `fg-505-build-verifier.md` exists with correct frontmatter
- All 7 mode overlay files exist in `shared/modes/`
- `fg-414-frontend-quality-reviewer.md` does NOT exist
- `shared/cross-repo-contracts.md` exists
- `tests/fixtures/sim/` contains at least 10 YAML files

- [ ] **Step 2: Update CLAUDE.md**

- Agent count: keep at 36 (net zero: +1 fg-505, -1 fg-414)
- Update reviewer list: remove fg-414, note fg-413 now handles a11y + performance
- Add "Scripts" section listing all forge-* scripts with one-line descriptions
- Update orchestrator description: note 4-file split structure
- Add mode overlays: describe `shared/modes/` directory
- State schema: note v1.5.0 with token tracking, decision quality, _seq
- Scoring: note default `shipping.min_score: 90`
- Update description tiering: "Tier 2 (reviewers, 8)"

- [ ] **Step 3: Run full test suite**

Run: `./tests/run-all.sh`

- [ ] **Step 4: Commit**

```bash
git add tests/validate-plugin.sh CLAUDE.md
git commit -m "docs: update CLAUDE.md and structural validation for P1+P2 deliverables"
```

---

## Execution Order Summary

| Task | Depends On | Deliverable |
|------|-----------|------------|
| 1 | P1 complete | Simulation harness + 10 scenarios |
| 2 | P0 cross-repo docs | Cross-repo contract-first + integration tests |
| 3 | P1 Task 3 (fg-505 exists) | Reviewer merge (fg-413 absorbs fg-414) |
| 4 | P1 Task 1 (token tracker) | Retrospective guardrails + fix cost tracking |
| 5 | P0 Task 5-8 (orchestrator split) | Agent prompt compression |
| 6 | P1 Task 6 (hooks fixed) | Compaction hook + timeout + git fix |
| 7 | All above | Structural validation + CLAUDE.md |

Tasks 1-6 are mostly independent (can parallelize).
Task 7 must be last (validates everything).
