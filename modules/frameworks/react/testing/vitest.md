# React + Vitest Testing Conventions

## Test Structure

- Co-locate tests: `Component.test.tsx` next to `Component.tsx`
- Integration tests: `__tests__/` directory at feature boundary
- Use `describe` blocks matching component/hook name
- Name tests by behavior: `it('shows error when email is invalid')`

## Component Testing

- Render via `render()` from `@testing-library/react`
- Query by role, label, text — NEVER by test-id unless no semantic alternative
- Use `userEvent` (not `fireEvent`) for user interactions
- Wrap state updates in `act()` only when not using RTL's built-in waiting
- Prefer `screen` import for all queries

## Hook Testing

- Use `renderHook()` from `@testing-library/react`
- Test hooks in isolation first, then integration with components
- For hooks with effects: use `waitFor` to assert async state

## Async Testing

- `await screen.findByText()` for async content (NOT `waitFor` + `getBy`)
- `waitFor` only for assertions on changing state
- Mock timers with `vi.useFakeTimers()` for debounce/throttle

## Mocking

- MSW (Mock Service Worker) for API mocking — intercept at network level
- `vi.mock()` for module mocking — use sparingly, prefer dependency injection
- Never mock React internals (useState, useEffect)
- Mock child components only when they have complex side effects

## Error Boundaries

- Test error boundaries at route level
- Use `vi.spyOn(console, 'error')` to suppress expected React warnings
- Verify fallback UI renders on error

## Dos

- Test user behavior, not implementation details
- One assertion per behavior (group related assertions)
- Use `screen` import for all queries
- Test loading states explicitly
- Test keyboard navigation for interactive components
- Clean up side effects in `afterEach`

## Don'ts

- Don't test styled-components/CSS classes
- Don't snapshot-test complex components (brittle)
- Don't mock child components by default (test integration)
- Don't use `container.querySelector` (breaks accessibility contract)
- Don't test library behavior (e.g., Router navigation internals)
- Don't test implementation details (internal state, method calls)
