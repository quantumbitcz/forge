# FastAPI + Elasticsearch (async)

> Async Elasticsearch patterns for FastAPI using the official `elasticsearch[async]` client.

## Integration Setup

```bash
pip install "elasticsearch[async]"
```

## Framework-Specific Patterns

### Lifespan client init + DI dependency
```python
# app/lifespan.py
from contextlib import asynccontextmanager
from elasticsearch import AsyncElasticsearch
from fastapi import FastAPI

es_client: AsyncElasticsearch | None = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global es_client
    es_client = AsyncElasticsearch(
        hosts=[settings.ELASTICSEARCH_URL],
        basic_auth=(settings.ES_USERNAME, settings.ES_PASSWORD),
        verify_certs=settings.ENV == "production",
    )
    await _ensure_indices(es_client)
    yield
    await es_client.close()

async def _ensure_indices(es: AsyncElasticsearch):
    if not await es.indices.exists(index="products"):
        await es.indices.create(
            index="products",
            mappings={"properties": {"name": {"type": "text"}, "price": {"type": "float"}}},
        )
```

### Dependency
```python
# app/dependencies.py
from elasticsearch import AsyncElasticsearch
from app.lifespan import es_client

async def get_es() -> AsyncElasticsearch:
    if es_client is None:
        raise RuntimeError("Elasticsearch client not initialized")
    return es_client
```

### Search endpoint
```python
# app/routers/search.py
from fastapi import APIRouter, Depends, Query
from elasticsearch import AsyncElasticsearch
from app.dependencies import get_es

router = APIRouter()

@router.get("/search")
async def search_products(
    q: str = Query(..., min_length=1),
    es: AsyncElasticsearch = Depends(get_es),
):
    result = await es.search(
        index="products",
        query={"multi_match": {"query": q, "fields": ["name^3", "description"]}},
        size=20,
    )
    return [hit["_source"] for hit in result["hits"]["hits"]]
```

### Index document
```python
async def index_product(product: Product, es: AsyncElasticsearch):
    await es.index(
        index="products",
        id=str(product.id),
        document={"name": product.name, "description": product.description, "price": product.price},
    )
```

## Scaffolder Patterns
```
app/
  lifespan.py           # AsyncElasticsearch init + index setup
  dependencies.py       # get_es dependency
  services/
    search_service.py   # index, search, delete helpers
  routers/
    search.py           # search endpoints
```

## Dos
- Initialize `AsyncElasticsearch` in `lifespan` so the connection is reused across requests
- Create indices with explicit mappings in `_ensure_indices` — avoid dynamic mapping in production
- Use `Depends(get_es)` in route functions; never import the client global directly
- Handle `elasticsearch.NotFoundError` and `elasticsearch.ConnectionError` explicitly

## Don'ts
- Don't create a new `AsyncElasticsearch` per request
- Don't use the synchronous client in async FastAPI routes — it blocks the event loop
- Don't rely on ES as your source of truth — always persist to the primary DB first
- Don't expose raw ES query errors to the client
