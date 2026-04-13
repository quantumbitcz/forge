# F15: Cross-Browser Testing and Advanced Accessibility Automation

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge's frontend reviewer (`fg-413-frontend-reviewer`) performs static WCAG 2.2 AA checks: contrast ratios, ARIA attributes, semantic HTML, alt text, and landmark structure. These checks analyze source code and — when Playwright MCP is available — take screenshots for visual verification. However, the reviewer cannot verify dynamic accessibility behaviors that require browser interaction.

**Dynamic a11y gaps:**
- **Tab order:** No verification that interactive elements follow a logical tab sequence. A sighted user may not notice that Tab jumps from the header to the footer, skipping the main content.
- **Focus visibility:** No check that every focusable element has a visible focus indicator. CSS `outline: none` without a replacement is invisible to keyboard users.
- **Keyboard-only navigation:** No verification that all interactive elements (dropdowns, modals, tooltips) are operable without a mouse.
- **ARIA live regions:** No validation that dynamic content updates are announced to screen readers.

**Cross-browser gap:** Visual verification currently runs in a single browser (Chromium via Playwright). Layout differences between Firefox and WebKit (Safari) can cause real accessibility and visual regressions that go undetected.

**Competitive context:** Deque axe-core provides automated a11y audits but does not test keyboard navigation flows. pa11y tests individual pages but not interaction sequences. No AI coding tool combines static a11y analysis with automated keyboard navigation verification.

## Proposed Solution

Enhance `fg-413-frontend-reviewer` with two new capabilities:

1. **Dynamic accessibility checks** via Playwright MCP: automated tab-order verification, focus visibility detection, keyboard-only navigation testing, and ARIA completeness validation.
2. **Cross-browser visual testing** (opt-in): run visual verification across Chromium, Firefox, and WebKit, comparing screenshots for layout discrepancies.

## Detailed Design

### Architecture

```
fg-413-frontend-reviewer
     |
     +-- Part A: Code Conventions (existing)
     +-- Part B: Design Quality (existing)
     +-- Part C: Accessibility (ENHANCED)
     |     +-- C.1: Static WCAG checks (existing)
     |     +-- C.2: Dynamic keyboard/focus checks (NEW)
     |     |     +-- Tab order verification
     |     |     +-- Focus visibility audit
     |     |     +-- Keyboard-only interaction test
     |     |     +-- ARIA live region validation
     |     +-- C.3: Cross-browser a11y (NEW, opt-in)
     |
     +-- Part D: Performance (existing)
     +-- Part E: Cross-Browser Visual (NEW, opt-in)
           +-- Chromium screenshot (existing)
           +-- Firefox screenshot (NEW)
           +-- WebKit screenshot (NEW)
           +-- Pixel-diff comparison
```

**Playwright MCP dependency:** Dynamic checks require `mcp__plugin_playwright_playwright__*` tools. If Playwright MCP is unavailable, the dynamic checks are skipped and an INFO finding is emitted: "Dynamic a11y checks skipped: Playwright MCP not available."

### Dynamic Accessibility Checks

#### Tab Order Verification

```
Algorithm:
1. Navigate to the page via browser_navigate
2. Send Tab key repeatedly via browser_press_key("Tab")
3. After each Tab, capture the focused element via browser_evaluate:
   - document.activeElement.tagName
   - document.activeElement.getAttribute('id')
   - document.activeElement.getBoundingClientRect() (position)
4. Build ordered list of focused elements with their positions
5. Verify: elements are focused in top-to-bottom, left-to-right order
   (with exceptions for RTL layouts where order is right-to-left)
6. Verify: no interactive element is skipped (compare against DOM query
   for all focusable elements: a, button, input, select, textarea, [tabindex])
7. Report A11Y-KEYBOARD findings for violations
```

**Finding format:**
```
A11Y-KEYBOARD: WARNING: Tab order skips main content — focus jumps from #header-nav to #footer-links, bypassing #search-input and #main-content interactive elements
A11Y-KEYBOARD: INFO: Tab order includes 3 elements with tabindex > 0 (anti-pattern; use tabindex="0" and DOM order instead)
```

#### Focus Visibility Audit

