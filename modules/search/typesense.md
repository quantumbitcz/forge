# Typesense — Search Best Practices

## Overview

Typesense is a fast, typo-tolerant, open-source search engine designed as a lightweight
alternative to Elasticsearch and Algolia. Use it for product search, autocomplete, faceted
navigation, and geo-search where sub-50ms latency and easy operation matter. Typesense
excels at instant search with typo tolerance out of the box. Avoid it for log aggregation
(use Elasticsearch/Loki), complex analytics (use ClickHouse), or when you need the full
Elasticsearch DSL for advanced query patterns.

## Architecture Patterns

### Collection Schema Design
```json
{
  "name": "products",
  "fields": [
    { "name": "name", "type": "string" },
    { "name": "description", "type": "string" },
    { "name": "price", "type": "float", "facet": true },
    { "name": "category", "type": "string", "facet": true },
    { "name": "brand", "type": "string", "facet": true },
    { "name": "rating", "type": "float", "sort": true },
    { "name": "in_stock", "type": "bool", "facet": true },
    { "name": "tags", "type": "string[]", "facet": true },
    { "name": "location", "type": "geopoint" },
    { "name": "created_at", "type": "int64", "sort": true }
  ],
  "default_sorting_field": "rating",
  "token_separators": ["-", "/"]
}
```

### Indexing Documents
```python
import typesense

client = typesense.Client({
    "api_key": "xyz",
    "nodes": [{"host": "ts.internal", "port": 8108, "protocol": "https"}],
    "connection_timeout_seconds": 2
})

# Batch import (JSONL — most efficient)
with open("products.jsonl") as f:
    client.collections["products"].documents.import_(f.read(), {"action": "upsert"})

# Single document
client.collections["products"].documents.upsert({
    "id": "prod_123",
    "name": "Wireless Headphones",
    "price": 79.99,
    "category": "Electronics",
    "rating": 4.5
})
```

### Search with Facets and Filtering
```python
results = client.collections["products"].documents.search({
    "q": "wireles headphnes",         # typo-tolerant by default
    "query_by": "name,description",
    "filter_by": "price:<100 && in_stock:true && category:Electronics",
    "sort_by": "rating:desc",
    "facet_by": "category,brand,price",
    "max_facet_values": 10,
    "per_page": 20,
    "page": 1
})
```

### Geo Search
```python
results = client.collections["stores"].documents.search({
    "q": "*",
    "filter_by": "location:(48.85, 2.35, 10 km)",  # within 10km of Paris
    "sort_by": "location(48.85, 2.35):asc"           # nearest first
})
```

### Anti-pattern — indexing large text blobs without `index: false` on non-searchable fields: Every indexed field consumes memory. If a field is only used for display (not search or filter), set `"index": false` to exclude it from the search index.

## Configuration

**HA Cluster (3-node minimum):**
```bash
# Node 1
typesense-server --data-dir /data --api-key=xyz --api-port 8108 \
  --peering-address 10.0.1.1 --peering-port 8107 \
  --nodes /etc/typesense/nodes.txt

# nodes.txt
10.0.1.1:8107:8108,10.0.1.2:8107:8108,10.0.1.3:8107:8108
```

**Docker Compose:**
```yaml
typesense:
  image: typesense/typesense:27.1
  ports: ["8108:8108"]
  volumes: ["typesense-data:/data"]
  command: --data-dir /data --api-key=xyz --enable-cors
```

**Search-only API key (for frontend):**
```python
client.keys.create({
    "description": "Search-only key",
    "actions": ["documents:search"],
    "collections": ["products"]
})
```

## Performance

**Use `query_by` weights for relevance tuning:**
```python
{ "query_by": "name,description,tags", "query_by_weights": "3,1,2" }
```

**Prefix search for autocomplete:**
```python
{ "q": "wire", "query_by": "name", "prefix": "true", "per_page": 5 }
```

**Use `exclude_fields` to reduce response size:**
```python
{ "q": "headphones", "query_by": "name", "exclude_fields": "description,embedding" }
```

**Synonyms for better recall:**
```python
client.collections["products"].synonyms.upsert("headphone-synonyms", {
    "synonyms": ["headphones", "earphones", "earbuds", "headset"]
})
```

**Memory sizing:** Typesense keeps the index in RAM. Plan for 2-3x the raw data size in memory. Use `index: false` on display-only fields to reduce memory footprint.

## Security

**Use scoped API keys for frontend search:**
```python
# Scoped key — can only search products, expires in 1 hour
scoped_key = client.keys.generate_scoped_search_key(
    search_key, {"filter_by": "tenant_id:tenant_123", "expires_at": int(time.time()) + 3600}
)
```

**Never expose the admin API key to the client.** Use search-only or scoped keys for frontend applications.

**Enable HTTPS** in production — Typesense supports TLS natively or behind a reverse proxy.

**Network isolation:** Typesense peering traffic (port 8107) should be on a private network. Only expose the API port (8108) through a load balancer.

## Testing

```python
import typesense
import pytest

@pytest.fixture
def ts_client():
    client = typesense.Client({"api_key": "test", "nodes": [{"host": "localhost", "port": 8108, "protocol": "http"}]})
    client.collections.create(schema)
    yield client
    client.collections["products"].delete()

def test_typo_tolerant_search(ts_client):
    ts_client.collections["products"].documents.create({"id": "1", "name": "Headphones", "rating": 4.5})
    results = ts_client.collections["products"].documents.search({"q": "hedphones", "query_by": "name"})
    assert results["found"] == 1
```

Use a local Typesense Docker container for integration tests. Test typo tolerance, faceted filtering, and geo queries explicitly. Verify that scoped API keys restrict access correctly.

## Dos
- Use JSONL batch import for initial indexing — it's 10-100x faster than individual document inserts.
- Use scoped API keys for multi-tenant search — embed tenant filters in the key to prevent cross-tenant data leaks.
- Set `default_sorting_field` on collections — Typesense requires it for relevance scoring.
- Use `query_by_weights` to boost important fields (title > description > tags).
- Mark display-only fields with `"index": false` to reduce memory usage.
- Use synonyms to improve recall for domain-specific vocabulary.
- Monitor memory usage — Typesense keeps indexes in RAM, and OOM kills lose uncommitted data.

## Don'ts
- Don't expose the admin API key in frontend code — use search-only or scoped keys.
- Don't index every field — non-searchable display fields should have `"index": false`.
- Don't use Typesense for log aggregation or analytics — it's optimized for search, not aggregation.
- Don't skip schema definition — Typesense requires explicit schemas (no schemaless mode).
- Don't store large binary data in Typesense — store references to external storage.
- Don't ignore memory requirements — Typesense needs all indexed data in RAM for sub-50ms latency.
- Don't use auto-schema detection in production — explicit schemas prevent type mismatches and ensure consistent indexing.
