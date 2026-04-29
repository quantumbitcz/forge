# Living Specifications

Drift detection between structured specs and implementation. Specs authored by the shaper (`fg-010`) carry machine-parseable acceptance criteria. The quality gate (`fg-400`) detects drift at REVIEW. The retrospective (`fg-700`) proposes or applies spec updates at LEARN.

## Spec Format

Acceptance criteria use monotonic `AC-NNN` identifiers with recommended Given/When/Then structure:

```markdown
**Acceptance Criteria:**
- [AC-001] GIVEN {precondition} WHEN {action} THEN {observable outcome}
- [AC-002] GIVEN {precondition} WHEN {action} THEN {observable outcome}
```

Rules:
- IDs are zero-padded 3-digit, monotonic within a spec (`AC-001`, `AC-002`, ...).
- Given/When/Then is recommended but not mandatory. Freeform ACs are tracked but marked `mappable: false` in the registry.
- Existing shaper testability enforcement (Phase 6, rule 5) still applies. The AC-ID prefix is additive.

### AC ID namespaces

- `AC-NNN` (e.g. `AC-001`) — forge-generated ACs (fg-540 or shaper).
- `AC-BNNN` (e.g. `AC-B001`) — benchmark-injected ACs (Phase 8). Source field `benchmark-injected`.

The orchestrator's spec-refresh logic MUST preserve any spec entry whose `source` field is present (currently: only `benchmark-injected`).

## Spec Registry

File: `.forge/specs/index.json`. Schema: `shared/schemas/spec-registry-schema.json`.

Tracks all specs and their AC statuses. Created/updated by the shaper at shaping time. Read by orchestrator, planner, quality gate, and retrospective.

### Status Lifecycle

```
DRAFT  -->  ACTIVE  -->  SATISFIED
                    -->  DRIFTED  -->  SATISFIED (after update)
                                 -->  ARCHIVED (spec obsoleted)
ACTIVE -->  ARCHIVED (manual or by retrospective)
```

| Status | Meaning |
|--------|---------|
| `DRAFT` | Spec created by shaper, not yet executed by pipeline |
| `ACTIVE` | Pipeline run started with `--spec` pointing to this spec |
| `SATISFIED` | All ACs have status `SATISFIED` |
| `DRIFTED` | One or more ACs have status `DRIFTED` or `UNIMPLEMENTED` |
| `ARCHIVED` | Spec no longer applicable (superseded or feature removed) |

### AC Status

| Status | Meaning |
|--------|---------|
| `PENDING` | Not yet verified |
| `SATISFIED` | Mapped tests exist and pass |
| `DRIFTED` | Mapped tests exist but fail, or implementation exists without test coverage |
| `UNIMPLEMENTED` | No implementation or tests found |

## Drift Detection (REVIEW Stage)

Runs once per REVIEW pass inside the quality gate synthesis, after all review agents return findings. Not repeated per convergence iteration.

### AC-to-Test Mapping Algorithm

For each AC in the active spec:

1. **Extract keywords** from AC text:
   - Entity names (nouns after GIVEN/WHEN)
   - Action verbs (after WHEN)
   - Expected outcomes (after THEN: status codes, state changes, visible elements)

2. **Search test files** for matches:
   - Test file names containing entity keywords
   - Test method names containing action/outcome keywords
   - Test assertions containing expected values (status codes, strings)
   - Explore cache `file_index.*.patterns` for entity-to-test mapping (when available)

3. **Score each candidate test**:
   - +3: test name contains entity AND action keyword
   - +2: test contains assertion matching expected outcome
   - +1: test file is in same module as implementation file
   - Threshold: score >= 3 = mapped, score 1-2 = weak match (logged, not mapped)

4. **Search implementation files** for AC coverage:
   - Route/endpoint matching AC action (HTTP method + path)
   - Domain logic matching AC precondition
   - Explore cache `file_index.*.dependencies` for relationship mapping (when available)

5. **Determine AC status**:
   - `mapped_tests` non-empty AND all pass --> `SATISFIED`
   - `mapped_tests` non-empty AND any fail --> `DRIFTED` (finding: `SPEC-DRIFT-VIOLATION`)
   - `mapped_tests` empty AND `mapped_implementation` non-empty --> `DRIFTED` (finding: `SPEC-DRIFT-COVERAGE-GAP`)
   - `mapped_tests` empty AND `mapped_implementation` empty --> `UNIMPLEMENTED` (finding: `SPEC-DRIFT-UNIMPLEMENTED`)
   - AC not mappable (no Given/When/Then) --> status unchanged, finding at configured `unmapped_ac_severity`

6. **Detect undocumented behavior**:
   - Public endpoints/methods in changed files not covered by any AC
   - Each: emit `SPEC-DRIFT-UNDOCUMENTED` (INFO)

### Mapping Confidence

Each mapping carries HIGH/MEDIUM/LOW confidence based on keyword match strength. LOW-confidence mappings are reported but do not affect AC status. Aligns with the confidence scoring system in `scoring.md`.

## Finding Categories

Registered in `shared/checks/category-registry.json` under `SPEC-DRIFT` (wildcard prefix).

| Code | Severity | Meaning |
|------|----------|---------|
| `SPEC-DRIFT-COVERAGE-GAP` | WARNING | AC exists but no test covers it |
| `SPEC-DRIFT-VIOLATION` | CRITICAL | Test exists for AC but fails |
| `SPEC-DRIFT-UNDOCUMENTED` | INFO | Implementation adds behavior not in any AC |
| `SPEC-DRIFT-UNIMPLEMENTED` | CRITICAL | AC has no corresponding implementation |

