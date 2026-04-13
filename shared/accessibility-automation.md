# Accessibility Automation

Dynamic accessibility testing via Playwright MCP. Complements static WCAG analysis in `fg-413-frontend-reviewer` Part C with runtime keyboard, focus, and ARIA verification.

## Prerequisites

- Playwright MCP tools available (`mcp__plugin_playwright_playwright__*`)
- Preview URL or dev server URL configured (`visual_verification.dev_server_url`)
- `accessibility.dynamic_checks: true` in config (default)

If Playwright MCP is unavailable, all dynamic checks are skipped with an INFO finding. Static checks (Part C.1) still run.

## Tab-Order Verification

**Playwright operations:** `browser_navigate`, `browser_press_key("Tab")`, `browser_evaluate`

**Algorithm:**

1. Navigate to the page under test via `browser_navigate`
2. Send `Tab` key repeatedly via `browser_press_key("Tab")`, up to `accessibility.tab_order_max_elements` (default 50)
3. After each Tab press, capture the focused element via `browser_evaluate`:
   ```javascript
   JSON.stringify({
     tag: document.activeElement.tagName,
     id: document.activeElement.getAttribute('id'),
     role: document.activeElement.getAttribute('role'),
     rect: document.activeElement.getBoundingClientRect()
   })
   ```
4. Build an ordered list of focused elements with their viewport positions
5. Query all focusable elements in the DOM for comparison:
   ```javascript
   document.querySelectorAll('a[href], button, input, select, textarea, [tabindex]:not([tabindex="-1"])')
   ```
6. **Verify logical order:** elements are focused in top-to-bottom, left-to-right order (right-to-left for RTL layouts detected via `document.documentElement.dir`)
7. **Verify completeness:** no interactive element is skipped (compare tab traversal list against DOM query results)
8. **Detect anti-patterns:** elements with `tabindex > 0` (breaks natural order)

**Findings:**
- `A11Y-KEYBOARD` WARNING: tab order skips interactive elements
- `A11Y-KEYBOARD` WARNING: no focusable elements found (page may lack interactive content)
- `A11Y-KEYBOARD` INFO: elements use `tabindex > 0` (anti-pattern)

## Focus Indicator Detection

**Playwright operations:** `browser_evaluate`, `browser_take_screenshot`

**Algorithm:**

1. For each focusable element discovered during tab-order traversal:
2. Capture unfocused state — record computed styles and take element screenshot
3. Focus the element via `browser_evaluate`:
   ```javascript
   document.querySelector(selector).focus();
   ```
4. Capture focused state — computed styles for `outline`, `outline-offset`, `box-shadow`, `border`:
   ```javascript
   const el = document.activeElement;
   const s = getComputedStyle(el);
   JSON.stringify({
     outline: s.outline,
     outlineOffset: s.outlineOffset,
     boxShadow: s.boxShadow,
     border: s.border
   })
   ```
5. Take element screenshot in focused state via `browser_take_screenshot`
6. Compare focused vs unfocused states:
   - If `outline: none` or `outline: 0` AND no `box-shadow` change AND no `border` change: **no visible focus indicator**
   - Pixel diff between screenshots below `accessibility.focus_pixel_diff_threshold` (default 0.5%): **no visible focus indicator**

**Findings:**
- `A11Y-FOCUS` WARNING: element has no visible focus indicator (outline removed without replacement)
- `A11Y-FOCUS` WARNING: focus indicator contrast below 3:1 against background

## Keyboard-Only Navigation Testing

**Playwright operations:** `browser_press_key`, `browser_evaluate`

**Algorithm:**

1. Identify interactive patterns in changed components by analyzing the DOM:
   - **Dropdown menus:** elements with `aria-expanded`, `role="menu"`, or `role="listbox"`
   - **Modal dialogs:** elements with `role="dialog"` or `aria-modal="true"`
   - **Tooltips:** elements with `aria-describedby` pointing to tooltip content
   - **Accordion/tabs:** elements with `role="tablist"` or `role="tab"`

2. For each detected pattern, execute the keyboard interaction sequence:

   | Pattern | Keys | Expected Behavior |
   |---------|------|-------------------|
   | Dropdown | Enter/Space to open, Escape to close, Arrow keys to navigate | `aria-expanded` toggles, focus moves to menu items |
   | Modal | Enter to open trigger, Tab cycles within modal, Escape to close | Focus trapped inside modal, returns to trigger on close |
   | Tooltip | Focus on trigger element | Tooltip content becomes visible |
   | Accordion/Tabs | Arrow keys between tabs, Enter/Space to activate | `aria-selected` updates, panel content changes |

