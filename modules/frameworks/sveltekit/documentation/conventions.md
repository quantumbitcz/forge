# SvelteKit Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with SvelteKit-specific patterns.

## Code Documentation

- Use TSDoc (`/** */`) for all exported `load` functions, form actions, API route handlers, and shared utilities.
- `+page.server.ts` / `+layout.server.ts` `load` functions: document what data they fetch, what errors they throw, and any redirect conditions.
- Form actions: document each action name, its expected form fields, return shape on success, and `fail()` codes on error.
- `+server.ts` API routes: document the method, request body shape, response shape, and auth requirements.
- Svelte stores in `lib/`: document the store's value type and mutation API.

```typescript
/**
 * Loads user profile data for the profile page.
 *
 * Redirects to `/login` if the session is missing.
 *
 * @throws `redirect(302, '/login')` — unauthenticated
 * @throws `error(404, 'User not found')` — unknown userId
 */
export const load: PageServerLoad = async ({ locals, params }) => { ... }
```

## Architecture Documentation

- Document the file-based routing structure for apps with 10+ routes — a table or tree diagram.
- Document the `hooks.server.ts` middleware chain: what each hook checks or attaches to `locals`.
- Document `$lib` module structure: what each subdirectory exports and its intended consumers.
- Document SSR vs CSR decisions: which routes are SSR-only, which are prerendered, and why.
- Authentication: document the session pattern (cookie-based, JWT, etc.) and how `locals.user` is populated.

## Diagram Guidance

- **Route tree:** Mermaid flowchart for the file-based routing structure.
- **Data loading chain:** Sequence diagram showing layout `load` → page `load` → component render.

## Dos

- Document `event.locals` shape in `app.d.ts` — it is the contract between hooks and load functions
- Document the `$env` variables required at each build target (server, static, both)
- Keep `+page.ts` (CSR) vs `+page.server.ts` (SSR) distinctions explicit in docs

## Don'ts

- Don't document Svelte reactive declarations (`$:`) as architectural concepts — they are implementation details
- Don't duplicate form field docs in both the action and the Zod schema — pick one location
