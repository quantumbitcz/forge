# React Framework Conventions

> Framework-specific conventions for React projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (Component-Based)

| Layer | Responsibility | Location |
|-------|---------------|----------|
| Page | Route-level UI, data loading | `src/routes/` or `src/pages/` |
| Feature component | Feature-specific UI + state | `src/app/components/{feature}/` |
| Shared component | Reusable UI atoms/molecules | `src/app/components/shared/` |
| Hook | Encapsulated stateful logic | Co-located with feature or `shared/` |
| API module | HTTP client wrappers | `src/app/api/` |
| Type definitions | Shared types/interfaces | `src/app/types/` or co-located |

**Dependency rule:** Shared components never import from feature components. Features import from shared via barrel exports.

## Component Patterns

- Prefer composable atoms (children-based) over monolithic config-object components
- Follows the Radix/shadcn composition pattern
- Keep component files under 200 lines -- extract sub-components when they have independent state or logic (hard limit 400 lines enforced by check engine)
- Functions max ~30 lines, max 3 nesting levels, max 4 params

## Hooks and State Management

### When to Use What
- **Component state** (`useState`): form inputs, UI toggles, ephemeral state
- **URL state** (search params, route params): filter criteria, pagination, shareable state
- **Server state** (TanStack Query / SWR): API data with caching, refetching, optimistic updates
- **Global client state** (Context / Zustand / Jotai): auth, theme, feature flags -- keep minimal

### Anti-Patterns
- Don't duplicate server data in global state -- let the data fetching library manage the cache
- Don't use Context for frequently changing values (causes full subtree re-renders)
- Don't use `useEffect` for derived state -- use `useMemo` or compute inline
- Don't store server data in `useState` -- use a data fetching library

## Typography (inline style, NOT Tailwind classes)

Use `style={{ fontSize }}` with project type scale. Never use Tailwind `text-sm`, `text-lg` etc.

## Colors (theme tokens, NEVER hardcoded)

Use CSS custom properties from `theme.css` -- never hardcode (`bg-white`, `#ffffff`).
Use `bg-background`, `bg-card`, `text-foreground`, `border-border`.

## Styling

- Surface hierarchy: `bg-card` for cards, `bg-muted/30` for sections, `bg-muted/20` for nested
- Border subtlety: `border-border/50` sections, `border-border/30` inner dividers
- Dark mode via `.dark` class on root -- always verify in both themes
- Shadows: subtle (`shadow-sm`/`shadow-md`). In dark mode prefer borders over shadows

## Import Order

1. React/framework
2. Third-party
3. `@/app/components/shared` (barrel import)
4. Feature-local

## Empty States

Every data-dependent section must handle zero-state with `EmptyChartState` or appropriate fallback. Never show broken charts, NaN, or blank space.

## Charts (recharts)

- Every tooltip uses `CHART_TOOLTIP_STYLE` from shared primitives
- Wrap in `<ResponsiveContainer>` inside a fixed-height parent
- Standard heights: `h-52` (most), `h-56` (radar/complex), `h-36` (compact pie)
- Color-code semantically (emerald positive, amber warning, red negative)

## Immutability

Never mutate state directly -- always spread or clone. Use helper functions for deep structures.

## Error Handling

### Error Boundaries
- Wrap each route in an `ErrorBoundary` with user-friendly fallback + retry button
- Log errors to monitoring service from `componentDidCatch`
- Error boundaries do NOT catch: event handlers, async code, SSR

### Async Error Handling
- All `fetch` calls must handle network errors (catch) and HTTP errors (status check)
- Implement retry logic for transient failures (exponential backoff, max 3)
- Cancel pending requests on unmount with AbortController

## API Integration

- Use a fetch wrapper standardizing: base URL, auth headers, error parsing
- Implement request deduplication -- identical concurrent requests share one call
- Handle loading, error, and empty states for every API-consuming component
- Debounce search-as-you-type (300ms min), UI inputs (150ms min)

## Accessibility

- All interactive elements keyboard-accessible
- Icon-only buttons: `title` or `aria-label` required
- Color must not be only status indicator -- pair with icons
- Focus rings visible on keyboard navigation

## Animation & Motion

Reference `shared/frontend-design-theory.md` for design theory guardrails (Gestalt, hierarchy, color, spacing, motion principles).

### Library Preference
- **Simple transitions** (hover, reveal, toggle): CSS transitions with `transition-property: transform, opacity`
- **Component transitions** (mount/unmount, layout shifts): Framer Motion (`motion/react`) -- `animate`, `exit`, `layout` props
- **Complex sequences** (scroll-driven, orchestrated page loads): GSAP with `useGSAP` hook for timeline choreography
- **CSS-only** when no React dependency needed (loading spinners, skeleton pulses)

### Timing Standards
- Instant feedback (button press, toggle): < 100ms
- Micro-interaction (hover state, tooltip): 150-200ms
- UI transition (panel open, element reveal): 200-350ms
- Page transition (route change, staggered load): 300-500ms total sequence
- Stagger between group elements: 50-80ms offset

