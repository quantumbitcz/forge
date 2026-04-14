# Bazel

## Overview

Bazel is a polyglot build system developed by Google that prioritizes correctness, reproducibility, and scalability over configuration simplicity. It models builds as hermetic, deterministic functions of their declared inputs — given the same source files and build rules, Bazel produces identical outputs regardless of the machine, user, or time of execution. This hermeticity enables aggressive caching (local and remote), remote execution across distributed build farms, and guaranteed reproducibility for compliance-critical environments.

Use Bazel when the project is a large-scale monorepo (hundreds of modules, multiple languages), when build correctness and reproducibility are non-negotiable requirements (regulatory, financial, safety-critical), when remote execution and distributed caching are needed to keep build times manageable as the codebase scales, or when the project spans multiple languages (Java, Go, Python, C++, TypeScript, Rust) and needs a single build system with uniform semantics across all of them. Bazel's strength scales with project size — a 10-module project may find Bazel's overhead excessive, but a 500-module monorepo will find it indispensable.

Do not use Bazel for small projects (under 20 modules) — the learning curve and configuration overhead outweigh the benefits at small scale. Do not use Bazel when the team is unfamiliar with it and has no time for the steep onboarding — Bazel's concepts (hermeticity, sandboxing, Starlark rules, visibility) are fundamentally different from Gradle/Maven/npm, and partially adopted Bazel is worse than fully adopted simpler tools. Do not use Bazel for projects that are tightly coupled to a specific ecosystem's build tool (Android with Gradle, iOS with Xcode, Rust with Cargo) unless the project is part of a larger monorepo that already uses Bazel.

Key differentiators from other build systems: (1) Hermeticity — Bazel sandboxes every action (compilation, linking, code generation), restricting file access to declared inputs only. Undeclared dependencies cause build failures, not silent correctness issues. (2) Content-addressed caching — Bazel caches action outputs by hashing all inputs (source files, compiler version, flags, environment). Identical inputs always produce a cache hit, regardless of the machine. (3) Remote execution — Bazel can distribute build actions across a cluster of machines, turning a 60-minute local build into a 5-minute distributed build. (4) Bzlmod (CMake 3.24+ equivalent) — Bazel's module system for external dependency management, replacing the older WORKSPACE-based approach. (5) Starlark — Bazel's configuration language is a deterministic, hermetic subset of Python. Unlike Gradle's Kotlin scripts or CMake's scripting language, Starlark cannot perform I/O, access the network, or produce non-deterministic output — enforcing build reproducibility at the language level.

## Architecture Patterns

### Bzlmod Dependency Management

Bzlmod (Bazel Modules, introduced in Bazel 6.0, default in 7.0+) is Bazel's modern dependency management system. It replaces the legacy `WORKSPACE` file with a declarative `MODULE.bazel` file that describes the project's external dependencies, version constraints, and module extensions. Bzlmod uses a registry (Bazel Central Registry by default) to resolve module metadata and dependency graphs, similar to how npm uses the npm registry or Go uses the module proxy.

**`MODULE.bazel` — the project's dependency declaration:**
```python
module(
    name = "my-project",
    version = "1.0.0",
    compatibility_level = 1,
)

# Bazel rules for specific languages
bazel_dep(name = "rules_java", version = "8.6.3")
bazel_dep(name = "rules_go", version = "0.50.1")
bazel_dep(name = "rules_python", version = "1.1.0")
bazel_dep(name = "rules_proto", version = "7.1.0")

# Testing frameworks
bazel_dep(name = "rules_jvm_external", version = "6.6")
bazel_dep(name = "googletest", version = "1.15.2")

# Protobuf
bazel_dep(name = "protobuf", version = "29.3")

# JVM dependencies via rules_jvm_external
maven = use_extension("@rules_jvm_external//:extensions.bzl", "maven")
maven.install(
    artifacts = [
        "org.springframework.boot:spring-boot-starter-web:3.4.1",
        "org.springframework.boot:spring-boot-starter-actuator:3.4.1",
        "com.fasterxml.jackson.module:jackson-module-kotlin:2.18.2",
        "io.kotest:kotest-runner-junit5-jvm:5.9.1",
        "io.mockk:mockk-jvm:1.13.13",
    ],
    repositories = [
        "https://repo.maven.apache.org/maven2",
    ],
    lock_artifacts = True,
)
use_repo(maven, "maven")
```

