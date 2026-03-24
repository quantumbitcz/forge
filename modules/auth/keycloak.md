# Keycloak — Best Practices

## Overview

Keycloak is an open-source Identity and Access Management (IAM) solution supporting OAuth2, OIDC,
SAML 2.0, and LDAP/AD federation. Use Keycloak when you need a self-hosted IdP with SSO, fine-
grained role management, user federation, and custom authentication flows. Keycloak is a production-
grade choice for enterprises that cannot use managed IdP services (Auth0, Okta) due to data
residency, cost, or compliance requirements. Invest in operational maturity — Keycloak requires
a database, clustering, and backup strategy to be production-ready.

## Architecture Patterns

### Realm Design
```
One realm per deployment environment (recommended for most teams):
├── realm: wellplanned-dev
├── realm: wellplanned-staging
└── realm: wellplanned-prod

One realm per tenant (multi-tenant SaaS — advanced):
├── realm: acme-corp          # Tenant A's isolated realm
├── realm: globex-inc         # Tenant B's isolated realm
└── realm: master             # Admin only — never for application auth
```
The `master` realm is for Keycloak administration only. All application authentication uses
dedicated realms. Never configure application clients in the master realm.

### Client Configuration
```json
// Confidential client (backend services with client secret)
{
  "clientId": "backend-api",
  "protocol": "openid-connect",
  "publicClient": false,
  "secret": "generated-in-keycloak-ui",
  "standardFlowEnabled": false,     // not a redirect-based client
  "serviceAccountsEnabled": true,   // enables client_credentials grant
  "directAccessGrantsEnabled": false
}

// Public client (SPA/mobile — PKCE required)
{
  "clientId": "web-frontend",
  "protocol": "openid-connect",
  "publicClient": true,
  "redirectUris": ["https://app.example.com/*", "http://localhost:3000/*"],
  "webOrigins": ["https://app.example.com", "http://localhost:3000"],
  "standardFlowEnabled": true,
  "pkceCodeChallengeMethod": "S256"
}
```

### Role Mapping — Realm vs Client Roles
```
Realm roles: cross-client roles (e.g., "admin", "support", "billing-manager")
Client roles: scoped to a specific client (e.g., "backend-api:reader", "backend-api:writer")

Composite roles: group multiple roles into a single assignable role
  └── "premium-user" composite role
        ├── realm role: "user"
        └── client role: "api:advanced-features"
```
Prefer client roles for application permissions — they scope the permission to a specific audience
and appear in the access token only when that client's audience is requested.

### Custom Token Claims via Mappers
```json
// Client scope mapper — add roles to the JWT
{
  "name": "roles-mapper",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-realm-role-mapper",
  "config": {
    "claim.name": "roles",
    "jsonType.label": "String",
    "multivalued": "true",
    "userinfo.token.claim": "false",
    "id.token.claim": "false",
    "access.token.claim": "true"
  }
}
```

### User Federation (LDAP/AD)
```json
{
  "providerId": "ldap",
  "providerType": "org.keycloak.storage.UserStorageProvider",
  "config": {
    "connectionUrl": ["ldap://ad.example.com:389"],
    "bindDn": ["CN=keycloak-bind,OU=Service Accounts,DC=example,DC=com"],
    "usersDn": ["OU=Users,DC=example,DC=com"],
    "usernameAttr": ["sAMAccountName"],
    "uuidLDAPAttribute": ["objectGUID"],
    "syncRegistrations": ["false"],
    "importEnabled": ["true"],
    "fullSyncPeriod": ["86400"]   // daily full sync
  }
}
```

### Admin REST API — Realm Export/Import
```bash
# Export realm configuration (excludes secrets — inject via env in CI)
curl -X GET "https://keycloak.example.com/admin/realms/wellplanned-prod" \
  -H "Authorization: Bearer $ADMIN_TOKEN" > realm-export.json

# Import realm on new environment
curl -X POST "https://keycloak.example.com/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d @realm-export.json
```
Store realm export in source control (without secrets). Inject client secrets via environment
variables during deployment. Automate realm configuration via Keycloak Terraform provider.

### Custom Themes
```
themes/
├── my-company/
│   ├── login/                   # login page, password reset, register
│   │   ├── theme.properties
│   │   ├── login.ftl
│   │   └── resources/css/
│   └── email/                   # email templates (verification, reset)
│       ├── theme.properties
│       └── email-verification.html
```
Mount custom themes as a volume or bake into a custom Keycloak Docker image.

## Configuration

```yaml
# docker-compose production-ready Keycloak
services:
  keycloak:
    image: quay.io/keycloak/keycloak:24.0
    command: start
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: ${KC_DB_PASSWORD}
      KC_HOSTNAME: auth.example.com
      KC_HTTPS_CERTIFICATE_FILE: /opt/keycloak/conf/tls.crt
      KC_HTTPS_CERTIFICATE_KEY_FILE: /opt/keycloak/conf/tls.key
      KC_PROXY: edge                  # behind reverse proxy (Traefik/nginx)
      KC_HEALTH_ENABLED: "true"
      KC_METRICS_ENABLED: "true"
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: ${KC_ADMIN_PASSWORD}
```

**Token TTL settings (per-realm):**
- Access token: 5–15 minutes
- Refresh token: 30 minutes idle, 8 hours max (SSO session)
- SSO session idle: 30 minutes; max: 10 hours

## Performance

- Enable Infinispan clustering for session replication when running multiple Keycloak nodes.
- Use `KC_CACHE=ispn` with a JDBC_PING discovery in Kubernetes for stateful session clustering.
- Enable `KC_DB_POOL_MAX_SIZE` tuning — Keycloak database connections are the primary bottleneck.
- Cache the OIDC discovery document and JWKS at the resource server level (1-hour TTL).

## Security

- Enforce HTTPS (`KC_HTTPS_*`) — never run Keycloak over HTTP in any shared environment.
- Use `KC_PROXY=edge` when behind a TLS-terminating reverse proxy.
- Enable brute force protection: Admin console → Realm Settings → Security Defenses.
- Rotate admin credentials and restrict admin console access to internal networks only.
- Disable unused grant types on every client (e.g., set `directAccessGrantsEnabled: false` for SPA clients).

## Testing

```bash
# Run Keycloak in dev mode for local/test environments
docker run -p 8080:8080 \
  -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin \
  quay.io/keycloak/keycloak:24.0 start-dev

# Import test realm with pre-configured clients and test users
docker exec keycloak /opt/keycloak/bin/kc.sh import --file /tmp/test-realm.json
```
For integration tests, use the `keycloak-testcontainers` library to spin up Keycloak programmatically
and create test users/tokens without a running server.

## Dos
- Use one realm per environment — never reuse realms across prod/staging.
- Store realm configuration as code (export JSON, Terraform provider) and deploy via CI/CD.
- Use composite roles to group permissions — simplifies user assignment and permission auditing.
- Enable health and metrics endpoints for monitoring — expose to internal network only.
- Use client scopes to share mapper configurations across multiple clients in the same realm.

## Don'ts
- Don't configure application clients in the master realm — it is for admin access only.
- Don't enable `directAccessGrantsEnabled` (Resource Owner Password Credentials) — it is deprecated and bypasses MFA.
- Don't store client secrets in realm exports committed to source control — inject via environment.
- Don't expose the Keycloak admin console on a public-facing interface in production.
- Don't run Keycloak without a proper database backup strategy — realm data loss is unrecoverable.
