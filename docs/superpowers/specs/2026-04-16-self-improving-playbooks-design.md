# Spec 3: Self-Improving Playbooks

**Status:** Approved
**Author:** Denis Sajnar
**Date:** 2026-04-16
**Depends on:** Spec 2 (Run History Store), Spec 1 (MCP Server — for analytics exposure)

---

## Problem

Forge playbooks are static recipes. A developer writes `add-rest-endpoint.md` with stages, scoring, acceptance criteria, and parameter defaults — and it never evolves. If every run of a playbook hits the same `TEST-COVERAGE` findings, nobody adds a preventive acceptance criterion. If a parameter is always set to the same value, nobody updates the default. The retrospective already tracks playbook usage in `playbook-analytics.json`, but that data is observational — it never feeds back into the playbook itself.

Hermes Agent's key insight: procedural memory (skills) should self-improve based on execution outcomes. We adapt this pattern for Forge playbooks — after each run, the retrospective analyzes outcomes and proposes refinements that push the playbook toward consistently producing near-perfect code.

## Solution

Extend `fg-700-retrospective` to analyze playbook runs and emit **refinement proposals** — concrete, evidence-backed suggestions for improving the playbook. Proposals accumulate in `run-history.db` (Spec 2) and `.forge/playbook-refinements/`. When enough evidence supports a proposal (3+ runs agreeing), it becomes actionable.

The philosophy: **make the code meet the bar, never move the bar to meet the code.** Refinements always push quality up — adding preventive criteria, fixing blind spots, improving focus — never lowering thresholds.

## Non-Goals

- **Not rewriting playbooks from scratch** — refinements are incremental adjustments, not wholesale replacements.
- **Not creating playbooks automatically** — playbook creation stays manual or via `fg-710-post-run` suggestion. This spec improves existing playbooks.
- **Not lowering quality bars** — no `pass_threshold` reductions, no `category_overrides` to suppress findings, no severity downgrades.

## Refinement Categories (4 types)

### 1. Scoring Gap Remediation

When a playbook's runs consistently miss the quality target, analyze **why** and add preventive measures.

**Trigger:** Playbook's last 3+ runs average score < `pass_threshold`

**Analysis:**
1. Group all findings from those runs by category
2. Identify top categories causing point deductions
3. For each top category:
   - If no acceptance criterion covers it → propose adding one
   - If PREEMPT item exists but wasn't applied → propose adding to playbook's PREEMPT list
   - If the issue is domain-specific → propose adding domain-targeted review focus

**Example:**
> Runs of `add-rest-endpoint` average 78 (threshold 85). Top deductions: `TEST-COVERAGE` (-10pts across 3 runs), `SEC-INPUT-VALIDATION` (-6pts across 2 runs).
>
> Proposal: Add acceptance criteria:
> - "Unit test coverage for new endpoint ≥80%"
> - "All request parameters validated with explicit type checks"

**Never proposed:** Lowering `pass_threshold`, adding `scoring.category_overrides`, suppressing categories.

### 2. Stage Focus Tuning

Optimize which stages the playbook focuses on based on where time and iterations are actually spent.

**Trigger:** Stage timing data shows consistent imbalance across 3+ runs

**Analysis:**
1. For each stage, compute average `duration_seconds` and `tokens_in + tokens_out` across playbook runs
2. If a stage not in playbook's `stages_focus` consistently takes >25% of total wall time → propose adding it
3. If a stage in `stages_focus` consistently takes <2% of total wall time across 3+ runs → propose removing it (but never VERIFYING, REVIEWING, or SHIPPING — per existing safety constraints)

**Example:**
> `add-rest-endpoint` focuses on `[IMPLEMENTING, REVIEWING]` but VERIFYING consistently takes 35% of wall time due to test failures.
>
> Proposal: Add VERIFYING to `stages_focus` to allocate more convergence budget to test fixes.

### 3. Acceptance Criteria Gaps

Close blind spots where the playbook has no criteria but findings consistently appear.

**Trigger:** A finding category appears in 2+ runs of the same playbook but no acceptance criterion covers it