The critical difference between Bzlmod and `WORKSPACE` is determinism: Bzlmod resolves the dependency graph once, produces a lockfile (`MODULE.bazel.lock`), and guarantees that every subsequent build uses the exact same dependency versions. `WORKSPACE` loaded repositories imperatively in file order — the final state depended on which `http_archive` calls were evaluated, with no conflict resolution, no version mediation, and no lockfile.

**`.bazelversion` — pin the Bazel version:**
```
7.5.0
```

Use Bazelisk (the Bazel Wrapper equivalent) to automatically download and use the pinned version. Never rely on a globally installed Bazel.

**`MODULE.bazel.lock` — committed to version control:**
The lockfile records the exact resolved version of every transitive dependency. Commit it and treat unexpected diffs as signals of dependency changes that need review. Regenerate it with `bazel mod deps --lockfile_mode=update`.

### Hermetic Build Rules

Bazel's power comes from its rule system. A rule defines how to transform inputs into outputs — `java_library` compiles Java sources into a JAR, `go_binary` compiles Go sources into an executable, `proto_library` generates language-specific code from `.proto` files. Rules are hermetic: they can only read declared inputs and produce declared outputs. Any file access outside this contract causes a sandbox violation.

**`BUILD.bazel` — library target:**
```python
load("@rules_java//java:defs.bzl", "java_library", "java_test")

java_library(
    name = "core",
    srcs = glob(["src/main/java/**/*.java"]),
    resources = glob(["src/main/resources/**"]),
    deps = [
        "@maven//:com_fasterxml_jackson_core_jackson_databind",
        "@maven//:org_slf4j_slf4j_api",
    ],
    visibility = ["//app:__pkg__"],
)

java_test(
    name = "core_test",
    srcs = glob(["src/test/java/**/*Test.java"]),
    test_class = "com.example.core.AllTests",
    deps = [
        ":core",
        "@maven//:io_kotest_kotest_runner_junit5_jvm",
        "@maven//:io_mockk_mockk_jvm",
    ],
    size = "small",
)
```

Key concepts:
- `visibility` controls which packages can depend on this target. Default is package-private (only BUILD files in the same directory). Use `["//visibility:public"]` sparingly — prefer explicit visibility to enforce module boundaries.
- `size` on test targets (`small`, `medium`, `large`, `enormous`) sets timeout defaults and resource allocation. Small tests timeout at 60s, medium at 300s. This prevents test suites from hanging indefinitely.
- `deps` lists direct dependencies only. Bazel resolves the full transitive closure at build time but enforces that source code only imports symbols from directly declared `deps` — this is "strict deps" and catches accidental transitive dependency usage.

**Go target example:**
```python
load("@rules_go//go:def.bzl", "go_library", "go_test", "go_binary")

go_library(
    name = "server",
    srcs = [
        "server.go",
        "handler.go",
        "middleware.go",
    ],
    importpath = "github.com/example/myproject/server",
    deps = [
        "@com_github_go_chi_chi_v5//:chi",
        "@com_github_rs_zerolog//:zerolog",
    ],
    visibility = ["//cmd:__subpackages__"],
)

go_test(
    name = "server_test",
    srcs = ["server_test.go"],
    embed = [":server"],
    deps = [
        "@com_github_stretchr_testify//assert",
    ],
)
```

