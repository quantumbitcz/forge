---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "ng-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-001"
  - id: "ng-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["state", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-002"
  - id: "ng-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["rendering", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-003"
  - id: "ng-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["dependency-injection", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-004"
  - id: "ng-preempt-005"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["state", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-005"
  - id: "ng-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["state", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-006"
  - id: "ng-preempt-007"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["routing", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-007"
  - id: "ng-preempt-008"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["rendering", "angular"]
    source: "cross-project"
    archived: false
    body_ref: "ng-preempt-008"
  - id: "common-pitfalls"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["angular"]
    source: "cross-project"
    archived: false
    body_ref: "common-pitfalls"
  - id: "effective-patterns"
    base_confidence: 0.75
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.699156Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["angular"]
    source: "cross-project"
    archived: false
    body_ref: "effective-patterns"
---
# Cross-Project Learnings: angular

## PREEMPT items

### NG-PREEMPT-001: Standalone component imports must include all transitive dependencies
<a id="ng-preempt-001"></a>
- **Domain:** build
- **Pattern:** Standalone components require every dependency in their `imports` array — unlike NgModules there is no implicit transitive resolution. Missing imports cause runtime template errors not caught by `ng build` in some configurations.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-002: toSignal() from Observables needs an initial value or undefined handling
<a id="ng-preempt-002"></a>
- **Domain:** state
- **Pattern:** `toSignal(obs$)` returns `Signal<T | undefined>` unless `initialValue` is provided. Forgetting this causes template null errors when the signal is consumed before the first emission.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-003: OnPush components with impure function calls in templates silently break
<a id="ng-preempt-003"></a>
- **Domain:** rendering
- **Pattern:** Calling functions that depend on mutable external state inside OnPush templates produces stale UI. Use `computed()` signals or pipes instead of template function calls for derived values.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-004: inject() only works in injection context — not in callbacks or setTimeout
<a id="ng-preempt-004"></a>
- **Domain:** dependency-injection
- **Pattern:** `inject()` must be called synchronously during constructor, factory, or field initializer. Calling it inside `setTimeout`, `Promise.then`, or event callbacks throws NG0203. Move inject calls to field declarations.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-005: NgRx SignalStore patchState must use immutable updates
<a id="ng-preempt-005"></a>
- **Domain:** state
- **Pattern:** `patchState(store, { items: [...store.items(), newItem] })` works correctly. Mutating arrays in place (push/splice) and then calling patchState does not trigger change detection because the reference has not changed.
- **Confidence:** MEDIUM
- **Hit count:** 0

### NG-PREEMPT-006: effect() runs during change detection — side effects must not trigger additional changes
<a id="ng-preempt-006"></a>
- **Domain:** state
- **Pattern:** Writing to a signal inside `effect()` creates an infinite loop (signal change triggers effect which changes signal). Use `untracked()` to write signals inside effects or restructure as `computed()`.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-007: Lazy-loaded routes lose providers if not using route-level providers array
<a id="ng-preempt-007"></a>
- **Domain:** routing
- **Pattern:** Services provided in a lazy-loaded standalone component are scoped to that component, not to the route. Use the `providers` array in the route config or a dedicated `provideXxx()` function for route-scoped singletons.
- **Confidence:** MEDIUM
- **Hit count:** 0

### NG-PREEMPT-008: @defer blocks require explicit trigger or they render immediately
<a id="ng-preempt-008"></a>
- **Domain:** rendering
- **Pattern:** `@defer` without a trigger condition (e.g., `on viewport`, `on interaction`, `when condition`) renders the content immediately, defeating the purpose. Always specify an explicit trigger.
- **Confidence:** MEDIUM
- **Hit count:** 0

## Standalone/Signals Variant Learnings

### Common Pitfalls
<a id="common-pitfalls"></a>
<!-- Populated by retrospective agent: signal migration issues, NgModule interop -->

### Effective Patterns
<a id="effective-patterns"></a>
<!-- Populated by retrospective agent -->
