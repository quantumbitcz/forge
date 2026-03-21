---
name: fe-check-theme
description: Scan files for hardcoded colors, wrong font-size patterns, and theme token violations — quick lint for WellPlanned design system
disable-model-invocation: true
---

# Theme Compliance Check

Scan recently changed or specified files for WellPlanned design system violations.

## What to Scan

If the user specifies files, scan those. Otherwise, scan recently modified files:

```bash
git diff --name-only HEAD | grep -E '\.(tsx|ts)$'
```

## Violations to Detect

### Critical — Hardcoded Colors

Search for these patterns in `.tsx` files (excluding `ui/` base components and `theme.css`):

```bash
# Hardcoded backgrounds
grep -rn 'bg-white\|bg-black\|bg-gray-\|bg-slate-\|bg-zinc-\|bg-neutral-\|bg-stone-' --include='*.tsx' src/app/components/ --exclude-dir=ui

# Hardcoded text colors
grep -rn 'text-white\|text-black\|text-gray-\|text-slate-' --include='*.tsx' src/app/components/ --exclude-dir=ui

# Hex colors in className (not in style objects for gradients)
grep -rn "className=.*#[0-9a-fA-F]\{3,6\}" --include='*.tsx' src/app/components/
```

**Fix**: Replace with theme tokens:

- `bg-white` → `bg-background` or `bg-card`
- `bg-gray-100` → `bg-muted` or `bg-muted/30`
- `text-gray-500` → `text-muted-foreground`
- `border-gray-200` → `border-border` or `border-border/50`

### Critical — Tailwind Font-Size Classes

```bash
grep -rn 'text-xs\|text-sm\|text-base\|text-lg\|text-xl\|text-2xl\|text-3xl\|text-4xl\|text-5xl' --include='*.tsx' src/app/components/ --exclude-dir=ui
```

**Fix**: Replace with inline `style={{ fontSize: "X.Xrem" }}` using the project scale.

### Warning — Missing Empty States

For components that render lists or charts, check they handle the zero-data case.

## Output

Report violations grouped by file with line numbers and suggested fixes.
