# Django + pytest Testing Patterns

> Django-specific pytest patterns. Extends `modules/testing/pytest.md`.
> Generic pytest conventions (fixtures, parametrize, conftest) are NOT repeated here.

## Database Access

Mark all tests needing database access — pytest-django enforces this explicitly:

```python
import pytest

@pytest.mark.django_db
def test_user_creation():
    user = User.objects.create_user(username="alice", password="secret")
    assert User.objects.count() == 1
```

Use `transaction=True` for tests that exercise `select_for_update` or raw transactions:

```python
@pytest.mark.django_db(transaction=True)
def test_concurrent_update():
    ...
```

## API Testing with DRF APIClient

```python
import pytest
from rest_framework.test import APIClient
from rest_framework import status

@pytest.fixture
def api_client():
    return APIClient()

@pytest.fixture
def authenticated_client(api_client, user):
    api_client.force_authenticate(user=user)
    return api_client

@pytest.mark.django_db
def test_create_order(authenticated_client):
    response = authenticated_client.post("/api/v1/orders/", {"product_id": 1, "quantity": 2})
    assert response.status_code == status.HTTP_201_CREATED
    assert response.data["id"] is not None
```

## Model Factories with factory_boy

```python
import factory
from factory.django import DjangoModelFactory

class UserFactory(DjangoModelFactory):
    class Meta:
        model = User

    username = factory.Sequence(lambda n: f"user{n}")
    email = factory.LazyAttribute(lambda o: f"{o.username}@example.com")
    is_active = True

class OrderFactory(DjangoModelFactory):
    class Meta:
        model = Order

    user = factory.SubFactory(UserFactory)
    status = Order.Status.PENDING
    total = factory.Faker("pydecimal", left_digits=4, right_digits=2, positive=True)
```

Use factories in tests — never construct model instances manually for complex cases:

```python
@pytest.mark.django_db
def test_order_service(user):
    order = OrderFactory(user=user)
    result = order_service.confirm(order.id)
    assert result.status == Order.Status.CONFIRMED
```

## conftest.py Fixtures

Organize shared fixtures in `conftest.py` at the appropriate level (test root or app-level):

```python
# tests/conftest.py
import pytest

@pytest.fixture
def user(db):
    return UserFactory()

@pytest.fixture
def admin_user(db):
    return UserFactory(is_staff=True, is_superuser=True)

@pytest.fixture
def api_client():
    return APIClient()
```

## Settings Overrides

```python
@pytest.mark.django_db
def test_email_on_registration(settings):
    settings.EMAIL_BACKEND = "django.core.mail.backends.locmem.EmailBackend"
    # ... trigger registration flow
    assert len(mail.outbox) == 1
```

Or as a decorator: `@override_settings(CELERY_TASK_ALWAYS_EAGER=True)`

## Celery Tasks in Tests

```python
@pytest.fixture(autouse=True)
def celery_eager(settings):
    settings.CELERY_TASK_ALWAYS_EAGER = True
    settings.CELERY_TASK_EAGER_PROPAGATES = True
```

This makes `delay()` / `apply_async()` run synchronously in tests.

## What to Test at Each Layer

| Layer | Test type | Tools |
|-------|-----------|-------|
| ViewSet / API | Integration | `@pytest.mark.django_db` + `APIClient` |
| Service | Unit + Integration | `@pytest.mark.django_db` + factories |
| Model manager | Integration | `@pytest.mark.django_db` + factories |
| Serializer | Unit | Direct instantiation, no DB needed |
| Celery task | Integration | `CELERY_TASK_ALWAYS_EAGER=True` |
