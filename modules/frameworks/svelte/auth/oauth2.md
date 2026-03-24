# Svelte 5 + OAuth2 / OIDC (oidc-client-ts)

> Svelte 5 standalone SPA patterns for OIDC-based auth via oidc-client-ts. Extends Svelte 5 conventions.

## Integration Setup

```bash
npm install oidc-client-ts
```

No React adapter — wire `oidc-client-ts` directly into a `.svelte.ts` auth store.

## Auth Store (`.svelte.ts`)

```typescript
// src/stores/auth.svelte.ts
import { UserManager, type UserManagerSettings, type User } from 'oidc-client-ts';

const settings: UserManagerSettings = {
  authority: import.meta.env.VITE_OIDC_AUTHORITY,
  client_id: import.meta.env.VITE_OIDC_CLIENT_ID,
  redirect_uri: `${window.location.origin}/auth/callback`,
  post_logout_redirect_uri: window.location.origin,
  scope: 'openid profile email',
  automaticSilentRenew: true,
  // Tokens stored in memory by default in oidc-client-ts v3+ — do NOT override to localStorage
};

const userManager = new UserManager(settings);

let _user = $state<User | null>(null);
let _isLoading = $state(true);

// Initialize: load user from session on app start
userManager.getUser().then((user) => {
  _user = user;
  _isLoading = false;
});

// Keep store in sync with silent renew events
userManager.events.addUserLoaded((user) => { _user = user; });
userManager.events.addUserUnloaded(() => { _user = null; });
userManager.events.addAccessTokenExpired(() => { _user = null; });

export const authStore = {
  get user() { return _user; },
  get isLoading() { return _isLoading; },
  get isAuthenticated() { return _user !== null && !_user.expired; },
  get accessToken() { return _user?.access_token ?? null; },

  login: () => userManager.signinRedirect(),
  logout: () => userManager.signoutRedirect(),
  handleCallback: () => userManager.signinRedirectCallback().then((user) => { _user = user; }),
  handleSilentCallback: () => userManager.signinSilentCallback(),
};
```

## Callback Page Component

```svelte
<!-- src/pages/AuthCallback.svelte -->
<script lang="ts">
  import { authStore } from '../stores/auth.svelte.ts';
  import { navigate } from 'svelte-routing';

  $effect(() => {
    authStore.handleCallback()
      .then(() => {
        // Clean up OIDC query params from URL
        window.history.replaceState({}, '', '/');
        navigate('/', { replace: true });
      })
      .catch((err) => {
        console.error('OIDC callback failed:', err);
        navigate('/login', { replace: true });
      });
  });
</script>

<p>Signing in…</p>
```

## Protected Route Pattern

```svelte
<!-- src/components/shared/ProtectedRoute.svelte -->
<script lang="ts">
  import { authStore } from '../../stores/auth.svelte.ts';
  import { navigate } from 'svelte-routing';

  let { children } = $props();

  $effect(() => {
    if (!authStore.isLoading && !authStore.isAuthenticated) {
      navigate('/login', { replace: true });
    }
  });
</script>

{#if authStore.isLoading}
  <LoadingSpinner />
{:else if authStore.isAuthenticated}
  {@render children()}
{/if}
```

## Token Attachment to API Calls

```typescript
// src/api/client.ts
import { authStore } from '../stores/auth.svelte.ts';

export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const token = authStore.accessToken;
  const response = await fetch(`${import.meta.env.VITE_API_BASE_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  });
  if (!response.ok) throw new Error(`API error ${response.status}: ${await response.text()}`);
  return response.json() as Promise<T>;
}
```

## App Bootstrap

```svelte
<!-- src/App.svelte -->
<script lang="ts">
  import { Router, Route } from 'svelte-routing';
  import { authStore } from './stores/auth.svelte.ts';
  import ProtectedRoute from './components/shared/ProtectedRoute.svelte';
  import AuthCallback from './pages/AuthCallback.svelte';
  import Dashboard from './pages/Dashboard.svelte';
  import Login from './pages/Login.svelte';

  export let url = '';
</script>

<Router {url}>
  <Route path="/auth/callback" component={AuthCallback} />
  <Route path="/login" component={Login} />
  <Route path="/">
    <ProtectedRoute>
      <Dashboard />
    </ProtectedRoute>
  </Route>
</Router>
```

## Scaffolder Patterns

```
src/
  stores/
    auth.svelte.ts              # oidc-client-ts UserManager + $state auth store
  pages/
    AuthCallback.svelte         # handles OIDC redirect callback
    Login.svelte                # triggers authStore.login()
  components/shared/
    ProtectedRoute.svelte       # guards authenticated routes
  api/
    client.ts                   # token-attaching fetch wrapper (reads authStore.accessToken)
```

## Dos

- Initialize `UserManager` once at module level — it manages its own event subscriptions
- Use `automaticSilentRenew: true` to refresh tokens before expiry without user interaction
- Call `window.history.replaceState({}, '', '/')` after callback to strip OIDC query params
- Store tokens in memory (oidc-client-ts v3+ default) — never `localStorage` (XSS-readable)
- Use `authStore.isLoading` to avoid auth flicker before the initial user load resolves

## Don'ts

- Don't read `authStore.accessToken` in components for rendering — only in the API client layer
- Don't use `localStorage` for tokens — prefer the default `sessionStorage` or in-memory store
- Don't expose `client_secret` in the SPA — SPAs use the PKCE flow without a client secret
- Don't navigate on auth events inside the store — navigate in components reacting to auth state
- Don't conditionally render auth-protected content without handling `authStore.isLoading` — flicker causes unauthorized UI flashes
