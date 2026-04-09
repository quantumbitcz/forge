# Forge Hardening: Complete Specification

> Addresses all 41 items identified in the Architecture Review and Orchestrator Review.
> Organized into 3 implementation waves: P0 (Reliability), P1 (Observability), P2 (Advanced).
> 2 items (P2-6 State Splitting, P2-7 Session Boundaries) are DEFERRED with explicit trigger conditions.
>
> Current codebase baseline: 36 agents, state schema v1.4.0, 8 review agents.

---

## Table of Contents

1. [Wave P0 — Reliability Foundation](#wave-p0--reliability-foundation)
   - [P0-1: Executable State Machine](#p0-1-executable-state-machine-forge-statesh)
   - [P0-2: Atomic State Writes + WAL + Versioning](#p0-2-atomic-state-writes--wal--versioning)
   - [P0-3: Orchestrator Phase Split](#p0-3-orchestrator-phase-split)
   - [P0-4: Scoring & Convergence Changes](#p0-4-scoring--convergence-changes)
   - [P0-5: State Machine Tests](#p0-5-state-machine-tests)
2. [Wave P1 — Observability & Efficiency](#wave-p1--observability--efficiency)
   - [P1-1: Token Budget Tracking](#p1-1-token-budget-tracking)
   - [P1-2: LLM Decision Quality Observability](#p1-2-llm-decision-quality-observability)
   - [P1-3: Extract Phase A Agent](#p1-3-extract-phase-a-agent)
   - [P1-4: Linear Event Consolidation](#p1-4-linear-event-consolidation)
   - [P1-5: Mode Config Overlays](#p1-5-mode-config-overlays)
   - [P1-6: Hook Architecture Fixes](#p1-6-hook-architecture-fixes)
   - [P1-7: INFO "Fix if Easy" Policy](#p1-7-info-fix-if-easy-policy)
3. [Wave P2 — Advanced Capabilities](#wave-p2--advanced-capabilities)
   - [P2-1: Simulation Harness](#p2-1-simulation-harness)
   - [P2-2: Cross-Repo Improvements](#p2-2-cross-repo-improvements)
   - [P2-3: Reviewer Consolidation](#p2-3-reviewer-consolidation)
   - [P2-4: Retrospective Guardrails](#p2-4-retrospective-guardrails)
   - [P2-5: Agent Prompt Compression](#p2-5-agent-prompt-compression)
   - [P2-6: State Splitting](#p2-6-state-splitting)
   - [P2-7: Session Boundaries](#p2-7-session-boundaries)
   - [P2-8: Compaction Hook](#p2-8-compaction-hook)
   - [P2-9: Miscellaneous Fixes](#p2-9-miscellaneous-fixes)
   - [P2-10: Tests, Validation, Docs](#p2-10-tests-validation-docs)
4. [Cross-Cutting Concerns](#cross-cutting-concerns)
5. [Migration & Backwards Compatibility](#migration--backwards-compatibility)

---

## Wave P0 — Reliability Foundation

### P0-1: Executable State Machine (`forge-state.sh`)

**Items:** A1, O2, B7-B12

**Problem:** The 49-row state transition table exists only as a markdown document. The orchestrator (an LLM) must interpret and follow it correctly every time. A single misinterpreted guard condition, skipped counter increment, or wrong transition silently corrupts the pipeline.

**Solution:** Create `shared/forge-state.sh` — an executable that is the single source of truth for state transitions and counter management. The orchestrator calls this script instead of manually editing state.json fields.

#### Interface

```bash
# Transition to a new state
forge-state.sh transition <event> [--guard key=value ...] [--forge-dir <path>]
# Output on success: JSON with { "previous_state": "...", "new_state": "...", "action": "...", "counters_changed": {...} }
# Output on failure: JSON with { "error": "...", "current_state": "...", "event": "...", "valid_transitions": [...] }
# Exit 0 on success, exit 1 on invalid transition, exit 2 on state file error

# Query current state without modifying
forge-state.sh query [--forge-dir <path>]
# Output: JSON with current state, all counters, convergence phase

# Initialize state for a new run
forge-state.sh init <story-id> <requirement> [--mode standard|bugfix|migration|bootstrap|testing|refactor|performance] [--dry-run] [--forge-dir <path>]
# Creates state.json with all defaults per state-schema.md v1.5.0

# Reset specific counters (for PR rejection re-entry)
forge-state.sh reset <counter-group> [--forge-dir <path>]
# counter-group: "implementation" (quality_cycles + test_cycles = 0)
#                "design" (quality_cycles + test_cycles + verify_fix_count + validation_retries = 0)
```

#### Transition Logic

The script encodes the complete Normal Flow transition table (48 data rows, numbered 1-49 with row 20 absent) + 7 error transitions + dry-run flow + convergence phase transitions from `shared/state-transitions.md`. Implementation as a lookup function:

```python
# Pseudocode for the core logic (implemented in Python embedded in bash)
def transition(current_state, event, guards):
    # 1. Check error transitions first (they fire from ANY state)
    for row in ERROR_TRANSITIONS:
        if row.event == event and evaluate_guard(row.guard, guards):
            return row.next_state, row.action

    # 2. Check normal flow transitions
    for row in NORMAL_TRANSITIONS:
        if row.current_state == current_state and row.event == event:
            if evaluate_guard(row.guard, guards):
                return row.next_state, row.action

    # 3. No matching transition = error
    raise InvalidTransition(current_state, event, guards)
```

#### Counter Management

Every transition that increments counters does so atomically within the script:

| Event | Counters Incremented |
|-------|---------------------|
| `phase_a_failure` (verify_fix_count < max) | `verify_fix_count`, `total_iterations`, `total_retries` |
| `tests_fail` (phase_iterations < max) | `phase_iterations`, `total_iterations`, `total_retries` |
| `score_improving` (total_iterations < max) | `plateau_count=0`, `phase_iterations`, `total_iterations`, `quality_cycles`, `total_retries` |
| `score_plateau` (plateau_count < patience) | `plateau_count`, `phase_iterations`, `total_iterations`, `total_retries` |
| `pr_rejected` (implementation) | `quality_cycles=0`, `test_cycles=0`, `total_retries` |
| `pr_rejected` (design) | `quality_cycles=0`, `test_cycles=0`, `verify_fix_count=0`, `validation_retries=0`, `total_retries` |
| `verdict_REVISE` | `validation_retries`, `total_retries` |
| `safety_gate_fail` (failures < 2) | `safety_gate_failures`, `total_iterations` |

The orchestrator NEVER directly modifies counter fields. It calls `forge-state.sh transition <event>` and the script handles all side effects.

#### Convergence Phase Transitions

The script also manages convergence sub-state transitions:

| Trigger | Phase Change | Resets |
|---------|-------------|--------|
| `verify_pass` + phase=correctness | correctness → perfection | `phase_iterations=0` |
| `score_target_reached` | perfection → safety_gate | (none) |
| `verify_pass` + phase=safety_gate | safety_gate → (exit to DOCUMENTING) | `safety_gate_passed=true` |
| `safety_gate_fail` (failures < 2) | safety_gate → correctness | `phase_iterations=0`, `plateau_count=0`, `last_score_delta=0`, `convergence_state=IMPROVING` |
| Plateau + score >= pass_threshold | perfection → safety_gate | (document unfixable) |

#### Guard Evaluation

Guards are passed as `--guard key=value` flags. The script reads current state.json for counter values and evaluates composite guards:

```bash
# Example: orchestrator calls after VERIFY passes
forge-state.sh transition verify_pass \
  --guard "convergence.phase=correctness"

# Example: orchestrator calls after REVIEW scoring
forge-state.sh transition score_improving \
  --guard "total_iterations=3" \
  --guard "max_iterations=8"
```

The script validates that all required guards for a transition are provided. Missing guards = error (not silent default).

#### Decision Logging

Every transition automatically appends to `.forge/decisions.jsonl`:

```json
{"ts":"2026-04-09T10:05:00Z","agent":"forge-state","decision":"state_transition","input":{"state":"VERIFYING","event":"verify_pass","guards":{"convergence.phase":"correctness"}},"choice":"REVIEWING","reason":"Row 26: verify_pass + phase=correctness → REVIEWING"}
```

#### File Location & Dependencies

- **Path:** `shared/forge-state.sh`
- **Dependencies:** Python 3 (for JSON manipulation), bash 4.0+
- **Executable:** `chmod +x`, shebang `#!/usr/bin/env bash`
- **Uses:** `forge-state-write.sh` (P0-2) for atomic writes
- **Source of truth:** Encodes `shared/state-transitions.md` tables
- **Implementation pattern:** Bash script with embedded Python via `python3 -c '...'` for JSON read/write/manipulation. The bash layer handles argument parsing, file I/O, and flock; the Python layer handles JSON parsing, guard evaluation, and transition table lookup. This matches the existing pattern used by `state-integrity.sh`.
- **Prerequisite check:** `shared/check-prerequisites.sh` (defined in P1-6 A8b) is promoted to P0 as a prerequisite for all P0 scripts. It validates both bash 4.0+ and python3 availability. This script is created as part of P0 implementation, not deferred to P1.

---

### P0-2: Atomic State Writes + WAL + Versioning

**Items:** A5a, A5b, A5c, B12

**Problem:** `state.json` is a single point of failure. An interrupted write, concurrent access, or filesystem issue corrupts the entire pipeline run.

**Solution:** Create `shared/forge-state-write.sh` that provides three layers of protection.

#### Interface

```bash
# Atomic write with WAL and versioning
forge-state-write.sh write <json-content> [--forge-dir <path>]
# 1. Increment _seq counter in the JSON
# 2. Write to .forge/state.wal (append: timestamp + full JSON)
# 3. Write to .forge/state.json.tmp
# 4. mv .forge/state.json.tmp .forge/state.json (atomic on POSIX)
# Exit 0 on success, exit 1 on failure (WAL preserved for recovery)

# Read with staleness check
forge-state-write.sh read [--forge-dir <path>]
# If state.json exists and is valid: output contents, exit 0
# If state.json missing but WAL exists: recover from WAL, output, exit 0
# If neither exists: exit 1

# Recover from WAL (used by state-integrity.sh)
forge-state-write.sh recover [--forge-dir <path>]
# Reads last valid entry from .forge/state.wal, writes to state.json
```

#### State Versioning

Add `_seq` field to state.json (monotonic counter, starts at 1):

```json
{
  "version": "1.5.0",
  "_seq": 42,
  ...
}
```

Every write increments `_seq`. If a write attempt has `_seq` <= the current file's `_seq`, reject it as stale (exit code 3). This prevents race conditions where two processes read-modify-write the same state.

#### WAL Format

`.forge/state.wal` is an append-only file. Each entry:

```
--- SEQ:42 TS:2026-04-09T10:05:00Z ---
{full state.json content}
```

WAL is truncated at 50 entries (keep last 50). Rotation happens at the start of each `write` call if the file exceeds 50 entries.

#### Integration with forge-state.sh

`forge-state.sh` uses `forge-state-write.sh` internally. The orchestrator never writes state.json directly. Call chain:

```
Orchestrator → forge-state.sh transition → (compute new state) → forge-state-write.sh write → atomic write
```

---

### P0-3: Orchestrator Phase Split

**Items:** O1a, O1b, O1c, O4, B1-B6, B16

**Problem:** The orchestrator is 1,786 lines / ~27K tokens loaded as a single system prompt. LLMs have declining attention to instructions in the middle of long contexts ("lost in the middle"). Forbidden actions at line 1707 get less attention than identity at line 22.

**Solution:** Split into 4 files. Each phase loads only the relevant document, cutting per-phase token cost ~60%.

#### File Structure

```
agents/
├── fg-100-orchestrator-core.md     # Identity, principles, forbidden actions, dispatch protocol (~300 lines)
├── fg-100-orchestrator-boot.md     # PREFLIGHT: config, conventions, state init (~500 lines)
├── fg-100-orchestrator-execute.md  # EXPLORE → REVIEW: stages 1-6 + convergence (~600 lines)
├── fg-100-orchestrator-ship.md     # DOCS → LEARN: stages 7-9, evidence, PR, learn (~400 lines)
```

#### Core File (fg-100-orchestrator-core.md)

Always loaded. Contains:

1. **Frontmatter** (name, description, tools, ui)
2. **§1 Identity & Purpose** — 3 touchpoints, coordinator-only, zero source files
3. **§2 Forbidden Actions** (MOVED FROM §21 — front-loaded for maximum attention)
   - Universal forbidden actions
   - Orchestrator-specific forbidden actions
   - Implementation agent forbidden actions
4. **§3 Pipeline Principles** (MOVED FROM §18)
5. **§4 Dispatch Protocol** — TaskCreate → Agent → TaskUpdate wrapper
6. **§5 Argument Parsing** — flags, --from, --spec, --dry-run, --run-dir, --wait-for
7. **§6 State Management** — forge-state.sh usage (replaces manual counter management)
8. **§7 Context Management** — compaction rules, output budget caps
9. **§8 Phase Loading** — how to load boot/execute/ship docs at boundaries
10. **§9 Decision Framework** — 70/30 choose silently, 60/40 choose simpler, 50/50 ask
11. **§10 Mode Resolution** — how to load mode overlay files (references `shared/modes/`)

#### Boot File (fg-100-orchestrator-boot.md)

Loaded once at pipeline start. Contains PREFLIGHT (Stage 0):

Sections numbered by stage:
- **§0.1** Read Project Config
- **§0.2** Read Mutable Runtime Params
- **§0.3** Config Validation
- **§0.4** Convention Fingerprinting
- **§0.5** PREEMPT System + Version Detection
- **§0.6** Deprecation Refresh (dispatch fg-140)
- **§0.7** Multi-Component Convention Resolution
- **§0.8** Check Engine Rule Cache
- **§0.9** Documentation Discovery (dispatch fg-130)
- **§0.10** Coverage Baseline (dispatch fg-150)
- **§0.11** State Integrity Check
- **§0.12** Interrupted Run Recovery
- **§0.13** Pipeline Lock
- **§0.14** Initialize State (via `forge-state.sh init`)
- **§0.15** Create Worktree (dispatch fg-101)
- **§0.16** Bugfix Source Resolution
- **§0.17** Visual Task Tracker
- **§0.18** Kanban Status Transitions
- **§0.19** Graph Context (optional)

After PREFLIGHT completes, the orchestrator transitions to the execute phase. The core doc §8 describes how to load `fg-100-orchestrator-execute.md`.

#### Execute File (fg-100-orchestrator-execute.md)

Loaded after PREFLIGHT. Contains stages 1-6:

- **§1.1** EXPLORE — standard/bugfix dispatch
- **§1.2** Post-EXPLORE Scope Check (auto-decomposition)
- **§2.1** PLAN — mode-based planner dispatch (references mode overlay)
- **§2.2** Cross-Repo Task Detection
- **§2.3** Multi-Service Task Decomposition
- **§3.1** VALIDATE — dispatch fg-210
- **§3.2** Bugfix Validation (4 perspectives)
- **§3.3** Contract Validation (conditional fg-250)
- **§3.4** Decision Gate
- **§4.1** IMPLEMENT — Git Checkpoint + Worktree Verify
- **§4.2** Documentation Prefetch
- **§4.3** Execute Tasks (scaffold → conflict detect → implement)
- **§4.4** Checkpoints + Failure Isolation
- **§4.5** Frontend Creative Polish (conditional)
- **§4.6** Post-IMPLEMENT Graph Update
- **§5.1** VERIFY Phase A — dispatch `fg-505-build-verifier` if available (P1-3), else inline build+lint with fix loop (preserves current behavior until P1-3 is implemented). **Acceptance criterion: §5.1 MUST NOT fail when `agents/fg-505-build-verifier.md` does not exist. It must use the current inline approach as fallback.**
- **§5.2** VERIFY Phase B — dispatch fg-500-test-gate
- **§5.3** Convergence Engine Integration (EXTRACTED — references `shared/convergence-engine.md` and `forge-state.sh` for transitions, does NOT restate the algorithm)
- **§6.1** REVIEW — Batch Dispatch
- **§6.2** Score and Verdict (via `forge-state.sh`)
- **§6.3** Convergence-Driven Fix Cycle (HIGH-LEVEL: "call forge-state.sh transition with score event, follow returned action")
- **§6.4** Code Review Feedback Rigor
- **§6.5** Score Escalation Ladder

Key change in §5.3 and §6.3: instead of restating the convergence algorithm (which was ~150 lines), the execute doc says:

```
Call `forge-state.sh transition <score_event>` with the current score.
The script returns the next state and action. Follow the returned action:
- If action contains "dispatch implementer": dispatch fg-300 with findings
- If action contains "transition to safety_gate": dispatch VERIFY
- If action contains "escalate": escalate to user per escalation format
```

This replaces ~150 lines of convergence prose with ~20 lines of dispatch-by-action.

#### Ship File (fg-100-orchestrator-ship.md)

Loaded after REVIEW passes. Contains stages 7-9:

- **§7.1** DOCS — dispatch fg-350
- **§7.2** Pre-Ship Verification — dispatch fg-590
- **§7.3** Evidence Verdict Routing
- **§8.1** SHIP — dispatch fg-600
- **§8.2** Merge Conflict Handling
- **§8.3** Preview Validation (conditional)
- **§8.4** Infrastructure Deployment Verification (conditional)
- **§8.5** User Response + Feedback Loop Detection
- **§9.1** LEARN — dispatch fg-700
- **§9.2** Worktree Cleanup
- **§9.3** Post-Run (dispatch fg-710)
- **§9.4** Final Report

#### Phase Loading Mechanism

In the core doc §8:

```markdown
## §8 Phase Loading

After completing PREFLIGHT, load the next phase document:

1. After PREFLIGHT → Read `agents/fg-100-orchestrator-execute.md` via the Read tool.
   Follow its instructions for stages 1-6.
2. After REVIEW passes (score accepted) → Read `agents/fg-100-orchestrator-ship.md` via the Read tool.
   Follow its instructions for stages 7-9.
3. On re-entry (PR rejection → IMPLEMENT, evidence BLOCK → IMPLEMENT):
   Re-read `agents/fg-100-orchestrator-execute.md`.

Always keep this core document's principles active. Phase documents add stage-specific behavior;
they do not override core principles or forbidden actions.
```

#### Complete Section-to-File Mapping

Every current orchestrator section must map to exactly one new file. Here is the exhaustive mapping:

| Current Section | New File | New Section |
|----------------|----------|-------------|
| §1 Identity & Purpose | core | §1 |
| §2 Argument Parsing | core | §5 |
| Graph Context | boot | §0.19 |
| §3 PREFLIGHT (§3.0-§3.12) | boot | §0.1-§0.18 |
| §4 EXPLORE | execute | §1.1-§1.2 |
| §5 PLAN | execute | §2.1-§2.3 |
| §6 VALIDATE | execute | §3.1-§3.4 |
| §7 IMPLEMENT | execute | §4.1-§4.6 |
| §8 VERIFY | execute | §5.1-§5.3 |
| §9 REVIEW | execute | §6.1-§6.5 |
| §10 DOCS | ship | §7.1 |
| §10.5 Pre-Ship | ship | §7.2-§7.3 |
| §11 SHIP | ship | §8.1-§8.5 |
| §12 LEARN | ship | §9.1-§9.4 |
| §13 Context Management | core | §7 |
| §14 Agent Dispatch Rules | core | §4 (merged into dispatch protocol) |
| §15 State Tracking | core | §6 (replaced by forge-state.sh usage) |
| §16 Timeout Enforcement | core | §7 (merged into context management) |
| §17 Final Report | ship | §9.4 |
| §18 Pipeline Principles | core | §3 (MOVED TO FRONT) |
| §19 Large Codebase | core | §7 (merged into context management) |
| §20 Worktree & Cross-Repo | core | §5 (reference to fg-101/fg-103 docs) |
| §21 Forbidden Actions | core | §2 (MOVED TO FRONT) |
| §22 Autonomy & Decision | core | §9 |
| §23 MCP Detection | boot | §0.18 (part of PREFLIGHT) |
| §24 Escalation Format | core | §9 (merged into decision framework) |
| §25 Pipeline Observability | core | §7 (merged into context management) |
| §26 Task Blueprint | core | §4 (merged into dispatch protocol) |
| §27 Reference Documents | core | §11 (final section) |

#### Linear Operations

All 6 scattered Linear blocks are removed from the phase files. Replaced with a single call pattern at stage boundaries:

```
forge-linear-sync.sh emit <event-type> <event-data-json> [--forge-dir <path>]
```

See P1-4 for the full Linear sync spec.

#### Mode-Specific Logic

All `if mode == "bugfix"` / `if mode == "migration"` branches are removed. Replaced with mode overlay loading:

```
At PREFLIGHT, after detecting mode:
Read `shared/modes/${mode}.md` for mode-specific dispatch overrides.
```

See P1-5 for the full mode overlay spec.

---

### P0-4: Scoring & Convergence Changes

**Items:** A4a, A4b, A16, A19

**Problem:** `shipping.min_score: 100` means the pipeline iterates to fix every INFO finding. Diminishing returns waste tokens.

#### Change 1: Default `shipping.min_score` to 90

In `shared/scoring.md`, update the Scoring Customization section:

```markdown
shipping:
  min_score: 90             # Default 90 (was 100). Minimum score to create PR.
```

Update the constraint: `min_score` must be >= `pass_threshold` and <= 100.

Update `shared/convergence-engine.md` Configuration section:

```markdown
convergence:
  target_score: 90          # Default 90 (was 100). Convergence target.
```

#### Change 2: Diminishing Returns Detector

Add to `shared/convergence-engine.md` after the plateau detection algorithm:

```markdown
### Diminishing Returns Detection

After each convergence iteration in Phase 2 (perfection), check:

1. Compute `gain = score_current - score_previous`
2. If `gain > 0 AND gain <= 2 AND score_current >= pass_threshold`:
   - This is a diminishing returns cycle — progress is real but minimal
   - Increment `diminishing_count` (new field in convergence state)
   - If `diminishing_count >= 2`: treat as PLATEAUED (apply score escalation ladder)
   - Log: "Diminishing returns: gained {gain} points in last {diminishing_count} iterations"
3. If `gain > 2`: reset `diminishing_count = 0`

This prevents the pipeline from spending 3-4 iterations to squeeze out the last 2-3 INFO fixes
when the score is already above pass_threshold.
```

Add `diminishing_count` to state schema convergence section (default 0).

Add transition row to `shared/state-transitions.md`:

```
| 50 | REVIEWING | score_diminishing | diminishing_count >= 2 AND score >= pass_threshold | VERIFYING | Treat as plateau, transition to safety_gate |
```

Update `forge-state.sh` to handle the new `score_diminishing` event.

---

### P0-5: State Machine Tests

**Item:** T1

**Problem:** Zero tests validate that state transitions happen correctly. The state machine table is untested.

#### Test File: `tests/unit/forge-state.bats`

Tests for `forge-state.sh` in isolation:

```bash
# Normal flow transitions (one test per row)
@test "forge-state: PREFLIGHT + preflight_complete (dry_run=false) → EXPLORING"
@test "forge-state: PREFLIGHT + preflight_complete (dry_run=true) → EXPLORING"
@test "forge-state: EXPLORING + explore_complete (scope < threshold) → PLANNING"
@test "forge-state: EXPLORING + explore_complete (scope >= threshold) → DECOMPOSED"
@test "forge-state: PLANNING + plan_complete → VALIDATING"
@test "forge-state: VALIDATING + verdict_GO (risk <= auto_proceed) → IMPLEMENTING"
@test "forge-state: VALIDATING + verdict_REVISE (retries < max) → PLANNING"
@test "forge-state: VALIDATING + verdict_REVISE (retries >= max) → ESCALATED"
@test "forge-state: VALIDATING + verdict_NOGO → ESCALATED"
@test "forge-state: IMPLEMENTING + implement_complete (at_least_one_passed) → VERIFYING"
@test "forge-state: IMPLEMENTING + implement_complete (all_failed) → ESCALATED"
@test "forge-state: VERIFYING + phase_a_failure (within budget) → IMPLEMENTING"
@test "forge-state: VERIFYING + phase_a_failure (budget exhausted) → ESCALATED"
@test "forge-state: VERIFYING + tests_fail (within budget) → IMPLEMENTING"
@test "forge-state: VERIFYING + tests_fail (budget exhausted) → ESCALATED"
@test "forge-state: VERIFYING + verify_pass (phase=correctness) → REVIEWING"
@test "forge-state: VERIFYING + verify_pass (phase=safety_gate) → DOCUMENTING"
@test "forge-state: VERIFYING + safety_gate_fail (failures < 2) → IMPLEMENTING"
@test "forge-state: VERIFYING + safety_gate_fail (failures >= 2) → ESCALATED"
@test "forge-state: REVIEWING + score_target_reached → VERIFYING"
@test "forge-state: REVIEWING + score_improving (within budget) → IMPLEMENTING"
@test "forge-state: REVIEWING + score_improving (budget exhausted) → ESCALATED"
@test "forge-state: REVIEWING + score_plateau (patience reached + score >= pass) → VERIFYING"
@test "forge-state: REVIEWING + score_plateau (patience reached + concerns range) → ESCALATED"
@test "forge-state: REVIEWING + score_plateau (patience reached + below concerns) → ESCALATED"
@test "forge-state: REVIEWING + score_plateau (patience not reached) → IMPLEMENTING"
@test "forge-state: REVIEWING + score_regressing → ESCALATED"
@test "forge-state: REVIEWING + score_diminishing (count >= 2) → VERIFYING"
@test "forge-state: DOCUMENTING + docs_complete → SHIPPING"
@test "forge-state: SHIPPING + evidence_SHIP (fresh) → SHIPPING (PR)"
@test "forge-state: SHIPPING + evidence_BLOCK (build) → IMPLEMENTING"
@test "forge-state: SHIPPING + pr_created → SHIPPING (user gate)"
@test "forge-state: SHIPPING + user_approve_pr → LEARNING"
@test "forge-state: SHIPPING + pr_rejected (implementation) → IMPLEMENTING"
@test "forge-state: SHIPPING + pr_rejected (design) → PLANNING"
@test "forge-state: LEARNING + retrospective_complete → COMPLETE"

# Error transitions
@test "forge-state: ANY + budget_exhausted → ESCALATED"
@test "forge-state: ANY + recovery_budget_exhausted → ESCALATED"
@test "forge-state: ANY + circuit_breaker_open → ESCALATED"
@test "forge-state: ANY + unrecoverable_error → ESCALATED"

# Counter management
@test "forge-state: phase_a_failure increments verify_fix_count + total_iterations + total_retries"
@test "forge-state: tests_fail increments phase_iterations + total_iterations + total_retries"
@test "forge-state: score_improving resets plateau_count to 0"
@test "forge-state: pr_rejected (implementation) resets quality_cycles + test_cycles"
@test "forge-state: pr_rejected (design) resets quality + test + verify + validation"

# Invalid transitions
@test "forge-state: rejects PREFLIGHT + verify_pass (invalid event for state)"
@test "forge-state: rejects REVIEWING + preflight_complete (invalid event for state)"
@test "forge-state: rejects missing guard values"

# Convergence phase transitions
@test "forge-state: verify_pass transitions correctness → perfection"
@test "forge-state: score_target_reached transitions perfection → safety_gate"
@test "forge-state: safety_gate_fail transitions safety_gate → correctness with resets"

# Init and query
@test "forge-state: init creates valid state.json with all required fields"
@test "forge-state: query returns current state as JSON"
@test "forge-state: reset implementation clears quality_cycles + test_cycles"
@test "forge-state: reset design clears all inner-loop counters"
```

#### Test File: `tests/unit/forge-state-write.bats`

Tests for atomic writes:

```bash
@test "forge-state-write: write creates state.json atomically"
@test "forge-state-write: write increments _seq counter"
@test "forge-state-write: write appends to WAL"
@test "forge-state-write: rejects stale writes (lower _seq)"
@test "forge-state-write: recover restores from WAL when state.json missing"
@test "forge-state-write: WAL truncates at 50 entries"
@test "forge-state-write: read returns valid JSON"
@test "forge-state-write: concurrent writes don't corrupt (flock)"
```

#### Test File: `tests/scenario/state-transitions.bats`

End-to-end scenarios using forge-state.sh:

```bash
@test "scenario: happy path PREFLIGHT → COMPLETE transitions"
@test "scenario: convergence correctness → perfection → safety_gate → DOCUMENTING"
@test "scenario: plateau detection escalates after patience exceeded"
@test "scenario: oscillation detection escalates on score regression"
@test "scenario: diminishing returns stops after 2 low-gain iterations"
@test "scenario: PR rejection resets counters and re-enters correctly"
@test "scenario: total_retries budget prevents infinite loops"
@test "scenario: safety_gate failure returns to correctness phase"
@test "scenario: dry-run stops at VALIDATING"
```

---

## Wave P1 — Observability & Efficiency

### P1-1: Token Budget Tracking

**Items:** A3, A3b, A12-A14

**Problem:** No tracking of token consumption. Pipeline runs can consume 500K-1M+ tokens with no visibility or budget control.

#### State Schema Changes (v1.5.0)

Add `tokens` section to `state.json`:

```json
"tokens": {
  "estimated_total": 0,
  "budget_ceiling": 2000000,
  "by_stage": {
    "preflight": { "input": 0, "output": 0 },
    "explore": { "input": 0, "output": 0 },
    "plan": { "input": 0, "output": 0 },
    "validate": { "input": 0, "output": 0 },
    "implement": { "input": 0, "output": 0 },
    "verify": { "input": 0, "output": 0 },
    "review": { "input": 0, "output": 0 },
    "docs": { "input": 0, "output": 0 },
    "ship": { "input": 0, "output": 0 },
    "learn": { "input": 0, "output": 0 }
  },
  "by_agent": {},
  "budget_warning_issued": false
}
```

#### Token Tracker Script

Create `shared/forge-token-tracker.sh`:

```bash
# Record token usage for an agent dispatch
forge-token-tracker.sh record <stage> <agent-name> <input-tokens> <output-tokens> [--forge-dir <path>]

# Estimate tokens from a file (chars / 4 approximation)
forge-token-tracker.sh estimate <file-path>

# Check budget
forge-token-tracker.sh check [--forge-dir <path>]
# Exit 0 if within budget, exit 1 if >= 80% (warning), exit 2 if exceeded
```

Token estimation: `chars / 4` for English text (standard approximation). Agent prompt size = sum of agent `.md` file + convention stack files + dispatch prompt.

#### Budget Ceiling as Pipeline Constraint

Add to `forge-config.md` configurable parameters:

```yaml
tokens:
  budget_ceiling: 2000000    # Default 2M tokens. 0 = no limit.
  warning_threshold: 0.8     # Warn at 80% of ceiling
```

Add error transition to `shared/state-transitions.md`:

```
| E8 | ANY | token_budget_exhausted | tokens.estimated_total >= budget_ceiling | ESCALATED | Token budget exceeded, escalate to user |
```

#### Retrospective Integration

`fg-700-retrospective.md` reports token cost per stage and per convergence iteration. Proposes `budget_ceiling` adjustments based on actual usage trends.

---

### P1-2: LLM Decision Quality Observability

**Items:** A6a-A6d, A24-A27, O11

#### Agent Confidence Field (A6a)

Update `shared/checks/output-format.md` to add optional confidence:

```
file:line | CATEGORY-CODE | SEVERITY | message | fix_hint | confidence:HIGH
```

Confidence values: `HIGH` (>90% certain), `MEDIUM` (70-90%), `LOW` (<70%). Default `HIGH` if omitted (backwards compatible).

Agents are instructed: "If you are unsure about a finding's severity or whether it's a false positive, add `confidence:LOW` or `confidence:MEDIUM`. This data is used by the retrospective to track reviewer accuracy."

#### Reviewer Agreement Tracking (A6b)

Update `fg-400-quality-gate.md`:

When multiple reviewers report findings on the same `(file, line)`:
- Track agreement: both report same severity → `agreement`
- Track disagreement: different severity → `disagreement`
- Record in quality gate stage notes: `"Reviewer agreement: {N}/{M} findings ({pct}%)""`

Store in `state.json.decision_quality`:

```json
"decision_quality": {
  "reviewer_agreement_rate": 0.85,
  "findings_with_low_confidence": 3,
  "overridden_findings": 1,
  "total_decisions_logged": 42
}
```

#### Decision Log Population (A6c)

Currently `decisions.jsonl` is specified but may not be populated by all agents. Add explicit instructions to these agents:

- `fg-100-orchestrator` (via core doc): log state transitions (handled by `forge-state.sh`)
- `fg-200-planner`: log approach selection (alternatives considered → chosen)
- `fg-210-validator`: log verdict decision (findings → verdict)
- `fg-400-quality-gate`: log conflict resolutions (reviewer A vs B → winner)
- `fg-300-implementer`: log implementation choices (pattern selection, fix strategy)

Each agent gets a one-line instruction: "Append decisions to `.forge/decisions.jsonl` per `shared/decision-log.md`."

#### Decision Log Validation (O11)

Add to `shared/state-integrity.sh`:

```bash
# ── 10. Decision log format validation ─────────────────────────────────────
if [[ -f "${FORGE_DIR}/decisions.jsonl" ]]; then
  # Validate each line is valid JSON with required fields
  invalid_lines=$(python3 -c "..." "$FORGE_DIR/decisions.jsonl")
  if [[ -n "$invalid_lines" ]]; then
    warn "decisions.jsonl has $invalid_lines malformed lines"
  fi
fi
```

#### Decision Quality in Retrospective (A6d)

Update `fg-700-retrospective.md` to include a "Decision Quality" section in the run report:

```markdown
## Decision Quality
- Decisions logged: {total_decisions_logged}
- Reviewer agreement rate: {rate}%
- Findings with low confidence: {count} ({pct}% of total)
- Overridden findings (orchestrator pushed back): {count}
- Score trajectory: {scores joined by →}
- Fix cost per point: {tokens_per_point_gained} tokens/point (last iteration)
- Auto-threshold recommendation: if fix_cost_per_point > {threshold}, suggest raising shipping.min_score

(This section covers item A4d: fix cost per point tracking with auto-threshold adjustment.
The retrospective calculates: tokens consumed in last convergence iteration ÷ score points gained.
If the ratio exceeds a configurable threshold (default: 50,000 tokens/point), the retrospective
proposes increasing `shipping.min_score` by 5 for the next run, subject to P2-4 guardrails.)
```

---

### P1-3: Extract Phase A Agent

**Items:** O5, B17-B18

**Problem:** VERIFY Phase A (build + lint + fix loop) is inline in the orchestrator. The orchestrator analyzes compiler output and edits source files — violating its own "coordinator only" principle.

#### New Agent: `agents/fg-505-build-verifier.md`

```yaml
---
name: fg-505-build-verifier
description: Verifies build and lint pass. Analyzes errors, applies fixes, re-runs. Returns PASS or escalation context.
model: inherit
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
---
```

**Responsibilities:**
1. Run `commands.build` — if fails, analyze error, fix, re-run
2. Run `commands.lint` — if fails, analyze error, fix, re-run
3. Run `inline_checks` from config
4. Track fix attempts (up to `max_fix_loops`)
5. Return structured result: `{ "verdict": "PASS"|"FAIL", "fix_attempts": N, "errors": [...] }`

**NOT responsible for:**
- State transitions (orchestrator calls `forge-state.sh`)
- Escalation decisions (returns FAIL, orchestrator decides)
- Test execution (that's Phase B / fg-500)

#### Orchestrator Change

In `fg-100-orchestrator-execute.md` §5.1, replace the inline Phase A with:

```markdown
### §5.1 VERIFY Phase A — Build & Lint

Dispatch `fg-505-build-verifier`:
[dispatch fg-505-build-verifier]

Commands: build={commands.build}, lint={commands.lint}, inline_checks={quality_gate.inline_checks}
Max fix loops: {implementation.max_fix_loops}
Check engine skipped count: {from .forge/.check-engine-skipped}

If verdict == "PASS": proceed to Phase B.
If verdict == "FAIL": call `forge-state.sh transition phase_a_failure` and follow returned action.
```

---

### P1-4: Linear Event Consolidation

**Items:** O6, B19-B20

**Problem:** Linear integration appears in 6 places across the orchestrator. Each has its own guard and failure handling.

#### Event-Driven Architecture

Create `shared/forge-linear-sync.sh`:

```bash
# Emit a pipeline event for Linear sync
forge-linear-sync.sh emit <event-type> <event-json> [--forge-dir <path>]
# Appends event to .forge/linear-events.jsonl
# If Linear available: processes immediately, removes from queue
# If Linear unavailable: logs event to file for debugging, does NOT retry or queue
# NEVER blocks the pipeline. NEVER returns non-zero.
# The .forge/linear-events.jsonl file serves as a debug log only (not a retry queue).
# File is truncated at 100 entries to prevent unbounded growth.
# On successful Linear operation: event is still logged (for audit trail).
```

#### Event Types

| Event Type | Payload | Linear Action |
|-----------|---------|---------------|
| `plan_complete` | `{ epic_title, stories: [...], tasks: [...] }` | Create Epic, Stories, Tasks |
| `task_started` | `{ task_id }` | Move Task → In Progress |
| `task_completed` | `{ task_id }` | Move Task → Done |
| `task_blocked` | `{ task_id, reason }` | Move Task → Blocked |
| `verify_complete` | `{ epic_id, summary }` | Comment on Epic |
| `review_complete` | `{ epic_id, score, verdict }` | Comment on Epic |
| `pr_created` | `{ epic_id, pr_url, story_ids }` | Link PR, move Stories → In Review |
| `pr_merged` | `{ epic_id }` | Close Epic |

#### Orchestrator Change

All 6 Linear blocks replaced with one-line calls:

```markdown
forge-linear-sync.sh emit plan_complete '{"epic_title":"...","stories":[...]}'
```

Linear availability is checked once inside the sync script. The orchestrator never checks `integrations.linear.available` directly for Linear operations.

---

### P1-5: Mode Config Overlays

**Items:** O7, B21

**Problem:** 7 mode-specific branches (`if mode == "bugfix"`, `if mode == "migration"`, etc.) scattered across the orchestrator.

#### Mode Overlay Files

Create `shared/modes/` directory with one file per mode:

```
shared/modes/
├── standard.md
├── bugfix.md
├── migration.md
├── bootstrap.md
├── testing.md
├── refactor.md
└── performance.md
```

#### Overlay Schema

Each mode file has YAML frontmatter defining stage overrides:

```yaml
---
mode: bugfix
stages:
  explore:
    agent: fg-020-bug-investigator
    prompt_suffix: "Execute Phase 1 — INVESTIGATE"
  plan:
    agent: fg-020-bug-investigator
    prompt_suffix: "Execute Phase 2 — REPRODUCE"
  validate:
    perspectives: [root_cause_validity, fix_scope, regression_risk, test_coverage]
    max_retries: 1
  implement:
    skip: false
  review:
    batch_override:
      batch_1: [fg-410-code-reviewer, fg-411-security-reviewer]
    conditional:
      - agent: fg-413-frontend-reviewer
        condition: "frontend_files_in_diff"
        # Conditions are evaluated by the quality gate (fg-400) at dispatch time.
        # "frontend_files_in_diff" = any changed file matches *.tsx|*.jsx|*.vue|*.svelte|*.css
    target_score: pass_threshold
  ship:
    target_score: pass_threshold
---

## Bugfix Mode

Additional instructions for bugfix pipeline execution.
[Bugfix-specific prose that was previously in the orchestrator if/else branches]
```

#### Orchestrator Change

In the core doc §10:

```markdown
## §10 Mode Resolution

After detecting mode at PREFLIGHT:
1. Read `shared/modes/${mode}.md`
2. Parse YAML frontmatter for stage overrides
3. Store overrides in state.json under `mode_config`
4. At each stage, check `mode_config.stages.{stage_name}` for overrides:
   - `agent`: dispatch this agent instead of the default
   - `skip: true`: skip the stage entirely
   - `batch_override`: use these review batches instead of config
   - `target_score`: override the convergence target
   - `perspectives`: use these validation perspectives
```

This replaces ~200 lines of if/else branching in the orchestrator with ~20 lines of overlay resolution logic.

---

### P1-6: Hook Architecture Fixes

**Items:** A8a-A8d, A31-A34

#### File Locks (A8a)

In `shared/checks/engine.sh`, replace the `_ENGINE_RUNNING` environment variable guard with flock:

```bash
# OLD (race condition):
# [[ -n "${_ENGINE_RUNNING:-}" ]] && exit 0
# export _ENGINE_RUNNING=1

# NEW (atomic file lock):
LOCK_FILE="${FORGE_DIR:-.forge}/.engine.lock"
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0  # Another instance running, skip silently
```

#### Bash 4+ Install Check (A8b)

Add to the plugin installation process (checked when `hooks.json` is loaded):

Create `shared/check-prerequisites.sh`:

```bash
#!/usr/bin/env bash
errors=0

# Bash 4.0+ check
BASH_MAJOR="${BASH_VERSINFO[0]}"
if [[ "$BASH_MAJOR" -lt 4 ]]; then
  echo "ERROR: forge plugin requires bash 4.0+ (found ${BASH_VERSION})"
  echo "Install with: brew install bash"
  errors=$((errors + 1))
fi

# Python 3 check (required by forge-state.sh, state-integrity.sh)
if ! command -v python3 &>/dev/null; then
  echo "ERROR: forge plugin requires python3 (not found)"
  echo "Install with: brew install python3"
  errors=$((errors + 1))
fi

[[ $errors -eq 0 ]] && echo "OK: all prerequisites met"
exit $errors
```

This runs at plugin install time. If it fails, the plugin installation warns loudly (not silently skipping checks at runtime).

**Note:** `hooks.json` does not currently support `install_checks` as a top-level key — the Claude Code plugin system uses a fixed schema. Instead, this check is invoked by the `/forge-init` skill at first setup, and by `validate-plugin.sh` during CI. The `hooks.json` schema is NOT modified to add new top-level keys to avoid breaking plugin loading.
```

#### Hook Failure Logging (A8c)

Modify `shared/checks/engine.sh` error handling:

```bash
# On any error/timeout, append to failure log instead of silent exit
handle_failure() {
  local reason="$1"
  local file="$2"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | engine.sh | ${reason} | ${file}" \
    >> "${FORGE_DIR:-.forge}/.hook-failures.log"
}
```

In the orchestrator (fg-100-orchestrator-execute.md §5.1), add before Phase A:

```markdown
Read `.forge/.hook-failures.log` if it exists. If non-empty:
- Count failure entries since last VERIFY
- Log in stage notes: "{N} hook failures since last verification"
- Delete the file after reading (reset for next cycle)
```

#### Configurable Hook Timeouts (A8d)

Hook timeouts are configured through the existing `hooks.json` `timeout` field (already supported by Claude Code). The change is to increase the default timeout for `engine.sh` from 5 to 10 seconds:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{
          "type": "command",
          "command": "engine.sh --hook",
          "timeout": 10
        }]
      }
    ]
  }
}
```

Per-project timeout overrides are configured in `forge.local.md` and read by the hook scripts themselves (not via `hooks.json` schema extension, which has a fixed schema):

```yaml
hooks:
  timeouts:
    engine_sh: 15       # engine.sh reads this value if present
```

Each hook script reads its own timeout from `forge.local.md` YAML and uses it as an internal deadline, exiting before the hooks.json hard timeout.

---

### P1-7: INFO "Fix if Easy" Policy

**Items:** A17, A4c

**Problem:** The pipeline iterates to fix INFO findings that cost more tokens to fix than they're worth.

#### Policy Change

Add to `shared/scoring.md` after the Aim-for-100 Policy section:

```markdown
### INFO Efficiency Policy

During convergence Phase 2 (perfection), INFO findings follow "fix if easy, skip if costly":

1. On first iteration: attempt to fix ALL findings (including INFO)
2. On subsequent iterations: if an INFO finding was present in the previous cycle
   and the implementer did not fix it, mark it as `unfixable_info` in convergence state
3. Unfixable INFO findings are excluded from the convergence target calculation:
   `effective_target = min(target_score, 100 - 2 * unfixable_info_count)`
4. The pipeline converges when `score >= effective_target` (not raw `target_score`)

This prevents the pipeline from iterating to fix style nits that the implementer
cannot or should not fix (e.g., pre-existing code style in unchanged files).
```

Add `unfixable_info_count` to convergence state (default 0).

---

## Wave P2 — Advanced Capabilities

### P2-1: Simulation Harness

**Items:** A2, A6-A11

#### Script: `shared/forge-sim.sh`

```bash
# Run a simulated pipeline and validate the execution trace
forge-sim.sh run <scenario-file> [--forge-dir <temp-dir>]

# Validate a trace against the transition table
forge-sim.sh validate <trace-file>
```

#### Scenario File Format

```yaml
name: "happy-path-simple-feature"
requirement: "Add a health check endpoint"
mode: standard
mock_events:
  - { stage: explore, event: explore_complete, guards: { scope: 1 } }
  - { stage: plan, event: plan_complete }
  - { stage: validate, event: verdict_GO, guards: { risk: "LOW", auto_proceed_risk: "MEDIUM" } }
  - { stage: implement, event: implement_complete, guards: { at_least_one_task_passed: true } }
  - { stage: verify, event: verify_pass, guards: { "convergence.phase": "correctness" } }
  - { stage: review, event: score_target_reached, mock_score: 95 }
  - { stage: verify_safety, event: verify_pass, guards: { "convergence.phase": "safety_gate" } }
  - { stage: docs, event: docs_complete }
  - { stage: ship, event: evidence_SHIP, guards: { evidence_fresh: true } }
  - { stage: ship, event: pr_created }
  - { stage: ship, event: user_approve_pr }
  - { stage: learn, event: retrospective_complete }
expected_trace:
  - PREFLIGHT → EXPLORING
  - EXPLORING → PLANNING
  - PLANNING → VALIDATING
  - VALIDATING → IMPLEMENTING
  - IMPLEMENTING → VERIFYING
  - VERIFYING → REVIEWING
  - REVIEWING → VERIFYING (safety_gate)
  - VERIFYING → DOCUMENTING
  - DOCUMENTING → SHIPPING
  - SHIPPING → LEARNING
  - LEARNING → COMPLETE
expected_counters:
  total_retries: 0
  quality_cycles: 0
```

#### Scenario Library

Pre-built scenarios in `tests/fixtures/sim/`:
- `happy-path.yaml` — clean run, no retries
- `convergence-improving.yaml` — 3 review cycles, each improving
- `convergence-plateau.yaml` — plateau after 2 cycles above pass_threshold
- `convergence-regressing.yaml` — score drops, immediate escalation
- `convergence-diminishing.yaml` — gains of 1-2 points, stops early
- `pr-rejection-impl.yaml` — PR rejected, implementation feedback loop
- `pr-rejection-design.yaml` — PR rejected, design feedback loop
- `budget-exhaustion.yaml` — total_retries hits max
- `safety-gate-failure.yaml` — Phase 2 breaks tests, returns to Phase 1
- `dry-run.yaml` — stops at VALIDATING

---

### P2-2: Cross-Repo Improvements

**Items:** A7a-A7c, A28-A30

#### Contract-First Phase (A7a)

Add `shared/cross-repo-contracts.md`:

```markdown
# Cross-Repo Contract-First Protocol

Before either side of a cross-repo feature implements, establish the API contract:

1. **PLAN stage:** Planner identifies shared contracts (OpenAPI, proto, GraphQL, shared types)
2. **New sub-stage: CONTRACT_AGREEMENT** (between VALIDATE and IMPLEMENT):
   a. Generate contract stub from the plan (schema only, no implementation)
   b. Validate stub against both producer and consumer expectations
   c. Both repos commit the contract stub to their branches
   d. Only after contract agreement: proceed to IMPLEMENT on both sides
3. **Contract checkpoint:** At VERIFY, both sides validate their implementation
   matches the agreed contract stub

**State machine integration:** CONTRACT_AGREEMENT is implemented as a sub-step within the VALIDATING state (not a new top-level state). It runs after `verdict_GO` and before the transition to IMPLEMENTING. No new transition table rows are needed — the orchestrator handles it as conditional logic within the VALIDATING → IMPLEMENTING transition, similar to how contract validation (fg-250) already works. If contract agreement fails, it routes back to PLANNING (increment `validation_retries`).
```

#### Bi-directional Dependencies (A7b)

Update `shared/sprint-state-schema.md` to support:

```json
"dependencies": {
  "type": "contract",
  "contract_file": "shared/api-spec.yaml",
  "producer": "git@github.com:org/backend.git",
  "consumer": "git@github.com:org/frontend.git",
  "checkpoint": "contract_agreed"
}
```

When both sides need each other's output:
1. Both sides implement to the contract stub (not to each other's actual code)
2. Contract stub serves as the stable interface
3. Integration verification happens at SHIP, not during IMPLEMENT

#### Integration Smoke Tests (A7c)

Add to `fg-103-cross-repo-coordinator.md` a new phase:

```markdown
## Integration Verification (pre-SHIP gate)

Before creating PRs for cross-repo features:
1. Check if both repos have `commands.integration_test` configured
2. If yes: run integration tests that exercise the contract boundary
3. If tests fail: report findings, block PR creation for both repos
4. If no integration tests configured: skip (advisory warning)
```

---

### P2-3: Reviewer Consolidation

**Items:** A9, A35

**Problem:** Three separate frontend reviewers (`fg-413-frontend-reviewer`, `fg-414-frontend-quality-reviewer`, `fg-415-frontend-performance-reviewer`) each load their own system prompt. This is 3x the token cost for what could be one agent with modes.

#### Merge Plan

Merge `fg-414-frontend-quality-reviewer.md` (which handles a11y + performance) into `fg-413-frontend-reviewer.md` (which handles conventions + framework patterns), creating a single frontend reviewer with modes:

```yaml
---
name: fg-413-frontend-reviewer
description: Reviews frontend code for conventions, accessibility, performance, and framework-specific patterns across React, Svelte, Vue, Angular.
tools: ['Read', 'Glob', 'Grep', 'Bash']
---
```

The agent receives a `mode` parameter in its dispatch prompt:

```
Review mode: [full | conventions-only | performance-only | a11y-only]
```

- `full` (default): all three review domains (conventions + a11y + performance) in one pass
- Individual modes for targeted review when needed

Delete `fg-414-frontend-quality-reviewer.md` only (1 file — `fg-415` does not exist; it was previously merged into fg-414).

Update `fg-400-quality-gate.md` batch config to dispatch one agent with `mode: full` instead of three separate agents.

**Agent count change:** The current codebase has **36 agents**. P2-3 deletes `fg-414-frontend-quality-reviewer.md` (1 file). P1-3 adds `fg-505-build-verifier.md` (1 file). Net result: **36 agents** (no change to total count).

Update `CLAUDE.md` description tiering line from "Tier 2 (reviewers, 9)" to "Tier 2 (reviewers, 8)" — the reviewer list at line 80 already shows 8 correctly, but the tier count at the agent rules section is stale.

---

### P2-4: Retrospective Guardrails

**Items:** A10, A36

**Problem:** The retrospective agent auto-tunes `max_iterations`, `plateau_patience`, `plateau_threshold` — parameters that control the deterministic state machine. Unconstrained tuning could cascade into broken behavior.

#### Tuning Bounds

Add to `fg-700-retrospective.md`:

```markdown
## Auto-Tuning Guardrails

When proposing configuration changes, respect these hard bounds:

| Parameter | Min | Max | Max Change Per Run |
|-----------|-----|-----|--------------------|
| max_iterations | 3 | 20 | ±2 |
| plateau_patience | 1 | 5 | ±1 |
| plateau_threshold | 0 | 10 | ±2 |
| target_score | pass_threshold | 100 | ±5 |
| max_fix_loops | 2 | 10 | ±1 |
| max_test_cycles | 2 | 10 | ±1 |
| max_review_cycles | 1 | 5 | ±1 |

### Rollback on Regression

Track tuning history in `forge-config.md` under `## Auto-Tuning History`:

If the CURRENT run's score is worse than the PREVIOUS run's score by > 10 points
AND the retrospective tuned a parameter in the previous run:
1. Revert the tuned parameter to its pre-tuning value
2. Log: "Rolling back {parameter} from {new_value} to {old_value} — regression detected"
3. Add `<!-- locked: {parameter} -->` fence for 3 runs (prevent re-tuning)
```

---

### P2-5: Agent Prompt Compression

**Items:** A15

**Problem:** Many agents carry inline copies of shared rules (forbidden actions, output format, finding format). This duplicates tokens across every agent dispatch.

#### Reference-Based System

Instead of each agent containing:
```markdown
### Forbidden Actions
- DO NOT modify source files...
- DO NOT modify shared contracts...
[20 lines duplicated in every reviewer]
```

Replace with:
```markdown
**Constraints:** Follow `shared/agent-defaults.md` §Standard Reviewer Constraints.
```

This is already partially done (agents reference `shared/agent-defaults.md`), but many agents still carry "compressed inline versions." The change:

1. Audit all 36 agents for inline copies of shared rules (specifically: Forbidden Actions, Finding Format, Output Format, Convention Drift Check, MCP Degradation)
2. Replace each inline copy with a one-line reference: `**Constraints:** Follow shared/agent-defaults.md §{section-name}.`
3. Accept the Read tool overhead (1 extra Read call per agent) in exchange for smaller system prompts
4. Estimated savings: ~200-500 tokens per reviewer agent × 8 reviewers = 1,600-4,000 tokens per review cycle

**Acceptance criteria:**
- Grep for duplicated text blocks (>3 lines matching agent-defaults.md) returns zero hits across all agent .md files
- Every agent that previously had inline constraints now has a reference line
- `validate-plugin.sh` check: no agent contains >50% overlap with `shared/agent-defaults.md`

---

### P2-6: State Splitting

**Items:** A5d, A23

**Problem:** All state in one file means any corruption destroys everything.

#### Design

Split `state.json` into 3 files:

```
.forge/
├── state.json              # Core: story_id, story_state, mode, counters, timestamps
├── state-integrations.json # Integrations: linear, neo4j, context7, etc.
├── state-convergence.json  # Convergence: phase, iterations, score_history, plateau
```

`forge-state.sh` and `forge-state-write.sh` manage all three atomically. If one corrupts, the others survive. Recovery only needs to reconstruct the corrupted file.

**Status:** DEFERRED. Implement only if P0-2 (atomic writes + WAL) proves insufficient in practice. The trigger condition: if state corruption is reported by ≥2 users OR if `state-reconstruction` recovery strategy fires ≥3 times across tracked runs. Until triggered, this item is not implemented.

**Acceptance criteria (if triggered):**
- All three files written atomically via `forge-state-write.sh`
- Corruption of any single file does not prevent reading the other two
- `forge-state.sh` transparently reads/writes across all three files
- All existing tests continue to pass

---

### P2-7: Session Boundaries

**Items:** O1d, B15

**Problem:** A single conversation for the entire pipeline accumulates context until it degrades.

#### Design

The orchestrator can optionally break into separate sessions at phase boundaries:

1. **Session 1** (boot): PREFLIGHT → VALIDATE. State handoff via `state.json`.
2. **Session 2** (execute): IMPLEMENT → REVIEW convergence loop. State handoff via `state.json`.
3. **Session 3** (ship): DOCS → LEARN. State handoff via `state.json`.

This is enabled by the phase split (P0-3). Each session loads only its phase document.

**Implementation:** Add to `forge-config.md`:

```yaml
orchestrator:
  session_boundaries: false   # Default false. Set true for very large features.
```

When enabled, the orchestrator writes a "resume marker" to `state.json` at phase boundaries and exits. The next session resumes from the marker.

**Status:** EXPLORATORY. Implement only if the compaction hook (P2-8) proves insufficient. The trigger condition: if pipeline runs consistently hit context limits (observed via token tracking from P1-1) despite compaction hooks. Until triggered, this item is not implemented.

**Acceptance criteria (if triggered):**
- Each session boundary writes a resume marker to `state.json` and exits cleanly
- New session resumes from the marker without state loss
- Total context per session stays under 500K tokens
- All existing tests continue to pass

---

### P2-8: Compaction Hook

**Items:** O3, O10, B13-B14, B24

**Problem:** The orchestrator instructions say "run /compact between major stages" but this relies on the LLM remembering to do it, and `/compact` may not be invocable by a subagent.

#### Automatic Compaction via Hook

Add a new hook to `hooks/hooks.json`:

```json
{
  "PostToolUse": [
    {
      "matcher": "Agent",
      "hooks": [{
        "type": "command",
        "command": "forge-compact-check.sh",
        "timeout": 3
      }]
    }
  ]
}
```

Create `shared/forge-compact-check.sh`:

```bash
#!/usr/bin/env bash
# After every Agent dispatch, check if compaction is needed
# This is advisory — the hook outputs a suggestion, doesn't force compaction

FORGE_DIR="${FORGE_DIR:-.forge}"
TOKEN_FILE="${FORGE_DIR}/.token-estimate"

# Increment dispatch counter
count=0
if [[ -f "$TOKEN_FILE" ]]; then
  count=$(cat "$TOKEN_FILE")
fi
count=$((count + 1))
echo "$count" > "$TOKEN_FILE"

# Suggest compaction every 5 agent dispatches
if (( count % 5 == 0 )); then
  echo "SUGGESTION: Consider running /compact to free context space (${count} dispatches since last compact)"
fi
```

**Output mechanism:** PostToolUse hook stdout may not be directly surfaced to the LLM conversation for all matchers. As a fallback, the hook also writes its suggestion to `.forge/.compact-suggestion`. The orchestrator checks this file at stage boundaries (alongside `.forge/.hook-failures.log`). If the file exists and contains a suggestion, the orchestrator acts on it and deletes the file. This is more reliable than relying on hook stdout visibility or LLM memory.

---

### P2-9: Miscellaneous Fixes

#### Clean Git Checkpoints (O8)

In `fg-100-orchestrator-execute.md` §4.1, replace:

```markdown
# OLD:
git add -A && git commit -m "wip: pipeline checkpoint pre-implement" --allow-empty

# NEW:
git add -A
if ! git diff --cached --quiet; then
  git commit -m "wip: pipeline checkpoint pre-implement"
fi
```

Only create a checkpoint commit if there are actual staged changes.

#### Pipeline Timeout Enforcement (O9)

Create `shared/forge-timeout.sh`:

```bash
#!/usr/bin/env bash
# Check if pipeline has exceeded its time budget
# Called by the orchestrator at each stage transition

FORGE_DIR="${1:-.forge}"
MAX_SECONDS="${2:-7200}"  # Default 2 hours

STATE_FILE="${FORGE_DIR}/state.json"
start_ts=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('stage_timestamps',{}).get('preflight',''))")

if [[ -z "$start_ts" ]]; then
  exit 0  # No start time, skip check
fi

elapsed=$(python3 -c "
from datetime import datetime, timezone
start = datetime.fromisoformat('$start_ts'.replace('Z','+00:00'))
now = datetime.now(timezone.utc)
print(int((now - start).total_seconds()))
")

if (( elapsed >= MAX_SECONDS )); then
  echo "TIMEOUT: Pipeline has been running for ${elapsed}s (limit: ${MAX_SECONDS}s)"
  exit 1
fi

# Warning at 80%
warning_threshold=$(( MAX_SECONDS * 80 / 100 ))
if (( elapsed >= warning_threshold )); then
  echo "WARNING: Pipeline at ${elapsed}s of ${MAX_SECONDS}s time budget ($(( elapsed * 100 / MAX_SECONDS ))%)"
  exit 0
fi

exit 0
```

The orchestrator calls this at each stage boundary. On exit 1, it escalates to the user.

---

### P2-10: Tests, Validation, Docs

**Items:** T2-T5, D1

#### Update `tests/validate-plugin.sh`

Add structural checks for new files:
- `forge-state.sh` exists and is executable
- `forge-state-write.sh` exists and is executable
- `forge-token-tracker.sh` exists and is executable
- `forge-linear-sync.sh` exists and is executable
- Orchestrator core, boot, execute, ship files exist
- Mode overlay files exist for all 7 modes
- `fg-505-build-verifier.md` exists with correct frontmatter
- `fg-414` and `fg-415` no longer exist (after P2-3 merge)

#### Contract Tests

New `tests/contract/state-machine-contract.bats`:
- Every row in `state-transitions.md` has a corresponding transition in `forge-state.sh`
- Every event in `forge-state.sh` appears in `state-transitions.md`
- Counter increments in `forge-state.sh` match the transition table descriptions

New `tests/contract/mode-overlay-contract.bats`:
- Every mode file has valid YAML frontmatter
- Every mode's `stages` keys are valid stage names
- Referenced agents exist

#### Update CLAUDE.md

- Agent count: 36 (unchanged net — P1-3 adds fg-505, P2-3 removes fg-414)
- New scripts section listing `forge-state.sh`, `forge-state-write.sh`, etc.
- Orchestrator split: describe the 4-file structure
- Mode overlays: describe `shared/modes/` directory
- State schema version bump: 1.4.0 → 1.5.0
- New scoring defaults: `shipping.min_score: 90`

---

## State Schema v1.5.0 — Consolidated Changes

All state.json changes across waves are collected here for a single migration:

```json
{
  "version": "1.5.0",
  "_seq": 1,

  "tokens": {
    "estimated_total": 0,
    "budget_ceiling": 2000000,
    "by_stage": {},
    "by_agent": {},
    "budget_warning_issued": false
  },

  "decision_quality": {
    "reviewer_agreement_rate": 0.0,
    "findings_with_low_confidence": 0,
    "overridden_findings": 0,
    "total_decisions_logged": 0
  },

  "mode_config": {},

  "convergence": {
    "diminishing_count": 0,
    "unfixable_info_count": 0
  }
}
```

New fields added to existing sections (defaults shown — all are backwards-compatible):
- `_seq` (integer, required): Monotonic write counter. Starts at 1. Incremented on every write by `forge-state-write.sh`.
- `tokens` (object, optional): Token budget tracking. Added by P1-1. Absent = no tracking.
- `decision_quality` (object, optional): LLM decision quality metrics. Added by P1-2. Absent = no tracking.
- `mode_config` (object, optional): Parsed mode overlay settings. Added by P1-5. Absent = standard mode.
- `convergence.diminishing_count` (integer): Consecutive low-gain iterations. Added by P0-4. Default 0.
- `convergence.unfixable_info_count` (integer): INFO findings that weren't fixed. Added by P1-7. Default 0.

### Token Tracker Integration with Atomic Writes

`forge-token-tracker.sh record` writes to state.json's `tokens` section using `forge-state-write.sh` (not directly). Flow:

```
1. forge-token-tracker.sh record <stage> <agent> <input> <output>
2. → reads current state.json via forge-state-write.sh read
3. → updates tokens.by_stage[stage] and tokens.by_agent[agent]
4. → writes back via forge-state-write.sh write (atomic, WAL, _seq increment)
```

This ensures token tracking uses the same atomic write pipeline as state transitions.

---

## Cross-Cutting Concerns

### Backwards Compatibility

- **State schema:** Version bumps from 1.4.0 to 1.5.0. New fields have defaults; existing state.json files continue to work. `forge-state.sh init` creates v1.5.0.
- **Orchestrator split:** The old `fg-100-orchestrator.md` is replaced by 4 files. Any external references to the old file need updating. The `plugin.json` agent list needs updating.
- **Reviewer merge:** `fg-414` and `fg-415` are deleted. Quality gate batch configs referencing them need migration to `fg-413` with mode parameter.
- **Scoring change:** `shipping.min_score` default changes from 100 to 90. Existing `forge-config.md` files that explicitly set `min_score: 100` are unaffected (explicit > default).
- **Hooks:** New hooks are additive. Existing hooks unchanged.

### Testing Strategy

Every new script gets:
1. **Unit tests** in `tests/unit/` (isolated component behavior)
2. **Contract tests** in `tests/contract/` (interface adherence)
3. **Scenario tests** in `tests/scenario/` (end-to-end flows)

Existing tests updated:
- `validate-plugin.sh` for new file structure
- `agent-frontmatter.bats` for new/renamed agents
- `ui-frontmatter-consistency.bats` for fg-505 UI tier

### File Manifest

**New files (21):**
- `shared/forge-state.sh`
- `shared/forge-state-write.sh`
- `shared/check-prerequisites.sh` (promoted from P1-6 to P0 — required by forge-state.sh)
- `shared/forge-token-tracker.sh`
- `shared/forge-linear-sync.sh`
- `shared/forge-timeout.sh`
- `shared/forge-sim.sh`
- `shared/forge-compact-check.sh`
- `shared/cross-repo-contracts.md`
- `shared/modes/standard.md`
- `shared/modes/bugfix.md`
- `shared/modes/migration.md`
- `shared/modes/bootstrap.md`
- `shared/modes/testing.md`
- `shared/modes/refactor.md`
- `shared/modes/performance.md`
- `agents/fg-100-orchestrator-core.md`
- `agents/fg-100-orchestrator-boot.md`
- `agents/fg-100-orchestrator-execute.md`
- `agents/fg-100-orchestrator-ship.md`
- `agents/fg-505-build-verifier.md`
- `tests/fixtures/sim/*.yaml` (10 scenario files)

**Modified files (21):**
- `shared/scoring.md` (P0-4: min_score default, P1-7: INFO policy)
- `shared/convergence-engine.md` (P0-4: diminishing returns)
- `shared/state-schema.md` (P0-2: `_seq` + WAL fields, P1-1: `tokens` section, P1-2: `decision_quality` section, P0-4: `diminishing_count`, P1-7: `unfixable_info_count`, P1-5: `mode_config` — consolidated as state schema v1.5.0)
- `shared/state-transitions.md` (P0-4: row 50 score_diminishing, P1-1: row E8 token_budget_exhausted)
- `shared/state-integrity.sh` (P1-2: decision log validation)
- `shared/checks/engine.sh` (P1-6: file locks replacing env var guard)
- `shared/checks/output-format.md` (P1-2: confidence field)
- `shared/decision-log.md` (P1-2: confidence and agreement tracking fields)
- `shared/sprint-state-schema.md` (P2-2: bi-directional dependency support)
- `hooks/hooks.json` (P2-8: compaction hook — additive only, no schema-breaking changes)
- `agents/fg-400-quality-gate.md` (P1-2: reviewer agreement tracking)
- `agents/fg-413-frontend-reviewer.md` (P2-3: absorb fg-414 content + modes)
- `agents/fg-700-retrospective.md` (P1-2: decision quality section, P2-4: tuning guardrails)
- `agents/fg-200-planner.md` (P1-2: decision log population instruction)
- `agents/fg-210-validator.md` (P1-2: decision log population instruction)
- `agents/fg-300-implementer.md` (P1-2: decision log population instruction)
- `agents/fg-103-cross-repo-coordinator.md` (P2-2: integration verification phase)
- `.claude-plugin/plugin.json` (P0-3: update description/keywords if needed — agents are auto-discovered from `agents/` directory, no manual agent list to update)
- `tests/validate-plugin.sh` (P2-10: structural checks for all new files)
- `skills/forge-init.md` (P1-6: invoke check-prerequisites.sh)
- `CLAUDE.md` (P2-10: reflect new architecture)

**Deleted files (2):**
- `agents/fg-100-orchestrator.md` (replaced by 4 split files)
- `agents/fg-414-frontend-quality-reviewer.md` (merged into fg-413)

**New test files (6):**
- `tests/unit/forge-state.bats`
- `tests/unit/forge-state-write.bats`
- `tests/scenario/state-transitions.bats`
- `tests/contract/state-machine-contract.bats`
- `tests/contract/mode-overlay-contract.bats`
- `tests/scenario/simulation.bats`

---

## Migration & Backwards Compatibility

### Migration Steps (for consuming projects)

1. **After P0:** Run `/forge-init` to regenerate project config. Existing `.forge/state.json` files auto-migrate (new fields get defaults).
2. **After P1:** Update `forge.local.md` quality gate batches if they reference `fg-414` or `fg-415` (P2-3 only).
3. **After P2:** No action required. New features are opt-in.

### Risk Assessment

| Wave | Risk | Mitigation |
|------|------|-----------|
| P0 | High — orchestrator split changes the core dispatch model | Validate with dry-run on 3 test projects before merge |
| P1 | Medium — new scripts + agent changes | Each script independently testable |
| P2 | Low — additive features, optional behavior | Feature flags for experimental items |
