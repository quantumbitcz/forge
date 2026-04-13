# Q10: Coordinator Structured Output

## Status
DRAFT — 2026-04-13

## Problem Statement

Three coordinator agents produce Markdown prose output that downstream consumers must parse with custom logic:

- **fg-400-quality-gate:** Outputs a Markdown report with findings, score, verdict, batch results, and dedup stats. The retrospective (fg-700) and post-run agent (fg-710) parse this report to extract score history, finding categories, and agent effectiveness metrics.

- **fg-500-test-gate:** Outputs a Markdown report with test results, duration, coverage metrics, and flaky test detection. The orchestrator parses this to determine convergence phase transitions (Phase A pass/fail, Phase B pass/fail).

- **fg-700-retrospective:** Outputs a Markdown report with learnings, config change proposals, agent effectiveness scores, and trend comparisons. The post-run agent (fg-710) and future `/forge-insights` queries parse this for analytics.

**The core problem:** Markdown prose parsing is fragile. Each consumer implements its own regex/pattern matching to extract structured data from free-form text. When an agent's output format changes slightly (e.g., adding a new section, changing a heading), downstream parsers break silently -- they extract partial data or miss fields entirely. This manifests as:

- Retrospective missing score history entries (incomplete trend analysis)
- Orchestrator misclassifying test results (incorrect convergence transitions)
- Insights dashboard showing gaps in agent effectiveness data

The forge system already uses structured formats elsewhere: `state.json` (JSON), `evidence.json` (JSON), decision log (JSONL), automation log (JSONL). Coordinators are the last major prose-only output producers.

## Target
Eliminate fragile Markdown parsing for coordinator outputs. Enable reliable machine consumption while preserving human-readable Markdown for the UI.

## Detailed Changes

### 1. Structured Output Block Standard

Define a standard mechanism for embedding machine-readable JSON within Markdown output. The JSON is wrapped in an HTML comment so it is invisible in rendered Markdown but trivially extractable by consumers.

**Format:**

```markdown
<!-- FORGE_STRUCTURED_OUTPUT
{
  "schema": "coordinator-output/v1",
  "agent": "fg-400-quality-gate",
  "timestamp": "2026-04-13T10:00:00Z",
  ...agent-specific fields...
}
-->
```

**Extraction algorithm:**

```python
import re, json

def extract_structured_output(markdown_text):
    """Extract FORGE_STRUCTURED_OUTPUT from coordinator Markdown output."""
    pattern = r'<!-- FORGE_STRUCTURED_OUTPUT\n(.*?)\n-->'
    match = re.search(pattern, markdown_text, re.DOTALL)
    if match:
        return json.loads(match.group(1))
    return None  # Trigger fallback to Markdown parsing
```

**Placement rule:** The structured output block MUST appear at the end of the coordinator's Markdown output, after all human-readable sections. This ensures the Markdown is complete and readable even if the structured block is stripped. Agents that truncate output due to token limits should prioritize the structured block over trailing Markdown prose.

**Schema versioning:** The `schema` field enables forward compatibility. Consumers check the schema version before parsing. Unknown schema versions trigger fallback to Markdown parsing.

### 2. Per-Coordinator Schemas

#### 2.1 fg-400-quality-gate Output Schema

```json
{
  "schema": "coordinator-output/v1",
  "agent": "fg-400-quality-gate",
  "timestamp": "2026-04-13T10:00:00Z",
  "verdict": "CONCERNS",
  "score": {
    "current": 72,
    "target": 90,
    "effective_target": 88,
    "unfixable_info_count": 1
  },
  "findings_summary": {
    "total": 12,
    "deduplicated": 8,
    "by_severity": {
      "CRITICAL": 0,
      "WARNING": 5,
      "INFO": 3
    },
    "by_confidence": {
      "HIGH": 4,
      "MEDIUM": 3,
      "LOW": 1
    },
    "by_category_prefix": {
      "ARCH": 2,
      "SEC": 1,
      "CONV": 3,
      "QUAL": 1,
      "DOC": 1
    }
  },
  "batches": [
    {
      "batch_id": 1,
      "agents_dispatched": ["fg-410-code-reviewer", "fg-411-security-reviewer", "fg-416-backend-performance-reviewer"],
      "agents_completed": ["fg-410-code-reviewer", "fg-411-security-reviewer", "fg-416-backend-performance-reviewer"],
      "agents_timed_out": [],
      "raw_findings": 10,
      "duration_ms": 45000
    },
    {
      "batch_id": 2,
      "agents_dispatched": ["fg-412-architecture-reviewer", "fg-418-docs-consistency-reviewer"],
      "agents_completed": ["fg-412-architecture-reviewer", "fg-418-docs-consistency-reviewer"],
      "agents_timed_out": [],
      "raw_findings": 5,
      "duration_ms": 32000
    }
  ],
  "dedup_stats": {
    "pre_dedup_count": 15,
    "post_dedup_count": 8,
    "duplicates_removed": 7,
    "scout_findings_separated": 2
  },
  "cycle_info": {
    "quality_cycles": 2,
    "score_history": [65, 72],
    "dip_count": 0,
    "oscillation_detected": false
  },
  "reviewer_agreement": {
    "conflicting_findings": 0,
    "deliberation_triggered": false
  },
  "coverage_gaps": []
}
```

