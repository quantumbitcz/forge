# Quality Scoring Reference

This document defines the canonical quality scoring formula, verdict thresholds, finding format, and deduplication rules used by all review agents across all projects.

## Scoring Formula

```
score = max(0, 100 - 20 * CRITICAL - 5 * WARNING - 2 * INFO)
```

Every pipeline run starts at 100. Each finding deducts points based on its severity. The score cannot go below 0.

**Exception:** `SCOUT-*` findings (Boy Scout improvements) are excluded from the scoring formula. They are tracked for reporting and recap purposes only — they represent improvements made, not problems found.

| Severity | Point Deduction | Meaning |
|----------|----------------|---------|
| CRITICAL | -20 | Architectural violation, security flaw, data loss risk, broken contract |
| WARNING  | -5  | Convention violation, missing test coverage, suboptimal pattern |
| INFO     | -2  | Style nit, minor improvement opportunity, documentation gap |

### Examples

| Findings | Score | Verdict |
|----------|-------|---------|
| 0 CRITICAL, 0 WARNING, 0 INFO | 100 | PASS |
| 0 CRITICAL, 2 WARNING, 3 INFO | 84 | PASS |
| 0 CRITICAL, 4 WARNING, 0 INFO | 80 | PASS |
| 0 CRITICAL, 4 WARNING, 1 INFO | 78 | CONCERNS |
| 0 CRITICAL, 8 WARNING, 0 INFO | 60 | CONCERNS |
| 0 CRITICAL, 8 WARNING, 1 INFO | 58 | FAIL |
| 1 CRITICAL, 0 WARNING, 0 INFO | 80 | FAIL (CRITICAL present) |

## Scoring Customization

The default formula and thresholds can be overridden per-project in `forge-config.md`:

    scoring:
      critical_weight: 20
      warning_weight: 5
      info_weight: 2
      pass_threshold: 80
      concerns_threshold: 60

### Resolution Order

1. `forge-config.md` scoring values (if present)
2. Plugin defaults (the values in this document)

### Constraints

These constraints are enforced at PREFLIGHT. If violated, log WARNING and use plugin defaults:

- `critical_weight` must be >= 10 (CRITICALs are always serious)
- `warning_weight` must be >= 1 (WARNINGs cannot be fully suppressed)
- `warning_weight` must be > `info_weight` (WARNINGs must be strictly more impactful than INFOs)
- `info_weight` must be >= 0 (INFOs can be zero-weighted but not negative)
- `pass_threshold` must be >= 60 (below 60 is always FAIL)
- `concerns_threshold` must be < `pass_threshold`
- `concerns_threshold` must be >= 40
- `pass_threshold - concerns_threshold` must be >= 10 (ensure distinct verdict bands — prevents overlap where a score falls into both PASS and CONCERNS)
- `oscillation_tolerance` must be >= 0 and <= 20
- `convergence.max_iterations` must be >= 3 and <= 20 (below 3 defeats convergence; above 20 is runaway)
- `convergence.plateau_threshold` must be >= 0 and <= 10 (0 = any improvement counts; 10 = very loose)
- `convergence.plateau_patience` must be >= 1 and <= 5 (1 = stop at first plateau; 5 = very patient)
- `convergence.target_score` must be >= `pass_threshold` and <= 100 (cannot target below the pass bar)

**Verdict band derivation:** When thresholds are customized, verdict bands adjust automatically:
- PASS: score >= `pass_threshold` AND 0 CRITICALs remaining after all fix cycles
- CONCERNS: score >= `concerns_threshold` AND score < `pass_threshold` AND 0 CRITICALs remaining after all fix cycles
- FAIL: score < `concerns_threshold` OR any CRITICAL remaining after convergence exhaustion (plateau + max_iterations)

Note: CRITICALs trigger fix cycles (per Aim-for-Target policy) before determining the final verdict. A CRITICAL in cycle 1 does NOT immediately produce FAIL — it is sent to the implementer for fixing first.

### When to Customize

- **Stricter** (raise weights/thresholds): regulated industries, production-critical systems, shared libraries
- **Looser** (lower weights/thresholds): prototypes, internal tools, early-stage startups
- **Default works for most projects.** Only customize if the default scoring is causing false gates (blocking good code) or false passes (allowing bad code).

## Confidence-Weighted Scoring

