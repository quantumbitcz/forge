# Django + Elasticsearch (django-elasticsearch-dsl)

> Full-text search for Django using `django-elasticsearch-dsl` with auto-sync on model save.

## Integration Setup

```bash
pip install django-elasticsearch-dsl
```

```python
# settings.py
INSTALLED_APPS = [..., "django_elasticsearch_dsl"]

ELASTICSEARCH_DSL = {
    "default": {"hosts": env("ELASTICSEARCH_URL", default="http://localhost:9200")},
}
```

## Framework-Specific Patterns

### Document definition
```python
# products/documents.py
from django_elasticsearch_dsl import Document, fields
from django_elasticsearch_dsl.registries import registry
from .models import Product

@registry.register_document
class ProductDocument(Document):
    category = fields.ObjectField(properties={
        "name": fields.TextField(),
        "slug": fields.KeywordField(),
    })

    class Index:
        name = "products"
        settings = {"number_of_shards": 1, "number_of_replicas": 0}

    class Django:
        model = Product
        fields = ["name", "description", "price", "stock"]
        related_models = []     # list models whose save should trigger re-index

    def get_queryset(self):
        return super().get_queryset().select_related("category")
```

### Auto-sync on save
`@registry.register_document` hooks into `post_save` and `post_delete` signals automatically. For bulk indexing:
```bash
python manage.py search_index --rebuild   # drop + recreate + populate
python manage.py search_index --populate  # populate without dropping
```

### Search in a view
```python
# products/views.py
from django.views.generic import ListView
from .documents import ProductDocument

class ProductSearchView(ListView):
    template_name = "products/search.html"

    def get_queryset(self):
        query = self.request.GET.get("q", "")
        if not query:
            return []
        return ProductDocument.search().query(
            "multi_match", query=query, fields=["name^3", "description"]
        ).to_queryset()   # returns a Django QuerySet for pagination
```

### DRF search endpoint
```python
# products/api/views.py
from rest_framework.views import APIView
from rest_framework.response import Response
from products.documents import ProductDocument

class ProductSearchAPIView(APIView):
    def get(self, request):
        q = request.query_params.get("q", "")
        hits = ProductDocument.search().query(
            "multi_match", query=q, fields=["name^3", "description"]
        )[:20]
        return Response([h.to_dict() for h in hits])
```

## Scaffolder Patterns
```
products/
  documents.py          # @registry.register_document classes
  views.py              # ListView using DocumentSearch
  api/
    views.py            # DRF search endpoint
  apps.py               # import documents in ready() for signal registration
```

## Dos
- Import `documents.py` in `AppConfig.ready()` so signals are registered at startup
- Use `to_queryset()` when you need Django ORM features (pagination, `select_related`)
- Run `search_index --rebuild` as part of your deployment for schema changes
- Define explicit `Index.settings` — don't rely on cluster defaults for replicas/shards

## Don'ts
- Don't use `auto_refresh=True` in production — it increases indexing latency
- Don't store all model fields in ES — project only what is needed for search
- Don't rely on ES as the primary data store; always persist to the Django ORM first
- Don't skip signal registration in `ready()` — documents not imported = no auto-sync
