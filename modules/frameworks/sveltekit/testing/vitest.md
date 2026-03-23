# SvelteKit + Vitest Testing Patterns

> SvelteKit-specific testing patterns for Vitest. Extends `modules/testing/vitest.md`.

## Component Testing

- Use `@testing-library/svelte` for component rendering and interaction
- Prefer queries: `getByRole` > `getByLabelText` > `getByText` > `getByTestId`
- Test Svelte 5 rune-based components by interacting with rendered output

```typescript
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import MyComponent from './MyComponent.svelte';

test('handles user interaction', async () => {
  render(MyComponent, { props: { items: mockItems } });
  const button = screen.getByRole('button', { name: /submit/i });
  await userEvent.click(button);
  expect(screen.getByText('Success')).toBeInTheDocument();
});
```

## Load Function Testing

- Import load functions directly and call with mocked event objects
- Mock `fetch`, `params`, `locals` as needed
- Assert return shape matches expected data

```typescript
import { load } from './+page.server';

test('load returns user data', async () => {
  const result = await load({ params: { id: '123' }, locals: { user: mockUser } });
  expect(result.user).toBeDefined();
});
```

## Form Action Testing

- Test actions by providing mocked `request` with `FormData`
- Assert `fail()` returns for validation errors
- Assert redirect for successful mutations

## Accessibility Testing

- Use `@testing-library/svelte` with `getByRole`, `getByLabelText` queries
- Run axe-core in tests: `@axe-core/playwright` for E2E
- Test keyboard navigation for critical flows