When findings include a confidence field (`confidence:HIGH`, `confidence:MEDIUM`, `confidence:LOW`), the scoring formula applies a confidence multiplier:

    deduction = severity_weight * confidence_multiplier

| Confidence | Multiplier | Effect |
|------------|-----------|--------|
| `HIGH` | 1.0 | Full deduction (default when confidence omitted) |
| `MEDIUM` | 0.75 | 75% deduction (reviewer likely correct but acknowledges uncertainty) |
| `LOW` | 0.5 | Half deduction (reviewer uncertain) |

MEDIUM findings are less certain than HIGH and carry reduced scoring weight. A MEDIUM CRITICAL costs 15 points (20 x 0.75) instead of 20. This creates meaningful differentiation between the three confidence tiers rather than collapsing HIGH and MEDIUM into a single effective tier.

**Rounding rule:** Fractional deductions from confidence multipliers are rounded to the nearest integer (standard rounding: 0.5 rounds up). This prevents accumulation of fractional points across many findings.

### Example

| Finding | Severity | Confidence | Raw Deduction | Weighted Deduction |
|---------|----------|-----------|--------------|-------------------|
| SEC-AUTH-001 | CRITICAL | HIGH | -20 | -20 |
| ARCH-LAYER-002 | WARNING | MEDIUM | -5 | -4 (5 x 0.75 = 3.75, rounded to 4) |
| QUAL-NAME-003 | INFO | LOW | -2 | -1 |

Score: `100 - 20 - 4 - 1 = 75` (vs. `100 - 20 - 5 - 2 = 73` without confidence weighting)

### Confidence Field

Every finding MUST include a confidence level (HIGH, MEDIUM, LOW). Findings without confidence are logged as `COMPRESSION_DRIFT` by the quality gate and returned to the emitting reviewer for correction.

Weight multipliers:
- HIGH (1.0x): Strong evidence — deterministic check, clear violation
- MEDIUM (0.75x): Likely issue — heuristic match, pattern-based
- LOW (0.5x): Possible issue — uncertain, context-dependent

LOW-confidence findings are flagged for human review, NOT auto-dispatched to implementer. Included in stage notes and recap but excluded from fix cycles.

### Routing by Confidence

The quality gate uses confidence for dispatch routing:
- **HIGH/MEDIUM findings:** Auto-dispatched to implementer for fixing
- **LOW findings:** Flagged for human review, NOT auto-dispatched to implementer. Included in stage notes and recap but excluded from fix cycles.

The `decision_quality.findings_with_low_confidence` counter in `state.json` tracks LOW-confidence findings per run, feeding into the retrospective's reviewer accuracy analysis.

### Confidence Promotion

When 2+ reviewers independently report the same finding (same file, same line range, overlapping category), promote the finding's confidence:
- Both MEDIUM → HIGH
- One HIGH + one MEDIUM → HIGH
- Both LOW → MEDIUM
- One LOW + one MEDIUM → MEDIUM

Quality gate (fg-400) applies promotion during deduplication. See also agent-defaults.md §Confidence Reporting.

## Verdict Thresholds

| Verdict | Condition | Pipeline Action |
|---------|-----------|----------------|
| **PASS** | score >= 80 AND 0 CRITICALs | Proceed to next stage |
| **CONCERNS** | score 60-79 AND 0 CRITICALs | Proceed, but send ALL findings to implementer for fixing. The pipeline continues, but improvements are expected. |
| **FAIL** | score < 60 OR any CRITICAL remaining after convergence exhaustion | Escalate to user. Pipeline pauses until user decides. |

### Aim-for-Target Policy

Regardless of the verdict, every review cycle returns ALL findings -- not just CRITICALs. The quality gate dispatches the implementer to fix as many as possible, then rescores. This repeats up to `quality_gate.max_review_cycles` times.

The goal is always the configured `target_score` (default 90, max 100). Even when the verdict is CONCERNS and the pipeline proceeds, the full finding list is preserved in stage notes for the retrospective to analyze.

### INFO Efficiency Policy

During convergence Phase 2 (perfection), INFO findings follow "fix if easy, skip if costly":

