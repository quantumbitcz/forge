# psalm

## Overview

PHP type checker and static analysis tool with taint analysis for security vulnerabilities. Psalm uses an 8-level error severity system (1 = strictest, 8 = most lenient) and supports gradual adoption via `--set-baseline`. Its key differentiator from PHPStan is built-in taint analysis (`--taint-analysis`) that tracks data flow from untrusted sources (HTTP request, database) to dangerous sinks (SQL queries, HTML output). Configuration lives in `psalm.xml`. Use Psalm and PHPStan complementarily — they have overlapping but distinct analysis capabilities.

## Architecture Patterns

### Installation & Setup

```bash
# Install via Composer
composer require --dev vimeo/psalm

# Initialise config (interactive)
vendor/bin/psalm --init

# Or generate with a specific level
vendor/bin/psalm --init src 4

# Verify
vendor/bin/psalm --version
```

Framework plugins:
```bash
composer require --dev psalm/plugin-symfony
composer require --dev weirdan/doctrine-psalm-plugin
composer require --dev psalm/plugin-laravel
vendor/bin/psalm-plugin enable psalm/plugin-symfony
```

### Rule Categories (Error Levels)

| Level | Description | Pipeline Severity |
|---|---|---|
| 1 | All issues including `MissingReturnType`, `MissingParamType` | CRITICAL for 1-4 |
| 2 | Unsafe object creation, property type coercion | CRITICAL |
| 3 | Possibly undefined properties, mixed type propagation | CRITICAL |
| 4 | Possibly null and undefined variable issues | CRITICAL |
| 5 | `MixedMethodCall`, `MixedPropertyAccess`, `MixedAssignment` | WARNING |
| 6 | `UndefinedInterfaceMethod`, more type inference errors | WARNING |
| 7 | Relaxed mixed type handling | WARNING |
| 8 | Only the most critical issues | WARNING |

Key issue types across all levels:

| Issue Type | Category | Pipeline Severity |
|---|---|---|
| `UndefinedVariable` | Correctness | CRITICAL |
| `NullReference` | Correctness | CRITICAL |
| `InvalidArgument` | Type safety | CRITICAL |
| `TaintedInput` | Security (taint) | CRITICAL |
| `TaintedSql` | Security (taint) | CRITICAL |
| `MissingReturnType` | Type coverage | WARNING |
| `MixedInferredReturnType` | Type coverage | WARNING |

### Configuration Patterns

`psalm.xml` at the project root:

```xml
<?xml version="1.0"?>
<psalm
    errorLevel="4"
    resolveFromConfigFile="true"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns="https://getpsalm.org/schema/config"
    xsi:schemaLocation="https://getpsalm.org/schema/config vendor/vimeo/psalm/config.xsd"
    findUnusedVariablesAndParams="true"
    findUnusedPsalmSuppress="true"
    checkForThrowsDocblock="false"
>
    <projectFiles>
        <directory name="src" />
        <directory name="tests" />
        <ignoreFiles>
            <directory name="src/Migrations" />   <!-- Doctrine auto-generated -->
            <directory name="vendor" />
            <directory name="var" />
        </ignoreFiles>
    </projectFiles>

    <plugins>
        <pluginClass class="Psalm\SymfonyPsalmPlugin\Plugin" />
    </plugins>

    <!-- Suppress specific issue types for legacy code -->
    <issueHandlers>
        <MissingReturnType errorLevel="info" />
        <MixedArgumentTypeCoercion errorLevel="suppress">
            <errorLevelFileIf errorLevel="warning" files="src/Legacy/**" />
        </MixedArgumentTypeCoercion>
    </issueHandlers>
</psalm>
```

Baseline adoption for existing codebases:
```bash
# Generate baseline (suppresses all current violations)
vendor/bin/psalm --set-baseline=psalm-baseline.xml

# Update baseline after resolving some violations
vendor/bin/psalm --update-baseline

# The baseline is referenced automatically from psalm.xml once generated
```

Inline suppression:
```php
/** @psalm-suppress MixedArgument */
$this->process($legacyUntypedValue);

/** @psalm-suppress NullReference -- $this->conn is guaranteed to be set in setUp() */
$this->conn->query($sql);
```

