# Next.js + Vitest Testing Patterns

> Next.js-specific testing patterns for Vitest. Extends `modules/testing/vitest.md` and `modules/frameworks/react/testing/vitest.md`.

## Setup

Use Vitest with `@vitejs/plugin-react` and a Next.js-compatible config. Install `@testing-library/react`, `@testing-library/user-event`, and `msw`.

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    globals: true,
    alias: {
      '@': path.resolve(__dirname, './'),
    },
  },
})
```

Next.js server-only modules (`next/headers`, `next/navigation`) must be mocked for unit tests — they are not available in jsdom.

```ts
// tests/setup.ts
import { vi } from 'vitest'

vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), back: vi.fn() }),
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
  redirect: vi.fn(),
}))

vi.mock('next/headers', () => ({
  cookies: () => ({ get: vi.fn(), set: vi.fn() }),
  headers: () => new Headers(),
}))
```

## Client Component Testing

Client Components test exactly like standard React components with Testing Library.

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { SearchBar } from '@/app/components/SearchBar'

test('calls onChange when user types', async () => {
  const user = userEvent.setup()
  const onChange = vi.fn()
  render(<SearchBar onChange={onChange} />)

  await user.type(screen.getByRole('searchbox'), 'hello')
  expect(onChange).toHaveBeenCalledWith('hello')
})
```

## Server Component Testing

Server Components are async functions — call them directly and await the result.

```tsx
import { UserCard } from '@/app/components/UserCard'

// Mock data dependencies (db calls, fetch calls)
vi.mock('@/lib/db', () => ({
  getUserById: vi.fn().mockResolvedValue({ id: '1', name: 'Alice' }),
}))

test('renders user name', async () => {
  const jsx = await UserCard({ userId: '1' })
  render(jsx)
  expect(screen.getByText('Alice')).toBeInTheDocument()
})
```

- Mock all external dependencies (DB, `fetch`) — Server Components are pure functions given their inputs
- If the Server Component imports `cookies()` or `headers()`, ensure the `next/headers` mock is active

## Route Handler Testing

Use `NextRequest` directly — no need to spin up a server.

```ts
import { GET, POST } from '@/app/api/users/route'
import { NextRequest } from 'next/server'

test('GET /api/users returns list', async () => {
  const request = new NextRequest('http://localhost/api/users')
  const response = await GET(request)
  const data = await response.json()

  expect(response.status).toBe(200)
  expect(data.users).toBeInstanceOf(Array)
})

test('POST /api/users validates input', async () => {
  const request = new NextRequest('http://localhost/api/users', {
    method: 'POST',
    body: JSON.stringify({ name: '' }),  // invalid
    headers: { 'Content-Type': 'application/json' },
  })
  const response = await POST(request)
  expect(response.status).toBe(400)
})
```

## Server Action Testing

Server Actions are plain async functions — call them directly.

```ts
import { updateUser } from '@/actions/user'

test('returns error for empty name', async () => {
  const formData = new FormData()
  formData.set('name', '')

  const result = await updateUser(formData)
  expect(result.success).toBe(false)
})

test('calls db on valid input', async () => {
  const mockUpdate = vi.fn().mockResolvedValue({ id: '1', name: 'Alice' })
  vi.mocked(db.user.update).mockImplementation(mockUpdate)

  const formData = new FormData()
  formData.set('name', 'Alice')

  const result = await updateUser(formData)
  expect(result.success).toBe(true)
  expect(mockUpdate).toHaveBeenCalled()
})
```

## MSW for Client Component API Mocking

```ts
// tests/mocks/handlers.ts
import { http, HttpResponse } from 'msw'

export const handlers = [
  http.get('/api/users', () => {
    return HttpResponse.json({ users: [{ id: '1', name: 'Alice' }] })
  }),
]
```

Use `server.use()` for test-specific overrides. MSW intercepts `fetch()` at the network level, making tests resilient to implementation changes.

## What to Test

- Client Component interactions (click, type, submit)
- Conditional rendering: loading, error, empty, success states
- Server Action validation logic (no DB needed — mock the data layer)
- Route Handler status codes and response shape
- Middleware logic (pure function: request in → response out)

## What NOT to Test

- That Next.js routing works (it's framework behavior)
- That `revalidatePath` is called (implementation detail)
- Large snapshot tests of full page renders
- Third-party library internals