### Easing
- Prefer spring physics (Framer Motion `type: "spring"`) over cubic-bezier for natural feel
- Standard spring: `{ stiffness: 300, damping: 30, mass: 1 }`
- Gentle spring: `{ stiffness: 200, damping: 25, mass: 1.2 }`
- Never use `linear` easing for UI motion -- it feels mechanical

### Performance Rules
- Only animate `transform` and `opacity` -- GPU-composited, no layout recalc
- Use `will-change` sparingly -- only on elements about to animate, remove after
- Target 60fps -- if animation jank occurs, simplify or remove
- Intersection Observer for scroll-triggered effects, NOT scroll event listeners
- Test on low-end devices

### Accessibility
- REQUIRED: All animations must respect `prefers-reduced-motion`
- Framer Motion: use `useReducedMotion()` hook to conditionally skip animations
- Never use animation as the ONLY indicator of state change
- Provide `@media (prefers-reduced-motion: reduce)` fallback in CSS

### Anti-AI-Look Standards
- ONE well-orchestrated animation moment per page (staggered reveal on load) beats scattered effects
- Every animation must have purpose: guide attention, confirm action, show relationship, or create continuity
- No bouncing logos, spinning icons, or decorative motion without functional intent

## Multi-Viewport Design

### Breakpoints
- Mobile: 375px (iPhone SE baseline)
- Tablet: 768px
- Desktop: 1280px
- Wide: 1536px+ (optional)

### Mobile Requirements (375px)
- Touch targets: minimum 44x44px (padding counts)
- Single-column reflow -- no horizontal scrolling
- Bottom navigation for primary actions (thumb-zone friendly)
- Font size: minimum 16px body text (prevents iOS zoom on focus)
- Full-width inputs and buttons

### Tablet Requirements (768px)
- NOT just scaled-up mobile -- adapt layout (sidebar + content, split views)
- Touch AND hover support
- Cards can go 2-column, complex forms side-by-side

### Desktop Requirements (1280px+)
- Hover states on all interactive elements
- Generous whitespace
- Sidebar navigation, multi-column layouts, data tables with full columns

### Cross-Viewport Consistency
- Same information hierarchy across all viewports
- Consistent spacing rhythm (8pt grid at all sizes)
- Images: use `<picture>` with `srcset` or responsive image component

## Security

- Sanitize all content before rendering as raw HTML
- Validate all user input before submission
- Use CSP headers, avoid inline scripts
- Never store sensitive data in localStorage

## Performance

### Rendering
- Profile with React DevTools before optimizing
- Virtualize long lists (>100 items) with react-window or @tanstack/react-virtual
- `React.lazy()` + `Suspense` for route-level code splitting

### Bundle
- Target <200KB initial JS
- Tree-shake: use named imports, avoid importing entire libraries
- Prefer Tailwind over runtime CSS-in-JS for bundle size

## Testing

### Test Framework
- **Vitest** as the test runner with **Testing Library** (`@testing-library/react`) for component tests
- `jsdom` or `happy-dom` as the test environment
- **MSW** (Mock Service Worker) for API mocking — intercept at the network level, not in components

### Integration Test Patterns
- Render the full component tree for feature tests — avoid shallow rendering
- Use `renderWithProviders()` helper that wraps components with required context (router, query client, theme)
- Mock API calls at the MSW handler level — components use real hooks and fetching logic
- Test user flows end-to-end within a page: fill form, submit, verify success/error UI

### What to Test
- User-visible behavior: what the user sees and can interact with
- Conditional rendering based on data states (loading, error, empty, populated)
- Form validation and submission flows
- Error boundaries: verify fallback UI appears on component error
- Accessibility: keyboard navigation, ARIA attributes on interactive elements

### What NOT to Test
- React internals (that `useState` updates, that `useEffect` fires)
- Component re-render counts or internal state values
- Third-party library behavior (e.g., that TanStack Query caches)
- CSS classes or styling details — test visible outcomes instead

### Example Test Structure
```
src/app/components/{feature}/
  FeatureComponent.tsx
  FeatureComponent.test.tsx     # co-located test
src/test/
  setup.ts                      # vitest setup, MSW server init
  handlers/                     # MSW request handlers
  utils/renderWithProviders.tsx  # shared render helper
```

For general Vitest patterns, see `modules/testing/vitest.md`.

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Smart Test Rules

- No duplicate tests -- grep existing tests before generating
- Test behavior, not implementation
- Skip framework guarantees (don't test React renders, useState)
- One assertion focus per it() -- multiple asserts OK if same behavior

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated components, changing hook contracts, restructuring state management.

## Dos and Don'ts

### Do
- Use Error Boundaries around route-level components and lazy-loaded chunks
- Wrap async data fetching in dedicated hooks -- never call `fetch` directly in components
- Memoize expensive computations with `useMemo` only when measurably slow (profile first)
- Use `useCallback` for callbacks passed to memoized children
- Use AbortController to cancel in-flight requests on unmount
- Test user-visible behavior with Testing Library -- `getByRole`, `getByText`

### Don't
- Don't suppress ESLint exhaustive-deps warnings -- fix the dependency array
- Don't use `index` as key in lists that can reorder, filter, or insert
- Don't create new objects/arrays in render without memoization if passed as props to memoized children
- Don't test implementation details (state values, internal method calls)
- Don't mock everything -- prefer integration tests that render real child components
