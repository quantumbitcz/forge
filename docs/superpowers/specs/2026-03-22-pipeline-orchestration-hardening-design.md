# Pipeline Orchestration Hardening — Design Spec

**Date:** 2026-03-22
**Scope:** Contract-first hardening of shared contracts, then orchestrator + agent updates
**Status:** Implemented — both batches delivered
**Approach:** Clean Contract Evolution (Option B) — version bumps with forward migration

---

## Context

A thorough investigation of the orchestration layer identified 15 gaps across shared contracts, the orchestrator, and agents. These range from critical (PREEMPT hit counts never updated, no design-level feedback escalation) to structural (silent check engine failures, recovery budget lacks prioritization).

This spec addresses all 15 issues in two batches:
- **Batch 1 (Contracts):** Changes to 7 shared contract files that form the foundation
- **Batch 2 (Consumers):** Orchestrator and agent updates that adopt the new contracts

---

## Batch 1: Contract Changes

### 1. State Schema (`shared/state-schema.md`)

#### 1.1 Version Bump

Schema version changes from `"1.1"` to `"1.2"`.

Forward migration: When recovery engine encounters `version: "1.1"` state files, it adds all new fields with defaults and sets `version: "1.2"`.

#### 1.2 New Fields in `state.json`

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `total_retries` | integer | 0 | Cumulative retry count across all loops |
| `total_retries_max` | integer | 10 | Global retry ceiling (configurable in pipeline-config.md) |
| `preempt_items_status` | object | `{}` | Tracks which PREEMPT items were applied/skipped/false-positive. Complements existing `preempt_items_applied` (which lists items *loaded* at PREFLIGHT). `preempt_items_applied` is retained as-is — it records what was loaded; `preempt_items_status` records what was actually used. |
| `feedback_classification` | string | `""` | `""` \| `"implementation"` \| `"design"` — set by pl-710 on PR rejection |
| `check_engine_skipped` | integer | 0 | Count of inline check engine invocations that were skipped due to timeout/error |
| `recovery_budget` | object | see below | Weighted recovery budget tracking |
| `score_history` | number[] | `[]` | Quality score per review cycle for oscillation detection. Integer with default weights; may be non-integer with custom scoring weights. |
| `linear_sync` | object | see below | Tracks Linear API operation success/failure |
| `conventions_section_hashes` | object | `{}` | Per-section SHA256 hashes (first 8 chars) for granular drift detection |

**`recovery_budget` default:**

```json
{
  "total_weight": 0.0,
  "max_weight": 5.0,
  "applications": []
}
```

Each application entry: `{ "strategy": "<name>", "weight": <float>, "stage": "<stage>", "timestamp": "<ISO8601>" }`

**`linear_sync` default:**

```json
{
  "in_sync": true,
  "failed_operations": []
}
```

Each failed operation: `{ "op": "<operation>", "error": "<message>", "timestamp": "<ISO8601>" }`

**`preempt_items_status` example:**

```json
{
  "check-openapi-before-controller": { "applied": true, "false_positive": false },
  "use-kotlin-uuid": { "applied": false, "false_positive": true }
}
```

**`recovery` object — new sub-field:**

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `budget_warning_issued` | boolean | `false` | True when recovery budget exceeds 80% |

#### 1.3 Checkpoint Schema Addition

New field in `tasks_completed[]` entries in `checkpoint-{storyId}.json`:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `preempt_items_used` | string[] | Yes | PREEMPT item identifiers applied during this task. Empty array if none. |

#### 1.4 Migration Path (1.1 → 1.2)

When recovery engine encounters `version: "1.1"`:

1. Add `total_retries: 0`, `total_retries_max: 10`
2. Add `preempt_items_status: {}`
3. Add `feedback_classification: ""`
4. Add `check_engine_skipped: 0`
5. Add `recovery_budget: { "total_weight": 0.0, "max_weight": 5.0, "applications": [] }`
6. Add `score_history: []`
7. Add `linear_sync: { "in_sync": true, "failed_operations": [] }`
8. Copy `conventions_hash` value into `conventions_section_hashes: { "_full": "<value>" }`
9. Add `recovery.budget_warning_issued: false`
10. Populate `recovery_budget.applications` from existing `recovery_applied[]` with weight 1.0 each (conservative)
11. Set `version: "1.2"`

