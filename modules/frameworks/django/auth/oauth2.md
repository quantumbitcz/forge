# Django + OAuth2 / JWT

> Django-specific patterns for OAuth2 / JWT auth via djangorestframework-simplejwt and mozilla-django-oidc. Extends generic Django conventions.

## Integration Setup

```bash
# JWT for DRF APIs
pip install djangorestframework-simplejwt

# OIDC social auth (Keycloak, Entra ID, etc.)
pip install mozilla-django-oidc
```

```python
# settings.py — simplejwt
INSTALLED_APPS += ["rest_framework_simplejwt"]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
}

from datetime import timedelta
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME":  timedelta(minutes=15),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=1),
    "ROTATE_REFRESH_TOKENS":  True,
    "BLACKLIST_AFTER_ROTATION": True,
    "ALGORITHM": "RS256",
    "SIGNING_KEY":   env("JWT_PRIVATE_KEY"),
    "VERIFYING_KEY": env("JWT_PUBLIC_KEY"),
    "AUTH_HEADER_TYPES": ("Bearer",),
}
```

```python
# settings.py — mozilla-django-oidc
AUTHENTICATION_BACKENDS = [
    "myapp.auth.OIDCBackend",
    "django.contrib.auth.backends.ModelBackend",
]
OIDC_RP_CLIENT_ID     = env("OIDC_CLIENT_ID")
OIDC_RP_CLIENT_SECRET = env("OIDC_CLIENT_SECRET")
OIDC_OP_AUTHORIZATION_ENDPOINT = env("OIDC_AUTH_URL")
OIDC_OP_TOKEN_ENDPOINT         = env("OIDC_TOKEN_URL")
OIDC_OP_JWKS_ENDPOINT          = env("OIDC_JWKS_URL")
OIDC_RP_SIGN_ALGO = "RS256"
```

## Framework-Specific Patterns

### JWT token endpoints (simplejwt)

```python
# urls.py
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView, TokenVerifyView

urlpatterns = [
    path("api/auth/token/",         TokenObtainPairView.as_view()),
    path("api/auth/token/refresh/", TokenRefreshView.as_view()),
    path("api/auth/token/verify/",  TokenVerifyView.as_view()),
]
```

### Custom token claims

```python
# auth/tokens.py
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

class CustomTokenSerializer(TokenObtainPairSerializer):
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token["email"] = user.email
        token["roles"] = list(user.groups.values_list("name", flat=True))
        return token
```

### Permission classes

```python
from rest_framework.permissions import BasePermission

class IsAdmin(BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user and
            request.user.is_authenticated and
            request.user.groups.filter(name="admin").exists()
        )

# ViewSet usage
class OrderViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]

    def destroy(self, request, *args, **kwargs):
        self.permission_classes = [IsAdmin]
        self.check_permissions(request)
        return super().destroy(request, *args, **kwargs)
```

### OIDC backend (mozilla-django-oidc)

```python
# auth/oidc.py
from mozilla_django_oidc.auth import OIDCAuthenticationBackend

class OIDCBackend(OIDCAuthenticationBackend):
    def create_user(self, claims):
        user = super().create_user(claims)
        user.email = claims.get("email", "")
        user.first_name = claims.get("given_name", "")
        user.save()
        return user

    def update_user(self, user, claims):
        user.email = claims.get("email", user.email)
        user.save()
        return user
```

## Scaffolder Patterns

```
config/
  settings/
    base.py               # SIMPLE_JWT + OIDC settings
auth/
  tokens.py               # CustomTokenSerializer
  oidc.py                 # OIDCAuthenticationBackend subclass
  permissions.py          # custom DRF permission classes
urls.py                   # token endpoints
```

## Dos

- Use `RS256` with separate signing/verifying keys — `HS256` with a shared secret is not suitable for public APIs
- Rotate refresh tokens (`ROTATE_REFRESH_TOKENS = True`) and blacklist after rotation to prevent replay
- Keep `ACCESS_TOKEN_LIFETIME` short (10-15 min) and rely on refresh tokens for session extension
- Use `mozilla-django-oidc` for SSO / social login — it handles JWKS rotation and token validation correctly

## Don'ts

- Don't store JWT tokens in Django's session — JWTs are stateless; use `Authorization: Bearer` header
- Don't add sensitive data to token claims — tokens are base64-encoded, not encrypted
- Don't skip `BLACKLIST_AFTER_ROTATION` — without it, old refresh tokens remain valid after rotation
- Don't use `SessionAuthentication` alongside `JWTAuthentication` for the same API — pick one scheme per surface