1. On first iteration: attempt to fix ALL findings (including INFO)
2. On subsequent iterations: if an INFO finding was present in the previous cycle and the implementer did not fix it, mark it as `unfixable_info` in convergence state
3. Unfixable INFO findings are excluded from the convergence target calculation:
   `effective_target = max(pass_threshold, min(target_score, 100 - 2 * unfixable_info_count))`
   The `max(pass_threshold, ...)` floor ensures the effective target never drops below the passing
   threshold, preventing scenarios where many persistent INFOs could lower the bar to unacceptable levels.
   This matches the canonical formula in `convergence-engine.md`.
4. The pipeline converges when `score >= effective_target` (not raw `target_score`)

This prevents the pipeline from spending 3-4 iterations to squeeze out the last 2-3 INFO fixes when the score is already above pass_threshold.

## Finding Format

Every review agent (module-specific reviewers, inline checks, quality gate batches) must return findings in this exact format:

```
file:line | category | severity | description | suggested fix
```

| Field | Description | Example |
|-------|-------------|---------|
| `file` | Relative path from project root | `core/domain/plan/PlanComment.kt` |
| `line` | Line number (0 if file-level) | `42` |
| `category` | Finding category code (see below) | `HEX-BOUNDARY` |
| `severity` | One of: `CRITICAL`, `WARNING`, `INFO` | `WARNING` |
| `description` | What is wrong and why it matters | `Core imports adapter type, violating dependency rule` |
| `suggested fix` | Concrete action to resolve | `Move mapping to adapter layer, use port interface in core` |

### Category Codes

> **Authoritative source:** See `shared/checks/category-registry.json` for the canonical list of all category codes, their emitting agents, and conflict resolution priorities. When adding a new category, update the registry first, then update this document.

Categories are defined per module in `conventions.md`. Common shared categories:

| Code | Meaning |
|------|---------|
| `ARCH-*` | Architectural violation (SRP, DIP, layer boundary) |
| `SEC-*` | Security concern (auth, injection, exposure) |
| `SEC-SECRET` | Secret or credential in source code or pipeline artifact |
| `SEC-PII` | Potential PII detected (email, phone — verify manually) |
| `SEC-REDACT` | Value auto-redacted from pipeline artifact |
| `PERF-*` | Backend performance issue (N+1, O(n^2), blocking I/O, unnecessary allocation) |
| `FE-PERF-*` | Frontend performance issue (re-renders, bundle size, DOM efficiency, assets) |
| `TEST-*` | Test quality (missing coverage, testing framework behavior, mock-only tests, weak assertions, edge case gaps, isolation). Subcategories: `TEST-MOCK-ONLY`, `TEST-EDGE-MISSING`, `TEST-ASSERT-WEAK`, `TEST-ISOLATION`. Emitted by `fg-410-code-reviewer`. |
| `TEST-MUTATION-SURVIVE` | Mutant survived — test didn't detect the change (mutation testing) |
| `TEST-MUTATION-TIMEOUT` | Mutant caused test timeout — likely meaningful (mutation testing) |
| `TEST-MUTATION-EQUIVALENT` | Mutant is functionally equivalent — not a test gap (mutation testing) |
| `CONV-*` | Convention violation (naming, style, patterns) |
| `DOC-*` | Documentation gap (missing KDoc/TSDoc, unclear intent) |
| `QUAL-*` | Code quality (complexity, duplication, dead code, error handling, defensive programming, plan alignment, naming). Subcategories: `QUAL-ERR-*` (error handling), `QUAL-DRY-*` (duplication), `QUAL-DEF-*` (defensive programming), `QUAL-PLAN-*` (plan alignment), `QUAL-NAME` (naming), `QUAL-COMPLEX` (complexity), `QUAL-MAGIC` (magic values), `QUAL-LENGTH` (function length), `QUAL-KISS-*` (over-engineering). Emitted by `fg-410-code-reviewer`. |
| `REFLECT-*` | Implementer-judge (fg-301) reflection findings — implementation diff does not satisfy the intent of the tests. Subcategories: `REFLECT-DIVERGENCE`, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, `REFLECT-MISSING-BRANCH`. Emitted by `fg-301-implementer-judge` during TDD GREEN→REFACTOR transition (Chain-of-Verification). |
| `APPROACH-*` | Solution quality (suboptimal pattern, unnecessary complexity, missed simplification) |
| `SCOUT-*` | Boy Scout improvement (tracked, no point deduction). Cleanup improvement made while modifying code — removed unused imports, renamed variables, extracted helpers |
| `EVAL-*` | see `shared/checks/eval-categories.md` | excluded from pipeline scoring (harness-only) |

