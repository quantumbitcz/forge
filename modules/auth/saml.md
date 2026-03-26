# SAML 2.0 — Best Practices

## Overview

SAML (Security Assertion Markup Language) 2.0 is an XML-based protocol for exchanging
authentication and authorization data between an Identity Provider (IdP) and a Service
Provider (SP). Use SAML for enterprise SSO integrations where customers require it (Okta,
Azure AD, ADFS, OneLogin, PingFederate). SAML is the dominant protocol in enterprise B2B
SaaS onboarding. Avoid implementing SAML from scratch — use a library or service. Consider
OIDC (OpenID Connect) for new greenfield applications where all parties support it.

## Architecture Patterns

### SP-Initiated SSO Flow (Most Common)
```
1. User visits SP (your app) → not authenticated
2. SP generates AuthnRequest → redirects to IdP login page
3. User authenticates at IdP (Okta, Azure AD, etc.)
4. IdP generates SAML Response (assertion) → POSTs to SP's ACS URL
5. SP validates assertion signature, extracts user attributes
6. SP creates session → user is logged in
```

### Service Provider Configuration (Node.js — passport-saml)
```javascript
import { Strategy as SamlStrategy } from "@node-saml/passport-saml";

passport.use(new SamlStrategy({
    entryPoint: "https://idp.example.com/sso/saml",
    issuer: "https://myapp.com",
    callbackUrl: "https://myapp.com/auth/saml/callback",
    cert: IDP_CERTIFICATE,   // IdP's signing certificate (public)
    privateKey: SP_PRIVATE_KEY,
    decryptionPvk: SP_DECRYPTION_KEY,
    signatureAlgorithm: "sha256",
    wantAssertionsSigned: true,
    wantAuthnResponseSigned: true
  },
  async (profile, done) => {
    const user = await userRepository.findOrCreateBySaml({
      nameId: profile.nameID,
      email: profile.email || profile["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"],
      firstName: profile.firstName,
      lastName: profile.lastName,
      orgId: deriveTenantFromIssuer(profile.issuer)
    });
    done(null, user);
  }
));
```

### Spring Security SAML (Java/Kotlin)
```yaml
# application.yml
spring:
  security:
    saml2:
      relyingparty:
        registration:
          okta:
            assertingparty:
              metadata-uri: https://idp.example.com/metadata.xml
            signing:
              credentials:
                - private-key-location: classpath:sp-key.pem
                  certificate-location: classpath:sp-cert.pem
```

### Metadata Exchange
```xml
<!-- SP Metadata — serve at /auth/saml/metadata -->
<EntityDescriptor entityID="https://myapp.com" xmlns="urn:oasis:names:tc:SAML:2.0:metadata">
  <SPSSODescriptor AuthnRequestsSigned="true" WantAssertionsSigned="true"
    protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <AssertionConsumerService
      Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
      Location="https://myapp.com/auth/saml/callback" index="0"/>
    <SingleLogoutService
      Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
      Location="https://myapp.com/auth/saml/logout"/>
  </SPSSODescriptor>
</EntityDescriptor>
```

### Anti-pattern — parsing SAML XML manually: SAML responses are signed XML with complex canonicalization rules. Hand-parsing XML or using generic XML libraries without proper signature verification leads to authentication bypass vulnerabilities. Always use a battle-tested SAML library.

## Configuration

**Per-tenant IdP configuration (multi-tenant SaaS):**
```javascript
// Store IdP config per tenant in database
const tenantConfig = await getTenantSamlConfig(tenantId);
// Dynamically construct SAML strategy per tenant
const strategy = new SamlStrategy({
  entryPoint: tenantConfig.ssoUrl,
  cert: tenantConfig.idpCertificate,
  issuer: `https://myapp.com/tenants/${tenantId}`,
  callbackUrl: `https://myapp.com/auth/saml/${tenantId}/callback`
}, verifyCallback);
```

**Required IdP information (collected during customer onboarding):**
- IdP SSO URL (entryPoint)
- IdP certificate (X.509, for signature verification)
- IdP entity ID (issuer)
- Attribute mapping (email, name, groups — IdP-specific claim names)

**SP information to provide to IdP:**
- SP entity ID (issuer)
- ACS URL (Assertion Consumer Service — your callback URL)
- SP metadata URL (if supported)
- SP signing certificate (if AuthnRequests are signed)

## Performance

**Cache IdP metadata:** Parse IdP metadata XML once and cache the parsed config. Re-fetch periodically (daily) or on certificate rotation events.

**Avoid re-parsing SAML assertions:** After validation, extract claims once and store them in the session or JWT — don't re-validate the SAML response on subsequent requests.

**SP-initiated vs IdP-initiated:** SP-initiated SSO is more secure (includes relay state and request ID correlation). IdP-initiated SSO skips the AuthnRequest, making it vulnerable to replay attacks. Support IdP-initiated only if customers require it, with additional replay protection.

## Security

**Always verify the assertion signature** against the IdP's known public certificate. Never skip signature verification, even in development.

**Validate the audience restriction:**
```javascript
// Assertion must be intended for your SP
if (assertion.audience !== "https://myapp.com") throw new Error("Audience mismatch");
```

**Check assertion validity period:**
```javascript
// Reject expired or not-yet-valid assertions
const now = new Date();
if (now < assertion.notBefore || now > assertion.notOnOrAfter) {
  throw new Error("Assertion expired or not yet valid");
}
```

**Prevent XML Signature Wrapping attacks:** Use a SAML library that validates the signature covers the entire assertion, not just a portion. This is the most common SAML vulnerability.

**Use HTTPS for all SAML endpoints** — ACS URL, metadata URL, and SSO URL must all use TLS.

**Implement replay protection:** Track assertion IDs and reject duplicates within the validity window.

## Testing

**Use a test IdP (e.g., samling, MockSAML, or saml-idp npm package):**
```bash
npx saml-idp --port 7000 --cert idp-cert.pem --key idp-key.pem \
  --acsUrl https://localhost:3000/auth/saml/callback
```

**Test attribute mapping variations:** Different IdPs send attributes with different claim names (e.g., `email` vs `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress`). Test with multiple IdP simulators.

**Test clock skew tolerance:** Assertions with `NotBefore`/`NotOnOrAfter` should allow a small clock skew window (typically 2-5 minutes).

**Test certificate rotation:** Simulate an IdP rotating their signing certificate — your SP should handle the new certificate after configuration update without downtime.

## Dos
- Use a battle-tested SAML library (passport-saml, Spring Security SAML, python3-saml) — never parse XML yourself.
- Serve SP metadata at a well-known URL — IdPs use it for automated configuration.
- Validate assertion signature, audience, expiry, and replay on every login.
- Support multi-tenant IdP configuration — enterprise customers each bring their own IdP.
- Log SAML errors with detail (but not the full assertion, which contains PII) for debugging.
- Allow clock skew tolerance (2-5 minutes) for `NotBefore`/`NotOnOrAfter` validation.
- Plan for IdP certificate rotation — support multiple concurrent certificates during rollover.

## Don'ts
- Don't parse SAML XML manually or with generic XML libraries — XML Signature Wrapping attacks are the #1 SAML vulnerability.
- Don't skip signature verification, even in development or staging.
- Don't support IdP-initiated SSO without additional replay protection (assertion ID tracking).
- Don't log full SAML assertions — they contain PII (email, name, group memberships).
- Don't hardcode IdP certificates — store them in a database or secrets manager for rotation support.
- Don't assume all IdPs send the same attribute names — build flexible attribute mapping per tenant.
- Don't use HTTP (non-TLS) for any SAML endpoint — assertion POST data is sensitive.
