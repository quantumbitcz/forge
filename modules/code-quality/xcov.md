# xcov

## Overview

Xcode provides built-in coverage via `xcodebuild test -enableCodeCoverage YES`. Coverage data is stored in `.xccovreport` files inside the derived data directory. Use `xcrun xccov view` to read the reports from the command line. The `xcov` RubyGem extends this with minimum threshold enforcement, filtering, and formatted output for CI. For SPM packages, `swift test --enable-code-coverage` generates LLVM `.profdata` usable with `llvm-cov`. Xcode 14+ has improved coverage for Swift concurrency (`async`/`await`) — older versions undercount async code paths.

## Architecture Patterns

### Installation & Setup

**Xcode built-in coverage:**
```bash
# Run tests with coverage enabled
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme MyApp \
  -destination "platform=iOS Simulator,name=iPhone 15,OS=17.0" \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult

# View coverage report
xcrun xccov view --report TestResults.xcresult

# JSON output for CI parsing
xcrun xccov view --report --json TestResults.xcresult > coverage.json
```

**xcov gem:**
```bash
gem install xcov
# Or in Gemfile:
gem "xcov", "~> 1.7"
```

```ruby
# Xcovfile or Fastfile
xcov(
  workspace: "MyApp.xcworkspace",
  scheme: "MyApp",
  output_directory: "coverage/",
  minimum_coverage_percentage: 80.0,
  include_targets: ["MyApp.app", "MyAppCore.framework"],
  exclude_targets: ["Pods"],
  ignore_file_path: ".xcovignore",
  html_report: true,
  markdown_report: true
)
```

**Swift Package Manager:**
```bash
# Run tests with coverage
swift test --enable-code-coverage

# Find the profdata and binary
PROF_DATA=$(swift test --enable-code-coverage --show-bin-path 2>/dev/null)
# Or find manually:
find .build -name "*.profdata" 2>/dev/null

# Generate LCOV report
xcrun llvm-cov export \
  .build/debug/MyPackagePackageTests.xctest/Contents/MacOS/MyPackagePackageTests \
  --instr-profile=.build/debug/codecov/default.profdata \
  --format=lcov \
  > coverage.lcov

# HTML via genhtml
genhtml coverage.lcov --output-directory coverage-html/
```

### Rule Categories

| Coverage Type | Tool | Notes |
|---|---|---|
| Line coverage | `xccov`, `xcov` | Primary metric in Xcode reports |
| Function coverage | `xcrun xccov view --json` | Per-function hit counts |
| Branch coverage | `llvm-cov` (SPM) | Not directly exposed in Xcode GUI |
| Threshold enforcement | `xcov` gem | `minimum_coverage_percentage` |

### Configuration Patterns

**`.xcovignore` file (xcov):**
```
.*AppDelegate.*
.*SceneDelegate.*
.*Generated.*
.*Mocks.*
.*\.generated\.swift
```

**Fastlane integration:**
```ruby
# fastlane/Fastfile
lane :test do
  run_tests(
    workspace: "MyApp.xcworkspace",
    scheme: "MyApp",
    code_coverage: true,
    output_directory: "build/reports",
    result_bundle: true
  )

  xcov(
    workspace: "MyApp.xcworkspace",
    scheme: "MyApp",
    output_directory: "build/coverage",
    minimum_coverage_percentage: 80.0,
    exclude_targets: ["Pods", "RxSwift.framework"],
    html_report: true
  )
end
```

**Per-target minimum coverage check via shell:**
```bash
#!/usr/bin/env bash
# scripts/check-coverage.sh
THRESHOLD=80
JSON=$(xcrun xccov view --report --json TestResults.xcresult)

# Extract total coverage using python (available on macOS)
COVERAGE=$(echo "$JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['lineCoverage'] * 100)
")

echo "Coverage: ${COVERAGE}%"
if (( $(echo "$COVERAGE < $THRESHOLD" | bc -l) )); then
    echo "FAIL: below ${THRESHOLD}% threshold"
    exit 1
fi
```

### CI Integration

