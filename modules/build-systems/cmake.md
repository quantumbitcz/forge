# CMake

## Overview

CMake is a cross-platform meta-build system that generates native build files (Makefiles, Ninja files, Visual Studio solutions, Xcode projects) from a declarative project description written in `CMakeLists.txt`. It is the de facto standard for C and C++ projects, widely adopted in embedded systems, game engines, scientific computing, and systems programming. CMake does not build code directly — it generates build system files that are then executed by the native build tool. This two-phase design (configure + build) enables CMake to target any platform and IDE without modification to the project's build description.

Use CMake when the project is C, C++, or a polyglot codebase that includes native components. CMake's cross-compilation toolchain system handles ARM, RISC-V, and embedded targets with the same project files used for desktop builds. FetchContent and the newer CMake dependency providers integrate with package managers (vcpkg, Conan) while maintaining CMake's hermetic configure-time dependency resolution. For projects that target multiple platforms (Linux, macOS, Windows, embedded), CMake's generator abstraction is invaluable — the same `CMakeLists.txt` produces Makefiles on Linux, Ninja files on CI, and Visual Studio solutions on Windows.

Do not use CMake for pure managed-language projects (Java, Python, JavaScript, Rust) — each has a superior native build tool. CMake's learning curve is steep compared to language-specific tools, and its scripting language has well-known ergonomic issues (stringly-typed variables, implicit scoping, macro hygiene problems). For Rust projects that need C/C++ interop, Cargo's `build.rs` with the `cc` crate is simpler than managing a separate CMake build. For Go projects with CGo dependencies, Go's build system handles C compilation natively. Use CMake only when the C/C++ component is large enough to justify a dedicated build description.

Key differentiators from other native build tools: (1) CMake is a generator, not a build tool — it produces Ninja/Make/MSVC project files, letting the actual build tool handle scheduling, parallelism, and incremental compilation. (2) Modern CMake (3.0+) uses target-based configuration rather than directory-scoped variables, enabling proper dependency propagation and encapsulation. (3) CMake Presets (3.19+) standardize configure/build/test/workflow invocations in a version-controlled JSON file, eliminating ad-hoc shell scripts. (4) FetchContent (3.11+) downloads and builds dependencies at configure time, providing source-level dependency management without external package managers. (5) CTest integrates test discovery and execution with CDash for CI result aggregation.

## Architecture Patterns

### Target-Based Modern CMake

Modern CMake (3.0+) centers everything on targets. A target represents a library, executable, or custom command with associated properties (sources, include directories, compile options, link dependencies). Properties propagate through the dependency graph via `PUBLIC`, `PRIVATE`, and `INTERFACE` keywords — this replaces the old directory-scoped variable approach where settings leaked between unrelated targets.

**Minimal modern CMake project:**
```cmake
cmake_minimum_required(VERSION 3.25)
project(my-project
    VERSION 1.0.0
    LANGUAGES CXX
    DESCRIPTION "Example modern CMake project"
)

# Set C++ standard as a target property, not a global variable
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Export compile_commands.json for IDE support (clangd, clang-tidy)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_subdirectory(src)
add_subdirectory(tests)
```

The critical insight of modern CMake is the distinction between `PUBLIC`, `PRIVATE`, and `INTERFACE`:
- `PRIVATE` — applies only to the target itself. Use for implementation details.
- `PUBLIC` — applies to the target AND propagates to anything that links against it. Use for headers that are part of the public API.
- `INTERFACE` — applies only to consumers, not the target itself. Use for header-only libraries.

**Library target with proper encapsulation:**
```cmake
# src/core/CMakeLists.txt
add_library(core)

target_sources(core
    PRIVATE
        core.cpp
        internal/parser.cpp
        internal/validator.cpp
    PUBLIC
        FILE_SET HEADERS
        BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include
        FILES
            include/core/api.hpp
            include/core/types.hpp
)

target_include_directories(core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/internal
)

target_compile_features(core PUBLIC cxx_std_23)

target_compile_options(core
    PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang>:-Wall -Wextra -Wpedantic -Werror>
        $<$<CXX_COMPILER_ID:MSVC>:/W4 /WX>
)
```

