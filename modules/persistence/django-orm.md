# Django ORM Best Practices

## Overview
Django ORM is the built-in persistence layer for Django applications, providing an expressive QuerySet API, automatic migrations, and tight framework integration. Use it for Django projects — it is the natural choice and deeply integrated with forms, admin, and auth. Avoid it outside Django, or for applications requiring reactive/async-first database access (consider SQLAlchemy async there).

## Architecture Patterns

### Model Design
```python
from django.db import models
from django.utils import timezone

class Customer(models.Model):
    email      = models.EmailField(unique=True, db_index=True)
    name       = models.CharField(max_length=100)
    is_active  = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["is_active", "created_at"]),  # composite index
        ]

class Order(models.Model):
    customer   = models.ForeignKey(Customer, on_delete=models.CASCADE,
                                   related_name="orders")
    total      = models.DecimalField(max_digits=10, decimal_places=2)
    status     = models.CharField(max_length=20, default="pending")
    created_at = models.DateTimeField(auto_now_add=True)
```

### Custom Managers
```python
class ActiveOrderManager(models.Manager):
    def get_queryset(self):
        return super().get_queryset().filter(status__in=["pending", "processing"])

    def for_customer(self, customer_id: int):
        return self.get_queryset().filter(customer_id=customer_id)

class Order(models.Model):
    objects = models.Manager()          # keep default manager first
    active  = ActiveOrderManager()      # custom manager as secondary

# Usage
pending_orders = Order.active.for_customer(42).select_related("customer")
```

### F and Q Expressions
```python
from django.db.models import F, Q, Sum, Count

# F: atomic field reference — avoids race conditions in updates
Order.objects.filter(id=order_id).update(total=F("total") * F("quantity"))

# Q: complex boolean conditions
high_value = Order.objects.filter(
    Q(total__gte=1000) | (Q(status="vip") & Q(customer__tier="gold"))
)

# Annotations
Customer.objects.annotate(
    order_count=Count("orders"),
    total_spent=Sum("orders__total")
).filter(order_count__gt=5)
```

## Configuration

```python
# settings.py
DATABASES = {
    "default": {
        "ENGINE":   "django.db.backends.postgresql",
        "NAME":     env("DB_NAME"),
        "USER":     env("DB_USER"),
        "PASSWORD": env("DB_PASSWORD"),
        "HOST":     env("DB_HOST", default="localhost"),
        "PORT":     env("DB_PORT", default="5432"),
        "CONN_MAX_AGE": 60,      # persistent connections (seconds)
        "OPTIONS": {
            "connect_timeout": 5,
            "options": "-c statement_timeout=30000",  # 30s query timeout
        },
    }
}
```

## Performance

### select_related and prefetch_related
```python
# select_related: SQL JOIN for ForeignKey / OneToOne (avoids N+1)
orders = Order.objects.select_related("customer").filter(status="pending")

# prefetch_related: separate query with IN for ManyToMany / reverse FK
customers = Customer.objects.prefetch_related(
    Prefetch(
        "orders",
        queryset=Order.objects.filter(status="pending").only("id", "total"),
        to_attr="pending_orders"
    )
)

# N+1 detection in tests
from django.test.utils import override_settings
from django.db import connection, reset_queries

with override_settings(DEBUG=True):
    reset_queries()
    list(Customer.objects.all())      # execute queryset
    assert len(connection.queries) <= 2, f"N+1 detected: {len(connection.queries)} queries"
```

### Bulk Operations
```python
# bulk_create: single INSERT for many objects
Order.objects.bulk_create([
    Order(customer_id=cid, total=amount)
    for cid, amount in order_data
], batch_size=500)

# bulk_update: single UPDATE for multiple rows
orders_to_update = [...]
for order in orders_to_update:
    order.status = "shipped"
Order.objects.bulk_update(orders_to_update, ["status"], batch_size=500)

# iterator(): stream large querysets to avoid loading all into memory
for order in Order.objects.filter(status="pending").iterator(chunk_size=1000):
    process(order)
```

### QuerySet Chaining and Deferred Fields
```python
# only(): load specific columns
Order.objects.only("id", "total", "status")

# defer(): load all except specified
Order.objects.defer("large_text_field", "binary_data")

# values() / values_list() for projection (returns dicts/tuples, not model instances)
Order.objects.values("id", "total").filter(status="shipped")
```

## Security

```python
# SAFE: Django ORM always parameterizes values
Order.objects.filter(customer__email=user_input)

# SAFE: raw() with params tuple
Order.objects.raw("SELECT * FROM orders WHERE status = %s", [user_input])

# UNSAFE: never interpolate into raw() SQL
# Order.objects.raw(f"SELECT * FROM orders WHERE status = '{user_input}'")

# Multi-tenant: always scope querysets to the current tenant
def get_queryset(self):
    return Order.objects.filter(tenant_id=self.request.tenant.id)
```

## Testing

```python
import pytest
from django.test import TestCase
from model_bakery import baker  # or factory_boy

class OrderQueryTests(TestCase):
    def setUp(self):
        self.customer = baker.make(Customer, is_active=True)
        self.orders   = baker.make(Order, customer=self.customer, _quantity=3)

    def test_pending_orders_excludes_shipped(self):
        baker.make(Order, customer=self.customer, status="shipped")
        qs = Order.active.for_customer(self.customer.id)
        self.assertEqual(qs.count(), 3)

    def test_no_n1_on_order_listing(self):
        with self.assertNumQueries(2):  # 1 orders + 1 customers (select_related)
            list(Order.objects.select_related("customer").all())

# Integration test with Testcontainers (pytest-django)
@pytest.mark.django_db(transaction=True)
def test_bulk_create_performance(django_db_setup):
    Order.objects.bulk_create([Order(customer_id=1, total=i) for i in range(1000)])
    assert Order.objects.count() == 1000
```

## Dos
- Always use `select_related` for ForeignKey traversal and `prefetch_related` for reverse relations or M2M.
- Use `bulk_create` / `bulk_update` with `batch_size` for inserting/updating large sets of objects.
- Add `db_index=True` on fields used in `.filter()`, and composite `Meta.indexes` for multi-column filters.
- Use `only()` or `values()` to avoid loading unused columns in list views.
- Write custom managers for common filter patterns — keeps views and serializers clean.
- Use `iterator(chunk_size=...)` when iterating over large querysets in management commands.
- Use `assertNumQueries` in tests to detect and prevent N+1 regressions.

## Don'ts
- Don't call `.all()` in views without pagination or `.iterator()` — can load millions of rows into memory.
- Don't use `Model.objects.get()` in loops — use `filter()` with `in` lookups instead.
- Don't use `raw()` with string formatting or f-strings for user input — always use the params argument.
- Don't put business logic in model `save()` overrides — side effects are hard to test and control.
- Don't use model signals (`post_save`, `pre_delete`) for critical business logic — they are hard to trace and test.
- Don't use `on_delete=models.SET_NULL` when null FK creates orphan data integrity issues — prefer CASCADE or PROTECT.
- Don't use `auto_now=True` when you need to control the timestamp value in migrations or fixtures.
