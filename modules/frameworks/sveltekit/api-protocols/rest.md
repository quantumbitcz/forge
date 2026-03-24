# SvelteKit REST — API Protocol Binding

> SvelteKit REST patterns: server routes (`+server.ts`), load functions, form actions, and typed fetch.

## Integration Setup
- Built-in: `RequestEvent`, `json()` helper from `@sveltejs/kit`
- Validation: `zod` with manual `safeParse`; `superforms` + `zod` for form actions
- OpenAPI: `@sveltejs/adapter-auto` or manual `swagger.json` served as a static asset

## Framework-Specific Patterns

### Server route (`+server.ts`)
```typescript
// src/routes/api/users/+server.ts
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod';

const CreateUserSchema = z.object({ name: z.string().min(1), email: z.string().email() });

export const GET: RequestHandler = async ({ url }) => {
  const users = await userService.list();
  return json(users);
};

export const POST: RequestHandler = async ({ request }) => {
  const parsed = CreateUserSchema.safeParse(await request.json());
  if (!parsed.success) throw error(400, { message: 'Invalid input' });
  const user = await userService.create(parsed.data);
  return json(user, { status: 201 });
};
```

### Dynamic segment
```typescript
// src/routes/api/users/[id]/+server.ts
export const GET: RequestHandler = async ({ params }) => {
  const user = await userService.findById(params.id);
  if (!user) throw error(404, 'User not found');
  return json(user);
};
```

### Load function (server-side data fetching)
```typescript
// src/routes/users/+page.server.ts
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, cookies }) => {
  const res = await fetch('/api/users');
  const users = await res.json();
  return { users };
};
```

### Form actions
```typescript
// src/routes/users/new/+page.server.ts
import type { Actions } from './$types';
import { fail, redirect } from '@sveltejs/kit';

export const actions: Actions = {
  create: async ({ request }) => {
    const data = Object.fromEntries(await request.formData());
    const parsed = CreateUserSchema.safeParse(data);
    if (!parsed.success) return fail(400, { errors: parsed.error.flatten() });
    await userService.create(parsed.data);
    throw redirect(303, '/users');
  },
};
```

### Typed `fetch` in load functions
SvelteKit's `fetch` in load functions is enhanced — it handles cookies, relative URLs, and SSR. Always use it instead of global `fetch` in `+page.server.ts`.

## Scaffolder Patterns
```
src/
  routes/
    api/
      users/
        +server.ts          # GET, POST
        [id]/
          +server.ts        # GET, PATCH, DELETE
    users/
      +page.server.ts       # load + actions
      +page.svelte          # UI
  lib/
    server/
      users.service.ts      # business logic (server-only)
```

## Dos
- Export only the HTTP method handlers you implement — SvelteKit returns 405 automatically for others
- Use `throw error(status, message)` from `@sveltejs/kit` — it integrates with SvelteKit's error page
- Use `fail()` in form actions to return validation errors without a redirect
- Mark server-only modules with `.server.ts` suffix to prevent accidental client bundling

## Don'ts
- Don't use global `fetch` in load functions — use the event-scoped `fetch` parameter
- Don't write database queries directly in `+page.server.ts` — delegate to a service layer
- Don't expose internal error messages to the client via `error()` in production
- Don't mix form actions and JSON REST endpoints in the same `+page.server.ts` file
