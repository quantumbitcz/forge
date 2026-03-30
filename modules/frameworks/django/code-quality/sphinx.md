# Django + sphinx

> Extends `modules/code-quality/sphinx.md` with Django-specific integration.
> Generic Sphinx conventions (conf.py setup, CI integration, ReadTheDocs) are NOT repeated here.

## Integration Setup

Django must be configured before autodoc can import models, views, and serializers:

```python
# docs/conf.py
import django
from django.conf import settings

if not settings.configured:
    settings.configure(
        INSTALLED_APPS=[
            "django.contrib.contenttypes",
            "django.contrib.auth",
            "myapp",
        ],
        DATABASES={"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}},
        DEFAULT_AUTO_FIELD="django.db.models.BigAutoField",
    )
    django.setup()

extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.napoleon",
    "sphinx.ext.viewcode",
    "sphinx.ext.intersphinx",
    "sphinx_autodoc_typehints",
]

autodoc_mock_imports = ["celery", "redis", "boto3"]  # heavy deps not needed for docs

intersphinx_mapping = {
    "python": ("https://docs.python.org/3", None),
    "django": ("https://docs.djangoproject.com/en/stable/_objects/", None),
}
```

## Framework-Specific Patterns

### Django Model Documentation

Document models with class-level docstrings and field-level help_text for admin display:

```python
class Article(models.Model):
    """Published content item authored by a staff member.

    Supports draft/published workflow via the ``status`` field.
    All articles are slug-routed under ``/articles/<slug>/``.
    """

    title = models.CharField(
        max_length=200,
        help_text="Display title shown in listings and page heading.",
    )
    status = models.CharField(
        max_length=10,
        choices=[("draft", "Draft"), ("published", "Published")],
        help_text="Only published articles are visible to anonymous users.",
    )
```

`help_text` values appear in the Django admin and in autodoc output when `sphinx-django` or `sphinxcontrib-django` is installed.

### Settings Reference Page

Generate a settings reference page using `autodata` directives for project-specific settings:

```rst
.. docs/reference/settings.rst
Project Settings
================

.. autodata:: myproject.settings.base.FEATURE_FLAGS
   :annotation:

.. autodata:: myproject.settings.base.API_RATE_LIMIT
   :annotation:
```

### Admin Documentation

Django's built-in `django.contrib.admindocs` generates admin UI docs at `/admin/doc/`. Enable it alongside Sphinx for a two-tier documentation approach — Sphinx for developer docs, admindocs for ops/admin users.

```python
# myproject/urls.py
urlpatterns = [
    path("admin/doc/", include("django.contrib.admindocs.urls")),
    path("admin/", admin.site.urls),
]
```

## Additional Dos

- Call `django.setup()` in `conf.py` before any autodoc imports — Django models cannot be imported without a configured settings module.
- Add `autodoc_mock_imports` for Celery, Redis, and database drivers — they are not available in the Sphinx build environment.
- Use `intersphinx` with the official Django objects inventory to cross-link to Django's own documentation.

## Additional Don'ts

- Don't run Sphinx with `DJANGO_SETTINGS_MODULE` pointing to production settings in CI — it may connect to real databases or trigger service discovery.
- Don't document migration files with autodoc — exclude `*/migrations/` from autodoc `source` to avoid cluttering the API reference with auto-generated classes.
- Don't expose model field `help_text` that contains internal implementation details — `help_text` appears verbatim in admindocs and Sphinx output.
