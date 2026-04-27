# Vitest Testing Conventions

> Support tier: contract-verified

## Test Structure

Use `describe` for grouping, `it` (or `test`) for individual cases. Mirror the source file structure — one test file per module. Co-locate unit tests next to source files (`*.test.ts`); place integration tests in `tests/`.

```typescript
describe('UserStore', () => {
  describe('when authenticated', () => {
    it('returns the current user profile', async () => { ... })
  })
  describe('when unauthenticated', () => {
    it('returns null', () => { ... })
  })
})
```

## Naming

- `describe`: names the subject or scenario context
- `it`/`test`: completes the sentence "it {expected behaviour}"
- Use plain English — avoid abbreviations or implementation names

## Assertions / Matchers

```typescript
expect(value).toBe(primitive)          // strict equality (===)
expect(obj).toEqual({ a: 1 })          // deep equality
expect(arr).toContain(item)
expect(arr).toHaveLength(3)
expect(fn).toThrow('message')
expect(fn).toThrow(CustomError)
expect(mock).toHaveBeenCalledWith(arg)
expect(mock).toHaveBeenCalledTimes(1)
```

Use `.toStrictEqual()` when `undefined` properties matter.

## Lifecycle

```typescript
beforeAll(async () => { /* once per describe block */ })
afterAll(async () => { })
beforeEach(() => { /* reset state before each it() */ })
afterEach(() => { vi.clearAllMocks() })
```

Call `vi.clearAllMocks()` in `afterEach` rather than `vi.resetAllMocks()` unless implementation counts matter.

## Mocking

```typescript
// Function mock
const fn = vi.fn().mockReturnValue(42)
const asyncFn = vi.fn().mockResolvedValue(data)

// Spy on existing method
const spy = vi.spyOn(service, 'send').mockImplementation(() => {})

// Module mock (hoisted automatically)
vi.mock('./api', () => ({ fetchUser: vi.fn().mockResolvedValue(user) }))
```

Use `vi.importActual()` inside `vi.mock()` to partially mock a module.

## Snapshot Testing

Use snapshots for stable, serializable output (API response shapes, rendered markdown).
Do NOT use snapshots for large component trees — they become unreadable diffs and break on unrelated style changes. Prefer explicit `toEqual` assertions for component output.

```typescript
expect(serializedConfig).toMatchSnapshot()    // ok for small stable output
expect(rendered).toMatchSnapshot()             // avoid for full component HTML
```

## Data-Driven Testing

```typescript
it.each([
  [1, 'one'],
  [2, 'two'],
  [3, 'three'],
])('maps %i to %s', (num, word) => {
  expect(numberToWord(num)).toBe(word)
})
```

## Async Testing

Always `await` inside `async` test functions. Never use `.then()` inside a test body without `return`.

```typescript
it('resolves with user data', async () => {
  const user = await fetchUser('123')
  expect(user.name).toBe('Alice')
})
```

For timers: `vi.useFakeTimers()` in `beforeEach`, `vi.runAllTimers()` to advance, restore in `afterEach`.

## What NOT to Test

- Third-party library internals (axios, lodash, date-fns)
- CSS class presence as a proxy for business logic
- Implementation details — test what the component renders/returns, not how
- Private/unexported functions — access through the public API

## Anti-Patterns

- `await new Promise(r => setTimeout(r, 100))` — use fake timers or `waitFor`
- Deep nesting beyond 3 levels of `describe`
- Tests that depend on execution order
- Clearing mocks manually per call instead of in `afterEach`
- Using `expect.assertions(n)` as a workaround for flaky async without fixing the root cause
