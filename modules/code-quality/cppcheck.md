---
name: cppcheck
categories: [linter]
languages: [c, cpp]
exclusive_group: c-linter
recommendation_score: 80
detection_files: [.cppcheck, cppcheck.xml]
---

# cppcheck

## Overview

Open-source C and C++ static analysis tool focused on finding bugs rather than enforcing style. cppcheck analyzes C/C++ code independently of the compiler, detecting memory leaks, buffer overflows, undefined behavior, and resource management errors. Its key strengths over clang-tidy are: works without `compile_commands.json` (useful for legacy build systems), lower false positive rate (conservative analysis), and built-in MISRA C compliance checking. Use both cppcheck and clang-tidy together — they use different analysis engines and find complementary issues.

## Architecture Patterns

### Installation & Setup

```bash
# Ubuntu/Debian
sudo apt-get install cppcheck

# macOS
brew install cppcheck

# Windows (Chocolatey)
choco install cppcheck

# Verify
cppcheck --version

# Run on a directory
cppcheck --enable=all --suppress=missingInclude src/

# Run with include paths and C++ standard
cppcheck --enable=all --std=c++17 -I include/ src/
```

CMake integration:
```cmake
# CMakeLists.txt
option(ENABLE_CPPCHECK "Enable cppcheck" OFF)

if(ENABLE_CPPCHECK)
    find_program(CPPCHECK_EXE NAMES "cppcheck")
    if(CPPCHECK_EXE)
        set(CMAKE_CXX_CPPCHECK
            "${CPPCHECK_EXE}"
            "--std=c++17"
            "--enable=warning,performance,portability"
            "--suppress=missingInclude"
            "--error-exitcode=1"
            "--inline-suppr"
        )
    endif()
endif()
```

### Rule Categories

`--enable` flag controls which check categories are active:

| Category | What It Checks | Default | Pipeline Severity |
|---|---|---|---|
| `error` | Definite bugs: buffer overflow, null dereference, use-after-free | Always on | CRITICAL |
| `warning` | Likely bugs: uninitialized variables, suspicious conditions | Off by default | CRITICAL |
| `performance` | Inefficient code: postfix `++` on objects, unnecessary copies | Off by default | WARNING |
| `portability` | Undefined behavior, platform-specific patterns | Off by default | WARNING |
| `style` | Code style: unused variables, redundant code, shadow variables | Off by default | INFO |
| `information` | Configuration messages, suppression hints | Off by default | INFO |
| `unusedFunction` | Functions declared but never called | Off by default | WARNING |
| `missingInclude` | Missing include files (often noisy without full build context) | Off by default | INFO |

### Configuration Patterns

`cppcheck.cfg` or inline via command-line arguments. For project-wide settings, use a suppressions file:

```
# cppcheck-suppressions.txt
# Suppress specific checks for specific files
missingInclude:*/third_party/*
unmatchedSuppression

# Suppress a check globally (use sparingly)
# noExplicitConstructor

# Suppress by error ID and file path
shadowVariable:src/legacy/old_module.cpp
```

Run with suppressions file:
```bash
cppcheck \
  --enable=all \
  --suppressions-list=cppcheck-suppressions.txt \
  --suppress=missingInclude \
  --std=c++17 \
  --language=c++ \
  -I include/ \
  --error-exitcode=1 \
  --xml \
  src/ \
  2> cppcheck-report.xml
```

MISRA C checking (requires `MISRA_Cxx_2008.py` addon):
```bash
cppcheck \
  --addon=misra \
  --addon-python=MISRA_C_2012.py \
  --std=c99 \
  src/
```

Inline suppression:
```c
// cppcheck-suppress nullPointer
result = process(ptr);  // ptr validated upstream, cppcheck can't see it

/* cppcheck-suppress memleak */
char* buf = malloc(size);  // ownership transferred to caller
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Install cppcheck
  run: sudo apt-get install -y cppcheck

- name: Run cppcheck
  run: |
    cppcheck \
      --enable=warning,performance,portability \
      --suppress=missingInclude \
      --std=c++17 \
      --error-exitcode=1 \
      --xml \
      -I include/ \
      src/ \
      2> cppcheck-report.xml

- name: Upload cppcheck report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: cppcheck-report
    path: cppcheck-report.xml
```

