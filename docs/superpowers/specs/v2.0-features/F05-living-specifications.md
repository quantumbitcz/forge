# F05: Living Specifications with Drift Detection

## Status
DRAFT -- 2026-04-13

## Problem Statement

Forge's `/forge-shape` (fg-010-shaper) produces structured spec documents in `.forge/specs/{feature-name}.md` with epics, stories, and acceptance criteria. These specs are write-once artifacts: after the pipeline runs, no mechanism detects when the implementation drifts from the original specification. Over time, code evolves through bugfixes, convergence loop iterations, and follow-up pipeline runs, but the spec remains frozen at the moment of shaping.

This matters because:
- **Post-run drift**: Convergence loops (Phase 1 correctness, Phase 2 perfection) may alter implementation in ways that deviate from the spec's acceptance criteria without anyone noticing.
- **Cross-run drift**: Subsequent `/forge-run` invocations that touch the same code area may invalidate prior spec assumptions.
- **Feedback-driven drift**: User corrections captured by `fg-710-post-run` (convention-violation, wrong-approach, missing-requirement, style-preference) may override spec decisions without updating the spec.

Competitive landscape: GitHub Spec Kit pushes spec-driven development with auto-linking. Kiro (AWS) generates specs from requirements with acceptance criteria tracking. Tessl converts specs to implementation with live status. Martin Fowler's team warns that verbose, heavyweight specs create review fatigue -- the key is lightweight, machine-parseable acceptance criteria, not 50-page documents.

## Proposed Solution

Extend the existing spec format with machine-parseable acceptance criteria identifiers (AC-NNN). Introduce a spec registry at `.forge/specs/index.json` to track all specs and their status. Add drift detection at the REVIEW stage that maps acceptance criteria to test assertions and implementation, producing `SPEC-DRIFT-*` findings. Close the loop at the LEARN stage where the retrospective proposes spec updates when implementation deviates.

## Detailed Design

### Architecture

The system has four components:

1. **Spec format extension** (shaper output) -- structured acceptance criteria with IDs
2. **Spec registry** (new file) -- tracks spec status and AC-to-artifact mappings
3. **Drift detector** (review-stage integration) -- compares spec against implementation
4. **Spec updater** (learn-stage integration) -- proposes spec updates on drift

#### Component Ownership

| Component | Owner Agent | Stage |
|-----------|-------------|-------|
| Spec format | fg-010-shaper | Pre-pipeline (shaping) |
| Spec registry | fg-100-orchestrator | PREFLIGHT (init), REVIEW (update), LEARN (close) |
| Drift detector | fg-400-quality-gate | REVIEWING |
| Spec updater | fg-700-retrospective | LEARNING |

### Schema / Data Model

#### Enhanced Acceptance Criteria Format

The shaper's output format (Section 4 of `fg-010-shaper.md`) is extended with machine-parseable AC identifiers. The existing checkbox format:

```markdown
**Acceptance Criteria:**
- [ ] {criterion 1}
```

Becomes:

```markdown
**Acceptance Criteria:**
- [AC-001] GIVEN {precondition} WHEN {action} THEN {observable outcome}
- [AC-002] GIVEN {precondition} WHEN {action} THEN {observable outcome}
```

Rules:
- AC identifiers are monotonic within a spec, prefixed `AC-` with zero-padded 3-digit number.
- Given/When/Then structure is recommended but not mandatory. ACs without this structure are still tracked but cannot be auto-mapped to tests.
- Existing shaper testability enforcement (Phase 6, rule 5) ensures ACs are verifiable. The AC-ID prefix is additive to that rule.
- ACs that do not follow Given/When/Then are tagged `mappable: false` in the registry.

#### Spec Registry Schema

`.forge/specs/index.json`:

