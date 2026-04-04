---
name: dart-analyzer
categories: [linter]
languages: [dart]
exclusive_group: dart-linter
recommendation_score: 90
detection_files: [analysis_options.yaml]
---

# dart-analyzer

## Overview

Dart's built-in static analysis tool, invoked via `dart analyze` or automatically during IDE usage. Configuration lives in `analysis_options.yaml` at the package root. The Dart analyzer supports three curated lint packages: `lints` (core Dart lints), `flutter_lints` (Flutter-specific superset), and the stricter `very_good_analysis`. It catches type errors, potential null safety violations, dead code, and style issues. The analyzer is zero-config for basic use — create `analysis_options.yaml` to customize beyond defaults.

## Architecture Patterns

### Installation & Setup

The Dart analyzer ships with the Dart SDK — no separate installation needed:

```bash
dart analyze                    # analyze the current package
dart analyze lib/               # analyze specific directory
dart analyze --fatal-infos      # treat info-level issues as errors
dart analyze --fatal-warnings   # treat warnings as errors (recommended for CI)
```

For Flutter projects:
```bash
flutter analyze                 # wraps dart analyze with Flutter context
flutter analyze --watch         # continuous analysis mode
```

Add the lint package to `pubspec.yaml`:
```yaml
# pubspec.yaml
dev_dependencies:
  lints: ^5.0.0               # core Dart lints
  # OR for Flutter:
  flutter_lints: ^5.0.0       # extends lints with Flutter rules
  # OR for strict projects:
  very_good_analysis: ^7.0.0  # very strict superset
```

### Rule Categories

| Lint Package | Rules Count | Strictness | Pipeline Severity |
|---|---|---|---|
| `lints/core` | ~30 rules | Minimum recommended set | CRITICAL |
| `lints/recommended` | ~60 rules | Extends core with style | WARNING |
| `flutter_lints/flutter` | ~70 rules | Flutter idioms on top of recommended | WARNING |
| `very_good_analysis` | ~180 rules | Highly opinionated, production-grade | INFO (additional) |

Key rule categories within the lint system:

| Category | What It Checks | Pipeline Severity |
|---|---|---|
| `errors` | Type mismatches, null safety violations, undefined names | CRITICAL |
| `style` | `prefer_const_constructors`, `use_key_in_widget_constructors` | WARNING |
| `pub` | `sort_pub_dependencies`, `valid_pubspec` | INFO |
| `performance` | `avoid_unnecessary_containers`, `sized_box_for_whitespace` | WARNING |

### Configuration Patterns

`analysis_options.yaml` at the package root:

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml
# OR for non-Flutter:
# include: package:lints/recommended.yaml
# OR for strict:
# include: package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true          # disallow implicit dynamic casts
    strict-inference: true      # require explicit types when inferred is dynamic
    strict-raw-types: true      # disallow raw generic types (List vs List<T>)

  exclude:
    - "**/*.g.dart"             # generated code (json_serializable, freezed)
    - "**/*.freezed.dart"
    - "**/*.gr.dart"            # auto_route generated
    - "lib/generated/**"
    - "test/helpers/golden/**"  # golden test images are not Dart

  errors:
    # Treat specific lint categories as errors
    invalid_annotation_target: ignore   # suppress for older annotation packages
    missing_required_param: error
    missing_return: error

linter:
  rules:
    # Additional rules on top of included package
    - always_use_package_imports    # prefer package: over relative imports
    - avoid_dynamic_calls           # no .call() on dynamic
    - prefer_final_locals           # immutable locals
    - require_trailing_commas       # consistent multiline formatting

    # Disable specific rules from included package
    - avoid_print: false            # allow in CLI tools; disable for UI code

    # Rules that must be explicitly disabled for specific files:
    # Use // ignore: rule_name on a specific line
```

Inline suppression:
```dart
// ignore: avoid_print
print('Debug output during development');

// ignore_for_file: always_use_package_imports
// Use at top of file to suppress for entire file
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Dart analyze
  run: dart analyze --fatal-warnings --fatal-infos

# Flutter projects
- name: Flutter analyze
  run: flutter analyze
  working-directory: ./mobile
```

For monorepos with multiple packages:
```yaml
- name: Analyze all packages
  run: |
    for dir in packages/*/; do
      echo "Analyzing $dir"
      dart analyze "$dir" --fatal-warnings
    done
```

## Performance

- The Dart analyzer maintains an incremental analysis server — IDE analysis is near-instant after the initial full analysis.
- `dart analyze` performs a full analysis pass each invocation. For large multi-package repos, run per-package rather than from the root.
- Generated file exclusion (`**/*.g.dart`, `**/*.freezed.dart`) is critical — generated files often contain patterns that trigger dozens of false positives.
- `strict-inference` and `strict-casts` increase analysis time slightly but catch real type safety issues that default inference misses.
- The analysis server (`dart language-server`) caches results between IDE sessions. Clear the cache with `dart pub cache clean` if analysis appears stale.

## Security

Dart's type system and null safety are the primary security mechanisms:

- `strict-casts: true` — prevents implicit `dynamic` downcasting that can bypass type-level safety guarantees.
- Null safety (enabled by default in Dart 3.x) — eliminates null pointer dereferences from entire categories of runtime errors.
- `avoid_dynamic_calls` — dynamic method calls bypass the type system entirely; disable only with justification.

For Flutter apps, security concerns are primarily handled at the network layer (certificate pinning, secure storage) rather than static analysis. Pair `dart analyze` with `dart pub audit` to scan for known vulnerabilities in dependencies.

## Testing

```bash
# Full analysis with warnings-as-errors
dart analyze --fatal-warnings

# Analyze with info-level issues treated as errors
dart analyze --fatal-infos

# Analyze a specific package
dart analyze packages/core_domain/

# Format check (use dart format alongside analyzer)
dart format --output=none --set-exit-if-changed .

# Fix auto-correctable issues
dart fix --apply

# Preview fixes without applying
dart fix --dry-run

# Show all enabled lint rules
dart analyze --help
```

## Dos

- Enable `strict-casts`, `strict-inference`, and `strict-raw-types` for production code — they catch type safety issues that default Dart analysis misses.
- Exclude all generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`) from analysis — generated code legitimately violates lint rules and analysis of it wastes time.
- Use `dart fix --apply` to auto-resolve bulk migrations (e.g., adopting new lint rules, migrating deprecated APIs) — it applies all safe fixes in one pass.
- Treat `--fatal-warnings` as the CI standard — info issues can be reviewed in PRs, but warnings indicate real code quality problems.
- Include `flutter_lints` or `lints/recommended` rather than writing rules from scratch — community-maintained packages evolve with the language and framework.
- Run `dart pub audit` alongside `dart analyze` in CI — the analyzer checks code quality; pub audit checks dependency security.

## Don'ts

- Don't omit `analysis_options.yaml` from packages — without it, only basic error-level issues are reported and lint rules do not run.
- Don't use `// ignore_for_file` on source files that are not generated — per-file suppression is intended for generated code only.
- Don't disable `avoid_dynamic_calls` without a documented reason — dynamic calls bypass Dart's type safety and can cause runtime errors that the analyzer cannot predict.
- Don't suppress null safety violations with `!` operators to silence the analyzer — investigate whether the value can actually be null and handle it explicitly.
- Don't exclude `test/` from analysis — test code lint violations (unused imports, dynamic calls in test helpers) hide real code quality issues.
- Don't configure `analysis_options.yaml` in `lib/` subdirectories to override the root config — nested analysis options are not inherited predictably by the analyzer.
