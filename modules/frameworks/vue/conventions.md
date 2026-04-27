# Vue 3 / Nuxt 3 Framework Conventions
> Support tier: contract-verified
> Framework-specific conventions for Vue 3 / Nuxt 3 projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture

| Layer | Responsibility | Location |
|-------|---------------|----------|
| Page | Route-level component, SEO meta, layout assignment | `pages/{route}.vue` |
| Layout | Shared UI shell wrapping page slots | `layouts/{name}.vue` |
| Component | Reusable UI, no route coupling | `components/{Feature}/{Name}.vue` |
| Composable | Shared reactive logic, side-effect encapsulation | `composables/use{Name}.ts` |
| Server Route | REST API endpoints via Nitro | `server/api/{resource}.{method}.ts` |
| Middleware | Auth guards, redirects, per-route logic | `middleware/{name}.ts` |
| Store | Global reactive state via Pinia | `stores/{domain}.ts` |
| Plugin | Third-party SDK setup, global providers | `plugins/{name}.ts` |

**Dependency rule:** Pages depend on layouts and components. Components depend only on composables and stores — never on page-level data. Server routes never import client-side Vue/Nuxt APIs.

## Composition API

- Use `<script setup lang="ts">` exclusively — no Options API, no `defineComponent` wrapper
- Nuxt auto-imports: never manually import `ref`, `computed`, `watch`, `useFetch`, `useRoute`, `useRouter`, `navigateTo`, or `definePageMeta` — Nuxt provides them automatically
- Keep `<script setup>` blocks under 80 lines; extract reactive logic into composables when exceeded
- Order in `<script setup>`: imports → props/emits → composables → reactive state → computed → watchers → functions → lifecycle

```vue
<script setup lang="ts">
interface Props {
  userId: string
  readonly?: boolean
}

const props = defineProps<Props>()
const emit = defineEmits<{ updated: [user: User] }>()

const { data: user, status } = await useFetch(`/api/users/${props.userId}`)
const isLoading = computed(() => status.value === 'pending')

function handleSave(updated: User) {
  emit('updated', updated)
}
</script>
```

## State Management (Pinia)

- Define stores with `defineStore` using the Setup Store syntax (Composition API style)
- Store IDs must be unique and kebab-case: `defineStore('user-profile', () => { ... })`
- Expose only what consumers need — keep internal state private to the setup function
- For SSR-safe global state that does not need persistence, prefer `useState()` (Nuxt composable)

```ts
// stores/cart.ts
export const useCartStore = defineStore('cart', () => {
  const items = ref<CartItem[]>([])
  const total = computed(() => items.value.reduce((sum, i) => sum + i.price, 0))

  function addItem(item: CartItem) {
    items.value.push(item)
  }

  return { items: readonly(items), total, addItem }
})
```

- Never mutate store state outside the store — expose action functions instead
- Use `storeToRefs()` to destructure reactive properties from a store without losing reactivity

## Data Fetching

- `useFetch` for data required at page load (SSR + CSR, auto-keyed, cached)
- `useAsyncData` for custom async logic or when key control is needed
- `$fetch` for client-triggered requests (event handlers, mutations) — not SSR-safe for initial data
- `useLazyFetch` / `useLazyAsyncData` for non-blocking data (page renders immediately with `pending` state)

```vue
<script setup lang="ts">
// Blocking: page waits for data before rendering (SSR-safe, good for critical content)
const { data: posts, error } = await useFetch('/api/posts', {
  key: 'posts-list',
  pick: ['id', 'title', 'slug'],
})

// Non-blocking: page renders immediately, data fills in (good for secondary content)
const { data: recommendations, pending } = useLazyFetch('/api/recommendations')
</script>
```

- Always provide a stable `key` to `useFetch`/`useAsyncData` to prevent duplicate requests
- Use `pick` to select only the fields you need — reduces payload and reactive overhead
- Refresh data with `refresh()` returned from `useFetch`; use `execute()` on lazy variants
- For mutations, use `$fetch` + call `refresh()` or `clearNuxtData(key)` after success

## Routing and Navigation

- File-based routing in `pages/` — directory structure maps to URL paths
- Dynamic segments: `pages/users/[id].vue` → `/users/123`
- Nested routes: `pages/settings/profile.vue` → `<NuxtPage>` inside `settings.vue`
- `<NuxtLink to="...">` for all internal navigation — never use `<a>` for internal links
- Programmatic navigation: `navigateTo('/path')` (server + client safe) or `useRouter().push()`
- Page metadata: always define with `definePageMeta` at the top of `<script setup>`

```vue
<script setup lang="ts">
definePageMeta({
  layout: 'dashboard',
  middleware: ['auth'],
})
</script>
```

## Server Routes (Nitro)

```ts
// server/api/users/[id].get.ts
import { z } from 'zod'

export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  if (!id) throw createError({ statusCode: 400, message: 'Missing id' })

  const user = await db.users.findById(id)
  if (!user) throw createError({ statusCode: 404, message: 'User not found' })

  return user
})
```

