# Q08: Documentation Completeness

## Status
DRAFT — 2026-04-13

## Problem Statement

Documentation scored A- (88/100) in the system review. Five specific gaps were identified:

1. **No version migration table in `state-schema.md`.** The schema is at v1.5.0 but there is no documentation of what changed between versions, how the orchestrator detects and upgrades old state files, or what migration steps are needed. A project that last ran with v1.4.0 state has no guidance on what happens when v1.5.0 loads that state.

2. **Frontend design theory has no explicit mapping to reviewer scoring.** `shared/frontend-design-theory.md` defines Gestalt principles, visual hierarchy, color theory, typography, 8pt grid, and motion rules. `agents/fg-413-frontend-reviewer.md` references this theory file. But there is no explicit mapping from theory concepts to finding categories (`FE-VISUAL-*`, `DESIGN-TOKEN`, `DESIGN-MOTION`). A reviewer implementing `fg-413` must infer which theory violations produce which finding codes.

3. **Cross-reference audit needed.** Several shared docs reference sections in other documents that are underspecified or missing. No systematic audit has been performed.

4. **CLAUDE.md does not mention composition priority order.** The architecture section in `CLAUDE.md` lists the module layer structure but does not reference the composition priority order (variant > framework-binding > framework > language > code-quality > generic-layer > testing), which is documented in CLAUDE.md itself under Module layer but not connected to any standalone document explaining the resolution algorithm.

5. **Evidence partial failure undocumented.** `shared/verification-evidence.md` defines the schema and verdict rules for `evidence.json`, but does not specify what happens when evidence collection partially fails (e.g., build succeeds but test command times out, or lint succeeds but review agent crashes).

## Target
Documentation A- -> A+ (88 -> 96+)

## Detailed Changes

### 1. Version Migration Table in state-schema.md

**Location:** Add a new `## Version Migration` section at the end of `shared/state-schema.md`, before any appendix.

**Content:**

```markdown
## Version Migration

### Migration History

| From | To | Changes | Migration |
|------|-----|---------|-----------|
| 1.0.0 | 1.1.0 | Added `convergence` block (phase, state, score_history, plateau_count) | Auto-migrate: add empty `convergence` block with defaults |
| 1.1.0 | 1.2.0 | Added `recovery` block, `total_retries` counter, `mode` field | Auto-migrate: add `recovery: {}`, `total_retries: 0`, `mode: "standard"` |
| 1.2.0 | 1.3.0 | Added `graph` block, `ticket_id`, `branch_name` | Auto-migrate: add `graph: { enabled: false }`, null ticket/branch |
| 1.3.0 | 1.4.0 | Added `tokens` block (per-stage/agent/model breakdowns), `cost.estimated_cost_usd`, `feedback_loop_count`, `detected_versions` | Auto-migrate: add empty `tokens: {}`, `cost: {}`, `feedback_loop_count: 0`, `detected_versions: {}` |
| 1.4.0 | 1.5.0 | Added `decision_quality` block, `evidence.block_history[]`, `_seq` versioning for WAL writes, `sprint_id` field, `explore_cache_hit` boolean, `plan_cache_hit` boolean | Auto-migrate: add `decision_quality: {}`, `evidence: { block_history: [] }`, `_seq: 0` |

### Version Detection and Upgrade

The orchestrator detects the state version at PREFLIGHT (stage 0):

1. Read `state.json`. If file does not exist, create fresh with current version (1.5.0).
2. Check `state.json.version` field.
3. If version matches current (1.5.0): proceed normally.
4. If version is older: apply migrations sequentially (1.0.0 -> 1.1.0 -> ... -> 1.5.0).
5. If version is newer (future state loaded by older plugin): log WARNING "State version {v} is newer than plugin version 1.5.0. Proceeding with best-effort compatibility." Do not downgrade.
6. After migration: update `version` field to 1.5.0, write via `forge-state-write.sh`.

### Migration Safety

- Migrations are additive only (new fields with safe defaults). No field removals or renames.
- Missing fields are populated with defaults; existing fields are never overwritten by migration.
- If `state.json` is corrupt (invalid JSON), the orchestrator creates a fresh state and logs ERROR "Corrupted state.json, starting fresh."
- Migration is logged to `.forge/.hook-failures.log` with reason `state_migration:{from}->{to}`.
```

### 2. Frontend Design Theory to Reviewer Scoring Mapping

**Location:** Add a new section to `shared/frontend-design-theory.md` at the end: `## Theory-to-Finding Category Mapping`.

Alternatively, add a `## Scoring Reference` section to `agents/fg-413-frontend-reviewer.md`. The theory file is the better location because it is the shared reference for both the polisher and reviewer.