**Analysis:**
1. Extract all finding categories from playbook runs
2. Map each to playbook's acceptance criteria (keyword matching on category + criterion text)
3. Unmatched categories with 2+ occurrences become gap candidates
4. Also detect acceptance criteria that have never been relevant (0 findings in their category across 3+ runs) — propose as potential noise

**Example:**
> `add-rest-endpoint` has no criterion about API documentation, but `DOC-API-SPEC` appears in 3/4 runs.
>
> Proposal: Add acceptance criterion: "OpenAPI spec updated with new endpoint schema"

> `add-rest-endpoint` has criterion "Database indexes reviewed" but 0 runs had `PERF-INDEX` findings.
>
> Proposal: Remove criterion "Database indexes reviewed" (noise — 0 findings in 4 runs). Consider if it should be a general PREEMPT instead.

### 4. Parameter Default Optimization

Tune parameter defaults based on actual usage patterns.

**Trigger:** 3+ runs of the same playbook with parameter data

**Analysis:**
1. For each parameter, collect values used across runs (from `playbook_runs.parameters`)
2. If a parameter has the same value in ≥80% of runs → propose making it the default
3. If a parameter is never changed from its current default → mark as "stable" (informational, no change proposed)

**Example:**
> `add-rest-endpoint` parameter `http_method` defaults to `GET` but 4/5 runs used `POST`.
>
> Proposal: Change default for `http_method` from `GET` to `POST`.

## Refinement Flow

### Per-Run (in `fg-700-retrospective`)

Added as a new step after the existing playbook analytics update:

```
IF state.json.playbook_id is set:
  1. Load playbook definition from project or built-in playbooks
  2. Load run data: score, findings, stage_timings, acceptance results
  3. Compute refinement suggestions:
     a. Scoring gap analysis (compare score vs threshold, find top deduction categories)
     b. Stage focus analysis (compare timing distribution vs stages_focus)
     c. Acceptance gap analysis (cross-reference findings vs criteria)
     d. Parameter analysis (compare used values vs defaults)
  4. Write suggestions to playbook_runs.refinement_suggestions in run-history.db
  5. Check: 3+ runs of this playbook in run-history.db?
     YES → Proceed to aggregation
     NO  → Log "Insufficient data for {playbook_id} refinement ({N}/3 runs). Skipping."
```

### Aggregation (3+ runs threshold)

```
  6. Load all refinement_suggestions for this playbook from run-history.db
  7. For each unique suggestion (grouped by type + target field):
     a. Count how many runs agree (contain the same or compatible suggestion)
     b. If agreement >= refine_agreement (default 66%) of runs:
        - Set confidence: HIGH if agreement >= 90%, MEDIUM if >= 66%
        - Mark proposal as "ready"
     c. If agreement < refine_agreement:
        - Mark proposal as "insufficient_evidence"
  8. Write ready proposals to .forge/playbook-refinements/{playbook_id}.json
  9. Log to forge-log.md: "[REFINE] {playbook_id}: {N} proposals ready ({types})"
```

## Refinement Proposal Schema

File: `.forge/playbook-refinements/{playbook_id}.json`