**Protobuf cross-language generation:**
```python
load("@rules_proto//proto:defs.bzl", "proto_library")
load("@rules_java//java:defs.bzl", "java_proto_library")
load("@rules_go//proto:def.bzl", "go_proto_library")

proto_library(
    name = "user_proto",
    srcs = ["user.proto"],
    deps = ["@protobuf//:timestamp_proto"],
    visibility = ["//visibility:public"],
)

java_proto_library(
    name = "user_java_proto",
    deps = [":user_proto"],
)

go_proto_library(
    name = "user_go_proto",
    importpath = "github.com/example/myproject/proto/user",
    proto = ":user_proto",
)
```

This is Bazel's polyglot strength: a single `.proto` file generates Java and Go bindings through separate rules, and each generated library has proper dependency tracking. Changing `user.proto` rebuilds only the affected language bindings and their downstream consumers — nothing more.

### Remote Execution and Caching

Remote execution is Bazel's signature enterprise feature. Instead of building on the developer's machine or a single CI runner, Bazel distributes build actions across a cluster of workers. Each action (compile, link, test) is sent to a remote worker with its declared inputs, executed in a sandbox, and the outputs are returned and cached.

**`.bazelrc` — remote execution configuration:**
```
# Remote cache (read/write for CI, read-only for developers)
build:remote-cache --remote_cache=grpcs://cache.example.com
build:remote-cache --remote_upload_local_results=false

# Remote execution (CI only)
build:remote-exec --remote_executor=grpcs://executor.example.com
build:remote-exec --remote_cache=grpcs://cache.example.com
build:remote-exec --remote_upload_local_results=true
build:remote-exec --jobs=200
build:remote-exec --remote_timeout=3600
build:remote-exec --spawn_strategy=remote

# Platform configuration for remote workers
build:remote-exec --extra_execution_platforms=//platforms:linux_x86_64
build:remote-exec --host_platform=//platforms:linux_x86_64
```

**Using remote execution:**
```bash
# Developer: read from cache, build locally
bazel build //... --config=remote-cache

# CI: distribute to cluster, populate cache
bazel build //... --config=remote-exec
bazel test //... --config=remote-exec
```

Remote caching alone (without execution) provides substantial benefit: CI populates the cache, and every developer gets cache hits for unchanged targets. A typical cache hit rate of 80-90% on developer machines means that a 30-minute full build takes 3-5 minutes when only a few targets changed. Remote execution extends this further by parallelizing the remaining 10-20% of cache misses across a cluster.

**Supported remote execution backends:**
- **BuildBarn** — open-source, self-hosted.
- **Buildbarn** — open-source, self-hosted.
- **EngFlow** — managed service.
- **BuildBuddy** — managed service with free tier.
- **Google RBE (Remote Build Execution)** — for Google Cloud.

### Polyglot Monorepo

Bazel's greatest strength is managing monorepos with multiple languages under a single build graph. A monorepo might contain Java microservices, Go CLI tools, Python ML pipelines, C++ native libraries, and TypeScript frontend applications — all built, tested, and deployed from one repository with one build system.

**Monorepo directory structure:**
```
monorepo/
  MODULE.bazel
  .bazelrc
  .bazelversion
  platforms/
    BUILD.bazel           (platform definitions)
  proto/
    user/
      BUILD.bazel         (proto_library + language-specific libraries)
      user.proto
  services/
    user-service/
      BUILD.bazel         (java_binary)
      src/...
    notification-service/
      BUILD.bazel         (go_binary)
      main.go
  libs/
    common-model/
      BUILD.bazel         (java_library)
    auth-sdk/
      BUILD.bazel         (go_library)
  tools/
    cli/
      BUILD.bazel         (go_binary)
  frontend/
    web-app/
      BUILD.bazel         (ts_project)
  ml/
    recommender/
      BUILD.bazel         (py_binary)
```

