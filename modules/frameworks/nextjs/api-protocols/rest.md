# Next.js REST — API Protocol Binding

> Next.js App Router REST patterns. Route Handlers replace the Pages Router `pages/api/` approach.

## Integration Setup
- Built-in `NextRequest` / `NextResponse` — no additional packages needed
- Validation: `zod` for request bodies; `@conform-to/zod` for Server Action forms
- OpenAPI: `next-swagger-doc` or manual `swagger.json` served at `/api/docs`

## Framework-Specific Patterns
- Route Handlers live at `app/api/{resource}/route.ts`; name the exported function after the HTTP verb (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`)
- Dynamic segments: `app/api/users/[id]/route.ts` — receive `{ params }` as second argument
- Use `NextResponse.json(data, { status })` for all responses; set `Content-Type` automatically
- Middleware (`middleware.ts` at project root) runs on matched paths before Route Handlers — use for auth, rate-limiting, and request ID injection
- Typed responses: define a `ResponseBody` type and wrap `NextResponse.json<ResponseBody>(...)`
- Force dynamic evaluation when the handler reads headers/cookies: `export const dynamic = 'force-dynamic'`

```typescript
// app/api/users/[id]/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';

const UpdateSchema = z.object({ name: z.string().min(1) });

export async function PATCH(
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  const body = UpdateSchema.safeParse(await req.json());
  if (!body.success) return NextResponse.json({ error: body.error.flatten() }, { status: 400 });
  // ... update logic
  return NextResponse.json(updated);
}
```

### Middleware example
```typescript
// middleware.ts
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(req: NextRequest) {
  const res = NextResponse.next();
  res.headers.set('x-request-id', crypto.randomUUID());
  return res;
}

export const config = { matcher: '/api/:path*' };
```

## Scaffolder Patterns
```
app/
  api/
    users/
      route.ts            # GET (list), POST (create)
      [id]/
        route.ts          # GET, PATCH, DELETE
middleware.ts             # auth + request-id
lib/
  api-response.ts         # typed NextResponse helpers
  errors.ts               # AppError → NextResponse mapping
```

## Dos
- Export only the HTTP methods your endpoint supports — Next.js returns 405 for unimplemented methods automatically
- Validate with `zod.safeParse` and return 400 before any business logic
- Use `middleware.ts` matcher for route-level auth rather than repeating checks in every handler
- Return RFC 7807 error shapes: `{ title, status, detail }`

## Don'ts
- Don't mix Server Actions and Route Handlers for the same mutation — pick one per resource
- Don't use `pages/api/` in App Router projects; migrate to `app/api/`
- Don't return raw database errors to clients
- Don't use `export const runtime = 'edge'` unless you've verified all dependencies support edge