**Downstream impact:** All agents that read state.json, orchestrator (state init + every stage transition), recovery engine (budget tracking), retrospective (PREEMPT updates).

---

### 2. Stage Contract (`shared/stage-contract.md`)

#### 2.1 Global Retry Budget

Add new section after existing retry loop table:

**Global Retry Budget**

All retry loops share a cumulative budget tracked in `state.json.total_retries`. Every retry increment (validation_retries++, verify_fix_count++, test_cycles++, quality_cycles++) also increments `total_retries`.

| Field | Default | Configurable In |
|-------|---------|-----------------|
| `total_retries_max` | 10 | `pipeline-config.md` |

When `total_retries >= total_retries_max`, the orchestrator escalates to the user regardless of which individual loop has budget remaining. Escalation format:

> "Pipeline exhausted global retry budget ({total_retries}/{total_retries_max}). Breakdown: validation={N}, build_fix={N}, test_fix={N}, quality_fix={N}. How should I proceed?"

Constraint: `total_retries_max` must be >= 5 and <= 30. If violated, use default (10).

#### 2.2 Feedback Classification in Stage 8

Replace the single-path PR rejection flow with:

| Feedback Type | Detection Heuristic | Routing |
|---|---|---|
| `implementation` | References specific files, code behavior, test cases, UI details, variable names | Reset `quality_cycles` and `test_cycles` to 0 → re-enter Stage 4 (IMPLEMENT) |
| `design` | References wrong approach, wrong decomposition, missing stories, architectural direction, "should be split", "wrong pattern" | Reset stage-specific counters (`quality_cycles`, `test_cycles`, `verify_fix_count`, `validation_retries`) to 0. Do NOT reset `total_retries` — user-driven re-plan still counts toward the global budget to prevent unbounded loops. Re-enter Stage 2 (PLAN) with feedback as planner input. |

Detection responsibility: `pl-710-feedback-capture` classifies the feedback and writes `feedback_classification` to stage notes. The orchestrator reads it and sets `state.json.feedback_classification`.

