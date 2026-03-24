# Auth0 — Best Practices

## Overview

Auth0 is a managed Identity-as-a-Service (IDaaS) platform providing OAuth2, OIDC, SAML, and
social login out of the box. Use Auth0 when you need a production-ready IdP without operational
overhead (no database, no clustering, no key management). Auth0 excels at B2C authentication
(social login, progressive profiling), B2B with organization support, and M2M token issuance.
Choose Auth0 over a self-hosted solution when time-to-market and managed reliability outweigh
cost and vendor dependency concerns.

## Architecture Patterns

### Tenant Architecture
```
auth0-dev.auth0.com    → Development tenant (free or dev plan)
auth0-staging.auth0.com → Staging tenant (mirrored production config)
auth0-prod.auth0.com   → Production tenant (separate billing, no development access)
```
Never share tenants across environments. Production and staging must be completely isolated —
a misconfiguration in staging must not affect production. Each tenant has its own:
application clients, connections, user database, rate limits, and custom domains.

### Universal Login (Recommended)
```javascript
// Auth0 SPA SDK — redirects to Auth0's hosted Universal Login page
import { createAuth0Client } from "@auth0/auth0-spa-js";

const auth0 = await createAuth0Client({
  domain: "your-tenant.auth0.com",
  clientId: "YOUR_CLIENT_ID",
  authorizationParams: {
    redirect_uri: window.location.origin,
    audience: "https://api.yourdomain.com",
    scope: "openid profile email offline_access"
  }
});

await auth0.loginWithRedirect();   // Universal Login — hosted by Auth0
```
Universal Login handles MFA, social connections, and password policies without embedding auth UI
in your application. Embedded login (lock.js) bypasses SSO and is not recommended for new projects.

### Actions (Replaces Rules — Migrate Rules to Actions)
```javascript
// Auth0 Action — Post-Login trigger: enrich ID token with app metadata
exports.onExecutePostLogin = async (event, api) => {
  const userId = event.user.user_id;

  // Enrich token with role from external API
  const response = await fetch(`${event.secrets.APP_API}/users/${userId}/roles`);
  const { roles } = await response.json();

  api.idToken.setCustomClaim("https://yourdomain.com/roles", roles);
  api.accessToken.setCustomClaim("https://yourdomain.com/roles", roles);
};
```
Rules are deprecated — migrate all Rules to Actions. Actions support versioning, testing in the
Auth0 dashboard, and a cleaner async/await API. Custom claim names must be namespaced with a URL
to avoid conflicts with standard OIDC claims.

### Organization Support (B2B)
```javascript
// Organizations: each B2B customer gets an Auth0 Organization
const auth0 = await createAuth0Client({
  domain: "your-tenant.auth0.com",
  clientId: "CLIENT_ID",
  authorizationParams: {
    organization: "org_abc123",    // specific org — or prompt for org selection
    redirect_uri: window.location.origin
  }
});

// Organization ID is available in the token
// event.organization.id in Actions
// org_id claim in the JWT
```
Organizations support custom branding per tenant, per-org MFA policies, and member roles.
Use organizations for B2B SaaS where each customer manages their own users.

### M2M Tokens (Client Credentials)
```python
import httpx

def get_m2m_token(client_id: str, client_secret: str, audience: str) -> str:
    response = httpx.post(
        f"https://{AUTH0_DOMAIN}/oauth/token",
        json={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "audience": audience
        }
    )
    return response.json()["access_token"]

# Cache the token until exp - 60 seconds; then re-fetch
# Do NOT re-fetch on every request — M2M tokens are rate-limited
```
Auth0 M2M tokens have a default TTL of 24 hours. Cache them in memory; rotate before expiry.
Each M2M token request consumes from the tenant's token endpoint rate limit.

### Custom Database Connections
```javascript
// Login script — authenticate against your own DB during migration
module.exports = async function login(email, password, callback) {
  const user = await db.findUserByEmail(email);
  if (!user) return callback(new WrongUsernameOrPasswordError(email));
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) return callback(new WrongUsernameOrPasswordError(email));
  callback(null, {
    user_id: user.id,
    email: user.email,
    email_verified: user.email_verified
  });
};
```
Custom DB connections enable gradual migration — Auth0 calls your DB on login, and you can
optionally migrate users to the Auth0 user store after first successful login.

### Rate Limits
Auth0 rate limits by plan and endpoint. Key limits (Production plan):
```
/oauth/token:              300 requests/minute per IP
/userinfo:                 300 requests/minute per user
Management API:            2 req/second burst, 1000/minute
Auth0 Actions (external):  triggered per login — watch cold start latency
```
Cache Management API responses. Never call `/userinfo` on every API request — validate the JWT
locally. Cache M2M tokens; do not re-fetch per-request.

## Configuration

```json
// Auth0 Application settings (SPA)
{
  "app_type": "spa",
  "token_endpoint_auth_method": "none",   // public client
  "grant_types": ["authorization_code", "refresh_token"],
  "allowed_callback_urls": ["https://app.example.com/callback"],
  "allowed_logout_urls": ["https://app.example.com"],
  "allowed_web_origins": ["https://app.example.com"],
  "refresh_token": {
    "rotation_type": "rotating",           // single-use refresh tokens
    "expiration_type": "expiring",
    "token_lifetime": 2592000,             // 30 days
    "idle_token_lifetime": 1296000         // 15 days idle
  }
}
```

## Performance

- Validate JWTs locally using the JWKS endpoint — never call `/userinfo` on every API request.
- Cache JWKS response (1-hour TTL) at the resource server.
- Cache M2M tokens in memory; implement proactive refresh at 80% of their lifetime.
- Actions run synchronously during login — keep them fast (< 2 s); use async background jobs for slow operations.

## Security

- Enable MFA (Guardian push or TOTP) at minimum for admin roles.
- Restrict Management API tokens — only grant the permissions needed for each service.
- Enable Attack Protection: brute force, credential stuffing, breached password detection.
- Use rotating refresh tokens — single-use rotation detects theft.
- Never expose the Management API client secret in frontend code — always call from backend.

## Testing

```javascript
// Use Auth0 Management API to create test users programmatically
const ManagementClient = require("auth0").ManagementClient;
const management = new ManagementClient({
  domain: process.env.AUTH0_TEST_DOMAIN,
  clientId: process.env.AUTH0_M2M_CLIENT_ID,
  clientSecret: process.env.AUTH0_M2M_CLIENT_SECRET
});

async function createTestUser(email) {
  const user = await management.users.create({
    email, password: "TestPass1!", connection: "Username-Password-Authentication"
  });
  // Use Resource Owner Password (test tenant only) or Auth0 test tokens for integration tests
  return user;
}
```

## Dos
- Use Universal Login — it centralizes auth UI, supports SSO, and requires no embedded auth code.
- Migrate all Rules to Actions — Rules are deprecated and will be removed.
- Use Organizations for B2B tenants — they provide isolated user pools and per-org branding.
- Cache M2M tokens — re-fetching per-request consumes rate limit quota rapidly.
- Use rotating refresh tokens with idle expiry for long-lived browser sessions.

## Don'ts
- Don't use the Management API from frontend clients — it exposes admin credentials.
- Don't call `/userinfo` on every API request — validate JWTs locally from JWKS.
- Don't share a production tenant with staging — any misconfiguration (deleted connection, wrong redirect URI) is live.
- Don't use embedded login (Lock.js) for new projects — Universal Login supports SSO; embedded login does not.
- Don't create Actions that make slow external API calls synchronously during login — defer to background jobs.
