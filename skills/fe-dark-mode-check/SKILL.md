---
name: fe-dark-mode-check
description: Verify a component or page works correctly in both light and dark mode using Playwright screenshots
disable-model-invocation: true
---

# Dark Mode Verification

Verify that a component or page renders correctly in both light and dark mode.

## Steps

1. **Start dev server** if not already running:

   ```bash
   bun run dev &
   ```

2. **Navigate to the page** using Playwright MCP:
   - Take a screenshot in light mode (default)
   - Toggle dark mode by adding `.dark` class to the root element
   - Take a screenshot in dark mode

3. **Compare and check for**:
   - Text readable against backgrounds in both modes
   - No pure white (#fff) elements on dark backgrounds
   - Borders visible (prefer borders over shadows in dark mode)
   - Status colors (emerald/amber/red) still readable
   - Custom properties all resolving (no missing dark mode variants)
   - Charts and graphs rendering correctly with `var(--border)` and `var(--muted-foreground)`

4. **Report findings** with specific elements that need attention.

## Common Dark Mode Issues

- `bg-white` instead of `bg-card` → invisible in dark mode
- `text-gray-900` instead of `text-foreground` → invisible in dark mode
- `shadow-lg` without border fallback → invisible shadow in dark mode
- `border-gray-200` instead of `border-border` → wrong color in dark mode