**Cross-language dependency graph:**
```python
# services/user-service/BUILD.bazel
java_binary(
    name = "user-service",
    main_class = "com.example.UserServiceApplication",
    deps = [
        "//libs/common-model",
        "//proto/user:user_java_proto",
        "@maven//:org_springframework_boot_spring_boot_starter_web",
    ],
)

# services/notification-service/BUILD.bazel
go_binary(
    name = "notification-service",
    srcs = ["main.go"],
    deps = [
        "//libs/auth-sdk",
        "//proto/user:user_go_proto",
    ],
)
```

Both services depend on the same `user.proto` definition through language-specific generated libraries. Changing `user.proto` triggers recompilation of both services' proto bindings — but only the affected downstream targets, not the entire repository. Bazel's fine-grained dependency tracking ensures that a change in the Go CLI tool does not trigger a rebuild of the Java services or the Python ML pipeline.

**Visibility for monorepo governance:**
```python
# libs/common-model/BUILD.bazel
java_library(
    name = "common-model",
    srcs = glob(["src/**/*.java"]),
    visibility = [
        "//services:__subpackages__",
        "//ml:__subpackages__",
    ],
)
```

Visibility rules enforce architectural boundaries: `common-model` is visible to services and ML pipelines, but not to the CLI tools or frontend. This prevents unauthorized coupling and makes architectural decisions enforceable at build time rather than through code reviews.

## Configuration

### Development

Bazel's configuration is layered through `.bazelrc` files: project-level (`.bazelrc`, committed), user-level (`~/.bazelrc`, not committed), and workspace-level (`.bazelrc.user`, gitignored). The resolution order is: command line > `--config` flags > user `.bazelrc` > project `.bazelrc`.

**`.bazelrc` — project configuration (committed):**
```
# Common settings for all builds
common --enable_bzlmod

# Build settings
build --java_language_version=21
build --java_runtime_version=remotejdk_21
build --tool_java_language_version=21

# Test settings
test --test_output=errors
test --test_summary=detailed

# Strict dependency checking
build --strict_java_deps=ERROR
build --experimental_strict_action_env

# Convenience aliases
build:debug --compilation_mode=dbg
build:release --compilation_mode=opt
build:ci --config=release --remote_upload_local_results=true

# Platform-specific settings
build:linux --platforms=//platforms:linux_x86_64
build:macos --platforms=//platforms:macos_arm64
```

**`.bazelrc.user` — gitignored, per-developer overrides:**
```
# Local cache directory
build --disk_cache=~/.cache/bazel

# Use local JDK instead of remote
build --java_runtime_version=local_jdk

# Remote cache for cache hits
build --config=remote-cache
```

**Bazelisk (the Bazel Wrapper):**
```bash
# Install Bazelisk
brew install bazelisk    # MacOS
npm install -g @bazel/bazelisk  # any platform

# Use Bazelisk as drop-in replacement
bazel build //...       # Bazelisk reads .bazelversion, downloads and runs the pinned Bazel
```

Always use Bazelisk in CI and developer documentation. Never require a manually installed Bazel version.

### Production

**CI pipeline invocation:**
```bash
# Full build and test
bazel build //... --config=ci
bazel test //... --config=ci --test_tag_filters=-manual

# Build specific targets
bazel build //services/user-service --config=ci

# Query the dependency graph
bazel query "deps(//services/user-service)" --output=graph
```

**GitHub Actions example:**
```yaml
- name: Setup Bazelisk
  uses: bazelbuild/setup-bazelisk@v3

- name: Mount Bazel cache
  uses: actions/cache@v4
  with:
    path: ~/.cache/bazel
    key: bazel-${{ hashFiles('MODULE.bazel.lock') }}

- name: Build
  run: bazel build //... --config=ci

- name: Test
  run: |
    bazel test //... --config=ci \
      --test_output=errors \
      --build_event_json_file=bep.json

- name: Upload test results
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: test-results
    path: bazel-testlogs/
```

