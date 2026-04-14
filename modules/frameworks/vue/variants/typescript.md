# Vue 3 / Nuxt 3 + TypeScript Variant

> TypeScript-specific patterns for Vue 3 / Nuxt 3 projects. Extends `modules/languages/typescript.md` and `modules/frameworks/vue/conventions.md`.

## Component Prop Typing

- Use `defineProps<T>()` generic syntax — no runtime validator objects with TypeScript
- Use `withDefaults(defineProps<T>(), { ... })` to supply default values
- Export prop interfaces when the type is reused across components

```ts
interface UserCardProps {
  user: User
  selected?: boolean
  onSelect?: (id: string) => void
}

const props = withDefaults(defineProps<UserCardProps>(), {
  selected: false,
})
```

## Emit Typing

- Use `defineEmits<{ eventName: [payload: PayloadType] }>()` — tuple-based signature (Vue 3.3+)
- Name events in camelCase; they map to kebab-case in templates automatically

```ts
const emit = defineEmits<{
  selected: [id: string]
  updated: [user: User]
  closed: []
}>()
```

## defineModel Typing

```ts
// Two-way binding for form inputs (Vue 3.4+)
const model = defineModel<string>({ required: true })

// Optional with default
const checked = defineModel<boolean>('checked', { default: false })
```

## Composable Return Types

- Type composable return values explicitly when return type is not obvious from inference
- Prefer returning a plain object with named properties over a tuple (except when mimicking `useState`)

```ts
interface UseUserProfileReturn {
  user: Readonly<Ref<User | null>>
  displayName: ComputedRef<string>
  status: Ref<'idle' | 'pending' | 'success' | 'error'>
  refresh: () => Promise<void>
}

export function useUserProfile(userId: Ref<string>): UseUserProfileReturn {
  // ...
}
```

## Pinia Store Types

- Setup stores are fully inferred — no explicit store type annotation needed
- When exposing from a store, use `readonly()` on refs to prevent external mutation
- Import store type via `ReturnType<typeof useMyStore>` if needed outside the store

```ts
// stores/user.ts
export const useUserStore = defineStore('user', () => {
  const currentUser = ref<User | null>(null)
  const isAuthenticated = computed(() => currentUser.value !== null)

  async function login(credentials: LoginCredentials): Promise<void> {
    currentUser.value = await $fetch<User>('/api/auth/login', {
      method: 'POST',
      body: credentials,
    })
  }

  return {
    currentUser: readonly(currentUser),
    isAuthenticated,
    login,
  }
})
```

## Async State Pattern

```ts
type AsyncState<T> =
  | { status: 'idle' }
  | { status: 'pending' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error }
```

Use discriminated unions for UI state derived from async operations — avoids impossible states like `{ loading: true, data: [...] }`.

## Server Route Types (Nitro)

```ts
// server/api/users/index.post.ts
import { z } from 'zod'
import type { User } from '~/types/user'

const CreateUserSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
})

export default defineEventHandler(async (event): Promise<User> => {
  const body = await readValidatedBody(event, CreateUserSchema.parse)
  return db.users.create(body)
})
```

- Always annotate the return type of `defineEventHandler` — drives API client type inference
- Use Zod schemas as the source of truth for request body types: `z.infer<typeof Schema>`

## useFetch / useAsyncData Types

```ts
// Typed useFetch — data is Ref<User | null>
const { data: user, status } = await useFetch<User>(`/api/users/${id}`)

// useAsyncData with explicit return type
const { data: posts } = await useAsyncData<Post[]>('posts-list', () =>
  $fetch<Post[]>('/api/posts')
)
```

## Strict Mode

- `strict: true` in `tsconfig.json` — no exceptions
- No `any` — use `unknown` and narrow with type guards or Zod `.parse()`
- No `as` type assertions unless narrowing from `unknown`
- TSDoc on all exported composables, store actions, and server route handlers (what + why, not how)

## Typed Slots

Use `defineSlots<T>()` for typed slot props:

```ts
const slots = defineSlots<{
  default: (props: { item: Item }) => any
  header: (props: { title: string }) => any
}>()
```

## Typed Refs

- Use typed `ref<T>()` for explicit types when inference is insufficient
- Use `Ref<T>` for function parameter types
- Template refs: `const el = ref<HTMLInputElement | null>(null)`

## Dos

- Use `vue-tsc` for type checking
- Use Volar extension for IDE support
- Type all composable return values
- Use discriminated unions for component variants

## Don'ts

- Don't use `any` for props or emits
- Don't use Options API in new TypeScript components
- Don't mix `<script>` and `<script setup>` unnecessarily
- Don't use `this` -- Composition API does not use `this`
