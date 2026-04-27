---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "em-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-001"
  - id: "em-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["memory", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-002"
  - id: "em-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["memory", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-003"
  - id: "em-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["performance", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-004"
  - id: "em-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-005"
  - id: "em-preempt-006"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-006"
  - id: "em-preempt-007"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["concurrency", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-007"
  - id: "em-preempt-008"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.735617Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["reliability", "embedded"]
    source: "cross-project"
    archived: false
    body_ref: "#em-preempt-008"
---
# Cross-Project Learnings: embedded

## PREEMPT items

### EM-PREEMPT-001: Missing volatile on ISR-shared variables causes optimization bugs
<a id="em-preempt-001"></a>
- **Domain:** concurrency
- **Pattern:** Variables shared between ISR and main context without `volatile` qualifier are optimized away by the compiler. The main loop reads a cached register value and never sees ISR updates. Mark all ISR-shared variables `volatile`.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-002: Dynamic allocation in ISR causes non-deterministic timing
<a id="em-preempt-002"></a>
- **Domain:** memory
- **Pattern:** Calling `malloc`/`calloc` inside an ISR or critical section introduces unbounded latency from heap fragmentation. Pre-allocate all buffers statically. Use ring buffers or fixed-size pools for ISR-to-main data transfer.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-003: Stack overflow from unbounded recursion or VLAs
<a id="em-preempt-003"></a>
- **Domain:** memory
- **Pattern:** Variable-length arrays (VLAs) and recursive functions with no depth limit can exceed the task stack budget. Use fixed-size arrays with `_Static_assert` on bounds. Document worst-case stack depth at every task entry point.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-004: Floating point in ISR triggers FPU context save overhead
<a id="em-preempt-004"></a>
- **Domain:** performance
- **Pattern:** Using `float` or `double` in ISR handlers forces the CPU to save and restore the full FPU register set, increasing ISR latency by 10-50 cycles. Use fixed-point arithmetic (Q15/Q31) for ISR computations.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-005: sprintf without bounds checking overflows buffers
<a id="em-preempt-005"></a>
- **Domain:** security
- **Pattern:** Using `sprintf` instead of `snprintf` in embedded code leads to buffer overflows that corrupt adjacent memory, especially stack-allocated buffers. Always use `snprintf` with explicit buffer size.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-006: Binary semaphore vs mutex — no priority inheritance
<a id="em-preempt-006"></a>
- **Domain:** concurrency
- **Pattern:** Binary semaphores do not support priority inheritance in FreeRTOS/Zephyr. Using them to protect shared resources causes priority inversion. Use mutexes (with built-in priority inheritance) for resource protection; semaphores only for signaling.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-007: Missing critical section around multi-byte shared variable access
<a id="em-preempt-007"></a>
- **Domain:** concurrency
- **Pattern:** Reading a multi-byte variable (32-bit on 8/16-bit MCU) shared with an ISR without disabling interrupts can produce torn reads — half old value, half new. Wrap reads and writes in critical sections or use atomic types.
- **Confidence:** MEDIUM
- **Hit count:** 0

### EM-PREEMPT-008: Watchdog timer not fed during long initialization
<a id="em-preempt-008"></a>
- **Domain:** reliability
- **Pattern:** Long initialization sequences (flash erase, sensor calibration, network join) exceed the watchdog timeout and trigger unexpected resets. Feed the watchdog periodically during init or increase the timeout for the init phase, then reduce it for normal operation.
- **Confidence:** MEDIUM
- **Hit count:** 0
