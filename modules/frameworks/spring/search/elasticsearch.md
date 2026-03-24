# Spring Data Elasticsearch

> Spring-specific patterns for Elasticsearch integration. Extends generic Spring conventions.

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-data-elasticsearch")
```

```yaml
# application.yml
spring:
  elasticsearch:
    uris: ${ES_URIS:http://localhost:9200}
    username: ${ES_USER:}
    password: ${ES_PASSWORD:}
    connection-timeout: 5s
    socket-timeout: 30s
```

## Framework-Specific Patterns

```kotlin
// Document mapping
@Document(indexName = "products", createIndex = true)
data class ProductDocument(
    @Id val id: String,
    @Field(type = FieldType.Text, analyzer = "english") val name: String,
    @Field(type = FieldType.Keyword) val category: String,
    @Field(type = FieldType.Double) val price: Double,
    @Field(type = FieldType.Date, format = [DateFormat.date_time]) val createdAt: Instant,
)
```

```kotlin
// Repository — simple queries via method names
interface ProductSearchRepository : ElasticsearchRepository<ProductDocument, String> {
    fun findByCategory(category: String, pageable: Pageable): Page<ProductDocument>
}
```

```kotlin
// ElasticsearchOperations — complex queries
@Service
class ProductSearchService(private val ops: ElasticsearchOperations) {

    fun search(term: String, category: String?, pageable: Pageable): SearchHits<ProductDocument> {
        val query = NativeQuery.builder()
            .withQuery(
                Query.of { q -> q.bool { b ->
                    b.must { m -> m.multiMatch { mm ->
                        mm.query(term).fields("name^2", "description")
                    }}
                    if (category != null) b.filter { f -> f.term { t -> t.field("category").value(category) } }
                    b
                }}
            )
            .withPageable(pageable)
            .withHighlightQuery(HighlightQuery(Highlight.of { h -> h.fields("name") { _ -> } }, null))
            .build()
        return ops.search(query, ProductDocument::class.java)
    }

    fun bulkIndex(docs: List<ProductDocument>) {
        val queries = docs.map { IndexQuery().apply { id = it.id; `object` = it } }
        ops.bulkIndex(queries, ProductDocument::class.java)
    }
}
```

## Scaffolder Patterns

```
src/main/kotlin/com/example/
  search/
    document/
      ProductDocument.kt        # @Document entity
    repository/
      ProductSearchRepository.kt  # ElasticsearchRepository
    service/
      ProductSearchService.kt   # ElasticsearchOperations for complex queries
  config/
    ElasticsearchConfig.kt      # custom client config (SSL, API key auth)
```

## Dos

- Set `createIndex = true` in `@Document` only for dev/test; manage index lifecycle with index templates in production
- Use `FieldType.Keyword` for exact-match fields (IDs, enums) and `FieldType.Text` with analyzers for full-text
- Prefer `ElasticsearchOperations` over `ElasticsearchRepository` for complex multi-clause queries
- Paginate bulk index operations (1 000–5 000 docs per batch) to avoid OOM and ES circuit breaker trips

## Don'ts

- Don't map the entire DB entity to an Elasticsearch document — project only the fields needed for search
- Don't use `findAll()` without pagination — unbounded result sets exhaust heap
- Don't use synchronous blocking calls in reactive service flows; use `ReactiveElasticsearchOperations` instead
- Don't skip index aliases — they enable zero-downtime re-indexing by swapping alias targets
