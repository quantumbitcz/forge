# Django + safety

> Extends `modules/code-quality/safety.md` with Django-specific integration.
> Generic Safety conventions (policy file, CI integration, pip-audit) are NOT repeated here.

## Integration Setup

Scan both production and development requirements separately — Django projects typically split them:

```bash
# Scan production dependencies
safety scan -r requirements/production.txt

# Scan development dependencies
safety scan -r requirements/development.txt

# Or scan the full virtual environment after installation
safety scan
```

```yaml
# .github/workflows/security.yml
- name: Safety scan (production)
  env:
    SAFETY_API_KEY: ${{ secrets.SAFETY_API_KEY }}
  run: safety scan -r requirements/production.txt --exit-code

- name: Safety scan (development)
  env:
    SAFETY_API_KEY: ${{ secrets.SAFETY_API_KEY }}
  run: safety scan -r requirements/development.txt --exit-code
```

## Framework-Specific Patterns

### Django CVE Awareness

Critical vulnerability classes in the Django ecosystem to monitor:

| Package | Vulnerability Class | Notes |
|---|---|---|
| `Django` itself | SQL injection via ORM `RawSQL`, XSS via template autoescape bypass, CSRF token leaks | Core framework CVEs — patch immediately |
| `Pillow` | Arbitrary code execution via crafted image files | Common in Django projects with `ImageField` |
| `django-debug-toolbar` | Information disclosure when `INTERNAL_IPS` misconfigured | Keep in dev requirements only |
| `social-auth-app-django` | Account takeover via OAuth state parameter bypass | High-severity auth CVEs |
| `djangorestframework` | Authentication bypass, permission class misconfigurations | Monitor DRF security advisories |
| `whitenoise` | Path traversal (historical) | Used for static file serving |

### Policy File for Django Projects

```yaml
# .safety-policy.yml
version: "3.0"

security:
  ignore-cvss-severity-below: 0
  ignore-unpinned-requirements: false
  continue-on-vulnerability-error: false

ignore-vulnerabilities:
  # Example: known false positive in dev tooling only
  # - id: "12345"
  #   reason: "Only affects Python 2.x; project requires Python 3.11+"
  #   expires: "2025-06-30"
```

### Django Debug Toolbar

Ensure `django-debug-toolbar` is in `requirements/development.txt`, not `requirements/production.txt`. Run safety scans on each file separately so dev-only vulnerabilities do not block production deployments.

```toml
# pyproject.toml
[project.optional-dependencies]
dev = ["django-debug-toolbar>=4.0", "django-extensions>=3.2"]
prod = ["gunicorn>=21.0", "psycopg2-binary>=2.9"]
```

## Additional Dos

- Scan all requirements split files (`base.txt`, `production.txt`, `development.txt`) individually — CVEs in dev dependencies can be exploited in CI/CD pipelines.
- Monitor Django's security mailing list (`django-announce`) alongside Safety scans — official patches are released before CVE IDs are assigned.
- Pin Django to an LTS release and upgrade on the published security support schedule — intermediate releases receive no backported security fixes.

## Additional Don'ts

- Don't include `django-debug-toolbar` in production requirements — beyond CVE risk, it leaks SQL queries, cache keys, and template context to `INTERNAL_IPS` addresses.
- Don't suppress Django core CVEs in `.safety-policy.yml` without an immediate remediation plan and a tight expiry date — Django CVEs frequently affect authentication and SQL execution paths.
- Don't scan only the base requirements file — many Django projects extend it with environment-specific files that introduce additional dependencies.