```json
{
  "schema_version": "1.0.0",
  "specs": {
    "notification-system": {
      "file": ".forge/specs/notification-system.md",
      "created_at": "2026-04-13T10:00:00Z",
      "last_checked_at": "2026-04-13T14:30:00Z",
      "status": "ACTIVE",
      "story_ids": ["FG-042", "FG-043"],
      "acceptance_criteria": {
        "AC-001": {
          "text": "GIVEN authenticated user WHEN POST /api/notifications THEN returns 201 with notification ID",
          "status": "SATISFIED",
          "mappable": true,
          "mapped_tests": [
            "src/test/kotlin/com/example/NotificationControllerTest.kt#testCreateNotification"
          ],
          "mapped_implementation": [
            "src/main/kotlin/com/example/api/NotificationController.kt"
          ],
          "last_verified_at": "2026-04-13T14:30:00Z"
        },
        "AC-002": {
          "text": "GIVEN unauthenticated user WHEN POST /api/notifications THEN returns 401",
          "status": "DRIFTED",
          "mappable": true,
          "mapped_tests": [],
          "mapped_implementation": [
            "src/main/kotlin/com/example/api/NotificationController.kt"
          ],
          "drift_detail": "No test covers the 401 response path",
          "last_verified_at": "2026-04-13T14:30:00Z"
        }
      }
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Registry format version for migration |
| `specs` | object | Keyed by spec slug (matches filename sans `.md`) |
| `specs.*.file` | string | Relative path to the spec file |
| `specs.*.created_at` | string (ISO 8601) | When the spec was first shaped |
| `specs.*.last_checked_at` | string (ISO 8601) | Last drift check timestamp |
| `specs.*.status` | enum | `DRAFT`, `ACTIVE`, `SATISFIED`, `DRIFTED`, `ARCHIVED` |
| `specs.*.story_ids` | string[] | Kanban ticket IDs linked to this spec |
| `specs.*.acceptance_criteria` | object | Keyed by AC identifier |
| `specs.*.acceptance_criteria.*.text` | string | The full AC text |
| `specs.*.acceptance_criteria.*.status` | enum | `PENDING`, `SATISFIED`, `DRIFTED`, `UNIMPLEMENTED` |
| `specs.*.acceptance_criteria.*.mappable` | boolean | Whether AC follows Given/When/Then and can be auto-mapped |
| `specs.*.acceptance_criteria.*.mapped_tests` | string[] | Test file paths with optional `#methodName` suffix |
| `specs.*.acceptance_criteria.*.mapped_implementation` | string[] | Implementation file paths |
| `specs.*.acceptance_criteria.*.drift_detail` | string or null | Human-readable drift explanation |
| `specs.*.acceptance_criteria.*.last_verified_at` | string (ISO 8601) | Last verification timestamp |

**Spec status lifecycle:**

```
DRAFT  -->  ACTIVE  -->  SATISFIED
                    -->  DRIFTED  -->  SATISFIED (after update)
                                 -->  ARCHIVED (spec obsoleted)
ACTIVE -->  ARCHIVED (manual or by retrospective)
```

- `DRAFT`: Spec created by shaper, not yet executed by pipeline.
- `ACTIVE`: Pipeline run started with `--spec` pointing to this spec.
- `SATISFIED`: All ACs have status `SATISFIED`.
- `DRIFTED`: One or more ACs have status `DRIFTED` or `UNIMPLEMENTED`.
- `ARCHIVED`: Spec no longer applicable (superseded or feature removed).

#### Finding Categories

New category entries for `shared/checks/category-registry.json`:

```json
{
  "SPEC-DRIFT": {
    "description": "Specification drift detected (implementation deviates from spec)",
    "agents": ["fg-400-quality-gate"],
    "wildcard": true,
    "priority": 3,
    "affinity": ["fg-410-code-reviewer", "fg-418-docs-consistency-reviewer"]
  }
}
```

Finding codes under `SPEC-DRIFT-*`:

| Code | Severity | Meaning |
|------|----------|---------|
| `SPEC-DRIFT-COVERAGE-GAP` | WARNING | AC exists but no test covers it |
| `SPEC-DRIFT-VIOLATION` | CRITICAL | Test exists for AC but fails |
| `SPEC-DRIFT-UNDOCUMENTED` | INFO | Implementation adds behavior not captured in any AC |
| `SPEC-DRIFT-UNIMPLEMENTED` | CRITICAL | AC has no corresponding implementation at all |