Additional category codes for specialized review domains:

| Code | Meaning |
|------|---------|
| `A11Y-*` | Accessibility violation (WCAG compliance, keyboard nav, screen reader, ARIA) |
| `DEP-*` | Dependency health (vulnerable, unmaintained, outdated, conflicting versions, license compliance). Subcategories: `DEP-CVE-*` (vulnerabilities), `DEP-OUTDATED-*` (outdated), `DEP-UNMAINTAINED` / `DEP-DEPRECATED` (maintenance), `DEP-CONFLICT-*` (version conflicts), `DEP-LICENSE-*` (license compliance). Emitted by `fg-417-dependency-reviewer`. |
| `COMPAT-*` | Compatibility issue (browser, platform, API version, backward compatibility). Reserved — currently `fg-417-dependency-reviewer` uses `QUAL-COMPAT`. `COMPAT-*` may be activated for browser/platform-specific compatibility. |
| `CONTRACT-*` | Contract validation findings from `fg-250-contract-validator` — subcategories: `CONTRACT-BREAK` (CRITICAL: breaking API change — removed endpoint, changed type, removed field), `CONTRACT-CHANGE` (WARNING: non-breaking but impactful change — new required field, enum change), `CONTRACT-ADD` (INFO: additive change or skip notice — new endpoint, new optional field) |
| `REVIEW-GAP` | Coverage gap from timed-out or failed review agent (see Partial Failure Handling) |
| `DESIGN-TOKEN` | Frontend design token violation (hardcoded hex/rgb instead of theme tokens) |
| `DESIGN-MOTION` | Frontend animation performance issue (non-GPU-accelerated properties, missing will-change) |
| `STRUCT-*` | Project structure violation — subcategories: `STRUCT-PLACE` (file in wrong directory/package), `STRUCT-NAME` (file/class naming convention violation), `STRUCT-BOUNDARY` (cross-layer import not caught by ARCH-BOUNDARY — emitted by Layer 1 check engine patterns), `STRUCT-MISSING` (required directory or file missing from expected structure) |
| `INFRA-*` | Infrastructure/deployment issue — subcategories: `INFRA-SEC` (security), `INFRA-REL` (reliability), `INFRA-SCA` (scalability), `INFRA-OBS` (observability), `INFRA-DOC` (Docker), `INFRA-HLM` (Helm), `INFRA-TF` (Terraform) |

Specific INFRA finding codes for tiered infra verification:

| Code | Meaning | Default Severity |
|------|---------|-----------------|
| `INFRA-HEALTH` | Pod/service health check failure | CRITICAL |
| `INFRA-SMOKE` | Smoke test failure (connectivity, DNS, config) | WARNING |
| `INFRA-CONTRACT` | Contract schema/routing validation failure | CRITICAL |
| `INFRA-E2E` | Full stack integration test failure | CRITICAL |
| `INFRA-IMAGE` | Image resolution failure (pull/build) | WARNING (auto fallback) / CRITICAL (explicit mode) |

Additional category codes for visual verification:

| Code | Meaning |
|------|---------|
| `FE-VISUAL-REGRESSION` | Unexpected visual change detected (layout shift, element missing) |
| `FE-VISUAL-RESPONSIVE` | Layout breaks at specific viewport breakpoint |
| `FE-VISUAL-CONTRAST` | Text contrast ratio below WCAG AA threshold |
| `FE-VISUAL-FIDELITY` | Visual output deviates from design specification |

Additional category codes for AI-aware code quality (v2.5.0):

| Code | Meaning |
|------|---------|
| `AI-LOGIC-*` | AI-generated logic bug (null handling, boundary, condition, type coercion, return, state, async, edge case). Assigned to `fg-410-code-reviewer`. |
| `AI-PERF-*` | AI-generated performance bug (N+1, excessive I/O, memory leak, quadratic, redundant render, blocking, bundle). Assigned to `fg-416-performance-reviewer`. |
| `AI-CONCURRENCY-*` | AI-generated concurrency bug (race condition, deadlock, atomicity, starvation, lost update). Assigned to `fg-410-code-reviewer` + `fg-416-performance-reviewer`. |
| `AI-SEC-*` | AI-generated security bug (injection, hardcoded secret, insecure default, missing auth, verbose error, deserialization). Assigned to `fg-411-security-reviewer`. |