**Build Event Protocol (BEP)** — Bazel emits structured build events (target completion, test results, timing data) that CI systems and build dashboards consume:
```bash
bazel build //... --build_event_json_file=bep.json
bazel test //... --build_event_json_file=test_bep.json
```

BEP files are the Bazel equivalent of Gradle build scans — they contain the complete build model for analysis and debugging.

## Performance

**Content-addressed caching** is Bazel's primary performance mechanism. Every build action is keyed by the SHA-256 hash of its inputs (source files, compiler version, flags, dependent outputs). Cache hits skip the action entirely — whether the cache is local (disk), remote (shared server), or both. This is fundamentally more powerful than Gradle's build cache because Bazel's hermeticity guarantees that cache hits produce identical outputs.

**Disk cache for local development:**
```
build --disk_cache=~/.cache/bazel
```

The disk cache persists across branch switches and clean builds. Switching from a feature branch back to main and running `bazel build //...` hits the cache for all targets that are identical across branches — typically 90%+ of the build graph.

**Remote cache for team-wide sharing:**
```
build --remote_cache=grpcs://cache.example.com
```

CI populates the remote cache. Developers read from it. A typical developer build after `git pull` hits the remote cache for all unchanged targets, rebuilding only locally modified targets and their direct dependents.

**Parallel execution:**
```bash
# Local parallelism (default: auto-detected CPU cores)
bazel build //... --jobs=auto

# Remote parallelism (hundreds of concurrent actions)
bazel build //... --config=remote-exec --jobs=200
```

Bazel's fine-grained dependency graph enables massive parallelism — hundreds of independent compilation actions execute concurrently on a remote cluster. Local builds parallelize across CPU cores. The `--jobs` flag controls the concurrency limit.

**Query for build analysis:**
```bash
# What depends on this target? (reverse dependencies)
bazel query "rdeps(//..., //libs/common-model)"

# What does this target depend on?
bazel query "deps(//services/user-service)" --output=graph | dot -Tpng > deps.png

# Which targets are affected by changes in these files?
bazel query "rdeps(//..., set($(git diff --name-only HEAD~1)))"
```

The query language enables precise impact analysis: before building, determine which targets are affected by recent changes. CI pipelines use this to build only affected targets rather than the entire repository, dramatically reducing CI time for large monorepos.

**Build profiling:**
```bash
# JSON trace for Chrome tracing viewer
bazel build //... --profile=build_profile.json
# Open chrome://tracing and load the file

# Execution log for cache debugging
bazel build //... --execution_log_json_file=exec_log.json
```

The execution log shows every action, its inputs, outputs, cache hit/miss status, and execution time. It is the definitive tool for debugging cache misses and identifying slow actions.

## Security

**Hermetic builds are inherently more secure** than non-hermetic builds because they restrict what build actions can access. An action that tries to read `/etc/passwd`, access the network, or write outside its output directory fails in Bazel's sandbox. This prevents:
- Build scripts that exfiltrate secrets from the build machine.
- Dependencies that phone home during compilation.
- Actions that produce different outputs based on machine state.

**Dependency lockfile integrity:**
```bash
# Verify the lockfile matches the resolved dependency graph
bazel mod deps --lockfile_mode=error

# Update the lockfile after dependency changes
bazel mod deps --lockfile_mode=update
```

Commit `MODULE.bazel.lock` and treat lockfile diffs as dependency change signals that require security review.

**Visibility for access control:**
```python
# Restrict who can depend on sensitive libraries
java_library(
    name = "crypto-utils",
    srcs = glob(["src/**/*.java"]),
    visibility = [
        "//services/auth-service:__pkg__",
        "//services/payment-service:__pkg__",
    ],
)
```

Only the auth and payment services can depend on crypto utilities. Other services that attempt to add a dependency will get a build error. This is architectural security enforced at build time.

