# Embedded Documentation Conventions

> Extends `modules/documentation/conventions.md` with embedded systems-specific patterns.

## Code Documentation

- Use Doxygen-style comments (`/** */` or `///`) for all public APIs: functions, structs, enums, and `#define` constants.
- ISR handlers: document the interrupt source, maximum execution time (must be ≤ 10µs), and any shared `volatile` variables accessed.
- Every `volatile` variable: document who writes it (ISR name), who reads it, and the required critical section pattern.
- Hardware abstraction layer (HAL): document register addresses and bit fields for every peripheral access.
- Memory sections (`__attribute__((section(...)))`): document the target memory region and why placement is required.

```c
/**
 * @brief UART receive interrupt handler.
 *
 * Execution time: < 5µs (measured on 72 MHz STM32F4).
 * Writes: rx_buffer (ring buffer, protected by disabling UART IRQ in consumer).
 *
 * @note Called from USART1_IRQHandler — do NOT call directly.
 */
void uart1_rx_isr(void);

/**
 * @brief Raw ADC count from channel 3 (battery voltage divider).
 *
 * Updated by ADC_IRQHandler every 10ms. Read by battery_monitor_task()
 * — must be read with interrupts disabled or via atomic load.
 */
volatile uint16_t adc_ch3_raw;
```

## Architecture Documentation

- Maintain a register map document for each peripheral: base address, offset, bit fields, and access restrictions (R/W/R-C).
- Document interrupt priority table: vector, priority level, handler name, and maximum latency budget.
- Memory layout: document the linker script regions (.text, .data, .bss, stack, heap) and reserved areas.
- Boot sequence: document the startup flow from reset vector through `main()` — stack init, clock config, peripheral init order.
- Document RTOS task list (if applicable): task name, stack size, priority, CPU budget, and inter-task communication channels.

## Diagram Guidance

- **Memory map:** Table or Mermaid block diagram showing memory regions and their addresses.
- **Interrupt priority table:** Table listing all active vectors, priorities, and handlers.
- **Task interaction:** Sequence or state diagram for RTOS task communication patterns.
- **Boot sequence:** Flowchart from reset to application ready.

## Dos

- Doxygen `@note` for every `volatile` shared variable — thread-safety is not obvious
- Document ISR execution time — it is a hard constraint, not a guideline
- Document linker script changes — they affect binary layout and debug symbol resolution

## Don'ts

- Don't use `malloc`/`printf`/`float` in ISRs — document why each is forbidden at the ISR header level
- Don't omit interrupt priority documentation — priority inversions are silent bugs
- Don't skip memory section docs — wrong placement causes runtime failures that are hard to diagnose