**Field reference:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `verdict` | enum | Yes | `PASS`, `CONCERNS`, or `FAIL` |
| `score.current` | integer | Yes | Final deduplicated score |
| `score.target` | integer | Yes | Configured target score |
| `score.effective_target` | integer | Yes | Target after INFO efficiency adjustment |
| `score.unfixable_info_count` | integer | Yes | Number of persistent INFO findings excluded from target |
| `findings_summary.total` | integer | Yes | Total raw findings before dedup |
| `findings_summary.deduplicated` | integer | Yes | Findings after dedup |
| `findings_summary.by_severity` | object | Yes | Count per severity level |
| `findings_summary.by_confidence` | object | Yes | Count per confidence level |
| `findings_summary.by_category_prefix` | object | Yes | Count per category prefix (top-level only) |
| `batches[]` | array | Yes | Per-batch execution details |
| `dedup_stats` | object | Yes | Deduplication metrics |
| `cycle_info` | object | Yes | Inner-cycle convergence data |
| `coverage_gaps[]` | array | Yes | REVIEW-GAP findings (timed out agents) |

#### 2.2 fg-500-test-gate Output Schema

```json
{
  "schema": "coordinator-output/v1",
  "agent": "fg-500-test-gate",
  "timestamp": "2026-04-13T10:05:00Z",
  "phase_a": {
    "build": {
      "command": "npm run build",
      "exit_code": 0,
      "duration_ms": 4200,
      "passed": true
    },
    "lint": {
      "command": "npm run lint",
      "exit_code": 0,
      "duration_ms": 1800,
      "passed": true
    },
    "is_phase_a_failure": false
  },
  "phase_b": {
    "tests": {
      "command": "npm test",
      "exit_code": 0,
      "total": 142,
      "passed": 142,
      "failed": 0,
      "skipped": 3,
      "duration_ms": 18500,
      "tests_pass": true
    },
    "analysis": {
      "agents_dispatched": ["pr-review-toolkit:pr-test-analyzer"],
      "agents_completed": ["pr-review-toolkit:pr-test-analyzer"],
      "critical_findings": 0,
      "analysis_pass": true
    },
    "flaky_tests": {
      "detected": false,
      "tests": []
    },
    "coverage": {
      "available": true,
      "line_coverage_pct": 87.3,
      "branch_coverage_pct": 72.1,
      "uncovered_files": ["src/utils/legacy.ts"]
    }
  },
  "mutation_testing": {
    "enabled": false,
    "mutants_generated": 0,
    "mutants_killed": 0,
    "mutants_survived": 0,
    "mutation_score_pct": null
  },
  "verdict": {
    "tests_pass": true,
    "analysis_pass": true,
    "is_phase_a_failure": false,
    "proceed_to": "REVIEWING"
  }
}
```

**Field reference:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `phase_a.is_phase_a_failure` | boolean | Yes | True if build or lint failed |
| `phase_b.tests.tests_pass` | boolean | Yes | True if all tests pass |
| `phase_b.analysis.analysis_pass` | boolean | Yes | True if no CRITICAL analysis findings |
| `phase_b.flaky_tests.detected` | boolean | Yes | True if test flickering detected |
| `phase_b.coverage` | object | No | Present when coverage tools are configured |
| `mutation_testing` | object | No | Present when mutation testing is enabled |
| `verdict` | object | Yes | Summarized verdict for orchestrator consumption |
| `verdict.proceed_to` | string | Yes | Next pipeline state (`REVIEWING`, `IMPLEMENTING`, `ESCALATED`) |

#### 2.3 fg-700-retrospective Output Schema

