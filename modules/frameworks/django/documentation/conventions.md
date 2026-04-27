# Django Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with Django-specific patterns.

## Code Documentation

- Use Google-style docstrings for all view classes/functions, model methods, and service layer functions.
- Django models: document non-obvious fields with `help_text` (surfaces in admin UI) and class-level docstrings for model invariants.
- Django REST Framework serializers: document `validate_*` methods explaining the business rule being enforced.
- Management commands (`BaseCommand`): document `help` string — it is the CLI documentation.
- Signals: document sender, when the signal fires, and what the receiver does — signal dispatch is non-obvious.

```python
class UserProfile(models.Model):
    """Extended profile for authenticated users.

    Created automatically via post_save signal on User creation.
    Invariant: exactly one UserProfile per User.
    """

    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        help_text="The auth.User this profile extends.",
    )
    coaching_tier = models.CharField(
        max_length=20,
        choices=CoachingTier.choices,
        help_text="Determines feature access. Updated by billing webhooks.",
    )
```

## Architecture Documentation

- Document the app structure: list Django apps, their responsibilities, and which domain areas they own.
- Document the URL routing hierarchy: `urls.py` at project level and each app's `urls.py`.
- Django REST Framework: use `drf-spectacular` or `drf-yasg` for OpenAPI generation. Document spec location.
- Document the Celery task registry: task name, queue, retry policy, and what triggers it.
- Settings: document `BASE_DIR`-relative paths and environment variable overrides. Use `django-environ` or `python-decouple` and document required `.env` keys.

## Diagram Guidance

- **App dependency graph:** Mermaid class diagram showing Django app imports and service dependencies.
- **Request lifecycle:** Sequence diagram showing middleware, URL dispatch, view, serializer, and response.

## Dos

- `help_text` on all non-obvious model fields — it is both admin UI documentation and developer documentation
- Document signal receivers at the signal definition site — receivers in other files are invisible without it
- Keep `INSTALLED_APPS` ordered consistently and document any order-sensitive entries

## Don'ts

- Don't document Django's ORM query API — document your project's query patterns and manager methods
- Don't skip docstrings on custom model managers — `objects.active()` is not self-documenting
