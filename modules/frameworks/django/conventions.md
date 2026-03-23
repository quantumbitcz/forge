# Django Framework Conventions

> Framework-specific conventions for Django projects. Language idioms are in `modules/languages/python.md`.
> Generic testing patterns are in `modules/testing/pytest.md`.

## Architecture (MTV + Services Layer)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `{app}/views.py` / `{app}/api/views.py` | HTTP handling, serialization, delegating to services | Services, serializers |
| `{app}/services.py` | Business logic, use cases, orchestration | Models, repositories/managers |
| `{app}/models.py` | ORM model definitions, database schema, custom managers | Django ORM only |
| `{app}/serializers.py` | DRF request/response validation and serialization | Models, DRF |
| `{app}/urls.py` | URL routing, viewset registration | Views, routers |
| `{app}/migrations/` | Database schema migrations | Models |

**Dependency rule:** Views (and ViewSets) never contain business logic — they validate, delegate to services, and serialize. Services mediate all data access and orchestrate model operations. Models are persistence representations, not business objects. Serializers handle validation and shape, not business rules.

## Apps as Bounded Contexts

- Each Django app represents a bounded context: `users/`, `orders/`, `products/`
- Apps are self-contained: models, services, serializers, views, urls all within the app directory
- Cross-app dependencies flow through service interfaces, not direct model imports where possible
- Avoid circular imports between apps — use `get_model()` for forward references when needed
- App configs (`AppConfig`) must define `default_auto_field = "django.db.models.BigAutoField"`

## Django REST Framework (DRF)

- Use DRF for all API endpoints — raw Django views only for non-API pages
- ViewSets + Routers for standard CRUD: `ModelViewSet`, `ReadOnlyModelViewSet`, or custom `ViewSet`
- Function-based views with `@api_view` only for simple, non-RESTful endpoints
- Serializers for all input/output — never return model instances or raw dicts from views
- Validation: DRF serializer `validate_*` methods for field-level; `validate()` for cross-field
- Pagination: configure globally via `DEFAULT_PAGINATION_CLASS` + `PAGE_SIZE`; override per ViewSet

## Django ORM

### QuerySet Best Practices
- Always use `select_related()` for ForeignKey/OneToOne traversal in loops
- Always use `prefetch_related()` for ManyToMany and reverse FK traversal in loops
- Use `only()` / `defer()` to fetch partial models for read-heavy paths where few fields are needed
- Use `F()` objects for database-side arithmetic and comparisons — avoids Python-side race conditions
- Use `Q()` objects for complex OR/AND query logic in filter clauses
- Use `annotate()` and `aggregate()` for computed values at the database layer, not in Python
- Never call `.all()` and then filter in Python — build the full queryset before evaluating

### N+1 Prevention
- If a loop accesses a related object attribute, you have N+1 — use `select_related` / `prefetch_related`
- Use `django-debug-toolbar` in development to detect unexpected queries
- Add database indexes on foreign keys and frequently-filtered fields

### Model Design
- Singular PascalCase model names: `User`, `Order`, `Product`
- Use `UUIDField(primary_key=True, default=uuid.uuid4)` for public-facing IDs
- Audit fields: `created_at = models.DateTimeField(auto_now_add=True)`, `updated_at = models.DateTimeField(auto_now=True)`
- Custom managers for common querysets: `objects = ActiveManager()`; keep default `objects` manager as well
- `__str__` on every model — essential for admin and debugging
- Meta class: always define `verbose_name`, `verbose_name_plural`, `ordering` where relevant
- Avoid model methods with side effects — move mutations to services

## Migrations

- Always reversible: every `migrations.RunPython` must include `reverse_code`
- Never modify an applied migration — create a new one
- Atomic migrations (default) — avoid `atomic = False` unless absolutely required for concurrent index creation
- Data migrations (using `RunPython`) must be idempotent
- Squash migrations periodically in long-lived projects; document the squash in the PR

## Authentication and Authorization

- Use `django.contrib.auth` for session-based auth; DRF `authentication_classes` for APIs
- JWT: use `djangorestframework-simplejwt` — configure token lifetime, rotation, and blacklisting
- Permissions: `IsAuthenticated` as global default; override with custom permissions per viewset
- Custom permissions: inherit `BasePermission`, implement `has_permission` and `has_object_permission`
- Object-level permissions: use `has_object_permission` on ViewSet `get_object()` — never skip object-level checks
- Never trust user-supplied IDs for authorization — always filter with `request.user` ownership

## Error Handling

- Custom DRF exception handler: override `EXCEPTION_HANDLER` in DRF settings
- Define app-level base exceptions: `AppException(APIException)` with a `default_code`
- DRF returns structured JSON errors automatically for validation failures — never raise `Http404` in serializers
- Use `get_object_or_404()` only in views — services should raise a domain-specific `NotFoundException`
- Map exceptions to HTTP status codes consistently:

| Exception | HTTP Status |
|-----------|-------------|
| `ValidationError` | 400 |
| `NotFoundException` (custom) | 404 |
| `PermissionDenied` | 403 |
| `NotAuthenticated` | 401 |
| `ConflictException` (custom) | 409 |
| Unhandled | 500 |

