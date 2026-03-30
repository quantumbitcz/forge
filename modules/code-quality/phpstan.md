# phpstan

## Overview

PHP static analysis tool that finds bugs without running the code. PHPStan operates on a 0-9 level system where higher levels enforce stricter type checking — level 5 is the pragmatic starting point for established codebases, level 8+ for new greenfield projects. Configuration lives in `phpstan.neon`. PHPStan understands PHPDoc annotations and native PHP 8 types equally, and integrates with Symfony, Laravel, Doctrine, and other frameworks via extension packages.

## Architecture Patterns

### Installation & Setup

```bash
# Install via Composer (recommended)
composer require --dev phpstan/phpstan

# Framework extensions (install as needed)
composer require --dev phpstan/phpstan-symfony
composer require --dev phpstan/phpstan-doctrine
composer require --dev nunomaduro/larastan   # Laravel

# Verify
vendor/bin/phpstan --version
```

### Rule Categories (Analysis Levels)

| Level | What It Checks | Pipeline Severity |
|---|---|---|
| 0 | Basic checks: unknown classes, functions, methods, constant usage | CRITICAL |
| 1 | Possibly undefined variables, unknown magic methods | CRITICAL |
| 2 | Unknown methods on all expressions, return types on `__construct` | CRITICAL |
| 3 | Return types, property types | CRITICAL |
| 4 | Basic dead code: always-false conditions, unreachable branches | WARNING |
| 5 | Argument types passed to methods and functions | WARNING |
| 6 | Return type enforcement on all methods | WARNING |
| 7 | Union type propagation | WARNING |
| 8 | `null` safety: strict nullable type checking | CRITICAL |
| 9 | `mixed` type enforcement: no implicit mixed propagation | WARNING |

### Configuration Patterns

`phpstan.neon` at the project root:

```neon
# phpstan.neon
parameters:
    level: 8
    paths:
        - src
        - tests
    excludePaths:
        - src/Migrations           # doctrine auto-generated
        - tests/Fixtures           # test data fixtures

    # Treat PHPDoc type errors as errors (not just warnings)
    treatPhpDocTypesAsCertain: false

    # Report unmatched ignored errors (catches stale suppressions)
    reportUnmatchedIgnoredErrors: true

    # Parallel analysis (auto-detected, explicit override)
    parallel:
        maximumNumberOfProcesses: 4

    ignoreErrors:
        # Ignore specific error pattern across all files
        - '#Call to an undefined method Symfony\\Component\\Form\\FormInterface#'

        # Ignore error in specific file
        - message: '#Method App\\Entity\\User::getRoles\(\) should return array<string> but returns array<int, string>#'
          path: src/Entity/User.php

    # Symfony extension config
    symfony:
        containerXmlPath: var/cache/dev/App_KernelDevDebugContainer.xml

    # Bootstrap file (for Laravel or custom autoload)
    bootstrapFiles:
        - tests/bootstrap.php

includes:
    - vendor/phpstan/phpstan-symfony/extension.neon
    - vendor/phpstan/phpstan-doctrine/extension.neon
```

Baseline adoption (for existing codebases with many violations):
```bash
# Generate baseline file that suppresses all existing violations
vendor/bin/phpstan analyse --generate-baseline phpstan-baseline.neon

# Reference baseline in phpstan.neon
# includes:
#     - phpstan-baseline.neon
```

Inline suppression:
```php
/** @phpstan-ignore-next-line */
$result = $this->legacyService->undocumentedMethod();

// Suppress specific error type
/** @phpstan-ignore-next-line argument.type */
$this->process($untypedValue);
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: PHPStan
  run: vendor/bin/phpstan analyse --no-progress --error-format=github

- name: Upload SARIF (optional)
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: phpstan-results.sarif
```

Generate SARIF output:
```bash
vendor/bin/phpstan analyse --no-progress --error-format=json | \
  phpstan-to-sarif > phpstan-results.sarif
```

## Performance

- PHPStan caches analysis results in a `tmp/` directory (configured via `tmpDir`). Cache is invalidated on PHP version, config, or source changes.
- Parallel analysis (`parallel.maximumNumberOfProcesses`) defaults to auto-detected CPU count. On CI with 2-core runners, set explicitly to 2 to avoid over-subscription.
- Higher analysis levels (8-9) are significantly slower — they require resolving all type information, including `mixed` propagation chains.
- `--no-progress` suppresses the real-time progress bar, reducing CI log noise.
- Exclude auto-generated files (migrations, entity proxies, compiled container) — they inflate analysis time and produce unavoidable violations.

## Security

PHPStan is a type-safety tool, not a dedicated security scanner. However, these checks are security-adjacent:

- Level 8 `null` checking — prevents null dereference in security-sensitive code paths (authentication, authorization checks).
- Strict return type enforcement — prevents implicit type coercion that can bypass `===` comparisons in authentication logic.
- Dead code detection (level 4+) — reveals unreachable branches that may indicate logic errors in access control.

For PHP security scanning, pair PHPStan with `psalm --taint-analysis` (taint tracking for SQL injection, XSS) or `progpilot` for dedicated SAST.

## Testing

```bash
# Run analysis at configured level
vendor/bin/phpstan analyse

# Run at a specific level
vendor/bin/phpstan analyse --level=5

# Analyse specific paths
vendor/bin/phpstan analyse src/Domain tests/Domain

# Generate baseline for existing codebase
vendor/bin/phpstan analyse --generate-baseline phpstan-baseline.neon

# Clear result cache
vendor/bin/phpstan clear-result-cache

# Show errors in different formats
vendor/bin/phpstan analyse --error-format=table
vendor/bin/phpstan analyse --error-format=json

# Debug a specific error
vendor/bin/phpstan analyse --debug src/Service/UserService.php
```

## Dos

- Start at level 5 for existing codebases and generate a baseline — then progressively increase the level and resolve violations before raising again.
- Enable `reportUnmatchedIgnoredErrors: true` — it catches `ignoreErrors` patterns that no longer match after refactoring, keeping the suppression list clean.
- Install framework extensions (`phpstan-symfony`, `phpstan-doctrine`, `larastan`) — they teach PHPStan about magic methods, container resolution, and ORM patterns that otherwise generate false positives.
- Use `--generate-baseline` on legacy code rather than adding hundreds of `@phpstan-ignore-next-line` comments — baselines are easier to manage and track.
- Pin PHPStan to a specific minor version in `composer.json` — new minor versions regularly add checks that break CI.

## Don'ts

- Don't start at level 0 and stay there — level 0 only catches missing class/function names, which PHP itself already errors on. Aim for at least level 5.
- Don't add `@phpstan-ignore-next-line` without a comment explaining why — stale suppressions accumulate and hide real future regressions.
- Don't exclude entire top-level directories (`src/`) from analysis — if code is in `paths`, it should be analyzed. Use `excludePaths` for specific auto-generated subdirectories only.
- Don't commit a baseline with thousands of suppressed errors — the baseline is a migration tool, not a permanent escape hatch.
- Don't run PHPStan without the framework extension for Symfony/Laravel/Doctrine projects — you'll get hundreds of false positives from container magic and ORM methods.