**No secrets in BUILD files or .bazelrc:**
```
# .bazelrc — reference secrets from environment
build --action_env=SIGNING_KEY
build --action_env=REGISTRY_TOKEN
```

Secrets are passed as environment variables and explicitly declared with `--action_env`. Undeclared environment variables are not visible to build actions (due to hermeticity), preventing accidental secret leakage.

**Supply chain hardening checklist:**
- Use Bzlmod with a lockfile (`MODULE.bazel.lock`) for all external dependencies.
- Pin Bazel version via `.bazelversion` and use Bazelisk.
- Enable strict sandboxing (`--spawn_strategy=sandboxed`).
- Use visibility rules to enforce architectural boundaries and restrict access to sensitive modules.
- Review lockfile diffs during code review — they are the bill of materials for external dependencies.
- Use `--remote_cache` with TLS (`grpcs://`) and authentication to prevent cache poisoning.
- Enable `--experimental_remote_cache_compression` to reduce cache storage and transfer overhead.

## Testing

**Bazel's test model** treats tests as first-class build actions. Tests are cached (a passing test with unchanged inputs is not re-run), parallelized, and subject to the same hermeticity as build actions. Test results are stored in `bazel-testlogs/` with structured output.

**Running tests:**
```bash
# Run all tests
bazel test //...

# Run tests in a specific package
bazel test //services/user-service/...

# Run a specific test target
bazel test //libs/common-model:common_model_test

# Run only tests affected by recent changes
bazel test $(bazel query "rdeps(//..., set($(git diff --name-only HEAD~1))) intersect kind(test, //...)")

# Run with verbose output
bazel test //... --test_output=all

# Run tests tagged as integration
bazel test //... --test_tag_filters=integration

# Exclude manual tests
bazel test //... --test_tag_filters=-manual
```

**Test tagging and filtering:**
```python
java_test(
    name = "user_service_integration_test",
    srcs = ["UserServiceIntegrationTest.java"],
    deps = [":user-service", "@maven//:org_testcontainers_testcontainers"],
    tags = ["integration", "requires-docker"],
    size = "large",
    timeout = "long",
)
```

Tags enable fine-grained test selection: run only unit tests locally (`--test_tag_filters=-integration`), run everything in CI, or run only tests that require Docker on machines with Docker installed.

**Test sharding for parallelism:**
```python
java_test(
    name = "large_test_suite",
    srcs = glob(["src/test/**/*Test.java"]),
    shard_count = 4,
    deps = [":core"],
)
```

Bazel splits the test suite into 4 shards and runs them in parallel, either locally or across remote workers. Sharding is transparent to the test framework — Bazel uses environment variables to tell each shard which subset of tests to run.

**Test caching:**
Test results are cached by default. A test that passed with the same inputs is not re-run — `bazel test` reports `(cached)` for unchanged tests. This is safe because Bazel's hermeticity guarantees that the same inputs always produce the same test result. To force re-execution (e.g., for flaky test investigation), use `--nocache_test_results`.

**Flaky test handling:**
```python
java_test(
    name = "flaky_network_test",
    flaky = True,      # Retried up to 3 times
    srcs = ["NetworkTest.java"],
    tags = ["requires-network"],
    deps = [":core"],
)
```

Bazel retries flaky-tagged tests and reports them separately from deterministic failures. Track flaky tests and fix them — the `flaky` attribute is a temporary workaround, not a permanent solution.

## Dos

