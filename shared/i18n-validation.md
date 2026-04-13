# i18n Validation

Internationalization validation module for detecting hard-coded user-facing strings, RTL layout violations, locale formatting issues, and translation key completeness. Opt-in via `i18n.enabled: true` in config.

## Overview

The i18n validation system operates at two layers:

- **L1 (regex, sub-second):** Runs on every `Edit`/`Write` via the check engine PostToolUse hook. Detects hard-coded strings, RTL CSS violations, and hardcoded date/number formats.
- **L2 (linter adapters):** Runs at VERIFY stage. Compares translation keys across locale files for completeness. Optionally detects unused keys.

## Framework Detection

The module auto-detects the i18n framework from project dependencies when `i18n.frameworks: [auto]`:

| Detection Signal | Framework | Locale File Pattern |
|------------------|-----------|---------------------|
| `react-i18next` in package.json | react-i18next | `locales/{locale}/*.json` or `public/locales/{locale}/*.json` |
| `@ngx-translate/core` in package.json | ngx-translate | `assets/i18n/{locale}.json` |
| `vue-i18n` in package.json | vue-i18n | `src/locales/{locale}.json` |
| `.lproj` directories present | iOS NSLocalizedString | `{locale}.lproj/Localizable.strings` |
| `values-*/strings.xml` present | Android resources | `res/values-{locale}/strings.xml` |

If no framework is detected, L1 generic patterns still run. L2 key completeness is skipped with an INFO finding.

## L1 Pattern Rules

### Hard-Coded String Detection

**React (JSX/TSX):**
- Pattern: multi-word text content inside JSX elements not wrapped in `t()`, `<Trans>`, or `<FormattedMessage>`
- Regex: `>([A-Z][a-z]+(\s+[a-z]+){2,})</`
- File pattern: `*.tsx`, `*.jsx`
- Excludes: test files (`*.test.*`, `*.spec.*`), storybook (`*.stories.*`)
- Finding: `I18N-HARDCODED` WARNING

**Angular (HTML templates):**
- Pattern: multi-word text content not using `| translate` pipe or `i18n` attribute
- Regex: `>([A-Z][a-z]+(\s+[a-z]+){2,})</` in `.component.html` files
- Excludes: interpolation expressions `{{ }}`
- Finding: `I18N-HARDCODED` WARNING

**Vue (SFC templates):**
- Pattern: multi-word text content not using `$t()` or `v-t` directive
- Regex: `>([A-Z][a-z]+(\s+[a-z]+){2,})</` in `.vue` files
- Finding: `I18N-HARDCODED` WARNING

**Swift/SwiftUI:**
- Pattern: string literals in `Text()` not using `String(localized:)` or `NSLocalizedString`
- Regex: `Text\("([^"]+)"\)` where argument is a plain string literal
- Finding: `I18N-HARDCODED` WARNING

**Kotlin/Android:**
- Pattern: hardcoded strings in XML layouts not referencing `@string/` resources
- Regex: `(android:text|android:hint|android:contentDescription)="[^@][^"]*"` in XML layouts
- Regex: `setText\("` in Kotlin/Java code
- Finding: `I18N-HARDCODED` WARNING

### RTL Layout Detection

Applies to all frameworks with CSS/SCSS/Tailwind:

- Pattern: hardcoded `left`/`right` instead of logical `start`/`end` properties
- CSS regex: `(margin|padding|border|text-align|float)\s*:\s*(left|right)`
- Tailwind regex: `(ml-|mr-|pl-|pr-|left-|right-)` (physical properties instead of `ms-`/`me-`/`ps-`/`pe-`/`start-`/`end-`)
- Excludes: source maps, vendor prefixes, animation keyframes
- Finding: `I18N-RTL` INFO

### Locale Formatting Detection

Applies to all JavaScript/TypeScript frameworks:

- Pattern: date/number formatting without locale parameter
- Regex: `(toLocaleDateString|toLocaleString)\(\)` (no locale argument)
- Regex: `new Date\(\)\.(toString|toDateString|toTimeString)\(\)` (non-locale-aware)
- Regex: `\d+\.toFixed\(\d+\)` (hardcoded decimal formatting without `Intl.NumberFormat`)
- Finding: `I18N-FORMAT` INFO

## L2 Checks

### Translation Key Completeness

Runs at VERIFY stage when `i18n.checks.key_completeness: true` (default).

1. Identify source locale file from `i18n.source_locale` (default `en`)
2. Find all locale files matching the detected framework pattern
3. Parse keys from source locale
4. For each target locale, compare keys:
   - Key in source but not target: `I18N-MISSING-KEY` WARNING
   - Key in target but not source: `I18N-EXTRA-KEY` INFO (may be intentional)
5. Summary: `"{N} missing keys in {locale} ({percentage}% coverage)"`

### Unused Translation Keys

Runs when `i18n.checks.unused_keys: true` (default `false` -- can be noisy).

1. Parse all keys from source locale file
2. Search codebase for references: `t('key')`, `$t('key')`, `translate('key')`, `NSLocalizedString("key"`, `R.string.key`
3. Keys with zero references: `I18N-UNUSED-KEY` INFO
4. Skip keys matching dynamic patterns (e.g., `t(\`error.${code}\`)`)

## Finding Categories

| Category | Severity | Description |
|----------|----------|-------------|
| `I18N-HARDCODED` | WARNING | Hard-coded user-facing string not using i18n framework |
| `I18N-MISSING-KEY` | WARNING | Translation key in source locale but missing in target locale |
| `I18N-RTL` | INFO | Hardcoded left/right in CSS instead of logical start/end |
| `I18N-FORMAT` | INFO | Hardcoded date/number format instead of locale-aware Intl API |
| `I18N-UNUSED-KEY` | INFO | Translation key defined but never referenced in code |
| `I18N-EXTRA-KEY` | INFO | Translation key in target locale but not in source locale |

## Configuration Reference

```yaml
i18n:
  enabled: false                # Opt-in. Default: false.
  source_locale: en             # Source locale code. Default: en.
  target_locales: [auto]        # Auto-detect from locale directories, or explicit list.
  frameworks: [auto]            # Auto-detect i18n framework, or explicit list.
  checks:
    hardcoded_strings: true     # L1: detect hard-coded user-facing strings.
    key_completeness: true      # L2: compare translation keys across locales.
    rtl_layout: true            # L1: detect hardcoded left/right in CSS.
    locale_formatting: true     # L1: detect hardcoded date/number formats.
    unused_keys: false          # L2: detect unused translation keys (can be noisy).
  exclude_paths: []             # Paths to exclude from i18n checks.
```

## Error Handling

| Failure | Behavior |
|---------|----------|
| No i18n framework detected | L1 generic patterns still run. L2 key completeness skipped. Emit INFO. |
| Locale files not found | Skip L2 key completeness. Emit INFO. |
| False positives on non-user-facing strings | Use `exclude_paths` config or `rules-override.json` with `"disabled": true`. |
| Dynamic translation keys | L2 unused key check skips keys matching dynamic patterns. Logs INFO. |

## Performance

| Check | Time | Notes |
|-------|------|-------|
| L1 hardcoded string regex | 1-5ms per file | Runs within existing L1 budget |
| L1 RTL CSS regex | 1-3ms per file | Per CSS/SCSS file |
| L1 format regex | 1-3ms per file | Per JS/TS file |
| L2 key comparison | 5-100ms | O(n) key comparison |
| L2 unused key search | 500ms-5s | Grep across codebase |
