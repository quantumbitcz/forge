# Q06: Core Contract Refinements

## Status
DRAFT — 2026-04-13

## Problem Statement

Core Contracts scored A (95/100) in the system review. Five issues prevent reaching A+:

1. **MEDIUM and HIGH confidence are functionally identical.** Both have a 1.0x scoring multiplier (see `shared/scoring.md` lines 86-91). The semantic distinction between "reviewer stands behind it" (MEDIUM) and "full confidence" (HIGH) carries no weight in the scoring formula. This defeats the purpose of having three confidence tiers -- effectively there are only two: "confident" (1.0x) and "uncertain" (0.5x).

2. **PREEMPT decay for "loaded but not reported" is ambiguous.** The PREEMPT decay mechanism (10 unused applications cause HIGH->MEDIUM->LOW->ARCHIVED) references "loaded but not reported" without defining what counts as "loaded." If an agent's context window is too small to include a PREEMPT item, does that count as unused? If the item is loaded but the relevant code pattern is not present in the current changeset, is that unused?

3. **Dual oscillation detection is undocumented.** `shared/convergence-engine.md` defines REGRESSING state (cross-iteration oscillation), and `shared/scoring.md` defines the Consecutive Dip Rule (within-iteration oscillation in quality gate cycles). Both are active simultaneously but `shared/state-transitions.md` only documents their effects, not their interaction or precedence.

4. **`shared/logging-rules.md` is skeletal.** At 13 lines, it covers only application-level logging conventions for consuming projects (no PII, structured logging, etc.). It says nothing about the forge pipeline's own logging: agent log format, log levels, token budgets for log output, or what must not be logged. Agents interpret "log to stage notes" differently.

5. **Mode overlays only specify `target_score`.** The 7 mode overlays (`shared/modes/*.md`) only override `target_score` in review/ship stages. Other convergence parameters (`max_iterations`, `plateau_threshold`, `plateau_patience`, `max_quality_cycles`) use global defaults regardless of mode, even though different modes have fundamentally different convergence characteristics (e.g., bugfix should converge faster with less patience than migration).

## Target
Core Contracts A -> A+ (95 -> 98+)

## Detailed Changes

### 1. MEDIUM Confidence Multiplier: 1.0x -> 0.75x

**Rationale:** MEDIUM confidence means the reviewer believes the finding is likely correct but is not fully certain. A 0.75x multiplier creates meaningful differentiation:
- HIGH (1.0x): Full deduction. Reviewer is certain.
- MEDIUM (0.75x): 75% deduction. Reviewer is likely correct but acknowledges uncertainty.
- LOW (0.5x): Half deduction. Reviewer is uncertain, finding flagged for human review.

**Scoring impact examples:**

| Finding | Severity | Confidence | Current Deduction | New Deduction |
|---------|----------|-----------|-------------------|---------------|
| SEC-AUTH-001 | CRITICAL (-20) | HIGH | -20 | -20 |
| ARCH-LAYER-002 | WARNING (-5) | MEDIUM | -5 | -3.75 (round to -4) |
| QUAL-NAME-003 | INFO (-2) | LOW | -1 | -1 |
| PERF-N+1-004 | WARNING (-5) | MEDIUM | -5 | -3.75 (round to -4) |

**Rounding rule:** Fractional deductions are rounded to the nearest integer (standard rounding: 0.5 rounds up). This prevents accumulation of fractional points across many findings.

**Files to update:**
- `shared/scoring.md`: Update the Confidence-Weighted Scoring table (lines 86-91), update the example (lines 94-100), add rounding rule
- `CLAUDE.md`: Update the line referencing confidence multipliers

**Backward compatibility:** Findings without a confidence field default to HIGH (1.0x), preserving existing behavior. Scores for runs with no MEDIUM findings are unchanged.

**Routing impact:** MEDIUM findings remain auto-dispatched to the implementer (existing behavior, line 109). Only LOW findings are excluded from fix cycles. The 0.75x multiplier affects scoring weight, not routing.

### 2. PREEMPT Decay Clarification with Concrete Examples

**Location:** Add a new subsection to `shared/agent-communication.md` after the existing PREEMPT discussion. Also update `CLAUDE.md` gotchas section.

**New section: "PREEMPT Decay Counting Rules"**

Three states a PREEMPT item can be in during a pipeline run:

| State | Counts as | Decay effect |
|-------|-----------|-------------|
| Loaded + checked + finding reported | "Used" | Resets decay counter to 0 |
| Loaded + checked + no match in changeset | "Loaded but not reported" | +1 decay unit |
| Not loaded (agent context too small) | Not counted | No decay change |

**Example 1: Item loaded, checked, finding reported (resets decay)**

PREEMPT item: "Always use `@Transactional(readOnly = true)` for query-only service methods."