Generate HTML report:
```bash
cppcheck --xml src/ 2> cppcheck.xml
cppcheck-htmlreport --file=cppcheck.xml --report-dir=cppcheck-html/
```

## Performance

- cppcheck is slower than clang-tidy but faster than deep path-sensitive analyzers. On 100k-line codebases, expect 30-120s with all checks enabled.
- `--jobs=4` (or `-j4`) enables parallel analysis across files — significantly reduces wall-clock time.
- `missingInclude` check is extremely slow and noisy without full include paths — always suppress it unless you provide complete `-I` paths for all headers.
- `unusedFunction` check requires a full project-wide analysis pass — it cannot run incrementally. Run it in CI only, not on individual files.
- cppcheck does not require `compile_commands.json` — it can analyze individual files without a configured build system, making it useful for legacy or embedded projects.

## Security

cppcheck finds security-relevant memory and resource management bugs:

- Buffer overflows: fixed-size array writes without bounds checking.
- Use-after-free: accessing memory after it has been deallocated.
- Memory leaks: allocated memory without corresponding deallocation on all paths.
- Null pointer dereference: using a pointer without null check after potentially-null assignment.
- Integer overflow: arithmetic on fixed-size integers that may wrap.
- `--addon=misra` — enables MISRA C 2012 / MISRA C++ 2008 compliance checking, required for automotive (AUTOSAR), medical (IEC 62304), and industrial (IEC 61508) safety standards.

MISRA addon configuration:
```bash
# Download MISRA addon: https://github.com/danmar/cppcheck/tree/main/addons
cppcheck --addon=misra --std=c99 --language=c src/
```

## Testing

```bash
# Basic run with all checks
cppcheck --enable=all --suppress=missingInclude src/

# Run with specific checks only
cppcheck --enable=warning,performance src/

# Run on a single file
cppcheck --enable=all --suppress=missingInclude src/module.cpp

# XML output
cppcheck --xml --xml-version=2 src/ 2> report.xml

# Run with include paths
cppcheck --enable=all -I include/ -I /usr/include src/

# Check C code
cppcheck --language=c --std=c11 --enable=all src/

# MISRA checking
cppcheck --addon=misra --std=c99 src/

# Parallel execution
cppcheck -j4 --enable=all src/

# List available addons
cppcheck --list-cfg-addons
```

## Dos

- Enable `warning` and `performance` in CI — the default-only `error` category misses many real bugs that `warning` catches (uninitialized variables, suspicious conditions).
- Use `--suppressions-list` for project-wide suppressions rather than scattering inline `cppcheck-suppress` comments across source files.
- Provide `-I` paths for your project's own headers — without them, cppcheck cannot fully analyze code that uses custom types defined in headers.
- Run both cppcheck and clang-tidy in CI — they use different analysis engines and find complementary issues; neither is a superset of the other.
- For embedded/automotive projects, enable MISRA checking from the start of the project — retrofitting MISRA compliance to an existing codebase is expensive.
- Use `--error-exitcode=1` in CI to fail the build on any finding (combined with appropriate `--suppress` to avoid false positives).

## Don'ts

- Don't enable `--enable=all` without `--suppress=missingInclude` — the `missingInclude` check produces hundreds of false positives without complete `-I` paths and drowns out real issues.
- Don't use cppcheck as the sole static analysis tool for C++ — it has a conservative analysis strategy (low false positives but also lower coverage). Pair with clang-tidy.
- Don't suppress `error` category findings without investigation — cppcheck's `error` category has very low false positive rates; suppressing these usually hides real bugs.
- Don't skip the `-j4` flag on CI with multiple cores — sequential analysis of large codebases can take 10+ minutes unnecessarily.
- Don't use cppcheck for style enforcement — its `style` category is minimal compared to clang-tidy's `readability-*` and `modernize-*` checks. Use clang-tidy for style, cppcheck for bug detection.
- Don't ignore `portability` findings in cross-platform code — they catch implicit platform assumptions (pointer size, integer signedness) that cause subtle bugs when targeting different architectures.