Generator expressions (`$<...>`) are CMake's mechanism for conditional configuration that adapts to the build type, compiler, platform, or install context. The `BUILD_INTERFACE` / `INSTALL_INTERFACE` pattern ensures include paths are correct both during the build (pointing to source directories) and after installation (pointing to installed include directories). This duality is what makes CMake targets portable and installable.

**Executable target linking against the library:**
```cmake
# src/app/CMakeLists.txt
add_executable(app)

target_sources(app PRIVATE main.cpp)
target_link_libraries(app PRIVATE core)
```

`target_link_libraries(app PRIVATE core)` does everything: it adds `core`'s public include directories to `app`'s include path, links against `core`'s compiled library, and propagates any transitive dependencies that `core` declared as `PUBLIC`. The developer never manually manages include paths or linker flags for dependencies — the target dependency graph handles it automatically.

**Header-only library (interface target):**
```cmake
add_library(json-utils INTERFACE)

target_sources(json-utils
    INTERFACE
        FILE_SET HEADERS
        BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include
        FILES include/json_utils.hpp
)

target_compile_features(json-utils INTERFACE cxx_std_23)
target_link_libraries(json-utils INTERFACE nlohmann_json::nlohmann_json)
```

Interface libraries have no compiled sources — they exist only to propagate include paths, compile features, and transitive dependencies to consumers. They are the correct way to model header-only libraries in CMake.

### Cross-Compilation Toolchains

CMake's toolchain file system enables building for a different target platform than the host. A toolchain file sets the compiler, sysroot, target architecture, and system name — everything CMake needs to generate build files for the target platform. This is essential for embedded systems, mobile platforms, and heterogeneous deployments.

**ARM cross-compilation toolchain file (`toolchains/arm-none-eabi.cmake`):**
```cmake
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

# Compiler paths (adjust to your toolchain installation)
set(CMAKE_C_COMPILER arm-none-eabi-gcc)
set(CMAKE_CXX_COMPILER arm-none-eabi-g++)
set(CMAKE_ASM_COMPILER arm-none-eabi-gcc)

set(CMAKE_FIND_ROOT_PATH /usr/arm-none-eabi)

# Search for programs on the host, libraries and headers on the target
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Disable shared libraries for bare-metal targets
set(BUILD_SHARED_LIBS OFF)

# Embedded-specific flags
set(CMAKE_C_FLAGS_INIT "-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16")
set(CMAKE_CXX_FLAGS_INIT "-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 -fno-exceptions -fno-rtti")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-specs=nosys.specs -specs=nano.specs")
```

**Using the toolchain with presets (preferred) or command line:**
```bash
# Command line
cmake -B build-arm \
  -DCMAKE_TOOLCHAIN_FILE=toolchains/arm-none-eabi.cmake \
  -DCMAKE_BUILD_TYPE=Release

# Or via presets (see CMake Presets section)
cmake --preset arm-release
```

The toolchain file is evaluated before any project code, so it configures the compiler and platform detection before `project()` runs. Never set `CMAKE_C_COMPILER` or `CMAKE_CXX_COMPILER` inside `CMakeLists.txt` — it must be in the toolchain file or on the command line, because CMake's compiler detection runs exactly once during the first configure.

**Android NDK toolchain (built into the NDK):**
```bash
cmake -B build-android \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-26
```

**iOS/macOS cross-compilation:**
```cmake
# toolchains/ios.cmake
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0")
set(CMAKE_OSX_ARCHITECTURES "arm64")
set(CMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "TEAM_ID")
```

### FetchContent for Dependencies

FetchContent (CMake 3.11+) downloads, configures, and builds dependencies at configure time, integrating them as if they were subdirectories of the project. It replaces the fragile pattern of manually downloading dependencies, using `ExternalProject_Add` (which runs at build time, breaking dependency tracking), or requiring system-installed packages.

**Fetching dependencies with version pinning:**
```cmake
include(FetchContent)

FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG v3.11.3
    GIT_SHALLOW ON
    FIND_PACKAGE_ARGS  # Try find_package() first, fall back to download
)

FetchContent_Declare(
    fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG 11.0.2
    GIT_SHALLOW ON
)

FetchContent_Declare(
    spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG v1.15.0
    GIT_SHALLOW ON
)

FetchContent_MakeAvailable(nlohmann_json fmt spdlog)
```

