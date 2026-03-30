# swiftlint

## Overview

Swift linter enforcing the Ray Wenderlich / community Swift style guide via configurable rules. Runs as `swiftlint lint` against Swift source files and supports both warning and error severity levels. SwiftLint integrates into Xcode build phases, SPM plugin runs, and CI workflows. It provides 200+ rules covering correctness, style, idiomatic patterns, and performance. For formatting (whitespace, indentation), pair with `swift-format` or use SwiftLint's `autocorrect` command for rules that support it.

## Architecture Patterns

### Installation & Setup

```bash
# Homebrew (recommended for local development)
brew install swiftlint

# Swift Package Manager plugin (recommended for project distribution)
# Package.swift — add to project or as dev tool
.package(url: "https://github.com/realm/SwiftLint.git", from: "0.57.0")

# Mint (alternative version manager)
mint install realm/SwiftLint

# Verify
swiftlint version
```

Xcode build phase integration (classic approach):
```bash
# In Xcode: Target → Build Phases → + New Run Script Phase
if which swiftlint > /dev/null; then
    swiftlint
else
    echo "warning: SwiftLint not installed — download from https://github.com/realm/SwiftLint"
fi
```

SPM plugin (Xcode 14+, zero config needed if `.swiftlint.yml` exists):
```swift
// Package.swift — dev target
.target(
    name: "MyApp",
    plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
)
```

### Rule Categories

| Category | Key Rules | Pipeline Severity |
|---|---|---|
| Lint | `unused_import`, `unused_variable`, `unreachable_code` | CRITICAL |
| Idiomatic | `force_cast`, `force_try`, `force_unwrapping` | CRITICAL |
| Style | `trailing_whitespace`, `vertical_whitespace`, `line_length` | WARNING |
| Metrics | `function_body_length`, `type_body_length`, `cyclomatic_complexity` | WARNING |
| Performance | `reduce_into`, `contains_over_filter_count`, `first_where` | WARNING |
| Naming | `type_name`, `identifier_name`, `generic_type_name` | WARNING |

### Configuration Patterns

`.swiftlint.yml` at the project root:

```yaml
# .swiftlint.yml
disabled_rules:
  - trailing_comma        # allow or disallow as a team preference
  - todo                  # allow TODO comments in development

opt_in_rules:
  - force_unwrapping      # flag ! operator
  - missing_docs          # require documentation for public APIs
  - strict_fileprivate    # prefer private over fileprivate
  - empty_xctest_method   # flag empty test methods
  - closure_spacing       # consistent closure brace spacing

included:
  - Sources
  - Tests

excluded:
  - Carthage
  - Pods
  - .build
  - DerivedData
  - Sources/Generated   # code generation output

line_length:
  warning: 120
  error: 200
  ignores_comments: true
  ignores_urls: true

function_body_length:
  warning: 50
  error: 100

type_body_length:
  warning: 300
  error: 500

cyclomatic_complexity:
  warning: 10
  error: 20

identifier_name:
  min_length:
    warning: 2
  excluded:
    - id
    - i
    - j
    - x
    - y

type_name:
  min_length: 3
  max_length:
    warning: 50
    error: 100

file_length:
  warning: 500
  error: 1000
  ignore_comment_only_lines: true

reporter: "xcode"   # or "json", "html", "github-actions-logging"
```

Inline suppression:
```swift
// swiftlint:disable:next force_cast
let viewController = storyboard.instantiateViewController(withIdentifier: "Main") as! MainViewController

// swiftlint:disable force_unwrapping
// Module where force-unwrap is acceptable (e.g., static config)
let url = URL(string: "https://api.example.com")!
// swiftlint:enable force_unwrapping
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: SwiftLint
  run: swiftlint lint --reporter github-actions-logging --strict
```

`--strict` upgrades all warnings to errors. `--reporter github-actions-logging` emits inline PR annotations.

```yaml
# GitLab CI
swiftlint:
  script:
    - swiftlint lint --reporter json | tee swiftlint-report.json
  artifacts:
    reports:
      codequality: swiftlint-report.json
```

## Performance

- SwiftLint analyzes one file per thread — large projects benefit from multi-core machines. On M-series Macs, 50k-line projects lint in ~5s.
- `--use-script-input-files` in Xcode build phase limits analysis to changed files, reducing incremental build time.
- Exclude `Pods/`, `Carthage/`, `.build/`, and generated code directories — analyzing dependencies adds minutes without benefit.
- The `--fix` / `autocorrect` command writes safe fixes in place — run before committing to reduce CI failures.
- Cache SwiftLint binary in CI (e.g., `cache: brew` in GitHub Actions macOS runners) to avoid re-downloading on each run.

## Security

SwiftLint's `force_cast` and `force_unwrapping` rules are security-adjacent: crash-prone force casts and forced unwraps in request-handling code can be exploited for denial-of-service by crafting inputs that trigger panics. Additional security-relevant rules:

- `explicit_type_interface` — prevents implicit type inference that can mask type confusion bugs.
- `no_fallthrough_only` — switch fallthrough without code can lead to logic errors in security checks.

For secrets and credentials, combine SwiftLint with dedicated secret scanning (e.g., `gitleaks`). SwiftLint does not scan for hardcoded credentials.

## Testing

```bash
# Lint all configured sources
swiftlint lint

# Lint specific files
swiftlint lint --path Sources/MyModule

# Auto-fix correctable violations
swiftlint --fix

# Output JSON for tooling
swiftlint lint --reporter json

# Show all available rules
swiftlint rules

# Show a specific rule's documentation
swiftlint rules force_unwrapping

# Validate config file syntax
swiftlint lint --config .swiftlint.yml --reporter xcode
```

## Dos

- Enable `force_unwrapping`, `force_cast`, and `force_try` as opt-in rules — these are CRITICAL correctness issues disguised as style lint.
- Use `opt_in_rules: [anyobject_protocol, discouraged_object_literal, strict_fileprivate]` to progressively tighten quality without a big-bang enforcement.
- Configure `excluded` to omit `Pods/`, `Carthage/`, `.build/`, and generated code — false positives from dependencies create noise and slow analysis.
- Use `--reporter github-actions-logging` in CI for inline PR annotations that show exactly which line violated a rule.
- Set both `warning` and `error` thresholds on metrics rules — warnings in local dev, errors in CI (`--strict`).
- Add `.swiftlint.yml` to version control so all developers and CI use identical rules.

## Don'ts

- Don't use `// swiftlint:disable all` — it disables every rule for the file and hides future issues. Suppress specific rules with a comment explaining why.
- Don't disable `force_cast` and `force_unwrapping` globally — they indicate real crash risks. Fix the underlying optionality or use `guard let`/`if let`.
- Don't skip `excluded` configuration — analyzing `Pods/` generates hundreds of false violations that desensitize the team to real issues.
- Don't run SwiftLint without `--strict` in CI — warnings accumulate silently and are never resolved if they don't block the build.
- Don't configure SwiftLint per-developer in `~/.swiftlint.yml` for project rules — all rules must be in the repo's `.swiftlint.yml` for reproducible CI.
- Don't use `reporter: xcode` in CI — it formats output for Xcode's issue navigator, not for CI log parsing. Use `github-actions-logging` or `json`.