**Content:**

```markdown
## Theory-to-Finding Category Mapping

This table maps design theory violations to finding categories emitted by `fg-413-frontend-reviewer` and `fg-320-frontend-polisher`. When evaluating code, use this as the authoritative mapping.

### Gestalt Principle Violations

| Theory Concept | Violation | Finding Category | Default Severity |
|---------------|-----------|-----------------|-----------------|
| Proximity | Related elements not grouped; ambiguous spacing | `FE-VISUAL-LAYOUT` | WARNING |
| Similarity | Same-function elements with inconsistent styling | `FE-VISUAL-LAYOUT` | WARNING |
| Continuity | Grid misalignment; inconsistent visual flow | `FE-VISUAL-LAYOUT` | WARNING |
| Closure | Over-bordered UI; nested cage effect | `FE-VISUAL-LAYOUT` | INFO |
| Figure-Ground | Poor content-background separation | `FE-VISUAL-CONTRAST` | WARNING |

### Visual Hierarchy Violations

| Theory Concept | Violation | Finding Category | Default Severity |
|---------------|-----------|-----------------|-----------------|
| Squint test failure | No clear primary focal point | `FE-VISUAL-LAYOUT` | WARNING |
| Heading scale | Ratio between heading levels < 1.2x | `FE-VISUAL-TYPE` | INFO |
| Weight hierarchy | Competing bold elements with no clear primary | `FE-VISUAL-LAYOUT` | INFO |

### Color Theory Violations

| Theory Concept | Violation | Finding Category | Default Severity |
|---------------|-----------|-----------------|-----------------|
| 60/30/10 rule | Dominant color exceeds 70% or accent exceeds 15% | `FE-VISUAL-COLOR` | INFO |
| Contrast ratio | Text contrast below WCAG AA (4.5:1 normal, 3:1 large) | `FE-VISUAL-CONTRAST` | CRITICAL |
| Hardcoded color values | Hex/RGB literals instead of design tokens | `DESIGN-TOKEN` | WARNING |
| Color-only signaling | Meaning conveyed only through color (a11y) | `A11Y-COLOR` | WARNING |

### Typography Violations

| Theory Concept | Violation | Finding Category | Default Severity |
|---------------|-----------|-----------------|-----------------|
| Font count | More than 2 font families | `FE-VISUAL-TYPE` | WARNING |
| Hardcoded font sizes | Pixel values instead of design tokens/scale | `DESIGN-TOKEN` | WARNING |
| Line length | Body text exceeding 80ch or below 45ch | `FE-VISUAL-TYPE` | INFO |
| Line height | Line height < 1.4 for body text | `FE-VISUAL-TYPE` | INFO |

### 8pt Grid Violations

| Theory Concept | Violation | Finding Category | Default Severity |
|---------------|-----------|-----------------|-----------------|
| Spacing off-grid | Padding/margin not a multiple of 8px (or 4px for small elements) | `FE-VISUAL-SPACING` | WARNING |
| Inconsistent spacing | Same logical spacing using different values | `FE-VISUAL-SPACING` | WARNING |
| Hardcoded spacing | Pixel values instead of spacing tokens | `DESIGN-TOKEN` | WARNING |

### Motion Violations

| Theory Concept | Violation | Finding Category | Default Severity |
|---------------|-----------|-----------------|-----------------|
| Non-GPU animation | Animating width/height/top/left instead of transform/opacity | `DESIGN-MOTION` | WARNING |
| Missing will-change | Complex animation without will-change hint | `DESIGN-MOTION` | INFO |
| Missing prefers-reduced-motion | Animation without reduced-motion media query | `A11Y-MOTION` | WARNING |
| Duration too long | Animation > 500ms for UI transitions | `DESIGN-MOTION` | INFO |
| Duration too short | Animation < 100ms (imperceptible) | `DESIGN-MOTION` | INFO |

### Category Cross-Reference

| Finding Category | Defined in | Scoring Weight |
|-----------------|-----------|---------------|
| `FE-VISUAL-LAYOUT` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `FE-VISUAL-COLOR` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `FE-VISUAL-TYPE` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `FE-VISUAL-SPACING` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `FE-VISUAL-CONTRAST` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `FE-VISUAL-REGRESSION` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `FE-VISUAL-RESPONSIVE` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `FE-VISUAL-FIDELITY` | scoring.md (`FE-VISUAL-*` wildcard) | Standard per severity |
| `DESIGN-TOKEN` | scoring.md (discrete) | Standard per severity |
| `DESIGN-MOTION` | scoring.md (discrete) | Standard per severity |
| `A11Y-*` | scoring.md (`A11Y-*` wildcard) | Standard per severity |
```

### 3. Cross-Reference Audit

