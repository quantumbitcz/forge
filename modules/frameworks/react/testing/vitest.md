# React + Vitest Testing Patterns

> React-specific testing patterns for Vitest. Extends `modules/testing/vitest.md`.

## Testing Library Setup

- Use `@testing-library/react` for component rendering
- Prefer queries: `getByRole` > `getByLabelText` > `getByText` > `getByTestId`
- Never use `getByTestId` unless no semantic alternative exists
- Use `screen` object for all queries -- not destructured from `render()`

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

test('submits form with valid data', async () => {
  const user = userEvent.setup();
  render(<LoginForm onSubmit={mockSubmit} />);

  await user.type(screen.getByLabelText('Email'), 'test@example.com');
  await user.click(screen.getByRole('button', { name: /submit/i }));

  expect(mockSubmit).toHaveBeenCalledWith({ email: 'test@example.com' });
});
```

## Network Mocking with MSW

- Mock at the network level with Mock Service Worker (MSW), not component-level mocks
- Define handlers in `src/tests/mocks/handlers.ts`
- Use `server.use()` for test-specific overrides

## What to Test

- User interactions: click, type, submit -- test what the user sees and does
- Conditional rendering: both branches (loading, error, success, empty)
- Form validation: messages appear for invalid input
- API integration: mock at network level (MSW)

## What NOT to Test

- Implementation details: internal state values, method calls
- Styling: don't assert CSS classes or inline styles
- Third-party libraries: don't test that React Router navigates correctly
- Snapshot tests for large components: they break on every change

## Async Patterns

- Use `findByRole` / `findByText` for elements that appear after async operations
- Use `waitFor` only when no `findBy*` query applies
- Use `waitForElementToBeRemoved` for loading states
