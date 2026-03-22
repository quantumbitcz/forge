# React-Vite Agent Conventions Reference

> Framework conventions for React + Vite + TypeScript + shadcn/ui projects. This is a curated subset for agent consumption. Customize per-project via `.claude/dev-pipeline.local.md`.

## Typography (inline style, NOT Tailwind classes)

Use `style={{ fontSize }}` with this scale:

| Purpose            | Size          | Weight  |
| ------------------ | ------------- | ------- |
| Page heading       | `1.1rem`      | 600     |
| Section heading    | `0.95rem`     | 600     |
| Card title / label | `0.8rem`      | 500-600 |
| Body text          | `0.78-0.8rem` | 400-500 |
| Caption / meta     | `0.7rem`      | 400-500 |
| Micro label        | `0.6-0.65rem` | 500-600 |
| Tiny annotation    | `0.55rem`     | 400     |

## Colors (theme tokens, NEVER hardcoded)

Use CSS custom properties from `theme.css` — never hardcode (`bg-white`, `#ffffff`).
Use `bg-background`, `bg-card`, `text-foreground`, `border-border`.

| Meaning            | Color                     | Usage                                    |
| ------------------ | ------------------------- | ---------------------------------------- |
| Success / on track | `emerald-500/600`         | Compliance >= 75%, active, completed     |
| Warning / moderate | `amber-500/600`           | Compliance 50-74%, approaching threshold |
| Danger / at risk   | `destructive` / `red-500` | Compliance < 50%, inactive, overdue      |
| Primary action     | `primary`                 | CTAs, active states, brand accents       |
| Neutral / disabled | `muted-foreground`        | Secondary text, disabled controls        |

Exception: status colors (`emerald-500`, `amber-500`, `red-500`) are fine as-is.

## Styling

- Surface hierarchy: `bg-card` for cards, `bg-muted/30` for section containers, `bg-muted/20` for nested content.
- Border subtlety: `border-border/50` for sections, `border-border/30` for inner dividers.
- Spacing: `gap-2` (tight), `gap-3` (related), `gap-5` (distinct), `gap-6` (top-level).
- Corners: `rounded-lg` cards, `rounded-xl` containers, `rounded-full` avatars/pills.
- Shadows: subtle (`shadow-sm`/`shadow-md`). In dark mode prefer borders over shadows.
- Dark mode via `.dark` class on root. Always verify new UI in both themes.

## Code Quality

- Functions: max ~30 lines, max 3 nesting levels, max 4 params
- Files: max ~400 lines — extract sub-components beyond that
- Cyclomatic complexity: max 10 per function
- TSDoc on all exported functions, types, components (what + why, not how)

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Smart Test Rules

- No duplicate tests — grep existing tests before generating
- Test behavior, not implementation
- Skip unreachable branches
- Skip framework guarantees (don't test React renders, useState)
- One assertion focus per it() — multiple asserts OK if same behavior
- Coverage != quality — fewer meaningful tests > high trivial coverage

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Import Order

1. React/framework
2. Third-party
3. `@/app/components/shared` (barrel import)
4. Feature-local

## Empty States

Every data-dependent section must handle zero-state with `EmptyChartState` or appropriate fallback.
Never show broken charts, NaN, or blank space.

```tsx
<EmptyChartState
  icon={Dumbbell}
  message="No workout data yet"
  sub="Create and assign a plan to see analytics"
/>
```

## Accessibility

- All interactive elements keyboard-accessible
- Icon-only buttons: `title` or `aria-label` required
- Color must not be only status indicator — pair with icons
- Focus rings visible on keyboard navigation

## Charts (recharts)

- Every tooltip uses `CHART_TOOLTIP_STYLE` from shared primitives
- Wrap in `<ResponsiveContainer width="100%" height="100%">` inside a fixed-height parent
- Standard heights: `h-52` (most), `h-56` (radar/complex), `h-36` (compact pie)
- Grid: `CartesianGrid strokeDasharray="3 3" stroke="var(--border)"`
- Axis ticks: `fontSize: 11, fill: "var(--muted-foreground)"`
- Color-code semantically (emerald positive, amber warning, red negative)

## Immutability

- Never mutate state directly — always spread or clone
- Use helper functions (`cloneSession`, `cloneBlock`, `cloneWeekPlans`) for deep structures

## Shared Primitives

- All cross-feature UI atoms live in `shared/` and are barrel-exported from `shared/index.ts`
- Derived client metrics computed in `shared/client-utils.ts` — never re-implement inline
- When the same JSX appears in two features, extract to `shared/`

## Component Composition

Prefer composable atoms (children-based) over monolithic config-object components.
Follows the Radix/shadcn pattern.

## Suggested Project Commands

These are project-specific commands that should live in the consuming project's `.claude/commands/` directory, not in the pipeline plugin. Create them during `/pipeline-init` or manually:

### `/fe-check-theme` — Theme token compliance scan

Scans `.tsx` files for hardcoded colors (`bg-white`, `text-gray-*`, hex values) and Tailwind font-size classes (`text-sm`, `text-lg`). Reports violations with line numbers and fix suggestions (e.g., `bg-white` → `bg-background`). Quick lint — no model invocation needed.

### `/fe-design-review` — Full design system review

Comprehensive UI/UX review against the project's design system: typography scale, color tokens, spacing/gap scale, dark mode, responsive layout, empty states, accessibility, chart styling, interaction feedback. Returns findings with severity.

### `/fe-dark-mode-check` — Light/dark mode verification

Uses Playwright MCP to screenshot a page in both light and dark mode. Checks for: text readability, invisible elements (white on white), missing dark mode CSS variable fallbacks, shadow-only borders. Requires dev server running.

### `/fe-react-doctor` — React codebase analysis

Runs `npx -y react-doctor@latest .` to detect React anti-patterns: component complexity, hook misuse, performance issues, missing memoization. Prioritizes fixes by severity and applies project conventions (400-line file limit, entity ID keys, spread-based state updates).
