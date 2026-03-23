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

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Smart Test Rules

- No duplicate tests -- grep existing tests before generating
- Test behavior, not implementation
- Skip framework guarantees (don't test React renders, useState)
- One assertion focus per it() -- multiple asserts OK if same behavior

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
