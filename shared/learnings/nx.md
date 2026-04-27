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
    first_seen: "2026-04-20T10:37:16.781329Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "nx"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-001"
  - id: "ks-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.781329Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["dependencies", "nx"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-002"
  - id: "ks-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.781329Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["architecture", "nx"]
    source: "cross-project"
    archived: false
    body_ref: "#ks-preempt-003"
---
# Cross-Project Learnings: nx

## PREEMPT items

### KS-PREEMPT-001: Nx affected requires --base in CI
<a id="ks-preempt-001"></a>
- **Domain:** build
- **Pattern:** CI pipelines using `nx affected` must pass `--base=origin/main` explicitly — the default base ref may not match the PR target branch
- **Applies when:** `build_system: nx` and CI pipeline
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-002: @nrwl packages renamed to @nx
<a id="ks-preempt-002"></a>
- **Domain:** dependencies
- **Pattern:** All `@nrwl/*` packages were renamed to `@nx/*` in Nx 16. Mixed `@nrwl` and `@nx` imports cause version resolution failures.
- **Applies when:** `build_system: nx` and Nx version >= 16
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-003: Module boundary tags must be non-empty
<a id="ks-preempt-003"></a>
- **Domain:** architecture
- **Pattern:** Empty `tags: []` in project.json disables module boundary enforcement for that project. Every project must have at least type and scope tags.
- **Applies when:** `build_system: nx` with `@nx/enforce-module-boundaries`
- **Confidence:** HIGH
- **Hit count:** 0
