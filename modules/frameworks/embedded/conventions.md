# Embedded C Framework Conventions

> Framework-specific conventions for embedded C projects. Language idioms are in `modules/languages/c.md`.

## Architecture (POSIX / Bare-Metal Hybrid)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `src/drivers/` | Hardware abstraction (GPIO, UART, SPI, I2C) | CMSIS / vendor HAL only |
| `src/app/` | Application logic, state machines | drivers, lib |
| `src/lib/` | Reusable utilities (ring buffers, CRC, protocol parsers) | none (freestanding) |
| `include/` | Public headers for each module | -- |
| `test/` | Unity / CMock unit tests, host-compiled | src, mocks |

**Dependency rule:** Drivers never depend on app. App depends on drivers via header interfaces. Lib is standalone.

## Memory Management

- **Static allocation preferred.** All buffers fixed-size at file scope or `static` locals.
- **No dynamic allocation in ISR or critical sections.** Acceptable only during initialization with comment `/* INIT-ONLY: dynamic alloc */`.
- **Stack budgets:** Each task/thread documents worst-case stack usage at entry point.
- **No variable-length arrays (VLAs).** Use fixed-size with `_Static_assert` on bounds.

## Real-Time Safety

- **No unbounded loops.** Every loop has documented max iteration count or timeout.
- **No floating point in ISR context.** Use fixed-point arithmetic (Q15, Q31).
- **ISR bodies must be short.** Defer work to main-loop or RTOS task via flag/queue.
- **No blocking calls in ISR:** no printf, no dynamic allocation, no mutex locks.

## ISR and RTOS Patterns

### ISR (Interrupt Service Routine) Rules
- Maximum ISR duration: 10us on most embedded targets
- Pre-allocate all buffers -- no dynamic allocation in ISR
- Use flag-and-handle pattern (set flag in ISR, process in main loop)
- Use `volatile` for all variables shared between ISR and main context
- Disable interrupts (critical section) for minimum time when accessing shared state

### RTOS Patterns (FreeRTOS / Zephyr)
- Use message queues for inter-task communication -- avoid shared memory
- Priority assignment based on urgency (deadline-driven)
- Use mutexes (with priority inheritance) for shared resources -- not binary semaphores
- Stack size: measure with high-water mark API, add 20% margin

## Header Guards

Every header file uses include guard:
```c
#ifndef MODULE_FILENAME_H
#define MODULE_FILENAME_H
/* ... */
#endif /* MODULE_FILENAME_H */
```

`#pragma once` acceptable only for host-compiled test headers.

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Public function | `module_action_noun` | `uart_send_byte` |
| Static function | `action_noun` (file-scoped) | `static parse_header(...)` |
| Type | `module_noun_t` | `uart_config_t` |
| Macro / constant | `MODULE_NOUN` | `UART_BAUD_RATE` |
| ISR handler | `MODULE_IRQHandler` | `USART1_IRQHandler` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- One declaration per line. No comma-separated declarations.
- Comments explain WHY, not WHAT
- No compiler warnings: `-Wall -Wextra -Werror -pedantic`

## Error Handling

- All system/POSIX calls must check return values
- Functions return `int` status code (0 = success, negative = error) or enum error type
- Never silently ignore errors -- at minimum set a fault flag

## Build System

- Primary: `make` with top-level `Makefile`. Alternative: CMake.
- Cross-compilation via toolchain file or `CROSS_COMPILE` prefix
- Debug builds: `-Og -g -DDEBUG`. Release: `-Os -DNDEBUG`.

## Testing

- **Framework:** Unity + CMock (lightweight C testing)
- **Host-compiled tests:** compile and run on development host, not target hardware
- **Test naming:** `test_module_behavior_condition`
- **Hardware mocks:** all hardware access through driver headers; tests link mock implementations
- **Coverage:** `gcov` / `lcov` targeting 80%+ on `lib/` and `app/`

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Dos and Don'ts

### Do
- Use `snprintf` instead of `sprintf` -- always bound buffer writes
- Check all return values -- especially system calls and memory allocation
- Use `static` for file-scoped functions and variables
- Use `const` wherever possible -- function parameters, global data, pointers
- Use `volatile` for hardware registers and shared ISR variables only
- Document memory ownership in function signatures

### Don't
- Don't use dynamic allocation in ISR context -- non-deterministic timing
- Don't use `float` in ISR handlers -- FPU context save overhead
- Don't use unbounded loops in ISR -- keep under 10us
- Don't cast away `const` -- redesign if needed
- Don't use `goto` except for centralized error cleanup
