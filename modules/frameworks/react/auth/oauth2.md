# React + OAuth2 / OIDC (oidc-client-ts)

> React-specific patterns for OIDC-based auth via oidc-client-ts or Auth0 React SDK. Extends generic React conventions.

## Integration Setup

```bash
npm install oidc-client-ts react-oidc-context
# OR for Auth0:
npm install @auth0/auth0-react
```

## Framework-Specific Patterns

### AuthProvider setup (react-oidc-context)

```typescript
// src/auth/oidcConfig.ts
import type { AuthProviderProps } from "react-oidc-context";

export const oidcConfig: AuthProviderProps = {
  authority: import.meta.env.VITE_OIDC_AUTHORITY,
  client_id: import.meta.env.VITE_OIDC_CLIENT_ID,
  redirect_uri: `${window.location.origin}/auth/callback`,
  post_logout_redirect_uri: window.location.origin,
  scope: "openid profile email",
  automaticSilentRenew: true,
  // Tokens stored in memory via oidc-client-ts default — do NOT change to localStorage
};
```

```tsx
// src/main.tsx
import { AuthProvider } from "react-oidc-context";
import { oidcConfig } from "./auth/oidcConfig";

root.render(
  <AuthProvider {...oidcConfig} onSigninCallback={() => window.history.replaceState({}, "", "/")}>
    <App />
  </AuthProvider>
);
```

### useAuth hook

```tsx
// src/auth/useAuthGuard.ts
import { useAuth } from "react-oidc-context";
import { useNavigate } from "react-router-dom";
import { useEffect } from "react";

export function useAuthGuard() {
  const auth = useAuth();
  const navigate = useNavigate();
  useEffect(() => {
    if (!auth.isLoading && !auth.isAuthenticated) navigate("/login");
  }, [auth.isLoading, auth.isAuthenticated]);
  return auth;
}
```

### Protected route pattern

```tsx
// src/auth/ProtectedRoute.tsx
import { useAuth } from "react-oidc-context";
import { Navigate } from "react-router-dom";

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const auth = useAuth();
  if (auth.isLoading) return <LoadingSpinner />;
  if (!auth.isAuthenticated) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

// Usage in router
<Route path="/dashboard" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
```

### Token attachment to API calls

```typescript
// src/api/apiClient.ts
import { User } from "oidc-client-ts";

const OIDC_STORAGE_KEY = `oidc.user:${import.meta.env.VITE_OIDC_AUTHORITY}:${import.meta.env.VITE_OIDC_CLIENT_ID}`;

function getAccessToken(): string | null {
  // oidc-client-ts stores in sessionStorage by default (memory store in v3+)
  const raw = sessionStorage.getItem(OIDC_STORAGE_KEY);
  if (!raw) return null;
  return (JSON.parse(raw) as User).access_token ?? null;
}

export async function apiFetch(url: string, init?: RequestInit): Promise<Response> {
  const token = getAccessToken();
  return fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...init?.headers,
    },
  });
}
```

### Silent refresh handling

```tsx
// src/auth/SilentRenew.tsx — mounted at /auth/silent-renew route
import { useEffect } from "react";
import { signinSilentCallback } from "oidc-client-ts";
export function SilentRenewPage() {
  useEffect(() => { signinSilentCallback().catch(console.error); }, []);
  return null;
}
```

## Scaffolder Patterns

```
src/
  auth/
    oidcConfig.ts         # AuthProvider configuration
    ProtectedRoute.tsx    # route guard component
    useAuthGuard.ts       # hook for authenticated pages
    SilentRenewPage.tsx   # silent renew callback
  api/
    apiClient.ts          # token-attaching fetch wrapper
```

## Dos

- Store tokens in memory (oidc-client-ts v3+ default) — never in `localStorage` (XSS-readable)
- Use `automaticSilentRenew: true` to refresh tokens before expiry without user interaction
- Clear auth state on logout via `auth.removeUser()` and redirect to IdP logout endpoint
- Use `onSigninCallback` to clean up `?code=` and `?state=` from the URL after OIDC redirect

## Don'ts

- Don't read `auth.user?.access_token` in render — render from state only; attach token in the API layer
- Don't use `localStorage` for tokens even with content security policy — prefer `sessionStorage` or in-memory
- Don't expose `client_secret` in the SPA — SPAs use the PKCE flow without a secret
- Don't conditionally render auth state without handling `auth.isLoading` — flicker causes unauthorized redirects