`FetchContent_MakeAvailable` downloads (if not cached), configures, and builds each dependency. The `FIND_PACKAGE_ARGS` option (CMake 3.24+) checks if the dependency is already installed via `find_package()` before downloading — this enables seamless integration with system package managers and vcpkg/Conan.

`GIT_SHALLOW ON` avoids cloning the full repository history, significantly reducing download time for large repositories. Always pin to a specific tag or commit hash — never use a branch name, as branches are mutable and break build reproducibility.

**Using fetched dependencies:**
```cmake
target_link_libraries(core
    PUBLIC nlohmann_json::nlohmann_json
    PRIVATE fmt::fmt spdlog::spdlog
)
```

Fetched dependencies expose their targets through the same namespace as `find_package()`. This means switching between FetchContent and system-installed packages is transparent to consuming targets.

**Dependency provider pattern (CMake 3.24+) with vcpkg:**
```cmake
# CMakePresets.json (excerpt)
{
    "configurePresets": [{
        "name": "vcpkg",
        "cacheVariables": {
            "CMAKE_TOOLCHAIN_FILE": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
        }
    }]
}
```

The dependency provider mechanism redirects `FetchContent_Declare` and `find_package()` calls through a package manager. With vcpkg as the provider, FetchContent declarations become hints — vcpkg resolves the actual packages from its registry, ensuring consistent versions across the organization.

### CMake Presets

CMake Presets (3.19+) replace ad-hoc shell scripts and tribal knowledge with a version-controlled JSON file that standardizes how the project is configured, built, tested, and packaged. Presets eliminate the "works on my machine" problem for build configuration.

**`CMakePresets.json` — committed to version control:**
```json
{
    "version": 6,
    "cmakeMinimumRequired": { "major": 3, "minor": 25, "patch": 0 },
    "configurePresets": [
        {
            "name": "base",
            "hidden": true,
            "generator": "Ninja",
            "binaryDir": "${sourceDir}/build/${presetName}",
            "cacheVariables": {
                "CMAKE_EXPORT_COMPILE_COMMANDS": "ON",
                "BUILD_TESTING": "ON"
            }
        },
        {
            "name": "dev-debug",
            "displayName": "Development Debug",
            "inherits": "base",
            "cacheVariables": {
                "CMAKE_BUILD_TYPE": "Debug",
                "ENABLE_SANITIZERS": "ON"
            }
        },
        {
            "name": "dev-release",
            "displayName": "Development Release",
            "inherits": "base",
            "cacheVariables": {
                "CMAKE_BUILD_TYPE": "RelWithDebInfo"
            }
        },
        {
            "name": "ci-release",
            "displayName": "CI Release",
            "inherits": "base",
            "cacheVariables": {
                "CMAKE_BUILD_TYPE": "Release",
                "CMAKE_INTERPROCEDURAL_OPTIMIZATION": "ON"
            }
        },
        {
            "name": "arm-release",
            "displayName": "ARM Cross-Compilation Release",
            "inherits": "base",
            "toolchainFile": "toolchains/arm-none-eabi.cmake",
            "cacheVariables": {
                "CMAKE_BUILD_TYPE": "MinSizeRel"
            }
        }
    ],
    "buildPresets": [
        {
            "name": "dev-debug",
            "configurePreset": "dev-debug"
        },
        {
            "name": "ci-release",
            "configurePreset": "ci-release",
            "jobs": 0
        }
    ],
    "testPresets": [
        {
            "name": "dev-debug",
            "configurePreset": "dev-debug",
            "output": {
                "outputOnFailure": true,
                "verbosity": "default"
            }
        },
        {
            "name": "ci-release",
            "configurePreset": "ci-release",
            "output": {
                "outputOnFailure": true,
                "verbosity": "verbose"
            },
            "execution": {
                "jobs": 0,
                "timeout": 300
            }
        }
    ]
}
```

**`CMakeUserPresets.json` — gitignored, per-developer overrides:**
```json
{
    "version": 6,
    "configurePresets": [
        {
            "name": "my-dev",
            "inherits": "dev-debug",
            "cacheVariables": {
                "CMAKE_C_COMPILER": "/opt/homebrew/bin/gcc-14",
                "CMAKE_CXX_COMPILER": "/opt/homebrew/bin/g++-14"
            }
        }
    ]
}
```

