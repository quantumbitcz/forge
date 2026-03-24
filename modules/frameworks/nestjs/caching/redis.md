# NestJS + Redis Caching

> NestJS-specific patterns for caching via `@nestjs/cache-manager` with a Redis store.
> Extends generic NestJS conventions.

## Integration Setup

```bash
npm install @nestjs/cache-manager cache-manager @keyv/redis cacheable
```

> `@nestjs/cache-manager` v2+ uses `cache-manager` v5 which has a new adapter API.
> Use `@keyv/redis` (not `cache-manager-redis-store`) for Redis support.

## CacheModule Registration

```typescript
// app.module.ts
@Module({
  imports: [
    CacheModule.registerAsync({
      isGlobal: true,
      inject: [ConfigService],
      useFactory: async (config: ConfigService) => ({
        stores: [
          new KeyvAdapter(new Keyv({
            store: new KeyvRedis(config.get<string>('REDIS_URL')),
            ttl: config.get<number>('CACHE_TTL_SECONDS', 300) * 1000,
          })),
        ],
      }),
    }),
  ],
})
export class AppModule {}
```

## Service-Level Caching

Inject `CACHE_MANAGER` directly for programmatic cache operations:

```typescript
import { CACHE_MANAGER } from '@nestjs/cache-manager';
import { Cache } from 'cache-manager';

@Injectable()
export class ProductsService {
  private readonly logger = new Logger(ProductsService.name);

  constructor(
    @Inject(CACHE_MANAGER) private readonly cache: Cache,
    private readonly productsRepo: ProductsRepository,
  ) {}

  async findOne(id: string): Promise<ProductDto> {
    const cacheKey = `product:${id}`;

    const cached = await this.cache.get<ProductDto>(cacheKey);
    if (cached) {
      this.logger.debug(`Cache HIT for ${cacheKey}`);
      return cached;
    }

    const product = await this.productsRepo.findById(id);
    if (!product) throw new NotFoundException(`Product ${id} not found`);

    const dto = plainToInstance(ProductDto, product);
    await this.cache.set(cacheKey, dto, 300);   // TTL in seconds
    return dto;
  }

  async update(id: string, dto: UpdateProductDto): Promise<ProductDto> {
    const updated = await this.productsRepo.update(id, dto);
    await this.cache.del(`product:${id}`);       // invalidate on write
    return plainToInstance(ProductDto, updated);
  }
}
```

## Decorator-Based Caching (Controller Level)

```typescript
// Simple GET endpoint caching via @UseInterceptors(CacheInterceptor)
@Controller('products')
@UseInterceptors(CacheInterceptor)
export class ProductsController {
  @Get(':id')
  @CacheKey('product-detail')
  @CacheTTL(300)
  findOne(@Param('id', ParseUUIDPipe) id: string) {
    return this.productsService.findOne(id);
  }

  // Skip cache for this endpoint
  @Get('search')
  @CacheKey('product-search')
  @CacheTTL(0)
  search(@Query('q') q: string) {
    return this.productsService.search(q);
  }
}
```

> Prefer service-level caching over `CacheInterceptor` for write-through invalidation and user-scoped keys.

## Cache Key Strategies

```typescript
// Namespace cache keys to avoid collisions
const cacheKey = `products:${tenantId}:${productId}`;

// User-scoped caching
const userKey = `user:${userId}:profile`;

// Pattern-based invalidation
async invalidateProductCache(productId: string): Promise<void> {
  // Invalidate specific key
  await this.cache.del(`product:${productId}`);
  // Invalidate list caches (if using Redis directly for SCAN)
  // Use specific keys per page rather than wildcard scans
}
```

## Health Check

```typescript
// Using @nestjs/terminus
@Get('health')
@HealthCheck()
check() {
  return this.health.check([
    () => this.microserviceHealth.pingCheck('redis', {
      transport: Transport.REDIS,
      options: { host: 'localhost', port: 6379 },
    }),
  ]);
}
```

## Scaffolder Patterns

```
src/
  app.module.ts                      # CacheModule.registerAsync global registration
  products/
    products.service.ts              # @Inject(CACHE_MANAGER) + cache.get/set/del
    products.controller.ts           # Optional @UseInterceptors(CacheInterceptor)
```

## Dos

- Use `isGlobal: true` on `CacheModule` so all feature modules can inject `CACHE_MANAGER`
- Prefix all cache keys with a namespace (`product:`, `user:`) for easy invalidation and debugging
- Invalidate cache immediately after write mutations — never serve stale data from a write path
- Use separate TTLs for different entity types based on data freshness requirements

## Don'ts

- Don't use `CacheInterceptor` for user-specific data without scoping the cache key to the user ID
- Don't cache data that contains sensitive personal information without encryption or strict TTLs
- Don't use wildcard Redis key scanning (`KEYS *`) in production — it blocks Redis; use explicit key tracking
- Don't use `cache-manager-redis-store` — it is incompatible with `cache-manager` v5; use `@keyv/redis`