### Configuration

In `forge-config.md`:

```yaml
living_specs:
  enabled: true                    # Master toggle (default: true when specs exist)
  drift_detection: true            # Run drift checks at REVIEW (default: true)
  auto_update_specs: false         # Retrospective auto-updates specs (default: false)
  ac_format: "given-when-then"     # AC format: "given-when-then" or "freeform" (default: given-when-then)
  unmapped_ac_severity: "WARNING"  # Severity for ACs that cannot be auto-mapped (default: WARNING)
```

Constraints enforced at PREFLIGHT:
- `unmapped_ac_severity` must be one of `CRITICAL`, `WARNING`, `INFO`.
- `ac_format` must be one of `given-when-then`, `freeform`.
- When `living_specs.enabled` is `true` and no specs exist in `.forge/specs/`, no error -- the feature simply has nothing to check.

### Data Flow

#### At Shaping Time (fg-010-shaper)

1. Shaper produces spec with `AC-NNN` identifiers (Phase 5, output format).
2. Shaper creates or updates `.forge/specs/index.json` with the new spec entry, status `DRAFT`, all ACs status `PENDING`.
3. No change to the 9-phase shaping process. The AC-ID format is a formatting rule applied during Phase 5 (Structure Output) and validated during Phase 6 (Self-Review).

#### At PREFLIGHT (fg-100-orchestrator)

1. If `--spec` flag is provided, read the referenced spec file.
2. Parse AC identifiers from the spec.
3. Update registry: set spec status to `ACTIVE`.
4. Store `active_spec_slug` in `state.json` for downstream agents to reference.

#### At PLANNING (fg-200-planner)

1. Planner reads the active spec's ACs from the registry.
2. Each AC becomes a plan task constraint: the plan must address every `PENDING` or `DRIFTED` AC.
3. Planner notes unmappable ACs (those without Given/When/Then) for manual verification.

#### At REVIEW (fg-400-quality-gate)

The drift detector runs as part of the quality gate's review synthesis, after all review agents have returned findings.

**AC-to-test mapping algorithm:**

```
FOR each AC in active spec:
  1. Extract keywords from AC text:
     - Entity names (nouns after GIVEN/WHEN)
     - Action verbs (after WHEN)
     - Expected outcomes (after THEN: status codes, state changes, visible elements)

  2. Search test files for matches:
     - Grep test file names for entity keywords
     - Grep test method names for action/outcome keywords
     - Grep test assertions for expected values (status codes, strings)
     - If explore cache available: use file_index.*.patterns for entity-to-test mapping

  3. Score each candidate test:
     - +3: test name contains entity AND action keyword
     - +2: test contains assertion matching expected outcome
     - +1: test file is in same module as implementation file
     - Threshold: score >= 3 = mapped, score 1-2 = weak match (logged, not mapped)

  4. Search implementation files for AC coverage:
     - Grep for route/endpoint matching AC's action (HTTP method + path)
     - Grep for domain logic matching AC's precondition
     - Use explore cache file_index.*.dependencies for relationship mapping

  5. Determine AC status:
     - mapped_tests non-empty AND all pass -> SATISFIED
     - mapped_tests non-empty AND any fail -> DRIFTED (finding: SPEC-DRIFT-VIOLATION)
     - mapped_tests empty AND mapped_implementation non-empty -> DRIFTED (finding: SPEC-DRIFT-COVERAGE-GAP)
     - mapped_tests empty AND mapped_implementation empty -> UNIMPLEMENTED (finding: SPEC-DRIFT-UNIMPLEMENTED)
     - AC not mappable (no Given/When/Then) -> status unchanged, finding at configured severity

  6. Detect undocumented behavior:
     - Identify public endpoints/methods in changed files not covered by any AC
     - For each: emit SPEC-DRIFT-UNDOCUMENTED (INFO)
```

**Mapping confidence:** Each mapping carries a confidence score (HIGH/MEDIUM/LOW) based on keyword match strength. LOW-confidence mappings are reported but do not affect AC status. This aligns with the existing confidence scoring system in `shared/scoring.md`.

