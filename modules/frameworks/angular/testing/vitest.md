# Angular + Vitest Testing Patterns

> Angular-specific testing patterns for Vitest (via Analog / analog-vitest). Extends `modules/testing/vitest.md`.

## Setup

Use `@analogjs/vitest-angular` or the native Angular test utilities with Vitest:

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import angular from '@analogjs/vite-plugin-angular';

export default defineConfig({
  plugins: [angular()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['src/testing/setup.ts'],
  },
});
```

```typescript
// src/testing/setup.ts
import '@testing-library/jest-dom';
import { TestBed } from '@angular/core/testing';
import { BrowserDynamicTestingModule, platformBrowserDynamicTesting } from '@angular/platform-browser-dynamic/testing';

TestBed.initTestEnvironment(BrowserDynamicTestingModule, platformBrowserDynamicTesting());
```

## Angular Testing Library

Use `@testing-library/angular` for component tests — prefer role queries over TestBed direct DOM access:

```typescript
import { render, screen } from '@testing-library/angular';
import userEvent from '@testing-library/user-event';
import { UserCardComponent } from './user-card.component';

test('displays user name and triggers select', async () => {
  const user = userEvent.setup();
  const mockSelected = vi.fn();

  await render(UserCardComponent, {
    componentInputs: { user: { id: '1', name: 'Alice' } },
    on: { selected: mockSelected },
  });

  expect(screen.getByText('Alice')).toBeInTheDocument();
  await user.click(screen.getByRole('button', { name: /select/i }));
  expect(mockSelected).toHaveBeenCalledWith('1');
});
```

## Signal Testing

Signals are synchronous — read them directly without `async` or `fakeAsync`:

```typescript
import { TestBed } from '@angular/core/testing';
import { UserStore } from './user.store';
import { UserService } from './user.service';

test('loads users into store', async () => {
  const mockService = { getAll: vi.fn().mockReturnValue(of([{ id: '1', name: 'Alice' }])) };

  TestBed.configureTestingModule({
    providers: [
      UserStore,
      { provide: UserService, useValue: mockService },
    ],
  });

  const store = TestBed.inject(UserStore);
  store.loadUsers();
  TestBed.flushEffects();

  expect(store.users()).toHaveLength(1);
  expect(store.users()[0].name).toBe('Alice');
});
```

## HTTP Testing

```typescript
import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';

test('fetches user by id', () => {
  TestBed.configureTestingModule({
    providers: [UserService, provideHttpClient(), provideHttpClientTesting()],
  });

  const service = TestBed.inject(UserService);
  const httpMock = TestBed.inject(HttpTestingController);

  service.getById('1').subscribe(user => {
    expect(user.name).toBe('Alice');
  });

  const req = httpMock.expectOne('/api/users/1');
  expect(req.request.method).toBe('GET');
  req.flush({ id: '1', name: 'Alice' });
  httpMock.verify();
});
```

## Query Preferences

- `getByRole` > `getByLabelText` > `getByText` > `getByTestId`
- Never use `getByTestId` unless no semantic alternative exists
- Use `screen` object for all queries

## What to Test

- User interactions: click, type, submit — test what the user sees and does
- Conditional rendering based on signal state (loading, error, success, empty)
- Form validation: error messages appear for invalid input
- Route guards: authenticated vs unauthenticated returns

## What NOT to Test

- Angular change detection internals (that OnPush updates signals)
- Signal graph topology — test the output signals, not that `computed()` ran
- Third-party library internals (that `HttpClient` serializes JSON)
- Snapshot tests for large templates — they break on every whitespace change

## Async Patterns

- Use `findByRole` / `findByText` for elements that appear after async operations
- Use `waitFor` only when no `findBy*` query applies
- For `fakeAsync` zones: wrap with `TestBed.runInInjectionContext` when testing effects