If classification is ambiguous, default to `implementation` (safer — doesn't discard the existing plan).

**Retry Loops table update:** Add a new row to the existing retry loops table in stage-contract.md:

| Loop | From → To | Counter | Max | Trigger |
|------|-----------|---------|-----|---------|
| PR rejection (implementation) | 8 SHIP → 4 IMPLEMENT | (none, but increments `total_retries`) | ∞ (bounded by `total_retries_max`) | User rejects with implementation feedback |
| PR rejection (design) | 8 SHIP → 2 PLAN | (none, but increments `total_retries`) | ∞ (bounded by `total_retries_max`) | User rejects with design feedback |

**Transition Diagram update:** Add `SHIPPING -> PLANNING` arrow (labeled "design feedback") alongside the existing `SHIPPING -> IMPLEMENTING` arrow in the ASCII transition diagram.

#### 2.3 Stage 4 Entry Condition

**Current:** "Plan validated with GO verdict; worktree created"

**New:** "Plan validated with GO verdict; worktree created on a unique branch; working tree clean"

Pre-entry checks:
1. Check `git branch --list pipeline/{story-id}` — if branch exists, append epoch suffix: `pipeline/{story-id}-{epoch}`
2. Check for stale worktree at `.pipeline/worktree` — if found, remove and log WARNING
3. Verify working tree is clean — if dirty, warn user, offer to stash. NEVER force-clean.

#### 2.4 Parallel Conflict Detection Algorithm

Replace the under-specified Stage 4 section 7.6 with:

```
BEFORE dispatching parallel group G:
  1. For each task T in G:
     - If scaffolder ran: read files_created + files_modified from scaffolder output (checkpoint schema)
     - Else: read task.files from plan (flat list of file paths the task declares it will create or modify)
  2. Build conflict map: { "path/file.kt": ["T001", "T003"] }
  3. For each file with >1 task:
     - Keep first task (by plan order) in group G
     - Move all other tasks claiming that file to new sub-group G'
     - Log in stage notes: "Conflict: {file} claimed by {tasks}. Serialized {moved_tasks}."
  4. Dispatch G (now conflict-free)
  5. After G completes, run conflict check on G' (recursive — G' may have internal conflicts)
  6. Report total serializations in stage notes
```

This check runs at IMPLEMENT time because task file lists are finalized during scaffolding.

#### 2.5 Stage 6 Oscillation Tolerance

**Canonical source:** `scoring.md` section 3.1 defines the algorithm. Stage-contract.md references it. This avoids maintaining the same logic in two places.

**Current:** "If score DECREASES between cycles → escalate"

**New:** Track `score_history[]` in state.json. After each cycle (see `scoring.md` Section 3.1 for full algorithm):

1. If `score_history` has < 2 entries: no check, continue
2. `delta = current_score - previous_score`
3. If `delta >= 0`: improvement or stable — continue
4. If `abs(delta) <= oscillation_tolerance` (default: 5): minor regression — allow one more cycle, log WARNING
5. If `abs(delta) > oscillation_tolerance`: significant regression — escalate

Configurable: `scoring.oscillation_tolerance` in `pipeline-config.md` (constraint: >= 0, <= 20).

#### 2.6 Stage 5 Check Engine Skip Reporting

Add to VERIFY Phase A actions:

> Before running build/lint, read `.pipeline/.check-engine-skipped`. If present and count > 0: report in stage notes: "{N} file edits had inline checks skipped (hook timeout/error). Running full verification now." Reset counter to 0 after reading.

**Downstream impact:** Orchestrator (all retry logic, feedback routing, worktree creation, conflict detection, oscillation handling, skip reporting).

---

### 3. Scoring (`shared/scoring.md`)

#### 3.1 Oscillation Tolerance

Add section "Score Oscillation Handling" after "Review Cycle Flow":

Track `score_history[]` in `state.json` across quality cycles. After each cycle's score is computed:

1. If `score_history` has < 2 entries: no oscillation check, continue
2. `delta = current - previous`
3. If `delta >= 0`: continue normally
4. If `abs(delta) <= oscillation_tolerance` (default: 5): minor regression — allow one more cycle, log WARNING: "Score dipped {abs(delta)} points ({previous} → {current}). Within tolerance. Continuing."
5. If `abs(delta) > oscillation_tolerance`: significant regression — escalate: "Quality regression: {previous} → {current} (delta: {delta}, tolerance: {oscillation_tolerance}). Fix cycle may be introducing new issues."

Configurable in `pipeline-config.md`:

```yaml
scoring:
  oscillation_tolerance: 5
```

Constraint: `oscillation_tolerance` must be >= 0 and <= 20. If violated, use default (5).

#### 3.2 Critical Agent Gap Severity

Strengthen partial failure handling. Add after existing rule 2:

> If the timed-out agent covers a CRITICAL-focused domain, use WARNING severity instead of INFO for the coverage gap finding:
> `{agent}:0 | REVIEW-GAP | WARNING | Critical-domain agent timed out, {focus} not reviewed | Re-run review or inspect manually`
>
> A domain is "critical-focused" if the agent's `focus` field in batch config contains any of: "security", "auth", "injection", "architecture", "boundary", "SRP", "DIP".

#### 3.3 Constraints Table Addition

Add to the existing constraints list:

| Field | Constraint |
|-------|-----------|
| `oscillation_tolerance` | >= 0 and <= 20 |

**Downstream impact:** Quality gate agent (oscillation logic, partial failure severity), orchestrator (constraint validation at PREFLIGHT).

---

### 4. Recovery Engine (`shared/recovery-engine.md`)

#### 4.1 Weighted Recovery Budget

Replace "max 5 applications" (section 8) with weighted budget:

| Strategy | Weight | Rationale |
|----------|--------|-----------|
| `transient-retry` | 0.5 | Cheap, likely to succeed |
| `tool-diagnosis` | 1.0 | Standard |
| `state-reconstruction` | 1.5 | Expensive, risk of data loss |
| `agent-reset` | 1.0 | Standard |
| `dependency-health` | 1.0 | Standard |
| `resource-cleanup` | 0.5 | Cheap, low risk |
| `graceful-stop` | 0.0 | Terminal — ends the run |

Budget ceiling: `max_weight: 5.0` (same effective limit, but cheap strategies don't starve expensive ones).

Budget warning: When `total_weight > 4.0` (80%), set `recovery.budget_warning_issued: true`, log WARNING: "Recovery budget at {percent}% — {remaining} weight remaining."

Budget exhaustion: When `total_weight >= max_weight`, escalate with full budget report.

State tracking: Use `state.json.recovery_budget` object (replaces `recovery_applied` as the primary budget tracker). Keep `recovery_applied` as derived view for backward compatibility. Derivation rule: `recovery_applied = recovery_budget.applications.map(a => a.strategy)` — updated at every budget write.

#### 4.2 Pre-Classified Error Validation

Add to section 3 "Pre-Classified Errors":

> When an error arrives with `ERROR_TYPE` and `SUGGESTED_STRATEGY`, validate:
> 1. `ERROR_TYPE` must exist in `error-taxonomy.md`
> 2. Compare `SUGGESTED_STRATEGY` with the default strategy for that `ERROR_TYPE`
> 3. If mismatched: log WARNING "Pre-classified {type} suggests {strategy}, expected {default}. Using suggested."
> 4. If `ERROR_TYPE` is unknown: log WARNING "Unknown error type {type}. Falling back to heuristic classification."
>
> The agent's suggestion is always respected (unless the error type is unknown). The warning surfaces miscalibration for the retrospective.

#### 4.3 Degraded Capabilities Enforcement

Add new section "Degraded Capability Handling":

> After recovery returns DEGRADED, the recovery engine writes the degraded capability name to `recovery.degraded_capabilities[]`.
>
> **Capability naming convention:** Use short, lowercase names matching `state.json.integrations` keys for MCP capabilities (`"context7"`, `"linear"`, `"playwright"`, `"slack"`), and tool-type names for infrastructure capabilities (`"build"`, `"test"`, `"git"`). Existing dependency-health strategy values (e.g., `"integration-tests-skipped"`, `"coverage-analysis-unavailable"`) are legacy — the dependency-health strategy in Batch 2 should be updated to emit the new-style names. Both old and new styles are accepted by the orchestrator during the migration period; the orchestrator normalizes them by stripping everything after the first `-` and lowercasing (e.g., `"integration-tests-skipped"` → `"integration"`).
>
> The orchestrator MUST check `degraded_capabilities[]` before any capability-dependent dispatch:
>
> | Degraded Capability | Skipped Operations |
> |---|---|
> | `"context7"` | Documentation prefetch (Stage 4), context7 queries |
> | `"linear"` | All Linear tracking operations (create, update, comment) |
> | `"playwright"` | Preview validation (Stage 8.5) |
> | `"slack"` | Slack notifications |
> | `"figma"` | Skip design validation (Stage 6) |
> | `"build"` | Escalate — cannot proceed without build |
> | `"test"` | Escalate — cannot proceed without tests |
> | `"git"` | Escalate — cannot proceed without git |
>
> Required capabilities (`build`, `test`, `git`) trigger immediate escalation. Optional capabilities are skipped silently with a log entry.

#### 4.4 State Reconstruction — Counter Recovery

Replace "reset all counters to 0" in state-reconstruction strategy with:

> When reconstructing counters from corrupted state:
>
> 1. **verify_fix_count:** Sum `fix_attempts` across all `tasks_completed` entries in checkpoint files
> 2. **test_cycles:** Count `stage_5_notes_*.md` sections containing "Test cycle" or "test fix"
> 3. **quality_cycles:** Count `stage_6_notes_*.md` sections containing "Quality cycle" or "review cycle"
> 4. **validation_retries:** Count `stage_3_notes_*.md` sections containing "REVISE"
> 5. **total_retries:** Sum of all above counters
> 6. **Fallback:** If a counter cannot be determined from artifacts, use the **configured maximum** (conservative — assumes all retries were used). This prevents accepting extra retries beyond limits.
>
> Log all reconstructed values: "State reconstructed: verify_fix={N} (from checkpoint), test_cycles={N} (from notes), quality_cycles={N} (from notes), validation_retries={N} (from notes)."

**Downstream impact:** Orchestrator (budget checking, degraded capability checks), all agents (via state.json reads).

---

### 5. Agent Communication (`shared/agent-communication.md`)

#### 5.1 PREEMPT Item Tracking

Add new section "6. PREEMPT Item Tracking":

> During implementation, agents that receive PREEMPT items in their dispatch prompt must report usage in stage notes:
>
> ```
> PREEMPT_APPLIED: {item-id} — applied at {file}:{line}
> PREEMPT_SKIPPED: {item-id} — not applicable ({reason})
> ```
>
> The orchestrator reads these markers from stage notes and populates `state.json.preempt_items_status`:
> - `{ "applied": true, "false_positive": false }` — item was used and relevant
> - `{ "applied": false, "false_positive": true }` — item was loaded but inapplicable
>
> The retrospective agent reads `preempt_items_status` and:
> 1. Increments `hit_count` in `pipeline-log.md` for applied items
> 2. Records false positives for confidence decay acceleration (false positive = 3 unused runs toward decay)
> 3. Logs: "PREEMPT effectiveness: {applied}/{total} items used, {false_positives} false positives"

#### 5.2 Finding Deduplication Hints — Size Cap

Add to existing section "2. Shared Findings Context":

> Cap dedup hints at **top 20 findings by severity** (all CRITICALs first, then WARNINGs, then INFOs by line number). If previous batches produced > 20 findings, include note:
>
> ```
> Previous batch findings ({N} total, showing top 20 for dedup):
> ...
> ({N-20} additional findings omitted — focus on your domain, post-hoc dedup will catch overlaps)
> ```

#### 5.3 Data Flow Diagram

Replace existing section "5. Data Flow Summary" with expanded version including state writes, Linear operations, PREEMPT feedback, and feedback classification:

```
EXPLORE agent → stage_1_notes → orchestrator → PLAN dispatch prompt
PLAN agent → stage_2_notes → orchestrator → VALIDATE dispatch prompt
                                          ↘ Linear: create Epic/Stories/Tasks
VALIDATE agent → stage_3_notes → orchestrator → IMPLEMENT dispatch prompt
                                              ↘ Linear: validation verdict comment
IMPLEMENT agent → stage_4_notes → orchestrator → state.json (preempt_items_status)
                                               → checkpoint.json (preempt_items_used)
VERIFY (test gate) → stage_5_notes → orchestrator → REVIEW dispatch prompt
REVIEW batch 1 → findings → quality gate → batch 2 (top 20 dedup hints)
REVIEW final → stage_6_notes → orchestrator → state.json (score_history)
                                            ↘ DOCS inline
SHIP agent → stage_8_notes → orchestrator → LEARN dispatch prompt
                                          ↘ Linear: PR link, status
FEEDBACK agent → classification → orchestrator → route to PLAN or IMPLEMENT
LEARN (retro) → stage_9_notes → pipeline-log.md (PREEMPT hit counts)
                              → pipeline-config.md (auto-tuning)
LEARN (recap) → recap report ↘ Linear: summary comment
```

**Downstream impact:** Implementer agents (PREEMPT reporting), quality gate (dedup hint cap), retrospective (PREEMPT hit count updates), feedback capture (classification).

---

### 6. Error Taxonomy (`shared/error-taxonomy.md`)

#### 6.1 MCP_UNAVAILABLE — Agent Instruction

Add note to MCP_UNAVAILABLE row:

> **Agent handling:** MCP failures are NOT recovery engine domain. Agents handle inline: skip the MCP-dependent operation, log INFO in stage notes ("MCP {name} unavailable, skipping {operation}"), continue with degraded capability. Do NOT call recovery engine for MCP_UNAVAILABLE.

#### 6.2 Error Severity Ordering

Add new section "Error Severity Ordering":

> When multiple errors co-occur in a stage, determine outcome by severity (highest first):
>
> 1. `CONFIG_INVALID` — pipeline cannot proceed
> 2. `PERMISSION_DENIED` — system-level block
> 3. `DISK_FULL` — resource hard limit
> 4. `STATE_CORRUPTION` — pipeline integrity
> 5. `DEPENDENCY_MISSING` — required tool absent
> 6. `GIT_CONFLICT` — version control integrity
> 7. `AGENT_TIMEOUT` / `AGENT_ERROR` — agent-level
> 8. `TOOL_FAILURE` — tool-level
> 9. `BUILD_FAILURE` / `TEST_FAILURE` / `LINT_FAILURE` — code-level (retry loops)
> 10. `NETWORK_UNAVAILABLE` — possibly transient
> 11. `MCP_UNAVAILABLE` — optional, graceful degradation
> 12. `PATTERN_MISSING` — planner error, non-blocking
>
> The highest-severity non-recoverable error determines stage outcome. Recoverable errors are attempted via recovery engine in order.

#### 6.3 NETWORK_UNAVAILABLE Permanence Detection

Add to NETWORK_UNAVAILABLE row:

> **Permanence heuristic:** After 3 consecutive transient-retry failures for the same endpoint within 60 seconds, reclassify as non-recoverable for that endpoint. Log: "Network to {endpoint} appears permanently unavailable after 3 retries." Continue with degraded mode. Do not consume further recovery budget for this endpoint.

**Downstream impact:** All agents (MCP handling instruction), recovery engine (severity ordering, permanence detection).

---

### 7. Check Engine Skip Tracking

#### 7.1 `shared/checks/engine.sh` Hook Behavior

**Current:** `trap 'exit 0' ERR` silently swallows failures.

**New:** On timeout or error:
1. Still exit 0 (do not block the file edit)
2. Increment counter in `.pipeline/.check-engine-skipped`:
   ```bash
   SKIP_FILE=".pipeline/.check-engine-skipped"
   if [ -f "$SKIP_FILE" ]; then
     count=$(cat "$SKIP_FILE")
     echo $((count + 1)) > "$SKIP_FILE"
   else
     echo 1 > "$SKIP_FILE"
   fi
   ```
3. Log to stderr: `[check-engine] Hook skipped for {file} (timeout/error)`

#### 7.2 VERIFY Phase A Integration

Orchestrator reads `.pipeline/.check-engine-skipped` at Stage 5 entry:
- If present and count > 0: report in stage notes
- Delete marker after reading
- Informational only — VERIFY runs full checks regardless

**Downstream impact:** Check engine script, orchestrator (VERIFY phase A).

---

## Batch 2: Consumer Changes (Separate Implementation Phase)

After Batch 1 contracts land, these consumers update:

| File | Changes |
|------|---------|
| `pl-100-orchestrator.md` | Adopt all new state fields, implement feedback routing, conflict algorithm, budget checking, skip reporting, total retry budget, oscillation tolerance, degraded capability checks, worktree branch collision detection, MCP mid-run health checks |
| `pl-710-feedback-capture.md` | Add feedback classification logic (implementation vs design) |
| `pl-700-retrospective.md` | Add PREEMPT hit count updates from `preempt_items_status`, false positive tracking |
| `pl-400-quality-gate.md` | Adopt oscillation tolerance, dedup hint cap (top 20), critical agent gap severity |
| `pl-300-implementer.md` | Add PREEMPT_APPLIED/PREEMPT_SKIPPED markers in stage notes |
| `shared/checks/engine.sh` | Add skip counter on timeout/error |
| `modules/*/known-deprecations.json` | Bootstrap known-deprecations for all 12 modules. Use `modules/react-vite/known-deprecations.json` as the template schema. Each module's file should contain 5-15 commonly known deprecations from that ecosystem (e.g., `javax.*` → `jakarta.*` for java-spring/kotlin-spring, Node.js deprecated APIs for typescript-node, Python 2 patterns for python-fastapi). "Bootstrap" means pre-populate with established, well-documented deprecations — not speculative ones. The layer-3 deprecation-refresh agent will maintain them incrementally after bootstrap. |
| `shared/recovery/strategies/dependency-health.md` | Update to emit new-style capability names (short, lowercase) instead of legacy descriptive strings |
| `shared/recovery/recovery-engine.md` | Already updated in Batch 1 (contract); agents adopt new budget format |

---

## Success Criteria

After both batches are implemented:

1. **PREEMPT feedback loop closed:** Hit counts increment after each run, false positives accelerate decay
2. **Design-level feedback routes to PLAN:** User rejects PR with "wrong approach" → pipeline re-plans, not re-implements
3. **Parallel conflicts are deterministic:** Explicit algorithm, no file corruption possible
4. **Retry budget is bounded:** No run exceeds `total_retries_max` cumulative retries
5. **Check engine failures are visible:** Skipped checks reported at VERIFY, not silently lost
6. **Recovery budget is fair:** Transient retries don't starve critical recovery strategies
7. **Oscillation tolerance prevents false stops:** Minor score dips don't halt the pipeline
8. **Worktree branches don't collide:** Collision detection with suffix fallback
9. **Convention drift is granular:** Per-section hashing reduces false positive warnings
10. **Linear sync is tracked:** Failed operations logged, desync reported in retrospective
11. **State reconstruction is conservative:** Counters default to max, not 0
12. **Error severity is ordered:** Aggregation uses defined priority, not arbitrary choice
13. **MCP handling is explicit:** Agents know to handle MCP failures inline, not via recovery engine
14. **Network permanence is detected:** Repeated failures stop consuming recovery budget
15. **Known deprecations bootstrap:** All 12 modules have pre-populated deprecation registries

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| State schema changes break running pipelines | Version-based forward migration (1.1 → 1.2) with safe defaults |
| Total retry budget too low (10) stops legitimate complex runs | Configurable in pipeline-config.md, constraint allows up to 30 |
| Feedback classification is wrong (design classified as implementation) | Default to `implementation` when ambiguous — safer, doesn't discard plan |
| Recovery weight assignments are wrong | Weights are in contract — easy to tune per-project if needed |
| Oscillation tolerance too generous (allows bad code through) | Default 5 is conservative; projects can set to 0 for strict mode |

---

## Post-Implementation Addendum

The following additions were made during implementation that extend beyond the original spec:

### State Schema 1.2 → 1.3
The version-aware deprecation feature required a new `detected_versions` field in state.json, triggering a schema version bump from 1.2 to 1.3. Migration chain is now: 1.1 → 1.2 → 1.3.

### Version-Aware Deprecation Rules
- `known-deprecations.json` upgraded to schema v2 with `applies_from`, `removed_in`, `applies_to` fields
- PREFLIGHT detects project dependency versions from manifest files, stores in `state.json.detected_versions`
- Deprecation-refresh agent gates rule severity based on project version (SKIP if below applies_from, WARNING if deprecated, CRITICAL if removed_in reached)
- Old projects with unknown versions get conservative default (all rules apply)

### Migration Auto-Detection (DETECT Phase)
- New Phase 0 (DETECT) in pl-160-migration-planner before AUDIT
- Auto-detects current version from manifests or `detected_versions`
- Queries Context7/registries for latest stable target
- Builds breaking change impact analysis
- Migration skill supports `/migration upgrade <lib>`, `/migration upgrade all`, `/migration check`

### Module Conventions Enhancement
- All 12 module `conventions.md` files extended with Dos/Don'ts sections and framework-specific best practices (627 lines total)
- Coverage: error handling, state management, async patterns, performance, testing, accessibility, memory safety, observability (module-appropriate)

### Additional Orchestration Hardening (Cycle 2+)
- Worktree merge conflict detection (dry-merge before actual merge)
- Checkpoint corruption 5-stage recovery fallback
- Linear mid-run failure resilience (retry once, then degrade)
- Concurrent pipeline run lock (.pipeline/.lock)
- Multi-module failure isolation (FAILED/BLOCKED states)
- PREEMPT confidence decay formula with false-positive acceleration
- DOCS stage large-change guidance (>15 files threshold)
- Pipeline skills updated (pipeline-status, pipeline-reset, pipeline-rollback)
