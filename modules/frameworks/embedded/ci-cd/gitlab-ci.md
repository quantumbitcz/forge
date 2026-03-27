# GitLab CI with Embedded

> Extends `modules/ci-cd/gitlab-ci.md` with embedded cross-compilation CI patterns.
> Generic GitLab CI conventions (stages, artifacts, includes) are NOT repeated here.

## Integration Setup

```yaml
# .gitlab-ci.yml
image: ubuntu:24.04

stages:
  - build
  - test
  - flash

variables:
  DEBIAN_FRONTEND: noninteractive

build:
  stage: build
  before_script:
    - apt-get update && apt-get install -y cmake gcc-arm-none-eabi libnewlib-arm-none-eabi
  script:
    - cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/arm-none-eabi.cmake
    - cmake --build build
    - arm-none-eabi-size build/firmware.elf
  artifacts:
    paths:
      - build/firmware.hex
      - build/firmware.bin
      - build/firmware.elf
    expire_in: 7 days
```

## Framework-Specific Patterns

### Host-Side Unit Tests

```yaml
test:
  stage: test
  image: ubuntu:24.04
  before_script:
    - apt-get update && apt-get install -y cmake gcc
  script:
    - cmake -B build-test -S tests
    - cmake --build build-test
    - ctest --test-dir build-test --output-on-failure
  artifacts:
    reports:
      junit: build-test/test-results.xml
```

### QEMU Integration Tests

```yaml
qemu-test:
  stage: test
  image: ubuntu:24.04
  before_script:
    - apt-get update && apt-get install -y cmake gcc-arm-none-eabi libnewlib-arm-none-eabi qemu-system-arm
  script:
    - cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/arm-none-eabi.cmake -DQEMU=ON
    - cmake --build build
    - timeout 30 qemu-system-arm
        -machine lm3s6965evb
        -nographic
        -kernel build/firmware.elf
        -semihosting || true
```

### Binary Size Regression

```yaml
size-check:
  stage: test
  image: ubuntu:24.04
  before_script:
    - apt-get update && apt-get install -y gcc-arm-none-eabi
  script:
    - |
      SIZE=$(arm-none-eabi-size build/firmware.elf | tail -1 | awk '{print $1}')
      BUDGET=524288
      echo "Binary: ${SIZE} bytes / ${BUDGET} bytes budget"
      [ "$SIZE" -le "$BUDGET" ] || exit 1
  needs:
    - build
```

### Hardware-in-the-Loop Testing

```yaml
hil-test:
  stage: test
  tags:
    - hardware-lab
    - stlink
  script:
    - openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
        -c "program build/firmware.hex verify reset exit"
    - python3 tests/hil/run_tests.py --port /dev/ttyACM0 --timeout 60
  needs:
    - build
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

HIL tests require self-hosted runners with hardware access. Tag runners with the programmer type (`stlink`, `jlink`).

### Flash Deployment

```yaml
flash:
  stage: flash
  tags:
    - hardware-lab
    - stlink
  script:
    - openocd -f interface/stlink.cfg -f target/stm32f4x.cfg
        -c "program build/firmware.hex verify reset exit"
  needs:
    - build
    - test
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  when: manual
```

Use `when: manual` for flash deployment to require explicit approval.

## Scaffolder Patterns

```yaml
patterns:
  pipeline: ".gitlab-ci.yml"
```

## Additional Dos

- DO install the cross-compilation toolchain in `before_script`
- DO report and enforce binary size budgets in CI
- DO use QEMU for automated integration tests without hardware
- DO use self-hosted runners tagged with programmer type for HIL testing
- DO use `when: manual` for flash deployment stages

## Additional Don'ts

- DON'T run HIL or flash jobs on shared GitLab runners -- they need hardware access
- DON'T skip binary size checks -- flash budget overruns cause deployment failures
- DON'T use Docker images with pre-installed toolchains unless you maintain them
- DON'T forget `timeout` on QEMU runs -- boot failures can hang indefinitely
