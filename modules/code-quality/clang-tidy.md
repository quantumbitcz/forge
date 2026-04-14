---
name: clang-tidy
categories: [linter]
languages: [c, cpp]
exclusive_group: cpp-linter
recommendation_score: 90
detection_files: [.clang-tidy, compile_commands.json]
---

# clang-tidy

## Overview

C and C++ linter and static analysis tool from the LLVM project. Runs checks across multiple categories: `bugprone` (likely bugs), `cert` (CERT coding standards), `cppcoreguidelines` (C++ Core Guidelines), `modernize` (C++11/14/17/20 migrations), `performance` (anti-patterns with runtime cost), and `readability` (code clarity). Configuration lives in `.clang-tidy`. Integrates with CMake via `CMAKE_CXX_CLANG_TIDY` and with editors via `compile_commands.json`. clang-tidy is the industry standard for C++ static analysis in safety-critical and systems code.

## Architecture Patterns

### Installation & Setup

```bash
# Ubuntu/Debian
sudo apt-get install clang-tidy

# MacOS (via LLVM Homebrew)
brew install llvm
export PATH="$(brew --prefix llvm)/bin:$PATH"

# Verify
clang-tidy --version

# Run on a single file (requires compile_commands.json)
clang-tidy src/main.cpp -- -std=c++17 -I include/

# Run on all files in compile_commands.json
run-clang-tidy -j4        # parallel, uses compile_commands.json
```

Generate `compile_commands.json` via CMake:
```bash
cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
ln -s build/compile_commands.json .   # symlink to project root
```

### Rule Categories

| Check Group | What It Checks | Pipeline Severity |
|---|---|---|
| `bugprone-*` | Suspicious patterns: argument comments, integer overflow, use-after-move | CRITICAL |
| `cert-*` | CERT C/C++ coding standard rules (memory safety, concurrency) | CRITICAL |
| `cppcoreguidelines-*` | C++ Core Guidelines: no raw pointers, bounds safety, lifetime | CRITICAL |
| `modernize-*` | Upgrade to modern C++: `nullptr`, range-for, `auto`, smart pointers | WARNING |
| `performance-*` | Avoid unnecessary copies, `std::move` opportunities, inefficient algorithms | WARNING |
| `readability-*` | Naming, magic numbers, else-after-return, qualified identifiers | WARNING |
| `clang-analyzer-*` | Deep path-sensitive analysis: null deref, memory leak, use-after-free | CRITICAL |
| `concurrency-*` | Thread safety: locking, data races (limited subset) | CRITICAL |

### Configuration Patterns

`.clang-tidy` at the project root:

```yaml
# .clang-tidy
Checks: >
  -*,
  bugprone-*,
  cert-dcl50-cpp,
  cert-err33-c,
  cert-err34-c,
  cert-flp30-c,
  cppcoreguidelines-avoid-c-arrays,
  cppcoreguidelines-avoid-goto,
  cppcoreguidelines-init-variables,
  cppcoreguidelines-no-malloc,
  cppcoreguidelines-pro-bounds-*,
  cppcoreguidelines-pro-type-*,
  modernize-use-auto,
  modernize-use-nullptr,
  modernize-use-override,
  modernize-use-using,
  modernize-loop-convert,
  performance-avoid-endl,
  performance-move-const-arg,
  performance-unnecessary-copy-initialization,
  readability-braces-around-statements,
  readability-identifier-naming,
  readability-magic-numbers,
  readability-redundant-declaration,
  -modernize-use-trailing-return-type,   # too noisy for existing code
  -readability-magic-numbers             # configure threshold below

WarningsAsErrors: >
  bugprone-*,
  cppcoreguidelines-pro-type-*,
  clang-analyzer-*

HeaderFilterRegex: '(src|include)/.*\.(h|hpp)$'

CheckOptions:
  - key: readability-identifier-naming.ClassCase
    value: CamelCase
  - key: readability-identifier-naming.FunctionCase
    value: camelCase
  - key: readability-identifier-naming.VariableCase
    value: camelCase
  - key: readability-identifier-naming.ConstantCase
    value: UPPER_CASE
  - key: readability-identifier-naming.MemberPrefix
    value: m_
  - key: readability-magic-numbers.IgnoredIntegerValues
    value: '0;1;2;-1'
  - key: modernize-use-auto.MinTypeNameLength
    value: '5'
```

CMake integration (runs clang-tidy during build):
```cmake
# CMakeLists.txt
option(ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)

if(ENABLE_CLANG_TIDY)
    find_program(CLANG_TIDY_EXE NAMES "clang-tidy-17" "clang-tidy")
    if(CLANG_TIDY_EXE)
        set(CMAKE_CXX_CLANG_TIDY
            "${CLANG_TIDY_EXE};--warnings-as-errors=bugprone-*")
    endif()
endif()
```

