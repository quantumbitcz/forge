---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "ks-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.814229Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "spring"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-001"
  - id: "ks-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.814229Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "spring"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-002"
  - id: "ks-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.814229Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["domain", "spring"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-003"
---
# Cross-Project Learnings: spring

## PREEMPT items

### KS-PREEMPT-001: R2DBC updates all columns
<a id="ks-preempt-001"></a>
- **Domain:** persistence
- **Pattern:** R2DBC update adapters must fetch-then-set to preserve @CreatedDate/@LastModifiedDate
- **Applies when:** `persistence: r2dbc`
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-002: Generated OpenAPI sources excluded from detekt
<a id="ks-preempt-002"></a>
- **Domain:** build
- **Pattern:** Detekt globs don't work with srcDir-added generated sources — use post-eval exclusion
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-003: Kotlin core must use kotlin.uuid.Uuid not java.util.UUID
<a id="ks-preempt-003"></a>
- **Domain:** domain
- **Pattern:** Core module uses Kotlin types; persistence layer uses Java types. Never mix.
- **Confidence:** HIGH
- **Hit count:** 0
# Cross-Project Learnings: spring (Java variant)

## PREEMPT items
