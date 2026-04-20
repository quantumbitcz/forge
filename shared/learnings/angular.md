---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: angular

## PREEMPT items

### NG-PREEMPT-001: Standalone component imports must include all transitive dependencies
- **Domain:** build
- **Pattern:** Standalone components require every dependency in their `imports` array — unlike NgModules there is no implicit transitive resolution. Missing imports cause runtime template errors not caught by `ng build` in some configurations.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-002: toSignal() from Observables needs an initial value or undefined handling
- **Domain:** state
- **Pattern:** `toSignal(obs$)` returns `Signal<T | undefined>` unless `initialValue` is provided. Forgetting this causes template null errors when the signal is consumed before the first emission.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-003: OnPush components with impure function calls in templates silently break
- **Domain:** rendering
- **Pattern:** Calling functions that depend on mutable external state inside OnPush templates produces stale UI. Use `computed()` signals or pipes instead of template function calls for derived values.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-004: inject() only works in injection context — not in callbacks or setTimeout
- **Domain:** dependency-injection
- **Pattern:** `inject()` must be called synchronously during constructor, factory, or field initializer. Calling it inside `setTimeout`, `Promise.then`, or event callbacks throws NG0203. Move inject calls to field declarations.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-005: NgRx SignalStore patchState must use immutable updates
- **Domain:** state
- **Pattern:** `patchState(store, { items: [...store.items(), newItem] })` works correctly. Mutating arrays in place (push/splice) and then calling patchState does not trigger change detection because the reference has not changed.
- **Confidence:** MEDIUM
- **Hit count:** 0

### NG-PREEMPT-006: effect() runs during change detection — side effects must not trigger additional changes
- **Domain:** state
- **Pattern:** Writing to a signal inside `effect()` creates an infinite loop (signal change triggers effect which changes signal). Use `untracked()` to write signals inside effects or restructure as `computed()`.
- **Confidence:** HIGH
- **Hit count:** 0

### NG-PREEMPT-007: Lazy-loaded routes lose providers if not using route-level providers array
- **Domain:** routing
- **Pattern:** Services provided in a lazy-loaded standalone component are scoped to that component, not to the route. Use the `providers` array in the route config or a dedicated `provideXxx()` function for route-scoped singletons.
- **Confidence:** MEDIUM
- **Hit count:** 0

### NG-PREEMPT-008: @defer blocks require explicit trigger or they render immediately
- **Domain:** rendering
- **Pattern:** `@defer` without a trigger condition (e.g., `on viewport`, `on interaction`, `when condition`) renders the content immediately, defeating the purpose. Always specify an explicit trigger.
- **Confidence:** MEDIUM
- **Hit count:** 0

## Standalone/Signals Variant Learnings

### Common Pitfalls
<!-- Populated by retrospective agent: signal migration issues, NgModule interop -->

### Effective Patterns
<!-- Populated by retrospective agent -->
