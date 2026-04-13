# F16: Internationalization (i18n) Validation Module

## Status
DRAFT — 2026-04-13

## Problem Statement

Internationalization defects are among the most common issues in software targeting international audiences: hard-coded user-facing strings bypass translation, missing translation keys cause fallback text or empty UI, hardcoded `left`/`right` CSS breaks RTL layouts, and hardcoded date/number formats display incorrectly in non-English locales.

Forge's check engine has ~70 code quality tool files covering linters, formatters, coverage, doc generators, security scanners, and mutation testing. However, there is no module for detecting i18n violations. The closest existing capability is the frontend reviewer's convention checks, which do not specifically target translation patterns.

**Gap:** No L1 patterns for detecting hard-coded user-facing strings. No L2 checks for translation key completeness. No checks for RTL layout violations or hardcoded locale formatting. Teams discover these issues during QA or after deployment to international markets.

**Scope:** This feature targets the six most impactful i18n validation patterns across React, Angular, Vue, Swift/SwiftUI, and Kotlin/Android. It does not cover full translation management (ICU message syntax, pluralization rules, context-aware translations) — those require integration with dedicated i18n platforms.

## Proposed Solution

Add a new code quality module `modules/code-quality/i18n-validation/` with L1 regex patterns for hard-coded string detection and L2 check integration for translation key completeness, RTL layout, and locale formatting. The module is opt-in and framework-aware.

## Detailed Design

### Architecture

```
modules/code-quality/i18n-validation/
     |
     +-- conventions.md          # Module overview, Dos/Don'ts
     +-- rules-override.json     # L1 pattern rules for check engine
     +-- l2-checks.md            # L2 linter adapter integration guide
     +-- framework-bindings/     # Per-framework detection patterns
          +-- react.md
          +-- angular.md
          +-- vue.md
          +-- swiftui.md
          +-- android.md
```

**Check engine integration:**

```
L1 (regex, sub-second):
  +-- Hard-coded string detection (per framework)
  +-- RTL CSS violations (hardcoded left/right)
  +-- Hardcoded date/number format patterns

L2 (linter adapters):
  +-- Translation key completeness (compare locale files)
  +-- Unused translation keys (keys defined but never referenced)
```

### L1 Pattern Rules

**React (JSX/TSX):**
```
Pattern: Text content inside JSX elements not wrapped in t()/Trans/FormattedMessage
Regex: >([A-Z][a-z]+(\s+[a-z]+){2,})</ (multi-word text content in JSX)
Exclude: comments, test files, storybook files
Finding: I18N-HARDCODED: WARNING
```

**Angular (HTML templates):**
```
Pattern: Text content not using translate pipe or i18n attribute
Regex: >([A-Z][a-z]+(\s+[a-z]+){2,})</  (in .component.html files)
Exclude: interpolation expressions {{ }}, structural directives
Finding: I18N-HARDCODED: WARNING
```

**Vue (SFC templates):**
```
Pattern: Text content not using $t() or v-t directive
Regex: >([A-Z][a-z]+(\s+[a-z]+){2,})</ (in <template> sections of .vue files)
Exclude: v-html content, slot fallbacks
Finding: I18N-HARDCODED: WARNING
```

**Swift/SwiftUI:**
```
Pattern: String literals in Text() views not using LocalizedStringKey
Regex: Text\("([^"]+)"\) where argument is not String(localized:) or NSLocalizedString
Finding: I18N-HARDCODED: WARNING
```

**Kotlin/Android:**
```
Pattern: Hardcoded strings in UI code not from R.string.*
Regex: (android:text|android:hint|android:contentDescription)="[^@][^"]*"  (in XML layouts)
Regex: setText\("  (in Kotlin/Java activity/fragment code)
Finding: I18N-HARDCODED: WARNING
```

**RTL Layout (CSS/SCSS/Tailwind — all frameworks):**
```
Pattern: Hardcoded left/right instead of logical start/end
Regex: (margin|padding|border|text-align|float)\s*:\s*(left|right)
Regex: (ml-|mr-|pl-|pr-|left-|right-) (Tailwind physical properties)
Exclude: source maps, vendor prefixes, animation keyframes
Finding: I18N-RTL: INFO
```

