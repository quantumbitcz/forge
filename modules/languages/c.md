# C Language Conventions

## Memory Management

- **Static allocation by default.** All buffers must be fixed-size and declared at file scope or as `static` locals. The allocator is the programmer — know your memory at compile time.
- **No dynamic allocation in production-critical paths.** `malloc`/`calloc`/`realloc` is acceptable only during initialization; mark such sites with `/* INIT-ONLY: dynamic alloc */`.
- **No variable-length arrays (VLAs).** Declare fixed-size arrays; use `_Static_assert` to verify bounds at compile time.
- **Stack budgets:** Document worst-case stack usage at task/thread entry points — stack overflows in bare-metal systems are silent and catastrophic.
- `free` every `malloc`; ownership of heap memory must be documented in function signatures (who allocates, who frees).

## Header Guards

Every header must use an include guard:

```c
#ifndef MODULE_FILENAME_H
#define MODULE_FILENAME_H
/* ... */
#endif /* MODULE_FILENAME_H */
```

`#pragma once` is acceptable for host-compiled test headers only — not for embedded target code.

## Const Correctness

- Pointer parameters that are not modified must be `const`-qualified: `void process(const uint8_t *buf, size_t len)`.
- Global and file-scoped lookup tables must be `static const` — places data in `.rodata` / flash rather than RAM.
- Prefer `const` for local variables computed once and never reassigned.
- Never cast away `const` — redesign the API if that seems necessary.

## Volatile

- Use `volatile` for all variables shared between an ISR and the main execution context.
- Use `volatile` for memory-mapped hardware registers.
- Do not use `volatile` as a substitute for proper synchronization primitives in POSIX/RTOS code — it does not provide atomicity or memory ordering guarantees on its own.

## Error Handling

- All functions that can fail must return a status: `int` (0 = success, negative = error code) or a domain-specific `enum` error type.
- Never silently ignore error returns — at minimum set a fault flag or log via `DEBUG_PRINTF`.
- Check all system/POSIX call return values. Inspect `errno` where applicable.
- Do not use exceptions (C has none) — error propagation is explicit via return values.

## Naming Idioms

| Artifact              | Pattern                         | Example                          |
|-----------------------|---------------------------------|----------------------------------|
| Public function       | `module_action_noun`            | `uart_send_byte`, `ring_buf_push`|
| Private function      | `action_noun` (file-scope `static`) | `static parse_header(...)`  |
| Type (struct/enum)    | `module_noun_t`                 | `uart_config_t`, `sensor_state_t`|
| Macro / constant      | `MODULE_NOUN`                   | `UART_BAUD_RATE`, `MAX_BUF_SIZE` |
| ISR handler           | `MODULE_IRQHandler`             | `USART1_IRQHandler`              |

- Use `static` for file-scoped functions and variables — minimize the global namespace.
- One declaration per line. No comma-separated declarations.

## Safe Coding Practices

- Use `snprintf` instead of `sprintf` — always bound buffer writes.
- Use `strncpy`/`strlcpy` instead of `strcpy` — prevent buffer overflows.
- Never use `gets()` — it was removed in C11.
- Use `goto` only for centralized error cleanup in functions with multiple resource acquisitions (the single accepted use case for `goto` in C).
- Build with `-Wall -Wextra -Werror -pedantic` — zero warnings is a hard requirement, not a goal.
- Minimal includes: each `.c` file includes only the headers it directly needs.

## Logging

- C has no standard logging library. Choose based on target environment:
  - **Embedded/bare-metal:** Custom `LOG_*` macros wrapping UART/SWO/RTT output with compile-time level filtering.
  - **POSIX applications:** **zlog** (`HardySimpson/zlog`) for high-performance structured logging, or **log.c** (`rxi/log.c`) for minimal footprint.
  - **Daemon processes:** `syslog(3)` via `<syslog.h>` for system log integration.