Taint analysis annotations:
```php
/**
 * @psalm-taint-source input
 */
function getUserInput(): string { ... }

/**
 * @psalm-taint-sink sql
 */
function executeQuery(string $sql): void { ... }

/**
 * @psalm-taint-escape sql
 */
function escapeForSql(string $input): string { ... }
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Psalm type checking
  run: vendor/bin/psalm --output-format=github --no-progress

- name: Psalm taint analysis
  run: vendor/bin/psalm --taint-analysis --output-format=github --no-progress
```

`--output-format=github` emits inline PR annotations. Run taint analysis as a separate step — it is significantly slower than type checking.

## Performance

- Psalm caches analysis results in a configurable cache directory (default: `~/.cache/psalm/`). Set `cacheDirectory` in `psalm.xml` to a project-local path for reproducible CI caching.
- Taint analysis (`--taint-analysis`) is 3-5x slower than regular analysis — run it separately in CI, potentially on a nightly schedule for large codebases.
- `--threads=4` enables parallel analysis (default auto-detected). Set explicitly on CI runners with known CPU counts.
- `--diff` analyzes only files changed since last successful run — reduces incremental CI time dramatically.
- Increasing the error level (e.g., 4 → 6) reduces analysis depth and speeds up runs but misses type inference issues.

## Security

Psalm's taint analysis (`--taint-analysis`) is its key security differentiator:

- Tracks data from `$_GET`, `$_POST`, `$_COOKIE`, `$_SERVER['HTTP_*']`, PDO results, and file reads as tainted.
- Reports `TaintedSql`, `TaintedHtml`, `TaintedShell`, `TaintedUnserialize`, `TaintedFile`, `TaintedHeader` when tainted data reaches dangerous sinks.
- `@psalm-taint-escape` annotation marks sanitization functions — Psalm understands that output is clean after sanitization.
- Catches second-order injection: tainted data stored in database, then retrieved and used in a sink in a separate request.

Taint analysis is not a replacement for code review but catches entire categories of injection vulnerabilities automatically across codebases too large to review manually.

## Testing

```bash
# Run type checking
vendor/bin/psalm

# Run with specific error level
vendor/bin/psalm --error-level=3

# Run taint analysis
vendor/bin/psalm --taint-analysis

# Analyse specific files
vendor/bin/psalm src/Domain/User/UserService.php

# Generate or update baseline
vendor/bin/psalm --set-baseline=psalm-baseline.xml
vendor/bin/psalm --update-baseline

# Show issue statistics
vendor/bin/psalm --stats

# Clear cache
vendor/bin/psalm --clear-cache

# List all issue types
vendor/bin/psalm --list-supported-issues

# Show issues for specific type only
vendor/bin/psalm --show-info=true
```

## Dos

- Enable `findUnusedVariablesAndParams="true"` — unused variables and params indicate dead code or copy-paste bugs.
- Enable `findUnusedPsalmSuppress="true"` — stale `@psalm-suppress` annotations accumulate after refactoring; this flag flags them for removal.
- Run taint analysis in CI on every PR — even if it's slow, SQL injection and XSS are too severe to catch only on nightly runs.
- Use error level 4 as a pragmatic starting point for established codebases — it catches null references and type mismatches without requiring full type coverage.
- Install framework plugins before running Psalm on Symfony/Doctrine/Laravel — without them, container injection and ORM magic produces hundreds of false positives.
- Use `--set-baseline` when onboarding rather than `@psalm-suppress` on every existing violation — baselines are centralized and auditable.

## Don'ts

- Don't run Psalm at level 8 long-term — it only catches the most basic issues and provides little value over a PHP syntax checker.
- Don't skip `--taint-analysis` entirely because it is slow — the security vulnerabilities it catches (SQL injection, XSS, RCE via unserialize) are critical.
- Don't use `@psalm-suppress` without a comment explaining why the suppression is intentional — undocumented suppressions become permanent workarounds.
- Don't commit a baseline with thousands of suppressions — treat the baseline as temporary scaffolding, then work down to zero baseline violations.
- Don't use Psalm as a substitute for PHPStan — they have complementary rule sets. Run both in CI for comprehensive coverage.
