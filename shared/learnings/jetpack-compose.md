---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: jetpack-compose

## PREEMPT items

### JC-PREEMPT-001: collectAsState() without lifecycle awareness causes leaks
- **Domain:** state
- **Pattern:** Using `collectAsState()` instead of `collectAsStateWithLifecycle()` keeps collecting from the flow even when the app is in the background, wasting resources and potentially updating invisible UI. Always use `collectAsStateWithLifecycle()` from `androidx.lifecycle.compose`.
- **Confidence:** HIGH
- **Hit count:** 0

### JC-PREEMPT-002: Unstable lambda captures cause unnecessary recompositions
- **Domain:** performance
- **Pattern:** Lambdas that capture mutable state or are recreated on every composition (e.g., `onClick = { viewModel.doSomething(item) }` inside `items {}`) mark the composable as unstable. Hoist lambdas, use `remember`, or mark data classes with `@Stable`/`@Immutable`.
- **Confidence:** HIGH
- **Hit count:** 0

### JC-PREEMPT-003: Missing key parameter in LazyColumn items causes incorrect state
- **Domain:** rendering
- **Pattern:** `LazyColumn` without `key = { it.id }` on `items {}` reuses composition state by index position. When items are reordered, deleted, or inserted, the wrong composable state is displayed (e.g., expanded state on the wrong item). Always provide a stable key.
- **Confidence:** HIGH
- **Hit count:** 0

### JC-PREEMPT-004: Side effects in composition cause infinite recomposition loops
- **Domain:** state
- **Pattern:** Calling `suspend` functions or launching coroutines directly during composition (outside `LaunchedEffect` or `rememberCoroutineScope`) triggers recomposition infinitely. Use `LaunchedEffect(key)` for lifecycle-tied effects and `rememberCoroutineScope()` for user-triggered actions.
- **Confidence:** HIGH
- **Hit count:** 0

### JC-PREEMPT-005: LiveData in new ViewModels breaks Compose lifecycle integration
- **Domain:** state
- **Pattern:** `LiveData` requires `observeAsState()` which does not integrate with Compose lifecycle (no lifecycle-aware collection). New ViewModels should use `StateFlow` and `collectAsStateWithLifecycle()`. LiveData also adds unnecessary dependency on `androidx.lifecycle.livedata`.
- **Confidence:** HIGH
- **Hit count:** 0

### JC-PREEMPT-006: Navigation arguments with complex types fail serialization
- **Domain:** navigation
- **Pattern:** Navigation Compose serializes route arguments as strings. Passing complex objects as navigation arguments fails at runtime. Pass only primitive IDs and load full data in the destination ViewModel from the repository.
- **Confidence:** HIGH
- **Hit count:** 0

### JC-PREEMPT-007: Hardcoded colors and dimensions bypass theme system
- **Domain:** styling
- **Pattern:** Using `Color(0xFF1234AB)` or `16.dp` directly in composables bypasses Material 3 theming and breaks dark mode. Always use `MaterialTheme.colorScheme.*` for colors and define dimension constants or theme tokens.
- **Confidence:** HIGH
- **Hit count:** 0

### JC-PREEMPT-008: mutableStateOf in composable body without remember resets on recomposition
- **Domain:** state
- **Pattern:** `val x = mutableStateOf(0)` inside a `@Composable` function body (without `remember`) creates a new state instance on every recomposition, resetting the value. Use `remember { mutableStateOf(0) }` for local UI state or hoist to ViewModel.
- **Confidence:** HIGH
- **Hit count:** 0