#### At LEARN (fg-700-retrospective)

1. Read the spec registry for the active spec.
2. For each `DRIFTED` AC:
   - If implementation clearly deviated with good reason (convergence loop optimized the approach): propose spec update with the new behavior.
   - If implementation is simply incomplete: note as a gap for the next run.
3. For each `SPEC-DRIFT-UNDOCUMENTED` finding:
   - If the undocumented behavior is intentional (added during convergence): propose adding a new AC.
   - If accidental: note for cleanup.
4. When `auto_update_specs: true`, the retrospective edits the spec file directly and updates the registry. When `false` (default), the retrospective writes proposals to the run report.
5. Update `.forge/specs/index.json` with final statuses.

### Integration Points

| System | Integration | Direction |
|--------|-------------|-----------|
| fg-010-shaper | Produces specs with AC-NNN format | Write |
| fg-100-orchestrator | Reads spec at PREFLIGHT, stores `active_spec_slug` in state | Read |
| fg-200-planner | Reads ACs as plan constraints | Read |
| fg-400-quality-gate | Runs drift detection, emits SPEC-DRIFT-* findings | Read + Write |
| fg-700-retrospective | Reads drift results, proposes/applies spec updates | Read + Write |
| fg-500-test-gate | Provides test results consumed by drift detector | Read |
| explore-cache.json | File patterns and dependencies used for AC-to-test mapping | Read |
| category-registry.json | SPEC-DRIFT-* category definitions | Read |
| scoring.md | SPEC-DRIFT-* severities affect quality score | Read |

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Spec file referenced by `--spec` does not exist | PREFLIGHT error: `SPEC_NOT_FOUND`. Log ERROR, abort pipeline. |
| Spec file exists but has no parseable AC identifiers | Log WARNING at PREFLIGHT. Drift detection skipped. Pipeline proceeds. |
| Registry `index.json` is corrupt (invalid JSON) | Rebuild from spec files in `.forge/specs/`. Log WARNING. |
| AC mapping finds zero candidates for a mappable AC | Status = `UNIMPLEMENTED`. Finding emitted. |
| AC mapping finds candidates but confidence is LOW for all | AC status unchanged. INFO finding: "Low-confidence mapping for AC-NNN -- manual review recommended." |
| Multiple specs active simultaneously (sprint mode) | Each spec tracked independently. `active_spec_slug` becomes `active_spec_slugs: string[]` in state. |
| Spec file deleted manually while pipeline is running | Drift detection skips the missing spec. Log WARNING. Registry status unchanged until next run. |

## Performance Characteristics

- **Drift detection overhead**: The AC-to-test mapping runs once per REVIEW pass (not per convergence iteration). Estimated cost: 2-5 seconds for keyword extraction and grep, negligible compared to review agent dispatch time.
- **Registry size**: ~1KB per spec with 5 ACs. At 100 specs, the registry is ~100KB -- well within JSON parsing limits.
- **Token cost**: Drift detection adds ~500 tokens to the quality gate prompt (AC list + mapping results). Undocumented behavior detection adds ~200 tokens for the changed-file analysis.
- **No LLM calls in the hot path**: AC-to-test mapping uses keyword matching and grep, not LLM inference. LLM is only used at LEARN stage for spec update proposals.

## Testing Approach

### Structural Tests (validate-plugin.sh)

1. `SPEC-DRIFT` category exists in `category-registry.json` with required fields.
2. All `SPEC-DRIFT-*` finding codes have defined severities.
3. Spec registry schema version field is present.

### Unit Tests

1. **AC parser**: Given a spec markdown with AC-NNN lines, extract all AC identifiers and text. Test with Given/When/Then format, freeform format, and mixed.
2. **AC-to-test mapper**: Given a set of AC keywords and a mock test file index, verify correct mapping scores and threshold filtering.
3. **Registry lifecycle**: Create spec (DRAFT), activate (ACTIVE), satisfy all ACs (SATISFIED), drift one AC (DRIFTED), archive (ARCHIVED).
4. **Finding emission**: Given various AC statuses, verify correct SPEC-DRIFT-* finding codes and severities.