```yaml
# .github/workflows/ios-test.yml
- name: Run tests with coverage
  run: |
    xcodebuild test \
      -workspace MyApp.xcworkspace \
      -scheme MyApp \
      -destination "platform=iOS Simulator,name=iPhone 15,OS=17.0" \
      -enableCodeCoverage YES \
      -resultBundlePath TestResults.xcresult \
      CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
      | xcpretty

- name: Generate coverage report
  run: |
    xcrun xccov view --report --json TestResults.xcresult > coverage.json
    # Convert to LCOV for Codecov
    xcrun xccov view --report --files-for-target MyApp.app TestResults.xcresult

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage.lcov
    fail_ci_if_error: true
```

**SPM package CI:**
```yaml
- name: Test with coverage (SPM)
  run: |
    swift test --enable-code-coverage
    xcrun llvm-cov export \
      $(swift build --show-bin-path)/MyPackagePackageTests.xctest/Contents/MacOS/MyPackagePackageTests \
      --instr-profile=$(swift test --show-bin-path)/../codecov/default.profdata \
      --format=lcov > coverage.lcov

- uses: codecov/codecov-action@v4
  with:
    files: coverage.lcov
```

## Performance

- `xcodebuild test -enableCodeCoverage YES` adds 5-15% test execution overhead for instrumentation.
- Use `xcpretty` to suppress verbose xcodebuild output — raw output is noisy and harder to parse in CI logs.
- SPM `swift test --enable-code-coverage` produces LLVM `.profdata` directly without needing Xcode — faster in CI environments without Xcode.app available (Linux CI for server-side Swift).
- `xcov` gem re-processes the `.xccovreport` — it adds a few seconds on top of test time but is negligible for the HTML/Markdown output value.

## Security

- `.xcresult` bundles contain test attachments and screenshots — they may be large and should not be stored long-term in CI artifacts.
- `coverage.json` from `xcrun xccov` contains file paths — safe as a build artifact but do not publish publicly for proprietary code.
- Derived data directories contain compiled artifacts — gitignore them (`DerivedData/`) to avoid committing build outputs.

## Testing

```bash
# Basic coverage run
xcodebuild test -project MyApp.xcodeproj -scheme MyApp \
  -destination "platform=iOS Simulator,name=iPhone 15" \
  -enableCodeCoverage YES -resultBundlePath TestResults.xcresult

# View summary
xcrun xccov view --report TestResults.xcresult

# View JSON (machine-readable)
xcrun xccov view --report --json TestResults.xcresult | python3 -m json.tool | head -30

# SPM package
swift test --enable-code-coverage

# xcov gem
xcov --workspace MyApp.xcworkspace --scheme MyApp --output_directory coverage/
```

## Dos

- Use `-resultBundlePath` to generate an `.xcresult` bundle — it contains all coverage data and test attachments in a single artifact.
- Use `xcrun xccov view --report --json` for CI threshold checks — JSON is reliably parseable vs human-readable text output.
- Use the `xcov` gem with `minimum_coverage_percentage` for clear threshold enforcement in CI with descriptive failure messages.
- Use `--exclude_targets` in xcov to exclude third-party pods and generated code from coverage calculations.
- For server-side Swift (Linux), use `swift test --enable-code-coverage` and LLVM toolchain — Xcode is not available on Linux.
- Keep `.xcovignore` in source control so all developers and CI use the same exclusion rules.

## Don'ts

- Don't rely on Xcode's GUI coverage percentage for CI enforcement — it is not scriptable. Use `xcrun xccov` or `xcov` gem in CI pipelines.
- Don't include `Pods/` or `Carthage/` dependencies in coverage targets — they inflate the denominator and obscure real coverage.
- Don't skip coverage for `AppDelegate` and `SceneDelegate` — instead, add them to `.xcovignore` explicitly with a comment explaining why.
- Don't use `XCTest` code coverage without `xcpretty` or similar in CI — raw xcodebuild output is thousands of lines and obscures real failures.
- Don't store `.xcresult` bundles in git — they are binary, large, and regenerated on every run.
