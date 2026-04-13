# Svelte + Vitest Testing Conventions

## Test Structure

- Co-locate tests: `Component.test.ts` next to `Component.svelte`
- Use `describe` matching component name

## Component Testing

- Render via `render()` from `@testing-library/svelte`
- Query with `screen.getByRole()`, `screen.getByText()` — same as React Testing Library
- Use `userEvent` from `@testing-library/user-event` for interactions
- Await `tick()` from `svelte` for reactive updates

## Svelte 5 Runes Testing

- Test `$state` runes through component rendering
- `$derived` values: change source, assert derived output renders
- `$effect` side effects: use `flushSync()` to force synchronous updates

## Store Testing

- Svelte stores: `get(store)` for current value
- Writable stores: `store.set(newValue)`, then assert component updated
- Derived stores: test through source store changes

## Mocking

- Mock modules: `vi.mock('$app/stores')` for SvelteKit stores
- Mock context: provide via wrapper component or `setContext` in test

## Dos

- Test component behavior through rendered output
- Test event dispatching: `component.$on('event', handler)`
- Test transitions via `vi.useFakeTimers()` + fast-forward
- Test accessibility with `@testing-library/jest-dom` matchers
- Clean up with `cleanup()` in `afterEach`

## Don'ts

- Don't test Svelte compiler output
- Don't access component internals (`$$`)
- Don't test CSS scoping
- Don't mock Svelte runtime functions
- Don't use `innerHTML` for assertions (fragile)
