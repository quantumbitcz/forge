# SvelteKit + Vitest Testing Conventions

## Test Structure

- Unit tests: `src/lib/**/*.test.ts` for library code
- Route tests: `src/routes/**/*.test.ts` alongside `+page.svelte`
- Server tests: `src/routes/**/*.server.test.ts` for server-only code

## Load Function Testing

- Import `load` function from `+page.ts` or `+page.server.ts`
- Create mock `RequestEvent` or `LoadEvent`:
  ```typescript
  const event = { params: { id: '1' }, fetch: vi.fn() } as unknown as LoadEvent;
  const result = await load(event);
  ```
- Assert returned data structure

## Server Route Testing

- Import handler from `+server.ts`
- Create mock `RequestEvent` with `Request` object
- Assert `Response` status and body

## Form Action Testing

- Import actions from `+page.server.ts`
- Create mock `RequestEvent` with `FormData`
- Assert redirect or returned data

## Component Testing

- Same as Svelte testing conventions (see `modules/frameworks/svelte/testing/vitest.md`)
- Additional: test layout components with slot content
- Test error pages (`+error.svelte`) with mock `$page.error`

## Mocking

- Mock `$app/stores`: `vi.mock('$app/stores', () => ({ page: writable({...}) }))`
- Mock `$app/navigation`: `vi.mock('$app/navigation', () => ({ goto: vi.fn() }))`
- Mock `$env`: `vi.mock('$env/static/private', () => ({ API_KEY: 'test' }))`

## Dos

- Test load functions independently from components
- Test server-only code without browser APIs
- Test form validation in actions
- Use `vitest-fetch-mock` or MSW for API mocking in load functions
- Test error handling in load functions (throw `error()`)

## Don'ts

- Don't import server code in client test files
- Don't test SvelteKit routing internals
- Don't mock `fetch` globally (use per-test mocking)
- Don't test prerendered pages at runtime
- Don't rely on `$app/environment` values in tests