**Using presets:**
```bash
# Configure
cmake --preset dev-debug

# Build
cmake --build --preset dev-debug

# Test
ctest --preset dev-debug

# List available presets
cmake --list-presets
```

Presets compose via inheritance (`"inherits": "base"`), allowing a hierarchy: base settings, platform-specific overrides, and CI/developer variations. The `CMakeUserPresets.json` file (gitignored) lets developers customize compiler paths, generator preferences, and local tool locations without modifying the committed presets.

## Configuration

### Development

CMake's configuration is two-phase: the configure step evaluates `CMakeLists.txt` and generates build files, and the build step executes them. Configuration results are cached in `CMakeCache.txt` — subsequent reconfigures only re-evaluate changed variables. This cache is both a feature (fast reconfigures) and a trap (stale cache entries cause mysterious behavior after refactoring).

**Development workflow:**
```bash
# Initial configure + build
cmake --preset dev-debug
cmake --build --preset dev-debug

# Rebuild after source changes (incremental, fast)
cmake --build --preset dev-debug

# Reconfigure after CMakeLists.txt changes
cmake --preset dev-debug  # Automatically re-runs configure

# Clean build (when cache is suspect)
rm -rf build/dev-debug
cmake --preset dev-debug
cmake --build --preset dev-debug
```

**Sanitizer configuration for development builds:**
```cmake
option(ENABLE_SANITIZERS "Enable ASan + UBSan" OFF)

if(ENABLE_SANITIZERS)
    add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address,undefined)
endif()
```

Address Sanitizer (ASan) and Undefined Behavior Sanitizer (UBSan) catch memory errors and undefined behavior at runtime. Enable them in development builds (`dev-debug` preset) and CI. They impose ~2x runtime overhead, so disable them for performance testing and release builds.

**compile_commands.json** — export this for clangd, clang-tidy, and IDE support:
```cmake
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
```

This generates a JSON file listing every compilation command in the project. Symlink it to the source root for IDE consumption: `ln -sf build/dev-debug/compile_commands.json compile_commands.json`.

### Production

**CI build workflow:**
```bash
# Configure with CI preset
cmake --preset ci-release

# Build with all available cores
cmake --build --preset ci-release --parallel

# Run tests
ctest --preset ci-release

# Install to staging directory
cmake --install build/ci-release --prefix staging/
```

**GitHub Actions example:**
```yaml
- name: Install Ninja
  run: sudo apt-get install -y ninja-build

- name: Configure
  run: cmake --preset ci-release

- name: Build
  run: cmake --build --preset ci-release --parallel

- name: Test
  run: ctest --preset ci-release --output-junit test-results.xml

- name: Publish test results
  uses: mikepenz/action-junit-report@v4
  if: always()
  with:
    report_paths: test-results.xml
```

**CPack for packaging:**
```cmake
# At the end of the root CMakeLists.txt
include(CPack)
set(CPACK_GENERATOR "TGZ;DEB;RPM")
set(CPACK_PACKAGE_CONTACT "team@example.com")
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libc6 (>= 2.34)")
```

```bash
# Generate packages
cd build/ci-release
cpack --config CPackConfig.cmake
```

CPack generates distributable packages (tarballs, DEBs, RPMs, NuGet, NSIS installers) from the install rules defined in `CMakeLists.txt`. It uses the same `install()` commands that `cmake --install` uses, ensuring consistency between development installs and packaged releases.

## Performance

**Ninja vs Make** — always use Ninja as the generator for both development and CI. Ninja was designed for speed: it tracks file-level dependencies, builds incrementally, and parallelizes by default. Make has historical baggage (recursive make, slow dependency scanning, no built-in parallelism). Ninja is typically 10-30% faster on full builds and dramatically faster on incremental builds.

```bash
# Set Ninja as default in presets (recommended)
# Or via command line
cmake -G Ninja -B build
cmake --build build --parallel
```

**Configure-time performance:**
- Use `GIT_SHALLOW ON` in all `FetchContent_Declare` calls to avoid cloning full histories.
- Use `FIND_PACKAGE_ARGS` to prefer system-installed packages over downloading from source.
- Minimize `file(GLOB ...)` usage — globbing re-runs on every configure and does not detect new/deleted files without a reconfigure. Prefer explicit source lists.
- Use `FetchContent_MakeAvailable` for multiple dependencies in a single call — it batches the downloads.