3. Verify expected state changes via `browser_evaluate`
4. Detect focus traps by checking if Tab returns to the same element after cycling

**Findings:**
- `A11Y-KEYBOARD` WARNING: dropdown not operable via keyboard (Enter/Space does not toggle)
- `A11Y-KEYBOARD` CRITICAL: modal does not trap focus (Tab escapes modal boundary)
- `A11Y-KEYBOARD` WARNING: tooltip only accessible via hover (no keyboard trigger)

## ARIA Pattern Matching

**Playwright operations:** `browser_evaluate`

**Algorithm:**

1. For each changed component with dynamic behavior, query ARIA attributes:
   ```javascript
   const el = document.querySelector(selector);
   JSON.stringify({
     role: el.getAttribute('role'),
     ariaLabel: el.getAttribute('aria-label'),
     ariaExpanded: el.getAttribute('aria-expanded'),
     ariaControls: el.getAttribute('aria-controls'),
     ariaLive: el.getAttribute('aria-live'),
     ariaHidden: el.getAttribute('aria-hidden'),
     ariaModal: el.getAttribute('aria-modal'),
     ariaSelected: el.getAttribute('aria-selected'),
     ariaLabelledby: el.getAttribute('aria-labelledby')
   })
   ```

2. Verify completeness against the component pattern:

   | Pattern | Required ARIA | Notes |
   |---------|---------------|-------|
   | Dropdown | `aria-expanded`, `aria-controls` | Toggle must reflect open/closed state |
   | Modal | `role="dialog"`, `aria-labelledby`, `aria-modal="true"` | Label must reference visible heading |
   | Tab panel | `role="tablist"` on container, `role="tab"` + `aria-selected` on tabs, `role="tabpanel"` + `aria-labelledby` on panels | |
   | Live region | `aria-live="polite"` or `"assertive"` | For toast, notifications, async updates |
   | Accordion | `aria-expanded` on trigger, `aria-controls` pointing to content panel | |

3. Check that `aria-labelledby` and `aria-controls` reference existing element IDs

**Findings:**
- `A11Y-ARIA` WARNING: dropdown toggle missing `aria-expanded`
- `A11Y-ARIA` WARNING: modal missing `aria-labelledby` (screen readers cannot identify dialog)
- `A11Y-ARIA` INFO: toast container should use `aria-live="polite"` for non-urgent notifications
- `A11Y-ARIA` WARNING: `aria-controls` references non-existent ID

## Cross-Browser Accessibility

When `visual_verification.cross_browser: true`, dynamic a11y checks run in all configured browsers (Chromium, Firefox, WebKit). This catches browser-specific ARIA interpretation differences:

- WebKit/VoiceOver may interpret `role` attributes differently than Chromium/NVDA
- Firefox focus indicator rendering may differ from Chromium
- Tab order can vary between browsers when CSS `order` or flexbox is used

Each browser's results are compared; discrepancies produce `FE-BROWSER-COMPAT` findings.

## Configuration Reference

```yaml
accessibility:
  dynamic_checks: true              # Enable runtime keyboard/focus/ARIA checks. Default: true.
  tab_order_max_elements: 50        # Max elements to tab through per page. Default: 50. Range: 10-200.
  focus_pixel_diff_threshold: 0.5   # Min pixel diff % to consider focus visible. Default: 0.5. Range: 0.1-5.0.
  interaction_patterns: [dropdown, modal, tooltip, accordion, tabs]

visual_verification:
  cross_browser: false              # Opt-in cross-browser testing. Default: false.
  browsers: [chromium, firefox, webkit]
  diff_warning_threshold: 5         # Pixel diff % for WARNING. Default: 5. Range: 1-20.
  diff_critical_threshold: 15       # Pixel diff % for CRITICAL. Default: 15. Range: 10-50.
```

## Error Handling

| Failure | Behavior |
|---------|----------|
| Playwright MCP unavailable | Skip all dynamic checks. Emit INFO. Static checks still run. |
| Page fails to load | Skip dynamic checks for that page. Emit INFO with URL and error. |
| No focusable elements | Emit `A11Y-KEYBOARD` WARNING. |
| Browser engine not installed | Skip that browser. Emit INFO with install instructions. |
| Timeout during tab traversal | Stop at current element count. Report partial results. |
