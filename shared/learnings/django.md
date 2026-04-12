# Cross-Project Learnings: django

## PREEMPT items

### DJ-PREEMPT-001: N+1 queries in DRF serializers with nested relationships
- **Domain:** persistence
- **Pattern:** DRF serializers that access related objects (e.g., `source='author.name'`) trigger a separate query per row if the queryset is not optimized. Override `get_queryset()` on the ViewSet to add `select_related()` / `prefetch_related()` for all serializer relationships.
- **Confidence:** HIGH
- **Hit count:** 0

### DJ-PREEMPT-002: Migration conflicts in team environments
- **Domain:** migrations
- **Pattern:** Multiple developers creating migrations for the same app simultaneously produces conflicting migration files that Django refuses to apply. Use `python manage.py makemigrations --merge` to resolve, or coordinate migration creation via feature branches.
- **Confidence:** HIGH
- **Hit count:** 0

### DJ-PREEMPT-003: Signals hide business logic coupling
- **Domain:** architecture
- **Pattern:** Using `post_save` signals for core business flows (e.g., sending emails, updating counts) creates hidden coupling that is hard to debug and test. Move business logic to explicit service calls. Reserve signals only for truly decoupled concerns like audit logging.
- **Confidence:** HIGH
- **Hit count:** 0

### DJ-PREEMPT-004: get_or_create race condition under concurrent requests
- **Domain:** persistence
- **Pattern:** `get_or_create()` and `update_or_create()` are not atomic by default and can raise `IntegrityError` under concurrent writes. Add `unique_together` or `UniqueConstraint` on the lookup fields and handle `IntegrityError` with retry logic.
- **Confidence:** HIGH
- **Hit count:** 0

### DJ-PREEMPT-005: RunPython migrations without reverse_code block rollbacks
- **Domain:** migrations
- **Pattern:** Data migrations using `RunPython` without a `reverse_code` parameter cause `IrreversibleError` on rollback. Always provide a reverse function, even if it is `migrations.RunPython.noop` for non-reversible transforms.
- **Confidence:** HIGH
- **Hit count:** 0

### DJ-PREEMPT-006: DEBUG=True in production leaks stack traces and settings
- **Domain:** security
- **Pattern:** Django's debug mode exposes full stack traces, settings values, and SQL queries in error pages. Run `python manage.py check --deploy` in CI to verify `DEBUG=False`, `ALLOWED_HOSTS` is set, and `SECRET_KEY` is not default.
- **Confidence:** HIGH
- **Hit count:** 0

### DJ-PREEMPT-007: Celery tasks accessing request.user fail silently
- **Domain:** concurrency
- **Pattern:** Celery tasks run outside the request/response cycle and have no access to `request.user`. Pass the user ID as a task argument and re-fetch the user inside the task. Never pass Django model instances to Celery — they are not JSON-serializable by default.
- **Confidence:** HIGH
- **Hit count:** 0

### DJ-PREEMPT-008: QuerySet evaluated inside a loop defeats lazy evaluation
- **Domain:** persistence
- **Pattern:** Iterating a queryset inside a `for` loop that itself queries the database creates O(N) queries. Build the full queryset with filters, annotations, and prefetches before evaluating. Use `django-debug-toolbar` in development to detect unexpected query counts.
- **Confidence:** MEDIUM
- **Hit count:** 0
