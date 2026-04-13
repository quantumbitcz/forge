# Embedded + Unity Test Framework Conventions

## Test Structure

- Tests in `test/` directory, one file per module: `test_<module>.c`
- Use Unity test framework (`unity.h`)
- Each test file: `setUp()`, `tearDown()`, and `test_<behavior>()` functions
- Register tests in `main()` via `RUN_TEST(test_name)`
- Build tests for host (x86/ARM) — NOT target hardware

## Unit Testing

- Test pure functions: input → output, no hardware dependencies
- Use Hardware Abstraction Layer (HAL) for testability
- Mock HAL calls via function pointers or link-time substitution
- Test state machines: verify transitions for all input combinations

## HAL Mocking

- Define HAL as function pointer table:
  ```c
  typedef struct { int (*gpio_read)(uint8_t pin); void (*gpio_write)(uint8_t pin, uint8_t val); } hal_t;
  ```
- In tests: provide mock HAL with counters/assertions
- In production: provide real HAL implementation
- CMock (Unity companion) for automatic mock generation

## Interrupt Testing

- Test ISR logic as regular functions (extract logic from ISR handler)
- Verify shared variable access uses `volatile`
- Test critical section logic: disable/enable interrupt pairs
- Never test actual interrupt timing (hardware-dependent)

## Memory Safety Testing

- Verify no dynamic allocation in production code (`malloc`/`free`)
- Test buffer bounds: pass boundary values, check no overflow
- Use `AddressSanitizer` in host builds for leak detection
- Test stack usage estimation with static analysis tools

## Dos

- Test on host first, then hardware-in-the-loop if available
- Test all error codes and return values
- Test boundary conditions (max/min values, buffer limits)
- Verify `volatile` on ISR-shared variables
- Test power state transitions
- Use `TEST_ASSERT_EQUAL_HEX` for register values

## Don'ts

- Don't use `malloc`/`printf`/`float` in test infrastructure for resource-constrained targets
- Don't test hardware peripherals in unit tests (use integration tests)
- Don't test timing-dependent behavior in unit tests
- Don't link real HAL in unit test builds
- Don't skip testing error paths (they're where embedded bugs hide)
