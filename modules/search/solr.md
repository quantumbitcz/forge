# Apache Solr — Search Best Practices

## Overview

Solr is a mature, open-source search platform built on Apache Lucene. Use it for enterprise
full-text search, faceted navigation, and applications needing SolrCloud for distributed search.
Solr excels at complex faceting, geospatial search, and heavy read workloads. Avoid it for
new projects where Elasticsearch or Typesense offer simpler operational setup, or for real-time
analytics (use ClickHouse).

## Architecture Patterns

### Schema Design
```xml
<field name="id" type="string" indexed="true" stored="true" required="true"/>
<field name="title" type="text_general" indexed="true" stored="true"/>
<field name="description" type="text_general" indexed="true" stored="true"/>
<field name="price" type="pfloat" indexed="true" stored="true"/>
<field name="category" type="string" indexed="true" stored="true" docValues="true"/>
<field name="tags" type="strings" indexed="true" stored="true"/>
<field name="location" type="location" indexed="true" stored="true"/>

<uniqueKey>id</uniqueKey>
<copyField source="title" dest="text"/>
<copyField source="description" dest="text"/>
```

### SolrCloud for Distributed Search
```bash
# Start with ZooKeeper ensemble
bin/solr start -c -z zk1:2181,zk2:2181,zk3:2181

# Create collection with shards and replicas
bin/solr create -c products -s 3 -rf 2
```

### Query
```
/select?q=wireless+headphones&fq=category:Electronics&fq=price:[0+TO+100]
  &facet=true&facet.field=brand&facet.field=category
  &sort=score+desc,price+asc&rows=20&start=0
  &fl=id,title,price,category
```

### Anti-pattern — using schemaless mode in production: Schemaless mode auto-detects field types, which causes inconsistent indexing when field values vary (e.g., a field being both string and integer).

## Configuration

```xml
<!-- solrconfig.xml — key settings -->
<requestHandler name="/select" class="solr.SearchHandler">
  <lst name="defaults">
    <str name="df">text</str>
    <str name="rows">10</str>
    <str name="wt">json</str>
  </lst>
</requestHandler>

<updateHandler class="solr.DirectUpdateHandler2">
  <autoCommit>
    <maxTime>15000</maxTime>
    <openSearcher>false</openSearcher>
  </autoCommit>
  <autoSoftCommit>
    <maxTime>1000</maxTime>
  </autoSoftCommit>
</updateHandler>
```

## Dos
- Use explicit schemas (managed-schema) — avoid schemaless mode in production.
- Use SolrCloud (ZooKeeper-managed) for distributed deployments — standalone Solr doesn't scale.
- Use `docValues` for fields used in sorting, faceting, and aggregation — they're more memory-efficient.
- Use `copyField` for multi-field search — it indexes the same content with different analyzers.
- Use soft commits for near-real-time search visibility, hard commits for durability.
- Monitor with Solr's admin UI and Prometheus exporter — track QPS, latency, and cache hit ratios.
- Use filter queries (`fq`) for cacheable filters — they're cached independently from the main query.

## Don'ts
- Don't use schemaless mode in production — it causes inconsistent field type detection.
- Don't commit after every document — batch commits improve throughput dramatically.
- Don't use `*:*` without filters on large collections — it scans all documents.
- Don't skip ZooKeeper for SolrCloud — it's required for collection management and leader election.
- Don't store large binary fields in Solr — store references to external storage.
- Don't ignore cache sizing — FilterCache, QueryResultCache, and DocumentCache need tuning per workload.
- Don't use the legacy `/update` handler without authentication — it allows arbitrary data modification.
