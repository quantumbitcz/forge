# OpenSearch — Search Best Practices

## Overview

OpenSearch is the AWS-maintained fork of Elasticsearch (post-7.10), developed as an Apache 2.0
open-source alternative. It shares the same core query DSL and index API as Elasticsearch 7.x
but adds built-in security, Index State Management (ISM), ML Commons, and observability plugins
without requiring a commercial license. Use OpenSearch when deploying on AWS (managed via Amazon
OpenSearch Service), when the built-in security plugin eliminates the X-Pack dependency, or when
ISM policies replace the need for a separate ILM orchestration layer.

## Architecture Patterns

### Security Plugin (Built-In)
OpenSearch ships with the security plugin enabled by default — no separate license required:
```yaml
# opensearch.yml
plugins.security.ssl.transport.enforce_hostname_verification: true
plugins.security.ssl.http.enabled: true
plugins.security.allow_unsafe_democertificates: false
plugins.security.nodes_dn:
  - "CN=node1.example.com,OU=ops,O=example,C=US"
```
Configure roles via the REST API or the OpenSearch Dashboards security plugin:
```bash
curl -XPUT -u admin:password "https://cluster:9200/_plugins/_security/api/roles/search_reader" \
  -H "Content-Type: application/json" -d '{
    "cluster_permissions": [],
    "index_permissions": [{ "index_patterns": ["products*"], "allowed_actions": ["read"] }]
  }'
```

### Index State Management (ISM) Policies
ISM replaces Elasticsearch ILM with a built-in, license-free alternative:
```json
PUT /_plugins/_ism/policies/logs-lifecycle
{
  "policy": {
    "description": "Log index lifecycle",
    "states": [
      {
        "name": "hot",
        "actions": [{ "rollover": { "min_size": "10gb", "min_index_age": "1d" } }],
        "transitions": [{ "state_name": "warm", "conditions": { "min_index_age": "7d" } }]
      },
      {
        "name": "warm",
        "actions": [{ "replica_count": { "number_of_replicas": 0 } }, { "force_merge": { "max_num_segments": 1 } }],
        "transitions": [{ "state_name": "delete", "conditions": { "min_index_age": "30d" } }]
      },
      {
        "name": "delete",
        "actions": [{ "delete": {} }],
        "transitions": []
      }
    ]
  }
}
```

### Data Streams for Time-Series
```json
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "data_stream": {},
  "template": {
    "settings": { "number_of_shards": 1, "number_of_replicas": 1 },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "level":      { "type": "keyword" },
        "service":    { "type": "keyword" },
        "message":    { "type": "text" }
      }
    }
  }
}
```
Data streams automatically manage backing indices, rollover, and ISM policy attachment.

### Cross-Cluster Replication (CCR)
```json
PUT /_plugins/_replication/products/_start
{
  "leader_alias": "primary-cluster",
  "leader_index": "products",
  "use_roles": { "leader_cluster_role": "replication_leader", "follower_cluster_role": "replication_follower" }
}
```
CCR enables active-passive replication across regions or clusters. Follower indexes are read-only
and lag the leader by a configurable window.

### Alerting and Monitors
```json
POST /_plugins/_alerting/monitors
{
  "name": "High error rate",
  "type": "monitor",
  "schedule": { "period": { "interval": 1, "unit": "MINUTES" } },
  "inputs": [{
    "search": {
      "indices": ["logs-*"],
      "query": {
        "size": 0,
        "query": { "bool": { "filter": [
          { "term": { "level": "ERROR" } },
          { "range": { "@timestamp": { "gte": "now-1m" } } }
        ]}},
        "aggs": { "error_count": { "value_count": { "field": "_id" } } }
      }
    }
  }],
  "triggers": [{
    "name": "error-threshold",
    "condition": { "script": { "source": "ctx.results[0].aggregations.error_count.value > 100" } },
    "actions": [{ "destination_id": "slack-webhook-id", "message_template": { "source": "{{ctx.monitor.name}} triggered" } }]
  }]
}
```

### Observability Integration
Use the OpenSearch Observability plugin for integrated traces, metrics, and logs:
```json
// Trace analytics uses Jaeger/OpenTelemetry data in the otel-v1-apm-* indexes
// Correlate log entries with trace IDs for distributed tracing within dashboards
```

## Configuration

```yaml
# opensearch.yml — production baseline
cluster.name: prod-search
node.roles: [data, ingest]
bootstrap.memory_lock: true
indices.memory.index_buffer_size: 20%
# ISM run interval
plugins.index_state_management.job_interval: 5
```

**Cluster sizing:** same as Elasticsearch — 3+ master-eligible nodes, heap 50% of RAM up to 30 GB.

## Performance

- ISM `force_merge` on warm/cold indexes reduces segment count and improves search performance.
- Use data streams for append-only time-series workloads — they handle rollover automatically.
- Enable request caching for dashboard aggregation queries: `"request_cache": true` in the search request.
- Pre-filter shards with `routing` on high-cardinality queries to reduce broadcast overhead.

## Security

- The security plugin is on by default in OpenSearch — never disable it in production.
- Use fine-grained access control (FGAC) for field-level and document-level security.
- Rotate admin credentials immediately after cluster creation — default demo credentials are public.
- Use Amazon OpenSearch Service with VPC endpoint; never expose OpenSearch publicly.

## Testing

```bash
# OpenSearch Testcontainers (Java)
@Container
static GenericContainer<?> opensearch = new GenericContainer<>("opensearchproject/opensearch:2.12.0")
    .withEnv("discovery.type", "single-node")
    .withEnv("DISABLE_SECURITY_PLUGIN", "true")   // test only — never production
    .withExposedPorts(9200);
```

## Dos
- Use ISM policies for index lifecycle management — it is built-in and does not require a commercial license.
- Enable the security plugin and configure RBAC even in staging — security must be tested.
- Use data streams for time-series workloads instead of manually managed index aliases.
- Monitor ISM policy execution errors via `GET /_plugins/_ism/explain/{index}`.

## Don'ts
- Don't disable the security plugin in any environment beyond local development.
- Don't use OpenSearch as a primary data store — always maintain a source of truth elsewhere.
- Don't mix OpenSearch and Elasticsearch clients in the same codebase — API compatibility varies past 7.10.
- Don't set more shards than needed — OpenSearch shard overhead per node is the same as Elasticsearch.
