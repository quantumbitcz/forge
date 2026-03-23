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

## Anti-Patterns

- **`malloc` in time-critical or ISR context:** Non-deterministic timing, fragmentation risk. Pre-allocate all buffers.
- **`float` in ISR handlers:** Many MCUs have no FPU; floating-point context save/restore is expensive. Use fixed-point (`Q15`, `Q31`) arithmetic.
- **Unbounded loops in production:** Every loop must have a documented maximum iteration count or a hard timeout exit.
- **Implicit function declarations:** Always include the correct header — implicit `int` return is undefined behavior in C99+.
- **Type-punning via pointer cast:** Violates strict aliasing. Use `memcpy` or a `union` for safe type punning.
- **Magic numbers:** Replace with named `#define` constants or `enum` values — describe intent, not value.
- **No `volatile` on ISR-shared variables:** The compiler may optimize away reads/writes to variables it doesn't know are modified by interrupts.