Run N: The implementer writes a new service method with `@Transactional`. The code reviewer loads this PREEMPT item, checks the new method, and finds it has `@Transactional` without `readOnly = true` on a query method. Finding reported: `CONV-TX-READONLY | WARNING`. Decay counter resets to 0.

**Example 2: Item loaded, checked, no match found (+1 decay unit)**

PREEMPT item: "Never use `Thread.sleep()` in production code."

Run N: The implementer writes a new REST controller. The code reviewer loads this PREEMPT item and checks all new/modified files. No `Thread.sleep()` calls found in the changeset. The item was loaded and checked but produced no finding. Decay counter increments by 1.

After 10 such runs (loaded but never triggered), the item decays: HIGH -> MEDIUM -> LOW -> ARCHIVED.

**Example 3: Item not loaded, agent context too small (no decay change)**

PREEMPT item: "Prefer `kotlinx.serialization` over `Jackson` for Kotlin multiplatform modules."

Run N: The pipeline runs in bugfix mode with reduced review (3 agents). The code reviewer's context is filled with bugfix-specific findings and the PREEMPT item list exceeds the agent's context window. This item is not included in the dispatch prompt. The decay counter is unchanged -- the item was not given a chance to prove relevance.

**Detection mechanism:** The orchestrator tracks which PREEMPT items were included in each agent dispatch prompt via `preempt_items_loaded[]` in stage notes. Items not in `preempt_items_loaded` for any agent in the run are classified as "not loaded." Items in `preempt_items_loaded` but not in any agent's `findings[]` are classified as "loaded but not reported."

**Auto-discovered items:** Items with `source: auto-discovered` follow the same rules but decay 2x faster (5 non-reports instead of 10).

### 3. Oscillation Detection Interaction Model

**Location:** Add a new section to `shared/state-transitions.md` after the "Mode Overlay Effects on Transitions" section.

**New section: "Oscillation Detection Interaction"**

Two complementary oscillation detection mechanisms operate concurrently:

| Mechanism | Scope | Operates on | Authority |
|-----------|-------|-------------|-----------|
| Convergence engine REGRESSING | Cross-iteration | `convergence.score_history[]` across IMPLEMENT->REVIEW cycles | **Authoritative** (triggers state transition C9) |
| Quality gate Consecutive Dip Rule | Within-iteration | `score_history[]` within a single convergence iteration's quality gate cycles | **Advisory** (logs WARNING, escalates within iteration) |

**Interaction rules:**

1. **Convergence engine is authoritative for state transitions.** When the convergence engine detects REGRESSING (score delta exceeds `oscillation_tolerance` across iterations), it triggers transition C9 -> ESCALATED. The quality gate's inner dip detection cannot override or delay this.

2. **Quality gate is authoritative within its iteration.** When the quality gate detects two consecutive dips within its review cycles (the Consecutive Dip Rule in `scoring.md`), it escalates within the current convergence iteration. This causes the convergence engine to receive a `score_regressing` event for C9 evaluation.

3. **No double escalation.** If the quality gate's Consecutive Dip Rule triggers an escalation AND the convergence engine independently detects REGRESSING on the same score delta, only one ESCALATED transition fires. The convergence engine checks `story_state == ESCALATED` before transitioning.

4. **Precedence on simultaneous detection:** If both mechanisms detect regression on the same review cycle completion:
   - The quality gate emits its Consecutive Dip escalation first (it runs synchronously within the review stage)
   - The convergence engine, receiving the review result, detects REGRESSING
   - The orchestrator sees `story_state` is already ESCALATED and does not re-escalate
   - The decision log records both detections with `source: quality_gate_dip_rule` and `source: convergence_engine_regressing`

5. **Advisory dips that do not trigger convergence REGRESSING:** A single dip within tolerance (scoring.md rule 4) is logged by the quality gate as WARNING but does not trigger convergence engine REGRESSING. The convergence engine only evaluates score deltas between iterations, not within quality gate cycles.

**State field mapping:**

| Field | Written by | Read by |
|-------|-----------|---------|
| `score_history[]` (state.json) | Quality gate (append after each cycle) | Convergence engine (cross-iteration delta), quality gate (within-iteration dip detection) |
| `convergence.state` | Convergence engine | Orchestrator (transition lookup) |
| `convergence.last_score_delta` | Convergence engine | Orchestrator (oscillation tolerance check) |

### 4. Expand logging-rules.md to Full Pipeline Logging Contract

**Current state:** `shared/logging-rules.md` is 13 lines covering only application-level logging conventions for consuming projects.

**Change:** Restructure the file into two sections: (A) the existing application logging rules, and (B) new pipeline logging rules.

**New content for Section B: Pipeline Logging Rules**

