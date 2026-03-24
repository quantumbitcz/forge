# SvelteKit + OAuth2 / Session Auth

> OAuth2 and session management for SvelteKit using Auth.js (SvelteKit adapter) or Lucia Auth.
> Both integrate via `hooks.server.ts` — the session is injected into every load function via `event.locals`.

## Integration Setup

```bash
# Option A: Auth.js (SvelteKit adapter — recommended for OAuth providers)
npm install @auth/sveltekit

# Option B: Lucia Auth (flexible, session-only)
npm install lucia @lucia-auth/adapter-drizzle  # or oslo for password hashing
```

## Framework-Specific Patterns

### Auth.js setup
```typescript
// src/auth.ts
import { SvelteKitAuth } from '@auth/sveltekit';
import GitHub from '@auth/sveltekit/providers/github';
import Google from '@auth/sveltekit/providers/google';

export const { handle, signIn, signOut } = SvelteKitAuth({
  providers: [GitHub, Google],
  callbacks: {
    session({ session, token }) {
      session.user.id = token.sub!;
      return session;
    },
  },
});
```

### `hooks.server.ts` — session injection
```typescript
// src/hooks.server.ts
export { handle } from './auth';
```

With Lucia or custom auth, populate `event.locals`:
```typescript
// src/hooks.server.ts (Lucia example)
import type { Handle } from '@sveltejs/kit';
import { lucia } from '$lib/server/auth';

export const handle: Handle = async ({ event, resolve }) => {
  const sessionId = event.cookies.get(lucia.sessionCookieName);
  if (!sessionId) {
    event.locals.user = null;
    event.locals.session = null;
    return resolve(event);
  }
  const { session, user } = await lucia.validateSession(sessionId);
  if (session?.fresh) {
    const cookie = lucia.createSessionCookie(session.id);
    event.cookies.set(cookie.name, cookie.value, { path: '/', ...cookie.attributes });
  }
  event.locals.user = user;
  event.locals.session = session;
  return resolve(event);
};
```

### Protected load function
```typescript
// src/routes/dashboard/+page.server.ts
import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) throw redirect(303, '/login');
  return { user: locals.user };
};
```

### Sign-in / sign-out actions
```typescript
// src/routes/login/+page.server.ts
import { signIn } from '../../auth';
import type { Actions } from './$types';

export const actions: Actions = { github: signIn('github') };
```

### Extend `Locals` type
```typescript
// src/app.d.ts
declare global {
  namespace App {
    interface Locals {
      user: import('$lib/server/auth').User | null;
      session: import('$lib/server/auth').Session | null;
    }
  }
}
```

## Scaffolder Patterns
```
src/
  auth.ts                         # SvelteKitAuth config
  hooks.server.ts                 # session injection via handle
  app.d.ts                        # Locals type extension
  lib/server/
    auth.ts                       # Lucia instance (if using Lucia)
  routes/
    login/
      +page.svelte
      +page.server.ts             # signIn actions
    (protected)/                  # group with layout guard
      +layout.server.ts           # redirect if not authenticated
      dashboard/
        +page.server.ts
```

## Dos
- Always validate session in `hooks.server.ts` — `event.locals` flows to all load functions
- Use route groups `(protected)/` with a `+layout.server.ts` guard to protect entire subtrees
- Extend `App.Locals` in `app.d.ts` for type-safe `locals.user` access
- Set `HttpOnly`, `SameSite=Lax`, and `Secure` on session cookies

## Don'ts
- Don't check auth inside individual `+page.server.ts` files when a layout guard covers the subtree
- Don't store sensitive data in the JWT payload that is returned to the client via `session`
- Don't commit `AUTH_SECRET` or OAuth `CLIENT_SECRET` to version control
- Don't use client-side stores as the auth source of truth — always verify server-side