```json
{
  "playbook_id": "add-rest-endpoint",
  "playbook_version": "1.2.0",
  "generated_at": "2026-04-16T14:00:00Z",
  "based_on_runs": 5,
  "run_ids": ["run-2026-04-10-abc", "run-2026-04-12-def", "run-2026-04-14-ghi", "run-2026-04-15-jkl", "run-2026-04-16-mno"],
  "proposals": [
    {
      "id": "add-rest-endpoint-REF-001",
      "type": "scoring_gap",
      "description": "Add acceptance criterion for test coverage",
      "target": "acceptance_criteria",
      "current_value": null,
      "proposed_value": "Unit test coverage for new endpoint >= 80%",
      "evidence": "TEST-COVERAGE findings in 4/5 runs, causing avg -8 point deduction. No acceptance criterion covers this.",
      "confidence": "HIGH",
      "agreement": "4/5",
      "impact_estimate": "+6 to +10 points (eliminates TEST-COVERAGE findings proactively)"
    },
    {
      "id": "add-rest-endpoint-REF-002",
      "type": "stage_focus",
      "description": "Add VERIFYING to stages_focus",
      "target": "stages_focus",
      "current_value": ["IMPLEMENTING", "REVIEWING"],
      "proposed_value": ["IMPLEMENTING", "VERIFYING", "REVIEWING"],
      "evidence": "VERIFYING stage takes 32-40% of wall time across all 5 runs, but is not in stages_focus.",
      "confidence": "HIGH",
      "agreement": "5/5",
      "impact_estimate": "Faster convergence in VERIFYING stage (more iterations allocated)"
    },
    {
      "id": "add-rest-endpoint-REF-003",
      "type": "parameter_default",
      "description": "Change default http_method from GET to POST",
      "target": "parameters.http_method.default",
      "current_value": "GET",
      "proposed_value": "POST",
      "evidence": "4/5 runs used POST. Only 1 run used GET.",
      "confidence": "MEDIUM",
      "agreement": "4/5",
      "impact_estimate": "Convenience — saves parameter override in 80% of uses"
    }
  ]
}
```

## Application Modes

### Manual (default)

Refinement proposals are written to `.forge/playbook-refinements/`. The developer reviews them via:

1. **`forge-playbook-refine` skill** (new) — interactive review:
   ```
   /forge-playbook-refine add-rest-endpoint
   ```
   Shows proposals one by one with evidence. Developer accepts, rejects, or modifies each. Accepted proposals are applied to the playbook file, version is incremented.

2. **MCP server** — `forge_playbook_effectiveness` tool returns proposals in its response. Any AI client can read and present them.

### Auto-apply (opt-in)

With `playbooks.auto_refine: true` in `forge-config.md`:

At PREFLIGHT of the next run (in `fg-100-orchestrator`):
1. Check `.forge/playbook-refinements/{playbook_id}.json` for ready proposals
2. Filter to HIGH confidence only
3. Apply max `max_auto_refines_per_run` changes (default 2)
4. Increment playbook version in frontmatter
5. Log each change to `forge-log.md` with `[AUTO-REFINE]` marker
6. Store pre-refinement playbook version in `state.json` for rollback

**Auto-apply restrictions:**
- Only HIGH confidence proposals
- Max 2 per run (prevents cascading)
- Respects `<!-- locked -->` fences in playbook files
- Never touches `pass_threshold`, `concerns_threshold`, or scoring weights
- Never removes VERIFYING, REVIEWING, or SHIPPING stages
- **Only modifies project-level playbooks** in `.claude/forge-playbooks/`. If a built-in playbook (in `shared/playbooks/`) has refinement proposals, auto-apply first copies it to `.claude/forge-playbooks/` (creating a project override), then applies refinements to the project copy. The plugin directory is never modified.

### Rollback

If a refined playbook's next run scores >10 points lower than the pre-refinement average (computed from last 3 runs before refinement):

1. Revert the applied changes (restore previous playbook version from `playbook-analytics.json.version_history`)
2. Log `[REFINE-ROLLBACK]` to `forge-log.md` with reasoning
3. Mark the proposal as `rolled_back` in the refinement file
4. Increment `rollback_count` — proposals with 2+ rollbacks are permanently marked `rejected`

## Guard Rails

| Rule | Rationale |
|------|-----------|
| Never lower `pass_threshold` | We aim for near-perfect code |
| Never add `scoring.category_overrides` to suppress findings | Findings indicate real issues to fix |
| Never remove stages VERIFYING, REVIEWING, SHIPPING | Safety-critical stages per existing constraints |
| Max 2 auto-refinements per run | Prevent cascading changes that obscure cause-effect |
| Rollback on >10pt regression | Protect against harmful refinements |
| Require 66%+ agreement across runs | Single-run anomalies don't drive changes |
| `<!-- locked -->` fences respected | Developer explicitly protects sections |
| Proposals with 2+ rollbacks permanently rejected | Prevent oscillation |