```
Algorithm:
1. For each focusable element discovered during tab-order traversal:
2. Focus the element via browser_evaluate: element.focus()
3. Capture computed styles via browser_evaluate:
   - outline, outline-offset, box-shadow, border
4. Take element screenshot via browser_take_screenshot
5. Compare focused vs unfocused screenshot (pixel diff)
6. If no visible focus indicator detected:
   - outline: none/0 AND no box-shadow AND no border change = FAIL
7. Report A11Y-FOCUS findings
```

**Finding format:**
```
A11Y-FOCUS: WARNING: src/components/Button.tsx:15: Button element has no visible focus indicator — outline removed without replacement. Add outline, box-shadow, or border change on :focus-visible.
```

#### Keyboard-Only Navigation Test

```
Algorithm:
1. Identify interactive patterns in changed components:
   - Dropdown menus: verify open/close with Enter/Space/Escape
   - Modal dialogs: verify focus trap (Tab cycles within modal)
   - Tooltips: verify accessible via focus (not hover-only)
   - Accordion/tabs: verify Arrow key navigation
2. For each pattern, execute keyboard interaction sequence
3. Verify expected state changes via browser_evaluate (e.g., dropdown open)
4. Report A11Y-KEYBOARD findings for failures
```

#### ARIA Completeness Validation

```
Algorithm:
1. For each changed component with dynamic behavior:
2. Query ARIA attributes via browser_evaluate:
   - role, aria-label, aria-expanded, aria-controls, aria-live, aria-hidden
3. Verify completeness against component pattern:
   - Dropdown: requires aria-expanded, aria-controls
   - Modal: requires role="dialog", aria-labelledby, aria-modal="true"
   - Tab panel: requires role="tablist", role="tab", aria-selected
   - Live region: requires aria-live="polite" or "assertive"
4. Report A11Y-ARIA findings for missing/incorrect attributes
```

**Finding format:**
```
A11Y-ARIA: WARNING: src/components/Dropdown.tsx:42: Dropdown toggle missing aria-expanded attribute — screen readers cannot determine open/closed state
A11Y-ARIA: INFO: src/components/Toast.tsx:18: Toast container should use aria-live="polite" for non-urgent notifications
```

### Cross-Browser Visual Testing

When `visual_verification.cross_browser: true`:

1. Run visual verification in Chromium (existing behavior)
2. Run same pages in Firefox via Playwright `firefox` browser
3. Run same pages in WebKit via Playwright `webkit` browser
4. Compare screenshots across browsers using pixel-diff:
   - Compute percentage of differing pixels
   - Threshold: >5% diff = `FE-BROWSER-COMPAT` (WARNING)
   - Threshold: >15% diff = `FE-BROWSER-COMPAT` (CRITICAL)
5. Generate diff image highlighting discrepancies

**Finding format:**
```
FE-BROWSER-COMPAT: WARNING: /dashboard — 7.2% pixel difference between Chromium and Firefox. Layout shift in sidebar navigation at 1024px width.
FE-BROWSER-COMPAT: CRITICAL: /login — 18.5% pixel difference between Chromium and WebKit. Form inputs render with different heights; submit button overlaps error text.
```

### Schema / Data Model

**Dynamic a11y report** (in stage notes):

```markdown
### Dynamic Accessibility Audit

| Check | Elements Tested | Pass | Fail | Skip |
|---|---|---|---|---|
| Tab order | 24 | 22 | 2 | 0 |
| Focus visibility | 24 | 20 | 4 | 0 |
| Keyboard navigation | 6 patterns | 5 | 1 | 0 |
| ARIA completeness | 8 components | 6 | 2 | 0 |

### Cross-Browser Visual Comparison

| Page | Chromium vs Firefox | Chromium vs WebKit |
|---|---|---|
| /dashboard | 2.1% (PASS) | 1.8% (PASS) |
| /login | 7.2% (WARNING) | 18.5% (CRITICAL) |
```

**New finding categories in `category-registry.json`:**

```json
{
  "A11Y-KEYBOARD": { "description": "Keyboard navigation issue (tab order, focus trap, interaction)", "agents": ["fg-413-frontend-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-413-frontend-reviewer"] },
  "A11Y-FOCUS": { "description": "Focus visibility issue (missing or insufficient focus indicator)", "agents": ["fg-413-frontend-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-413-frontend-reviewer"] },
  "A11Y-ARIA": { "description": "ARIA attribute completeness issue (missing or incorrect ARIA)", "agents": ["fg-413-frontend-reviewer"], "wildcard": false, "priority": 5, "affinity": ["fg-413-frontend-reviewer"] },
  "FE-BROWSER-COMPAT": { "description": "Cross-browser visual discrepancy exceeding threshold", "agents": ["fg-413-frontend-reviewer"], "wildcard": false, "priority": 3, "affinity": ["fg-413-frontend-reviewer"] }
}
```

