# Svelte 5 + Vitest Testing Patterns

> Svelte 5 standalone-specific testing patterns for Vitest. Extends `modules/testing/vitest.md`.

## Setup

```typescript
// vite.config.ts (or vitest.config.ts)
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  plugins: [svelte({ hot: !process.env.VITEST })],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./tests/setup.ts'],
  },
});
```

```typescript
// tests/setup.ts
import '@testing-library/jest-dom';
```

Required packages: `@testing-library/svelte`, `@testing-library/user-event`, `@testing-library/jest-dom`, `jsdom`.

## Component Testing

- Use `@testing-library/svelte` for component rendering and interaction
- Prefer queries: `getByRole` > `getByLabelText` > `getByText` > `getByTestId`
- Test Svelte 5 rune-based components by interacting with rendered output — not internal state
- Use `cleanup` after each test (Testing Library handles this automatically with `afterEach`)

```typescript
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import Button from './Button.svelte';

test('calls onclick prop when clicked', async () => {
  const user = userEvent.setup();
  const handleClick = vi.fn();
  render(Button, { props: { onclick: handleClick, label: 'Submit' } });

  await user.click(screen.getByRole('button', { name: /submit/i }));
  expect(handleClick).toHaveBeenCalledOnce();
});
```

## Testing Reactive State Changes

Test by triggering user interactions, not by directly mutating `$state` internals.

```typescript
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import Counter from './Counter.svelte';

test('increments count on button click', async () => {
  const user = userEvent.setup();
  render(Counter, { props: { initialCount: 0 } });

  await user.click(screen.getByRole('button', { name: /increment/i }));
  expect(screen.getByText('1')).toBeInTheDocument();
});
```

## Testing Snippet / Children Props

```typescript
import { render, screen } from '@testing-library/svelte';
import Card from './Card.svelte';

// For components accepting children snippets, use the slot-like approach:
test('renders children content', () => {
  render(Card, {
    props: {},
    // snippets are tested via wrapper components or raw HTML where testing-library/svelte supports it
  });
  // Verify the shell structure renders
  expect(screen.getByRole('article')).toBeInTheDocument();
});
```

## Store Testing (`.svelte.ts` files)

Test store behavior by importing the store module directly — no component needed.

```typescript
import { userStore } from '../stores/user.svelte.ts';

test('stores and clears user', () => {
  userStore.set({ id: '1', name: 'Alice' });
  expect(userStore.current?.name).toBe('Alice');

  userStore.clear();
  expect(userStore.current).toBeNull();
});
```

## Service Testing

Test service modules in isolation with mocked `fetch` via `vi.stubGlobal` or MSW.

```typescript
import { vi } from 'vitest';
import { fetchUser } from '../services/user.service.ts';

test('fetchUser returns parsed user', async () => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve({ id: '1', name: 'Alice' }),
  }));

  const user = await fetchUser('1');
  expect(user.name).toBe('Alice');

  vi.unstubAllGlobals();
});
```

## Mocking Service Modules

```typescript
import { vi } from 'vitest';

vi.mock('../services/user.service.ts', () => ({
  fetchUser: vi.fn().mockResolvedValue({ id: '1', name: 'Alice' }),
}));
```

## Accessibility Testing

- Use `getByRole`, `getByLabelText` queries for accessibility-first assertions
- Run `@axe-core/playwright` in Playwright E2E for WCAG compliance at the page level
- Test keyboard navigation for critical interactive flows (modals, dropdowns, forms)

## Dos

- Test the component's rendered output, not internal rune state
- Use `userEvent` over `fireEvent` for realistic DOM interactions (fires all associated events)
- Co-locate component tests with the component file (`Button.test.ts` next to `Button.svelte`)
- Mock services, not fetch — inject behavior at the module boundary

## Don'ts

- Don't assert on `$state` values directly — test rendered output instead
- Don't import Svelte stores and mutate them between tests without cleanup — use factory functions
- Don't skip `await` on user interactions — `userEvent` returns promises
- Don't test that Svelte renders components — test that your component logic renders the right output