**Build-time performance:**
- Enable link-time optimization (LTO/IPO) for release builds only — it significantly increases link time but produces faster binaries:
  ```cmake
  set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
  ```
- Use `ccache` or `sccache` for compilation caching across builds:
  ```cmake
  find_program(CCACHE_PROGRAM ccache)
  if(CCACHE_PROGRAM)
      set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
      set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE_PROGRAM})
  endif()
  ```
- Use precompiled headers for large projects with slow header parsing:
  ```cmake
  target_precompile_headers(core PRIVATE
      <vector>
      <string>
      <memory>
      <unordered_map>
  )
  ```
- Use unity builds (jumbo compilation) to reduce compilation overhead for large translation unit counts:
  ```cmake
  set(CMAKE_UNITY_BUILD ON)
  set(CMAKE_UNITY_BUILD_BATCH_SIZE 16)
  ```

**Incremental build performance:**
- Keep the build directory intact between builds — deleting it forces a full reconfigure and rebuild.
- Avoid `add_custom_command` that touches files outside the build directory — it breaks incremental dependency tracking.
- Use `DEPFILE` in custom commands to generate dependency files that Ninja can track.

**Build profiling:**
```bash
# Ninja build time log
ninja -C build/dev-debug -j1 -d stats

# Clang build time report (per-file compilation time)
cmake -B build -DCMAKE_CXX_FLAGS="-ftime-trace"
# Produces .json flame charts next to each .o file

# Chrome tracing for Ninja (build timeline visualization)
ninja -C build -t compdb > compile_commands.json
```

## Security

**Dependency integrity** — FetchContent downloads source code from external repositories. Pin to exact commit hashes or signed tags for production builds:
```cmake
FetchContent_Declare(
    fmt
    GIT_REPOSITORY https://github.com/fmtlib/fmt.git
    GIT_TAG e69e5f977d458f2650bb346dadf2ad30c5320281  # v11.0.2 exact commit
    GIT_SHALLOW ON
)
```

Tag names can be force-pushed. Commit hashes are immutable. For security-critical dependencies, verify the commit hash against the project's release notes or GPG-signed tags.

**Compiler hardening flags:**
```cmake
# Security hardening for release builds
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    target_compile_options(core PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang>:
            -fstack-protector-strong
            -D_FORTIFY_SOURCE=2
            -fPIE
        >
    )
    target_link_options(core PRIVATE
        $<$<CXX_COMPILER_ID:GNU,Clang>:
            -Wl,-z,relro,-z,now
            -pie
        >
    )
endif()
```

- `-fstack-protector-strong` — stack buffer overflow detection.
- `-D_FORTIFY_SOURCE=2` — runtime checks for buffer overflows in libc functions.
- `-fPIE` / `-pie` — position-independent executable for ASLR.
- `-Wl,-z,relro,-z,now` — full RELRO to prevent GOT overwrite attacks.

**No secrets in CMakeLists.txt or presets** — use environment variables or file-based secrets:
```cmake
# Read signing key from environment
set(SIGNING_KEY "$ENV{CODE_SIGNING_KEY}")
if(NOT SIGNING_KEY)
    message(WARNING "CODE_SIGNING_KEY not set — binaries will not be signed")
endif()
```

**Static analysis integration:**
```cmake
# clang-tidy integration (runs during compilation)
set(CMAKE_CXX_CLANG_TIDY "clang-tidy;-checks=*,-modernize-use-trailing-return-type")

# cppcheck integration
find_program(CPPCHECK cppcheck)
if(CPPCHECK)
    set(CMAKE_CXX_CPPCHECK ${CPPCHECK}
        --enable=warning,performance,portability
        --suppress=missingIncludeSystem
        --inline-suppr
    )
endif()
```

Running static analysis as part of the build ensures every compilation triggers analysis. This catches security issues (buffer overflows, use-after-free, null dereference) at compile time rather than in a separate CI step that developers can ignore.