## Security

- `SECRET_KEY`: load from environment variable — never hardcode in settings files
- `ALLOWED_HOSTS`: explicit list in production — never `["*"]` in production
- `DEBUG = False` in production — verified at startup via `check --deploy`
- CSRF: enabled by default for browser-facing views; use `CSRFExemptSessionAuthentication` for API endpoints using token auth
- SQL injection: handled by the ORM — never use `.raw()` or `cursor.execute()` with string formatting
- XSS: Django templates auto-escape; mark safe strings explicitly with `mark_safe()` only when absolutely necessary
- Sensitive settings: `DATABASES`, `SECRET_KEY`, `EMAIL_HOST_PASSWORD` — always from environment variables
- Content Security Policy: configure via `django-csp` for HTML views

## Performance

- Database indexes: add `db_index=True` or `Meta.indexes` for all filter/order_by fields
- QuerySet evaluation: avoid evaluating querysets inside loops — build them first, then slice
- Caching: `django.core.cache` with Redis backend for session, queryset, and fragment caching
- `cache_page` decorator for expensive view responses; cache key must include user/permission context
- Celery for background tasks — never block request/response cycle with heavy computation
- Use `CONN_MAX_AGE` in database settings for persistent connections in production

## API Design (DRF)

- Versioning: `NamespaceVersioning` or `URLPathVersioning` — not query parameter versioning
- Filtering: use `django-filter` integration; expose `filterset_class` on ViewSets
- Throttling: configure `DEFAULT_THROTTLE_CLASSES` globally; override per viewset for sensitive endpoints
- Pagination: `PageNumberPagination` or `CursorPagination` — always paginate list endpoints
- Response envelope: keep DRF default (list returns array, detail returns object) — avoid wrapping all responses in `{"data": ...}`

## Management Commands and Signals

- Management commands: subclass `BaseCommand`; use for data imports, one-time operations, scheduled tasks
- Signals (`post_save`, `pre_delete`): use sparingly — they create hidden coupling; prefer explicit service calls
- If signals are used: document the coupling in the `AppConfig.ready()` registration site
- Never trigger async tasks from signals — chain Celery tasks from services instead

## Code Quality

- Functions and methods: max ~40 lines; max 3 nesting levels
- Docstrings on public service methods — explain the business rule (WHY), not the implementation (WHAT)
- No `print()` in production code — use `logging.getLogger(__name__)`
- No bare `except:` — always name exception types

## TDD Flow

```
scaffold -> write tests (RED) -> implement (GREEN) -> refactor
```

1. **Scaffold**: create model/serializer/service stubs
2. **RED**: write the test expressing expected behavior — must fail
3. **GREEN**: implement the minimum code to pass
4. **Refactor**: clean up, apply ORM optimizations, tests must still pass

## Smart Test Rules

- Test behavior, not implementation — tests should survive internal refactoring
- No duplicate scenarios — each test covers a distinct case
- Do not test Django/DRF internals (model field validation, default serializer behavior)
- One logical assertion concept per test
- Use `@pytest.mark.django_db` for all tests touching the database
- Use `factory_boy` for test data — avoid fixtures for complex objects

## Logging and Monitoring

- Use Python `logging` with Django's `LOGGING` setting; structured JSON format for production
- `LOGGING['root']` at WARNING; app loggers at DEBUG in dev, INFO in production
- Log levels: ERROR (action needed), WARNING (degraded), INFO (business events), DEBUG (dev only)
- Never log sensitive data: passwords, tokens, PII, request bodies
- Health endpoint: `django-health-check` with DB, cache, and celery checks

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated apps, changing model schemas, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use `select_related` / `prefetch_related` — always prevent N+1 before code review
- Put business logic in services, not in views or models
- Use DRF serializers for all API input validation — never validate manually in views
- Use `get_object_or_404()` in views; raise domain exceptions in services
- Keep migrations reversible with `reverse_code` in all `RunPython` migrations
- Use `UUIDField(primary_key=True)` for public-facing IDs
- Configure `ALLOWED_HOSTS` explicitly in production
- Use environment variables for all sensitive settings
- Paginate all list endpoints
- Use custom managers for common querysets instead of repeating filters

### Don't
- Don't put business logic in views or ViewSets — delegate to services
- Don't put business logic in model methods that have side effects — use services
- Don't use `.raw()` or raw `cursor.execute()` with string formatting — use the ORM
- Don't use `signal.connect()` for core business flows — signals hide coupling
- Don't use `DEBUG = True` in production
- Don't use `ALLOWED_HOSTS = ["*"]` in production
- Don't use `print()` in production code — use `logging`
- Don't evaluate a queryset inside a loop — refactor to a single query
- Don't modify applied migrations — create new ones
- Don't use `get_or_create()` / `update_or_create()` without handling the `created` flag
- Don't access `request.user` in services — pass user context as an explicit parameter
- Don't use `mark_safe()` on user-supplied content — XSS risk
