# Vue 3 / Nuxt 3 + OAuth2 / OIDC

> Vue/Nuxt-specific patterns for OIDC-based auth. Covers both `@nuxtjs/auth-next` (session-based) and `oidc-client-ts` (SPA PKCE flow).

## Integration Setup

```bash
# Option A: Nuxt Auth module (recommended for full-stack Nuxt)
npm install @sidebase/nuxt-auth  # nextauth-based, supports credentials + OAuth providers

# Option B: SPA PKCE with oidc-client-ts
npm install oidc-client-ts
```

## Option A: @sidebase/nuxt-auth (recommended)

```ts
// nuxt.config.ts
export default defineNuxtConfig({
  modules: ['@sidebase/nuxt-auth'],
  auth: {
    provider: {
      type: 'authjs',
    },
    globalAppMiddleware: false,  // opt-in per route via definePageMeta
  },
})
```

```ts
// server/api/auth/[...].ts
import { NuxtAuthHandler } from '#auth'
import GitHubProvider from 'next-auth/providers/github'

export default NuxtAuthHandler({
  providers: [
    GitHubProvider({
      clientId: useRuntimeConfig().github.clientId,
      clientSecret: useRuntimeConfig().github.clientSecret,
    }),
  ],
})
```

### useAuth composable (@sidebase/nuxt-auth)

```vue
<script setup lang="ts">
const { data: session, status, signIn, signOut } = useAuth()
const isAuthenticated = computed(() => status.value === 'authenticated')
</script>
```

### Protected pages

```vue
<script setup lang="ts">
definePageMeta({
  auth: true,  // redirects to /api/auth/signin if not authenticated
})
</script>
```

## Option B: oidc-client-ts (SPA PKCE)

```ts
// composables/useOidc.ts
import { UserManager, type UserManagerSettings } from 'oidc-client-ts'

const settings: UserManagerSettings = {
  authority: useRuntimeConfig().public.oidcAuthority,
  client_id: useRuntimeConfig().public.oidcClientId,
  redirect_uri: `${window.location.origin}/auth/callback`,
  post_logout_redirect_uri: window.location.origin,
  scope: 'openid profile email',
  automaticSilentRenew: true,
}

let manager: UserManager | null = null

export function useOidc() {
  if (import.meta.server) return { isAuthenticated: ref(false), login: () => {}, logout: () => {} }

  if (!manager) manager = new UserManager(settings)

  const isAuthenticated = ref(false)

  manager.getUser().then((user) => {
    isAuthenticated.value = !!user && !user.expired
  })

  return {
    isAuthenticated,
    login: () => manager!.signinRedirect(),
    logout: () => manager!.signoutRedirect(),
    getAccessToken: () => manager!.getUser().then((u) => u?.access_token ?? null),
  }
}
```

### Auth middleware

```ts
// middleware/auth.ts
export default defineNuxtMiddleware(async () => {
  const { isAuthenticated } = useOidc()
  if (!isAuthenticated.value) {
    return navigateTo('/login')
  }
})
```

### Token attachment

```ts
// composables/useAuthFetch.ts
export function useAuthFetch() {
  const { getAccessToken } = useOidc()

  return async function authFetch<T>(url: string, options?: Parameters<typeof $fetch>[1]): Promise<T> {
    const token = await getAccessToken()
    return $fetch<T>(url, {
      ...options,
      headers: {
        ...options?.headers,
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    })
  }
}
```

## Scaffolder Patterns

```
middleware/
  auth.ts                    # route guard (redirect unauthenticated users)
server/
  api/
    auth/
      [...].ts               # @sidebase/nuxt-auth or custom auth handler
composables/
  useAuth.ts                 # session composable (wraps useAuth from nuxt-auth)
  useOidc.ts                 # oidc-client-ts wrapper (for SPA PKCE flow)
  useAuthFetch.ts            # token-attaching $fetch wrapper
pages/
  auth/
    callback.vue             # OIDC callback page (for SPA flow)
    login.vue                # login page
```

## Dos

- Use `@sidebase/nuxt-auth` for full-stack Nuxt apps — it handles sessions server-side, safer than client-side tokens
- Store OIDC client secrets in `runtimeConfig` (server-only) — never in `runtimeConfig.public`
- Use `automaticSilentRenew: true` in oidc-client-ts to refresh tokens before expiry
- Guard protected pages with `definePageMeta({ auth: true })` or an explicit middleware declaration
- Clear auth state and redirect to IdP logout endpoint on sign-out

## Don'ts

- Don't store access tokens in `localStorage` — use in-memory storage (oidc-client-ts default) or secure HttpOnly cookies
- Don't expose `client_secret` in the SPA — SPAs use PKCE flow without a secret
- Don't skip the `isLoading` / `status === 'loading'` check — rendering before auth resolves causes unauthorized flicker
- Don't use `useOidc` on the server side — OIDC client is browser-only; guard with `import.meta.client` checks
- Don't hardcode the OIDC authority URL — use `runtimeConfig.public.oidcAuthority` so it's configurable per environment