## New Skill: `forge-playbook-refine`

**File:** `skills/forge-playbook-refine/SKILL.md`

**Purpose:** Interactive review and application of playbook refinement proposals.

**Usage:** `/forge-playbook-refine [playbook_id]`

**Flow:**
1. If no `playbook_id`, list playbooks with pending proposals
2. Load `.forge/playbook-refinements/{playbook_id}.json`
3. If no proposals: "No refinement proposals for {playbook_id}. Run the playbook 3+ times to generate proposals."
4. For each proposal, present via `AskUserQuestion`:
   - Description, evidence, confidence, agreement, impact estimate
   - Options: Accept, Reject, Modify, Skip
5. Apply accepted proposals to playbook file
6. Increment version in frontmatter
7. Log changes to `forge-log.md`
8. Update refinement file: mark proposals as `applied`, `rejected`, or `deferred`

## Configuration

New/extended section in `forge-config.md`:

```yaml
playbooks:
  auto_refine: false              # Auto-apply HIGH confidence refinements at PREFLIGHT
  refine_min_runs: 3              # Minimum runs before proposing refinements
  refine_agreement: 0.66          # Fraction of runs that must agree (0.5-1.0)
  max_auto_refines_per_run: 2     # Cap on automatic changes per PREFLIGHT
  rollback_threshold: 10          # Score regression (points) that triggers rollback
  max_rollbacks_before_reject: 2  # Permanent rejection after N rollbacks
```

## Files Created/Modified

| File | Change |
|------|--------|
| `agents/fg-700-retrospective.md` | Add playbook refinement extraction step |
| `shared/playbooks.md` | Add "Self-Improvement" section with refinement protocol |
| `shared/schemas/playbook-refinement-schema.json` | New: JSON schema for refinement proposals |
| `skills/forge-playbook-refine/SKILL.md` | New: interactive refinement review skill |
| `shared/state-schema.md` | Document `.forge/playbook-refinements/` directory (survives `/forge-reset`, same as `playbook-analytics.json`) |
| `shared/preflight-constraints.md` | Add auto-refine constraints and validation |
| `CLAUDE.md` | Add entries (see below) |

### Exact `CLAUDE.md` Modifications

**Skill selection guide — new row:**
```
| Review playbook refinements | `/forge-playbook-refine` | Interactive review/apply of improvement proposals |
```

**Skills count:** Update from 40 to 41.

**Features table (v2.0 features) — new row:**
```
| Self-improving playbooks (F31) | `playbooks.*` | Refinement proposals, auto-apply, rollback. `.forge/playbook-refinements/` |
```

**Config sections — add to playbooks config documentation:**
```
auto_refine, refine_min_runs, refine_agreement, max_auto_refines_per_run, rollback_threshold, max_rollbacks_before_reject
```

## Integration Points

| System | Integration |
|--------|-------------|
| `fg-700-retrospective` | Emits refinement suggestions per playbook run |
| `run-history.db` | Stores refinement suggestions in `playbook_runs` table (Spec 2) |
| `.forge/playbook-refinements/` | Aggregated proposals ready for review/auto-apply |
| `forge-playbook-refine` skill | Manual review and application |
| `fg-100-orchestrator` | Auto-apply at PREFLIGHT (when enabled) |
| MCP server | `forge_playbook_effectiveness` exposes proposals (Spec 1) |
| `forge-log.md` | Audit trail for applied/rolled-back refinements |
| `playbook-analytics.json` | Version history for rollback support |

## Testing

- Structural test: verify `shared/schemas/playbook-refinement-schema.json` is valid JSON Schema
- Structural test: verify `skills/forge-playbook-refine/SKILL.md` exists with correct frontmatter
- Contract test: verify `fg-700-retrospective.md` references playbook refinement step
- Contract test: verify `shared/playbooks.md` includes self-improvement section
- Contract test: verify `shared/preflight-constraints.md` includes auto-refine validation
- Scenario test: given mock playbook runs data, verify correct refinement proposals are generated
