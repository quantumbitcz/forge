# Embedded C Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (POSIX / Bare-Metal Hybrid)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `src/drivers/` | Hardware abstraction (GPIO, UART, SPI, I2C) | CMSIS / vendor HAL only |
| `src/app/` | Application logic, state machines | drivers, lib |
| `src/lib/` | Reusable utilities (ring buffers, CRC, protocol parsers) | none (freestanding) |
| `include/` | Public headers for each module | — |
| `test/` | Unity / CMock unit tests, host-compiled | src, mocks |

**Dependency rule:** Drivers never depend on app. App depends on drivers via header interfaces. Lib is standalone.

## Memory Management

- **Static allocation preferred.** All buffers must be fixed-size and declared at file scope or as `static` locals.
- **No `malloc`/`calloc`/`realloc` in ISR or critical sections.** Dynamic allocation is acceptable only during initialization, guarded by a comment `/* INIT-ONLY: dynamic alloc */`.
- **Stack budgets:** Each task/thread must document its worst-case stack usage in a comment at the task entry point.
- **No variable-length arrays (VLAs).** Use fixed-size arrays with compile-time `_Static_assert` on bounds.

## Header Guards

Every header file must use an include guard following the pattern:

```c
#ifndef MODULE_FILENAME_H
#define MODULE_FILENAME_H
/* ... */
#endif /* MODULE_FILENAME_H */
```

`#pragma once` is acceptable only for host-compiled test headers, never for target code.

## Const Correctness

- Pointer parameters that are not modified must be `const`-qualified: `void process(const uint8_t *buf, size_t len)`.
- Global lookup tables must be `static const` (placed in `.rodata` / flash).
- Prefer `const` locals for values computed once and never reassigned.

## Error Handling

- All system/POSIX calls must check return values. Use `errno` inspection where applicable.
- Functions return an `int` status code (0 = success, negative = error) or a domain-specific `enum` error type.
- Never silently ignore errors. At minimum log via `DEBUG_PRINTF` or set a fault flag.

## Real-Time Safety

- **No unbounded loops.** Every loop must have a documented maximum iteration count or a timeout.
- **No floating point in ISR context.** Use fixed-point arithmetic (`Q15`, `Q31`) for signal processing in interrupt handlers.
- **ISR bodies must be short.** Defer work to a main-loop handler or RTOS task via a flag or queue.
- **No blocking calls in ISR:** no `printf`, no `malloc`, no mutex locks.

## Naming Patterns

| Artifact | Pattern | Example |
|----------|---------|---------|
| Public function | `module_action_noun` | `uart_send_byte`, `ring_buf_push` |
| Static (private) function | `action_noun` (file-scoped `static`) | `static parse_header(...)` |
| Type (struct/enum) | `module_noun_t` | `uart_config_t`, `sensor_state_t` |
| Macro / constant | `MODULE_NOUN` | `UART_BAUD_RATE`, `MAX_BUF_SIZE` |
| ISR handler | `MODULE_IRQHandler` | `USART1_IRQHandler` |

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels.
- One declaration per line. No comma-separated declarations.
- Comments explain WHY, not WHAT. Use `/* */` for block, `//` for inline (C99+).
- Minimal dependencies: each `.c` file includes only the headers it directly needs.
- No compiler warnings: build with `-Wall -Wextra -Werror -pedantic`.

## Build System

- Primary: `make` with a top-level `Makefile`. Alternative: CMake (`CMakeLists.txt`).
- Cross-compilation via toolchain file or `CROSS_COMPILE` prefix (e.g., `arm-none-eabi-`).
- Debug builds enable `-Og -g -DDEBUG`. Release builds enable `-Os -DNDEBUG`.

## Testing

- **Framework:** Unity (C unit test) + CMock (mocking) or similar lightweight framework.
- **Host-compiled tests:** tests compile and run on the development host (x86/ARM64), not on target hardware.
- **Test naming:** `test_module_behavior_condition` (e.g., `test_ring_buf_push_when_full_returns_error`).
- **Hardware mocks:** all hardware access goes through driver headers; tests link against mock implementations.
- **Coverage:** `gcov` / `lcov` for line coverage. Target: 80%+ on `lib/` and `app/`.

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.
