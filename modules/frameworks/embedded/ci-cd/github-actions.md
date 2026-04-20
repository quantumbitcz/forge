# GitHub Actions with Embedded

> Extends `modules/ci-cd/github-actions.md` with embedded cross-compilation CI patterns.
> Generic GitHub Actions conventions (workflow triggers, caching strategies, matrix builds) are NOT repeated here.

## Integration Setup

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Install ARM toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y gcc-arm-none-eabi libnewlib-arm-none-eabi

      - name: Build firmware
        run: |
          cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/arm-none-eabi.cmake
          cmake --build build

      - name: Report binary size
        run: arm-none-eabi-size build/firmware.elf

      - uses: actions/upload-artifact@v4
        with:
          name: firmware
          path: |
            build/firmware.hex
            build/firmware.bin
            build/firmware.elf
```

## Framework-Specific Patterns

### Cross-Compilation Matrix

```yaml
build:
  strategy:
    matrix:
      include:
        - target: arm-cortex-m4
          toolchain: arm-none-eabi
          packages: gcc-arm-none-eabi libnewlib-arm-none-eabi
          cmake_toolchain: cmake/toolchains/arm-none-eabi.cmake
        - target: riscv32
          toolchain: riscv32-unknown-elf
          packages: gcc-riscv64-unknown-elf
          cmake_toolchain: cmake/toolchains/riscv32-unknown-elf.cmake
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - run: sudo apt-get update && sudo apt-get install -y ${{ matrix.packages }}
    - run: |
        cmake -B build -DCMAKE_TOOLCHAIN_FILE=${{ matrix.cmake_toolchain }}
        cmake --build build
    - run: ${{ matrix.toolchain }}-size build/firmware.elf || true
```

### Host-Side Unit Tests

```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6

    - name: Build and run host tests
      run: |
        cmake -B build-test -S tests
        cmake --build build-test
        ctest --test-dir build-test --output-on-failure
```

Host-side tests use the native GCC compiler. They validate platform-independent logic without requiring hardware.

### QEMU Testing

```yaml
qemu-test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6

    - name: Install tools
      run: |
        sudo apt-get update
        sudo apt-get install -y gcc-arm-none-eabi libnewlib-arm-none-eabi qemu-system-arm

    - name: Build for QEMU
      run: |
        cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/arm-none-eabi.cmake -DQEMU=ON
        cmake --build build

    - name: Run on QEMU
      run: |
        timeout 30 qemu-system-arm \
          -machine lm3s6965evb \
          -nographic \
          -kernel build/firmware.elf \
          -semihosting || true
```

QEMU emulates ARM Cortex-M targets. Use it for automated integration tests without physical hardware. The `timeout` prevents hanging on infinite loops.

### Binary Size Regression Check

```yaml
- name: Check binary size budget
  run: |
    SIZE=$(arm-none-eabi-size build/firmware.elf | tail -1 | awk '{print $1}')
    BUDGET=524288  # 512KB
    echo "Binary: ${SIZE} bytes / ${BUDGET} bytes budget"
    if [ "$SIZE" -gt "$BUDGET" ]; then
      echo "::error::Binary exceeds flash budget (${SIZE} > ${BUDGET})"
      exit 1
    fi
```

### Flash Tool Integration

```yaml
flash:
  needs: build
  if: github.ref == 'refs/heads/main'
  runs-on: [self-hosted, hardware-lab]
  steps:
    - uses: actions/download-artifact@v4
      with:
        name: firmware
    - name: Flash to target
      run: |
        openocd -f interface/stlink.cfg -f target/stm32f4x.cfg \
          -c "program firmware.hex verify reset exit"
```

Flash jobs require self-hosted runners with physical hardware access (J-Link, ST-Link, etc.).

## Scaffolder Patterns

```yaml
patterns:
  workflow: ".github/workflows/ci.yml"
  flash_workflow: ".github/workflows/flash.yml"
```

## Additional Dos

- DO install the cross-compilation toolchain (`gcc-arm-none-eabi`) explicitly
- DO report binary size in CI and fail on budget overruns
- DO use QEMU for automated integration tests without hardware
- DO run host-side unit tests with the native compiler
- DO use self-hosted runners with hardware access for flash/HIL testing

## Additional Don'ts

- DON'T assume the cross-compiler is pre-installed on GitHub runners
- DON'T skip binary size reporting -- flash budget overruns must be caught in CI
- DON'T run hardware-in-the-loop tests on shared runners -- they need physical access
- DON'T use `timeout` without a fallback -- QEMU tests can hang on boot failures