**Supply chain hardening checklist:**
- Pin all FetchContent dependencies to exact commit hashes or signed release tags.
- Use `FETCHCONTENT_FULLY_DISCONNECTED` in CI after initial population to detect undeclared network dependencies.
- Enable compiler hardening flags (`-fstack-protector-strong`, `-D_FORTIFY_SOURCE=2`, RELRO) for all release builds.
- Run clang-tidy and cppcheck as part of the build, not as a separate optional step.
- Use `CMAKE_VERIFY_INTERFACE_HEADER_SETS` to ensure public headers are self-contained.
- Sign release binaries and generate SBOMs (Software Bill of Materials) for deployed artifacts.

## Testing

**CTest** is CMake's built-in test runner. It discovers and executes tests registered with `add_test()`, supports parallel execution, timeout control, and output formatting for CI integration.

**Registering tests:**
```cmake
# tests/CMakeLists.txt
include(CTest)

# Fetch test framework
FetchContent_Declare(
    Catch2
    GIT_REPOSITORY https://github.com/catchorg/Catch2.git
    GIT_TAG v3.7.1
    GIT_SHALLOW ON
)
FetchContent_MakeAvailable(Catch2)

add_executable(core_tests
    core_test.cpp
    parser_test.cpp
    validator_test.cpp
)
target_link_libraries(core_tests PRIVATE core Catch2::Catch2WithMain)

# Auto-discover Catch2 tests
include(Catch)
catch_discover_tests(core_tests)
```

