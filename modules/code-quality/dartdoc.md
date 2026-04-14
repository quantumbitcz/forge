---
name: dartdoc
categories: [doc-generator]
languages: [dart]
exclusive_group: dart-doc-generator
recommendation_score: 90
detection_files: [dartdoc_options.yaml, pubspec.yaml]
---

# dartdoc

## Overview

`dart doc` is the built-in Dart documentation generator. It ships with the Dart SDK (no extra installation needed) and generates HTML API docs from `///` triple-slash comment blocks. Configure output behavior through `dartdoc_options.yaml`. Use `--validate-links` to catch broken cross-references. Generated docs are hosted automatically on `pub.dev` for published packages.

## Architecture Patterns

### Installation & Setup

```bash
# Built-in with the Dart SDK — no installation required

# Generate docs for the current package
dart doc

# Generate to a custom output directory
dart doc --output docs/api

# Validate all hyperlinks in generated output
dart doc --validate-links

# Fail on broken links (useful in CI)
dart doc --validate-links 2>&1 | grep -E "^warning:" && exit 1 || exit 0
```

**`dartdoc_options.yaml` (project root):**
```yaml
dartdoc:
  # Shown in browser tab and doc header
  name: "My Package"
  # Exclude internal implementation directories
  exclude:
    - 'src/internal'
    - 'src/generated'
  # Source link template for GitHub
  linkToSource:
    root: '.'
    uriTemplate: 'https://github.com/org/my_package/blob/main/%f%#L%l%'
  # Show inherited members grouped by parent
  showUndocumentedCategories: false
  # Warn on missing docs
  errors:
    - missing-from-search-index
  warnings:
    - tool-error
    - unreachable-comment
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing library doc | Library without `/// ` comment before `library` directive | WARNING |
| Missing class doc | Public class without `///` block | WARNING |
| Missing member doc | Public method/property without `///` | INFO |
| Broken link | `[SymbolName]` reference to undefined symbol | WARNING |
| Invalid `@nodoc` | `@nodoc` on a public API type | INFO |

### Configuration Patterns

**Library-level documentation:**
```dart
/// A high-performance HTTP client with automatic retry support.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:my_package/my_package.dart';
///
/// final client = HttpClient();
/// final response = await client.get(Uri.parse('https://api.example.com/users'));
/// print(response.statusCode);
/// ```
///
/// See also:
/// - [RetryPolicy] for configuring retry behaviour
/// - [HttpClientOptions] for timeout and connection settings
library my_package;
```

**Class and method documentation:**
```dart
/// An HTTP client with configurable retry and timeout behaviour.
///
/// Create an instance with [HttpClient.new] or [HttpClient.withOptions].
/// All methods return a [Future] that resolves to an [HttpResponse].
///
/// Example:
/// ```dart
/// final client = HttpClient(timeout: Duration(seconds: 30));
/// final response = await client.get(Uri.parse('https://example.com'));
/// ```
class HttpClient {
  /// Creates an [HttpClient] with the default options.
  ///
  /// To customise behaviour, use [HttpClient.withOptions] instead.
  HttpClient();

  /// Creates an [HttpClient] with the provided [options].
  ///
  /// - [options] must not be null.
  factory HttpClient.withOptions(HttpClientOptions options);

  /// Sends a GET request to the given [uri].
  ///
  /// Retries up to [RetryPolicy.maxAttempts] times on `5xx` responses
  /// or network errors.
  ///
  /// Throws [TimeoutException] if no response is received within the
  /// configured [HttpClientOptions.timeout].
  ///
  /// Parameters:
  /// - [uri]: The target URI. Must use `https` scheme in production.
  /// - [headers]: Additional request headers. Merged with default headers.
  ///
  /// Returns an [HttpResponse] with status, headers, and decoded body.
  Future<HttpResponse> get(Uri uri, {Map<String, String> headers = const {}});
}
```

**Hiding from docs with `@nodoc`:**
```dart
/// @nodoc
/// Internal implementation — not part of the public API.
class InternalCache {}
```

**Cross-references using `[SymbolName]` syntax:**
```dart
/// Applies the [RetryPolicy] configured in [HttpClientOptions.retryPolicy].
/// Throws [NetworkException] if all retries are exhausted.
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Set up Dart
  uses: dart-lang/setup-dart@v1

- name: Install dependencies
  run: dart pub get

- name: Generate docs
  run: dart doc --output docs/api

- name: Validate links
  run: dart doc --validate-links 2>&1 | tee doc-warnings.txt
  continue-on-error: false

- name: Fail on link warnings
  run: grep -q "^warning:" doc-warnings.txt && exit 1 || exit 0

- name: Deploy to GitHub Pages
  if: github.ref == 'refs/heads/main'
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs/api
```

## Performance

- `dart doc` is fast (5-20s for typical packages) — it processes Dart source files without compilation.
- Exclude `src/` subdirectories containing generated code or private implementations via `dartdoc_options.yaml` `exclude:` to reduce output size and parse time.
- `--validate-links` adds extra time (crawls all generated hyperlinks). Run it separately from the main doc generation step in CI.
- For monorepos, run `dart doc` per-package in parallel rather than at the workspace root.

## Security

- dartdoc generates static HTML — no runtime security surface.
- `@nodoc` hides a symbol from the generated docs but does not make it inaccessible. Do not use it as a security boundary.
- Avoid embedding API keys, internal service URLs, or debug credentials in `///` examples — they appear on `pub.dev` for published packages.

## Testing

```bash
# Generate docs
dart doc

# Generate to custom path
dart doc --output docs/api

# Validate all cross-references and links
dart doc --validate-links

# Open generated docs locally (MacOS)
open doc/api/index.html

# Check for doc warnings (non-zero exit if warnings found)
dart doc --validate-links 2>&1 | grep "^warning:" | wc -l
```

## Dos

- Write `///` comments on every public class, typedef, function, and extension — `pub.dev` scores packages on doc coverage.
- Add a library-level `///` comment before the `library` directive summarising the package's purpose and linking to the key entry points.
- Use `[SymbolName]` cross-references in prose — they are validated at doc generation time and rendered as hyperlinks.
- Configure `linkToSource` in `dartdoc_options.yaml` to give readers direct source navigation from the docs.
- Exclude generated code and internal directories via `dartdoc_options.yaml` `exclude:` — generated classes bloat the API surface.
- Run with `--validate-links` in CI to catch broken links before publishing to `pub.dev`.

## Don'ts

- Don't use `@nodoc` on types that are referenced in public API signatures — dartdoc will warn and the cross-reference will break.
- Don't mix `//` (code comment) and `///` (doc comment) — only `///` blocks appear in the generated output.
- Don't skip the library-level comment — it is the first thing visitors see on `pub.dev`.
- Don't commit the generated `doc/` directory — regenerate in CI and publish from there.
- Don't document parameters with standalone lines if Dart's type system already makes the contract clear — add `///` only when behavior requires elaboration.
- Don't use `@deprecated` annotation alone without a `///` doc explaining the migration path.
