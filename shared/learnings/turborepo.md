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
    first_seen: "2026-04-20T10:37:16.825244Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "turborepo"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-001"
  - id: "ks-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.825244Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["configuration", "turborepo"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-002"
  - id: "ks-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.825244Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "turborepo"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-003"
---
# Cross-Project Learnings: turborepo

## PREEMPT items

### KS-PREEMPT-001: Undeclared env vars cause cache poisoning
<a id="ks-preempt-001"></a>
- **Domain:** build
- **Pattern:** Environment variables that affect build output must be declared in turbo.json `env` or `globalEnv`. Undeclared vars produce cache hits that return output built with different environment values.
- **Applies when:** `build_system: turborepo`
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-002: pipeline renamed to tasks in Turbo 2.0
<a id="ks-preempt-002"></a>
- **Domain:** configuration
- **Pattern:** The `pipeline` key in turbo.json was renamed to `tasks` in Turborepo 2.0. Using the old key silently falls back to defaults.
- **Applies when:** `build_system: turborepo` and Turborepo version >= 2.0
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-003: outputs required for cache correctness
<a id="ks-preempt-003"></a>
- **Domain:** build
- **Pattern:** Tasks without `outputs` in turbo.json cannot have their results cached. This is commonly missed for test tasks that produce coverage reports.
- **Applies when:** `build_system: turborepo`
- **Confidence:** HIGH
- **Hit count:** 0
