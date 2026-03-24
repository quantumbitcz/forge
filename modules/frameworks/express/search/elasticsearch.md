# Express + Elasticsearch

> Express-specific patterns for full-text search via @elastic/elasticsearch. Extends generic Express conventions.

## Integration Setup

```bash
npm install @elastic/elasticsearch
npm install --save-dev @elastic/elasticsearch   # types are bundled
```

```typescript
// src/lib/elasticsearch.ts
import { Client } from "@elastic/elasticsearch";

export const es = new Client({
  node: process.env.ES_NODE ?? "http://localhost:9200",
  auth: process.env.ES_API_KEY
    ? { apiKey: process.env.ES_API_KEY }
    : { username: process.env.ES_USER ?? "elastic", password: process.env.ES_PASSWORD ?? "" },
  tls: { rejectUnauthorized: process.env.NODE_ENV === "production" },
  requestTimeout: 10_000,
  maxRetries: 3,
});
```

## Framework-Specific Patterns

### Search endpoint

```typescript
// src/routes/search.ts
import { es } from "../lib/elasticsearch";
import { Request, Response, NextFunction } from "express";

router.get("/search", async (req: Request, res: Response, next: NextFunction) => {
  const { q, category, page = "1", size = "20" } = req.query as Record<string, string>;
  const from = (Number(page) - 1) * Number(size);

  try {
    const result = await es.search({
      index: "products",
      from,
      size: Number(size),
      query: {
        bool: {
          must: q ? { multi_match: { query: q, fields: ["name^2", "description"] } } : { match_all: {} },
          filter: category ? [{ term: { category } }] : [],
        },
      },
      highlight: { fields: { name: {} } },
    });

    res.json({
      total: (result.hits.total as any).value,
      hits: result.hits.hits.map((h) => ({ ...h._source, highlights: h.highlight })),
    });
  } catch (err) {
    next(err);
  }
});
```

### Bulk indexing helper

```typescript
// src/search/indexer.ts
import { es } from "../lib/elasticsearch";

export async function bulkIndex<T extends { id: string }>(
  index: string,
  docs: T[]
): Promise<void> {
  if (docs.length === 0) return;
  const body = docs.flatMap((doc) => [
    { index: { _index: index, _id: doc.id } },
    doc,
  ]);
  const { errors, items } = await es.bulk({ body, refresh: false });
  if (errors) {
    const failed = items.filter((i) => i.index?.error);
    throw new Error(`Bulk index failed for ${failed.length} docs`);
  }
}
```

### Index lifecycle (create with mapping)

```typescript
export async function ensureIndex(index: string, mappings: object): Promise<void> {
  const exists = await es.indices.exists({ index });
  if (!exists) {
    await es.indices.create({ index, mappings, settings: { number_of_shards: 1 } });
  }
}
```

## Scaffolder Patterns

```
src/
  lib/
    elasticsearch.ts      # Client singleton
  search/
    indexer.ts            # bulkIndex, ensureIndex helpers
  routes/
    search.ts             # search endpoint(s)
```

## Dos

- Use `requestTimeout` and `maxRetries` to bound latency and handle transient ES node restarts
- Use `from`/`size` for simple pagination; switch to `search_after` (PIT) for deep pagination > 10 000
- Always specify `index` explicitly — avoid cross-index wildcard queries in production
- Handle `errors: true` in bulk responses — partial failures do NOT throw by default

## Don'ts

- Don't use `refresh: true` on bulk index in hot paths — it forces a segment merge and hurts write throughput
- Don't return raw `_source` without sanitizing — strip internal/private fields before sending to clients
- Don't perform ES queries inside request middleware — delegate to a dedicated search service layer
- Don't ignore `tls.rejectUnauthorized` — set it to `true` in production even for self-signed certs (provide the CA)