`catch_discover_tests` (provided by Catch2's CMake integration) runs the test executable with `--list-tests` at build time and registers each test case individually with CTest. This enables fine-grained test selection, parallel execution, and per-test timeout control — rather than treating the entire executable as a single test.

**Running tests:**
```bash
# Run all tests
ctest --preset dev-debug

# Run tests matching a pattern
ctest --preset dev-debug -R "parser"

# Run tests with verbose output on failure
ctest --preset dev-debug --output-on-failure

# Run tests in parallel (all available cores)
ctest --preset dev-debug -j 0

# Generate JUnit XML for CI
ctest --preset ci-release --output-junit test-results.xml
```

**GoogleTest integration:**
```cmake
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
    GIT_SHALLOW ON
)
FetchContent_MakeAvailable(googletest)

include(GoogleTest)

add_executable(core_tests core_test.cpp)
target_link_libraries(core_tests PRIVATE core GTest::gtest_main)
gtest_discover_tests(core_tests)
```

**Valgrind integration via CTest:**
```cmake
# In CTestCustom.cmake or via command line
set(MEMORYCHECK_COMMAND_OPTIONS "--leak-check=full --show-reachable=yes --error-exitcode=1")
```

```bash
ctest --preset dev-debug -T memcheck
```

CTest runs each test under Valgrind and reports memory leaks, invalid reads/writes, and uninitialized value usage. This is essential for C/C++ projects where memory safety is not guaranteed by the language.

**Code coverage with gcov/llvm-cov:**
```cmake
option(ENABLE_COVERAGE "Enable code coverage" OFF)
if(ENABLE_COVERAGE)
    target_compile_options(core PRIVATE --coverage)
    target_link_options(core PRIVATE --coverage)
endif()
```

```bash
# Build with coverage
cmake --preset dev-debug -DENABLE_COVERAGE=ON
cmake --build --preset dev-debug
ctest --preset dev-debug

# Generate HTML report
gcovr --root . --html-details coverage.html build/dev-debug/
```

**Testing cross-compiled code** — when cross-compiling, tests cannot run on the host. Use CTest's cross-compilation support:
```cmake
# Set in the toolchain file
set(CMAKE_CROSSCOMPILING_EMULATOR "qemu-arm;-L;/usr/arm-linux-gnueabihf")
```

CTest will automatically run each test under the specified emulator. For QEMU-supported architectures, this enables full test execution on CI without target hardware.

## Dos

- Use target-based configuration (`target_compile_options`, `target_include_directories`, `target_link_libraries`) instead of directory-scoped commands (`add_compile_options`, `include_directories`, `link_libraries`). Targets encapsulate properties and propagate them through the dependency graph — directory-scoped commands leak to everything in the current directory and below.
- Use `PUBLIC`, `PRIVATE`, and `INTERFACE` keywords on every `target_*` command. These keywords control dependency propagation — omitting them defaults to `PUBLIC`, which leaks implementation details to consumers. Default to `PRIVATE` and promote to `PUBLIC` only when the dependency is part of the target's public API.
- Use CMake Presets (`CMakePresets.json`) for all standard build configurations. Presets eliminate ad-hoc shell scripts, document the project's supported configurations, and integrate with IDE preset selection (CLion, VS Code, Visual Studio).
- Use Ninja as the generator for all development and CI builds. Ninja's incremental build tracking, parallel execution, and minimal overhead produce significantly faster builds than Make.
- Pin FetchContent dependencies to exact commit hashes or immutable release tags. Git tags are mutable (can be force-pushed) — commit hashes are the only truly immutable reference. For critical dependencies, verify the hash against the project's signed releases.
- Enable `CMAKE_EXPORT_COMPILE_COMMANDS` for IDE and static analysis tool support. The `compile_commands.json` file enables clangd, clang-tidy, and cppcheck to analyze the project with the exact same flags used during compilation.
- Use `ccache` or `sccache` as the compiler launcher to cache compilation results across builds. Compilation caching provides dramatic speedups for clean builds and branch switches.
- Enable compiler warnings (`-Wall -Wextra -Wpedantic -Werror`) and static analysis (`clang-tidy`, `cppcheck`) in all development and CI builds. C/C++ has no safety net — static analysis is the first line of defense against undefined behavior and security vulnerabilities.
- Use `cmake_minimum_required(VERSION 3.25)` or later to access modern features (presets v6, FILE_SET, dependency providers). Do not support ancient CMake versions unless the project must build on legacy systems.
- Separate public headers from private implementation files using `target_sources` with `FILE_SET HEADERS` (CMake 3.23+). This replaces manual `install(FILES ...)` commands and ensures installed headers match the build's public API.

## Don'ts

- Don't use directory-scoped commands (`add_compile_options`, `include_directories`, `link_libraries`, `add_definitions`) in multi-target directories. They affect every target defined in the current directory and below, creating invisible coupling. Use `target_compile_options`, `target_include_directories`, `target_link_libraries`, and `target_compile_definitions` instead.
- Don't set `CMAKE_CXX_COMPILER` inside `CMakeLists.txt`. The compiler must be set before the `project()` command runs — either in a toolchain file, a preset, or on the command line. Setting it inside `CMakeLists.txt` causes undefined behavior because compiler detection has already completed.
- Don't use `file(GLOB ...)` to collect source files. Globbing runs at configure time and does not detect new or deleted files until the next reconfigure. CMake's own documentation discourages it. Use explicit source lists in `target_sources()` — they are the source of truth for what gets compiled.
- Don't use `ExternalProject_Add` when `FetchContent` is available. ExternalProject runs at build time, which means the external project's targets are not available during configure — breaking `target_link_libraries` and dependency propagation. FetchContent runs at configure time and integrates seamlessly.
- Don't modify `CMAKE_CXX_FLAGS` globally. Global flag modification affects every target in the project, including fetched dependencies that may not compile with your warning settings. Use `target_compile_options` with `PRIVATE` scope to apply flags only where they are needed.
- Don't rely on `CMAKE_BUILD_TYPE` in multi-configuration generators (Visual Studio, Xcode). These generators build all configurations from a single configure step — `CMAKE_BUILD_TYPE` is empty. Use generator expressions (`$<CONFIG:Release>`) for configuration-dependent logic.
- Don't use `IMPORTED_LOCATION` directly when `find_package()` provides proper imported targets. Manually setting imported target properties bypasses version checking, transitive dependency propagation, and configuration mapping. Use `find_package()` with `CONFIG` mode whenever a proper CMake config is available.
- Don't skip `cmake_minimum_required()` or set it to an ancient version "for compatibility." The minimum version affects CMake's policy defaults — setting it to 2.8 enables decade-old behaviors that conflict with modern CMake patterns, producing confusing warnings and broken builds.
- Don't use `CMAKE_SOURCE_DIR` or `CMAKE_BINARY_DIR` in library code — they refer to the top-level project, which is wrong when the library is consumed via `FetchContent` or `add_subdirectory`. Use `CMAKE_CURRENT_SOURCE_DIR` and `PROJECT_SOURCE_DIR` instead.
- Don't create build scripts that require manual environment setup beyond installing CMake and a compiler. Presets, FetchContent, and toolchain files should encode everything needed to configure, build, and test the project reproducibly.