**Methodology:** Systematically scan all files in `shared/` for markdown links and section references that point to underspecified or missing targets.

**Deliverable:** A table in a new section of `CLAUDE.md` or as inline fixes to the referenced documents.

**Known cross-reference gaps to investigate and fix:**

| Source File | Reference | Target | Issue | Fix |
|-------------|-----------|--------|-------|-----|
| `shared/convergence-engine.md` | "see scoring.md" | `shared/scoring.md` score escalation ladder | The "score escalation ladder" is described inline in convergence-engine but not explicitly labeled in scoring.md | Add `### Score Escalation Ladder` heading in scoring.md at the relevant section |
| `shared/scoring.md` | "per Aim-for-Target policy" | Same file, section reference | Self-reference is fine but the section is not a linkable heading | Add `### Aim-for-Target Policy` as an H3 heading |
| `shared/state-transitions.md` | "see algorithm ELSE branch" | `shared/convergence-engine.md` algorithm section | Vague reference to "ELSE branch" | Replace with specific section reference: "see convergence-engine.md Phase 1 Inner Caps" |
| `shared/agent-communication.md` | "defined in `shared/checks/category-registry.json`" | category-registry.json `affinity` field | The JSON file exists but `affinity` field documentation is only in agent-communication.md, not in the JSON file itself | Add a comment header or companion `category-registry-schema.md` documenting the affinity field |
| `shared/verification-evidence.md` | "history is in `state.json.evidence.block_history`" | `shared/state-schema.md` | The `block_history` field is referenced but not explicitly documented in the state schema field reference | Add `block_history` to the state-schema.md evidence block documentation |
| `shared/recovery/recovery-engine.md` | "7 strategies" | Recovery strategies list | Verify all 7 strategies are explicitly enumerated with names | Ensure strategy list is a numbered, named list |
| `CLAUDE.md` | "COMPOSITION.md" reference | Not present in CLAUDE.md | Composition priority order is stated but not linked to a standalone doc | Add composition reference (see change 4) |

**Process:** For each gap identified, apply the fix directly to the target document. The audit itself is not committed as a separate artifact -- the fixes are.

### 4. CLAUDE.md Composition Reference

**Location:** In the `## Architecture` section of `CLAUDE.md`, after the module layer bullet point.

**Current text (approximate):**
```
2. **Module layer** (`modules/`):
   - `languages/` (15): kotlin, java, ...
   ...
   - **Composition order** (most specific wins): variant > framework-binding > framework > language > code-quality > generic-layer > testing
```

**Addition:** After the composition order line, add:

```
   The composition algorithm is documented in `shared/composition.md`. When convention stacks are resolved at PREFLIGHT, files are loaded in this order with later files overriding earlier ones for conflicting rules.
```

**Conditional:** If `shared/composition.md` does not currently exist, create it as a focused document:

```markdown
# Convention Composition Order

When the orchestrator resolves the convention stack for a component at PREFLIGHT, it loads convention files in this order. Later files override earlier ones for conflicting rules. All files contribute additively for non-conflicting rules.

## Resolution Order (most specific wins)

1. **Testing module** (`modules/testing/{name}.md`) — test framework conventions
2. **Generic layer** (`modules/{layer}/{name}.md`) — cross-cutting domain conventions (auth, observability, etc.)
3. **Code quality** (`modules/code-quality/{tool}.md`) — linter/formatter conventions
4. **Language** (`modules/languages/{lang}.md`) — language-level conventions
5. **Framework** (`modules/frameworks/{name}/conventions.md`) — framework base conventions
6. **Framework binding** (`modules/frameworks/{name}/{layer}/{binding}.md`) — framework-specific layer binding (e.g., spring/persistence/hibernate.md)
7. **Variant** (`modules/frameworks/{name}/variants/{variant}.md`) — variant-specific overrides

Files loaded later (higher number) take precedence for conflicting rules. Example: if the language module says "use camelCase" but the framework variant says "use snake_case for database columns," the variant wins.

## Soft Cap

Convention stacks are soft-capped at 12 files per component. Beyond 12, the orchestrator logs WARNING and loads the 12 most specific files (prioritizing variant and framework binding). Module overviews are capped at 15 lines each.

## Drift Detection

Mid-run SHA256 hash comparison detects if convention files change during a pipeline run. Agents react only to changes in their relevant section (determined by the agent's `focus` field).
```

### 5. Evidence Partial Failure Documentation

**Location:** Add a new section to `shared/verification-evidence.md` after the "Lifecycle" section.

**New section: "## Partial Failure Handling"**

