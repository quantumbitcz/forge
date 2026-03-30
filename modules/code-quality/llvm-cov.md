# llvm-cov

## Overview

`llvm-cov` measures source-based coverage for Rust, C, and C++. For Rust, `cargo llvm-cov` is the idiomatic wrapper — it sets the correct LLVM flags and merges `.profraw` files automatically. For C/C++, compile with `-fprofile-instr-generate -fcoverage-mapping`, run the binary, then process `.profraw` files with `llvm-profdata merge` and `llvm-cov report/show`. LCOV output (`--format=lcov`) integrates with Codecov, Sonar, and `genhtml` for HTML reports. Source-based coverage is more accurate than gcov/gcda because it tracks every region, branch, and expression.

## Architecture Patterns

### Installation & Setup

**Rust — cargo-llvm-cov:**
```bash
cargo install cargo-llvm-cov
# Also need llvm-tools-preview component:
rustup component add llvm-tools-preview
```

```bash
# Run tests and generate LCOV
cargo llvm-cov --lcov --output-path coverage.lcov

# HTML report
cargo llvm-cov --html --output-dir coverage/

# Text summary to stdout
cargo llvm-cov

# With nextest (faster test runner)
cargo llvm-cov nextest --lcov --output-path coverage.lcov
```

**C/C++ — LLVM toolchain:**
```bash
# Compile with coverage instrumentation (Clang required)
clang -fprofile-instr-generate -fcoverage-mapping -o myapp src/main.c

# Run the binary (generates default.profraw)
./myapp

# Merge raw profiles
llvm-profdata merge -sparse default.profraw -o default.profdata

# Generate LCOV report
llvm-cov export ./myapp \
  --instr-profile=default.profdata \
  --format=lcov \
  --ignore-filename-regex="(/usr/|test_|_test\\.)" \
  > coverage.lcov

# Text summary
llvm-cov report ./myapp --instr-profile=default.profdata

# HTML via genhtml
genhtml coverage.lcov --output-directory coverage/
```

### Rule Categories

| Coverage Type | Description | Tool Flag |
|---|---|---|
| Region | Individual source regions (finer than line) | default |
| Branch | Taken/not-taken for conditionals | `--show-branches=count` |
| Line | Lines executed | `--format=lcov` line data |
| Function | Functions entered | reported in summary |
| MC/DC | Modified Condition/Decision Coverage (safety-critical) | experimental in LLVM 18+ |

### Configuration Patterns

**cargo-llvm-cov workspace with exclusions:**
```toml
# .cargo/config.toml or Cargo.toml
[workspace.metadata.llvm-cov]
exclude = ["tests/*", "examples/*", "benches/*"]
```

```bash
# Exclude specific packages in workspace
cargo llvm-cov --workspace \
  --exclude myapp-cli \
  --exclude myapp-bench \
  --lcov --output-path coverage.lcov

# Fail if below threshold
cargo llvm-cov --fail-under-lines 80
```

**C/C++ CMake integration:**
```cmake
# CMakeLists.txt — coverage build type
if(CMAKE_BUILD_TYPE STREQUAL "Coverage")
  if(CMAKE_C_COMPILER_ID MATCHES "Clang")
    add_compile_options(-fprofile-instr-generate -fcoverage-mapping)
    add_link_options(-fprofile-instr-generate)
  endif()
endif()
```

```bash
cmake -DCMAKE_BUILD_TYPE=Coverage -DCMAKE_C_COMPILER=clang ..
make
ctest                                   # runs tests, produces *.profraw
llvm-profdata merge -sparse *.profraw -o merged.profdata
llvm-cov export ./myapp --instr-profile=merged.profdata --format=lcov > coverage.lcov
```

**Multiple test binaries (Rust):**
```bash
# cargo llvm-cov handles this automatically
# For C/C++, merge all .profraw files:
llvm-profdata merge -sparse test_*.profraw integration_*.profraw -o all.profdata
llvm-cov report ./libmylib.a --instr-profile=all.profdata
```

### CI Integration