- Use Bzlmod (`MODULE.bazel`) for all external dependency management. The legacy `WORKSPACE` file is deprecated and lacks version mediation, lockfile support, and registry integration. Bzlmod provides deterministic, reproducible dependency resolution with a lockfile.
- Use Bazelisk instead of installing Bazel directly. Pin the version in `.bazelversion` and commit it. Bazelisk downloads and uses the exact pinned version, ensuring consistent behavior across developers and CI.
- Use visibility rules to enforce module boundaries. Default to package-private visibility and explicitly grant access to specific consumers. Visibility prevents unauthorized coupling and makes architectural decisions enforceable at build time.
- Use remote caching for all projects with more than 10 targets. The investment in setting up a remote cache server pays back immediately in faster developer builds and CI pipelines. Start with read-only cache for developers and write access for CI.
- Use `bazel query` and `bazel cquery` for impact analysis before building. Determine which targets are affected by recent changes and build/test only those targets. This is essential for monorepo CI where building everything on every PR is infeasible.
- Use test tags and size attributes to categorize tests. Run fast unit tests locally, integration tests in CI, and manual tests only on demand. Tags enable flexible test selection without restructuring the test suite.
- Commit the lockfile (`MODULE.bazel.lock`) and review lockfile diffs during code review. The lockfile is the bill of materials for external dependencies — unexpected changes may indicate supply chain issues.
- Use `--profile` and execution logs to debug build performance. Bazel's profiling tools show per-action timing, cache hit rates, and parallelism utilization. Optimize the critical path — the longest chain of dependent actions.
- Use hermetic toolchains (e.g., `remotejdk_21` for Java, `rules_go` managed Go SDK) instead of relying on locally installed tools. Hermetic toolchains ensure that the build uses the same compiler and SDK version regardless of the machine.
- Define platform configurations in `//platforms/BUILD.bazel` for all target platforms. Platforms enable cross-compilation, remote execution platform matching, and platform-specific configuration in a single build graph.

## Don'ts

- Don't use the legacy `WORKSPACE` file for new projects. WORKSPACE is deprecated in favor of Bzlmod. It loads dependencies imperatively (order-dependent), has no version mediation, no lockfile, and no registry. Migrating from WORKSPACE to Bzlmod is a one-time cost that eliminates an entire class of dependency management bugs.
- Don't use `glob()` for `BUILD.bazel` file discovery across directories. Globs in BUILD files are scoped to the current package — they do not cross package boundaries. Use `bazel query` or explicit target references for cross-package dependencies. Using `glob()` to reach outside the package is a hermeticity violation.
- Don't use `--spawn_strategy=local` in production builds. Local strategy disables sandboxing, allowing actions to read undeclared inputs and produce non-reproducible outputs. Use `sandboxed` (default) for local builds and `remote` for distributed builds.
- Don't check `bazel-bin/`, `bazel-out/`, or `bazel-testlogs/` into version control. These are symlinks to Bazel's output directories and are machine-specific. Gitignore them.
- Don't use `load()` statements that reach outside the current repository without going through Bzlmod. Direct repository references (`@some_repo//`) bypass version management and lockfile tracking. Declare all external dependencies in `MODULE.bazel`.
- Don't write non-hermetic rules that access the network, read environment variables, or depend on system state. Non-hermetic rules break caching, remote execution, and reproducibility — the three properties that make Bazel valuable. If a rule needs network access (e.g., downloading a tool), use repository rules with `sha256` verification.
- Don't use `//visibility:public` on internal library targets. Public visibility allows any target in the repository to depend on the library, defeating architectural boundary enforcement. Grant visibility only to specific packages that legitimately need the dependency.
- Don't ignore test cache hits. If Bazel reports `(cached)` for a test but you expect it to re-run, the inputs have not changed from Bazel's perspective. Investigate whether the test is actually hermetic — non-hermetic tests (reading from the filesystem, accessing the network, depending on time) produce false cache hits.
- Don't set `--jobs` higher than available resources for local builds. Over-subscribing CPU cores causes thrashing. Use `--jobs=auto` (default) for local builds and set explicit high values only for remote execution with sufficient worker capacity.
- Don't ignore `MODULE.bazel.lock` diffs in code review. Lockfile changes indicate dependency graph mutations — new transitive dependencies, version changes, or new registries. Every lockfile diff should be reviewed for unexpected additions and potential supply chain concerns.