**Locale Formatting (all frameworks):**
```
Pattern: Hardcoded date/number format strings
Regex: (toLocaleDateString|toLocaleString)\(\)  (no locale argument)
Regex: new Date\(\)\.to(String|DateString|TimeString)\(\)  (non-locale-aware)
Regex: \d+\.toFixed\(\d+\)  (hardcoded decimal formatting without Intl)
Finding: I18N-FORMAT: INFO
```

### L2 Checks

**Translation Key Completeness:**

```
Algorithm:
1. Identify source locale file (from config: i18n.source_locale, default "en")
2. Find all locale files matching the pattern:
   - React (i18next): locales/{locale}/*.json or public/locales/{locale}/*.json
   - Angular (@ngx-translate): assets/i18n/{locale}.json
   - Vue (vue-i18n): src/locales/{locale}.json
   - iOS: {locale}.lproj/Localizable.strings
   - Android: values-{locale}/strings.xml
3. Parse keys from source locale
4. For each target locale, compare keys:
   - Key in source but not target → I18N-MISSING-KEY: WARNING
   - Key in target but not source → I18N-EXTRA-KEY: INFO (may be intentional)
5. Report summary: "{N} missing keys in {locale} ({percentage}% coverage)"
```

**Unused Translation Keys:**

```
Algorithm:
1. Parse all keys from source locale file
2. Search codebase for each key reference (t('key'), $t('key'), translate('key'))
3. Keys with zero references → I18N-UNUSED-KEY: INFO
4. Skip keys matching dynamic key patterns (e.g., t(`error.${code}`))
```

### Schema / Data Model

**Finding categories in `category-registry.json`:**

```json
{
  "I18N-HARDCODED": { "description": "Hard-coded user-facing string not using i18n framework", "agents": ["fg-410-code-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-410-code-reviewer", "fg-413-frontend-reviewer"] },
  "I18N-MISSING-KEY": { "description": "Translation key present in source locale but missing in target locale", "agents": ["fg-410-code-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-410-code-reviewer"] },
  "I18N-RTL": { "description": "Hardcoded left/right in CSS instead of logical start/end properties", "agents": ["fg-410-code-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-410-code-reviewer", "fg-413-frontend-reviewer"] },
  "I18N-FORMAT": { "description": "Hardcoded date/number format instead of locale-aware Intl API", "agents": ["fg-410-code-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-410-code-reviewer"] },
  "I18N-UNUSED-KEY": { "description": "Translation key defined but never referenced in code", "agents": ["fg-410-code-reviewer"], "wildcard": false, "priority": 6, "affinity": ["fg-410-code-reviewer"] },
  "I18N-EXTRA-KEY": { "description": "Translation key in target locale but not in source locale", "agents": ["fg-410-code-reviewer"], "wildcard": false, "priority": 6, "affinity": ["fg-410-code-reviewer"] }
}
```

**Rules override file** (`modules/code-quality/i18n-validation/rules-override.json`):

```json
{
  "_module": "i18n-validation",
  "rules": [
    {
      "id": "i18n-hardcoded-jsx",
      "pattern": ">([A-Z][a-z]+(\\s+[a-z]+){2,})</",
      "file_pattern": "*.tsx",
      "category": "I18N-HARDCODED",
      "severity": "WARNING",
      "description": "Hard-coded text in JSX — wrap with t() or <Trans>",
      "exclude_patterns": ["*.test.*", "*.stories.*", "*.spec.*"]
    },
    {
      "id": "i18n-rtl-css",
      "pattern": "(margin|padding|border|text-align|float)\\s*:\\s*(left|right)",
      "file_pattern": "*.{css,scss,less}",
      "category": "I18N-RTL",
      "severity": "INFO",
      "description": "Use logical properties (start/end) instead of physical (left/right) for RTL support"
    },
    {
      "id": "i18n-format-date",
      "pattern": "new Date\\(\\)\\.(toString|toDateString|toTimeString)\\(\\)",
      "file_pattern": "*.{ts,tsx,js,jsx}",
      "category": "I18N-FORMAT",
      "severity": "INFO",
      "description": "Use Intl.DateTimeFormat or toLocaleDateString(locale) for locale-aware date formatting"
    }
  ]
}
```