```yaml
# .github/workflows/coverage.yml
- name: Install cargo-llvm-cov
  uses: taiki-e/install-action@cargo-llvm-cov

- name: Run coverage (Rust)
  run: cargo llvm-cov --workspace --lcov --output-path coverage.lcov --fail-under-lines 80

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage.lcov
    fail_ci_if_error: true

- name: Upload HTML report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: coverage-html
    path: coverage/
```

**C/C++ CI:**
```yaml
- name: Install LLVM
  run: sudo apt-get install -y clang llvm lcov

- name: Build with coverage
  run: |
    cmake -B build -DCMAKE_BUILD_TYPE=Coverage -DCMAKE_C_COMPILER=clang
    cmake --build build

- name: Run tests and generate coverage
  run: |
    cd build && ctest
    llvm-profdata merge -sparse *.profraw -o coverage.profdata
    llvm-cov export ./myapp --instr-profile=coverage.profdata --format=lcov > coverage.lcov
    genhtml coverage.lcov --output-directory coverage-html/

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: build/coverage.lcov
```

## Performance

- Source-based coverage (LLVM) adds 5-15% runtime overhead vs uninstrumented binary — lighter than gcov's 20-50%.
- `cargo llvm-cov` restores the original build artifacts after the coverage run so incremental builds are not invalidated.
- Use `--sparse` with `llvm-profdata merge` to reduce profile file size for large projects.
- `llvm-cov show` with `--format=html` is slow for large codebases — use `genhtml coverage.lcov` instead for faster HTML generation.
- For C/C++ with many test binaries, merge all `.profraw` in one `llvm-profdata merge` call rather than sequential merges.

## Security

- `.profraw` files contain runtime execution paths — they may reveal code flow in security-sensitive applications. Treat as build artifacts, not public assets.
- Coverage-instrumented binaries are larger (contain debug metadata) — never ship them to production.
- HTML coverage reports embed source code — do not publish publicly for proprietary C/C++ code.
- `LLVM_PROFILE_FILE` environment variable controls where profile data is written — set it explicitly to avoid `.profraw` files in unexpected locations.

## Testing

```bash
# Rust: quick text summary
cargo llvm-cov

# Rust: full LCOV + HTML
cargo llvm-cov --workspace --lcov --output-path coverage.lcov --html --output-dir coverage/

# Rust: fail if under threshold
cargo llvm-cov --fail-under-lines 80

# C/C++: full pipeline
clang -fprofile-instr-generate -fcoverage-mapping -o test_bin ./tests/*.c
LLVM_PROFILE_FILE="test_%p.profraw" ./test_bin
llvm-profdata merge -sparse test_*.profraw -o test.profdata
llvm-cov report ./test_bin --instr-profile=test.profdata
llvm-cov export ./test_bin --instr-profile=test.profdata --format=lcov > coverage.lcov
genhtml coverage.lcov -o coverage-html/
open coverage-html/index.html
```

## Dos

- Use `cargo llvm-cov` for Rust — it handles LLVM flag setup, profraw file collection, and merging automatically.
- Use `--format=lcov` for CI output — LCOV is universally supported by Codecov, Sonar, and Coveralls.
- Set `LLVM_PROFILE_FILE="prefix_%p_%m.profraw"` for programs that fork or spawn processes — `%p` embeds PID and `%m` embeds module signature to avoid overwrites.
- Use `llvm-profdata merge --sparse` to reduce profile size — non-sparse profiles are significantly larger for sparsely covered code.
- Add `--ignore-filename-regex` in `llvm-cov export` to exclude test files and third-party headers from the report.
- Pin LLVM toolchain version in CI — coverage format changes between LLVM major versions.

## Don'ts

- Don't use `-fprofile-arcs -ftest-coverage` (gcov flags) with Clang for new projects — LLVM source-based coverage is more accurate and integrates better with `llvm-cov`.
- Don't run coverage on release builds without `-g` debug info — `llvm-cov show` will be unable to map regions to source lines.
- Don't ship coverage-instrumented binaries — they write profile data to disk on every run and are significantly larger.
- Don't merge `.profraw` files from different binaries/builds into the same `profdata` — use separate profdata files per binary.
- Don't ignore the `LLVM_PROFILE_FILE` environment variable for integration tests — without it, all processes write to `default.profraw` and overwrite each other.
