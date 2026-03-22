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

## Verdict Thresholds

| Verdict | Condition | Pipeline Action |
|---------|-----------|----------------|
| **PASS** | score >= 80 AND 0 CRITICALs | Proceed to next stage |
| **CONCERNS** | score 60-79 AND 0 CRITICALs | Proceed, but send ALL findings to implementer for fixing. The pipeline continues, but improvements are expected. |
| **FAIL** | score < 60 OR any CRITICAL remaining after max review cycles | Escalate to user. Pipeline pauses until user decides. |

### Aim-for-100 Policy

Regardless of the verdict, every review cycle returns ALL findings -- not just CRITICALs. The quality gate dispatches the implementer to fix as many as possible, then rescores. This repeats up to `quality_gate.max_review_cycles` times.

The goal is always a score of 100. Even when the verdict is CONCERNS and the pipeline proceeds, the full finding list is preserved in stage notes for the retrospective to analyze.

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

Categories are defined per module in `conventions.md`. Common shared categories:

| Code | Meaning |
|------|---------|
| `ARCH-*` | Architectural violation (SRP, DIP, layer boundary) |
| `SEC-*` | Security concern (auth, injection, exposure) |
| `PERF-*` | Performance issue (N+1, O(n^2), unnecessary allocation) |
| `TEST-*` | Test quality (missing coverage, testing framework behavior) |
| `CONV-*` | Convention violation (naming, style, patterns) |
| `DOC-*` | Documentation gap (missing KDoc/TSDoc, unclear intent) |
| `QUAL-*` | Code quality (complexity, duplication, dead code) |
| `FE-PERF-*` | Frontend performance issue (bundle size, unnecessary re-renders, unoptimized assets) |
| `SCOUT-*` | Boy Scout improvement (tracked, no point deduction). Cleanup improvement made while modifying code — removed unused imports, renamed variables, extracted helpers |

Module-specific categories (e.g., `HEX-*` for kotlin-spring, `THEME-*` for react-vite) are defined in each module's `conventions.md`.

## Deduplication Rules

After all review batches and inline checks complete, findings are deduplicated before scoring.

### Deduplication Key

Findings are grouped by the tuple `(file, line, category)`. When multiple findings share the same key:

1. **Keep the highest severity.** If one agent reports WARNING and another reports CRITICAL for the same location and category, the CRITICAL survives.
2. **Preserve the most detailed description.** Among findings with the same key, keep the one with the longest description (it is likely the most actionable).
3. **Merge suggested fixes.** If different agents suggest complementary fixes, concatenate them. If they conflict, keep the fix from the highest-severity finding.

### Deduplication Process

```
1. Collect all findings from all batch agents + inline checks
2. Group by (file, line, category)
3. For each group:
   a. Select finding with highest severity
   b. If tie: select finding with longest description
   c. Discard others in group
4. Score the deduplicated set
```

### Cross-File Deduplication

Findings at different lines in the same file with the same category are NOT deduplicated -- they represent distinct issues. Only exact `(file, line, category)` matches are grouped.

## Partial Failure Handling

If a review agent times out or fails to return results:

1. **Score with available results.** Do not wait indefinitely or fail the entire review.
2. **Note the coverage gap.** Add an INFO-level finding: `<agent-name> | REVIEW-GAP | INFO | Agent timed out, {focus area} not reviewed | Re-run review or inspect manually`.
3. **Log in stage notes.** Record which agent failed and what it was supposed to cover.
4. **Do not lower the score** for the gap itself (the INFO finding costs -2, which is appropriate). The concern is missing coverage, not a quality problem in the code.
5. **If a CRITICAL-focused agent fails** (e.g., security reviewer): the quality gate should flag this to the orchestrator as a coverage risk, allowing it to decide whether to re-dispatch or escalate.

## Review Cycle Flow

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

## Time Limits

Each review cycle should complete within 10 minutes. If a review agent exceeds 10 minutes, treat as timeout per the partial failure handling rules.

## Findings Cap

If any single agent returns >100 raw findings, it should return only the top 100 by severity with a note: "{N} additional findings below threshold — truncated for context budget."

After deduplication, if the quality gate has >50 unique findings, it returns the top 50 by severity in its report with a total count note.

## Score Sub-Bands (Operational Guidance)

These sub-bands provide granularity for Linear documentation. They do NOT change the PASS/CONCERNS/FAIL verdict thresholds.

| Score Band | Verdict | Linear Documentation |
|---|---|---|
| 95-99 | PASS | Remaining INFOs documented. No follow-up tickets. |
| 80-94 | PASS | Each unfixed WARNING documented with options. Architectural WARNINGs get follow-up tickets. |
| 60-79 | CONCERNS | Full findings posted. User asked for guidance via escalation format. |
| < 60 | FAIL | Recommend abort or replan. Architectural root cause analysis posted. |
