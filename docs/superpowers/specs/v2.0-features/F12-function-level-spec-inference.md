# F12: Function-Level Specification Inference for Bug Fixes

## Status
DRAFT — 2026-04-13

## Problem Statement

AutoCodeRover's SpecRover (2024-2025) demonstrated that pairing buggy code locations with natural-language specifications of their intended behavior improves fix quality by 50%+. The insight is that LLMs fix code far more accurately when told what the code *should* do, not just where the bug is.

Forge's `fg-020-bug-investigator` already performs root cause analysis in two phases (INVESTIGATE + REPRODUCE). It identifies the buggy function, traces call chains, and writes a failing test. However, the output to the implementer is: "Fix function X — it fails test Y." The implementer must independently infer the function's intended behavior from naming, surrounding code, docs, and tests.

**Gap:** The investigator identifies *where* and *how* the bug manifests but does not articulate *what the function should do* as a structured specification. This forces the implementer to spend tokens re-deriving intent, and increases the risk of "fix the symptom, not the contract" patches.

**Competitive context:** SpecRover pairs `{Location, Specification}` and feeds both to the repair agent. Agentless-2.0 uses test-based specification synthesis. Neither operates within a 10-stage pipeline that can learn from specification accuracy over time.

## Proposed Solution

Enhance `fg-020-bug-investigator` Phase 1 (INVESTIGATE) to extract `{Location, Specification}` pairs for each identified buggy function. The specification is a natural-language description of the function's intended contract — inputs, outputs, side effects, invariants, and error conditions. These pairs flow through stage notes to the implementer as structured context.

## Detailed Design

### Architecture

```
fg-020-bug-investigator (Phase 1: INVESTIGATE)
     |
     +-- Root cause analysis (existing)
     +-- Specification inference (NEW)
     |     +-- Source 1: Docstrings / KDoc / JSDoc / rustdoc
     |     +-- Source 2: Existing tests (what they assert)
     |     +-- Source 3: Callers (what they expect)
     |     +-- Source 4: Function name + parameter names (semantic inference)
     |     +-- Source 5: Type signatures / return types
     |     +-- Synthesize: merge sources into specification
     |
     +-- Output: stage notes with Location-Specification pairs
     |
     v
fg-300-implementer
     +-- Reads stage notes
     +-- Each fix target includes: file, function, spec, failing test
     +-- Implements fix against the specification (not just the test)
```

**Key principle:** The specification is synthesized from *existing project evidence* — docs, tests, callers, types, naming. The investigator does not invent behavior; it articulates what the codebase already implies.

### Schema / Data Model

**Location-Specification pair** (embedded in stage notes markdown):

```markdown
### Spec Pair: {function_name}

- **Location:** `{file_path}:{start_line}-{end_line}`
- **Function:** `{qualified_name}` (e.g., `UserService.findByEmail`)
- **Specification:**
  - **Purpose:** {one-sentence summary of what this function should do}
  - **Inputs:** {parameter descriptions with expected types/ranges}
  - **Outputs:** {return value description, including edge cases}
  - **Side effects:** {database writes, events emitted, cache mutations — or "none"}
  - **Invariants:** {conditions that must hold before/after — or "none identified"}
  - **Error conditions:** {what should happen on invalid input, missing data, etc.}
- **Confidence:** HIGH | MEDIUM | LOW
- **Evidence sources:** [docstring, tests, callers, naming, types]
```

**Confidence scoring:**
- HIGH: 3+ evidence sources agree on the specification
- MEDIUM: 2 evidence sources, or sources partially conflict
- LOW: Single source (e.g., function name only), or significant ambiguity

**State tracking** (new fields in stage notes, not state.json):

```markdown
## Specification Inference Summary
- Specs generated: {count}
- High confidence: {count}
- Medium confidence: {count}
- Low confidence: {count}
- Primary evidence source: {most common source type}
```

### Configuration

In `forge-config.md`:

