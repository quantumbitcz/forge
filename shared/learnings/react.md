---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "rv-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.796175Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "react"]
    source: "cross-project"
    archived: false
    body_ref: "#rv-preempt-001"
  - id: "rv-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.796175Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["styling", "react"]
    source: "cross-project"
    archived: false
    body_ref: "#rv-preempt-002"
  - id: "rv-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.796175Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["styling", "react"]
    source: "cross-project"
    archived: false
    body_ref: "#rv-preempt-003"
  - id: "common-pitfalls"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.796175Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["react"]
    source: "cross-project"
    archived: false
    body_ref: "#common-pitfalls"
  - id: "effective-patterns"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.796175Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["react"]
    source: "cross-project"
    archived: false
    body_ref: "#effective-patterns"
---
# Cross-Project Learnings: react

## PREEMPT items

### RV-PREEMPT-001: Always check TypeScript compiles after component changes
<a id="rv-preempt-001"></a>
- **Domain:** build
- **Pattern:** Run tsc --noEmit before writing tests to catch type errors early
- **Confidence:** HIGH
- **Hit count:** 0

### RV-PREEMPT-002: Typography uses inline style, not Tailwind text-* classes
<a id="rv-preempt-002"></a>
- **Domain:** styling
- **Pattern:** Use style={{ fontSize: '...' }} instead of text-sm/text-lg classes
- **Confidence:** HIGH
- **Hit count:** 0

### RV-PREEMPT-003: Colors must use theme tokens, never hardcoded hex
<a id="rv-preempt-003"></a>
- **Domain:** styling
- **Pattern:** Use bg-background, text-foreground, etc. from theme.css custom properties
- **Confidence:** HIGH
- **Hit count:** 0

## TypeScript Variant Learnings

### Common Pitfalls
<a id="common-pitfalls"></a>
<!-- Populated by retrospective agent -->

### Effective Patterns
<a id="effective-patterns"></a>
<!-- Populated by retrospective agent -->
