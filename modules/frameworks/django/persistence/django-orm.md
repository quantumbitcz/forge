# Django ORM with Django

## Integration Setup

Django ORM is built-in — no additional dependencies for standard usage.

```bash
# For advanced query utilities
django-extensions==3.2.3          # shell_plus, show_urls
django-debug-toolbar==4.3.0       # SQL query inspection in dev
```

## Framework-Specific Patterns

### Model Meta Options

```python
class Order(models.Model):
    customer = models.ForeignKey("customers.Customer", on_delete=models.PROTECT)
    status = models.CharField(max_length=50, choices=OrderStatus.choices, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["customer", "status"], name="order_customer_status_idx"),
        ]
        constraints = [
            models.CheckConstraint(
                check=~models.Q(status="") , name="order_status_not_empty"
            )
        ]
```

### Custom Managers and QuerySets

```python
class OrderQuerySet(models.QuerySet):
    def active(self):
        return self.filter(status=OrderStatus.ACTIVE)

    def for_customer(self, customer_id):
        return self.filter(customer_id=customer_id)

class OrderManager(models.Manager):
    def get_queryset(self):
        return OrderQuerySet(self.model, using=self._db)

    def active(self):
        return self.get_queryset().active()

class Order(models.Model):
    objects = OrderManager()
```

### F() and Q() Expressions

```python
from django.db.models import F, Q, Sum, Count

# Atomic counter increment (no race condition)
Order.objects.filter(id=order_id).update(attempt_count=F("attempt_count") + 1)

# Complex OR filter
Order.objects.filter(Q(status="PENDING") | Q(status="PROCESSING"))

# Aggregation
Order.objects.values("customer_id").annotate(
    total_spent=Sum("amount"),
    order_count=Count("id"),
).filter(total_spent__gt=1000)
```

### signals vs. Overriding save()

Prefer overriding `save()` for model-local invariants (call `self.full_clean()` then `super().save()`). Use `post_save` signals only for cross-app side effects. Avoid signals for business logic — execution order is not guaranteed and they are hard to trace.

### Multi-DB Routing

```python
# routers.py
class ReplicaRouter:
    def db_for_read(self, model, **hints): return "replica"
    def db_for_write(self, model, **hints): return "default"

# settings.py
DATABASE_ROUTERS = ["myapp.routers.ReplicaRouter"]
```

## Scaffolder Patterns

```yaml
patterns:
  model: "{app}/models/{entity}.py"
  manager: "{app}/managers/{entity}_manager.py"
  queryset: "{app}/querysets/{entity}_queryset.py"
  router: "{project}/routers.py"
```

## Additional Dos/Don'ts

- DO use `select_related()` for ForeignKey traversal and `prefetch_related()` for ManyToMany
- DO define `__str__` on every model for readable admin and shell output
- DO use `QuerySet.iterator()` for large result sets to avoid loading all rows into memory
- DON'T use `Model.objects.all()` without a `LIMIT` equivalent in production list views
- DON'T call `save()` inside a loop — use `bulk_create()` / `bulk_update()` for batch operations
- DON'T use signals for ordering critical operations — their execution order is not guaranteed