- File naming convention: `{resource}.{method}.ts` (e.g., `users.get.ts`, `users.post.ts`)
- Use `defineEventHandler` — always the default export
- Validate path params with `getRouterParam`, query with `getQuery`, body with `readValidatedBody`
- Throw `createError({ statusCode, message })` for HTTP errors — never throw plain `Error`
- Validate request bodies with Zod via `readValidatedBody(event, schema.parse)`

```ts
// server/api/users/index.post.ts
import { z } from 'zod'

const CreateUserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
})

export default defineEventHandler(async (event) => {
  const body = await readValidatedBody(event, CreateUserSchema.parse)
  const user = await db.users.create(body)
  setResponseStatus(event, 201)
  return user
})
```

## Components

- Single-file components (`.vue`) with `<template>`, `<script setup lang="ts">`, `<style scoped>`
- `<template>` over JSX — JSX is only acceptable for render-function-heavy library code
- `defineProps<T>()` with TypeScript generic — no runtime validators needed with TypeScript
- `defineEmits<{ eventName: [payload: Type] }>()` for typed emit declarations
- `defineModel()` for two-way binding in components that wrap form inputs (Vue 3.4+)

```vue
<!-- components/Form/TextInput.vue -->
<script setup lang="ts">
const model = defineModel<string>({ required: true })

defineProps<{
  label: string
  placeholder?: string
  error?: string
}>()
</script>

<template>
  <div class="field">
    <label>{{ label }}</label>
    <input v-model="model" :placeholder="placeholder" />
    <span v-if="error" class="error">{{ error }}</span>
  </div>
</template>
```

- Use `v-bind="$attrs"` to forward attributes on wrapper components (`inheritAttrs: false`)
- Prefer `v-if` / `v-else` over conditional ternary in template for clarity
- `v-for` always requires a `:key` — use stable IDs, never array index for mutable lists

## Composables

- Composable filenames: `composables/use{Name}.ts` (e.g., `useUserProfile.ts`)
- A composable is a function that uses Vue reactivity and returns reactive state or actions
- Return a plain object — do NOT return a reactive wrapper around the whole return value
- Composables that use `useFetch`/`useAsyncData` must be called in `<script setup>` or another composable (not in event handlers)

```ts
// composables/useUserProfile.ts
export function useUserProfile(userId: Ref<string>) {
  const { data: user, status, refresh } = useFetch(
    () => `/api/users/${userId.value}`,
    { key: () => `user-${userId.value}`, watch: [userId] }
  )

  const displayName = computed(() =>
    user.value ? `${user.value.firstName} ${user.value.lastName}` : ''
  )

  return { user: readonly(user), displayName, status, refresh }
}
```

## Layouts

- Default layout: `layouts/default.vue` (used when no layout is specified)
- `<slot />` in the layout template defines where page content renders
- Switch layouts per-page via `definePageMeta({ layout: 'dashboard' })`
- Use `<NuxtLayout>` in `app.vue` to enable the layouts system

## Middleware

- Route middleware: `middleware/auth.ts` — runs on client-side navigation
- Server middleware: `server/middleware/{name}.ts` — runs for every server request

```ts
// middleware/auth.ts
export default defineNuxtMiddleware(() => {
  const { isAuthenticated } = useAuth()
  if (!isAuthenticated.value) {
    return navigateTo('/login')
  }
})
```

## Styling

- Scoped styles in `<style scoped>` — prevents class name collisions
- CSS custom properties (variables) for design tokens — never hardcode hex values in templates or scripts
- Tailwind CSS (if configured): use utility classes with design tokens; avoid arbitrary values
- No inline `style` objects unless the value is truly dynamic (data-driven, not static)
- `<style scoped>` deep selector (`::v-deep` or `:deep()`) only when overriding third-party components

## Animation & Motion

Reference `shared/frontend-design-theory.md` for design theory guardrails.

### Library Preference
- **Simple transitions**: `<Transition>` and `<TransitionGroup>` built-in Vue components
- **Page transitions**: `definePageMeta({ pageTransition: { name: 'fade' } })` + CSS classes
- **Complex sequences**: GSAP via `@gsap/vue` or `useGsap` Nuxt module
- **CSS-only**: loading spinners, skeleton pulses, hover effects via `<style scoped>`

### Key Constraint
All animation logic must be compatible with SSR — avoid `window`/`document` access in composables called at setup time. Use `onMounted` for DOM-dependent animation setup.

### Standards
- Spring physics over cubic-bezier for natural feel
- Timing: <100ms feedback, 150-200ms micro-interactions, 200-350ms transitions, 300-500ms sequences
- Only animate `transform` and `opacity` (GPU-composited)
- REQUIRED: `prefers-reduced-motion` support for all animations

```vue
<Transition name="fade" mode="out-in">
  <component :is="currentView" :key="currentView" />
</Transition>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 200ms ease;
}
@media (prefers-reduced-motion: reduce) {
  .fade-enter-active,
  .fade-leave-active { transition: none; }
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
```

## Multi-Viewport Design

### Breakpoints
- Mobile: 375px | Tablet: 768px | Desktop: 1280px | Wide: 1536px+