```markdown
## Partial Failure Handling

Evidence collection runs four checks sequentially: build, tests, lint, review. If any check
partially fails (timeout, crash, indeterminate result), the following rules apply:

### Check-Level Failure Modes

| Check | Failure Mode | Evidence Field | Verdict Effect |
|-------|-------------|---------------|----------------|
| Build | Command times out (`build_timeout` exceeded) | `build.exit_code: -1`, `build.output_tail: "TIMEOUT after {N}s"` | BLOCK with `block_reasons: ["build_timeout"]` |
| Build | Command crashes (signal) | `build.exit_code: {signal + 128}` | BLOCK with `block_reasons: ["build_crash"]` |
| Tests | Command times out (`test_timeout` exceeded) | `tests.exit_code: -1`, `tests.total: 0` | BLOCK with `block_reasons: ["test_timeout"]` |
| Tests | Partial completion (some suites pass, runner crashes) | `tests.exit_code: {code}`, `tests.passed: {partial}`, `tests.failed: -1` | BLOCK with `block_reasons: ["test_partial_failure"]` |
| Lint | Command times out (`lint_timeout` exceeded) | `lint.exit_code: -1` | BLOCK with `block_reasons: ["lint_timeout"]` |
| Review | Agent timeout (>10min) | `review.dispatched: true`, `review.critical_issues: -1` | BLOCK with `block_reasons: ["review_timeout"]` |
| Review | Agent crash | `review.dispatched: false` | BLOCK with `block_reasons: ["review_not_dispatched"]` |

### Sentinel Values

- `exit_code: -1` indicates timeout (the command did not produce an exit code)
- `tests.failed: -1` indicates the test runner crashed before reporting results
- `review.critical_issues: -1` indicates the review agent did not return a structured result

### Sequential Short-Circuit

Evidence collection is sequential: build -> tests -> lint -> review. If build fails, subsequent
checks are **not skipped** — all four run regardless. Rationale: even with a build failure, lint
and review may surface additional issues that inform the fix cycle.

**Exception:** If `build.exit_code` is -1 (timeout), tests are skipped (they cannot run without
a successful build). Lint and review still run against the source code (they do not require
a build artifact).

### Block History

Each BLOCK verdict appends to `state.json.evidence.block_history[]`:

```json
{
  "timestamp": "2026-04-13T10:00:00Z",
  "block_reasons": ["test_timeout"],
  "scores": { "build": 0, "tests": -1, "lint": 0, "review": 0 }
}
```

The orchestrator uses `block_history` to detect patterns (e.g., tests consistently timing out)
and may adjust timeouts or escalate.
```

## Testing Approach

1. **Documentation lint test (bats):** Validate that `state-schema.md` contains `## Version Migration` section.

2. **Documentation lint test:** Validate that `frontend-design-theory.md` contains `## Theory-to-Finding Category Mapping` section.

3. **Cross-reference test:** For each known cross-reference gap, verify the fix is in place (grep for the added heading or section).

4. **Composition doc test:** Verify `shared/composition.md` exists (or the CLAUDE.md reference is updated).

5. **Evidence doc test:** Verify `verification-evidence.md` contains `## Partial Failure Handling` section.

6. **Manual review:** Read through each changed document end-to-end for internal consistency.

## Acceptance Criteria

- [ ] `shared/state-schema.md` includes Version Migration section with migration history table (v1.0.0 through v1.5.0)
- [ ] Version detection and upgrade protocol is documented (5-step process)
- [ ] `shared/frontend-design-theory.md` includes Theory-to-Finding Category Mapping with all 6 theory domains mapped
- [ ] Every mapping row specifies: theory concept, violation description, finding category, default severity
- [ ] Cross-reference audit identifies and fixes at least 5 gaps (the 7 listed above as starting set)
- [ ] `CLAUDE.md` architecture section references composition order document
- [ ] `shared/composition.md` exists with resolution order, soft cap, and drift detection documentation
- [ ] `shared/verification-evidence.md` includes Partial Failure Handling section with check-level failure modes, sentinel values, short-circuit rules, and block history format
- [ ] All existing `validate-plugin.sh` checks continue to pass

## Effort Estimate

Medium (3-4 days). Entirely documentation work, no code changes.

- State schema version migration: 0.5 day
- Frontend design theory mapping: 1 day (requires careful review of all theory concepts)
- Cross-reference audit: 1 day (scanning + fixing)
- CLAUDE.md + composition doc: 0.25 day
- Evidence partial failure: 0.5 day
- Review and consistency check: 0.5 day

## Dependencies

- Q07 (module structural tests) may create documentation updates that should be reflected here
- The frontend design theory mapping should be reviewed by someone familiar with `fg-413-frontend-reviewer` implementation to verify the category assignments are correct
- No code dependencies -- all changes are documentation