```yaml
# Specification inference for bug fixes (v2.0+)
spec_inference:
  enabled: true           # Enable spec extraction during bug investigation. Default: true.
  min_confidence: MEDIUM   # Minimum confidence to include in stage notes. Default: MEDIUM. Values: HIGH, MEDIUM, LOW.
  max_specs_per_bug: 5    # Cap on spec pairs per bug investigation. Default: 5. Range: 1-10.
  sources:                 # Evidence sources to use (all enabled by default)
    docstrings: true
    tests: true
    callers: true
    naming: true
    types: true
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `spec_inference.enabled` | boolean | `true` | No reason to disable by default; zero overhead when not in bugfix mode |
| `spec_inference.min_confidence` | `HIGH`, `MEDIUM`, `LOW` | `MEDIUM` | LOW-confidence specs may mislead the implementer |
| `spec_inference.max_specs_per_bug` | 1-10 | 5 | Caps token cost of spec section in stage notes |

### Data Flow

**Step-by-step for a typical bugfix:**

1. User runs `/forge-fix Users get 404 on group endpoint`
2. Orchestrator enters bugfix mode, dispatches `fg-020-bug-investigator`
3. Phase 1 (INVESTIGATE): Investigator traces root cause to `GroupController.getGroup()` which calls `GroupRepository.findById()` with wrong ID type
4. **NEW — Specification inference:**
   a. Read `GroupController.getGroup()` docstring: "Returns group by ID. 404 if not found."
   b. Read tests for `getGroup`: assert 200 with valid UUID, assert 404 with unknown UUID
   c. Read callers: frontend calls with UUID string path parameter
   d. Naming: `getGroup(id: String)` — suggests single group retrieval by identifier
   e. Types: takes `String`, returns `GroupResponse` or 404
   f. Synthesize specification: "Given a UUID string, retrieve the group with that ID from the repository and return it as GroupResponse. If no group matches, return 404. The ID parameter is a UUID string, not a numeric ID."
   g. Confidence: HIGH (4 sources agree)
5. Phase 2 (REPRODUCE): Investigator writes failing test (existing behavior)
6. Output stage notes include spec pair with specification
7. Orchestrator passes stage notes to `fg-300-implementer`
8. Implementer reads: "Fix `GroupController.getGroup()` which should: [specification]. Failing test: [test reference]"
9. Implementer fixes the UUID/numeric ID type mismatch, guided by both the spec and the test

**When specification inference adds no value** (and is skipped):
- Function is a trivial getter/setter with no complex behavior
- Root cause is in infrastructure (config error, missing dependency) rather than logic
- Bug is in generated code that should not be manually fixed

### Integration Points

| File | Change |
|---|---|
| `agents/fg-020-bug-investigator.md` | Add Section 3.5 "Specification Inference" between root cause isolation and hypothesis formation. Add spec pair format to stage notes output template. |
| `agents/fg-300-implementer.md` | Add note in Section 3 (Input) about consuming spec pairs from stage notes when present. Prioritize spec-guided fix over test-only fix. |
| `agents/fg-700-retrospective.md` | Track spec accuracy: did the implementer's fix align with the inferred spec? Log discrepancies for learning. |
| `shared/checks/category-registry.json` | Add `SPEC-INFERENCE-LOW` (INFO: low-confidence spec may be inaccurate), `SPEC-INFERENCE-CONFLICT` (WARNING: evidence sources contradict each other) |
| `shared/learnings/` | Spec accuracy data feeds into per-module learnings (e.g., "functions in UserService tend to have HIGH-confidence specs because of thorough KDoc") |
| `modules/frameworks/*/forge-config-template.md` | Add `spec_inference:` section to templates |

### Error Handling

**Failure mode 1: No evidence sources available.**
- Detection: Function has no docstring, no tests, no callers (dead code or entry point)
- Behavior: Skip specification for this function. Log in stage notes: "Spec inference skipped for {function}: no evidence sources available"
- Impact: Implementer operates as before (without spec guidance)

**Failure mode 2: Evidence sources contradict.**
- Detection: Tests assert behavior X, but docstring describes behavior Y
- Behavior: Report `SPEC-INFERENCE-CONFLICT` finding (WARNING). Include both interpretations in the spec pair with a note. Let the implementer decide.
- Learning: Retrospective flags contradictions for future PREEMPT items (e.g., "GroupService docs are stale")

**Failure mode 3: Token budget exceeded.**
- Detection: Specification synthesis would exceed the investigator's output budget
- Behavior: Truncate to `max_specs_per_bug` pairs, prioritize by root cause relevance
- Impact: Some peripheral functions lack specs; only the primary buggy function is guaranteed a spec

**Failure mode 4: Spec inference leads to wrong fix.**
- Detection: Implementer's fix breaks other tests, or user rejects the fix
- Behavior: Post-run feedback captures "spec inaccuracy" as a learning. Retrospective reduces confidence for that function/module pattern.

## Performance Characteristics

**Token overhead per bug investigation:**

| Component | Additional Tokens | Notes |
|---|---|---|
| Read docstrings | 50-200 | Already partially read during investigation |
| Read test assertions | 100-500 | Focused extraction, not full test file |
| Read callers | 100-400 | Top 3-5 callers only |
| Synthesize specification | 200-500 | LLM generation of structured spec |
| Stage notes output | 100-300 | Per spec pair in output |
| **Total per spec pair** | **550-1,900** | |
| **Total per investigation (3 pairs avg)** | **1,650-5,700** | Well within investigator's token budget |

**Net benefit:** If spec-guided fixes reduce implementer fix loops by even 1 iteration (conservative), the savings of 2,000-8,000 tokens per iteration far exceed the 1,650-5,700 token investment.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Category registration:** `category-registry.json` contains `SPEC-INFERENCE-LOW` and `SPEC-INFERENCE-CONFLICT`
2. **Config template:** All `forge-config-template.md` files include `spec_inference:` section
3. **Agent update:** `fg-020-bug-investigator.md` contains "Specification Inference" section

### Unit Tests (`tests/unit/`)

1. **`spec-inference.bats`:**
   - Spec pair format validates against expected markdown structure
   - Confidence scoring: 3+ sources = HIGH, 2 = MEDIUM, 1 = LOW
   - `min_confidence: HIGH` filters out MEDIUM and LOW specs
   - `max_specs_per_bug: 1` limits output to single spec pair
   - Config disabled: `spec_inference.enabled: false` skips inference entirely

### Scenario Tests (`tests/scenario/`)

1. **`bugfix-with-spec.bats`:**
   - Full bugfix pipeline produces stage notes with spec pairs
   - Implementer references spec in its stage notes
   - Retrospective includes spec accuracy tracking

## Acceptance Criteria

1. Bug investigations in bugfix mode produce `{Location, Specification}` pairs in stage notes
2. Each specification includes purpose, inputs, outputs, side effects, invariants, and error conditions
3. Confidence levels (HIGH/MEDIUM/LOW) accurately reflect evidence source count and agreement
4. The implementer's stage notes reference the specification when available
5. Specification inference can be disabled via `spec_inference.enabled: false`
6. LOW-confidence specs are excluded by default (`min_confidence: MEDIUM`)
7. Token overhead per investigation is under 6,000 tokens for 3 spec pairs
8. Evidence source contradictions produce `SPEC-INFERENCE-CONFLICT` findings
9. Retrospective tracks spec accuracy for learning
10. Non-bugfix pipeline modes are unaffected (spec inference only runs in bugfix mode)

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** Spec inference is additive to the bug investigator's existing output.
2. **Stage notes format:** Existing stage notes consumers (orchestrator, implementer) ignore sections they don't recognize. The spec pair sections are new markdown headers that existing agents skip.
3. **Config:** New `spec_inference:` section added to config templates with `enabled: true` default. Existing configs without this section use defaults.
4. **Category registry:** Two new finding codes added. Existing scoring formula unchanged (these are INFO/WARNING findings within existing weight system).

## Dependencies

**This feature depends on:**
- `fg-020-bug-investigator` Phase 1 root cause analysis (already produces function-level locations)
- Stage notes inter-agent communication (already supported via `shared/agent-communication.md`)
- `shared/checks/category-registry.json` (for new finding categories)

**Other features that benefit from this:**
- F18 (Next-Task Prediction): spec accuracy data enriches prediction confidence
- Property-based test generation (F13): inferred specs suggest properties to test
