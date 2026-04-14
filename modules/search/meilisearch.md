# Meilisearch — Search Best Practices

## Overview

Meilisearch is a fast, typo-tolerant search engine designed for developer experience and end-user
relevance. Use it for product search, documentation search, and any user-facing search where
instant results (< 50 ms), typo tolerance, and faceted filtering matter more than complex
analytics. Meilisearch is not suited for log analytics, full aggregation pipelines, or queries
over billions of documents — use Elasticsearch/OpenSearch for those workloads.

## Architecture Patterns

### Index Configuration (Settings)
Configure all settings before indexing documents — changing settings triggers reindexing:
```json
PATCH /indexes/products/settings
{
  "searchableAttributes": ["name", "description", "brand", "tags"],
  "filterableAttributes": ["category", "brand", "price", "in_stock", "tags"],
  "sortableAttributes": ["price", "created_at", "popularity_score"],
  "displayedAttributes": ["id", "name", "price", "brand", "category", "thumbnail_url"],
  "rankingRules": ["words", "typo", "proximity", "attribute", "sort", "exactness"],
  "stopWords": ["the", "a", "an", "in", "on", "at", "for"],
  "typoTolerance": {
    "enabled": true,
    "minWordSizeForTypos": { "oneTypo": 5, "twoTypos": 9 },
    "disableOnWords": ["sku", "isbn"]
  }
}
```

`searchableAttributes` order matters — attributes listed first receive higher relevance weight.
Only list attributes that users actually search on; every listed attribute increases index size.

### Faceted Search
```json
POST /indexes/products/search
{
  "q": "running shoes",
  "filter": "category = 'footwear' AND price 50 TO 200 AND in_stock = true",
  "facets": ["category", "brand", "tags"],
  "sort": ["price:asc"],
  "limit": 20,
  "offset": 0
}
```
Response includes `facetDistribution` — the count of matching documents per facet value, ready
for rendering filter UI checkboxes without an additional query.

### Multi-Index Search (Federated Search)
```json
POST /multi-search
{
  "queries": [
    { "indexUid": "products",       "q": "apple",  "limit": 5 },
    { "indexUid": "blog-posts",     "q": "apple",  "limit": 3 },
    { "indexUid": "documentation",  "q": "apple",  "limit": 3 }
  ]
}
```
Multi-search executes all queries in parallel and returns results per index in a single round-trip.
Use for universal search bars that span multiple content types.

### Typo Tolerance Customization
```json
PATCH /indexes/products/settings/typo-tolerance
{
  "enabled": true,
  "minWordSizeForTypos": {
    "oneTypo": 4,    // "shoe" (4 chars) allows 1 typo
    "twoTypos": 8    // "sneakers" (8 chars) allows 2 typos
  },
  "disableOnAttributes": ["sku", "barcode"],  // exact match only for identifiers
  "disableOnWords": ["iPhone", "MacOS"]       // brand names — disable fuzzy matching
}
```

### Ranking Rules Customization
Default: `["words", "typo", "proximity", "attribute", "sort", "exactness"]`

Customizing for e-commerce (boost popularity):
```json
PATCH /indexes/products/settings/ranking-rules
["words", "typo", "proximity", "attribute", "sort", "exactness", "popularity_score:desc"]
```
Custom ranking rules reference numeric attributes — they act as a final tiebreaker after all
built-in rules. Do not put `sort` last — it overrides user-selected sorts only when explicitly
requested, it does not run automatically.

### API Key Management
```bash
# Create a search-only key scoped to specific indexes
curl -X POST 'http://localhost:7700/keys' \
  -H 'Authorization: Bearer MASTER_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "description": "Frontend search key",
    "actions": ["search"],
    "indexes": ["products", "blog-posts"],
    "expiresAt": "2027-01-01T00:00:00Z"
  }'
```
The master key must never be exposed to frontend clients. Create a scoped search-only key per
frontend application; rotate keys on a schedule.

### Synonyms
```json
PATCH /indexes/products/settings/synonyms
{
  "sneaker":  ["shoe", "trainer", "athletic footwear"],
  "tv":       ["television", "screen"],
  "iphone":   ["apple phone", "ios phone"]
}
```

## Configuration

```toml
# config.toml
env = "production"
master_key = "${MEILISEARCH_MASTER_KEY}"   # from environment, never hardcoded
db_path = "/var/lib/meilisearch/data"
http_addr = "127.0.0.1:7700"              # bind to localhost; put a reverse proxy in front
max_indexing_memory = "2 GiB"
max_indexing_threads = 4
```

**Persistent volume:** Meilisearch stores its index on disk — mount a persistent volume in
containerized deployments. Default data directory is `./data.ms`.

## Performance

- `searchableAttributes` order directly impacts relevance and index size — list only what users search on.
- For bulk initial indexing, use batches of 1 000–10 000 documents per `POST /indexes/{uid}/documents` call.
- Task polling: Meilisearch operations are async — poll `GET /tasks/{taskUid}` or use `waitForTask`.
- Limit `displayedAttributes` to fields needed by the UI — omitting large text fields reduces response size.
- Use `attributesToRetrieve` in search requests to further narrow the response payload.

## Security

- Never expose port 7700 directly to the internet — place Meilisearch behind a reverse proxy (nginx/Caddy).
- Rotate the master key on a regular schedule and immediately on suspected compromise.
- Use tenant tokens for multi-tenant deployments to enforce per-user filter constraints server-side:
  ```javascript
  const tenantToken = await client.generateTenantToken(
    apiKeyUid,
    { searchRules: { "products": { "filter": `tenant_id = ${userId}` } } },
    { expiresAt: new Date(Date.now() + 3600_000) }
  );
  ```
- Tenant tokens bake the filter into the JWT — the frontend cannot bypass the tenant constraint.

## Testing

```python
# Integration test with a real Meilisearch instance (Testcontainers)
from testcontainers.core.container import DockerContainer

with DockerContainer("getmeili/meilisearch:v1.7").with_exposed_ports(7700) as mc:
    url = f"http://{mc.get_container_host_ip()}:{mc.get_exposed_port(7700)}"
    client = meilisearch.Client(url)
    index = client.index("test-products")
    index.add_documents([{"id": 1, "name": "Running Shoes"}])
    client.wait_for_task(task["taskUid"])
    results = index.search("running")
    assert results["hits"][0]["id"] == 1
```

## Dos
- Configure all settings (`searchableAttributes`, `filterableAttributes`, etc.) before indexing data.
- Use scoped API keys with minimal permissions for each client (frontend, backend, admin).
- Use tenant tokens for multi-tenant search to enforce data isolation at the search engine level.
- Monitor task queue — failed tasks surface indexing errors that would otherwise be silent.
- Keep documents under 100 KB; store large content in object storage and index a summary.

## Don'ts
- Don't expose the master key to frontend clients — always use a scoped search-only API key.
- Don't use Meilisearch for analytics aggregations or log analysis — it lacks aggregation pipelines.
- Don't change `filterableAttributes` without planning for the reindex time — it can be minutes to hours.
- Don't index sensitive PII without considering that search results are plaintext in API responses.
- Don't rely on Meilisearch as a source of truth — always sync from a primary database.