```markdown
## Pipeline Logging Rules

These rules govern how forge agents log within the pipeline itself.

### Log Levels

| Level | When to use | Examples |
|-------|------------|---------|
| `DEBUG` | Development/diagnostic only. Never in production pipeline output. | Raw tool output parsing, regex match details |
| `INFO` | Stage transitions, agent dispatch, key decisions. | "Dispatching fg-300-implementer with 3 tasks", "Transitioning to REVIEWING" |
| `WARNING` | Fallbacks, degraded mode, minor failures. | "MCP Linear unavailable, skipping sync", "Component cache invalidated" |
| `ERROR` | Failures requiring attention or recovery. | "Build failed (exit 1)", "Recovery budget exhausted" |

### Log Format

All structured log entries in stage notes follow this format:

    [{level}] [{agent_id}] {message}

Examples:
- `[INFO] [fg-100-orchestrator] Transitioning IMPLEMENTING -> VERIFYING`
- `[WARNING] [fg-400-quality-gate] Reviewer fg-411 timed out, coverage gap filed`
- `[ERROR] [fg-500-test-gate] Test command exited with code 1 (3 failures)`

### Where Agents Log

| Agent tier | Log destination | Visibility |
|------------|----------------|-----------|
| Orchestrator (fg-100) | `state.json` fields + stage notes | Persistent across runs |
| Coordinators (fg-400, fg-500, fg-600) | Stage notes (stage_N_notes) | Per-run, read by retrospective |
| Leaf agents (fg-300, fg-410-420) | Return value to coordinator | Coordinator summarizes in stage notes |
| Hook scripts | `.forge/.hook-failures.log` | Persistent, surfaced by forge-status |

### Token Budget for Logging

Agent log sections in stage notes MUST stay within 500 tokens. If an agent would produce more:
1. Summarize: "12 findings (3 CRITICAL, 5 WARNING, 4 INFO)" instead of listing all
2. Reference: "Full findings in quality gate report" instead of duplicating
3. Truncate with count: "Showing top 5 of 23 entries"

### What NOT to Log

- File contents (reference by path: `src/main/App.kt:42`)
- Full tool output (extract structured data: exit code, counts, durations)
- User data, credentials, or PII (per Section A rules)
- Conversation history or LLM reasoning traces
- Raw JSON state (reference field names: `state.convergence.phase`)
```

### 5. Mode Overlay Convergence Parameter Expansion

**Current state:** Mode overlays in `shared/modes/*.md` only override `target_score` (bugfix, bootstrap, testing set it to `pass_threshold`). The convergence parameters `max_iterations`, `plateau_threshold`, `plateau_patience`, and `max_quality_cycles` are not specified, defaulting to global values regardless of mode.

**Change:** Add convergence parameter overrides to each mode overlay's YAML frontmatter.

**Updated mode overlays:**

**standard.md** (unchanged -- uses global defaults explicitly documented):
```yaml
mode: standard
convergence:
  max_iterations: ~    # Uses forge-config.md value (default 15)
  plateau_threshold: ~  # Uses forge-config.md value (default 3)
  plateau_patience: ~   # Uses forge-config.md value (default 3)
  max_quality_cycles: ~ # Uses forge-config.md value (default 3)
stages: {}
```

**bugfix.md** (fast convergence, low patience):
```yaml
convergence:
  max_iterations: 10      # Bugfixes should converge quickly
  plateau_threshold: 3     # Same sensitivity as standard
  plateau_patience: 2      # Less patience -- fix should be targeted
  max_quality_cycles: 2    # Fewer review cycles for focused changes
```

**bootstrap.md** (minimal convergence, scaffolding is pass/fail):
```yaml
convergence:
  max_iterations: 5       # Scaffolding rarely needs many iterations
  plateau_threshold: 5     # Generous -- scaffolding scores may fluctuate
  plateau_patience: 1      # No patience -- scaffold works or it doesn't
  max_quality_cycles: 1    # Single review pass for scaffolded code
```

**migration.md** (extended convergence, migrations are complex):
```yaml
convergence:
  max_iterations: 15      # Migrations may need many attempts
  plateau_threshold: 3     # Standard sensitivity
  plateau_patience: 3      # Standard patience
  max_quality_cycles: 3    # Standard review depth
```

**testing.md** (test-focused, reduced review):
```yaml
convergence:
  max_iterations: 10      # Tests should converge quickly
  plateau_threshold: 3     # Standard sensitivity
  plateau_patience: 2      # Less patience -- test code is simpler
  max_quality_cycles: 2    # Fewer review cycles for test-only changes
```

