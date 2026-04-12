# Cross-Project Learnings: embedded

## PREEMPT items

### EM-PREEMPT-001: Missing volatile on ISR-shared variables causes optimization bugs
- **Domain:** concurrency
- **Pattern:** Variables shared between ISR and main context without `volatile` qualifier are optimized away by the compiler. The main loop reads a cached register value and never sees ISR updates. Mark all ISR-shared variables `volatile`.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-002: Dynamic allocation in ISR causes non-deterministic timing
- **Domain:** memory
- **Pattern:** Calling `malloc`/`calloc` inside an ISR or critical section introduces unbounded latency from heap fragmentation. Pre-allocate all buffers statically. Use ring buffers or fixed-size pools for ISR-to-main data transfer.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-003: Stack overflow from unbounded recursion or VLAs
- **Domain:** memory
- **Pattern:** Variable-length arrays (VLAs) and recursive functions with no depth limit can exceed the task stack budget. Use fixed-size arrays with `_Static_assert` on bounds. Document worst-case stack depth at every task entry point.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-004: Floating point in ISR triggers FPU context save overhead
- **Domain:** performance
- **Pattern:** Using `float` or `double` in ISR handlers forces the CPU to save and restore the full FPU register set, increasing ISR latency by 10-50 cycles. Use fixed-point arithmetic (Q15/Q31) for ISR computations.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-005: sprintf without bounds checking overflows buffers
- **Domain:** security
- **Pattern:** Using `sprintf` instead of `snprintf` in embedded code leads to buffer overflows that corrupt adjacent memory, especially stack-allocated buffers. Always use `snprintf` with explicit buffer size.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-006: Binary semaphore vs mutex — no priority inheritance
- **Domain:** concurrency
- **Pattern:** Binary semaphores do not support priority inheritance in FreeRTOS/Zephyr. Using them to protect shared resources causes priority inversion. Use mutexes (with built-in priority inheritance) for resource protection; semaphores only for signaling.
- **Confidence:** HIGH
- **Hit count:** 0

### EM-PREEMPT-007: Missing critical section around multi-byte shared variable access
- **Domain:** concurrency
- **Pattern:** Reading a multi-byte variable (32-bit on 8/16-bit MCU) shared with an ISR without disabling interrupts can produce torn reads — half old value, half new. Wrap reads and writes in critical sections or use atomic types.
- **Confidence:** MEDIUM
- **Hit count:** 0

### EM-PREEMPT-008: Watchdog timer not fed during long initialization
- **Domain:** reliability
- **Pattern:** Long initialization sequences (flash erase, sensor calibration, network join) exceed the watchdog timeout and trigger unexpected resets. Feed the watchdog periodically during init or increase the timeout for the init phase, then reduce it for normal operation.
- **Confidence:** MEDIUM
- **Hit count:** 0
