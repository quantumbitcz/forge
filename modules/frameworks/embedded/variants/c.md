# Embedded + C Variant

> C-specific patterns for embedded projects. Extends `modules/languages/c.md` and `modules/frameworks/embedded/conventions.md`.

## Const Correctness

- Pointer parameters that are not modified must be `const`-qualified
- Global lookup tables: `static const` (placed in `.rodata` / flash)
- Prefer `const` locals for values computed once and never reassigned

```c
void process(const uint8_t *buf, size_t len);
static const uint16_t crc_table[256] = { ... };
```

## Volatile Usage

- `volatile` for all hardware-mapped registers
- `volatile` for all variables shared between ISR and main context
- Never use `volatile` as a substitute for proper synchronization
- Combine with appropriate atomic operations or critical sections

## Fixed-Point Arithmetic

- Use Q15 (`int16_t`) or Q31 (`int32_t`) for signal processing in ISR
- Document the Q format in comments: `/* Q15: 1 sign bit, 0 integer bits, 15 fractional bits */`
- Use shift-based multiply/divide for Q arithmetic

## Memory-Mapped I/O

- Access hardware registers through pointer to `volatile`
- Use vendor-provided CMSIS headers for register definitions
- Never access raw addresses without register definition structs

## Defensive Programming

- Assert invariants with `_Static_assert` at compile time
- Use `assert()` in debug builds for runtime invariants
- Validate all external inputs (UART, SPI, network) before processing
- Use sentinel values and magic numbers for buffer integrity checks
