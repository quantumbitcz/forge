# CMake with Embedded

> Extends `modules/build-systems/cmake.md` with embedded cross-compilation patterns.
> Generic CMake conventions (targets, properties, find_package) are NOT repeated here.

## Integration Setup

```cmake
# CMakeLists.txt
cmake_minimum_required(VERSION 3.22)
project(firmware C ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Target MCU configuration
set(MCU_FAMILY "STM32F4" CACHE STRING "MCU family")
set(MCU_MODEL "STM32F407VG" CACHE STRING "MCU model")

# Cross-compilation toolchain
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

# Compiler flags
add_compile_options(
    -mcpu=cortex-m4
    -mthumb
    -mfloat-abi=hard
    -mfpu=fpv4-sp-d16
    -Wall -Wextra -Werror
    -ffunction-sections
    -fdata-sections
    -fno-common
)

add_link_options(
    -mcpu=cortex-m4
    -mthumb
    --specs=nosys.specs
    -Wl,--gc-sections
    -Wl,-Map=${PROJECT_NAME}.map
    -T${CMAKE_SOURCE_DIR}/linker/${MCU_MODEL}.ld
)
```

## Framework-Specific Patterns

### Cross-Compilation Toolchain File

```cmake
# cmake/toolchains/arm-none-eabi.cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

set(CMAKE_C_COMPILER arm-none-eabi-gcc)
set(CMAKE_ASM_COMPILER arm-none-eabi-gcc)
set(CMAKE_OBJCOPY arm-none-eabi-objcopy)
set(CMAKE_SIZE arm-none-eabi-size)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
```

```bash
cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/arm-none-eabi.cmake
cmake --build build
```

### RISC-V Toolchain

```cmake
# cmake/toolchains/riscv32-unknown-elf.cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)

set(CMAKE_C_COMPILER riscv32-unknown-elf-gcc)
set(CMAKE_ASM_COMPILER riscv32-unknown-elf-gcc)

add_compile_options(-march=rv32imac -mabi=ilp32)
```

### Binary Output Formats

```cmake
# Generate .hex and .bin from .elf
add_custom_command(TARGET firmware POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:firmware> firmware.hex
    COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:firmware> firmware.bin
    COMMAND ${CMAKE_SIZE} $<TARGET_FILE:firmware>
    COMMENT "Generating hex/bin and printing size"
)
```

### Host-Side Unit Tests

```cmake
# tests/CMakeLists.txt
project(firmware_tests C)

# Host build -- NOT cross-compiled
set(CMAKE_C_COMPILER gcc)

enable_testing()

add_executable(test_driver
    test_main.c
    test_protocol.c
    ../src/protocol/protocol.c
)

target_include_directories(test_driver PRIVATE ../include)

# Unity test framework
target_link_libraries(test_driver unity)

add_test(NAME unit_tests COMMAND test_driver)
```

Host-side tests compile with the host GCC (not the cross-compiler). Only test platform-independent logic -- hardware drivers require HIL testing.

### Binary Size Budget

```cmake
set(FLASH_SIZE_KB 512)
set(FLASH_WARNING_KB 400)

add_custom_command(TARGET firmware POST_BUILD
    COMMAND ${CMAKE_SIZE} -A $<TARGET_FILE:firmware> > size_report.txt
    COMMAND ${CMAKE_COMMAND} -E echo "Flash budget: ${FLASH_WARNING_KB}KB / ${FLASH_SIZE_KB}KB"
)
```

## Scaffolder Patterns

```yaml
patterns:
  cmakelists: "CMakeLists.txt"
  toolchain_arm: "cmake/toolchains/arm-none-eabi.cmake"
  toolchain_riscv: "cmake/toolchains/riscv32-unknown-elf.cmake"
  linker_script: "linker/${MCU_MODEL}.ld"
```

## Additional Dos

- DO use CMake toolchain files for cross-compilation -- never set compilers in the main CMakeLists.txt
- DO use `-ffunction-sections` and `-fdata-sections` with `--gc-sections` for dead code elimination
- DO generate `.hex`/`.bin` and print size as post-build steps
- DO compile host-side unit tests with the host compiler, not the cross-compiler
- DO track binary size against flash budget in CI

## Additional Don'ts

- DON'T use `find_package()` for embedded dependencies -- most aren't CMake-aware
- DON'T link `libc`/`libm` unless you've accounted for heap usage (use `--specs=nosys.specs` or `nano.specs`)
- DON'T use C++ exceptions or RTTI in embedded targets -- they add significant code size
- DON'T forget linker scripts -- without them, the binary won't map to the MCU's memory layout
