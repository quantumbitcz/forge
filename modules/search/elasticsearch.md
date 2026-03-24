# Elasticsearch — Search Best Practices

## Overview

Elasticsearch is a distributed search and analytics engine built on Apache Lucene. Use it for
full-text search, faceted navigation, log aggregation, and real-time analytics. Elasticsearch
excels at complex query DSL, aggregations, and geospatial queries. Avoid using it as a primary
database — it is eventually consistent, lacks transactional semantics, and requires a separate
source of truth. Always write to the primary store first, then propagate to Elasticsearch.

## Architecture Patterns

### Index Design
```json
// One index per entity type — do not mix entity types in a single index
PUT /products
PUT /orders
PUT /users

// Time-series data: use index aliases and rollover
PUT /logs-2026.03
PUT /_aliases
{
  "actions": [{ "add": { "index": "logs-2026.03", "alias": "logs-current", "is_write_index": true } }]
}
```
Use ILM (Index Lifecycle Management) to automate rollover, shrink, and delete phases for time-series.

### Mapping — Keyword vs Text
```json
PUT /products/_mapping
{
  "properties": {
    "name":        { "type": "text", "analyzer": "english" },
    "name_exact":  { "type": "keyword" },   // for exact match, sorting, aggregations
    "sku":         { "type": "keyword" },   // identifiers — always keyword
    "price":       { "type": "scaled_float", "scaling_factor": 100 },
    "tags":        { "type": "keyword" },
    "description": { "type": "text", "analyzer": "english", "index_options": "offsets" },
    "category": {
      "type": "nested",                     // nested: independent scoring per element
      "properties": {
        "id":   { "type": "keyword" },
        "name": { "type": "text" }
      }
    }
  }
}
```
Use `keyword` for IDs, categories, statuses, and any field used in aggregations or exact-match filters.
Use `text` for full-text search fields. Avoid `nested` for frequently updated arrays — prefer `object`
when independent per-element scoring is not needed.

### Custom Analyzers
```json
PUT /products/_settings
{
  "analysis": {
    "analyzer": {
      "product_search": {
        "type": "custom",
        "tokenizer": "standard",
        "filter": ["lowercase", "asciifolding", "product_synonym", "english_stemmer"]
      }
    },
    "filter": {
      "product_synonym": {
        "type": "synonym",
        "synonyms_path": "analysis/synonyms.txt"
      },
      "english_stemmer": { "type": "stemmer", "language": "english" }
    }
  }
}
```

### Query DSL — bool/must/should/filter
```json
{
  "query": {
    "bool": {
      "must":   [{ "match": { "name": "running shoes" } }],
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "price": { "gte": 50, "lte": 200 } } }
      ],
      "should": [
        { "term": { "tags": "sale" } }
      ],
      "minimum_should_match": 0
    }
  }
}
```
Always put non-scoring conditions in `filter` (not `must`) — filter results are cached by Elasticsearch
and do not affect relevance scoring.

### Aggregations
```json
{
  "aggs": {
    "by_category": {
      "terms": { "field": "category.id", "size": 20 },
      "aggs": {
        "avg_price": { "avg": { "field": "price" } },
        "price_ranges": {
          "range": {
            "field": "price",
            "ranges": [{"to": 50}, {"from": 50, "to": 200}, {"from": 200}]
          }
        }
      }
    }
  },
  "size": 0   // aggregations only — skip hits when count not needed
}
```

### Bulk Indexing
```python
from elasticsearch.helpers import bulk, streaming_bulk

actions = (
    {"_index": "products", "_id": p["id"], "_source": p}
    for p in product_generator()
)
success, errors = bulk(es, actions, chunk_size=500, request_timeout=60)
```
Always use the bulk API for indexing more than one document. Single-document indexing is 10-50x
slower for large datasets.

### Reindex API
```json
POST /_reindex?slices=auto&wait_for_completion=false
{
  "source": { "index": "products-v1", "size": 500 },
  "dest":   { "index": "products-v2", "op_type": "create" }
}
```

## Configuration

**Cluster sizing (production baseline):**
- Minimum 3 dedicated master-eligible nodes; never an even number (split-brain).
- Data nodes: size based on storage; 30 GB heap ceiling (JVM limitation).
- Heap: 50% of RAM up to 30 GB; leave the other 50% for the OS filesystem cache.
- Shard sizing target: 10–50 GB per shard; avoid > 200 MB/s indexing throughput per shard.

```yaml
# elasticsearch.yml
cluster.name: production
node.roles: [ data, ingest ]        # dedicated master nodes have only [master]
bootstrap.memory_lock: true         # prevent heap from swapping to disk
indices.memory.index_buffer_size: 20%
```

## Performance

- Use `filter` context for non-scoring conditions — cached and much faster than `must`.
- Avoid wildcard queries on `text` fields — use edge-ngram analyzers for prefix search instead.
- Disable `_source` on indexes where you only need aggregations (analytics-only indexes).
- Use `search_after` for deep pagination instead of `from`/`size` (which is O(from + size)).
- Refresh interval default is 1 second — increase to `30s` during bulk indexing:
  ```json
  PUT /products/_settings { "index.refresh_interval": "30s" }
  ```
- Monitor: shard count, JVM heap usage, indexing latency, search latency, rejected threads.

## Security

- Use TLS for transport (node-to-node) and HTTP (client) in production.
- Role-based access control: grant index-level `read` to search services, `write` to indexers only.
- Never expose Elasticsearch port 9200 to the public internet — put an API gateway or proxy in front.
- Use field-level security to hide sensitive fields from unauthorized roles.

## Testing

```python
# Testcontainers for integration tests
from testcontainers.elasticsearch import ElasticsearchContainer

with ElasticsearchContainer("elasticsearch:8.12.0") as es_container:
    es = Elasticsearch(es_container.get_url())
    es.indices.create(index="test-products", mappings=test_mapping)
    es.index(index="test-products", id="1", document={"name": "Test Shoe"})
    es.indices.refresh(index="test-products")
    result = es.search(index="test-products", query={"match": {"name": "shoe"}})
    assert result["hits"]["total"]["value"] == 1
```

## Dos
- Keep shard count small (1 shard per 10-50 GB of data); over-sharding degrades performance.
- Always use `filter` context for boolean/range/term conditions that do not affect scoring.
- Use the bulk API for any indexing batch larger than one document.
- Set `index.number_of_replicas: 0` during initial bulk load, then restore replicas afterward.
- Design mappings before indexing — changing field types requires a full reindex.

## Don'ts
- Don't use Elasticsearch as a primary database — it is not transactional and can lose data.
- Don't use `from`/`size` for deep pagination (past 10 000 hits) — use `search_after` with a sort.
- Don't store unbounded `nested` arrays — they create one Lucene document per element.
- Don't deploy fewer than 3 master-eligible nodes in production — even numbers risk split-brain.
- Don't set heap above 30 GB — JVM compressed OOPs stop working above ~32 GB and performance degrades.
