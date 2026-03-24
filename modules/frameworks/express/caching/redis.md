# Express + Redis Caching

> Express-specific patterns for caching via ioredis. Extends generic Express conventions.

## Integration Setup

```bash
npm install ioredis connect-redis express-session
npm install --save-dev @types/ioredis
```

```typescript
// src/lib/redis.ts
import Redis from "ioredis";

export const redis = new Redis({
  host: process.env.REDIS_HOST ?? "localhost",
  port: Number(process.env.REDIS_PORT ?? 6379),
  password: process.env.REDIS_PASSWORD,
  db: 0,
  lazyConnect: true,
  maxRetriesPerRequest: 3,
  retryStrategy: (times) => Math.min(times * 50, 2000),
});
```

## Framework-Specific Patterns

### Cache middleware pattern

```typescript
// src/middleware/cache.ts
import { Request, Response, NextFunction } from "express";
import { redis } from "../lib/redis";

export function cacheMiddleware(ttlSeconds: number) {
  return async (req: Request, res: Response, next: NextFunction) => {
    const key = `cache:${req.method}:${req.originalUrl}`;
    const cached = await redis.get(key);
    if (cached) {
      res.setHeader("X-Cache", "HIT");
      return res.json(JSON.parse(cached));
    }
    // Intercept json() to populate cache
    const originalJson = res.json.bind(res);
    res.json = (body) => {
      if (res.statusCode < 400) {
        redis.setex(key, ttlSeconds, JSON.stringify(body)).catch(() => {});
      }
      res.setHeader("X-Cache", "MISS");
      return originalJson(body);
    };
    next();
  };
}
```

Usage:

```typescript
router.get("/products", cacheMiddleware(300), productController.list);
```

Cache invalidation helper:

```typescript
export async function invalidatePattern(pattern: string): Promise<void> {
  const keys = await redis.keys(pattern);
  if (keys.length > 0) await redis.del(...keys);
}
```

### Session store (connect-redis)

```typescript
// src/app.ts
import session from "express-session";
import { createClient } from "redis";
import { RedisStore } from "connect-redis";

const redisClient = createClient({ url: process.env.REDIS_URL });
await redisClient.connect();

app.use(session({
  store: new RedisStore({ client: redisClient }),
  secret: process.env.SESSION_SECRET!,
  resave: false,
  saveUninitialized: false,
  cookie: { secure: process.env.NODE_ENV === "production", httpOnly: true, maxAge: 86_400_000 },
}));
```

## Scaffolder Patterns

```
src/
  lib/
    redis.ts              # ioredis singleton
  middleware/
    cache.ts              # cacheMiddleware, invalidatePattern
  app.ts                  # session store wiring
```

## Dos

- Use `lazyConnect: true` and `retryStrategy` for resilience during startup race conditions
- Prefix all cache keys (e.g., `cache:`, `session:`) to namespace and simplify bulk invalidation
- Invalidate by pattern after write mutations to prevent stale reads
- Use a separate Redis database index (`db: 1`) or instance for sessions vs. application cache

## Don'ts

- Don't use `redis.keys("*")` in production hot paths — use `SCAN` for large keyspaces
- Don't share the ioredis client between session store and application cache without separate pools
- Don't block the event loop with synchronous fallback — all cache operations must be `await`ed
- Don't cache authenticated user-specific data without scoping the key to the user ID
