# Django REST Framework — API Protocol Binding

## Integration Setup
- Add `djangorestframework`; include `'rest_framework'` in `INSTALLED_APPS`
- Pagination: set `DEFAULT_PAGINATION_CLASS` and `PAGE_SIZE` in `REST_FRAMEWORK` settings
- Filtering: add `django-filter`; set `DEFAULT_FILTER_BACKENDS` to include `DjangoFilterBackend`
- OpenAPI: `drf-spectacular` (`@extend_schema` decorators + `SpectacularAPIView`/`SpectacularSwaggerView`)

## Framework-Specific Patterns
- ViewSets: `ModelViewSet` for full CRUD; `ReadOnlyModelViewSet` for list+retrieve only; custom `ViewSet` for non-standard actions
- Register with router: `router = DefaultRouter(); router.register(r"users", UserViewSet, basename="user")`
- Serializers: `ModelSerializer` for ORM-backed resources; `Serializer` for non-model data; always declare `fields` explicitly
- Permissions: combine with `permission_classes = [IsAuthenticated, IsOwner]`; implement `BasePermission` for custom rules
- Filtering: `filterset_fields = ["status", "created_by"]` on the ViewSet; `OrderingFilter` for sort support
- Throttling: `throttle_classes = [UserRateThrottle]`; configure rates in `REST_FRAMEWORK` settings
- Exception handling: DRF converts `ValidationError`, `AuthenticationFailed`, `PermissionDenied` automatically; add `EXCEPTION_HANDLER` for custom mapping

## Scaffolder Patterns
```
app/
  users/
    views.py               # ViewSet classes
    serializers.py         # ModelSerializer + nested serializers
    permissions.py         # custom BasePermission subclasses
    filters.py             # FilterSet subclasses
    urls.py                # router.urls include
  config/
    settings/
      rest_framework.py    # REST_FRAMEWORK dict settings
  urls.py                  # root urlconf, include spectacular urls
```

## Dos
- Use `@action(detail=True, methods=["post"])` on ViewSet for non-CRUD operations (e.g., `users/{id}/activate`)
- Set `select_related` / `prefetch_related` in `get_queryset()` to avoid N+1 queries
- Use `read_only_fields` or separate input/output serializers to prevent mass-assignment
- Document with `@extend_schema(request=..., responses=...)` on every non-obvious endpoint

## Don'ts
- Don't use `fields = "__all__"` on serializers — list fields explicitly to control exposure
- Don't skip pagination on list endpoints — unbounded lists are a performance hazard
- Don't override `perform_create`/`perform_update` to bypass validation — use serializer `validate_*` methods
- Don't return raw Django model instances from views — always go through a serializer
