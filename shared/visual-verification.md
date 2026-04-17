# Visual Verification

Screenshot-based UI verification for frontend changes. Uses Playwright MCP to capture and compare page screenshots at standard breakpoints during VERIFY and REVIEW stages.

## Prerequisites

All four conditions must be met for visual verification to activate:

| # | Condition | Check |
|---|-----------|-------|
| 1 | Playwright MCP available | `state.integrations.playwright.available == true` |
| 2 | Frontend files in changeset | At least one file matching `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.html`, `*.css`, `*.scss` |
| 3 | Enabled in config | `visual_verification.enabled != false` |
| 4 | Dev server URL configured | `visual_verification.dev_server_url` is set and non-empty |

If any condition is unmet, visual verification is silently skipped (see Graceful Degradation).

## Screenshot Strategy

### Breakpoints

| Name | Width (px) | Rationale |
|------|-----------|-----------|
| mobile | 375 | iPhone SE / small Android — most constrained viewport |
| tablet | 768 | iPad portrait — common tablet breakpoint |
| desktop | 1440 | Standard laptop/desktop — primary development target |

Screenshots are captured at each breakpoint for every detected page.

### Page Detection

Resolution order (first match wins):

1. **Config-defined** — explicit `visual_verification.pages` list in `forge-config.md`
2. **Auto-detect** — scan route definitions (Next.js `app/`, SvelteKit `routes/`, Vue Router, Angular routes) for top-level pages
3. **Fallback** — capture root URL (`/`) only

### Capture Process

1. Start dev server at `visual_verification.dev_server_url` (or confirm already running)
2. For each page + breakpoint combination:
   a. Navigate to page URL
   b. Wait for network idle (max 10s)
   c. Capture full-page screenshot
   d. Store in `.forge/screenshots/{page}-{breakpoint}.png`
3. Screenshots are ephemeral — deleted on `/forge-recover reset`

## Verification Modes

### fg-413 (Frontend Reviewer) — Code + Visual Review

During REVIEW stage, fg-413 receives screenshots alongside code diffs. The reviewer:
- Examines each breakpoint screenshot for layout issues, overflow, misalignment
- Cross-references visual output against design tokens and conventions
- Reports findings using FE-VISUAL-* categories

### fg-320 (Frontend Polisher) — Before/After Comparison

During IMPLEMENT stage, fg-320 captures screenshots before applying changes and after. The polisher:
- Compares before/after pairs at each breakpoint
- Identifies unintended visual regressions
- Validates responsive behavior across breakpoints
- Reports findings using FE-VISUAL-* categories

## Finding Categories

| Category | Severity | Description |
|----------|----------|-------------|
| `FE-VISUAL-REGRESSION` | WARNING | Unintended visual change detected in before/after comparison |
| `FE-VISUAL-RESPONSIVE` | WARNING | Layout breaks or degrades at one or more breakpoints |
| `FE-VISUAL-CONTRAST` | WARNING | Text or interactive elements fail contrast ratio thresholds |
| `FE-VISUAL-FIDELITY` | INFO | Minor visual discrepancy from design intent (spacing, alignment) |

All categories follow the shared scoring formula: WARNING = -5, INFO = -2.

## Graceful Degradation

| Failure | Behavior | Finding |
|---------|----------|---------|
| Playwright MCP unavailable | Silent skip — no visual verification attempted | None |
| Dev server not running / unreachable | Skip with informational note in stage notes | INFO |
| Individual screenshot capture fails | Skip that screenshot, continue remaining | INFO |
| All screenshots fail for a page | Log warning, continue with other pages | WARNING |

Visual verification never blocks the pipeline. All failures degrade gracefully to ensure the pipeline completes.

## Configuration

In `forge-config.md`:

    visual_verification:
      enabled: true
      dev_server_url: "http://localhost:3000"
      breakpoints:
        - { name: "mobile", width: 375 }
        - { name: "tablet", width: 768 }
        - { name: "desktop", width: 1440 }
      pages:
        - "/"
        - "/dashboard"
        - "/settings"

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable/disable visual verification |
| `dev_server_url` | string | — | Base URL of the development server (required) |
| `breakpoints` | list | mobile/tablet/desktop | Viewport widths for screenshot capture |
| `pages` | list | auto-detect | Explicit page paths to capture; overrides auto-detection |