- Define log level macros with compile-time filtering to eliminate disabled levels entirely:
  ```c
  #ifndef LOG_LEVEL
  #define LOG_LEVEL LOG_LEVEL_INFO
  #endif

  #define LOG_ERROR(fmt, ...) do { if (LOG_LEVEL <= LOG_LEVEL_ERROR) \
      log_write(LOG_LEVEL_ERROR, __FILE__, __LINE__, fmt, ##__VA_ARGS__); } while(0)
  #define LOG_WARN(fmt, ...)  do { if (LOG_LEVEL <= LOG_LEVEL_WARN)  \
      log_write(LOG_LEVEL_WARN,  __FILE__, __LINE__, fmt, ##__VA_ARGS__); } while(0)
  #define LOG_INFO(fmt, ...)  do { if (LOG_LEVEL <= LOG_LEVEL_INFO)  \
      log_write(LOG_LEVEL_INFO,  __FILE__, __LINE__, fmt, ##__VA_ARGS__); } while(0)
  #define LOG_DEBUG(fmt, ...) do { if (LOG_LEVEL <= LOG_LEVEL_DEBUG) \
      log_write(LOG_LEVEL_DEBUG, __FILE__, __LINE__, fmt, ##__VA_ARGS__); } while(0)
  ```
- Always include source location (`__FILE__`, `__LINE__`) in log macros — essential for embedded debugging where stack traces may be unavailable.
- Use `snprintf`-based formatting in log implementations — never `sprintf` (buffer overflow risk).
- In ISR context, buffer log data to a ring buffer and flush from the main loop — never perform I/O (UART writes, file writes) in interrupt handlers.
- Never use `printf` directly for production logging — it lacks levels, is not filterable, and has no timestamp.
- PII/credential/financial data logging rules: see `shared/logging-rules.md`. In embedded contexts, even debug builds are vulnerable — logs can be captured via JTAG/SWO probes.

## Anti-Patterns

- **`malloc` in time-critical or ISR context:** Non-deterministic timing, fragmentation risk. Pre-allocate all buffers.
- **`float` in ISR handlers:** Many MCUs have no FPU; floating-point context save/restore is expensive. Use fixed-point (`Q15`, `Q31`) arithmetic.
- **Unbounded loops in production:** Every loop must have a documented maximum iteration count or a hard timeout exit.
- **Implicit function declarations:** Always include the correct header — implicit `int` return is undefined behavior in C99+.
- **Type-punning via pointer cast:** Violates strict aliasing. Use `memcpy` or a `union` for safe type punning.
- **Magic numbers:** Replace with named `#define` constants or `enum` values — describe intent, not value.
- **No `volatile` on ISR-shared variables:** The compiler may optimize away reads/writes to variables it doesn't know are modified by interrupts.

## Dos
- Use `snprintf` over `sprintf` — always bound buffer writes to prevent overflows.
- Use `static` for file-scoped functions and variables — minimize the global symbol table.
- Use `const` for read-only data — it enables compiler optimizations and documents intent.
- Use `volatile` for variables shared between ISR and main context.
- Build with `-Wall -Wextra -Werror -pedantic` — zero warnings is a hard requirement.
- Use `goto` only for centralized error cleanup in functions with multiple resource acquisitions.
- Use `stdint.h` types (`uint32_t`, `int16_t`) instead of platform-dependent `int`/`long`.

## Don'ts
- Don't use `malloc` in ISR handlers or time-critical paths — non-deterministic timing and fragmentation risk.
- Don't use `float` in ISR handlers on MCUs without FPU — use fixed-point arithmetic.
- Don't use `gets()` — it was removed in C11 for buffer overflow vulnerability.
- Don't use implicit function declarations — always include the correct header.
- Don't use pointer casts for type punning — it violates strict aliasing; use `memcpy` instead.
- Don't use magic numbers — replace with named `#define` constants or `enum` values.
- Don't use `sprintf`, `strcpy`, or other unbounded string functions — use their `n`-bounded variants.
- Don't write C++-style OOP with function pointer tables unless the abstraction boundary is genuinely needed — prefer simple data + functions.
- Don't create deep abstraction layers — C thrives with flat, transparent data structures.
- Don't use `void*` callbacks when a typed function pointer with context struct works.