### Configuration

In `forge-config.md`:

```yaml
# Dynamic accessibility checks (v2.0+)
accessibility:
  dynamic_checks: true              # Enable keyboard/focus/ARIA runtime checks. Default: true.
  tab_order_max_elements: 50        # Max elements to tab through. Default: 50. Range: 10-200.
  focus_pixel_diff_threshold: 0.5   # Min pixel diff % to consider focus visible. Default: 0.5. Range: 0.1-5.0.
  interaction_patterns: [dropdown, modal, tooltip, accordion, tabs]  # Patterns to test.

# Cross-browser visual testing (v2.0+)
visual_verification:
  cross_browser: false              # Opt-in. Default: false. Adds ~30-60s per page.
  browsers: [chromium, firefox, webkit]  # Browsers to test. Default: all three.
  diff_warning_threshold: 5         # Pixel diff % for WARNING. Default: 5. Range: 1-20.
  diff_critical_threshold: 15       # Pixel diff % for CRITICAL. Default: 15. Range: 10-50.
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `accessibility.dynamic_checks` | boolean | `true` | Low overhead when Playwright is available; graceful skip when not |
| `accessibility.tab_order_max_elements` | 10-200 | 50 | Prevent runaway tabbing on complex pages |
| `visual_verification.cross_browser` | boolean | `false` | Significant latency cost; opt-in |
| `visual_verification.diff_warning_threshold` | 1-20 | 5 | Below 1% is noise; above 20% misses real issues |
| `visual_verification.diff_critical_threshold` | 10-50 | 15 | Must be > `diff_warning_threshold` |

### Data Flow

**Dynamic a11y check flow:**

1. Frontend reviewer enters Part C (Accessibility)
2. C.1 static checks run as before (source code analysis)
3. C.2 dynamic checks: reviewer checks if Playwright MCP is available
4. If available: navigate to each page affected by changed components
5. Execute tab-order, focus-visibility, keyboard-interaction, ARIA checks
6. Collect findings as `A11Y-KEYBOARD`, `A11Y-FOCUS`, `A11Y-ARIA`
7. If Playwright MCP unavailable: emit INFO "Dynamic a11y checks skipped" and continue

**Cross-browser flow:**

1. After standard visual verification (Chromium screenshots)
2. If `visual_verification.cross_browser: true`:
3. Re-run same pages in Firefox, capture screenshots
4. Re-run same pages in WebKit, capture screenshots
5. Compute pixel-diff percentages for each page across browser pairs
6. Emit `FE-BROWSER-COMPAT` findings where thresholds exceeded
7. Include diff highlights in stage notes

### Integration Points

| File | Change |
|---|---|
| `agents/fg-413-frontend-reviewer.md` | Add Part C.2 (dynamic a11y checks), Part C.3 (cross-browser a11y), Part E (cross-browser visual). Update mode table to include dynamic checks in `full` and `a11y-only` modes. |
| `shared/checks/category-registry.json` | Add `A11Y-KEYBOARD`, `A11Y-FOCUS`, `A11Y-ARIA`, `FE-BROWSER-COMPAT` |
| `shared/visual-verification.md` | Add cross-browser comparison section |
| `modules/frameworks/*/forge-config-template.md` | Add `accessibility:` and update `visual_verification:` sections |

### Error Handling

**Failure mode 1: Playwright MCP unavailable.**
- Detection: Tool dispatch for `mcp__plugin_playwright_playwright__*` fails
- Behavior: Skip all dynamic checks. Emit INFO: "Dynamic accessibility checks skipped: Playwright MCP not available." Static checks (C.1) still run.
- Consistent with existing MCP degradation pattern.

**Failure mode 2: Page fails to load in browser.**
- Detection: `browser_navigate` returns error or timeout
- Behavior: Skip dynamic checks for that page. Emit INFO with the URL and error.

**Failure mode 3: Tab key does not advance focus (page has no focusable elements).**
- Detection: `document.activeElement` stays on `body` after 3 Tab presses
- Behavior: Emit `A11Y-KEYBOARD` WARNING: "No focusable elements found — page may lack interactive content or all elements use tabindex='-1'."

**Failure mode 4: Cross-browser Playwright engine not available.**
- Detection: Firefox or WebKit launch fails (Playwright engines not installed)
- Behavior: Skip that browser. Emit INFO: "Cross-browser check skipped for {browser}: engine not installed. Run `npx playwright install {browser}` to enable."

**Failure mode 5: Pixel diff is mostly caused by font rendering differences.**
- Mitigation: The diff algorithm ignores anti-aliasing differences (1-pixel edge variations). Only structural layout differences are counted.

## Performance Characteristics

**Dynamic a11y checks:**

| Check | Time per Page | Notes |
|---|---|---|
| Tab order (50 elements) | 5-15s | Depends on page complexity |
| Focus visibility | 3-10s | Screenshot + compare per element (batched) |
| Keyboard interaction | 5-20s | Per interactive pattern |
| ARIA validation | 1-3s | DOM queries only |
| **Total per page** | **14-48s** | |

**Cross-browser testing:**

| Step | Time per Page | Notes |
|---|---|---|
| Firefox screenshot | 5-10s | Playwright engine switch |
| WebKit screenshot | 5-10s | Playwright engine switch |
| Pixel diff computation | 1-3s | Image comparison |
| **Total per page (3 browsers)** | **11-23s** | On top of existing Chromium check |

**For a typical 3-page check:** Dynamic a11y adds 42-144s. Cross-browser adds 33-69s. Total additional time: 75-213s (1-3.5 minutes). This is why cross-browser is opt-in.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Category registration:** `category-registry.json` contains `A11Y-KEYBOARD`, `A11Y-FOCUS`, `A11Y-ARIA`, `FE-BROWSER-COMPAT`
2. **Config template:** All frontend framework config templates include `accessibility:` section
3. **Agent update:** `fg-413-frontend-reviewer.md` contains Part C.2, Part C.3, Part E sections

### Unit Tests (`tests/unit/`)

1. **`dynamic-a11y.bats`:**
   - Tab order: logical order validated, skip detected
   - Focus visibility: missing outline detected
   - ARIA: missing aria-expanded on dropdown detected
   - Playwright MCP unavailable: graceful skip with INFO
   - Config disabled: `accessibility.dynamic_checks: false` skips Part C.2

2. **`cross-browser-visual.bats`:**
   - Pixel diff below threshold: no finding
   - Pixel diff above warning threshold: WARNING emitted
   - Pixel diff above critical threshold: CRITICAL emitted
   - Missing browser engine: graceful skip with INFO
   - Config disabled: `visual_verification.cross_browser: false` skips Part E

## Acceptance Criteria

1. Tab order verification detects out-of-order focus sequences
2. Focus visibility audit detects elements with `outline: none` and no replacement
3. Keyboard navigation tests verify dropdown, modal, and tooltip interaction patterns
4. ARIA validation detects missing required attributes per component pattern
5. All dynamic checks gracefully skip when Playwright MCP is unavailable
6. Cross-browser testing compares Chromium vs Firefox vs WebKit screenshots
7. Pixel diff thresholds are configurable and produce appropriate severity levels
8. Dynamic checks run in `full` and `a11y-only` modes, not in `conventions-only` or `performance-only`
9. Cross-browser is opt-in with `visual_verification.cross_browser: false` default
10. Tab order respects `tab_order_max_elements` cap to prevent runaway traversal

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** Dynamic checks enhance existing Part C. Static checks unchanged.
2. **Frontend reviewer update:** New sections C.2, C.3, E added. Existing sections A, B, C.1, D untouched.
3. **Config:** `accessibility.dynamic_checks: true` by default (low risk — skips if no Playwright). `visual_verification.cross_browser: false` by default (opt-in).
4. **Category registry:** Four new finding codes. Existing codes unchanged.
5. **No new dependencies:** All dynamic functionality uses already-supported Playwright MCP tools.

## Dependencies

**This feature depends on:**
- Playwright MCP (`mcp__plugin_playwright_playwright__*` tools) for dynamic checks (graceful degradation when absent)
- `fg-413-frontend-reviewer` existing Part C accessibility checks
- `shared/visual-verification.md` for screenshot comparison patterns

**Other features that benefit from this:**
- Visual verification (existing): cross-browser extends existing screenshot-based checking
- Frontend design theory: keyboard navigation testing validates implementation of design system interaction patterns
