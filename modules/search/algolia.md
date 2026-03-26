# Algolia — Search Best Practices

## Overview

Algolia is a hosted search-as-a-service platform providing sub-100ms search with typo
tolerance, faceting, geo-search, and AI-powered relevance. Use it when you need instant
search without managing infrastructure, especially for e-commerce product search, site
search, and autocomplete. Algolia excels at out-of-the-box relevance and UI components
(InstantSearch). Avoid it for log aggregation, full-text document search with complex
boolean queries, or cost-sensitive applications with large datasets (pricing is per-search
and per-record).

## Architecture Patterns

### Index Design
```javascript
const algoliasearch = require("algoliasearch");
const client = algoliasearch("APP_ID", "ADMIN_API_KEY");
const index = client.initIndex("products");

// Configure index settings (do once, not per query)
await index.setSettings({
  searchableAttributes: ["name", "description", "brand", "category"],
  attributesForFaceting: ["filterOnly(tenant_id)", "searchable(category)", "brand", "price_range"],
  customRanking: ["desc(popularity)", "desc(rating)"],
  attributesToRetrieve: ["name", "price", "image_url", "category"],
  attributesToHighlight: ["name", "description"]
});
```

### Indexing Records
```javascript
// Batch indexing (recommended)
await index.saveObjects(products, { autoGenerateObjectIDIfNotExist: true });

// Partial update (only changed fields)
await index.partialUpdateObjects([
  { objectID: "prod_123", price: 79.99, in_stock: true }
]);
```

### Frontend Search (InstantSearch.js)
```javascript
import algoliasearch from "algoliasearch/lite";
import instantsearch from "instantsearch.js";
import { searchBox, hits, refinementList, pagination } from "instantsearch.js/es/widgets";

const search = instantsearch({
  indexName: "products",
  searchClient: algoliasearch("APP_ID", "SEARCH_ONLY_KEY")
});

search.addWidgets([
  searchBox({ container: "#search-box" }),
  hits({ container: "#hits", templates: { item: hitTemplate } }),
  refinementList({ container: "#categories", attribute: "category" }),
  pagination({ container: "#pagination" })
]);

search.start();
```

### Sync Pattern (Database → Algolia)
```javascript
// Webhook or change stream listener
async function onProductUpdated(product) {
  await index.partialUpdateObject({
    objectID: product.id,
    name: product.name,
    price: product.price,
    in_stock: product.inStock
  });
}

// Full reindex (periodic or on-demand)
async function fullReindex() {
  const tmpIndex = client.initIndex("products_tmp");
  await tmpIndex.setSettings(await index.getSettings());
  await tmpIndex.saveObjects(allProducts);
  await client.moveIndex("products_tmp", "products");  // atomic swap
}
```

### Anti-pattern — querying with backend proxy for every search: Algolia's frontend SDKs are designed for direct client-to-Algolia communication using search-only API keys. Adding a backend proxy adds latency and defeats the sub-100ms search experience. Use secured API keys for multi-tenant filtering.

## Configuration

**Relevance configuration (done once per index):**
```javascript
await index.setSettings({
  // Textual relevance
  searchableAttributes: [
    "unordered(name)",       // highest priority
    "unordered(description)", // lower priority
    "brand,category"          // same priority (comma = tie)
  ],

  // Business relevance (applied after textual)
  customRanking: ["desc(sales_count)", "desc(rating)"],

  // Typo tolerance
  minWordSizefor1Typo: 3,
  minWordSizefor2Typos: 7,

  // Deduplication
  distinct: 1,
  attributeForDistinct: "product_group_id"
});
```

**Replicas for different sort orders:**
```javascript
await index.setSettings({
  replicas: ["products_price_asc", "products_price_desc", "products_newest"]
});

// Configure each replica's ranking
const priceAsc = client.initIndex("products_price_asc");
await priceAsc.setSettings({ ranking: ["asc(price)", "typo", "geo", "words", "filters", "proximity", "attribute", "exact", "custom"] });
```

## Performance

**Use `attributesToRetrieve` to minimize response payload** — don't return fields only needed for indexing.

**Use `filterOnly()` facets** for attributes used in filters but never displayed as facets — saves CPU.

**Batch operations for indexing:** Always use `saveObjects` or `partialUpdateObjects` in batches (up to 1000 records per batch, 10MB max).

**Use virtual replicas** (Algolia v2) instead of standard replicas — they share the index and don't count toward record limits.

**Implement "search as you type" with debouncing:**
```javascript
// InstantSearch handles this automatically
// For custom implementations, debounce 200-300ms
```

## Security

**Never expose the Admin API key in frontend code.** Use the Search-Only API key for client-side search.

**Secured API keys for multi-tenant filtering:**
```javascript
const securedKey = client.generateSecuredApiKey("SEARCH_ONLY_KEY", {
  filters: "tenant_id:tenant_123",
  validUntil: Math.floor(Date.now() / 1000) + 3600
});
// Send securedKey to the frontend — it can only search within tenant_123
```

**Use `filterOnly()` for tenant_id:** Mark the tenant attribute as `filterOnly` so it's used for filtering but never exposed in facet values.

**Rate limiting:** Algolia has built-in rate limiting per API key. Monitor usage in the Algolia dashboard and set alerts for unusual spikes.

## Testing

```javascript
describe("Search", () => {
  beforeAll(async () => {
    const testIndex = client.initIndex("products_test");
    await testIndex.saveObjects(testProducts);
    await testIndex.setSettings(productSettings);
  });

  it("should find products with typos", async () => {
    const { hits } = await testIndex.search("headphnes");
    expect(hits.length).toBeGreaterThan(0);
    expect(hits[0].name).toContain("Headphones");
  });

  afterAll(async () => {
    await client.initIndex("products_test").delete();
  });
});
```

Use a separate Algolia application or index prefix for testing. Algolia offers a free tier suitable for test suites. Test relevance configuration by asserting expected result order for known queries.

## Dos
- Configure index settings (`searchableAttributes`, `customRanking`) before indexing records — order matters for relevance.
- Use secured API keys for multi-tenant applications — embed tenant filters to prevent cross-tenant data access.
- Use `partialUpdateObject` for incremental updates — don't re-index the full record when only price changes.
- Use InstantSearch UI libraries (React, Vue, Angular, vanilla JS) — they handle debouncing, caching, and UX patterns.
- Implement atomic reindexing with temporary index + `moveIndex` for zero-downtime full reindex.
- Use `attributesToRetrieve` to minimize response payload and improve search latency.
- Monitor search analytics in the Algolia dashboard — popular queries with no results indicate content gaps.

## Don'ts
- Don't expose the Admin API key in client-side code — it can modify and delete all data.
- Don't proxy every search through your backend — use Algolia's frontend SDKs with search-only keys for sub-100ms latency.
- Don't put settings changes in every search query — configure once via `setSettings`, query with `search`.
- Don't create one index per tenant — use a single index with `filterOnly(tenant_id)` and secured API keys.
- Don't index large text blobs (> 10KB per record) — Algolia charges per record and large records degrade search speed.
- Don't skip replicas for alternative sort orders — Algolia's ranking is baked into the index; you need replicas for price-asc vs relevance.
- Don't ignore Algolia's record and operation limits — pricing is per-search and per-record; unexpected spikes can be costly.