```json
{
  "schema": "coordinator-output/v1",
  "agent": "fg-700-retrospective",
  "timestamp": "2026-04-13T10:30:00Z",
  "run_summary": {
    "mode": "standard",
    "total_iterations": 5,
    "total_retries": 3,
    "wall_time_seconds": 340,
    "final_score": 94,
    "final_verdict": "PASS",
    "convergence_phase_reached": "safety_gate"
  },
  "learnings": {
    "extracted": [
      {
        "type": "preempt",
        "description": "Spring @Transactional on query methods should use readOnly=true",
        "source": "auto-discovered",
        "confidence": "MEDIUM",
        "category": "CONV-TX"
      }
    ],
    "promoted": [],
    "archived": [],
    "total_active": 15
  },
  "config_changes": {
    "proposed": [
      {
        "field": "convergence.target_score",
        "current": 90,
        "proposed": 95,
        "rationale": "Last 3 runs achieved 94+ consistently",
        "locked": false
      }
    ],
    "applied": [],
    "blocked_by_lock": []
  },
  "agent_effectiveness": [
    {
      "agent_id": "fg-410-code-reviewer",
      "findings_reported": 8,
      "findings_after_dedup": 5,
      "findings_fixed": 4,
      "fix_rate_pct": 80.0,
      "average_confidence": "HIGH",
      "false_positive_estimate": 0
    },
    {
      "agent_id": "fg-411-security-reviewer",
      "findings_reported": 2,
      "findings_after_dedup": 2,
      "findings_fixed": 2,
      "fix_rate_pct": 100.0,
      "average_confidence": "HIGH",
      "false_positive_estimate": 0
    }
  ],
  "trend_comparison": {
    "runs_compared": 5,
    "score_trend": [78, 82, 88, 91, 94],
    "iteration_trend": [8, 7, 6, 5, 5],
    "recurring_categories": ["CONV-NAMING", "TEST-EDGE-MISSING"],
    "improving_categories": ["ARCH-BOUNDARY", "SEC-AUTH"]
  },
  "approach_accumulations": {
    "new_this_run": [],
    "escalated_to_convention": []
  }
}
```

**Field reference:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `run_summary` | object | Yes | High-level run metrics |
| `learnings.extracted[]` | array | Yes | New PREEMPT items discovered this run |
| `learnings.promoted[]` | array | Yes | Items promoted from MEDIUM to HIGH confidence |
| `learnings.archived[]` | array | Yes | Items that decayed to ARCHIVED |
| `config_changes.proposed[]` | array | Yes | Config auto-tune proposals |
| `config_changes.applied[]` | array | Yes | Changes actually written to forge-config.md |
| `config_changes.blocked_by_lock[]` | array | Yes | Changes blocked by `<!-- locked -->` fences |
| `agent_effectiveness[]` | array | Yes | Per-reviewer agent metrics |
| `trend_comparison` | object | No | Present when 2+ previous runs exist for comparison |
| `approach_accumulations` | object | Yes | APPROACH-* finding accumulation status |

### 3. Consumer Integration

#### 3.1 Orchestrator (fg-100) Consuming Test Gate Output

**Current:** Orchestrator parses test gate Markdown to determine `tests_pass`, `analysis_pass`, and `is_phase_a_failure` for convergence engine input.

**New:** Orchestrator extracts structured output first:

```
1. Receive fg-500-test-gate output (Markdown string)
2. Call extract_structured_output(output)
3. If structured block found:
   a. Read verdict.tests_pass, verdict.analysis_pass, verdict.is_phase_a_failure
   b. Pass directly to convergence engine
4. If structured block NOT found (backward compatibility):
   a. Fall back to existing Markdown parsing
   b. Log WARNING: "fg-500-test-gate did not include structured output, using Markdown fallback"
```

#### 3.2 Orchestrator Consuming Quality Gate Output

**Current:** Orchestrator parses quality gate Markdown to determine score, verdict, and findings for convergence engine.

**New:** Orchestrator extracts structured output:

```
1. Receive fg-400-quality-gate output
2. Extract structured block
3. If found:
   a. Read score.current, verdict, cycle_info.score_history
   b. Read findings_summary for convergence evaluation
   c. Pass to convergence engine as review_result
4. If not found:
   a. Fall back to existing Markdown parsing
   b. Log WARNING
```

#### 3.3 Retrospective Consuming Quality Gate and Test Gate Output

**Current:** Retrospective reads stage notes (which contain coordinator Markdown output) and parses them for trend analysis.

**New:** Retrospective reads structured output from stage notes:

```
1. Read stage_5_notes (VERIFY) and stage_6_notes (REVIEW)
2. For each note, extract FORGE_STRUCTURED_OUTPUT block
3. If found: use structured data directly for effectiveness analysis
4. If not found: fall back to Markdown parsing of stage notes
```

#### 3.4 Post-Run (fg-710) Consuming Retrospective Output

**Current:** Post-run agent parses retrospective Markdown for timeline and recap generation.

**New:** Post-run extracts structured output from retrospective:

```
1. Receive fg-700-retrospective output (or read stage_9_notes)
2. Extract structured block
3. Use run_summary, agent_effectiveness, trend_comparison for timeline
4. Fall back to Markdown parsing if block not found
```

### 4. Backward Compatibility