### Mobile (375px)
- Touch targets >= 44px, single-column reflow, 16px min body text
- Use `<NuxtImg>` (from `@nuxt/image`) with `sizes` prop for responsive image serving

### Tablet (768px)
- Adaptive layout (not scaled mobile), touch + hover hybrid

### Desktop (1280px+)
- Hover states, generous whitespace, full navigation
- Use `<NuxtImg>` `preload` for above-fold hero images

### Cross-Viewport
- Same information hierarchy at all sizes, 8pt grid spacing

## Security

- Nuxt server routes validate all input — never trust `readBody` without schema validation
- Runtime config: server-only secrets in `runtimeConfig.{key}` (not `runtimeConfig.public`)
- `runtimeConfig.public.*` values are exposed to the client — treat as public
- Nuxt auto-escapes template expressions — avoid `v-html` unless content is from a trusted source and sanitized
- Use `useRequestHeaders` for server-side header access — never pass sensitive headers as props
- Server route auth: verify session/token before every mutation endpoint

## Performance

- `useLazyFetch` for non-critical data to avoid blocking page render
- `defineAsyncComponent(() => import('./Heavy.vue'))` for large client-only components
- `<NuxtImg>` from `@nuxt/image` for automatic format conversion and lazy loading
- Tree-shake Nuxt modules — add only what is needed to `nuxt.config.ts` `modules` array
- Avoid large reactive objects — use `shallowRef` for data-only structures that Vue doesn't need to deep-track
- Prefetch links: `<NuxtLink prefetch>` fetches page component on viewport entry

## Testing

### Test Framework
- **Vitest** as the test runner with **`@vue/test-utils`** for component tests
- **`@nuxt/test-utils`** for Nuxt-specific integration tests (server routes, middleware, pages)
- **Playwright** for end-to-end tests

### Integration Test Patterns
- Test components with `@vue/test-utils` `mount` / `shallowMount` — mock composables and Pinia stores
- Test Pinia stores in isolation: `setActivePinia(createPinia())` in `beforeEach`
- Test server routes by calling the handler function directly with a mock event
- Use `@nuxt/test-utils` `setup()` for full Nuxt integration tests (slower — use sparingly)
- Mock `useFetch`/`useAsyncData` via `vi.mock('#app')` for unit tests

### What to Test
- Component rendering: correct UI for loading, error, empty, and populated states
- Store actions and computed values in isolation
- Composable reactive behavior (using `@vue/test-utils` `withSetup` helper or plain reactive context)
- Server route validation: 400 for invalid input, 201 for valid create, 404 for missing resources
- Middleware redirect logic

### What NOT to Test
- Nuxt file-based routing resolution (framework behavior)
- Auto-import resolution
- `useFetch` caching mechanics (framework behavior)
- Vue reactivity system internals

### Example Test Structure
```
pages/
  users/
    [id].vue
components/
  User/
    UserCard.vue
    UserCard.test.ts        # co-located component test
composables/
  useUserProfile.ts
  useUserProfile.test.ts    # composable unit test
server/
  api/
    users/
      [id].get.ts
      [id].get.test.ts      # server route test
stores/
  cart.ts
  cart.test.ts              # Pinia store test
tests/
  e2e/
    user-flow.spec.ts       # Playwright E2E
```

For general Vitest patterns, see `modules/testing/vitest.md`.
For Playwright E2E patterns, see `modules/testing/playwright.md`.

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Smart Test Rules

- No duplicate tests — grep existing tests before generating
- Test behavior, not implementation
- Skip framework guarantees (don't test Nuxt routing or auto-imports)
- One assertion focus per `it()` — multiple asserts OK if same behavior

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated composables, changing component public APIs, restructuring Pinia stores.

## Dos and Don'ts

### Do
- Use `<script setup lang="ts">` for every component — Composition API only
- Use Nuxt auto-imports — do not manually import Vue/Nuxt core APIs
- Use `useFetch` with a stable `key` for SSR-safe data loading
- Validate all server route inputs with Zod via `readValidatedBody`
- Use `definePageMeta` to assign layouts and middleware per page
- Use `<NuxtLink>` for all internal navigation
- Use `<NuxtImg>` for all content images
- Use `storeToRefs()` when destructuring Pinia store state
- Use `readonly()` when exposing internal refs from stores or composables
- Keep server secrets in `runtimeConfig` (not `runtimeConfig.public`)

### Don't
- Don't use Options API (`data()`, `methods:`, `computed:`) — use `<script setup>` exclusively
- Don't use `this.$` — there is no `this` in `<script setup>`
- Don't use `ref.value` in templates — Vue unwraps refs automatically in `<template>`
- Don't call `useFetch`/`useAsyncData` inside event handlers — call them in setup scope
- Don't hardcode hex colors — use CSS custom properties / design tokens
- Don't use `v-html` with untrusted content — always sanitize first
- Don't use array index as `:key` in `v-for` over mutable lists
- Don't store server-only secrets in `runtimeConfig.public`
- Don't use `<img>` for content images — use `<NuxtImg>`
- Don't bypass TypeScript — `strict: true` is required, no `any`
