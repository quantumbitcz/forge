# Vue 3 / Nuxt 3 + Vitest Testing Patterns

> Vue-specific testing patterns for Vitest. Extends `modules/testing/vitest.md`.

## Setup

Install `@vue/test-utils`, `@testing-library/vue`, `@pinia/testing`, and `@nuxt/test-utils` as devDependencies.

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    globals: true,
    alias: {
      '@': path.resolve(__dirname, './'),
      '#app': path.resolve(__dirname, './tests/mocks/nuxt-app.ts'),
    },
  },
})
```

Nuxt auto-import composables (`useFetch`, `useRoute`, `useRouter`, `navigateTo`) must be mocked for unit tests — they are not available outside the Nuxt runtime.

```ts
// tests/setup.ts
import { vi } from 'vitest'

vi.mock('#app', () => ({
  useFetch: vi.fn(),
  useAsyncData: vi.fn(),
  useRoute: () => ({ params: {}, query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), back: vi.fn() }),
  navigateTo: vi.fn(),
  definePageMeta: vi.fn(),
  useRuntimeConfig: () => ({ public: {} }),
}))
```

## Component Testing with @vue/test-utils

```ts
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import UserCard from '@/components/User/UserCard.vue'

describe('UserCard', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('renders user display name', () => {
    const wrapper = mount(UserCard, {
      props: { user: { id: '1', firstName: 'Alice', lastName: 'Smith' } },
    })

    expect(wrapper.text()).toContain('Alice Smith')
  })

  it('emits selected event on click', async () => {
    const wrapper = mount(UserCard, {
      props: { user: { id: '1', firstName: 'Alice', lastName: 'Smith' } },
    })

    await wrapper.find('[data-testid="card"]').trigger('click')
    expect(wrapper.emitted('selected')).toBeTruthy()
    expect(wrapper.emitted('selected')![0]).toEqual(['1'])
  })
})
```

- Prefer `mount` over `shallowMount` unless child components have costly side effects
- Use `wrapper.find()` with semantic selectors when possible; `data-testid` as last resort
- Always call `setActivePinia(createPinia())` in `beforeEach` when the component uses Pinia

## Pinia Store Testing

```ts
import { setActivePinia, createPinia } from 'pinia'
import { useCartStore } from '@/stores/cart'

describe('useCartStore', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('adds item and updates total', () => {
    const cart = useCartStore()
    cart.addItem({ id: '1', name: 'Widget', price: 10 })

    expect(cart.items).toHaveLength(1)
    expect(cart.total).toBe(10)
  })
})
```

- Test store actions and computed values without mounting a component
- Mock external dependencies (API calls, other stores) with `vi.mock()`
- Do NOT test Pinia internal reactivity mechanics — test observable behavior

## Composable Testing

```ts
import { ref } from 'vue'
import { useUserProfile } from '@/composables/useUserProfile'

// Helper to run composables in a reactive context
function withSetup<T>(composable: () => T): T {
  let result!: T
  const app = createApp({ setup() { result = composable(); return () => {} } })
  app.use(createPinia())
  app.mount(document.createElement('div'))
  return result
}

describe('useUserProfile', () => {
  it('returns display name from user data', () => {
    vi.mocked(useFetch).mockReturnValue({
      data: ref({ firstName: 'Alice', lastName: 'Smith' }),
      status: ref('success'),
      refresh: vi.fn(),
    } as any)

    const { displayName } = withSetup(() => useUserProfile(ref('user-1')))
    expect(displayName.value).toBe('Alice Smith')
  })
})
```

## Server Route Testing

```ts
import { createEvent } from 'h3'
import { IncomingMessage, ServerResponse } from 'node:http'

// Import the handler directly
import handler from '@/server/api/users/[id].get'

describe('GET /api/users/:id', () => {
  it('returns 404 for unknown user', async () => {
    vi.mocked(db.users.findById).mockResolvedValue(null)

    const req = new IncomingMessage(null as any)
    const res = new ServerResponse(req)
    const event = createEvent(req, res)
    event.context.params = { id: 'unknown-id' }

    await expect(handler(event)).rejects.toMatchObject({ statusCode: 404 })
  })
})
```

- Call the `defineEventHandler` function directly — no server spin-up needed
- Use `@nuxt/test-utils` `setup()` only for full integration tests that need the Nuxt runtime

## useFetch / useAsyncData Mocking

```ts
import { ref } from 'vue'

vi.mock('#app', () => ({
  useFetch: vi.fn().mockReturnValue({
    data: ref([{ id: '1', title: 'Post One' }]),
    status: ref('success'),
    error: ref(null),
    refresh: vi.fn(),
  }),
}))
```

## What to Test

- Component rendering: correct UI for loading, error, empty, and populated states
- Component interactions: click, type, submit, emit
- Pinia store actions and computed properties in isolation
- Composable reactive behavior (reactive state changes, computed updates)
- Server route validation (400 for bad input, 404 for missing, 201 for create)
- Middleware redirect logic (pure function: route in → redirect or continue)

## What NOT to Test

- Nuxt file-based routing resolution (framework behavior)
- Auto-import resolution (Nuxt internal mechanism)
- `useFetch` / `useAsyncData` caching mechanics
- Vue reactivity system internals
- `<Transition>` / `<TransitionGroup>` animation timing