The structured output block is **additive** -- it does not replace the Markdown output. Coordinators continue to produce their full Markdown report for human readability in the Claude Code UI. The structured block is appended at the end.

**Rollout strategy:**

1. **Phase 1 (this spec):** Add structured output blocks to all three coordinators. Add extraction logic to consumers with Markdown fallback.
2. **Phase 2 (future):** Once all consumers are using structured output reliably (no fallback warnings in 5+ consecutive runs), the Markdown parsing code can be simplified to presentation-only (not data extraction).

**Agent output size impact:** The structured JSON block adds approximately 500-2000 tokens per coordinator invocation. This is within the existing stage notes budget (2000 tokens per stage). If the combined Markdown + JSON exceeds the budget, the coordinator should compress the Markdown prose (shorter descriptions, fewer examples) rather than omitting the structured block.

### 5. Contract Test

**New file:** `tests/contract/coordinator-output.bats`

Validates that coordinator agent files declare structured output in their contract.

```bash
@test "fg-400-quality-gate declares structured output in agent md" {
  grep -q 'FORGE_STRUCTURED_OUTPUT' "$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
}

@test "fg-500-test-gate declares structured output in agent md" {
  grep -q 'FORGE_STRUCTURED_OUTPUT' "$PLUGIN_ROOT/agents/fg-500-test-gate.md"
}

@test "fg-700-retrospective declares structured output in agent md" {
  grep -q 'FORGE_STRUCTURED_OUTPUT' "$PLUGIN_ROOT/agents/fg-700-retrospective.md"
}
```

**New file:** `shared/schemas/coordinator-output-v1.json`

A JSON schema that the structured output blocks must conform to. The contract test validates sample outputs against this schema.

```bash
@test "quality gate sample output validates against schema" {
  python3 -c "
import json
with open('$PLUGIN_ROOT/shared/schemas/coordinator-output-v1.json') as f:
    schema = json.load(f)
# Validate required fields for quality gate
qg = schema['definitions']['quality-gate']
required = qg.get('required', [])
assert 'verdict' in required
assert 'score' in required
assert 'findings_summary' in required
"
}
```

## Testing Approach

1. **Schema validation test:** Validate `coordinator-output-v1.json` is well-formed and covers all three coordinator schemas.

2. **Extraction test:** Unit test for `extract_structured_output()` with:
   - Valid Markdown + structured block -> returns JSON
   - Valid Markdown without structured block -> returns None
   - Malformed JSON in structured block -> returns None (triggers fallback)
   - Multiple structured blocks -> returns first one (edge case)

3. **Agent output test:** Verify agent `.md` files reference the structured output format.

4. **Integration test:** Dry-run pipeline and verify structured blocks appear in stage notes.

5. **Backward compatibility test:** Verify consumers still function when structured block is absent (Markdown fallback).

## Acceptance Criteria

- [ ] `FORGE_STRUCTURED_OUTPUT` standard is documented in a new `shared/coordinator-output.md` file
- [ ] Extraction algorithm is provided in both Python and bash (for script consumers)
- [ ] fg-400-quality-gate agent md includes structured output block specification
- [ ] fg-500-test-gate agent md includes structured output block specification
- [ ] fg-700-retrospective agent md includes structured output block specification
- [ ] Each coordinator schema defines all required fields with types and descriptions
- [ ] Orchestrator uses structured output for convergence engine input (with Markdown fallback)
- [ ] Retrospective uses structured output for trend analysis (with Markdown fallback)
- [ ] Post-run uses structured output for timeline generation (with Markdown fallback)
- [ ] Fallback to Markdown parsing logs WARNING (observable degradation)
- [ ] `shared/schemas/coordinator-output-v1.json` exists and validates all three schemas
- [ ] `tests/contract/coordinator-output.bats` exists and passes
- [ ] Stage notes token budget is respected (structured block included in 2000-token cap)

## Effort Estimate

Large (4-5 days). Requires changes to 3 coordinator agent files and 4 consumer integration points.

- Standard definition + shared doc: 0.5 day
- Quality gate schema + agent md update: 1 day
- Test gate schema + agent md update: 0.5 day
- Retrospective schema + agent md update: 1 day
- Consumer integration (orchestrator, retrospective, post-run): 1 day
- JSON schema + contract tests: 0.5 day
- Integration testing: 0.5 day

## Dependencies

- Q06 (core contract refinements) defines the MEDIUM confidence multiplier change. The quality gate structured output schema includes `findings_summary.by_confidence` which must reflect the updated multiplier semantics.
- Q09 (config validation) defines JSON schema patterns that should be consistent with coordinator output schemas (same `$schema` conventions, same validation approach).
- No blocking dependencies -- all three coordinator agents can be updated independently.
- The standard should be established first (`shared/coordinator-output.md` + schemas), then agents updated, then consumers integrated.