### Configuration

In `forge-config.md`:

```yaml
# Internationalization validation (v2.0+)
i18n:
  enabled: false              # Opt-in. Default: false. Enable for projects with i18n requirements.
  source_locale: en           # Source locale code. Default: en.
  target_locales: [auto]      # Auto-detect from locale directory structure, or explicit list: [es, fr, de, ja]
  frameworks: [auto]          # Auto-detect i18n framework, or explicit: [react-i18next, ngx-translate, vue-i18n]
  checks:
    hardcoded_strings: true   # L1: detect hard-coded user-facing strings. Default: true.
    key_completeness: true    # L2: compare translation keys across locales. Default: true.
    rtl_layout: true          # L1: detect hardcoded left/right in CSS. Default: true.
    locale_formatting: true   # L1: detect hardcoded date/number formats. Default: true.
    unused_keys: false        # L2: detect unused translation keys. Default: false (can be noisy).
  exclude_paths: []           # Paths to exclude from i18n checks (e.g., admin panels, internal tools)
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `i18n.enabled` | boolean | `false` | Not all projects need i18n; explicit opt-in |
| `i18n.source_locale` | valid BCP 47 locale | `en` | Must be a real locale code |
| `i18n.target_locales` | `[auto]` or list of locale codes | `[auto]` | Auto-detection scans locale directories |
| `i18n.frameworks` | `[auto]` or list of i18n framework names | `[auto]` | Auto-detection from package.json/Podfile/build.gradle |

### Data Flow

**L1 check flow (per edit/write):**

1. Check engine PostToolUse hook fires on Edit|Write
2. Engine loads `i18n-validation/rules-override.json` (if `i18n.enabled`)
3. L1 regex patterns run against the modified file
4. Matches produce `I18N-HARDCODED`, `I18N-RTL`, `I18N-FORMAT` findings
5. Findings flow to standard scoring pipeline

**L2 check flow (at VERIFY stage):**

1. Build verifier or quality gate triggers L2 checks
2. L2 adapter identifies locale files based on framework detection
3. Key completeness check compares source vs target locale files
4. Produces `I18N-MISSING-KEY` findings with file locations
5. Optionally runs unused key detection (`i18n.checks.unused_keys`)

**Framework auto-detection:**

| Detection Signal | Framework | Locale File Pattern |
|---|---|---|
| `react-i18next` in package.json | react-i18next | `locales/{locale}/*.json` |
| `@ngx-translate/core` in package.json | ngx-translate | `assets/i18n/{locale}.json` |
| `vue-i18n` in package.json | vue-i18n | `src/locales/{locale}.json` |
| `.lproj` directories | iOS NSLocalizedString | `{locale}.lproj/Localizable.strings` |
| `values-*/strings.xml` | Android resources | `res/values-{locale}/strings.xml` |

### Integration Points

| File | Change |
|---|---|
| `modules/code-quality/i18n-validation/` | NEW — module directory with conventions.md, rules-override.json, l2-checks.md, framework-bindings/ |
| `shared/checks/category-registry.json` | Add 6 new I18N-* categories |
| `shared/checks/layer-1-fast/` | L1 engine loads i18n rules when enabled |
| `shared/checks/layer-2-linter/` | L2 adapter for translation key completeness |
| `modules/frameworks/{react,angular,vue,swiftui}/conventions.md` | Add i18n Dos/Don'ts section |
| `modules/frameworks/*/forge-config-template.md` | Add `i18n:` section |
| `shared/learnings/i18n.md` | NEW — learnings file for i18n patterns |

### Error Handling

**Failure mode 1: No i18n framework detected.**
- Detection: Auto-detection finds no i18n library in dependencies
- Behavior: L1 hardcoded string checks still run (framework-generic patterns). L2 key completeness skipped. Emit INFO: "No i18n framework detected. Running generic hardcoded string patterns only."

**Failure mode 2: Locale files not found.**
- Detection: Expected locale directory pattern yields no files
- Behavior: Skip L2 key completeness. Emit INFO: "No locale files found at expected paths."

**Failure mode 3: False positives on hardcoded strings.**
- Detection: Strings in non-user-facing code (logging, errors, constants) flagged
- Mitigation: Exclude patterns for test files, storybook, internal tooling. `exclude_paths` config for project-specific exclusions. `rules-override.json` supports `"disabled": true` per rule.

**Failure mode 4: Dynamic translation keys cause false negatives.**
- Detection: Keys constructed at runtime (e.g., `t(`error.${code}`)`) cannot be statically resolved
- Behavior: L2 unused key check skips keys matching dynamic patterns. Logs INFO noting that dynamic keys are excluded from completeness analysis.

## Performance Characteristics

**L1 checks (per edit):**

| Check | Time | Notes |
|---|---|---|
| Hardcoded string regex | 1-5ms | Per file, single regex |
| RTL CSS regex | 1-3ms | Per CSS/SCSS file |
| Format regex | 1-3ms | Per JS/TS file |
| **Total per edit** | **1-5ms** | Negligible; runs within existing L1 budget |

**L2 checks (at VERIFY stage):**

| Check | Time | Notes |
|---|---|---|
| Parse locale files | 10-100ms | Depends on file count and size |
| Key comparison | 5-50ms | O(n) key comparison |
| Unused key search | 500ms-5s | Grep across codebase for each key |
| **Total** | **515ms-5.15s** | Well within VERIFY stage budget |

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Module structure:** `modules/code-quality/i18n-validation/` contains `conventions.md`, `rules-override.json`
2. **Category registration:** All 6 `I18N-*` codes exist in `category-registry.json`
3. **Rules override format:** `rules-override.json` validates against expected schema

### Unit Tests (`tests/unit/`)

1. **`i18n-validation.bats`:**
   - Hardcoded JSX text detected: `>Welcome to our app</` produces `I18N-HARDCODED`
   - Wrapped JSX text not flagged: `>{t('welcome')}</` passes
   - RTL CSS detected: `margin-left: 10px` produces `I18N-RTL`
   - Logical CSS not flagged: `margin-inline-start: 10px` passes
   - Format detected: `new Date().toString()` produces `I18N-FORMAT`
   - Config disabled: `i18n.enabled: false` skips all i18n checks
   - Excluded paths respected

2. **`i18n-key-completeness.bats`:**
   - Missing key detected when source has key absent from target locale
   - 100% coverage reports no `I18N-MISSING-KEY` findings
   - Auto-detection identifies react-i18next from package.json

## Acceptance Criteria

1. Hard-coded user-facing strings detected in React (JSX), Angular (templates), Vue (SFC), Swift (Text()), and Android (XML layouts)
2. Translation key completeness compares source locale against all target locales
3. RTL layout violations detected for hardcoded left/right in CSS properties
4. Locale formatting violations detected for non-`Intl` date/number formatting
5. All i18n checks disabled when `i18n.enabled: false`
6. Framework auto-detection correctly identifies i18n library from package manager files
7. L1 checks add negligible latency (<5ms per edit)
8. L2 checks complete within 5 seconds for typical projects (<1,000 translation keys)
9. Test files, storybook, and excluded paths are not flagged
10. Module follows existing code quality module structure conventions

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** Module is opt-in (`i18n.enabled: false` default).
2. **New module directory:** `modules/code-quality/i18n-validation/` added alongside existing ~70 code quality modules.
3. **Rules loaded conditionally:** L1 engine only loads i18n rules when `i18n.enabled: true` in config.
4. **Category registry:** Six new codes added. No changes to existing codes or scoring formula.
5. **No new external dependencies.** All checks use built-in regex patterns and file parsing.

## Dependencies

**This feature depends on:**
- Check engine L1 pattern matching (`shared/checks/engine.sh`) for regex-based detection
- Check engine L2 linter adapter framework for key completeness checks
- Framework detection at PREFLIGHT (already reads package.json, Podfile, build.gradle)

**Other features that benefit from this:**
- F15 (Cross-Browser A11y): RTL layout checks complement dynamic RTL testing
- Frontend reviewer (fg-413): i18n convention violations feed into frontend review findings
- Codebase health (`/codebase-health`): i18n module included in full codebase scans when enabled
