# Next.js + Redis (ioredis)

> Next.js caching patterns with ioredis. Covers ISR cache backing, on-demand revalidation, and `unstable_cache` wrapping.

## Integration Setup

```bash
npm install ioredis
```

```typescript
// lib/redis.ts
import Redis from 'ioredis';

const globalForRedis = globalThis as unknown as { redis: Redis };

export const redis =
  globalForRedis.redis ??
  new Redis(process.env.REDIS_URL!, { maxRetriesPerRequest: 3 });

if (process.env.NODE_ENV !== 'production') globalForRedis.redis = redis;
```

## Framework-Specific Patterns

### `unstable_cache` with Redis backing
Wrap expensive queries in `unstable_cache`; populate Redis for cross-request sharing:
```typescript
// lib/cache.ts
import { unstable_cache } from 'next/cache';
import { redis } from './redis';

export function cachedQuery<T>(
  key: string,
  fn: () => Promise<T>,
  ttlSeconds = 60,
  tags: string[] = []
) {
  return unstable_cache(
    async () => {
      const cached = await redis.get(key);
      if (cached) return JSON.parse(cached) as T;
      const result = await fn();
      await redis.setex(key, ttlSeconds, JSON.stringify(result));
      return result;
    },
    [key],
    { tags, revalidate: ttlSeconds }
  );
}
```

### On-demand revalidation via Route Handler
```typescript
// app/api/revalidate/route.ts
import { revalidateTag } from 'next/cache';
import { NextRequest, NextResponse } from 'next/server';
import { redis } from '@/lib/redis';

export async function POST(req: NextRequest) {
  const { tag, secret } = await req.json();
  if (secret !== process.env.REVALIDATION_SECRET) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  await redis.del(`cache:${tag}`);
  revalidateTag(tag);
  return NextResponse.json({ revalidated: true });
}
```

### Session store (alternative to next-auth default)
```typescript
// Use ioredis as next-auth session adapter or manual cookie sessions
await redis.setex(`session:${sessionId}`, 3600, JSON.stringify(sessionData));
const session = await redis.get(`session:${sessionId}`);
```

## Scaffolder Patterns
```
lib/
  redis.ts          # singleton client
  cache.ts          # cachedQuery helper
app/
  api/
    revalidate/
      route.ts      # webhook-driven on-demand revalidation
```

## Dos
- Use the `globalThis` singleton in dev to avoid connection exhaustion under hot reload
- Namespace Redis keys by resource: `users:${id}`, `products:list`
- Always set a TTL (`setex`); never use `set` without expiry for cache entries
- Pair `revalidateTag` with Redis key deletion so both Next.js cache and Redis stay in sync

## Don'ts
- Don't use Redis in Client Components or middleware edge runtime without verifying ioredis edge support (use `@upstash/redis` for edge)
- Don't cache mutable user-specific data without scoping keys to the user
- Don't let Redis connection errors crash the app — catch and fall through to the uncached path
- Don't store sensitive data unencrypted in Redis
