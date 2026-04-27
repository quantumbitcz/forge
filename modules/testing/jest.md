# Jest Testing Conventions

> Support tier: contract-verified

## Test Structure

Use `describe`/`it`/`expect`. Mirror the source directory tree — one `.test.ts` (or `.test.js`) per source file. Keep unit tests co-located; put integration and E2E tests under `tests/` or `__tests__/` at the project root.

```typescript
describe('CartService', () => {
  describe('addItem', () => {
    it('increases quantity when item already exists', () => { ... })
    it('appends a new line when item is not present', () => { ... })
  })
})
```

## Naming

- `describe`: subject + scenario context
- `it`/`test`: expected behaviour in plain English
- File: `{subject}.test.ts`

## Assertions / Matchers

```typescript
expect(value).toBe(42)               // strict ===
expect(obj).toEqual({ a: 1 })        // deep equality
expect(arr).toContain(item)
expect(fn).toThrow('message')
expect(mock).toHaveBeenCalledWith(a, b)
expect(mock).toHaveBeenCalledTimes(1)
expect(promise).resolves.toBe(value)
expect(promise).rejects.toThrow(Error)
```

## Lifecycle

```typescript
beforeAll(async () => { /* once per describe */ })
afterAll(async () => { })
beforeEach(() => { jest.clearAllMocks() })
afterEach(() => { })
```

Prefer `jest.clearAllMocks()` in `beforeEach` to guarantee clean state regardless of test order.

## Mocking

```typescript
// Function mock
const fn = jest.fn().mockReturnValue(42)
const asyncFn = jest.fn().mockResolvedValue(data)

// Spy
const spy = jest.spyOn(module, 'method').mockImplementation(() => result)

// Module mock — placed at top of file, hoisted by Babel/ts-jest
jest.mock('./api', () => ({ fetchUser: jest.fn() }))

// Restore originals
afterEach(() => jest.restoreAllMocks())
```

Manual mocks: place in `__mocks__/` adjacent to the module. Automatically used for `node_modules` when a `__mocks__` directory exists at the project root.

## Timer Mocking

```typescript
beforeEach(() => jest.useFakeTimers())
afterEach(() => jest.useRealTimers())

it('fires callback after delay', () => {
  const cb = jest.fn()
  setTimeout(cb, 1000)
  jest.advanceTimersByTime(1000)
  expect(cb).toHaveBeenCalledTimes(1)
})
```

Use `jest.runAllTimers()` only when the number of timers is bounded.

## Snapshot Testing

Snapshots are appropriate for small, stable serialized values (config objects, error messages, API shapes). Avoid for large React component trees — prefer explicit assertions or React Testing Library queries.

```typescript
expect(buildConfig(opts)).toMatchSnapshot()   // ok: small stable object
expect(container.innerHTML).toMatchSnapshot() // avoid: fragile, large
```

Update snapshots deliberately: `jest --updateSnapshot` should be a conscious act, not a fix-all.

## Data-Driven Testing

```typescript
it.each([
  [1,  'one'],
  [2,  'two'],
  [3, 'three'],
])('maps %i → %s', (num, word) => {
  expect(numWord(num)).toBe(word)
})
```

## Async Testing

```typescript
it('loads user', async () => {
  const user = await service.loadUser('id-1')
  expect(user.name).toBe('Alice')
})
```

Always `return` or `await` promises. A test that neither returns nor awaits a promise will pass even if the assertion is never reached.

## What NOT to Test

- Internal implementation details — test observable behaviour
- Third-party library behaviour you don't control
- CSS class names as a proxy for logic
- Auto-wired framework plumbing

## Anti-Patterns

- `done` callback style in new tests — use `async`/`await` instead
- `jest.mock()` calls inside `describe` or `it` blocks — they must be top-level
- Asserting on `console.log` output for business logic verification
- Tests that mutate module-level state without restoring it
- Blanket `jest.mock('../module')` without specifying what should be real vs mocked
