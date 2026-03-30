# swift-format

## Overview

Apple's official Swift formatter and linter, distributed as a Swift Package Manager tool. Provides two modes: `swift-format format` (rewrites files in place) and `swift-format lint` (reports style violations without modifying files). Configuration via `.swift-format` JSON file at the project root. Xcode integration available via a build phase or `Run Script` phase. Use `swift-format lint --strict` in CI to fail on any violation. The tool enforces the Swift API Design Guidelines and community conventions from swift.org.

## Architecture Patterns

### Installation & Setup

```bash
# Via Swift Package Manager (recommended — pins to a specific version)
# Add to Package.swift or use as a command plugin

# Via Homebrew
brew install swift-format

# Via Mint (version-locked Swift tool manager)
mint install apple/swift-format

# Verify
swift-format --version   # e.g., 600.0.0
```

**`.swift-format` (JSON config at project root):**
```json
{
  "version": 1,
  "lineLength": 100,
  "indentation": {
    "spaces": 4
  },
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": false,
  "lineBreakBeforeEachGenericRequirement": false,
  "prioritizeKeepingFunctionOutputTogether": false,
  "indentConditionalCompilationBlocks": false,
  "tabWidth": 4,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": false,
    "AlwaysUseLowerCamelCase": true,
    "AmbiguousTrailingClosureOverload": true,
    "BeginDocumentationCommentWithOneLineSummary": false,
    "DoNotUseSemicolons": true,
    "FileScopedDeclarationPrivacy": true,
    "FullyIndirectEnum": true,
    "GroupNumericLiterals": true,
    "IdentifiersMustBeASCII": true,
    "NeverForceUnwrap": false,
    "NeverUseForceTry": false,
    "NoAccessLevelOnExtensionDeclaration": true,
    "OrderedImports": true,
    "UseEarlyExits": false,
    "UseExplicitNilCheckInConditions": false,
    "UseLetInEveryBoundCaseVariable": true,
    "UseShorthandTypeNames": true,
    "UseSingleLinePropertyGetter": true,
    "UseTripleSlashForDocumentationComments": true
  }
}
```

### Rule Categories

| Category | Key Rules | Pipeline Severity |
|---|---|---|
| Naming | `AlwaysUseLowerCamelCase`, `IdentifiersMustBeASCII` | WARNING |
| Documentation | `BeginDocumentationCommentWithOneLineSummary`, `UseTripleSlashForDocumentationComments` | INFO |
| Style | `DoNotUseSemicolons`, `OrderedImports`, `UseShorthandTypeNames` | WARNING |
| Safety | `NeverForceUnwrap`, `NeverUseForceTry` | CRITICAL (enable in strict mode) |
| Structure | `FileScopedDeclarationPrivacy`, `FullyIndirectEnum` | WARNING |

**Enable safety rules for production code:**
```json
{
  "rules": {
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true
  }
}
```

### Configuration Patterns

**Xcode Build Phase integration:**
```bash
# Script to add as a Run Script build phase (runs before Compile Sources)
if which swift-format >/dev/null; then
  swift-format lint --recursive --strict "${SRCROOT}"
else
  echo "warning: swift-format not installed"
fi
```

**Format on save via Xcode (requires swift-format Xcode extension or external tool):**
```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash
staged=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$')
if [ -n "$staged" ]; then
  echo "$staged" | xargs swift-format format --in-place
  echo "$staged" | xargs git add
fi
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: swift-format lint
  run: swift-format lint --recursive --strict .

- name: swift-format check
  run: |
    swift-format format --recursive . --dry-run 2>&1 | tee /tmp/fmt-diff
    if [ -s /tmp/fmt-diff ]; then
      echo "Formatting issues found:"
      cat /tmp/fmt-diff
      exit 1
    fi
```

**Makefile targets:**
```makefile
.PHONY: format format-check lint-swift

format:
	swift-format format --recursive --in-place .

format-check:
	swift-format format --recursive --dry-run . 2>&1

lint-swift:
	swift-format lint --recursive --strict .
```

## Performance

- `swift-format` processes files sequentially — large projects (500+ Swift files) can take 10-30 seconds.
- Use `--recursive Sources/` rather than `.` to avoid scanning test resources, documentation, and generated code.
- Pre-commit hooks should filter to `*.swift` staged files only — avoid full project scans on commit.
- Xcode integration: run `swift-format lint` in a separate build phase with a dependency-tracking script to avoid re-linting unchanged files.

## Security

swift-format has no security analysis capability. Key practices:

- `NeverForceUnwrap` and `NeverUseForceTry` rules help catch potential crash sites — enable them for frameworks and public-facing code.
- Pin the swift-format version via `Package.resolved` (SPM) or `Mintfile` — formatting behavior changes between versions.
- Running swift-format in Xcode build phases has access to all source files — ensure the build phase runs as the current user, not a privileged build account.

## Testing

```bash
# Format all Swift files in place
swift-format format --recursive --in-place .

# Lint without modifying (report violations only)
swift-format lint --recursive .

# Lint with strict mode (non-zero exit on any violation)
swift-format lint --recursive --strict .

# Format a single file
swift-format format --in-place Sources/MyApp/ContentView.swift

# Dry run (show what would change)
swift-format format --dry-run Sources/

# Print resolved config for current directory
swift-format dump-configuration
```

## Dos

- Enable `OrderedImports` — consistent import ordering prevents merge conflicts in files with many imports.
- Set `lineLength = 100` — 80 is too narrow for Swift's verbose generics and `@` attribute syntax.
- Enable `NeverForceUnwrap` and `NeverUseForceTry` for library code — force unwraps in library code cause crashes in calling code without actionable error messages.
- Use `--strict` in CI — linting without `--strict` exits 0 even when violations are found, making CI checks silent.
- Commit `.swift-format` to version control — ensures all contributors and CI use identical formatting rules.
- Use `swift-format dump-configuration` to generate the default config as a starting point rather than writing JSON from scratch.

## Don'ts

- Don't enable `AllPublicDeclarationsHaveDocumentation` for application code — it's appropriate for library/framework code but creates noise for app-level types.
- Don't use `--dry-run` to check formatting in CI without capturing the exit code — `--dry-run` exits 0 even when differences exist; use `--strict` with `lint` instead.
- Don't run `swift-format` on generated files (Core Data `.xcdatamodeld` Swift output, protobuf stubs) — add them to a `.swiftformatignore` equivalent or scope the tool to `Sources/` only.
- Don't pin to an old swift-format version indefinitely — it may become incompatible with new Swift language features and produce incorrect output.
- Don't use swift-format as a replacement for SwiftLint — swift-format is a formatter; SwiftLint covers a different set of idiomatic Swift rules that swift-format does not.
- Don't configure `respectsExistingLineBreaks: false` without reviewing the output — it can aggressively collapse intentional multi-line expressions.