See `shared/checks/ai-code-patterns.md` for full reference of all 26 discrete sub-categories with detection strategies and fix patterns.

Module-specific categories (e.g., `HEX-*` for spring, `THEME-*` for react) are defined in each module's `conventions.md`. Layer-1 pattern files may define additional category codes (e.g., `INFRA-BEST`, `INFRA-SCALE`, `INFRA-SIZE`, `INFRA-TAG` for container/infra patterns). Projects may define additional project-specific categories in their `conventions.md`.

**APPROACH-* accumulation rule:** APPROACH-* findings accumulate across runs. If the same APPROACH finding recurs 3+ times, the retrospective escalates it to a convention rule. "Same finding" is identified by matching on `(category, description_hash)` where `description_hash` is the first 8 characters of SHA256 of the normalized description (lowercase, trimmed). Accumulation is tracked in `forge-log.md` under the `approach_accumulations` section, updated by `fg-700-retrospective` at the end of each run.

### DOC-* Findings (Documentation Consistency)

Reported by `fg-418-docs-consistency-reviewer` during REVIEW stage.

| Category | Severity | Deduction | Description |
|----------|----------|-----------|-------------|
| `DOC-DECISION-*` | CRITICAL (HIGH confidence) / WARNING (MEDIUM) | -20 / -5 | Code violates a documented architectural decision |
| `DOC-CONSTRAINT-*` | CRITICAL (HIGH confidence) / WARNING (MEDIUM) | -20 / -5 | Code violates a documented constraint |
| `DOC-STALE-*` | WARNING | -5 | Documentation section describes changed files but is no longer accurate |
| `DOC-MISSING-*` | INFO | -2 | New public API or module has no documentation coverage |
| `DOC-DIAGRAM-*` | INFO | -2 | Diagram covers changed packages and may need update |
| `DOC-CROSSREF-*` | WARNING | -5 | Two documentation sections describe the same entity with contradictory content |

**LOW confidence handling:** Decisions and constraints with `confidence: LOW` appear as `SCOUT-DOC-*` findings (no score deduction). They are informational only until confidence is upgraded to MEDIUM or HIGH.

## Deduplication Rules

After all review batches and inline checks complete, findings are deduplicated before scoring.

### Deduplication Key

Findings are grouped by the tuple `(file, line, category)`. In multi-component projects, the deduplication key is `(component, file, line, category)` — the same issue in different components represents separate fixes and is not deduplicated. When multiple findings share the same key:

1. **Keep the highest severity.** If one agent reports WARNING and another reports CRITICAL for the same location and category, the CRITICAL survives.
2. **Preserve the most detailed description.** Among findings with the same key, keep the one with the longest description (it is likely the most actionable).
3. **Merge suggested fixes.** If different agents suggest complementary fixes, concatenate them. If they conflict, keep the fix from the highest-severity finding.

### Deduplication Process

```
1. Collect all findings from all batch agents + inline checks
2. Group by (component, file, line, category)
   — For single-component projects, component is omitted (equivalent to a constant)
3. For each group:
   a. Select finding with highest severity
   b. If tie: select finding with longest description
   c. Discard others in group
4. Score the deduplicated set
```

### Cross-File Deduplication

Findings at different lines in the same file with the same category are NOT deduplicated -- they represent distinct issues. Only exact `(component, file, line, category)` matches are grouped.

### SCOUT-* Finding Handling

`SCOUT-*` findings are **tracked separately** from non-SCOUT findings and are **never scored**. During deduplication:
- `SCOUT-*` findings are excluded from the dedup pass entirely — they are not compared against non-SCOUT findings.
- If an agent reports both a `SCOUT-IMPORT-UNUSED` and a regular `QUAL-IMPORT-UNUSED` for the same location, **both are kept**: the SCOUT version for the recap, the non-SCOUT version for scoring.
- SCOUT findings are passed through to `fg-710-post-run` and `fg-700-retrospective` for reporting but are **filtered out** before dispatch to `fg-300-implementer` (no action required — the improvement was already made).

### REFLECT-* Finding Handling

`REFLECT-*` findings are emitted by `fg-301-implementer-judge` during the per-task
reflection loop inside fg-300 (§5.3a). They are NOT SCOUT-class — they count
toward the score.