Inline suppression:
```cpp
// NOLINT(bugprone-easily-swappable-parameters)
void setDimensions(int width, int height) { ... }

// NOLINTNEXTLINE(cppcoreguidelines-pro-type-reinterpret-cast)
auto ptr = reinterpret_cast<uint8_t*>(buffer);

// Suppress for an entire file via command line:
// clang-tidy file.cpp --checks='-*,bugprone-*'
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Configure CMake with compile commands
  run: cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

- name: Run clang-tidy
  run: |
    run-clang-tidy -j$(nproc) \
      -p build \
      -header-filter='(src|include)/.*\.(h|hpp)$' \
      2>&1 | tee clang-tidy-report.txt
    grep -c 'warning:' clang-tidy-report.txt && exit 1 || true
```

With SARIF output (via `clang-tidy-sarif` converter):
```bash
clang-tidy --export-fixes=fixes.yaml src/*.cpp -- -std=c++17
```

## Performance

- clang-tidy re-parses each file — analysis time is proportional to compilation time. `run-clang-tidy -j$(nproc)` parallelizes across files.
- Cache the build directory between CI runs — clang-tidy does not have its own cache but benefits from precompiled headers and object file reuse.
- Run `bugprone-*` and `cppcoreguidelines-*` on all files; defer `modernize-*` to periodic refactoring runs rather than blocking CI on style upgrades.
- Exclude third-party dependencies (`vendor/`, `third_party/`) via `HeaderFilterRegex` — analyzing headers from dependencies wastes time and produces irrelevant findings.
- `clang-analyzer-*` checks perform deep path-sensitive analysis — significantly slower than syntactic checks. Run them in a separate nightly CI job.

## Security

clang-tidy catches security-critical C/C++ patterns:

- `bugprone-buffer-overflow` — fixed-size buffer writes without bounds checking.
- `cppcoreguidelines-pro-bounds-array-to-pointer-decay` — array-to-pointer decay loses bounds information.
- `cppcoreguidelines-pro-type-reinterpret-cast` — `reinterpret_cast` can subvert type safety and lead to UB.
- `cert-err33-c` — unchecked return values from functions that indicate failure (like `malloc`, `fopen`).
- `clang-analyzer-security.insecureAPI.*` — use of deprecated and insecure C library functions (`gets`, `strcpy`, `sprintf`).
- `clang-analyzer-cplusplus.NewDelete*` — memory management errors: double-free, use-after-free.

For comprehensive C/C++ security analysis, pair clang-tidy with `cppcheck` (different analysis engine, complementary findings) and address sanitizer (ASan) at runtime.

## Testing

```bash
# Analyze a single file
clang-tidy src/main.cpp -- -std=c++17 -I include/

# Analyze using compile_commands.json
clang-tidy -p build/ src/main.cpp

# Run all files in parallel
run-clang-tidy -p build/ -j4

# List available checks
clang-tidy --list-checks

# Enable all checks (for exploration)
clang-tidy --checks='*' src/main.cpp -- -std=c++17

# Apply auto-fixes
clang-tidy --fix src/main.cpp -- -std=c++17

# Apply fixes and show diff
clang-tidy --fix-errors --export-fixes=fixes.yaml src/*.cpp -- -std=c++17
clang-apply-replacements .
```

## Dos

- Generate `compile_commands.json` via CMake (`-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) — clang-tidy needs it for header resolution and semantic analysis.
- Enable `bugprone-*` and `cppcoreguidelines-pro-*` as mandatory checks — they catch memory safety, lifetime, and type safety issues with high precision.
- Restrict `HeaderFilterRegex` to your own headers — without it, clang-tidy analyzes all included headers including system headers and third-party code.
- Use `NOLINT` with a specific check name rather than bare `NOLINT` — bare `NOLINT` suppresses all checks on the line and masks future findings.
- Run `modernize-*` checks separately as optional/informational — they are useful for migrations but are too noisy as mandatory CI blockers on existing codebases.

## Don'ts

- Don't run clang-tidy without `compile_commands.json` using bare `--` fallback flags — missing include paths cause phantom "file not found" errors that hide real findings.
- Don't enable `cppcoreguidelines-*` as a blanket deny on legacy C codebases — many guidelines assume modern C++ and produce false positives on valid C patterns.
- Don't skip `HeaderFilterRegex` — analyzing system headers produces hundreds of irrelevant findings that drown out real issues in your code.
- Don't use `CMAKE_CXX_CLANG_TIDY` as the only CI integration — it runs during every build and slows incremental compilation. Use `run-clang-tidy` in a separate CI step.
- Don't suppress `clang-analyzer-security.*` findings without investigation — these represent deep path-sensitive analysis findings with low false-positive rates.
