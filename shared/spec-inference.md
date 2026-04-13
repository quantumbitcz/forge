# Specification Inference

v2.0+ — Function-level specification extraction for bug investigations.

## Purpose

During bugfix mode, `fg-020-bug-investigator` extracts `{Location, Specification}` pairs for each identified buggy function. The specification articulates *what the function should do* based on existing project evidence, giving `fg-300-implementer` structured intent alongside the failing test.

**Key principle:** Specifications are synthesized from existing project evidence — docs, tests, callers, types, naming. The investigator does not invent behavior; it articulates what the codebase already implies.

## Evidence Sources

Sources are consulted in priority order. Each source that provides information about the function's behavior contributes to the specification.

| Priority | Source | What It Provides | Token Cost |
|----------|--------|------------------|------------|
| 1 | Docstrings (KDoc, JSDoc, rustdoc, etc.) | Purpose, parameters, return value, exceptions | 50-200 |
| 2 | Existing tests | Expected inputs, outputs, edge cases, error handling | 100-500 |
| 3 | Callers (top 3-5) | What callers pass, what they expect back | 100-400 |
| 4 | Naming (function + parameters) | Semantic inference of purpose | 0 (already read) |
| 5 | Type signatures | Parameter types, return types, nullability, generics | 0 (already read) |

## Confidence Scoring

Confidence reflects how many evidence sources agree on the specification and whether they conflict.

| Level | Criteria | Implication |
|-------|----------|-------------|
| HIGH | 3+ evidence sources agree on the specification | Strong signal — implementer should trust and follow |
| MEDIUM | 2 evidence sources, or sources partially conflict | Useful guidance — implementer should verify against codebase |
| LOW | Single source (e.g., function name only), or significant ambiguity | Weak signal — may mislead. Excluded by default (`min_confidence: MEDIUM`) |

## Spec Pair Schema

Each pair is embedded in the investigator's stage notes as structured markdown:

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

## Integration with Implementer

When `fg-300-implementer` receives stage notes containing spec pairs:

1. Read each spec pair for the fix target(s)
2. Prioritize spec-guided fix over test-only fix — the spec describes the intended contract, the test confirms one symptom
3. If the spec and the failing test suggest different fixes, follow the spec (the test covers one case; the spec covers the contract)
4. Reference the spec in the implementer's own stage notes to enable retrospective tracking

## Finding Categories

| Code | Severity | Trigger | Impact |
|------|----------|---------|--------|
| `SPEC-INFERENCE-LOW` | INFO | A spec pair was generated with LOW confidence | Informational — warns implementer that guidance may be inaccurate |
| `SPEC-INFERENCE-CONFLICT` | WARNING | Evidence sources contradict each other (e.g., tests assert X, docstring says Y) | Includes both interpretations. Retrospective flags contradictions as stale-doc PREEMPT candidates |

## Configuration

```yaml
spec_inference:
  enabled: true           # Enable spec extraction during bug investigation. Default: true.
  min_confidence: MEDIUM   # Minimum confidence to include in stage notes. Values: HIGH, MEDIUM, LOW.
  max_specs_per_bug: 5    # Cap on spec pairs per investigation. Range: 1-10.
  sources:                 # Evidence sources to use (all enabled by default)
    docstrings: true
    tests: true
    callers: true
    naming: true
    types: true
```

## When Specification Inference Is Skipped

- `spec_inference.enabled: false` in config
- Pipeline mode is not bugfix (spec inference only runs in bugfix mode)
- Function is a trivial getter/setter with no complex behavior
- Root cause is infrastructure (config error, missing dependency) rather than logic
- Bug is in generated code
- No evidence sources available for the function

## Error Handling

| Failure Mode | Detection | Behavior |
|---|---|---|
| No evidence sources | Function has no docstring, no tests, no callers | Skip function, log in stage notes |
| Sources contradict | Tests assert X, docstring describes Y | Report `SPEC-INFERENCE-CONFLICT`, include both interpretations |
| Token budget exceeded | Synthesis would exceed investigator output budget | Truncate to `max_specs_per_bug`, prioritize by root cause relevance |
| Spec leads to wrong fix | Implementer's fix breaks other tests or user rejects | Post-run feedback captures "spec inaccuracy" as a learning |

## Performance

Total overhead per investigation (3 spec pairs average): 1,650-5,700 tokens. Well within the investigator's token budget. Net benefit: if spec-guided fixes reduce implementer iterations by even one cycle, the savings (2,000-8,000 tokens) exceed the investment.

## Learning Integration

The retrospective agent (`fg-700-retrospective`) tracks spec accuracy:
- Did the implementer's fix align with the inferred spec?
- Were any specs contradicted by the final fix?
- Discrepancies feed into per-module learnings (e.g., "functions in UserService tend to have HIGH-confidence specs because of thorough KDoc")
- Contradictions become PREEMPT candidates for stale documentation
