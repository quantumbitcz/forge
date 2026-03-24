# Next.js + NextAuth.js (Auth.js)

> OAuth2 / session management with Auth.js v5 (NextAuth) on Next.js App Router.
> Auth.js v5 unifies the config in a single `auth.ts` file and uses the Next.js middleware for protection.

## Integration Setup

```bash
npm install next-auth@beta
npx auth secret    # generates AUTH_SECRET in .env.local
```

```typescript
// auth.ts (project root)
import NextAuth from 'next-auth';
import GitHub from 'next-auth/providers/github';
import Google from 'next-auth/providers/google';

export const { handlers, auth, signIn, signOut } = NextAuth({
  providers: [GitHub, Google],
  session: { strategy: 'jwt' },
  callbacks: {
    jwt({ token, user }) {
      if (user) token.role = (user as any).role ?? 'user';
      return token;
    },
    session({ session, token }) {
      session.user.role = token.role as string;
      return session;
    },
  },
});
```

## Framework-Specific Patterns

### Route Handler (required by Auth.js)
```typescript
// app/api/auth/[...nextauth]/route.ts
export { handlers as GET, handlers as POST } from '@/auth';
```

### Middleware protection
```typescript
// middleware.ts
export { auth as middleware } from '@/auth';

export const config = {
  matcher: ['/((?!api/auth|_next/static|_next/image|favicon.ico).*)'],
};
```

### Server Component session access
```typescript
import { auth } from '@/auth';

export default async function Dashboard() {
  const session = await auth();
  if (!session) redirect('/login');
  return <div>Hello {session.user.name}</div>;
}
```

### Sign-in / sign-out Server Actions
```typescript
// app/auth/actions.ts
'use server';
import { signIn, signOut } from '@/auth';

export async function login(provider: string) {
  await signIn(provider, { redirectTo: '/dashboard' });
}

export async function logout() {
  await signOut({ redirectTo: '/' });
}
```

## Scaffolder Patterns
```
auth.ts                         # NextAuth config + exports
middleware.ts                   # route protection
app/
  api/auth/[...nextauth]/
    route.ts                    # Auth.js handler
  (auth)/
    login/page.tsx
    error/page.tsx
  dashboard/                    # protected area
```

## Additional Dos
- Store `AUTH_SECRET` in `.env.local`; rotate it via `npx auth secret`
- Use `session: { strategy: 'jwt' }` for stateless deployments (Vercel edge)
- Extend the `Session` type via module augmentation to add custom fields (`role`, `userId`)
- Use middleware for broad protection; use `auth()` in individual Server Components for fine-grained checks

## Additional Don'ts
- Don't access session in Client Components via `useSession` for security-critical checks — verify server-side
- Don't commit `AUTH_SECRET` or OAuth `CLIENT_SECRET` values to the repo
- Don't call `signIn()` / `signOut()` in Client Components directly — wrap in Server Actions
- Don't skip CSRF protection — Auth.js handles it; avoid custom session implementations