Normally, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, and `REFLECT-MISSING-BRANCH`
are resolved in-loop (implementer re-enters GREEN) and never reach Stage 6.
They surface to Stage 6 only when the reflection budget is exhausted — at that
point `REFLECT-DIVERGENCE` (WARNING, -5) is emitted on the task and the per-cycle
subtype findings are NOT re-surfaced (no double-counting). Reviewers at Stage 6
independently re-examine the code; they do not read `REFLECT-*` findings as prior art.

Dedup: standard `(component, file, line, category)` key.

### Cross-Category Deduplication for AI-* Overlap

Several AI-* categories detect the same bugs as existing categories (e.g., `AI-SEC-INJECTION` vs `SEC-INJECTION`, `AI-SEC-HARDCODED-SECRET` vs `SEC-SECRET`). Without special handling, both findings would survive standard deduplication (different categories at the same file:line) and double-penalize the score.

**Resolution:** After initial dedup by `(component, file, line, category)`, run a second pass: when two findings share the same `(file, line)` and one category is `AI-X-Y` while the other is `X-Y` (prefix match after removing `AI-`), treat them as the same finding for scoring purposes. Keep:
- The **highest severity** finding
- The **AI-* category** (more specific root cause metadata)
- The **longer description** (if descriptions differ)

This prevents double-counting while preserving the more specific AI-* root cause information for the learning pipeline. L1 patterns can also declare `exclude_if_existing` to suppress AI-* findings when the non-AI category already matched at the same location.

## Partial Failure Handling

If a review agent times out or fails to return results:

1. **Score with available results.** Do not wait indefinitely or fail the entire review.
2. **Note the coverage gap.** Add an INFO-level finding: `<agent-name> | REVIEW-GAP | INFO | Agent timed out, {focus area} not reviewed | Re-run review or inspect manually`.
3. **Log in stage notes.** Record which agent failed and what it was supposed to cover.
4. **Do not lower the score** for the gap itself (the INFO finding costs -2, which is appropriate). The concern is missing coverage, not a quality problem in the code.
5. **If a CRITICAL-focused agent fails** (e.g., security reviewer): the quality gate should flag this to the orchestrator as a coverage risk, allowing it to decide whether to re-dispatch or escalate.
6. **Critical-domain gap severity upgrade.** If the timed-out agent covers a CRITICAL-focused domain, use WARNING severity (-5 points) instead of INFO (-2 points) for the coverage gap finding: `{agent}:0 | REVIEW-GAP | WARNING | Critical-domain agent timed out, {focus} not reviewed | Re-run review or inspect manually`. A domain is "critical-focused" if the agent's `focus` field in batch config contains any of: "security", "auth", "injection", "architecture", "boundary", "SRP", "DIP", "performance", "scalability", "version", "compat", "dependency", "infra".

## Review Cycle Flow

> **Note:** This describes the quality gate's inner cycle per convergence iteration. The outer convergence loop is managed by `shared/convergence-engine.md`.

```
1. Dispatch all batch agents (parallel within each batch, sequential across batches)
2. Run inline checks
3. Collect + deduplicate findings
4. Score
5. If score < 100 AND cycles_remaining > 0:
   a. Send ALL findings to implementer
   b. Implementer fixes what it can
   c. Increment quality_cycles counter
   d. Go to step 1
6. Determine verdict from final score
7. Return verdict + full finding list + score history
```

The score history (score per cycle) is included in the quality gate report so the retrospective can track improvement trends across runs.

## Score Oscillation Handling

> **Note:** Two complementary oscillation mechanisms exist. (1) The **convergence engine's REGRESSING state** (see `shared/convergence-engine.md`) detects score dips **across** convergence iterations — if `delta < 0` and `abs(delta) > oscillation_tolerance`, the engine transitions to REGRESSING and escalates. (2) The **Consecutive Dip Rule below** operates **within** a single convergence iteration's quality gate cycles — if two consecutive inner cycles show score dips, the quality gate escalates within that iteration. Both mechanisms are active by default and are complementary, not redundant.

Track `score_history[]` in `state.json` across quality cycles. Initialized as `[]` at PREFLIGHT. After each cycle's score is computed, append it to the array FIRST, then run the oscillation check:

1. If `score_history` has < 2 entries: no oscillation check possible, continue
2. Compute `delta = current_score - previous_score`
3. If `delta >= 0`: improvement or stable — continue normally
4. If `delta < 0` and `abs(delta) <= oscillation_tolerance` (default: 5): minor regression — allow one more cycle, log WARNING: "Score dipped {abs(delta)} points ({previous} → {current}). Within tolerance. Continuing."
5. If `delta < 0` and `abs(delta) > oscillation_tolerance`: significant regression — escalate to user: "Quality regression: {previous} → {current} (delta: {delta}, tolerance: {oscillation_tolerance}). Fix cycle may be introducing new issues."

### Consecutive Dip Rule

Track dip count across cycles. A "dip" is any cycle where `delta < 0`. If a second consecutive dip occurs (even within tolerance), escalate immediately — do not allow a third cycle. This prevents oscillating fixes from consuming unlimited cycles.

- First dip within tolerance: allow one more cycle (per rule 4 above)
- Second consecutive dip (regardless of magnitude): escalate to user
- A non-dip cycle (delta >= 0) resets the dip counter to 0

### Per-Component Oscillation Tracking

In multi-component projects, the quality gate tracks score history per component in addition to the unified score. If any single component shows two consecutive score dips while the unified score appears stable or improving, the quality gate logs a WARNING:

> "Component '{name}' shows regression ({previous} → {current}) masked by improvements in other components. Investigating component-specific oscillation."

This prevents a scenario where one component steadily regresses while another improves, masking the regression in the unified score. The unified oscillation rules still apply to the aggregate score.

**Interaction with max_review_cycles:** Oscillation checks run BEFORE the max_review_cycles guard. Priority order:
1. If a second consecutive dip is detected AND `quality_cycles < max_review_cycles`: escalate immediately (oscillation overrides remaining cycles)
2. If `quality_cycles >= max_review_cycles`: end the run regardless of oscillation state (hard stop)
3. If both conditions are true simultaneously (second dip occurs on the final cycle): end the run — do not trigger a separate escalation, since the max-cycles message already communicates the situation

### Oscillation Tolerance Configuration

Configurable in `forge-config.md`:

    scoring:
      oscillation_tolerance: 5

Constraint: `oscillation_tolerance` must be >= 0 and <= 20. If violated, log WARNING and use default (5).

## Time Limits

Each review cycle should complete within 10 minutes. If a review agent exceeds 10 minutes, treat as timeout per the partial failure handling rules.

**Judge timeout semantics.** fg-205-plan-judge and fg-301-implementer-judge reuse the same 10-minute ceiling. On timeout, log INFO `JUDGE-TIMEOUT` finding (category added in Phase 5), treat verdict as PROCEED, and emit a WARNING `JUDGE-TIMEOUT` finding into the scoring set. The pipeline never blocks on judge failure.

## Findings Cap

If any single agent returns >100 raw findings, it should return only the top 100 by severity with a note: "{N} additional findings below threshold — truncated for context budget."

After deduplication, if the quality gate has >50 unique findings, it returns the top 50 by severity in its report with a total count note.

## Score Sub-Bands (Operational Guidance)

These sub-bands provide granularity for documentation and reporting. When Linear is integrated, findings are posted as Linear issues. When Linear is unavailable, findings are documented in stage notes and the retrospective report. Sub-bands do NOT change the PASS/CONCERNS/FAIL verdict thresholds.

| Score Band | Verdict | Documentation |
|---|---|---|
| 95-99 | PASS | Remaining INFOs documented. No follow-up tickets. |
| 80-94 | PASS | Each unfixed WARNING documented with options. Architectural WARNINGs get follow-up tickets. |
| 60-79 | CONCERNS | Full findings posted. User asked for guidance via escalation format. |
| < 60 | FAIL | Recommend abort or replan. Architectural root cause analysis posted. |

## Examples

See `convergence-examples.md` for worked scoring calculations in context.

## See Also

- `shared/convergence-engine.md` — Uses score history for IMPROVING/PLATEAUED/REGRESSING detection
- `shared/checks/category-registry.json` — Master list of 87 scoring categories (27 wildcard + 60 discrete)
- `shared/agent-communication.md` — Finding format validation and deduplication rules
- `shared/confidence-scoring.md` — Finding confidence weights (HIGH=1.0x, MEDIUM=0.75x, LOW=0.5x)
- `shared/state-schema.md` — `score_history` and `convergence` state fields
