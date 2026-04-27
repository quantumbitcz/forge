# i18n Validation Module

> Support tier: community

Internationalization code quality checks. Detects hard-coded user-facing strings, RTL layout violations, locale formatting issues, and translation key gaps.

## Overview

This module adds L1 regex patterns and L2 linter adapters for i18n validation. It is opt-in (`i18n.enabled: true`) and framework-aware, supporting React (i18next), Angular (ngx-translate), Vue (vue-i18n), Swift/SwiftUI (NSLocalizedString), and Kotlin/Android (R.string resources).

For full documentation of the validation system, see `shared/i18n-validation.md`.

## Dos

- **Do** wrap all user-facing strings with the project's i18n function (`t()`, `$t()`, `| translate`, `NSLocalizedString`, `R.string.*`)
- **Do** use logical CSS properties (`margin-inline-start`, `padding-inline-end`) instead of physical (`margin-left`, `padding-right`) for RTL support
- **Do** use `Intl.DateTimeFormat` and `Intl.NumberFormat` for locale-aware date and number formatting
- **Do** keep translation keys in sync across all target locales
- **Do** use Tailwind logical utilities (`ms-*`, `me-*`, `ps-*`, `pe-*`) instead of physical (`ml-*`, `mr-*`, `pl-*`, `pr-*`)
- **Do** provide context for translators via key naming or comments (e.g., `button.submit` not `btn1`)
- **Do** test the application with RTL locales (Arabic, Hebrew) to verify layout correctness
- **Do** use ICU message syntax for pluralization and gender-specific translations
- **Do** set the `lang` attribute on `<html>` to match the active locale
- **Do** handle text expansion (German text is ~30% longer than English) in layout design

## Don'ts

- **Don't** hardcode user-facing strings directly in JSX, templates, or SwiftUI views
- **Don't** use `margin-left`/`margin-right` or `text-align: left`/`right` in CSS when `start`/`end` alternatives exist
- **Don't** use `new Date().toString()` or `.toDateString()` for displaying dates to users
- **Don't** use `Number.toFixed()` without `Intl.NumberFormat` for user-facing number display
- **Don't** concatenate translated strings (word order varies by language) -- use interpolation
- **Don't** assume text direction is always LTR
- **Don't** embed locale-specific formatting (e.g., `MM/DD/YYYY`) in code
- **Don't** use images containing text that cannot be translated
- **Don't** split sentences across multiple translation keys (context loss for translators)
- **Don't** rely on string length for layout calculations (varies by locale)

## Framework-Specific Patterns

### React (react-i18next)

```tsx
// Wrong -- hardcoded string
<h1>Welcome to our application</h1>

// Correct
<h1>{t('home.welcome')}</h1>
// or
<Trans i18nKey="home.welcome">Welcome to our application</Trans>
```

### Angular (ngx-translate)

```html
<!-- Wrong -- hardcoded string -->
<h1>Welcome to our application</h1>

<!-- Correct -->
<h1>{{ 'home.welcome' | translate }}</h1>
<!-- or -->
<h1 i18n="@@home.welcome">Welcome to our application</h1>
```

### Vue (vue-i18n)

```vue
<!-- Wrong -- hardcoded string -->
<h1>Welcome to our application</h1>

<!-- Correct -->
<h1>{{ $t('home.welcome') }}</h1>
```

### Swift/SwiftUI

```swift
// Wrong -- hardcoded string
Text("Welcome to our application")

// Correct
Text(String(localized: "home.welcome"))
// or
Text(NSLocalizedString("home.welcome", comment: "Home screen title"))
```

### Kotlin/Android

```xml
<!-- Wrong -- hardcoded string -->
<TextView android:text="Welcome to our application" />

<!-- Correct -->
<TextView android:text="@string/home_welcome" />
```

### RTL CSS

```css
/* Wrong -- physical properties */
margin-left: 16px;
padding-right: 8px;
text-align: left;
float: right;

/* Correct -- logical properties */
margin-inline-start: 16px;
padding-inline-end: 8px;
text-align: start;
float: inline-end;
```