Scoring impact follows standard formula: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`. See `scoring.md`.

## Integration Points

### fg-010-shaper (Shaping Time)

- Produces spec with `AC-NNN` identifiers in Phase 5 output.
- Creates or updates `.forge/specs/index.json` with new spec entry, status `DRAFT`, all ACs `PENDING`.
- No change to the 9-phase shaping process. AC-ID format is a formatting rule in Phase 5 (Structure Output), validated in Phase 6 (Self-Review).

### fg-100-orchestrator (PREFLIGHT)

- If `--spec` flag provided, reads the referenced spec file.
- Parses AC identifiers from the spec.
- Updates registry: spec status --> `ACTIVE`.
- Stores `active_spec_slug` in `state.json` for downstream agents.
- Sprint mode: `active_spec_slugs: string[]` for multiple simultaneous specs.

### fg-200-planner (PLANNING)

- Reads active spec ACs from the registry.
- Each AC becomes a plan task constraint: plan must address every `PENDING` or `DRIFTED` AC.
- Notes unmappable ACs (no Given/When/Then) for manual verification.

### fg-400-quality-gate (REVIEWING)

- Runs drift detection after all review agents return findings.
- Emits `SPEC-DRIFT-*` findings per the mapping algorithm above.
- Updates AC statuses in the registry.

### fg-700-retrospective (LEARNING)

- Reads spec registry for active spec.
- For `DRIFTED` ACs: proposes spec update if deviation was intentional (convergence-driven), notes gap otherwise.
- For `SPEC-DRIFT-UNDOCUMENTED` findings: proposes new AC if behavior is intentional, notes for cleanup otherwise.
- When `auto_update_specs: true`: edits spec file and updates registry directly.
- When `auto_update_specs: false` (default): writes proposals to run report only.
- Updates `.forge/specs/index.json` with final statuses.

### Other Systems

| System | Usage |
|--------|-------|
| fg-500-test-gate | Provides test results consumed by drift detector |
| explore-cache.json | File patterns and dependencies enhance AC-to-test mapping |
| category-registry.json | `SPEC-DRIFT-*` category definitions |
| scoring.md | `SPEC-DRIFT-*` severities affect quality score |

## Configuration

In `forge-config.md` / `forge.local.md`:

```yaml
living_specs:
  enabled: true                    # Master toggle (default: true when specs exist)
  drift_detection: true            # Run drift checks at REVIEW (default: true)
  auto_update_specs: false         # Retrospective auto-updates specs (default: false)
  ac_format: "given-when-then"     # AC format: "given-when-then" or "freeform"
  unmapped_ac_severity: "WARNING"  # Severity for unmappable ACs: CRITICAL | WARNING | INFO
```

PREFLIGHT constraints:
- `unmapped_ac_severity` must be `CRITICAL`, `WARNING`, or `INFO`.
- `ac_format` must be `given-when-then` or `freeform`.
- When `living_specs.enabled: true` and no specs exist in `.forge/specs/`, no error -- nothing to check.
- When `living_specs.enabled: false`, no drift detection runs regardless of spec existence.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| `--spec` file does not exist | PREFLIGHT error: `SPEC_NOT_FOUND`. Log ERROR, abort pipeline. |
| Spec file has no parseable AC identifiers | Log WARNING at PREFLIGHT. Drift detection skipped. Pipeline proceeds. |
| Registry `index.json` is corrupt (invalid JSON) | Rebuild from spec files in `.forge/specs/`. Log WARNING. |
| Zero mapping candidates for a mappable AC | Status = `UNIMPLEMENTED`. Finding emitted. |
| All candidates LOW confidence | AC status unchanged. INFO finding: low-confidence mapping, manual review recommended. |
| Multiple specs active (sprint mode) | Each tracked independently. `active_spec_slugs` array in state. |
| Spec file deleted while pipeline running | Drift detection skips missing spec. Log WARNING. Registry unchanged until next run. |

## Performance

- Drift detection overhead: 2-5 seconds for keyword extraction and grep, once per REVIEW pass.
- Registry size: ~1KB per spec with 5 ACs. 100 specs = ~100KB.
- Token cost: ~500 tokens added to quality gate prompt (AC list + mapping results). ~200 tokens for undocumented behavior detection.
- No LLM calls in the hot path. Keyword matching and grep only. LLM used only at LEARN stage for spec update proposals.

## Intent Verification Integration (Phase 7)

`fg-540-intent-verifier` (Phase 7 F35) consumes the AC registry at
`.forge/specs/index.json`. Dispatched at end of Stage 5 VERIFY, before
Stage 6 REVIEW. The verifier reads each AC's Given/When/Then, decomposes
it into runtime probes, and emits `INTENT-*` findings. `fg-590-pre-ship-verifier` gates SHIP on:

- zero open `INTENT-MISSED` CRITICAL findings, AND
- `verified_pct >= intent_verification.strict_ac_required_pct` (default 100).

`INTENT-UNVERIFIABLE` findings bubble up as spec-quality issues
(fg-700 surfaces them in §2j Intent & Vote Analytics with a dedicated row so
they're distinguishable from implementation-quality misses). When the
retrospective sees 2+ `INTENT-MISSED` across 3 runs, Rule 11 proposes
`living_specs.strict_mode: true` via `/forge-admin refine`.

See `shared/intent-verification.md` for end-to-end architecture.
