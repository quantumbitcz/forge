# NestJS + Elasticsearch (@nestjs/elasticsearch)

> Full-text search integration with the official NestJS Elasticsearch module.

## Integration Setup

```bash
npm install @nestjs/elasticsearch @elastic/elasticsearch
```

```typescript
// app.module.ts
import { ElasticsearchModule } from '@nestjs/elasticsearch';

@Module({
  imports: [
    ElasticsearchModule.registerAsync({
      useFactory: (config: ConfigService) => ({
        node: config.get('ELASTICSEARCH_URL'),
        auth: { username: 'elastic', password: config.get('ELASTICSEARCH_PASSWORD')! },
        tls: { rejectUnauthorized: config.get('NODE_ENV') === 'production' },
      }),
      inject: [ConfigService],
    }),
  ],
})
export class AppModule {}
```

## Framework-Specific Patterns

### Search service
```typescript
// products/products.search.service.ts
import { Injectable } from '@nestjs/common';
import { ElasticsearchService } from '@nestjs/elasticsearch';

@Injectable()
export class ProductsSearchService {
  constructor(private readonly es: ElasticsearchService) {}

  async index(product: Product) {
    await this.es.index({
      index: 'products',
      id: product.id,
      document: { name: product.name, description: product.description, price: product.price },
    });
  }

  async search(query: string) {
    const result = await this.es.search<Product>({
      index: 'products',
      query: {
        multi_match: { query, fields: ['name^3', 'description'] },
      },
    });
    return result.hits.hits.map((h) => h._source!);
  }

  async remove(id: string) {
    await this.es.delete({ index: 'products', id });
  }
}
```

### Index management on module init
```typescript
// products/products.module.ts
@Module({
  imports: [ElasticsearchModule],
  providers: [ProductsSearchService, ProductsIndexInitializer],
})
export class ProductsModule {}

@Injectable()
export class ProductsIndexInitializer implements OnModuleInit {
  constructor(private readonly es: ElasticsearchService) {}

  async onModuleInit() {
    const exists = await this.es.indices.exists({ index: 'products' });
    if (!exists) {
      await this.es.indices.create({
        index: 'products',
        mappings: {
          properties: {
            name: { type: 'text', analyzer: 'standard' },
            description: { type: 'text' },
            price: { type: 'float' },
          },
        },
      });
    }
  }
}
```

## Scaffolder Patterns
```
src/
  products/
    products.search.service.ts    # ES search/index/delete
    products.index.initializer.ts # onModuleInit index setup
    products.service.ts           # orchestrates DB + ES sync
    products.module.ts
```

## Dos
- Register `ElasticsearchModule` as `@Global()` in a shared module if multiple feature modules need it
- Create indices with explicit mappings in `onModuleInit` rather than relying on dynamic mapping
- Keep ES sync in the application service — update both DB and ES in sequence (DB first, ES second)
- Use `_source` exclusion to avoid returning large blobs; project only what the client needs

## Don'ts
- Don't inject `ElasticsearchService` directly into controllers — go through a dedicated search service
- Don't rely on ES as the primary data store; use it as a read projection of your primary DB
- Don't use dynamic mapping in production — set explicit `properties` for index fields
- Don't swallow ES errors silently; failing to index should be logged and retried