### Contract Tests

1. Spec file produced by shaper contains valid AC-NNN identifiers parseable by the drift detector.
2. Registry `index.json` written by shaper is readable by the quality gate.
3. Drift findings produced by the quality gate are consumable by the retrospective.

### Scenario Tests

1. **Happy path**: Shape a spec, run pipeline, all ACs satisfied, spec status becomes SATISFIED.
2. **Coverage gap**: Shape a spec with 3 ACs, implement 2 with tests, third has no test. Expect `SPEC-DRIFT-COVERAGE-GAP` (WARNING) for the third AC.
3. **Violation**: Spec says "returns 201", test expects 201 but implementation returns 200. Expect `SPEC-DRIFT-VIOLATION` (CRITICAL).
4. **Undocumented**: Implementation adds a DELETE endpoint not in the spec. Expect `SPEC-DRIFT-UNDOCUMENTED` (INFO).
5. **Auto-update**: With `auto_update_specs: true`, retrospective updates spec to match implementation after convergence loop changed the approach.

## Acceptance Criteria

- [AC-001] GIVEN a `/forge-shape` run WHEN the shaper produces a spec THEN each acceptance criterion has a unique `AC-NNN` identifier and the spec is registered in `.forge/specs/index.json` with status `DRAFT`.
- [AC-002] GIVEN a pipeline run with `--spec` flag WHEN the spec has 5 ACs and implementation covers 4 with passing tests THEN the drift detector emits exactly one `SPEC-DRIFT-COVERAGE-GAP` WARNING finding for the uncovered AC.
- [AC-003] GIVEN a pipeline run with `--spec` flag WHEN a test for an AC fails THEN the drift detector emits a `SPEC-DRIFT-VIOLATION` CRITICAL finding and the AC status in the registry is `DRIFTED`.
- [AC-004] GIVEN a pipeline run with `--spec` flag WHEN the implementation adds a public endpoint not covered by any AC THEN the drift detector emits a `SPEC-DRIFT-UNDOCUMENTED` INFO finding.
- [AC-005] GIVEN `auto_update_specs: false` (default) WHEN drift is detected THEN the retrospective writes spec update proposals to the run report but does NOT modify the spec file.
- [AC-006] GIVEN `auto_update_specs: true` WHEN drift is detected and the deviation was intentional (convergence-driven) THEN the retrospective edits the spec file and updates the registry AC text and status.
- [AC-007] GIVEN `living_specs.enabled: false` WHEN a pipeline run executes THEN no drift detection occurs and no SPEC-DRIFT-* findings are emitted regardless of spec existence.
- [AC-008] GIVEN a spec with freeform ACs (no Given/When/Then) WHEN drift detection runs THEN unmappable ACs produce a finding at the configured `unmapped_ac_severity` level and their status remains unchanged.

## Migration Path

1. **v2.0.0**: Ship the feature behind `living_specs.enabled: true` (default when specs exist). Existing specs in `.forge/specs/` without AC-NNN identifiers are registered but all ACs are marked `mappable: false`. No drift detection runs for legacy specs.
2. **v2.0.x**: Add a `/forge-spec-migrate` skill that retroactively adds AC-NNN identifiers to existing specs by parsing their checkbox-format acceptance criteria.
3. **v2.1.0**: Consider promoting `auto_update_specs` default to `true` once the update quality is validated across real projects.

## Dependencies

| Dependency | Type | Required? |
|------------|------|-----------|
| fg-010-shaper output format change | Agent modification | Yes |
| category-registry.json update | Shared infrastructure | Yes |
| fg-400-quality-gate integration | Agent modification | Yes |
| fg-700-retrospective integration | Agent modification | Yes |
| fg-200-planner AC-aware planning | Agent modification | Yes |
| state.json `active_spec_slug` field | Schema addition | Yes |
| explore-cache.json | Existing system | No (enhances mapping accuracy) |
| Neo4j knowledge graph | Existing system | No (enhances mapping accuracy) |