**refactor.md** (careful convergence, must preserve behavior):
```yaml
convergence:
  max_iterations: 12      # Slightly fewer than standard
  plateau_threshold: 2     # Tighter sensitivity -- refactors should improve steadily
  plateau_patience: 3      # Standard patience -- refactors may have complex interactions
  max_quality_cycles: 3    # Full review depth -- behavior preservation is critical
```

**performance.md** (standard convergence with extra review):
```yaml
convergence:
  max_iterations: 12      # Performance changes may need tuning
  plateau_threshold: 3     # Standard sensitivity
  plateau_patience: 3      # Standard patience
  max_quality_cycles: 4    # Extra review cycles -- performance review is measurement-heavy
```

**Resolution order:** Mode overlay convergence values override `forge-config.md` convergence values, which override plugin defaults. The orchestrator resolves at PREFLIGHT and stores effective values in `state.json.convergence`.

**Validation:** Update PREFLIGHT validation to check mode-specific convergence parameters against the same constraints defined in `scoring.md`:
- `max_iterations`: 3-20
- `plateau_threshold`: 0-10
- `plateau_patience`: 1-5
- `max_quality_cycles`: 1-10 (new constraint)

**State transitions impact:** Update the Mode Overlay Effects table in `shared/state-transitions.md` to include the new convergence parameters:

| Mode | Affected Guard | Override |
|------|---------------|----------|
| bugfix | `max_iterations` in C1-C10 | 10 (default 15) |
| bugfix | `plateau_patience` in C8/C10 | 2 (default 3) |
| bugfix | `target_score` in C6, C8 | `pass_threshold` |
| bootstrap | `max_iterations` in C1-C10 | 5 |
| bootstrap | `plateau_patience` in C8/C10 | 1 |
| bootstrap | `target_score` in C6, C8 | `pass_threshold` |
| testing | `max_iterations` in C1-C10 | 10 |
| testing | `plateau_patience` in C8/C10 | 2 |
| testing | `target_score` in C6, C8 | `pass_threshold` |
| refactor | `plateau_threshold` in C7/C8 | 2 |
| performance | `max_quality_cycles` | 4 |

## Testing Approach

1. **Scoring unit test:** Verify MEDIUM confidence multiplier (0.75x) produces correct deductions:
   - CRITICAL + MEDIUM = -15 (20 * 0.75)
   - WARNING + MEDIUM = -4 (5 * 0.75, rounded)
   - INFO + MEDIUM = -2 (2 * 0.75, rounded to 2)

2. **Scoring regression test:** Verify findings with no confidence field (default HIGH) produce unchanged deductions.

3. **Mode overlay test (bats):** Validate all 7 mode overlay files have a `convergence:` block with all required parameters.

4. **Mode overlay constraint test:** Validate all mode-specific convergence values are within documented ranges.

5. **State transitions test:** Verify the Mode Overlay Effects table in `state-transitions.md` includes entries for all mode overrides.

6. **Documentation test:** Verify `logging-rules.md` exceeds 50 lines (no longer skeletal).

## Acceptance Criteria

- [ ] `shared/scoring.md` defines MEDIUM multiplier as 0.75x with rounding rule
- [ ] `shared/agent-communication.md` includes 3 concrete PREEMPT decay examples with detection mechanism
- [ ] `shared/state-transitions.md` includes "Oscillation Detection Interaction" section with 5 interaction rules
- [ ] `shared/logging-rules.md` includes Pipeline Logging Rules section (levels, format, destinations, token budget, prohibitions)
- [ ] All 7 mode overlays specify `convergence:` block with `max_iterations`, `plateau_threshold`, `plateau_patience`, `max_quality_cycles`
- [ ] `shared/state-transitions.md` Mode Overlay Effects table updated with new convergence parameters
- [ ] PREFLIGHT validation checks mode-specific convergence constraints
- [ ] All existing scoring tests pass with MEDIUM multiplier change
- [ ] CLAUDE.md updated to reflect MEDIUM 0.75x multiplier

## Effort Estimate

Medium (2-3 days). Changes are documentation-heavy with targeted scoring formula updates.

- Scoring multiplier change: 0.5 day (scoring.md + CLAUDE.md + test updates)
- PREEMPT decay examples: 0.5 day (agent-communication.md)
- Oscillation interaction model: 0.5 day (state-transitions.md)
- Logging rules expansion: 0.5 day (logging-rules.md)
- Mode overlay expansion: 0.5 day (7 mode files + state-transitions.md)
- Tests: 0.5 day

## Dependencies

- The MEDIUM confidence multiplier change affects scoring calculations. Any agent that emits MEDIUM confidence findings will see slightly lower deductions. This is intentional and does not require agent changes.
- Mode overlay changes require PREFLIGHT validation updates in the orchestrator.
- No dependency on other Q-series specs, though the logging rules expansion complements Q05 (hooks logging) and Q10 (structured output).
